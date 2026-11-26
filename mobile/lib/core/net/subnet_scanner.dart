import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models.dart';
import '../native_bridge.dart';
import '../util/format.dart';

/// LAN discovery built on the Android `ping` binary.
///
/// The stream is intentionally failure-tolerant: per-host timeouts are normal
/// results, `/proc/net/arp` is best-effort, and no exception escapes [scan].
class SubnetScanner {
  static const String _primaryPing = '/system/bin/ping';

  static final RegExp _rttPattern = RegExp(
    r'time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms',
  );

  /// Detects the local IPv4 subnet from the Android connection info.
  ///
  /// Returns null when no usable IPv4 address is available.
  static Future<SubnetInfo?> detectLocalSubnet() async {
    try {
      final connection = await NativeBridge.connectionInfo().timeout(
        const Duration(seconds: 2),
        onTimeout: () => const ConnectionInfo(connectionType: 'Unknown'),
      );
      final localIp = connection.localIpv4?.trim();
      if (localIp == null ||
          !isValidIpv4(localIp) ||
          localIp.startsWith('127.')) {
        return null;
      }
      final address = ipv4ToInt(localIp);
      if (address == null) return null;

      var prefix = connection.prefixLength ?? 24;
      if (prefix < 8 || prefix > 30) prefix = 24;

      final mask = prefixMask(prefix);
      final network = address & mask;

      var gateway = connection.gateway?.trim();
      if (gateway != null) {
        final gatewayValue = ipv4ToInt(gateway);
        if (gatewayValue == null ||
            gatewayValue == address ||
            gateway == '0.0.0.0') {
          gateway = null;
        }
      }

      return SubnetInfo(
        cidr: '${intToIpv4(network)}/$prefix',
        localIp: localIp,
        prefixLength: prefix,
        gateway: gateway,
        totalHosts: (1 << (32 - prefix)) - 2,
      );
    } catch (_) {
      return null;
    }
  }

  /// Scans a CIDR block or IP range, emitting progress and a final result.
  ///
  /// Cancelling the subscription kills active ping processes and sockets.
  static Stream<SubnetScanEvent> scan(SubnetConfig config) {
    final session = _ScanSession();
    var canceled = false;
    late final StreamController<SubnetScanEvent> controller;
    controller = StreamController<SubnetScanEvent>(
      onListen: () {
        unawaited(
          _runScan(config, controller, session, () => canceled).whenComplete(
            () {
              if (!controller.isClosed) {
                unawaited(controller.close());
              }
            },
          ),
        );
      },
      onCancel: () {
        canceled = true;
        session.killAll();
      },
    );
    return controller.stream;
  }

