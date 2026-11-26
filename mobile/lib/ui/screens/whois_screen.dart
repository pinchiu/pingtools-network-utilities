import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/whois_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../tool_registry.dart';
import '../theme.dart';
import '../widgets.dart';

const String _historyKey = 'whois';
const int _rawPreviewLimit = 6000;
const int _fieldsPreviewLimit = 24;

enum WhoisSummaryKind {
  registrar,
  created,
  updated,
  expires,
  nameServers,
  status,
  registrantOrganization,
}

class WhoisSummaryItem {
  final WhoisSummaryKind kind;
  final List<String> values;

  const WhoisSummaryItem(this.kind, this.values);
}

/// Presentation state for the WHOIS tool.
class WhoisViewModel extends ChangeNotifier {
  WhoisViewModel() {
    _recent = AppSettings.instance.recent(_historyKey);
  }

  bool _loading = false;
  WhoisResult? _result;
  String? _error;
  List<WhoisSummaryItem> _summary = const [];
  List<WhoisField> _details = const [];
  List<String> _recent = const [];
  int _requestId = 0;
  bool _disposed = false;

  bool get loading => _loading;
  WhoisResult? get result => _result;
  String? get error => _error;
  List<WhoisSummaryItem> get summary => _summary;
  List<WhoisField> get details => _details;
  List<String> get recent => _recent;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  Future<void> lookup(String input) async {
    if (_loading) return;
    final query = normalizeHost(input);
    if (query.isEmpty) {
      _error = 'empty';
      _notify();
      return;
    }
    _loading = true;
    _error = null;
    _result = null;
    _summary = const [];
    _details = const [];
    _notify();
    final id = ++_requestId;
    WhoisResult? result;
    try {
      result = await WhoisEngine.lookup(query);
    } catch (_) {
      result = null;
    }
    if (_disposed || id != _requestId) return;
    _loading = false;
    if (result == null) {
      _error = 'network';
      _notify();
      return;
    }
    _result = result;
    _error = result.error;
    final parsed = _parse(result.fields);
    _summary = parsed.summary;
    _details = parsed.details;
    _notify();
    if (result.error == null) await _remember(query);
  }

  Future<void> _remember(String value) async {
    try {
      await AppSettings.instance.addRecent(_historyKey, value);
    } catch (_) {
      return;
    }
    if (_disposed) return;
    _recent = AppSettings.instance.recent(_historyKey);
    _notify();
  }

  static ({List<WhoisSummaryItem> summary, List<WhoisField> details}) _parse(
    List<WhoisField> fields,
  ) {
    final grouped = <WhoisSummaryKind, List<({String key, String value})>>{};
    final details = <WhoisField>[];
    for (final field in fields) {
      final key = _normalizeKey(field.key);
      final kind = _kindFor(key);
      final value = field.value.trim();
      if (kind == null) {
        if (value.isNotEmpty) details.add(field);
        continue;
      }
      if (value.isEmpty) continue;
      final values = grouped.putIfAbsent(kind, () => []);
      if (values.any((entry) => entry.value == value)) continue;
      values.add((key: key, value: value));
    }

    final summary = <WhoisSummaryItem>[];
    for (final kind in WhoisSummaryKind.values) {
      final all = grouped[kind];
      if (all == null || all.isEmpty) continue;
      // Registry replies are appended after the IANA bootstrap, and explicit
      // registry keys are preferred over the bootstrap's generic ones.
      final preferred = all
          .where((entry) => _isPreferredKey(kind, entry.key))
          .toList();
      // IANA's bootstrap reply also contains an "organisation" field for the
      // registry itself; never present that as the registrant's organisation.
      if (kind == WhoisSummaryKind.registrantOrganization &&
          preferred.isEmpty) {
        continue;
      }
      final selected = preferred.isNotEmpty ? preferred : all;
      final limit =
          kind == WhoisSummaryKind.nameServers ||
              kind == WhoisSummaryKind.status
          ? 8
          : 2;
      final start = selected.length > limit ? selected.length - limit : 0;
      summary.add(
        WhoisSummaryItem(kind, [
          for (final entry in selected.skip(start)) entry.value,
        ]),
      );
    }
    return (summary: summary, details: details);
  }

