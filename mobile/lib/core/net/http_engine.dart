import 'dart:async';
import 'dart:io';

import 'package:pingtools/core/models.dart';

/// HTTP header inspection without downloading response bodies.
class HttpEngine {
  HttpEngine._();

  static const int _defaultTimeoutMs = 12000;
  static const String _userAgent = 'PingTools/2.0';

  static Future<HttpInfo> inspect(
    String url, {
    bool followRedirects = true,
    int timeoutMs = _defaultTimeoutMs,
  }) async {
    final input = url.trim();
    if (input.isEmpty) {
      return const HttpInfo(url: '', error: 'Enter a URL');
    }
    final effectiveTimeout = timeoutMs > 0 ? timeoutMs : _defaultTimeoutMs;
    final uri = _parseUrl(input);
    if (uri == null) {
      return HttpInfo(
        url: input,
        error: 'Enter a valid http:// or https:// URL',
      );
    }

    final stopwatch = Stopwatch()..start();
    HttpClient? client;
    _Exchange? exchange;
    Object? failure;

    try {
      client = HttpClient()
        ..connectionTimeout = Duration(milliseconds: effectiveTimeout);
      try {
        exchange = await _send(
          client,
          uri,
          'HEAD',
          followRedirects,
          effectiveTimeout,
        );
        final status = exchange.response.statusCode;
        if (status == 403 || status == 405 || status == 501) {
          await _discard(exchange.response);
          exchange = null;
        }
      } catch (error) {
        failure = error;
      }

      if (exchange == null) {
        try {
          exchange = await _send(
            client,
            uri,
            'GET',
            followRedirects,
            effectiveTimeout,
            range: true,
          );
          failure = null;
        } catch (error) {
          failure = error;
        }
      }

      if (exchange == null) {
        return HttpInfo(
          url: input,
          finalUrl: uri.toString(),
          durationMs: stopwatch.elapsedMilliseconds,
          error: _describeError(failure, effectiveTimeout),
        );
      }

      final response = exchange.response;
      final headers = response.headers;
      final certificate = response.certificate;
      final finalUri = _finalUri(exchange.request, response);
      final headerLength = _headerValue(
        headers,
        HttpHeaders.contentLengthHeader,
      );
      final length = response.contentLength;
      final contentLength = length >= 0
          ? length
          : int.tryParse(headerLength ?? '');

      final info = HttpInfo(
        url: input,
        finalUrl: finalUri.toString(),
        statusCode: response.statusCode,
        statusMessage: _reason(response.statusCode, response.reasonPhrase),
        protocol: 'HTTP/1.1',
        server: _headerValue(headers, HttpHeaders.serverHeader),
        contentType: _headerValue(headers, HttpHeaders.contentTypeHeader),
        contentLength: contentLength,
        durationMs: stopwatch.elapsedMilliseconds,
        headers: _headerList(headers),
        security: _securityList(headers, finalUri, certificate),
      );

      await _discard(response);
      return info;
    } catch (error) {
      return HttpInfo(
        url: input,
        finalUrl: uri.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        error: _describeError(error, effectiveTimeout),
      );
    } finally {
      client?.close(force: true);
    }
  }

