import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/util/format.dart';

/// Parses the textual output of the Android `ping` binary.
///
/// The parser is deliberately strict: a line only counts as a reply when it
/// carries a `time=`/`time<` value, which keeps router `Time to live exceeded`
/// messages from being mistaken for echo replies.
@visibleForTesting
class PingOutputParser {
  static final RegExp _timePattern = RegExp(
    r'time\s*([=<])\s*([0-9]+(?:\.[0-9]+)?)\s*ms',
    caseSensitive: false,
  );
  static final RegExp _ttlPattern = RegExp(
    r'\bttl\s*[=:]\s*(\d+)',
    caseSensitive: false,
  );
  static final RegExp _bytesFromPattern = RegExp(
    r'(\d+)\s+bytes\s+from\s+(\S+)',
    caseSensitive: false,
  );
  static final RegExp _ttlExpiredPattern = RegExp(
    r'time\s+to\s+live\s+exceeded|ttl\s+expired\s+in\s+transit',
    caseSensitive: false,
  );

  static bool isTtlExpired(String output) =>
      _ttlExpiredPattern.hasMatch(output);

  /// Returns the echo reply found in [output], or null when the packet was lost.
  ///
  /// [fallbackFrom] is used when the reply line does not contain a source
  /// address (some reduced `ping` implementations omit it).
  static PingReply? parseReply(
    String output, {
    required int seq,
    int defaultBytes = 56,
    String? fallbackFrom,
  }) {
    for (final line in const LineSplitter().convert(output)) {
      if (_ttlExpiredPattern.hasMatch(line)) continue;
      final timeMatch = _timePattern.firstMatch(line);
      if (timeMatch == null) continue;

      final value = double.tryParse(timeMatch.group(2)!);
      if (value == null || !value.isFinite || value < 0) continue;

      // `time<1ms` is reported as 1.0 ms.
      final rtt = timeMatch.group(1) == '<' ? 1.0 : value;

      final bytesMatch = _bytesFromPattern.firstMatch(line);
      final bytesValue = bytesMatch == null
          ? defaultBytes
          : int.tryParse(bytesMatch.group(1)!) ?? defaultBytes;
      var from = bytesMatch == null
          ? (fallbackFrom ?? '')
          : _cleanAddress(bytesMatch.group(2)!);
      if (from.isEmpty) from = fallbackFrom ?? '';

      final ttlMatch = _ttlPattern.firstMatch(line);
      final ttl = ttlMatch == null ? null : int.tryParse(ttlMatch.group(1)!);

      return PingReply(
        seq: seq,
        rttMs: rtt,
        ttl: ttl,
        bytes: bytesValue < 0 ? 0 : bytesValue,
        from: from,
      );
    }
    return null;
  }

