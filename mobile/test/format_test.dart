import 'package:flutter_test/flutter_test.dart';
import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/net/update_service.dart';
import 'package:pingtools/core/util/format.dart';

void main() {
  group('format helpers', () {
    test('latency formatting', () {
      expect(fmtLatency(0.42), '0.42 ms');
      expect(fmtLatency(8.12), '8.1 ms');
      expect(fmtLatency(143.4), '143 ms');
      expect(fmtLatency(double.nan), '--');
    });

    test('host normalization', () {
      expect(normalizeHost('https://example.com/path?q=1'), 'example.com');
      expect(normalizeHost('example.com:443'), 'example.com');
      expect(normalizeHost(' 1.1.1.1 '), '1.1.1.1');
      expect(normalizeHost('[2606:4700::1111]'), '2606:4700::1111');
    });

    test('IPv4 validation and private ranges', () {
      expect(isValidIpv4('192.168.1.1'), isTrue);
      expect(isValidIpv4('256.1.1.1'), isFalse);
      expect(isValidIpv4('1.2.3'), isFalse);
      expect(isPrivateIp('10.1.2.3'), isTrue);
      expect(isPrivateIp('172.20.0.5'), isTrue);
      expect(isPrivateIp('192.168.0.2'), isTrue);
      expect(isPrivateIp('8.8.8.8'), isFalse);
    });

    test('port specs', () {
      expect(parsePortSpec('22, 80,443'), [22, 80, 443]);
      expect(parsePortSpec('8000-8002'), [8000, 8001, 8002]);
      expect(() => parsePortSpec('0'), throwsFormatException);
      expect(() => parsePortSpec('1-60000'), throwsFormatException);
    });

    test('MAC normalization', () {
      expect(normalizeMac('aabbccddeeff'), 'AA:BB:CC:DD:EE:FF');
      expect(normalizeMac('AA-BB-CC-DD-EE-FF'), 'AA:BB:CC:DD:EE:FF');
      expect(normalizeMac('nope'), isNull);
    });

    test('subnet parsing and host expansion', () {
      final cidr = parseSubnetInput('192.168.1.0/24');
      expect(cidr, isNotNull);
      expect(cidr!.totalHosts, 254);
      expect(cidr.prefixLength, 24);
      final hosts = hostsFor(cidr);
      expect(hosts.length, 254);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');

      final range = parseSubnetInput('10.0.0.10-10.0.0.20');
      expect(range, isNotNull);
      expect(hostsFor(range!).length, 11);
      expect(parseSubnetInput('192.168.1.0/31'), isNull);
    });

    test('IPv4 integer round trip', () {
      final value = ipv4ToInt('192.168.1.20');
      expect(value, isNotNull);
      expect(intToIpv4(value!), '192.168.1.20');
    });

    test('duration formatting', () {
      expect(formatDuration(930), '930ms');
      expect(formatDuration(1500), '1.5s');
    });
  });

  group('update version comparison', () {
    test('newer versions', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('v2.0.1', '2.0.0'), isTrue);
      expect(UpdateService.isNewer('2.1', '2.0.9'), isTrue);
    });

    test('same or older versions', () {
      expect(UpdateService.isNewer('2.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('', '2.0.0'), isFalse);
    });
  });

  test('models stay value-oriented', () {
    const device = WolDevice(name: 'PC', mac: 'AA:BB:CC:DD:EE:FF');
    expect(device.port, 9);
    expect(WolDevice.fromJson(device.toJson()).mac, device.mac);
  });
}
