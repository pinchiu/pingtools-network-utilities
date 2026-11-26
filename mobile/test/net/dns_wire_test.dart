import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pingtools/core/net/dns_engine.dart';

List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _labels(String name) {
  final bytes = <int>[];
  for (final label in name.split('.')) {
    final encoded = utf8.encode(label);
    bytes.add(encoded.length);
    bytes.addAll(encoded);
  }
  bytes.add(0);
  return bytes;
}

List<int> _txt(List<String> values) {
  final bytes = <int>[];
  for (final value in values) {
    final encoded = utf8.encode(value);
    bytes.add(encoded.length);
    bytes.addAll(encoded);
  }
  return bytes;
}

List<int> _answer({
  List<int>? owner,
  required int type,
  required int ttl,
  required List<int> rdata,
}) {
  return [
    ...(owner ?? [0xC0, 0x0C]),
    ..._u16(type),
    ..._u16(1),
    ..._u32(ttl),
    ..._u16(rdata.length),
    ...rdata,
  ];
}

Uint8List _response({
  int id = 0x1234,
  int flags = 0x8180,
  int questionType = 1,
  List<List<int>> answers = const [],
}) {
  final bytes = <int>[
    ..._u16(id),
    ..._u16(flags),
    ..._u16(1),
    ..._u16(answers.length),
    ..._u16(0),
    ..._u16(0),
    ..._labels('example.com'),
    ..._u16(questionType),
    ..._u16(1),
  ];
  for (final answer in answers) {
    bytes.addAll(answer);
  }
  return Uint8List.fromList(bytes);
}

List<int> _soaData() => [
  ..._labels('ns1.example.com'),
  ..._labels('hostmaster.example.com'),
  ..._u32(2024010101),
  ..._u32(7200),
  ..._u32(3600),
  ..._u32(1209600),
  ..._u32(300),
];

void main() {
  group('DnsWire.buildQuery', () {
    test('writes header and one A question', () {
      final query = DnsWire.buildQuery('Example.COM.', 1, id: 0xBEEF);

      expect(query.length, 29);
      expect((query[0] << 8) | query[1], 0xBEEF);
      expect((query[2] << 8) | query[3], 0x0100);
      expect((query[4] << 8) | query[5], 1);
      expect((query[6] << 8) | query[7], 0);
      expect((query[8] << 8) | query[9], 0);
      expect((query[10] << 8) | query[11], 0);
      expect(query.sublist(12, 25), [
        7,
        ...utf8.encode('Example'),
        3,
        ...utf8.encode('COM'),
        0,
      ]);
      expect((query[25] << 8) | query[26], 1);
      expect((query[27] << 8) | query[28], 1);
    });

    test('encodes MX type and rejects bad labels', () {
      final query = DnsWire.buildQuery('example.com', 15, id: 7);
      expect((query[25] << 8) | query[26], 15);

      expect(() => DnsWire.buildQuery('', 1), throwsArgumentError);
      expect(() => DnsWire.buildQuery('a..b', 1), throwsArgumentError);
      expect(
        () => DnsWire.buildQuery('${'a' * 64}.com', 1),
        throwsArgumentError,
      );
    });
  });

  group('DnsWire.parse', () {
    test('parses compressed owner and CNAME pointer names', () {
      final data = _response(
        answers: [
          _answer(type: 1, ttl: 300, rdata: [93, 184, 216, 34]),
          _answer(
            type: 5,
            ttl: 120,
            rdata: [3, ...utf8.encode('www'), 0xC0, 0x0C],
          ),
        ],
      );

      final message = DnsWire.parse(data);

      expect(message.id, 0x1234);
      expect(message.rcode, 0);
      expect(message.truncated, isFalse);
      expect(message.answers, hasLength(2));
      expect(message.answers[0].type, 'A');
      expect(message.answers[0].value, '93.184.216.34');
      expect(message.answers[0].ttl, 300);
      expect(message.answers[1].type, 'CNAME');
      expect(message.answers[1].value, 'www.example.com.');
      expect(message.answers[1].ttl, 120);
    });

    test('parses AAAA, NS, MX, TXT, SOA, SRV, CAA and PTR', () {
      final data = _response(
        answers: [
          _answer(
            type: 28,
            ttl: 60,
            rdata: [0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
          ),
          _answer(type: 2, ttl: 3600, rdata: _labels('ns1.example.com')),
          _answer(
            type: 15,
            ttl: 3600,
            rdata: [..._u16(10), ..._labels('mail.example.com')],
          ),
          _answer(
            type: 16,
            ttl: 300,
            rdata: _txt(['v=spf1 -all', 'hello "world"']),
          ),
          _answer(type: 6, ttl: 3600, rdata: _soaData()),
          _answer(
            type: 33,
            ttl: 60,
            rdata: [
              ..._u16(10),
              ..._u16(5),
              ..._u16(443),
              ..._labels('svc.example.com'),
            ],
          ),
          _answer(
            type: 257,
            ttl: 3600,
            rdata: [
              0,
              5,
              ...utf8.encode('issue'),
              ...utf8.encode('letsencrypt.org'),
            ],
          ),
          _answer(type: 12, ttl: 300, rdata: _labels('host.example.com')),
        ],
      );

      final message = DnsWire.parse(data);
      final byType = {
        for (final record in message.answers) record.type: record,
      };

      expect(message.answers, hasLength(8));
      expect(byType['AAAA']!.value, '2001:db8::1');
      expect(byType['NS']!.value, 'ns1.example.com.');
      expect(byType['MX']!.value, '10 mail.example.com.');
      expect(byType['TXT']!.value, '"v=spf1 -all" "hello \\"world\\""');
      expect(
        byType['SOA']!.value,
        'ns1.example.com. hostmaster.example.com. '
        '2024010101 7200 3600 1209600 300',
      );
      expect(byType['SRV']!.value, '10 5 443 svc.example.com.');
      expect(byType['CAA']!.value, '0 issue "letsencrypt.org"');
      expect(byType['PTR']!.value, 'host.example.com.');
    });

    test('reports NXDOMAIN and truncation flags', () {
      final message = DnsWire.parse(_response(flags: 0x8383));

      expect(message.rcode, 3);
      expect(message.truncated, isTrue);
      expect(message.answers, isEmpty);
    });

    test('rejects compression loops and short messages', () {
      final looped = _response(
        answers: [
          _answer(owner: [0xC0, 29], type: 1, ttl: 60, rdata: [1, 2, 3, 4]),
        ],
      );

      expect(() => DnsWire.parse(looped), throwsFormatException);
      expect(
        () => DnsWire.parse(Uint8List.fromList([0, 1, 2])),
        throwsFormatException,
      );
    });
  });

  group('DnsWire.reverseName', () {
    test('reverses IPv4 and accepts existing reverse names', () {
      expect(DnsWire.reverseName('192.168.1.10'), '10.1.168.192.in-addr.arpa');
      expect(
        DnsWire.reverseName('10.1.168.192.in-addr.arpa'),
        '10.1.168.192.in-addr.arpa',
      );
      expect(() => DnsWire.reverseName('not-an-ip'), throwsArgumentError);
    });

    test('expands IPv6 addresses into nibble labels', () {
      final zeros = List.filled(23, '0').join('.');
      expect(
        DnsWire.reverseName('2001:db8::1'),
        '1.$zeros.8.b.d.0.1.0.0.2.ip6.arpa',
      );
    });
  });
}