  static String _cleanAddress(String raw) {
    var value = raw.trim();
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.endsWith(':') || value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

/// Pure latency statistics used by [PingEngine] at the end of a finite run.
@visibleForTesting
class PingSummaryCalculator {
  static PingSummary summarize({
    required int sent,
    required List<PingReply> replies,
  }) {
    final attempts = sent < 0 ? 0 : sent;
    final received = replies.length;
    if (received == 0) {
      return PingSummary(
        sent: attempts,
        received: 0,
        lossPercent: 100,
        minMs: 0,
        avgMs: 0,
        maxMs: 0,
        jitterMs: 0,
        stdDevMs: 0,
      );
    }

    final latencies = <double>[];
    for (final reply in replies) {
      final value = reply.rttMs;
      if (value.isFinite && value >= 0) latencies.add(value);
    }
    if (latencies.isEmpty) {
      return PingSummary(
        sent: attempts,
        received: 0,
        lossPercent: 100,
        minMs: 0,
        avgMs: 0,
        maxMs: 0,
        jitterMs: 0,
        stdDevMs: 0,
      );
    }

    var total = 0.0;
    var min = latencies.first;
    var max = latencies.first;
    for (final value in latencies) {
      total += value;
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final average = total / latencies.length;

    var jitterTotal = 0.0;
    for (var i = 1; i < latencies.length; i++) {
      jitterTotal += (latencies[i] - latencies[i - 1]).abs();
    }
    final jitter = latencies.length < 2
        ? 0.0
        : jitterTotal / (latencies.length - 1);

    var variance = 0.0;
    for (final value in latencies) {
      final delta = value - average;
      variance += delta * delta;
    }
    final stdDev = math.sqrt(variance / latencies.length);

    final loss = attempts == 0
        ? 0.0
        : math.min(
            100.0,
            math.max(0.0, (attempts - received) / attempts * 100.0),
          );

    return PingSummary(
      sent: attempts,
      received: received,
      lossPercent: loss,
      minMs: min,
      avgMs: average,
      maxMs: max,
      jitterMs: jitter,
      stdDevMs: stdDev,
    );
  }
}

/// ICMP echo / TCP-connect ping engine.
///
/// Emits [PingStarted] once, then one reply or timeout event per attempt. A
/// finite run ends with [PingFinishedEvent]; a continuous run (`count == 0`)
/// ends only when the subscription is cancelled.
class PingEngine {
  static const String _primaryPing = '/system/bin/ping';
  static const String _fallbackPing = 'ping';
  static const List<int> _tcpFallbackPorts = <int>[443, 80, 53];
  static const int _processGraceMs = 2000;

  static Stream<PingEvent> ping(PingConfig config) async* {
    Process? activeProcess;
    Socket? activeSocket;

    try {
      final target = normalizeHost(config.host);
      if (target.isEmpty) {
        yield const PingFailedEvent('Enter a host to ping.');
        return;
      }

      final address = await _resolve(target);
      if (address == null) {
        yield PingFailedEvent('Could not resolve "$target".');
        return;
      }
      final ip = address.address;

      final probe = await _probeIcmp();
      final mode = probe.available ? PingMode.icmp : PingMode.tcp;
      final replies = <PingReply>[];
      final finite = config.count > 0;

      yield PingStarted(target: target, resolvedIp: ip, mode: mode);
      if (!probe.available) {
        yield PingNoteEvent(probe.reason);
      }

      final packetSize = _clampInt(config.packetSize, 1, 65000);
      final ttl = _clampInt(config.ttl, 1, 255);
      final timeoutMs = _clampInt(config.timeoutMs, 100, 60000);
      final intervalMs = config.intervalMs < 0 ? 0 : config.intervalMs;
      final timeoutSeconds = math.max(1, (timeoutMs / 1000).ceil());
      final hardTimeoutMs = timeoutMs + _processGraceMs;

      var attempts = 0;
      while (!finite || attempts < config.count) {
        if (attempts > 0 && intervalMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: intervalMs));
        }
        final seq = ++attempts;
        PingReply? reply;

        if (mode == PingMode.icmp) {
          final arguments = <String>[
            '-c',
            '1',
            '-W',
            '$timeoutSeconds',
            '-s',
            '$packetSize',
            '-t',
            '$ttl',
            ip,
          ];
          _ProcessOutput? run;
          try {
            run = await _runProcess(
              probe.executable,
              arguments,
              hardTimeoutMs: hardTimeoutMs,
              onSpawn: (process) {
                activeProcess = process;
              },
            );
          } on ProcessException {
            run = null;
          } catch (_) {
            run = null;
          } finally {
            activeProcess = null;
          }
          if (run != null) {
            reply = PingOutputParser.parseReply(
              run.combined,
              seq: seq,
              defaultBytes: packetSize,
              fallbackFrom: ip,
            );
          }
        } else {
          reply = await _tcpProbe(
            ip: ip,
            seq: seq,
            timeoutMs: timeoutMs,
            onConnected: (socket) {
              activeSocket = socket;
            },
          );
          activeSocket = null;
        }

        if (reply != null) {
          replies.add(reply);
          yield PingReplyEvent(reply);
        } else {
          yield PingTimeoutEvent(seq);
        }
      }

      if (finite) {
        yield PingFinishedEvent(
          PingSummaryCalculator.summarize(sent: attempts, replies: replies),
          List<PingReply>.unmodifiable(replies),
        );
      }
    } catch (error) {
      yield PingFailedEvent(_friendlyError(error));
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

      final socket = activeSocket;
      activeSocket = null;
      if (socket != null) {
        try {
          socket.destroy();
        } catch (_) {
          // Already closed.
        }
      }
    }
  }

  /// Probes the loopback interface once to decide whether raw ICMP works.
  static Future<_IcmpProbe> _probeIcmp() async {
    for (final executable in const <String>[_primaryPing, _fallbackPing]) {
      _ProcessOutput run;
      try {
        run = await _runProcess(
          executable,
          const <String>['-c', '1', '-W', '1', '127.0.0.1'],
          hardTimeoutMs: 3000,
          onSpawn: (process) {},
        );
      } on ProcessException {
        continue;
      } catch (_) {
        continue;
      }

      if (run.exitCode == 0 && !run.timedOut) {
        return _IcmpProbe(available: true, executable: executable);
      }
      if (_looksUnsupported(run)) {
        return _IcmpProbe(
          available: false,
          executable: executable,
          reason:
              'ICMP is unavailable on this device. Using TCP connect probes.',
        );
      }
      // The binary exists but loopback did not answer; keep ICMP mode.
      return _IcmpProbe(available: true, executable: executable);
    }
    return const _IcmpProbe(
      available: false,
      executable: _fallbackPing,
      reason: 'The ping utility is unavailable on this device. Using TCP connect probes.',
    );
  }

  static bool _looksUnsupported(_ProcessOutput run) {
    if (run.timedOut) return true;
    if (run.exitCode == 0) return false;
    if (run.exitCode == 2) return true;
    final text = run.combined.toLowerCase();
    const markers = <String>[
      'operation not permitted',
      'permission denied',
      'not permitted',
      'unknown option',
      'invalid option',
      'unrecognized option',
      'unrecognised option',
      'usage:',
      'no such file',
      'socket',
    ];
    for (final marker in markers) {
      if (text.contains(marker)) return true;
    }
    return false;
  }

  /// TCP connect ping: 443, then 80, then 53, each with the configured timeout.
  static Future<PingReply?> _tcpProbe({
    required String ip,
    required int seq,
    required int timeoutMs,
    required void Function(Socket socket) onConnected,
  }) async {
    for (final port in _tcpFallbackPorts) {
      final stopwatch = Stopwatch()..start();
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
        onConnected(socket);
        stopwatch.stop();
        return PingReply(
          seq: seq,
          rttMs: stopwatch.elapsedMicroseconds / 1000.0,
          ttl: null,
          bytes: 0,
          from: '$ip:$port',
        );
      } catch (_) {
        // Try the next fallback port.
      } finally {
        if (socket != null) {
          try {
            socket.destroy();
          } catch (_) {
            // Already closed.
          }
        }
      }
    }
    return null;
  }

  /// Resolves [host], preferring IPv4. Returns null on any failure.
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

  /// Runs a process with a hard timeout, draining stdout and stderr.
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
    return text.isEmpty ? 'Ping failed.' : text;
  }
}

class _IcmpProbe {
  final bool available;
  final String executable;
  final String reason;

  const _IcmpProbe({
    required this.available,
    required this.executable,
    this.reason = '',
  });
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
