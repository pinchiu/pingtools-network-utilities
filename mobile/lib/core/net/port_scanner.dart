import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/util/format.dart';

/// Batched TCP connect port scanner with light banner grabbing.
///
/// OPEN on a completed connect, CLOSED for a refused connection (RST), and
/// FILTERED for timeouts or any other error. Cancelling the subscription closes
/// every socket still tracked by the scan.
class PortScanner {
  static const int _maxConcurrency = 128;
  static const int _bannerReadCapMs = 600;
  static const int _bannerByteCap = 512;
  static const int _bannerLineCap = 160;
  static const int _httpFlushCapMs = 250;
  static const Set<int> _tlsPorts = <int>{443, 8443};
  static const Set<int> _httpPorts = <int>{80, 8080};

  static Stream<PortScanEvent> scan(PortScanConfig config) async* {
    final activeSockets = <Socket>{};

    try {
      final host = normalizeHost(config.host);
      if (host.isEmpty) {
        yield const PortScanFailed('Enter a host to scan.');
        return;
      }

      final address = await _resolve(host);
      if (address == null) {
        yield PortScanFailed('Could not resolve "$host".');
        return;
      }
      final ip = address.address;

      final ports =
          config.ports
              .where((port) => port >= 1 && port <= 65535)
              .toSet()
              .toList()
            ..sort();
      if (ports.isEmpty) {
        yield const PortScanFailed('No ports to scan.');
        return;
      }

      final concurrency = _clampInt(config.concurrency, 1, _maxConcurrency);
      final timeoutMs = _clampInt(config.timeoutMs, 100, 60000);
      final stopwatch = Stopwatch()..start();

      yield PortScanStarted(host: host, resolvedIp: ip, total: ports.length);

      final results = <int, PortResult>{};
      final open = <PortResult>[];
      var scanned = 0;

      for (var offset = 0; offset < ports.length; offset += concurrency) {
        final end = math.min(offset + concurrency, ports.length);
        final batch = ports.sublist(offset, end);
        final batchResults = await Future.wait(
          batch.map(
            (port) => _scanPort(
              ip: ip,
              host: host,
              port: port,
              timeoutMs: timeoutMs,
              grabBanners: config.grabBanners,
              activeSockets: activeSockets,
            ),
          ),
        );

        for (final result in batchResults) {
          results[result.port] = result;
          if (result.state == PortState.open) open.add(result);
        }
        scanned += batch.length;
        open.sort((a, b) => a.port.compareTo(b.port));

        yield PortScanProgressEvent(
          PortScanProgress(
            scanned: scanned,
            total: ports.length,
            open: List<PortResult>.unmodifiable(open),
          ),
        );
      }

      final sorted = results.values.toList()
        ..sort((a, b) => a.port.compareTo(b.port));
      yield PortScanFinished(
        List<PortResult>.unmodifiable(sorted),
        stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      yield PortScanFailed(_friendlyError(error));
    } finally {
      for (final socket in activeSockets) {
        try {
          socket.destroy();
        } catch (_) {
          // Already closed.
        }
      }
      activeSockets.clear();
    }
  }

  /// Collapses arbitrary banner bytes into a single printable line.
  ///
  /// Control characters and ANSI escapes are removed, whitespace is collapsed,
  /// and the result is capped at 160 characters. Returns null when nothing
  /// printable remains.
  @visibleForTesting
  static String? sanitizeBanner(String raw) {
    if (raw.isEmpty) return null;
    var text = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), ' ');
    text = text.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\x80-\x9F]'),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;
    if (text.length > _bannerLineCap) {
      text = text.substring(0, _bannerLineCap).trimRight();
    }
    return text.isEmpty ? null : text;
  }

  static Future<PortResult> _scanPort({
    required String ip,
    required String host,
    required int port,
    required int timeoutMs,
    required bool grabBanners,
    required Set<Socket> activeSockets,
  }) async {
    final service = serviceNameForPort(port);
    Socket? socket;

    try {
      final connect = Socket.connect(
        ip,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      try {
        socket = await connect;
      } catch (_) {
        unawaited(
          connect.then<void>(
            (lateSocket) => lateSocket.destroy(),
            onError: (Object _) {},
          ),
        );
        rethrow;
      }

      activeSockets.add(socket);
      if (!grabBanners || _tlsPorts.contains(port)) {
        socket.destroy();
        return PortResult(port: port, state: PortState.open, service: service);
      }

      final banner = await _readBanner(socket, host: host, port: port);
      return PortResult(
        port: port,
        state: PortState.open,
        service: service,
        banner: banner,
      );
    } on SocketException catch (error) {
      return PortResult(
        port: port,
        state: _isConnectionRefused(error)
            ? PortState.closed
            : PortState.filtered,
        service: service,
      );
    } on TimeoutException {
      return PortResult(
        port: port,
        state: PortState.filtered,
        service: service,
      );
    } catch (_) {
      return PortResult(
        port: port,
        state: PortState.filtered,
        service: service,
      );
    } finally {
      if (socket != null) {
        activeSockets.remove(socket);
        try {
          socket.destroy();
        } catch (_) {
          // Already closed.
        }
      }
    }
  }

  static Future<String?> _readBanner(
    Socket socket, {
    required String host,
    required int port,
  }) async {
    if (_tlsPorts.contains(port)) return null;

    final readClock = Stopwatch()..start();
    if (_httpPorts.contains(port)) {
      try {
        socket.write('HEAD / HTTP/1.0\r\nHost: $host\r\n\r\n');
        await socket.flush().timeout(
          const Duration(milliseconds: _httpFlushCapMs),
        );
      } catch (_) {
        // Fall through to a passive read.
      }
    }

    final buffer = <int>[];
    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    var finished = false;
    Timer? timer;

    void finish() {
      if (finished) return;
      finished = true;
      timer?.cancel();
      if (!done.isCompleted) done.complete();
    }

    final remaining = _bannerReadCapMs - readClock.elapsedMilliseconds;
    timer = Timer(
      Duration(milliseconds: remaining <= 0 ? 0 : remaining),
      finish,
    );
    subscription = socket.listen(
      (chunk) {
        for (final byte in chunk) {
          if (buffer.length >= _bannerByteCap) break;
          buffer.add(byte);
        }
        if (buffer.length >= _bannerByteCap) finish();
      },
      onError: (Object _) => finish(),
      onDone: finish,
      cancelOnError: true,
    );

    await done.future;
    try {
      await subscription.cancel();
    } catch (_) {
      // Ignore teardown races.
    }
    try {
      socket.destroy();
    } catch (_) {
      // Already closed.
    }
    return sanitizeBanner(latin1.decode(buffer, allowInvalid: true));
  }

  static bool _isConnectionRefused(SocketException error) {
    final osError = error.osError;
    if (osError != null) {
      if (osError.errorCode == 111 ||
          osError.errorCode == 61 ||
          osError.errorCode == 10061) {
        return true;
      }
    }
    final text = '${error.message} ${osError?.message ?? ''}'.toLowerCase();
    return text.contains('connection refused') || text.contains('econnrefused');
  }

  static Future<InternetAddress?> _resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv4) return address;
      }
      return addresses.isEmpty ? null : addresses.first;
    } catch (_) {
      return null;
    }
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.isEmpty ? 'Port scan failed.' : text;
  }
}
