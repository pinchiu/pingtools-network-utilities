import 'dart:math' as math;

import '../models.dart';

String fmtLatency(double ms) {
  if (ms.isNaN || ms.isInfinite) return '--';
  if (ms < 1) return '${ms.toStringAsFixed(2)} ms';
  if (ms < 100) return '${ms.toStringAsFixed(1)} ms';
  return '${ms.toStringAsFixed(0)} ms';
}

String fmtPercent(double value, [int decimals = 1]) {
  return '${value.toStringAsFixed(decimals)}%';
}

String formatBytes(int bytes) {
  if (bytes < 0) return '--';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024.0;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024.0;
    index++;
  }
  return '${value.toStringAsFixed(1)} ${units[index]}';
}

String formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${ms ~/ 60000}m ${((ms % 60000) / 1000).round()}s';
}

String normalizeHost(String input) {
  var host = input.trim();
  if (host.startsWith('http://')) host = host.substring(7);
  if (host.startsWith('https://')) host = host.substring(8);
  host = host.split('/').first.split('?').first.split('#').first;
  if (host.startsWith('[') && host.contains(']')) {
    host = host.substring(1, host.indexOf(']'));
  } else if (':'.allMatches(host).length == 1) {
    host = host.split(':').first;
  }
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  return host.trim();
}

final RegExp _ipv4Pattern = RegExp(
  r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
);

bool isValidIpv4(String value) {
  final match = _ipv4Pattern.firstMatch(value.trim());
  if (match == null) return false;
  for (var i = 1; i <= 4; i++) {
    final part = match.group(i)!;
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return false;
    if (part.length > 1 && part.startsWith('0')) return false;
  }
  return true;
}

bool isPrivateIp(String value) {
  final match = _ipv4Pattern.firstMatch(value.trim());
  if (match == null) return false;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  return a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 169 && b == 254) ||
      a == 127;
}

int? ipv4ToInt(String ip) {
  if (!isValidIpv4(ip)) return null;
  final parts = ip.split('.').map(int.parse).toList();
  return ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) &
      0xFFFFFFFF;
}

String intToIpv4(int value) {
  final v = value & 0xFFFFFFFF;
  return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
}

