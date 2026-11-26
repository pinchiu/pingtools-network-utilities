import 'package:flutter_test/flutter_test.dart';
import 'package:pingtools/core/net/wol_engine.dart';

void main() {
  group('WolEngine.buildMagicPacket', () {
    const macBytes = <int>[0x00, 0x11, 0x22, 0x33, 0x44, 0x55];

    test('builds the standard 102-byte magic packet', () {
      final packet = WolEngine.buildMagicPacket('00:11:22:33:44:55');

      expect(packet, hasLength(102));
      expect(packet.sublist(0, 6), everyElement(0xFF));
      for (var repeat = 0; repeat < 16; repeat++) {
        final start = 6 + repeat * 6;
        expect(
          packet.sublist(start, start + 6),
          macBytes,
          reason: 'MAC repetition ${repeat + 1} matches',
        );
      }
    });

    test('normalises colon, dash, dot and bare MAC formats', () {
      const inputs = <String>[
        '00:11:22:33:44:55',
        '00-11-22-33-44-55',
        '0011.2233.4455',
        '001122334455',
        '0011 2233 4455',
      ];

      for (final input in inputs) {
        final packet = WolEngine.buildMagicPacket(input);
        expect(packet, hasLength(102), reason: input);
        expect(packet.sublist(6, 12), macBytes, reason: input);
      }
    });

    test('appends a six-byte SecureOn password', () {
      final packet = WolEngine.buildMagicPacket(
        '00:11:22:33:44:55',
        secureOn: '01-02-03-04-05-06',
      );

      expect(packet, hasLength(108));
      expect(packet.sublist(96, 102), macBytes);
      expect(packet.sublist(102, 108), <int>[1, 2, 3, 4, 5, 6]);
    });

    test('treats a blank SecureOn value as absent', () {
      final packet = WolEngine.buildMagicPacket(
        '00:11:22:33:44:55',
        secureOn: '   ',
      );

      expect(packet, hasLength(102));
    });

    test('rejects invalid MAC and SecureOn values', () {
      expect(
        () => WolEngine.buildMagicPacket('not-a-mac'),
        throwsArgumentError,
      );
      expect(
        () => WolEngine.buildMagicPacket('00:11:22:33:44'),
        throwsArgumentError,
      );
      expect(
        () =>
            WolEngine.buildMagicPacket('00:11:22:33:44:55', secureOn: '12:34'),
        throwsArgumentError,
      );
    });

    test('wake validates the MAC before opening a socket', () async {
      await expectLater(
        WolEngine.wake(mac: 'invalid', broadcast: '127.0.0.1'),
        throwsArgumentError,
      );
    });
  });
}
