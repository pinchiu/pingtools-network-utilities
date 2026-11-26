import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/net/ping_engine.dart';
import 'package:pingtools/core/net/port_scanner.dart';
import 'package:pingtools/core/net/traceroute_engine.dart';

PingReply _reply(int seq, double rtt) =>
    PingReply(seq: seq, rttMs: rtt, from: '1.1.1.1');

void main() {
  group('PingOutputParser', () {
    test('parses a standard Android echo reply', () {
      final reply = PingOutputParser.parseReply(
        '64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms',
        seq: 1,
      );

      expect(reply, isNotNull);
      expect(reply!.seq, 1);
      expect(reply.rttMs, closeTo(12.3, 1e-9));
      expect(reply.ttl, 57);
      expect(reply.bytes, 64);
      expect(reply.from, '1.1.1.1');
    });

    test('supports busybox seq= lines', () {
      final reply = PingOutputParser.parseReply(
        '64 bytes from 8.8.8.8: seq=3 ttl=118 time=4.567 ms',
        seq: 3,
      );

      expect(reply, isNotNull);
      expect(reply!.rttMs, closeTo(4.567, 1e-9));
      expect(reply.ttl, 118);
      expect(reply.from, '8.8.8.8');
    });

    test('uses 1.0 ms for time<1ms', () {
      final reply = PingOutputParser.parseReply(
        '64 bytes from 1.1.1.1: icmp_seq=2 ttl=57 time<1ms',
        seq: 2,
      );

      expect(reply, isNotNull);
      expect(reply!.rttMs, 1.0);
    });

    test('ignores router TTL-expired lines', () {
      final reply = PingOutputParser.parseReply(
        'From 192.168.1.1 icmp_seq=1 Time to live exceeded',
        seq: 1,
      );

      expect(reply, isNull);
      expect(
        PingOutputParser.isTtlExpired(
          'From 192.168.1.1 icmp_seq=1 Time to live exceeded',
        ),
        isTrue,
      );
    });

    test('parses the reply when TTL and echo lines are mixed', () {
      final reply = PingOutputParser.parseReply(
        'From 10.0.0.1 icmp_seq=1 Time to live exceeded\n'
        '64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=9.9 ms',
        seq: 1,
      );

      expect(reply, isNotNull);
      expect(reply!.from, '1.1.1.1');
      expect(reply.rttMs, closeTo(9.9, 1e-9));
    });

    test('falls back to the host and default size when unspecified', () {
      final reply = PingOutputParser.parseReply(
        'time=0.42 ms',
        seq: 5,
        defaultBytes: 56,
        fallbackFrom: '9.9.9.9',
      );

      expect(reply, isNotNull);
      expect(reply!.from, '9.9.9.9');
      expect(reply.bytes, 56);
      expect(reply.ttl, isNull);
    });

    test('returns null for unrelated output', () {
      expect(
        PingOutputParser.parseReply(
          'ping: sendmsg: Operation not permitted',
          seq: 1,
        ),
        isNull,
      );
    });
  });

  group('PingSummaryCalculator', () {
    test('computes loss, min/avg/max, jitter and population std dev', () {
      final summary = PingSummaryCalculator.summarize(
        sent: 4,
        replies: [_reply(1, 10), _reply(2, 20), _reply(3, 30)],
      );

      expect(summary.sent, 4);
      expect(summary.received, 3);
      expect(summary.lossPercent, closeTo(25, 1e-9));
      expect(summary.minMs, 10);
      expect(summary.avgMs, closeTo(20, 1e-9));
      expect(summary.maxMs, 30);
      expect(summary.jitterMs, closeTo(10, 1e-9));
      expect(summary.stdDevMs, closeTo(math.sqrt(200 / 3), 1e-9));
    });

    test('zero replies means 100% loss and zero latencies', () {
      final summary = PingSummaryCalculator.summarize(sent: 4, replies: []);

      expect(summary.sent, 4);
      expect(summary.received, 0);
      expect(summary.lossPercent, 100);
      expect(summary.minMs, 0);
      expect(summary.avgMs, 0);
      expect(summary.maxMs, 0);
      expect(summary.jitterMs, 0);
      expect(summary.stdDevMs, 0);
    });

    test('a single reply has zero jitter and zero std dev', () {
      final summary = PingSummaryCalculator.summarize(
        sent: 3,
        replies: [_reply(1, 12.5)],
      );

      expect(summary.minMs, 12.5);
      expect(summary.avgMs, 12.5);
      expect(summary.maxMs, 12.5);
      expect(summary.jitterMs, 0);
      expect(summary.stdDevMs, 0);
      expect(summary.lossPercent, closeTo(66.666666, 1e-5));
    });

    test('jitter uses consecutive absolute deltas', () {
      final summary = PingSummaryCalculator.summarize(
        sent: 3,
        replies: [_reply(1, 10), _reply(2, 30), _reply(3, 20)],
      );

      expect(summary.jitterMs, closeTo(15, 1e-9));
    });
  });

  group('TracerouteParser', () {
    test('parses TTL-exceeded router lines with elapsed fallback', () {
      final result = TracerouteParser.parse(
        'From 10.0.0.1 icmp_seq=1 Time to live exceeded',
        targetIp: '1.1.1.1',
        elapsedMs: 42,
      );

      expect(result, isNotNull);
      expect(result!.address, '10.0.0.1');
      expect(result.rttMs, 42);
      expect(result.reachedTarget, isFalse);
    });

    test('parses a destination echo reply from the target', () {
      final result = TracerouteParser.parse(
        '64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=14.2 ms',
        targetIp: '1.1.1.1',
        elapsedMs: 100,
      );

      expect(result, isNotNull);
      expect(result!.address, '1.1.1.1');
      expect(result.rttMs, closeTo(14.2, 1e-9));
      expect(result.reachedTarget, isTrue);
    });

    test('destination time<1ms is reported as 1.0 ms', () {
      final result = TracerouteParser.parse(
        '64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time<1ms',
        targetIp: '8.8.8.8',
        elapsedMs: 50,
      );

      expect(result, isNotNull);
      expect(result!.rttMs, 1.0);
      expect(result.reachedTarget, isTrue);
    });

    test('cleans a trailing colon on the From address', () {
      final result = TracerouteParser.parse(
        'From 10.0.0.1: icmp_seq=1 Time to live exceeded',
        targetIp: '1.1.1.1',
        elapsedMs: 10,
      );

      expect(result, isNotNull);
      expect(result!.address, '10.0.0.1');
    });

    test('does not mark a TTL-expired reply from the target as reached', () {
      final result = TracerouteParser.parse(
        'From 1.1.1.1 icmp_seq=1 Time to live exceeded',
        targetIp: '1.1.1.1',
        elapsedMs: 10,
      );

      expect(result, isNotNull);
      expect(result!.reachedTarget, isFalse);
    });

    test('returns null when a probe times out', () {
      expect(
        TracerouteParser.parse('', targetIp: '1.1.1.1', elapsedMs: 1500),
        isNull,
      );
    });
  });

  group('PortScanner.sanitizeBanner', () {
    test('flattens HTTP headers to one line', () {
      final banner = PortScanner.sanitizeBanner(
        'HTTP/1.1 200 OK\r\nServer: nginx/1.24.0\r\nContent-Type: text/html\r\n',
      );

      expect(
        banner,
        'HTTP/1.1 200 OK Server: nginx/1.24.0 Content-Type: text/html',
      );
    });

    test('strips control bytes and ANSI escapes', () {
      final banner = PortScanner.sanitizeBanner(
        '\x00\x01\x1B[32mSSH-2.0-OpenSSH_9.6\x1B[0m\r\n',
      );

      expect(banner, 'SSH-2.0-OpenSSH_9.6');
    });

    test('caps the banner at 160 characters', () {
      final raw = String.fromCharCodes(List<int>.filled(300, 65));
      final banner = PortScanner.sanitizeBanner(raw);

      expect(banner, isNotNull);
      expect(banner!.length, 160);
    });

    test('returns null for whitespace-only input', () {
      expect(PortScanner.sanitizeBanner(' \r\n\t '), isNull);
      expect(PortScanner.sanitizeBanner(''), isNull);
    });
  });
}
