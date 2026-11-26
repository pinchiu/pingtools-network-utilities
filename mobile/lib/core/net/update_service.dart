import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../native_bridge.dart';

/// GitHub releases based in-app updater.
class UpdateService {
  static const String repository = 'pinchiu/pingtools-network-utilities';
  static const String _apiBase = 'https://api.github.com/repos/$repository/releases/latest';
  static const String _userAgent = 'PingTools/2.0 (Android)';

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 15);

  static Future<UpdateInfo> check() async {
    final current = await NativeBridge.appVersion();
    try {
      final request = await _client.getUrl(Uri.parse(_apiBase));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join().timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) {
        return UpdateInfo(
          currentVersion: current,
          error: 'GitHub API returned ${response.statusCode}',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?)?.trim() ?? '';
      final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
      final notes = (json['body'] as String?)?.trim() ?? '';
      final htmlUrl = json['html_url'] as String?;

      String? apkUrl;
      String? shaUrl;
      final assets = (json['assets'] as List?) ?? const [];
      for (final raw in assets) {
        if (raw is! Map) continue;
        final name = (raw['name'] as String?) ?? '';
        final url = raw['browser_download_url'] as String?;
        if (url == null) continue;
        if (name.toLowerCase().endsWith('.apk')) {
          if (apkUrl == null ||
              name.toLowerCase().contains('flutter') ||
              latest.isNotEmpty && name.contains(latest)) {
            apkUrl = url;
          }
        } else if (name.toLowerCase().endsWith('.sha256')) {
          shaUrl = url;
        }
      }

      final hasUpdate = apkUrl != null && isNewer(latest, current);
      return UpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        tag: tag,
        releaseNotes: notes,
        apkUrl: apkUrl,
        sha256Url: shaUrl,
        htmlUrl: htmlUrl,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      return UpdateInfo(currentVersion: current, error: _friendlyError(e));
    }
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException')) {
      return 'Network unavailable. Check your connection and try again.';
    }
    if (text.contains('TimeoutException')) {
      return 'The update server took too long to respond.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  /// Numeric semver comparison: 2.0.0 > 1.9.9, 2.0.1 > 2.0.0.
  static bool isNewer(String latest, String current) {
    final a = _versionParts(latest);
    final b = _versionParts(current);
    if (a.isEmpty || b.isEmpty) return false;
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int> _versionParts(String version) {
    final cleaned = version.split('+').first.split('-').first.trim();
    if (cleaned.isEmpty) return const [];
    return cleaned
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  static Future<File> download(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
  }) async {
    final url = info.apkUrl;
    if (url == null || url.isEmpty) {
      throw const UpdateException('No APK asset found in the latest release');
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/updates');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final safeVersion = info.latestVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final file = File('${directory.path}/PingTools-$safeVersion.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final request = await _client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw UpdateException('Download failed (HTTP ${response.statusCode})');
    }
    final total = response.contentLength;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && received < total) {
      await file.delete();
      throw const UpdateException('Download was interrupted');
    }
    onProgress(1);

    final expected = await _fetchChecksum(info.sha256Url);
    if (expected != null) {
      final actual = sha256.convert(await file.readAsBytes()).toString();
      if (!actual.toLowerCase().startsWith(expected.toLowerCase())) {
        await file.delete();
        throw const UpdateException('APK checksum verification failed');
      }
    }
    return file;
  }

  static Future<String?> _fetchChecksum(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final text = await response.transform(utf8.decoder).join();
      final match = RegExp(r'[a-fA-F0-9]{64}').firstMatch(text);
      return match?.group(0);
    } catch (_) {
      return null;
    }
  }
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);

  @override
  String toString() => message;
}
