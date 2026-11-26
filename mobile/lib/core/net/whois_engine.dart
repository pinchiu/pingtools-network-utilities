import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pingtools/core/models.dart';
import 'package:pingtools/core/util/format.dart';

/// Raw WHOIS (TCP port 43) client with IANA bootstrap and referral following.
class WhoisEngine {
  WhoisEngine._();

  static const Duration _timeout = Duration(seconds: 8);
  static const int _maxBytes = 512 * 1024;
  static const int _maxFields = 200;
  static const int _maxReferrals = 2;
  static const String _ianaServer = 'whois.iana.org';

  static Future<WhoisResult> lookup(String query) async {
    final stopwatch = Stopwatch()..start();
    var normalized = query.trim();
    var server = '';
    var attemptedServer = '';
    var raw = '';
    var hasLookupData = false;
    final fields = <WhoisField>[];

    if (normalized.isEmpty) {
      return const WhoisResult(
        query: '',
        server: '',
        error: 'Enter a domain or IP address',
      );
    }

    try {
      final target = _normalizeTarget(normalized);
      if (target == null) {
        return WhoisResult(
          query: normalized,
          server: '',
          durationMs: stopwatch.elapsedMilliseconds,
          error: 'Enter a valid domain or IP address',
        );
      }
      normalized = target.value;

      attemptedServer = _ianaServer;
      final bootstrapQuery = target.isDomain ? _tldOf(normalized) : normalized;
      final bootstrap = await _query(attemptedServer, bootstrapQuery);
      server = attemptedServer;
      raw = bootstrap;
      final bootstrapFields = _parseFields(bootstrap);

      var nextServer = _findReferral(bootstrapFields, attemptedServer) ?? '';
      if (nextServer.isEmpty) {
        return WhoisResult(
          query: normalized,
          server: server,
          raw: raw,
          fields: fields,
          durationMs: stopwatch.elapsedMilliseconds,
          error: target.isDomain
              ? 'No WHOIS server found for .${_tldOf(normalized)}'
              : 'No WHOIS referral found for $normalized',
        );
      }

      final visited = <String>{_ianaServer};
      var followUps = 0;
      while (true) {
        if (!visited.add(nextServer.toLowerCase())) {
          break;
        }
        attemptedServer = nextServer;
        raw = await _query(attemptedServer, normalized);
        server = attemptedServer;
        hasLookupData = true;

        final parsed = _parseFields(raw);
        _mergeFields(fields, parsed);

        if (followUps >= _maxReferrals) {
          break;
        }
        final following = _findReferral(parsed, server);
        if (following == null) {
          break;
        }
        followUps += 1;
        nextServer = following;
      }

      if (!hasLookupData) {
        return WhoisResult(
          query: normalized,
          server: server,
          raw: raw,
          fields: fields,
          durationMs: stopwatch.elapsedMilliseconds,
          error: 'No WHOIS server responded',
        );
      }

      return WhoisResult(
        query: normalized,
        server: server,
        raw: raw,
        fields: fields,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      if (hasLookupData) {
        // The registry (or an earlier referral) answered; a failed optional
        // referral should not discard the data we already have.
        return WhoisResult(
          query: normalized,
          server: server,
          raw: raw,
          fields: fields,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      return WhoisResult(
        query: normalized,
        server: attemptedServer.isNotEmpty ? attemptedServer : server,
        durationMs: stopwatch.elapsedMilliseconds,
        error: _messageFor(error),
      );
    }
  }

  static ({String value, bool isDomain})? _normalizeTarget(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return null;
    }
    if (InternetAddress.tryParse(value) != null) {
      return (value: value, isDomain: false);
    }

    value = normalizeHost(value);
    if (value.isEmpty) {
      return null;
    }
    if (InternetAddress.tryParse(value) != null) {
      return (value: value, isDomain: false);
    }

    if (value.length > 253 || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      return null;
    }
    final labels = value.split('.');
    if (labels.any((label) => label.isEmpty || label.length > 63)) {
      return null;
    }
    return (value: value.toLowerCase(), isDomain: true);
  }

  static String _tldOf(String domain) {
    final labels = domain.split('.');
    return labels.isEmpty ? domain : labels.last;
  }

  static Future<String> _query(String server, String query) async {
    Socket? socket;
    StreamSubscription<Uint8List>? subscription;
    try {
      socket = await Socket.connect(server, 43, timeout: _timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.write('$query\r\n');
      await socket.flush().timeout(_timeout);

      final builder = BytesBuilder(copy: false);
      final completer = Completer<void>();
      var received = 0;

      subscription = socket.listen(
        (chunk) {
          if (received >= _maxBytes) {
            return;
          }
          final remaining = _maxBytes - received;
          if (chunk.length <= remaining) {
            builder.add(chunk);
            received += chunk.length;
          } else {
            builder.add(chunk.sublist(0, remaining));
            received = _maxBytes;
          }
          if (received >= _maxBytes) {
            socket?.destroy();
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) {
            completer.completeError(error, stack);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      await completer.future.timeout(_timeout);
      return latin1.decode(builder.takeBytes(), allowInvalid: true);
    } finally {
      await subscription?.cancel();
      socket?.destroy();
    }
  }

  static List<WhoisField> _parseFields(String raw) {
    final fields = <WhoisField>[];
    var lastIndex = -1;

    void appendContinuation(String text) {
      if (lastIndex < 0 || text.isEmpty) {
        return;
      }
      final previous = fields[lastIndex];
      fields[lastIndex] = WhoisField(
        previous.key,
        previous.value.isEmpty ? text : '${previous.value} $text',
      );
    }

    for (final rawLine in const LineSplitter().convert(raw)) {
      if (fields.length >= _maxFields) {
        break;
      }
      final left = rawLine.trimLeft();
      if (left.isEmpty) {
        lastIndex = -1;
        continue;
      }
      if (left.startsWith('%') ||
          left.startsWith('#') ||
          left.startsWith('>>>')) {
        lastIndex = -1;
        continue;
      }

      final indented = rawLine.startsWith(' ') || rawLine.startsWith('\t');
      final looksLikeField = _looksLikeField(left);

      // Many registries indent every field. Only indented text without a
      // plausible "Key:" prefix is a continuation of the previous value.
      if (indented && lastIndex >= 0 && !looksLikeField) {
        appendContinuation(left.trim());
        continue;
      }

      final colon = left.indexOf(':');
      if (colon <= 0) {
        if (indented && lastIndex >= 0) {
          appendContinuation(left.trim());
        } else {
          lastIndex = -1;
        }
        continue;
      }
      final key = left.substring(0, colon).trim();
      final value = left.substring(colon + 1).trim();
      if (!looksLikeField ||
          key.isEmpty ||
          key.length > 64 ||
          key.toLowerCase() == 'http' ||
          key.toLowerCase() == 'https') {
        if (indented && lastIndex >= 0) {
          appendContinuation(left.trim());
        } else {
          lastIndex = -1;
        }
        continue;
      }
      fields.add(WhoisField(key, value));
      lastIndex = fields.length - 1;
    }

    return fields
        .where((field) => field.value.isNotEmpty)
        .take(_maxFields)
        .toList(growable: false);
  }

  static bool _looksLikeField(String line) {
    return RegExp(r'^[A-Za-z][A-Za-z0-9 /_.-]{0,63}:').hasMatch(line);
  }

  static void _mergeFields(List<WhoisField> target, List<WhoisField> source) {
    final seen = target
        .map(
          (field) =>
              '${field.key.toLowerCase()}\u0000'
              '${field.value.toLowerCase()}',
        )
        .toSet();
    for (final field in source) {
      if (target.length >= _maxFields) {
        break;
      }
      final id =
          '${field.key.toLowerCase()}\u0000'
          '${field.value.toLowerCase()}';
      if (seen.add(id)) {
        target.add(field);
      }
    }
  }

  static String? _findReferral(List<WhoisField> fields, String currentServer) {
    const keys = [
      'refer',
      'referralserver',
      'registrar whois server',
      'whois server',
      'whois',
    ];
    for (final key in keys) {
      for (final field in fields) {
        if (field.key.toLowerCase() != key) {
          continue;
        }
        final host = _cleanServer(field.value);
        if (host != null && host.toLowerCase() != currentServer.toLowerCase()) {
          return host;
        }
      }
    }
    return null;
  }

  static String? _cleanServer(String value) {
    var text = value.trim();
    if (text.isEmpty) {
      return null;
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('rwhois://') ||
        lower.startsWith('http://') ||
        lower.startsWith('https://')) {
      return null;
    }
    if (!text.contains('://')) {
      text = 'whois://$text';
    }

    final uri = Uri.tryParse(text);
    var host = uri?.host ?? '';
    if (host.isEmpty || host.contains(' ')) {
      host = value.trim().split(RegExp(r'[\s/]+')).first;
      if (host.contains(':')) {
        host = host.split(':').first;
      }
    }
    host = host.trim();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty ||
        host.contains(' ') ||
        host.contains('@') ||
        (!host.contains('.') && host != 'localhost') ||
        !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host)) {
      return null;
    }
    return host;
  }

  static String _messageFor(Object error) {
    if (error is TimeoutException) {
      return 'WHOIS server timed out';
    }
    if (error is SocketException) {
      final reason = error.osError?.message ?? error.message;
      return 'WHOIS connection failed: $reason';
    }
    if (error is FormatException) {
      return 'WHOIS query failed: ${error.message}';
    }
    return 'WHOIS lookup failed: $error';
  }
}
