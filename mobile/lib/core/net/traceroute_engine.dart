import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/util/format.dart';

/// Result of parsing one traceroute probe (a single `ping -c 1 -t <ttl>`).
@visibleForTesting
class TraceProbeResult {
  final String? address;
  final double? rttMs;
  final bool reachedTarget;

  const TraceProbeResult({
    required this.address,
    required this.rttMs,
    required this.reachedTarget,
  });
}

/// Parses the output of a single ICMP probe used by [TracerouteEngine].
@visibleForTesting
class TracerouteParser {
  static final RegExp _timePattern = RegExp(
    r'time\s*([=<])\s*([0-9]+(?:\.[0-9]+)?)\s*ms',
    caseSensitive: false,
  );
  static final RegExp _ttlExpiredPattern = RegExp(
    r'time\s+to\s+live\s+exceeded|ttl\s+expired\s+in\s+transit',
    caseSensitive: false,
  );
  static final RegExp _bytesFromPattern = RegExp(
    r'(\d+)\s+bytes\s+from\s+(\S+)',
    caseSensitive: false,
  );
  static final RegExp _fromPattern = RegExp(
    r'\bfrom\s+(\S+)',
    caseSensitive: false,
  );

  static bool isTtlExpired(String output) =>
      _ttlExpiredPattern.hasMatch(output);

  /// Parses one probe. Returns null when the probe produced no address at all
  /// (a normal `*` timeout).
  static TraceProbeResult? parse(
    String output, {
    required String targetIp,
    required int elapsedMs,
  }) {
    final ttlExpired = _ttlExpiredPattern.hasMatch(output);
    final fallbackRtt = elapsedMs < 0 ? 0.0 : elapsedMs.toDouble();

    final bytesMatch = _bytesFromPattern.firstMatch(output);
    if (bytesMatch != null) {
      final address = _cleanAddress(bytesMatch.group(2)!);
      if (address.isEmpty) return null;
      return TraceProbeResult(
        address: address,
        rttMs: _parseRtt(output) ?? fallbackRtt,
        reachedTarget: !ttlExpired && _sameAddress(address, targetIp),
      );
    }

    final fromMatch = _fromPattern.firstMatch(output);
    if (fromMatch != null) {
      final address = _cleanAddress(fromMatch.group(1)!);
      if (address.isEmpty) return null;
      return TraceProbeResult(
        address: address,
        rttMs: _parseRtt(output) ?? fallbackRtt,
        reachedTarget: false,
      );
    }
    return null;
  }

  static double? _parseRtt(String output) {
    final match = _timePattern.firstMatch(output);
    if (match == null) return null;
    final value = double.tryParse(match.group(2)!);
    if (value == null || !value.isFinite || value < 0) return null;
    return match.group(1) == '<' ? 1.0 : value;
  }

  static String _cleanAddress(String raw) {
    var value = raw.trim();
    if (InternetAddress.tryParse(value) != null) return value;
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.endsWith(':') || value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    final parsed = InternetAddress.tryParse(value);
    return parsed?.address ?? value;
  }

  static bool _sameAddress(String left, String right) {
    final a = InternetAddress.tryParse(left)?.address ?? left;
    final b = InternetAddress.tryParse(right)?.address ?? right;
    return a.toLowerCase() == b.toLowerCase();
  }
}

/// ICMP TTL-expiry traceroute engine.
///
/// Each hop is probed with `ping -c 1 -W 1 -t <ttl>`; the hop's [TraceHop.rtts]
/// contains one entry per probe that produced a router or destination address.
/// Probes that time out are omitted (the UI pads them with `*`).
class TracerouteEngine {
  static const String _primaryPing = '/system/bin/ping';
  static const String _fallbackPing = 'ping';
  static const int _processGraceMs = 2000;
  static const String _blockedMessage =
      'ICMP is blocked on this device; traceroute requires raw ICMP support.';