  static bool _isPreferredKey(WhoisSummaryKind kind, String key) {
    switch (kind) {
      case WhoisSummaryKind.registrar:
        return key == 'registrar' ||
            key == 'registrar name' ||
            key == 'sponsoring registrar';
      case WhoisSummaryKind.created:
        return key.contains('creation') ||
            key.contains('created on') ||
            key.contains('registered on') ||
            key.contains('registration time') ||
            key.contains('registration date') ||
            key.contains('regdate') ||
            key.contains('reg date');
      case WhoisSummaryKind.updated:
        return key.contains('updated') ||
            key.contains('last modified') ||
            key.contains('last update');
      case WhoisSummaryKind.expires:
        return key.contains('expir') || key.contains('renewal date');
      case WhoisSummaryKind.nameServers:
        return key.contains('name server') ||
            key == 'nameserver' ||
            key == 'nserver';
      case WhoisSummaryKind.status:
        return key.contains('domain status') || key == 'domain state';
      case WhoisSummaryKind.registrantOrganization:
        return key.contains('registrant') ||
            key == 'orgname' ||
            key == 'org name' ||
            key == 'organization';
    }
  }

  static String _normalizeKey(String key) => key
      .toLowerCase()
      .replaceAll(RegExp(r'[_\s-]+'), ' ')
      .replaceAll(':', '')
      .trim();

  static WhoisSummaryKind? _kindFor(String key) {
    if (key.contains('registrant') &&
        (key.contains('organi') ||
            key.contains('organization') ||
            key.contains(' org'))) {
      return WhoisSummaryKind.registrantOrganization;
    }
    if (key == 'orgname' || key == 'org name' || key == 'organization') {
      return WhoisSummaryKind.registrantOrganization;
    }
    if (key == 'registrar' ||
        key == 'registrar name' ||
        key == 'sponsoring registrar' ||
        key.contains('registrar company')) {
      return WhoisSummaryKind.registrar;
    }
    if (key.contains('creation') ||
        key == 'created' ||
        key.contains('created on') ||
        key == 'registered' ||
        key == 'regdate' ||
        key == 'reg date' ||
        key.contains('registration date') ||
        key.contains('registration time') ||
        key.contains('registered on')) {
      return WhoisSummaryKind.created;
    }
    if (key.contains('updated') ||
        key.contains('last modified') ||
        key.contains('last update') ||
        key == 'modified') {
      return WhoisSummaryKind.updated;
    }
    if (key.contains('expir') ||
        key.contains('renewal date') ||
        key == 'expire') {
      return WhoisSummaryKind.expires;
    }
    if (key == 'name server' ||
        key == 'name servers' ||
        key == 'nameserver' ||
        key == 'nserver' ||
        key.contains('name server')) {
      return WhoisSummaryKind.nameServers;
    }
    if (key.contains('domain status') ||
        key == 'status' ||
        key == 'state' ||
        key == 'domain state') {
      return WhoisSummaryKind.status;
    }
    return null;
  }
}

class WhoisScreen extends StatefulWidget {
  const WhoisScreen({super.key});

  @override
  State<WhoisScreen> createState() => _WhoisScreenState();
}

class _WhoisScreenState extends State<WhoisScreen> {
  final WhoisViewModel _vm = WhoisViewModel();
  final TextEditingController _query = TextEditingController(
    text: AppSettings.instance.inputOrDefault('whois', 'example.com'),
  );
  Timer? _copiedTimer;
  bool _copied = false;
  bool _rawExpanded = false;
  bool _showAllFields = false;

  Color get _accent => adaptiveAccent(context, toolById('whois')!.accent);