int prefixMask(int prefix) => (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;

class PortPreset {
  final String label;
  final String spec;
  const PortPreset(this.label, this.spec);
}

const List<PortPreset> portPresets = [
  PortPreset(
    'Top 20',
    '21,22,23,25,53,80,110,139,143,443,445,1433,1521,3306,3389,5432,5900,6379,8080,8443',
  ),
  PortPreset('Web', '80,443,8000,8080,8081,8443,8888'),
  PortPreset('Remote', '22,23,3389,5900,5985,5986'),
  PortPreset('Database', '1433,1521,3306,5432,6379,27017'),
  PortPreset('Full 1-1024', '1-1024'),
];

List<int> parsePortSpec(String spec) {
  final trimmed = spec.trim();
  if (trimmed.isEmpty) throw const FormatException('Enter at least one port');
  final ports = <int>{};
  for (final rawPart in trimmed.split(RegExp(r'[,\s]+'))) {
    final part = rawPart.trim();
    if (part.isEmpty) continue;
    if (part.contains('-')) {
      final bounds = part.split('-');
      if (bounds.length != 2) {
        throw FormatException('Invalid port: $part');
      }
      final start = int.tryParse(bounds[0].trim());
      final end = int.tryParse(bounds[1].trim());
      if (start == null || end == null) {
        throw FormatException('Invalid port: $part');
      }
      if (start > end) {
        throw FormatException('Range start must be <= end: $part');
      }
      if (start < 1 || end > 65535) {
        throw const FormatException('Ports must be 1-65535');
      }
      if (end - start > 4096) {
        throw const FormatException('Range too large (max 4096 ports)');
      }
      for (var p = start; p <= end; p++) {
        ports.add(p);
      }
    } else {
      final port = int.tryParse(part);
      if (port == null) throw FormatException('Invalid port: $part');
      if (port < 1 || port > 65535) {
        throw const FormatException('Ports must be 1-65535');
      }
      ports.add(port);
    }
  }
  if (ports.isEmpty) throw const FormatException('Enter at least one port');
  if (ports.length > 4096) {
    throw const FormatException('Too many ports (max 4096)');
  }
  final sorted = ports.toList()..sort();
  return sorted;
}

const Map<int, String> _serviceNames = {
  7: 'echo',
  9: 'discard',
  20: 'ftp-data',
  21: 'ftp',
  22: 'ssh',
  23: 'telnet',
  25: 'smtp',
  53: 'dns',
  67: 'dhcp',
  69: 'tftp',
  80: 'http',
  110: 'pop3',
  111: 'rpcbind',
  123: 'ntp',
  135: 'msrpc',
  137: 'netbios-ns',
  138: 'netbios-dgm',
  139: 'netbios-ssn',
  143: 'imap',
  161: 'snmp',
  389: 'ldap',
  443: 'https',
  445: 'smb',
  465: 'smtps',
  500: 'isakmp',
  514: 'syslog',
  587: 'submission',
  631: 'ipp',
  636: 'ldaps',
  993: 'imaps',
  995: 'pop3s',
  1080: 'socks',
  1194: 'openvpn',
  1433: 'mssql',
  1521: 'oracle',
  1723: 'pptp',
  1883: 'mqtt',
  2049: 'nfs',
  2375: 'docker',
  3128: 'squid',
  3306: 'mysql',
  3389: 'rdp',
  5060: 'sip',
  5432: 'postgresql',
  5672: 'amqp',
  5900: 'vnc',
  6379: 'redis',
  8000: 'http-alt',
  8080: 'http-proxy',
  8443: 'https-alt',
  8888: 'http-alt',
  9000: 'http-alt',
  9090: 'http-alt',
  9100: 'jetdirect',
  27017: 'mongodb',
};

String serviceNameForPort(int port) => _serviceNames[port] ?? '';

String? normalizeMac(String input) {
  final hex = input.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  if (hex.length != 12) return null;
  final buffer = StringBuffer();
  for (var i = 0; i < 12; i += 2) {
    if (i > 0) buffer.write(':');
    buffer.write(hex.substring(i, i + 2).toUpperCase());
  }
  return buffer.toString();
}

SubnetInfo? parseSubnetInput(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  if (value.contains('/')) {
    final address = value.substring(0, value.indexOf('/'));
    final prefix = int.tryParse(value.substring(value.indexOf('/') + 1));
    if (!isValidIpv4(address) || prefix == null || prefix < 8 || prefix > 30) {
      return null;
    }
    return SubnetInfo(
      cidr: '$address/$prefix',
      localIp: address,
      prefixLength: prefix,
      totalHosts: (1 << (32 - prefix)) - 2,
    );
  }
  final separator = value.indexOf('-');
  if (separator < 0) return null;
  final start = value.substring(0, separator).trim();
  final end = value.substring(separator + 1).trim();
  if (!isValidIpv4(start) || !isValidIpv4(end)) return null;
  final startValue = ipv4ToInt(start);
  final endValue = ipv4ToInt(end);
  if (startValue == null || endValue == null || endValue <= startValue) {
    return null;
  }
  final count = endValue - startValue + 1;
  if (count > 4096) return null;
  var prefix = 32;
  var mask = 0xFFFFFFFF;
  while (prefix > 8 && (startValue & mask) != startValue) {
    prefix--;
    mask = (mask << 1) & 0xFFFFFFFF;
  }
  return SubnetInfo(
    cidr: value,
    localIp: start,
    prefixLength: prefix,
    totalHosts: count,
  );
}

/// Network address + broadcast information for a parsed subnet.
({int network, int broadcast, int prefix}) subnetRange(SubnetInfo info) {
  final value = ipv4ToInt(info.localIp) ?? 0;
  final mask = prefixMask(info.prefixLength);
  final network = value & mask;
  final broadcast = network | ((~mask) & 0xFFFFFFFF);
  return (network: network, broadcast: broadcast, prefix: info.prefixLength);
}

List<String> hostsFor(SubnetInfo info) {
  final raw = info.cidr.trim();
  if (raw.isEmpty) return const [];
  if (raw.contains('/')) {
    final range = subnetRange(info);
    final usable = range.broadcast - range.network - 1;
    if (usable <= 0) return const [];
    final count = math.min(usable, 4096);
    return List.generate(count, (i) => intToIpv4(range.network + i + 1));
  }
  final separator = raw.indexOf('-');
  if (separator < 0) return const [];
  final start = ipv4ToInt(raw.substring(0, separator).trim());
  final end = ipv4ToInt(raw.substring(separator + 1).trim());
  if (start == null || end == null || end < start) return const [];
  final count = math.min(end - start + 1, 4096);
  return List.generate(count, (i) => intToIpv4(start + i));
}
