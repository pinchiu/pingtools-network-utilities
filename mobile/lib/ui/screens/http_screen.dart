import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/http_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';

class HttpScreen extends StatefulWidget {
  const HttpScreen({super.key});

  @override
  State<HttpScreen> createState() => _HttpScreenState();
}

class _HttpScreenState extends State<HttpScreen> {
  late final _HttpViewModel _viewModel;
  Timer? _copyTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _viewModel = _HttpViewModel();
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _copyReport(HttpInfo info) async {
    try {
      await Clipboard.setData(ClipboardData(text: _buildReport(info)));
    } catch (_) {
      return;
    }
    HapticFeedback.selectionClick();
    if (!mounted) return;
    _copyTimer?.cancel();
    setState(() => _copied = true);
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAccent(
      context,
      toolById('http')?.accent ?? AppAccents.amber,
    );
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final p = context.palette;
        final result = _viewModel.result;
        return FrostedPage(
          title: context.tr('HTTP Inspector', 'HTTP 檢查器'),
          subtitle: context.tr('Status, headers & TLS', '狀態、標頭與 TLS'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppField(
                      label: context.tr('URL', '網址'),
                      controller: _viewModel.urlController,
                      placeholder: 'https://example.com',
                      monospace: true,
                      keyboardType: TextInputType.url,
                      onChanged: (_) {
                        if (_viewModel.invalidUrl) _viewModel.clearValidation();
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('Follow redirects', '跟隨重新導向'),
                                style: TextStyle(color: p.text, fontSize: 13),
                              ),
                              Text(
                                context.tr(
                                  'Report the final destination',
                                  '回報最終目的地',
                                ),
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label: context.tr('Follow redirects', '跟隨重新導向'),
                          child: SizedBox(
                            height: 44,
                            child: Center(
                              child: CupertinoSwitch(
                                value: _viewModel.followRedirects,
                                activeTrackColor: accent,
                                onChanged: _viewModel.setFollowRedirects,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: context.tr('Inspect', '檢查'),
                      icon: CupertinoIcons.link,
                      loading: _viewModel.loading,
                      onPressed: _viewModel.loading
                          ? null
                          : () => unawaited(_viewModel.inspect()),
                    ),
                  ],
                ),
              ),
              if (_viewModel.history.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionLabel(context.tr('Recent', '最近查詢')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final url in _viewModel.history)
                      _HistoryChip(
                        label: url,
                        accent: accent,
                        onTap: () => _viewModel.useHistory(url),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              if (_viewModel.invalidUrl) ...[
                ErrorBanner(
                  context.tr(
                    'Enter a valid http:// or https:// URL.',
                    '請輸入有效的 http:// 或 https:// 網址。',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_viewModel.errorDetail != null) ...[
                ErrorBanner(
                  context.tr('The request could not be inspected.', '無法檢查此請求。'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2),
                  child: Text(
                    _viewModel.errorDetail!,
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_viewModel.loading)
                AppCard(
                  child: Row(
                    children: [
                      CupertinoActivityIndicator(radius: 8, color: accent),
                      const SizedBox(width: 10),
                      Text(
                        context.tr('Inspecting response…', '正在檢查回應…'),
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else if (result != null)
                _ResultView(
                  info: result,
                  copied: _copied,
                  onCopy: () => unawaited(_copyReport(result)),
                )
              else if (!_viewModel.invalidUrl && _viewModel.errorDetail == null)
                AppCard(
                  child: EmptyState(
                    icon: CupertinoIcons.link,
                    title: context.tr('Ready to inspect', '準備檢查'),
                    body: context.tr(
                      'Enter a URL to see its status, redirects, response headers and security headers.',
                      '輸入網址以查看狀態、重新導向、回應標頭與安全性標頭。',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HttpViewModel extends ChangeNotifier {
  final AppSettings _settings = AppSettings.instance;
  final TextEditingController urlController = TextEditingController(
    text: 'https://example.com',
  );

  List<String> history = [];
  HttpInfo? result;
  bool loading = false;
  bool followRedirects = true;
  bool invalidUrl = false;
  String? errorDetail;
  bool _disposed = false;

  _HttpViewModel() {
    history = _settings.recent('http', limit: 5);
  }

  void setFollowRedirects(bool value) {
    followRedirects = value;
    notifyListeners();
  }

  void clearValidation() {
    if (!invalidUrl) return;
    invalidUrl = false;
    notifyListeners();
  }

  void useHistory(String url) {
    urlController.text = url;
    urlController.selection = TextSelection.collapsed(offset: url.length);
    unawaited(inspect());
  }

  Future<void> inspect() async {
    if (_disposed || loading) return;
    final url = _normalizeUrl(urlController.text);
    if (url == null) {
      invalidUrl = true;
      errorDetail = null;
      result = null;
      notifyListeners();
      return;
    }

    invalidUrl = false;
    errorDetail = null;
    result = null;
    loading = true;
    notifyListeners();
    try {
      final info = await HttpEngine.inspect(
        url,
        followRedirects: followRedirects,
      );
      if (_disposed) return;
      if (info.error != null && info.error!.trim().isNotEmpty) {
        errorDetail = info.error;
      } else {
        result = info;
        try {
          await _settings.addRecent('http', url);
          if (_disposed) return;
          history = _settings.recent('http', limit: 5);
        } catch (_) {
          // History is best-effort and must not hide a valid response.
        }
      }
    } catch (error) {
      if (_disposed) return;
      errorDetail = _detail(error);
    }
    if (_disposed) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    urlController.dispose();
    super.dispose();
  }
}

class _ResultView extends StatelessWidget {
  final HttpInfo info;
  final bool copied;
  final VoidCallback onCopy;

  const _ResultView({
    required this.info,
    required this.copied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = _statusColor(p, info.statusCode);
    final hasTls =
        (info.tlsVersion != null && info.tlsVersion!.isNotEmpty) ||
        (info.tlsCipher != null && info.tlsCipher!.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: status.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: status.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: MonoText(
                  '${info.statusCode}',
                  size: 22,
                  weight: FontWeight.w700,
                  color: status,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.statusMessage.trim().isEmpty
                          ? context.tr('Response', '回應')
                          : info.statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (info.protocol.isNotEmpty) info.protocol,
                        formatDuration(info.durationMs),
                      ].join(' · '),
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Pill(_statusLabel(info.statusCode), color: status),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel(context.tr('Response', '回應')),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CopyRow(
                label: context.tr('Final URL', '最終網址'),
                value: info.finalUrl.isNotEmpty ? info.finalUrl : info.url,
              ),
              if (info.finalUrl.isNotEmpty && info.finalUrl != info.url) ...[
                const SizedBox(height: 8),
                CopyRow(
                  label: context.tr('Requested URL', '請求網址'),
                  value: info.url,
                ),
              ],
              const SizedBox(height: 8),
              DataRow(
                context.tr('Duration', '耗時'),
                formatDuration(info.durationMs),
              ),
              DataRow(
                context.tr('Protocol', '協定'),
                info.protocol.isEmpty ? '—' : info.protocol,
              ),
              DataRow(
                context.tr('Server', '伺服器'),
                info.server == null || info.server!.isEmpty
                    ? '—'
                    : info.server!,
              ),
              DataRow(
                context.tr('Content type', '內容類型'),
                info.contentType == null || info.contentType!.isEmpty
                    ? '—'
                    : info.contentType!,
              ),
              DataRow(
                context.tr('Content length', '內容長度'),
                info.contentLength == null
                    ? '—'
                    : formatBytes(info.contentLength!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel(context.tr('TLS & security', 'TLS 與安全性')),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasTls) ...[
                if (info.tlsVersion != null && info.tlsVersion!.isNotEmpty)
                  DataRow(
                    context.tr('TLS version', 'TLS 版本'),
                    info.tlsVersion!,
                  ),
                if (info.tlsCipher != null && info.tlsCipher!.isNotEmpty)
                  DataRow(
                    context.tr('TLS cipher', 'TLS 加密演算法'),
                    info.tlsCipher!,
                  ),
                if (info.security.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  DividerLine(color: p.border.withValues(alpha: 0.6)),
                  const SizedBox(height: 6),
                ],
              ],
              if (info.security.isEmpty && !hasTls)
                Text(
                  context.tr(
                    'No TLS or security headers were reported. HTTP responses without '
                        'HSTS, CSP or similar headers offer fewer protections.',
                    '未回報 TLS 或安全性標頭。沒有 HSTS、CSP 等標頭的 HTTP 回應保護較少。',
                  ),
                  style: TextStyle(color: p.muted, fontSize: 11, height: 1.4),
                )
              else
                for (final entry in info.security)
                  if (entry.length >= 2)
                    DataRow(
                      _securityLabel(context, entry[0]),
                      _securityValue(context, entry[1]),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel(
          context.tr('Headers', '標頭'),
          trailing: Pill('${info.headers.length}', color: p.primary),
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (info.headers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    context.tr('No headers were returned.', '未傳回任何標頭。'),
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                )
              else
                for (var i = 0; i < info.headers.length; i++) ...[
                  if (i > 0)
                    DividerLine(color: p.border.withValues(alpha: 0.45)),
                  _HeaderRow(
                    name: info.headers[i][0],
                    value: info.headers[i].length > 1 ? info.headers[i][1] : '',
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: copied
              ? context.tr('Copied to clipboard', '已複製到剪貼簿')
              : context.tr('Copy full report', '複製完整報告'),
          icon: copied ? CupertinoIcons.check_mark : CupertinoIcons.doc_on_doc,
          secondary: true,
          onPressed: onCopy,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Includes status, metadata, TLS/security checks and every response header.',
            '包含狀態、中繼資料、TLS/安全性檢查與所有回應標頭。',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 10, height: 1.35),
        ),
      ],
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _HistoryChip({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SpringyTap(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: p.elevated.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border, width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.clock, size: 12, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.text,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String name;
  final String value;

  const _HeaderRow({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toLowerCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: value));
                HapticFeedback.selectionClick();
              } catch (_) {
                // Clipboard access can be unavailable on some platforms.
              }
            },
            child: Icon(
              CupertinoIcons.doc_on_doc,
              size: 14,
              color: p.muted,
              semanticLabel: context.tr('Copy header value', '複製標頭值'),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(AppPalette p, int code) {
  if (code >= 200 && code < 300) return p.success;
  if (code >= 300 && code < 400) return p.warning;
  return p.danger;
}

String _statusLabel(int code) {
  if (code >= 200 && code < 300) return '2xx';
  if (code >= 300 && code < 400) return '3xx';
  if (code >= 400 && code < 500) return '4xx';
  if (code >= 500) return '5xx';
  return '—';
}

String _securityLabel(BuildContext context, String raw) {
  final key = raw.trim().toLowerCase();
  switch (key) {
    case 'hsts':
      return 'HSTS';
    case 'csp':
      return 'CSP';
    case 'x-frame-options':
      return 'X-Frame-Options';
    case 'x-content-type-options':
      return 'X-Content-Type-Options';
    case 'referrer-policy':
      return 'Referrer-Policy';
    case 'permissions-policy':
      return 'Permissions-Policy';
    case 'cleartext':
      return context.tr('Cleartext', '明文傳輸');
    case 'tls certificate':
      return context.tr('TLS certificate', 'TLS 憑證');
    case 'tls valid until':
      return context.tr('TLS valid until', 'TLS 有效期限');
    default:
      return raw;
  }
}

String _securityValue(BuildContext context, String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'present':
    case 'yes':
    case 'true':
      return context.tr('Yes', '是');
    case 'missing':
    case 'no':
    case 'false':
      return context.tr('No', '否');
    case 'enabled':
      return context.tr('Enabled', '已啟用');
    case 'disabled':
      return context.tr('Disabled', '未啟用');
    case 'no — https':
      return context.tr('No — HTTPS', '否 — HTTPS');
    case 'yes — plain http':
      return context.tr('Yes — plain HTTP', '是 — 明文 HTTP');
    default:
      return raw;
  }
}

String? _normalizeUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return value;
}

String _buildReport(HttpInfo info) {
  final buffer = StringBuffer()
    ..writeln('PingTools HTTP report')
    ..writeln('Requested URL: ${info.url}')
    ..writeln('Final URL: ${info.finalUrl}')
    ..writeln('Status: ${info.statusCode} ${info.statusMessage}'.trimRight())
    ..writeln('Protocol: ${info.protocol}')
    ..writeln('Duration: ${formatDuration(info.durationMs)}')
    ..writeln('Server: ${info.server ?? '—'}')
    ..writeln('Content-Type: ${info.contentType ?? '—'}')
    ..writeln(
      'Content-Length: '
      '${info.contentLength == null ? '—' : formatBytes(info.contentLength!)}',
    );
  if (info.tlsVersion != null && info.tlsVersion!.isNotEmpty) {
    buffer.writeln('TLS: ${info.tlsVersion} / ${info.tlsCipher ?? '—'}');
  }
  if (info.security.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Security:');
    for (final entry in info.security) {
      if (entry.length >= 2) buffer.writeln('  ${entry[0]}: ${entry[1]}');
    }
  }
  buffer.writeln();
  buffer.writeln('Headers:');
  for (final header in info.headers) {
    if (header.length >= 2) buffer.writeln('  ${header[0]}: ${header[1]}');
  }
  return buffer.toString();
}

String _detail(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 200 ? '${text.substring(0, 197)}…' : text;
}