  @override
  void dispose() {
    _copiedTimer?.cancel();
    unawaited(AppSettings.instance.rememberInputNow('whois', _query.text));
    _query.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _run(String value) {
    FocusScope.of(context).unfocus();
    unawaited(AppSettings.instance.rememberInputNow('whois', value));
    _vm.lookup(value);
  }

  void _flashCopied() {
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  Future<void> _copyRaw(WhoisResult result) async {
    try {
      await Clipboard.setData(ClipboardData(text: result.raw));
    } catch (_) {
      return;
    }
    HapticFeedback.selectionClick();
    _flashCopied();
  }

  String _errorText(BuildContext context, String? error) {
    if (error == null) return '';
    if (error.toLowerCase().contains('timeout') ||
        error.toLowerCase().contains('timed out')) {
      return context.tr(
        'The WHOIS server took too long to respond.',
        'WHOIS 伺服器回應逾時。',
      );
    }
    if (error.contains('Enter a valid')) {
      return context.tr(
        'Enter a valid domain or IP address.',
        '請輸入有效的網域或 IP 位址。',
      );
    }
    if (error.startsWith('No WHOIS server found')) {
      return context.tr(
        'No WHOIS server is listed for this top-level domain.',
        '此頂級網域沒有列出 WHOIS 伺服器。',
      );
    }
    if (error.startsWith('No WHOIS referral found')) {
      return context.tr(
        'No WHOIS referral is available for this address.',
        '此位址沒有可用的 WHOIS 轉介資訊。',
      );
    }
    if (error.startsWith('No WHOIS server responded')) {
      return context.tr('The WHOIS server did not respond.', 'WHOIS 伺服器沒有回應。');
    }
    if (error.toLowerCase().contains('connection failed')) {
      return context.tr(
        'Could not connect to the WHOIS server.',
        '無法連線到 WHOIS 伺服器。',
      );
    }
    switch (error) {
      case 'empty':
        return context.tr('Enter a domain or IP address.', '請輸入網域或 IP 位址。');
      case 'network':
        return context.tr(
          'Network error — check your connection and try again.',
          '網路錯誤 — 請檢查連線後再試一次。',
        );
      default:
        return error;
    }
  }

  String _summaryLabel(BuildContext context, WhoisSummaryKind kind) {
    switch (kind) {
      case WhoisSummaryKind.registrar:
        return context.tr('Registrar', '註冊商');
      case WhoisSummaryKind.created:
        return context.tr('Created', '建立日期');
      case WhoisSummaryKind.updated:
        return context.tr('Updated', '更新日期');
      case WhoisSummaryKind.expires:
        return context.tr('Expires', '到期日期');
      case WhoisSummaryKind.nameServers:
        return context.tr('Name servers', '名稱伺服器');
      case WhoisSummaryKind.status:
        return context.tr('Domain status', '網域狀態');
      case WhoisSummaryKind.registrantOrganization:
        return context.tr('Registrant organization', '註冊人組織');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FrostedPage(
      title: context.tr('WHOIS', 'WHOIS 查詢'),
      subtitle: context.tr('Domain & IP registration', '網域與 IP 註冊資訊'),
      child: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final result = _vm.result;
          final error = _vm.error;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppField(
                      label: context.tr('Domain or IP', '網域或 IP'),
                      controller: _query,
                      placeholder: 'example.com',
                      monospace: true,
                      enabled: !_vm.loading,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        AppSettings.instance.rememberInput('whois', value);
                        _vm.clearError();
                      },
                      suffix: CupertinoButton(
                        padding: const EdgeInsets.only(right: 10, left: 4),
                        onPressed: _vm.loading ? null : () => _run(_query.text),
                        child: Icon(
                          CupertinoIcons.arrow_right_circle_fill,
                          size: 22,
                          color: _accent,
                          semanticLabel: context.tr(
                            'Look up WHOIS',
                            '查詢 WHOIS',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: context.tr('Lookup', '查詢'),
                      icon: CupertinoIcons.search,
                      loading: _vm.loading,
                      onPressed: _vm.loading ? null : () => _run(_query.text),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                ErrorBanner(_errorText(context, error)),
                const SizedBox(height: 12),
              ],
              if (_vm.loading)
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const CupertinoActivityIndicator(radius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr(
                            'Looking up registration data…',
                            '正在查詢註冊資料…',
                          ),
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              if (result != null && !_vm.loading) ...[
                if (result.server.isNotEmpty ||
                    result.raw.isNotEmpty ||
                    result.fields.isNotEmpty)
                  _ResultHeader(result: result, accent: _accent),
                if (_vm.summary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionLabel(context.tr('Summary', '摘要')),
                  const SizedBox(height: 8),
                  AppCard(
                    color: _accent.withValues(alpha: p.isDark ? 0.10 : 0.06),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _vm.summary.length; i++) ...[
                          if (i > 0) ...[
                            const SizedBox(height: 12),
                            DividerLine(color: _accent.withValues(alpha: 0.18)),
                            const SizedBox(height: 10),
                          ],
                          _SummaryBlock(
                            label: _summaryLabel(context, _vm.summary[i].kind),
                            values: _vm.summary[i].values,
                            accent: _accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (_vm.details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionLabel(
                    context.tr('Domain fields', '網域欄位'),
                    trailing: Text(
                      '${_vm.details.length}',
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      children: [
                        for (final field
                            in _showAllFields
                                ? _vm.details
                                : _vm.details.take(_fieldsPreviewLimit))
                          DataRow(field.key, field.value),
                        if (_vm.details.length > _fieldsPreviewLimit) ...[
                          const SizedBox(height: 10),
                          AppButton(
                            label: _showAllFields
                                ? context.tr('Show fewer fields', '收起欄位')
                                : context.tr(
                                    'Show all ${_vm.details.length} fields',
                                    '顯示全部 ${_vm.details.length} 個欄位',
                                  ),
                            secondary: true,
                            onPressed: () => setState(
                              () => _showAllFields = !_showAllFields,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (result.raw.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionLabel(context.tr('Raw response', '原始回應')),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.doc_plaintext,
                              size: 18,
                              color: _accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('WHOIS text', 'WHOIS 文字'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                _copied
                                    ? context.tr('Copied', '已複製')
                                    : context.tr('Copy', '複製'),
                                style: TextStyle(
                                  color: _copied ? p.success : p.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _copyRaw(result),
                              child: Icon(
                                CupertinoIcons.doc_on_doc,
                                size: 18,
                                color: p.muted,
                                semanticLabel: context.tr(
                                  'Copy raw WHOIS',
                                  '複製原始 WHOIS',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  setState(() => _rawExpanded = !_rawExpanded),
                              child: Icon(
                                _rawExpanded
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 16,
                                color: p.muted,
                                semanticLabel: _rawExpanded
                                    ? context.tr('Hide raw response', '收起源始回應')
                                    : context.tr('Show raw response', '顯示原始回應'),
                              ),
                            ),
                          ],
                        ),
                        if (_rawExpanded) ...[
                          const SizedBox(height: 10),
                          DividerLine(color: p.border.withValues(alpha: 0.6)),
                          const SizedBox(height: 10),
                          Text(
                            result.raw.length > _rawPreviewLimit
                                ? result.raw.substring(0, _rawPreviewLimit)
                                : result.raw,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 11,
                              height: 1.45,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (result.raw.length > _rawPreviewLimit) ...[
                            const SizedBox(height: 8),
                            Text(
                              context.tr(
                                'Preview truncated — copy to get the full text.',
                                '預覽已截斷 — 複製以取得完整內容。',
                              ),
                              style: TextStyle(
                                color: p.warning,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
                if (_vm.summary.isEmpty &&
                    _vm.details.isEmpty &&
                    result.error == null &&
                    result.raw.trim().isEmpty) ...[
                  const SizedBox(height: 8),
                  EmptyState(
                    icon: CupertinoIcons.search,
                    title: context.tr('No registration data', '沒有註冊資料'),
                    body: context.tr(
                      'The server returned an empty response for this query.',
                      '伺服器未回傳此查詢的任何資料。',
                    ),
                  ),
                ],
              ],
              if (result == null && !_vm.loading && error == null) ...[
                const SizedBox(height: 8),
                EmptyState(
                  icon: CupertinoIcons.search,
                  title: context.tr('Look up a domain or IP', '查詢網域或 IP'),
                  body: context.tr(
                    'See registrar, dates, name servers and the raw WHOIS response.',
                    '查看註冊商、日期、名稱伺服器與原始 WHOIS 回應。',
                  ),
                ),
              ],
              if (_vm.recent.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionLabel(context.tr('Recent', '最近查詢')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in _vm.recent.take(5))
                      SpringyTap(
                        onTap: _vm.loading
                            ? null
                            : () {
                                _query.text = item;
                                _run(item);
                              },
                        child: Pill(item, color: _accent),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final WhoisResult result;
  final Color accent;

  const _ResultHeader({required this.result, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Query', '查詢').toUpperCase(),
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 3),
                    MonoText(
                      result.query,
                      size: 19,
                      weight: FontWeight.w600,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Pill('WHOIS', color: accent),
            ],
          ),
          const SizedBox(height: 12),
          CopyRow(
            label: context.tr('WHOIS server', 'WHOIS 伺服器'),
            value: result.server,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: context.tr('Duration', '耗時'),
                  value: formatDuration(result.durationMs),
                  accent: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: context.tr('Fields', '欄位'),
                  value: '${result.fields.length}',
                  accent: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  final String label;
  final List<String> values;
  final Color accent;

  const _SummaryBlock({
    required this.label,
    required this.values,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              value,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.text,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