  static Uri? _parseUrl(String input) {
    try {
      final hasScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://').hasMatch(input);
      final candidate = hasScheme ? input : 'https://$input';
      final uri = Uri.tryParse(candidate);
      if (uri == null || uri.host.isEmpty) {
        return null;
      }
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        return null;
      }
      if (uri.host.contains(RegExp(r'\s'))) {
        return null;
      }
      return uri;
    } catch (_) {
      return null;
    }
  }

  static Future<_Exchange> _send(
    HttpClient client,
    Uri uri,
    String method,
    bool followRedirects,
    int timeoutMs, {
    bool range = false,
  }) async {
    final timeout = Duration(milliseconds: timeoutMs);
    final request = await client.openUrl(method, uri).timeout(timeout);
    request
      ..followRedirects = followRedirects
      ..maxRedirects = 5;
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (range) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    }
    final response = await request.close().timeout(timeout);
    return _Exchange(request, response);
  }

  /// Does not read the body: detaching and destroying the socket makes this
  /// safe even when a server ignores HEAD or the Range request.
  static Future<void> _discard(HttpClientResponse response) async {
    try {
      final socket = await response.detachSocket().timeout(
        const Duration(seconds: 2),
      );
      socket.destroy();
    } catch (_) {
      // The owning HttpClient is force-closed by the caller.
    }
  }

  static Uri _finalUri(HttpClientRequest request, HttpClientResponse response) {
    var finalUri = request.uri;
    for (final redirect in response.redirects) {
      finalUri = finalUri.resolveUri(redirect.location);
    }
    return finalUri;
  }

  static List<List<String>> _headerList(HttpHeaders headers) {
    final result = <List<String>>[];
    headers.forEach((name, values) {
      for (final value in values) {
        result.add([name, value]);
      }
    });
    result.sort((a, b) {
      final byName = a[0].compareTo(b[0]);
      return byName != 0 ? byName : a[1].compareTo(b[1]);
    });
    return result;
  }

  static List<List<String>> _securityList(
    HttpHeaders headers,
    Uri finalUri,
    X509Certificate? certificate,
  ) {
    String headerValue(String name) => _headerValue(headers, name) ?? 'Missing';
    final secure = finalUri.scheme.toLowerCase() == 'https';

    final security = <List<String>>[
      ['HSTS', headerValue('strict-transport-security')],
      ['CSP', headerValue('content-security-policy')],
      ['X-Frame-Options', headerValue('x-frame-options')],
      ['X-Content-Type-Options', headerValue('x-content-type-options')],
      ['Referrer-Policy', headerValue('referrer-policy')],
      ['Permissions-Policy', headerValue('permissions-policy')],
      ['Cleartext', secure ? 'No — HTTPS' : 'Yes — plain HTTP'],
    ];

    if (certificate != null) {
      security.add(['TLS certificate', certificate.subject]);
      security.add(['TLS valid until', _date(certificate.endValidity)]);
    }
    return security;
  }

  static String? _headerValue(HttpHeaders headers, String name) {
    final values = headers[name];
    if (values == null || values.isEmpty) {
      return null;
    }
    return values.join(', ');
  }

  static String _date(DateTime value) {
    final date = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String _reason(int statusCode, String reasonPhrase) {
    if (reasonPhrase.isNotEmpty) {
      return reasonPhrase;
    }
    switch (statusCode) {
      case 200:
        return 'OK';
      case 204:
        return 'No Content';
      case 206:
        return 'Partial Content';
      case 301:
        return 'Moved Permanently';
      case 302:
        return 'Found';
      case 304:
        return 'Not Modified';
      case 307:
        return 'Temporary Redirect';
      case 308:
        return 'Permanent Redirect';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 405:
        return 'Method Not Allowed';
      case 408:
        return 'Request Timeout';
      case 429:
        return 'Too Many Requests';
      case 500:
        return 'Internal Server Error';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      case 504:
        return 'Gateway Timeout';
      default:
        return '';
    }
  }

  static String _describeError(Object? error, int timeoutMs) {
    if (error == null) {
      return 'Request failed';
    }
    if (error is TimeoutException) {
      return 'Request timed out after ${timeoutMs}ms';
    }
    if (error is HandshakeException) {
      return 'TLS handshake failed: ${error.message}';
    }
    if (error is SocketException) {
      final detail = error.osError?.message ?? error.message;
      return 'Connection failed: $detail';
    }
    if (error is HttpException) {
      return 'HTTP error: ${error.message}';
    }
    if (error is FormatException) {
      return 'Invalid URL: ${error.message}';
    }
    return 'Request failed: $error';
  }
}

class _Exchange {
  final HttpClientRequest request;
  final HttpClientResponse response;

  const _Exchange(this.request, this.response);
}