  static Future<void> _runScan(
    SubnetConfig config,
    StreamController<SubnetScanEvent> controller,
    _ScanSession session,
    bool Function() isCanceled,
  ) async {
    final stopwatch = Stopwatch()..start();

    void emit(SubnetScanEvent event) {
      if (isCanceled() || controller.isClosed) return;
      controller.add(event);
    }

    try {
      final parsed = parseSubnetInput(config.cidr);
      if (parsed == null) {
        emit(
          const SubnetScanFailed(
            'Invalid subnet — enter a CIDR block (for example 192.168.1.0/24) '
            'or an IP range.',
          ),
        );
        return;
      }
      if (parsed.totalHosts > 4096) {
        emit(
          const SubnetScanFailed(
            'Subnet is too large — the maximum is 4096 addresses.',
          ),
        );
        return;
      }
      final targets = hostsFor(parsed);
      if (targets.isEmpty) {
        emit(
          const SubnetScanFailed(
            'The subnet does not contain any usable host addresses.',
          ),
        );
        return;
      }

      // Attach the detected gateway when it belongs to the scanned range.
      var info = parsed;
      try {
        final local = await detectLocalSubnet();
        if (isCanceled()) return;
        final localGateway = local?.gateway;
        if (localGateway != null) {
          final gatewayValue = ipv4ToInt(localGateway);
          final range = subnetRange(parsed);
          if (gatewayValue != null &&
              gatewayValue > range.network &&
              gatewayValue < range.broadcast) {
            info = parsed.copyWith(gateway: localGateway);
          }
        }
      } catch (_) {
        // Gateway detection is optional.
      }

      emit(SubnetScanStarted(info));

      final total = targets.length;
      final concurrency = _clampInt(config.concurrency, 1, 128);
      final timeoutMs = _clampInt(config.timeoutMs, 100, 10000);
      final gatewayValue = info.gateway == null
          ? null
          : ipv4ToInt(info.gateway!);
      final found = <String, LanHost>{};
      var scanned = 0;
      var launchFailures = 0;

      for (var offset = 0; offset < total; offset += concurrency) {
        if (isCanceled()) return;
        final end = math.min(offset + concurrency, total);
        final batch = targets.sublist(offset, end);
        final probes = await Future.wait(
          batch.map((ip) => _probeHost(ip, timeoutMs, session)),
        );
        if (isCanceled()) return;

        for (var i = 0; i < batch.length; i++) {
          final probe = probes[i];
          if (probe.launchFailed) launchFailures++;
          if (!probe.reachable) continue;
          final ip = batch[i];
          found[ip] = LanHost(
            ip: ip,
            rttMs: probe.rttMs,
            isGateway: gatewayValue != null && ipv4ToInt(ip) == gatewayValue,
          );
        }

        scanned += batch.length;
        await _mergeArp(found);
        if (isCanceled()) return;
        emit(
          SubnetScanProgress(
            scanned: scanned,
            total: total,
            found: _sortedHosts(found),
          ),
        );
      }

      if (launchFailures >= total && found.isEmpty) {
        emit(
          const SubnetScanFailed(
            'Unable to run ping on this device, so the subnet could not be scanned.',
          ),
        );
        return;
      }

      if (config.includePortProbe &&
          config.probePorts.isNotEmpty &&
          found.isNotEmpty) {
        final ports =
            config.probePorts
                .where((port) => port > 0 && port <= 65535)
                .toSet()
                .toList()
              ..sort();
        if (ports.isNotEmpty) {
          const portProbeHosts = 12;
          final hosts = _sortedHosts(found);
          for (
            var offset = 0;
            offset < hosts.length;
            offset += portProbeHosts
          ) {
            if (isCanceled()) return;
            final end = math.min(offset + portProbeHosts, hosts.length);
            final batch = hosts.sublist(offset, end);
            final results = await Future.wait(
              batch.map((host) => _probePorts(host.ip, ports, session)),
            );
            if (isCanceled()) return;
            for (var i = 0; i < batch.length; i++) {
              if (results[i].isEmpty) continue;
              found[batch[i].ip] = batch[i].copyWith(openPorts: results[i]);
            }
            emit(
              SubnetScanProgress(
                scanned: total,
                total: total,
                found: _sortedHosts(found),
              ),
            );
          }
        }
      }

      await _mergeArp(found);
      if (isCanceled()) return;
      emit(
        SubnetScanFinished(_sortedHosts(found), stopwatch.elapsedMilliseconds),
      );
    } catch (error) {
      if (!isCanceled()) {
        emit(SubnetScanFailed(_friendlyError(error)));
      }
    }
  }

