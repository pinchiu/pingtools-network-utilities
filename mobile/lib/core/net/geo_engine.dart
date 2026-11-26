import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/util/format.dart';

/// Public-IP geolocation using ipwho.is with an ipapi.co fallback.
class GeoEngine {
  GeoEngine._();

  static const Duration _timeout = Duration(seconds: 8);
  static const String _userAgent = 'PingTools/2.0';
  static const int _maxBodyBytes = 256 * 1024;

  static Future<PublicIpInfo> publicIp() async {
    final primary = await _fetchIpwho('https://ipwho.is/');
    if (primary != null) {
      return primary;
    }
    final fallback = await _fetchIpapi('https://ipapi.co/json/');
    if (fallback != null) {
      return fallback;
    }
    return const PublicIpInfo(error: 'Unable to fetch public IP information');
  }

  static Future<PublicIpInfo> lookup(String ip) async {
    final input = ip.trim();
    if (input.isEmpty) {
      return const PublicIpInfo(error: 'Enter an IP address');
    }
    final address = InternetAddress.tryParse(input);
    if (address == null) {
      return const PublicIpInfo(error: 'Enter a valid IP address');
    }
    if (_isPrivateAddress(address)) {
      return PublicIpInfo(
        ip: input,
        error: 'Private address — no public geolocation',
      );
    }

    final encoded = Uri.encodeComponent(input);
    final primary = await _fetchIpwho(
      'https://ipwho.is/$encoded',
      fallbackIp: input,
    );
    if (primary != null) {
      return primary;
    }
    final fallback = await _fetchIpapi(
      'https://ipapi.co/$encoded/json/',
      fallbackIp: input,
    );
    if (fallback != null) {
      return fallback;
    }
    return PublicIpInfo(ip: input, error: 'Geolocation lookup failed');
  }

  static Future<PublicIpInfo?> _fetchIpwho(
    String url, {
    String? fallbackIp,
  }) async {
    final map = await _getJson(url);
    if (map == null || map['success'] == false) {
      return null;
    }
    final info = _fromIpwho(map, fallbackIp);
    if (info.ip == null || info.ip!.isEmpty) {
      return null;
    }
    return info;
  }

  static Future<PublicIpInfo?> _fetchIpapi(
    String url, {
    String? fallbackIp,
  }) async {
    final map = await _getJson(url);
    if (map == null) {
      return null;
    }
    final error = map['error'];
    if (error == true || (error is String && error.isNotEmpty)) {
      return null;
    }
    final info = _fromIpapi(map, fallbackIp);
    if (info.ip == null || info.ip!.isEmpty) {
      return null;
    }
    return info;
  }

  static PublicIpInfo _fromIpwho(Map<String, dynamic> map, String? fallbackIp) {
    final connection = _mapOf(map['connection']);
    final timezone = _mapOf(map['timezone'])?['id'];
    return PublicIpInfo(
      ip: _string(map['ip']) ?? fallbackIp,
      isp: _string(connection?['isp']),
      org: _string(connection?['org']),
      asn: _asn(connection?['asn']),
      city: _string(map['city']),
      region: _string(map['region']),
      country: _string(map['country']),
      countryCode: _string(map['country_code']),
      lat: _double(map['latitude']),
      lon: _double(map['longitude']),
      timezone: _string(timezone),
    );
  }

  static PublicIpInfo _fromIpapi(Map<String, dynamic> map, String? fallbackIp) {
    final org = _string(map['org']);
    return PublicIpInfo(
      ip: _string(map['ip']) ?? fallbackIp,
      isp: _string(map['isp']) ?? org,
      org: org,
      asn: _asn(map['asn']),
      city: _string(map['city']),
      region: _string(map['region']),
      country: _string(map['country_name']) ?? _string(map['country']),
      countryCode: _string(map['country_code']),
      lat: _double(map['latitude']),
      lon: _double(map['longitude']),
      timezone: _string(map['timezone']),
    );
  }

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      if (response.contentLength > _maxBodyBytes) {
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        builder.add(chunk);
        if (builder.length > _maxBodyBytes) {
          return null;
        }
      }
      final body = utf8.decode(builder.takeBytes(), allowMalformed: true);
      if (body.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static bool _isPrivateAddress(InternetAddress address) {
    if (address.type == InternetAddressType.IPv4) {
      return isPrivateIp(address.address);
    }
    final bytes = address.rawAddress;
    if (bytes.length != 16) {
      return false;
    }
    var allZero = true;
    for (var i = 0; i < 16; i++) {
      if (bytes[i] != 0) {
        allZero = false;
        break;
      }
    }
    if (allZero) {
      return true;
    }
    var loopback = true;
    for (var i = 0; i < 15; i++) {
      if (bytes[i] != 0) {
        loopback = false;
        break;
      }
    }
    if (loopback && bytes[15] == 1) {
      return true;
    }
    if ((bytes[0] & 0xFE) == 0xFC) {
      return true;
    }
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) {
      return true;
    }
    var mapped = true;
    for (var i = 0; i < 10; i++) {
      if (bytes[i] != 0) {
        mapped = false;
        break;
      }
    }
    if (mapped && bytes[10] == 0xFF && bytes[11] == 0xFF) {
      return isPrivateIp('${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}');
    }
    return false;
  }

  static Map<String, dynamic>? _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return null;
  }

  static String? _string(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  static double? _double(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_string(value) ?? '');
  }

  static String? _asn(dynamic value) {
    final text = _string(value);
    if (text == null) {
      return null;
    }
    final upper = text.toUpperCase();
    if (upper.startsWith('AS')) {
      final number = upper.substring(2).trim();
      return number.isEmpty ? null : 'AS$number';
    }
    if (RegExp(r'^\d+$').hasMatch(text)) {
      return 'AS$text';
    }
    return text;
  }
}
