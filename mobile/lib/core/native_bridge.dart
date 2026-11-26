import 'package:flutter/services.dart';

import 'models.dart';

/// Thin wrapper around the Android host channel.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.pinchiu.pingtools/native',
  );

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static Future<ConnectionInfo> connectionInfo() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('connectionInfo');
      final map = _map(raw);
      if (map == null) {
        return const ConnectionInfo(connectionType: 'Unknown');
      }
      final wifiMap = _map(map['wifi']);
      final dns =
          (map['dnsServers'] as List?)?.map((e) => '$e').toList() ??
          const <String>[];
      return ConnectionInfo(
        connectionType: map['connectionType'] as String? ?? 'Unknown',
        localIpv4: map['localIpv4'] as String?,
        localIpv6: map['localIpv6'] as String?,
        prefixLength: (map['prefixLength'] as num?)?.toInt(),
        gateway: map['gateway'] as String?,
        dnsServers: dns,
        mobileOperator: map['mobileOperator'] as String?,
        isVpn: map['isVpn'] == true,
        wifi: wifiMap == null
            ? null
            : WifiDetails(
                ssid: wifiMap['ssid'] as String?,
                bssid: wifiMap['bssid'] as String?,
                rssiDbm: (wifiMap['rssiDbm'] as num?)?.toInt(),
                linkSpeedMbps: (wifiMap['linkSpeedMbps'] as num?)?.toInt(),
                frequencyMhz: (wifiMap['frequencyMhz'] as num?)?.toInt(),
              ),
      );
    } catch (_) {
      return const ConnectionInfo(connectionType: 'Unknown');
    }
  }

  static Future<String> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion') ?? '2.0.0';
    } catch (_) {
      return '2.0.0';
    }
  }

  static Future<bool> requestWifiPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestWifiPermissions') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<InstallOutcome> installApk(String path) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('installApk', {
        'path': path,
      });
      final map = _map(raw);
      final status = map?['status'] as String? ?? 'error';
      final message = map?['message'] as String?;
      switch (status) {
        case 'launched':
          return const InstallOutcome(InstallStatus.launched);
        case 'permissionRequired':
          return InstallOutcome(InstallStatus.permissionRequired, message);
        default:
          return InstallOutcome(
            InstallStatus.error,
            message ?? 'Install failed',
          );
      }
    } catch (e) {
      return InstallOutcome(InstallStatus.error, '$e');
    }
  }
}
