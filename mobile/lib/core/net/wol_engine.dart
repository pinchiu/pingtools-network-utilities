import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../util/format.dart';

/// Wake-on-LAN magic packet sender.
///
/// Invalid input surfaces as [ArgumentError]; socket and resolution failures
/// surface as [SocketException]. Callers are expected to catch both.
class WolEngine {
  static const int _packetCount = 3;
  static const Duration _packetGap = Duration(milliseconds: 60);

  /// Sends three magic packets to [broadcast] on [port].
  ///
  /// [secureOn] is an optional six-byte SecureOn password in MAC notation.
  static Future<WolOutcome> wake({
    required String mac,
    String broadcast = '255.255.255.255',
    int port = 9,
    String? secureOn,
  }) async {
    final normalizedMac = normalizeMac(mac);
    if (normalizedMac == null) {
      throw ArgumentError.value(mac, 'mac', 'Invalid MAC address');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(
        port,
        'port',
        'Port must be between 1 and 65535',
      );
    }
    final hasSecureOn = secureOn != null && secureOn.trim().isNotEmpty;
    final normalizedSecureOn = hasSecureOn ? normalizeMac(secureOn) : null;
    if (hasSecureOn && normalizedSecureOn == null) {
      throw ArgumentError.value(
        secureOn,
        'secureOn',
        'Invalid SecureOn password',
      );
    }
    final packet = buildMagicPacket(
      normalizedMac,
      secureOn: normalizedSecureOn,
    );
    final target = await _resolveTarget(broadcast);

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      var sent = 0;
      for (var i = 0; i < _packetCount; i++) {
        if (i > 0) {
          await Future<void>.delayed(_packetGap);
        }
        final written = socket.send(packet, target, port);
        if (written != packet.length) {
          throw SocketException(
            'Failed to send magic packet to ${target.address}:$port',
          );
        }
        sent++;
      }

      return WolOutcome(
        mac: normalizedMac,
        address: target.address,
        port: port,
        packetsSent: sent,
      );
    } on SocketException {
      rethrow;
    } catch (error) {
      throw SocketException('Wake-on-LAN failed: $error');
    } finally {
      socket?.close();
    }
  }

  /// Builds `6 × 0xFF + 16 × MAC (+ 6-byte SecureOn password)`.
  @visibleForTesting
  static Uint8List buildMagicPacket(String mac, {String? secureOn}) {
    final normalizedMac = normalizeMac(mac);
    if (normalizedMac == null) {
      throw ArgumentError.value(mac, 'mac', 'Invalid MAC address');
    }
    final hasSecureOn = secureOn != null && secureOn.trim().isNotEmpty;
    final normalizedSecureOn = hasSecureOn ? normalizeMac(secureOn) : null;
    if (hasSecureOn && normalizedSecureOn == null) {
      throw ArgumentError.value(
        secureOn,
        'secureOn',
        'Invalid SecureOn password',
      );
    }

    final macBytes = _macBytes(normalizedMac);
    final passwordBytes = normalizedSecureOn == null
        ? null
        : _macBytes(normalizedSecureOn);
    final packet = Uint8List(6 + 16 * 6 + (passwordBytes?.length ?? 0));

    for (var i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }
    var offset = 6;
    for (var repeat = 0; repeat < 16; repeat++) {
      packet.setRange(offset, offset + 6, macBytes);
      offset += 6;
    }
    if (passwordBytes != null) {
      packet.setRange(offset, offset + 6, passwordBytes);
    }
    return packet;
  }

  static Uint8List _macBytes(String normalizedMac) {
    final parts = normalizedMac.split(':');
    final bytes = Uint8List(parts.length);
    for (var i = 0; i < parts.length; i++) {
      bytes[i] = int.parse(parts[i], radix: 16);
    }
    return bytes;
  }

  /// Resolves an IPv4 literal or host name, preferring IPv4 results.
  static Future<InternetAddress> _resolveTarget(String broadcast) async {
    final host = broadcast.trim();
    if (host.isEmpty) {
      throw ArgumentError.value(
        broadcast,
        'broadcast',
        'Broadcast address is required',
      );
    }

    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      if (literal.type != InternetAddressType.IPv4) {
        throw SocketException('Wake-on-LAN requires an IPv4 broadcast address');
      }
      return literal;
    }

    try {
      final addresses = await InternetAddress.lookup(host);
      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv4) return address;
      }
    } on SocketException {
      rethrow;
    } catch (error) {
      throw SocketException('Unable to resolve $host: $error');
    }
    throw SocketException('No IPv4 address found for $host');
  }
}