  static Future<_ProbeResult> _probeHost(
    String ip,
    int timeoutMs,
    _ScanSession session,
  ) async {
    final seconds = _clampInt((timeoutMs / 1000).ceil(), 1, 30);
    final args = <String>['-c', '1', '-W', '$seconds', ip];
    final stopwatch = Stopwatch()..start();

    Process process;
    try {
      process = await Process.start(_primaryPing, args);
    } on ProcessException {
      try {
        process = await Process.start('ping', args);
      } catch (_) {
        return const _ProbeResult.launchFailure();
      }
    } catch (_) {
      return const _ProbeResult.launchFailure();
    }

    session.processes.add(process);
    try {
      final outputFuture = Future.wait<String>([
        process.stdout.transform(utf8.decoder).join(),
        process.stderr.transform(utf8.decoder).join(),
      ]).then<String>((parts) => parts.join('\n'), onError: (Object _) => '');

      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(
          Duration(milliseconds: timeoutMs + 1500),
        );
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(milliseconds: 300));
        } catch (_) {
          // The process is already gone or being torn down.
        }
        return const _ProbeResult.timeout();
      }

      var output = '';
      try {
        output = await outputFuture.timeout(const Duration(milliseconds: 500));
      } catch (_) {
        output = '';
      }
      if (exitCode != 0) return const _ProbeResult.timeout();

      return _ProbeResult(
        reachable: true,
        rttMs: _parseRtt(output) ?? stopwatch.elapsedMicroseconds / 1000.0,
      );
    } catch (_) {
      return const _ProbeResult.timeout();
    } finally {
      session.processes.remove(process);
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // Already exited.
      }
    }
  }

  static double? _parseRtt(String output) {
    final match = _rttPattern.firstMatch(output);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    return match.group(0)!.contains('<') ? 1.0 : value;
  }

  /// Reads `/proc/net/arp` and fills MACs for hosts that already replied.
  ///
  /// Newer Android versions hide this file; every failure is ignored.
  static Future<void> _mergeArp(Map<String, LanHost> found) async {
    if (found.isEmpty) return;
    try {
      final text = await File('/proc/net/arp')
          .readAsString()
          .timeout(const Duration(seconds: 1));
      final lines = const LineSplitter().convert(text);
      for (var i = 1; i < lines.length; i++) {
        final parts = lines[i].trim().split(RegExp(r'\s+'));
        if (parts.length < 4) continue;
        final ip = parts[0];
        final host = found[ip];
        if (host == null || host.mac != null) continue;

        final flags = int.tryParse(
          parts[2].replaceFirst(RegExp(r'^0[xX]'), ''),
          radix: 16,
        );
        if (flags == null || flags == 0) continue;

        final mac = normalizeMac(parts[3]);
        if (mac == null || mac == '00:00:00:00:00:00') continue;
        found[ip] = host.copyWith(mac: mac);
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  static Future<List<int>> _probePorts(
    String ip,
    List<int> ports,
    _ScanSession session,
  ) async {
    final open = <int>[];
    await Future.wait(
      ports.map((port) async {
        Socket? socket;
        try {
          socket = await Socket.connect(
            ip,
            port,
            timeout: const Duration(milliseconds: 400),
          );
          session.sockets.add(socket);
          open.add(port);
        } catch (_) {
          // Closed or filtered; normal for a LAN probe.
        } finally {
          if (socket != null) {
            session.sockets.remove(socket);
            try {
              socket.destroy();
            } catch (_) {
              // Ignore teardown races.
            }
          }
        }
      }),
    );
    open.sort();
    return open;
  }

  static List<LanHost> _sortedHosts(Map<String, LanHost> found) {
    final hosts = found.values.toList()
      ..sort((a, b) {
        final left = ipv4ToInt(a.ip) ?? 0;
        final right = ipv4ToInt(b.ip) ?? 0;
        return left.compareTo(right);
      });
    return List<LanHost>.unmodifiable(hosts);
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.isEmpty ? 'Subnet scan failed.' : text;
  }
}

class _ScanSession {
  final Set<Process> processes = <Process>{};
  final Set<Socket> sockets = <Socket>{};

  void killAll() {
    for (final process in processes) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // Already exited.
      }
    }
    processes.clear();

    for (final socket in sockets) {
      try {
        socket.destroy();
      } catch (_) {
        // Already closed.
      }
    }
    sockets.clear();
  }
}

class _ProbeResult {
  final bool reachable;
  final double? rttMs;
  final bool launchFailed;

  const _ProbeResult({required this.reachable, this.rttMs})
    : launchFailed = false;

  const _ProbeResult.timeout()
    : reachable = false,
      rttMs = null,
      launchFailed = false;

  const _ProbeResult.launchFailure()
    : reachable = false,
      rttMs = null,
      launchFailed = true;
}
