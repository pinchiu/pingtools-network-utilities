import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/native_bridge.dart';
import 'package:pingtools/core/util/format.dart';

/// DNS lookup over UDP with a minimal wire-format implementation.
class DnsEngine {
  DnsEngine._();

  static const Duration _timeout = Duration(seconds: 4);
  static const int _dnsPort = 53;
  static final Random _random = Random();

  /// Label / resolver pairs. The first entry means "use system DNS".
  static const List<(String, String)> resolvers = [
    ('System', 'system'),
    ('Cloudflare', '1.1.1.1'),
    ('Google', '8.8.8.8'),
    ('Quad9', '9.9.9.9'),
    ('OpenDNS', '208.67.222.222'),
    ('AdGuard', '94.140.14.14'),
  ];

  static const Map<DnsType, int> _typeCodes = {
    DnsType.a: 1,
    DnsType.aaaa: 28,
    DnsType.cname: 5,
    DnsType.mx: 15,
    DnsType.ns: 2,
    DnsType.txt: 16,
    DnsType.soa: 6,
    DnsType.srv: 33,
    DnsType.caa: 257,
    DnsType.ptr: 12,
  };

  static Future<DnsResult> lookup(
    String name,
    DnsType type, {
    String? resolver,
  }) async {
    final stopwatch = Stopwatch()..start();
    final input = name.trim();
    var resolverLabel = _resolverLabel(resolver);

    if (input.isEmpty) {
      return DnsResult(
        query: input,
        type: type,
        resolver: resolverLabel,
        error: 'Enter a domain name',
      );
    }

    String target;
    try {
      target = type == DnsType.ptr ? _ptrTarget(input) : normalizeHost(input);
    } catch (error) {
      return DnsResult(
        query: input,
        type: type,
        resolver: resolverLabel,
        durationMs: stopwatch.elapsedMilliseconds,
        error: _messageFor(error),
      );
    }

    if (target.isEmpty) {
      return DnsResult(
        query: input,
        type: type,
        resolver: resolverLabel,
        durationMs: stopwatch.elapsedMilliseconds,
        error: 'Enter a domain name',
      );
    }

    try {
      final server = await _selectServer(resolver);
      resolverLabel = server.label;
      final id = _random.nextInt(0x10000);
      final query = DnsWire.buildQuery(target, _typeCodes[type] ?? 1, id: id);

      Uint8List? response;
      for (var attempt = 0; attempt < 2 && response == null; attempt++) {
        response = await _exchange(server.address, query, id);
      }

      if (response == null) {
        return DnsResult(
          query: input,
          type: type,
          resolver: resolverLabel,
          durationMs: stopwatch.elapsedMilliseconds,
          error: 'No response from $resolverLabel (timeout)',
        );
      }

      final message = DnsWire.parse(response);
      if (message.id != id) {
        return DnsResult(
          query: input,
          type: type,
          resolver: resolverLabel,
          durationMs: stopwatch.elapsedMilliseconds,
          error: 'Mismatched DNS response',
        );
      }
      if (message.rcode != 0) {
        return DnsResult(
          query: input,
          type: type,
          resolver: resolverLabel,
          durationMs: stopwatch.elapsedMilliseconds,
          error: _rcodeMessage(message.rcode),
        );
      }
      if (message.truncated && message.answers.isEmpty) {
        return DnsResult(
          query: input,
          type: type,
          resolver: resolverLabel,
          durationMs: stopwatch.elapsedMilliseconds,
          error: 'DNS response truncated — try another resolver',
        );
      }

      return DnsResult(
        query: input,
        type: type,
        resolver: resolverLabel,
        records: message.answers,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      return DnsResult(
        query: input,
        type: type,
        resolver: resolverLabel,
        durationMs: stopwatch.elapsedMilliseconds,
        error: _messageFor(error),
      );
    }
  }

  static Future<DnsResult> reverse(String ip, {String? resolver}) async {
    final input = ip.trim();
    var value = input;
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    final isReverseName =
        value.toLowerCase().endsWith('.in-addr.arpa') ||
        value.toLowerCase().endsWith('.ip6.arpa');
    final looksLikeIp = isValidIpv4(value) || value.contains(':');
    if (value.isEmpty || (!isReverseName && !looksLikeIp)) {
      final label = _resolverLabel(resolver);
      return DnsResult(
        query: input,
        type: DnsType.ptr,
        resolver: label,
        error: 'Enter a valid IP address',
      );
    }
    return lookup(value, DnsType.ptr, resolver: resolver);
  }

  static String _resolverLabel(String? resolver) {
    final value = resolver?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'system') {
      return 'System';
    }
    for (final entry in resolvers) {
      if (entry.$2 != 'system' &&
          entry.$1.toLowerCase() == value.toLowerCase()) {
        return '${entry.$1} (${entry.$2})';
      }
    }
    return value;
  }