  static Stream<TraceEvent> trace(TraceConfig config) async* {
    Process? activeProcess;

    try {
      final target = normalizeHost(config.host);
      if (target.isEmpty) {
        yield const TraceFailed('Enter a host to trace.');
        return;
      }

      final address = await _resolve(target);
      if (address == null) {
        yield TraceFailed('Could not resolve "$target".');
        return;
      }
      final ip = address.address;

      yield TraceStarted(target: target, resolvedIp: ip);

      final executable = await _probeIcmp();
      if (executable == null) {
        yield const TraceFailed(_blockedMessage);
        return;
      }

      final maxHops = _clampInt(config.maxHops, 1, 255);
      final probesPerHop = _clampInt(config.probesPerHop, 1, 10);
      final timeoutMs = _clampInt(config.timeoutMs, 100, 60000);
      final hardTimeoutMs = timeoutMs + _processGraceMs;
      final hops = <TraceHop>[];
      var reachedTarget = false;

      for (var hopNumber = 1; hopNumber <= maxHops; hopNumber++) {
        String? hopAddress;
        final rtts = <double>[];
        var launchFailures = 0;

        final arguments = <String>[
          '-c',
          '1',
          '-W',
          '1',
          '-t',
          '$hopNumber',
          ip,
        ];

        for (var probe = 0; probe < probesPerHop; probe++) {
          _ProcessOutput? run;
          try {
            run = await _runProcess(
              executable,
              arguments,
              hardTimeoutMs: hardTimeoutMs,
              onSpawn: (process) {
                activeProcess = process;
              },
            );
          } on ProcessException {
            launchFailures++;
            run = null;
          } catch (_) {
            run = null;
          } finally {
            activeProcess = null;
          }
          if (run == null) continue;

          final parsed = TracerouteParser.parse(
            run.combined,
            targetIp: ip,
            elapsedMs: run.elapsedMs,
          );
          if (parsed == null) continue;

          hopAddress ??= parsed.address;
          final rtt = parsed.rttMs;
          if (rtt != null) rtts.add(rtt);
          if (parsed.reachedTarget) reachedTarget = true;
        }

        if (hopNumber == 1 && launchFailures == probesPerHop) {
          yield const TraceFailed(_blockedMessage);
          return;
        }

        final hop = TraceHop(
          hop: hopNumber,
          address: hopAddress,
          hostname: null,
          rtts: List<double>.unmodifiable(rtts),
        );
        hops.add(hop);
        yield TraceHopFound(hop);

        if (reachedTarget) break;
      }

      yield TraceFinished(List<TraceHop>.unmodifiable(hops), reachedTarget);
    } catch (error) {
      yield TraceFailed(_friendlyError(error));
    } finally {
      final process = activeProcess;
      activeProcess = null;
      if (process != null) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {
          // Already exited.
        }
      }
    }
  }

  /// Returns the ping executable when a loopback probe succeeds, else null.
  static Future<String?> _probeIcmp() async {
    for (final executable in const <String>[_primaryPing, _fallbackPing]) {
      try {
        final run = await _runProcess(
          executable,
          const <String>['-c', '1', '-W', '1', '127.0.0.1'],
          hardTimeoutMs: 3000,
          onSpawn: (process) {},
        );
        if (run.exitCode == 0 && !run.timedOut) return executable;
        return null;
      } on ProcessException {
        continue;
      } catch (_) {
        return null;
      }
    }
    return null;
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

  static Future<_ProcessOutput> _runProcess(
    String executable,
    List<String> arguments, {
    required int hardTimeoutMs,
    required void Function(Process process) onSpawn,
  }) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(executable, arguments);
    onSpawn(process);

    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    const decoder = Utf8Decoder(allowMalformed: true);

    final stdoutSubscription = process.stdout
        .transform(decoder)
        .listen(
          stdout.write,
          onError: (Object _) {},
          onDone: () {
            if (!stdoutDone.isCompleted) stdoutDone.complete();
          },
        );
    final stderrSubscription = process.stderr
        .transform(decoder)
        .listen(
          stderr.write,
          onError: (Object _) {},
          onDone: () {
            if (!stderrDone.isCompleted) stderrDone.complete();
          },
        );

    var timedOut = false;
    var exitCode = -1;
    try {
      try {
        exitCode = await process.exitCode.timeout(
          Duration(milliseconds: hardTimeoutMs),
        );
      } on TimeoutException {
        timedOut = true;
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {
          // Already exited.
        }
        try {
          exitCode = await process.exitCode.timeout(const Duration(seconds: 1));
        } on TimeoutException {
          exitCode = -1;
        }
      }

      try {
        await Future.wait(<Future<void>>[stdoutDone.future, stderrDone.future])
            .timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        // Use whatever was captured so far.
      }
    } finally {
      try {
        await stdoutSubscription.cancel();
      } catch (_) {
        // Ignore teardown races.
      }
      try {
        await stderrSubscription.cancel();
      } catch (_) {
        // Ignore teardown races.
      }
    }

    return _ProcessOutput(
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
      timedOut: timedOut,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.isEmpty ? 'Traceroute failed.' : text;
  }
}

class _ProcessOutput {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final int elapsedMs;

  const _ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.elapsedMs,
  });

  String get combined {
    if (stdout.isEmpty) return stderr;
    if (stderr.isEmpty) return stdout;
    return '$stdout\n$stderr';
  }
}