  static String _ptrTarget(String input) {
    final value = input.trim();
    final lower = value.toLowerCase();
    if (lower.endsWith('.in-addr.arpa') || lower.endsWith('.ip6.arpa')) {
      return normalizeHost(value);
    }
    if (isValidIpv4(value)) {
      return '${value.split('.').reversed.join('.')}.in-addr.arpa';
    }
    if (value.contains(':')) {
      return DnsWire.reverseName(value);
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(value)) {
      throw const FormatException('Enter a valid IP address');
    }
    return normalizeHost(value);
  }

  static Future<({String label, InternetAddress address})> _selectServer(
    String? resolver,
  ) async {
    final value = resolver?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'system') {
      String? systemDns;
      try {
        final info = await NativeBridge.connectionInfo();
        for (final entry in info.dnsServers) {
          final candidate = InternetAddress.tryParse(entry.trim());
          if (candidate != null && candidate.type == InternetAddressType.IPv4) {
            systemDns = candidate.address;
            break;
          }
        }
      } catch (_) {
        // Fall through to a public resolver.
      }
      final address = InternetAddress(systemDns ?? '1.1.1.1');
      return (label: 'System (${address.address})', address: address);
    }

    for (final entry in resolvers) {
      if (entry.$2 != 'system' &&
          entry.$1.toLowerCase() == value.toLowerCase()) {
        final address = InternetAddress(entry.$2);
        return (label: '${entry.$1} (${entry.$2})', address: address);
      }
    }

    final parsed = InternetAddress.tryParse(value);
    if (parsed != null) {
      return (label: value, address: parsed);
    }

    final addresses = await InternetAddress.lookup(value);
    if (addresses.isEmpty) {
      throw const SocketException('Resolver not found');
    }
    var chosen = addresses.first;
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4) {
        chosen = address;
        break;
      }
    }
    return (label: value, address: chosen);
  }

  static Future<Uint8List?> _exchange(
    InternetAddress server,
    Uint8List query,
    int id,
  ) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    try {
      final bindAddress = server.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4;
      socket = await RawDatagramSocket.bind(bindAddress, 0).timeout(_timeout);
      final completer = Completer<Uint8List?>();

      subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) {
            return;
          }
          Datagram? datagram;
          while ((datagram = socket!.receive()) != null) {
            final data = datagram!.data;
            if (data.length < 12) {
              continue;
            }
            final responseId = (data[0] << 8) | data[1];
            if (responseId == id && !completer.isCompleted) {
              completer.complete(data);
              return;
            }
          }
        },
        onError: (Object _) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );

      socket.send(query, server, _dnsPort);
      timer = Timer(_timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }

  static String _rcodeMessage(int rcode) {
    switch (rcode) {
      case 1:
        return 'DNS format error (FORMERR)';
      case 2:
        return 'DNS server failure (SERVFAIL)';
      case 3:
        return 'Domain does not exist (NXDOMAIN)';
      case 4:
        return 'DNS query not implemented (NOTIMP)';
      case 5:
        return 'DNS query refused (REFUSED)';
      default:
        return 'DNS error (RCODE $rcode)';
    }
  }

  static String _messageFor(Object error) {
    if (error is TimeoutException) {
      return 'DNS query timed out';
    }
    if (error is FormatException) {
      return 'Invalid DNS response: ${error.message}';
    }
    if (error is SocketException) {
      return 'DNS network error: ${error.message}';
    }
    if (error is ArgumentError) {
      return '${error.message}';
    }
    return 'DNS lookup failed: $error';
  }
}

/// Parsed DNS message.
class DnsMessage {
  final int id;
  final int flags;
  final int rcode;
  final bool truncated;
  final List<DnsRecord> answers;

  const DnsMessage({
    required this.id,
    required this.flags,
    required this.rcode,
    required this.truncated,
    required this.answers,
  });
}

/// Pure DNS wire-format helpers (query building and response parsing).
class DnsWire {
  DnsWire._();

  static const Map<int, String> _typeNames = {
    1: 'A',
    2: 'NS',
    5: 'CNAME',
    6: 'SOA',
    12: 'PTR',
    15: 'MX',
    16: 'TXT',
    28: 'AAAA',
    33: 'SRV',
    257: 'CAA',
  };

  static Uint8List buildQuery(String name, int type, {int? id}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Enter a domain name');
    }
    final normalized = trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final labels = normalized.isEmpty ? <String>[] : normalized.split('.');

    final builder = BytesBuilder(copy: false);
    final header = ByteData(12);
    header.setUint16(0, id ?? Random().nextInt(0x10000));
    header.setUint16(2, 0x0100);
    header.setUint16(4, 1);
    builder.add(header.buffer.asUint8List());

    var encodedLength = 1; // Root label.
    for (final label in labels) {
      if (label.isEmpty) {
        throw ArgumentError('Invalid domain name');
      }
      final bytes = utf8.encode(label);
      if (bytes.isEmpty || bytes.length > 63) {
        throw ArgumentError('Domain label is too long');
      }
      encodedLength += bytes.length + 1;
      if (encodedLength > 255) {
        throw ArgumentError('Domain name is too long');
      }
      builder.addByte(bytes.length);
      builder.add(bytes);
    }
    builder.addByte(0);
    builder.add(_be16(type));
    builder.add(_be16(1));
    return builder.takeBytes();
  }

  static DnsMessage parse(Uint8List data) {
    if (data.length < 12) {
      throw const FormatException('DNS response is too short');
    }
    final id = _readU16(data, 0);
    final flags = _readU16(data, 2);
    if ((flags & 0x8000) == 0) {
      throw const FormatException('Not a DNS response');
    }
    final questionCount = _readU16(data, 4);
    final answerCount = _readU16(data, 6);

    var offset = 12;
    for (var i = 0; i < questionCount; i++) {
      final question = _readName(data, offset);
      offset = question.next;
      if (offset + 4 > data.length) {
        throw const FormatException('Truncated DNS question');
      }
      offset += 4;
    }

    final answers = <DnsRecord>[];
    for (var i = 0; i < answerCount; i++) {
      final owner = _readName(data, offset);
      offset = owner.next;
      if (offset + 10 > data.length) {
        throw const FormatException('Truncated DNS record');
      }
      final type = _readU16(data, offset);
      final ttl = _readU32(data, offset + 4);
      final dataLength = _readU16(data, offset + 8);
      offset += 10;
      final dataEnd = offset + dataLength;
      if (dataEnd > data.length) {
        throw const FormatException('Truncated DNS record data');
      }
      final record = _parseRecord(data, type, ttl, offset, dataEnd);
      if (record != null) {
        answers.add(record);
      }
      offset = dataEnd;
    }

    return DnsMessage(
      id: id,
      flags: flags,
      rcode: flags & 0x0F,
      truncated: (flags & 0x0200) != 0,
      answers: answers,
    );
  }

  /// Converts an IPv4/IPv6 address (or an existing reverse name) to a
  /// PTR query name.
  static String reverseName(String input) {
    final value = input.trim().toLowerCase();
    if (value.isEmpty) {
      throw ArgumentError('Enter an IP address');
    }
    if (value.endsWith('.in-addr.arpa') || value.endsWith('.ip6.arpa')) {
      return value.endsWith('.') ? value.substring(0, value.length - 1) : value;
    }

    final ipv4 = _ipv4Parts(value);
    if (ipv4 != null) {
      return '${ipv4.reversed.join('.')}.in-addr.arpa';
    }

    if (!value.contains(':')) {
      throw ArgumentError('Invalid IP address');
    }

    var address = value;
    final zoneIndex = address.indexOf('%');
    if (zoneIndex >= 0) {
      address = address.substring(0, zoneIndex);
    }
    final halves = address.split('::');
    if (halves.length > 2) {
      throw ArgumentError('Invalid IP address');
    }
    final left = halves[0].isEmpty ? <String>[] : halves[0].split(':');
    final right = halves.length == 2 && halves[1].isNotEmpty
        ? halves[1].split(':')
        : <String>[];
    final missing = 8 - left.length - right.length;
    if (halves.length == 2) {
      if (missing < 1) {
        throw ArgumentError('Invalid IP address');
      }
    } else if (missing != 0) {
      throw ArgumentError('Invalid IP address');
    }

    final groups = <int>[];
    for (final part in [
      ...left,
      ...List.filled(max(missing, 0), '0'),
      ...right,
    ]) {
      final parsed = int.tryParse(part, radix: 16);
      if (parsed == null || parsed < 0 || parsed > 0xFFFF) {
        throw ArgumentError('Invalid IP address');
      }
      groups.add(parsed);
    }
    if (groups.length != 8) {
      throw ArgumentError('Invalid IP address');
    }

    final hex = groups
        .map((group) => group.toRadixString(16).padLeft(4, '0'))
        .join();
    return '${hex.split('').reversed.join('.')}.ip6.arpa';
  }

  static DnsRecord? _parseRecord(
    Uint8List data,
    int type,
    int ttl,
    int start,
    int end,
  ) {
    switch (type) {
      case 1:
        if (end - start != 4) {
          throw const FormatException('Invalid A record');
        }
        return DnsRecord(
          type: 'A',
          value:
              '${data[start]}.${data[start + 1]}.${data[start + 2]}.${data[start + 3]}',
          ttl: ttl,
        );
      case 28:
        if (end - start != 16) {
          throw const FormatException('Invalid AAAA record');
        }
        return DnsRecord(
          type: 'AAAA',
          value: _formatIpv6(Uint8List.sublistView(data, start, end)),
          ttl: ttl,
        );
      case 2:
      case 5:
      case 12:
        if (start >= end) {
          throw const FormatException('Invalid DNS name record');
        }
        final name = _readName(data, start);
        if (name.next > end) {
          throw const FormatException('Invalid DNS name record');
        }
        return DnsRecord(
          type: _typeNames[type]!,
          value: _dotted(name.name),
          ttl: ttl,
        );
      case 15:
        if (end - start < 3) {
          throw const FormatException('Invalid MX record');
        }
        final preference = _readU16(data, start);
        final exchange = _readName(data, start + 2);
        if (exchange.next > end) {
          throw const FormatException('Invalid MX record');
        }
        return DnsRecord(
          type: 'MX',
          value: '$preference ${_dotted(exchange.name)}',
          ttl: ttl,
        );
      case 16:
        final parts = <String>[];
        var offset = start;
        while (offset < end) {
          final length = data[offset];
          offset += 1;
          if (offset + length > end) {
            throw const FormatException('Invalid TXT record');
          }
          final text = utf8.decode(
            Uint8List.sublistView(data, offset, offset + length),
            allowMalformed: true,
          );
          parts.add('"${_escapeQuoted(text)}"');
          offset += length;
        }
        return DnsRecord(type: 'TXT', value: parts.join(' '), ttl: ttl);
      case 6:
        var offset = start;
        final primary = _readName(data, offset);
        offset = primary.next;
        final mailbox = _readName(data, offset);
        offset = mailbox.next;
        if (offset + 20 > end) {
          throw const FormatException('Invalid SOA record');
        }
        final serial = _readU32(data, offset);
        final refresh = _readU32(data, offset + 4);
        final retry = _readU32(data, offset + 8);
        final expire = _readU32(data, offset + 12);
        final minimum = _readU32(data, offset + 16);
        return DnsRecord(
          type: 'SOA',
          value:
              '${_dotted(primary.name)} ${_dotted(mailbox.name)} '
              '$serial $refresh $retry $expire $minimum',
          ttl: ttl,
        );
      case 33:
        if (end - start < 7) {
          throw const FormatException('Invalid SRV record');
        }
        final priority = _readU16(data, start);
        final weight = _readU16(data, start + 2);
        final port = _readU16(data, start + 4);
        final target = _readName(data, start + 6);
        if (target.next > end) {
          throw const FormatException('Invalid SRV record');
        }
        return DnsRecord(
          type: 'SRV',
          value: '$priority $weight $port ${_dotted(target.name)}',
          ttl: ttl,
        );
      case 257:
        if (end - start < 2) {
          throw const FormatException('Invalid CAA record');
        }
        final flags = data[start];
        final tagLength = data[start + 1];
        final tagStart = start + 2;
        final valueStart = tagStart + tagLength;
        if (valueStart > end) {
          throw const FormatException('Invalid CAA record');
        }
        final tag = utf8.decode(
          Uint8List.sublistView(data, tagStart, valueStart),
          allowMalformed: true,
        );
        final value = utf8.decode(
          Uint8List.sublistView(data, valueStart, end),
          allowMalformed: true,
        );
        return DnsRecord(
          type: 'CAA',
          value: '$flags $tag "${_escapeQuoted(value)}"',
          ttl: ttl,
        );
      default:
        return null;
    }
  }

  static ({String name, int next}) _readName(Uint8List data, int offset) {
    final labels = <String>[];
    final visited = <int>{};
    var cursor = offset;
    var next = -1;
    var jumps = 0;

    while (true) {
      if (cursor >= data.length) {
        throw const FormatException('Truncated DNS name');
      }
      final length = data[cursor];
      if (length == 0) {
        cursor += 1;
        if (next < 0) {
          next = cursor;
        }
        break;
      }
      if ((length & 0xC0) == 0xC0) {
        if (cursor + 1 >= data.length) {
          throw const FormatException('Truncated DNS compression pointer');
        }
        final pointer = ((length & 0x3F) << 8) | data[cursor + 1];
        if (next < 0) {
          next = cursor + 2;
        }
        if (pointer >= data.length || !visited.add(pointer)) {
          throw const FormatException('DNS compression loop');
        }
        cursor = pointer;
        jumps += 1;
        if (jumps > 64) {
          throw const FormatException('DNS compression loop');
        }
        continue;
      }
      if ((length & 0xC0) != 0) {
        throw const FormatException('Unsupported DNS label type');
      }
      final labelEnd = cursor + 1 + length;
      if (labelEnd > data.length) {
        throw const FormatException('Truncated DNS label');
      }
      labels.add(
        utf8.decode(
          Uint8List.sublistView(data, cursor + 1, labelEnd),
          allowMalformed: true,
        ),
      );
      cursor = labelEnd;
      if (labels.length > 128) {
        throw const FormatException('DNS name has too many labels');
      }
    }
    return (name: labels.join('.'), next: next);
  }

  static int _readU16(Uint8List data, int offset) {
    if (offset + 2 > data.length) {
      throw const FormatException('Truncated DNS message');
    }
    return (data[offset] << 8) | data[offset + 1];
  }

  static int _readU32(Uint8List data, int offset) {
    if (offset + 4 > data.length) {
      throw const FormatException('Truncated DNS message');
    }
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  static List<int> _be16(int value) {
    return [(value >> 8) & 0xFF, value & 0xFF];
  }

  static List<int>? _ipv4Parts(String value) {
    final parts = value.split('.');
    if (parts.length != 4) {
      return null;
    }
    final numbers = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 3 || int.tryParse(part) == null) {
        return null;
      }
      final number = int.parse(part);
      if (number > 255) {
        return null;
      }
      numbers.add(number);
    }
    return numbers;
  }

  static String _formatIpv6(Uint8List bytes) {
    final groups = <int>[];
    for (var i = 0; i < 16; i += 2) {
      groups.add((bytes[i] << 8) | bytes[i + 1]);
    }

    var bestStart = -1;
    var bestLength = 0;
    var index = 0;
    while (index < groups.length) {
      if (groups[index] != 0) {
        index += 1;
        continue;
      }
      var end = index;
      while (end < groups.length && groups[end] == 0) {
        end += 1;
      }
      if (end - index > bestLength) {
        bestStart = index;
        bestLength = end - index;
      }
      index = end;
    }

    String hex(int value) => value.toRadixString(16);
    if (bestLength < 2) {
      return groups.map(hex).join(':');
    }
    final left = groups.sublist(0, bestStart).map(hex).join(':');
    final right = groups.sublist(bestStart + bestLength).map(hex).join(':');
    return '$left::$right';
  }

  static String _dotted(String name) {
    return name.isEmpty ? '.' : '$name.';
  }

  static String _escapeQuoted(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
}
