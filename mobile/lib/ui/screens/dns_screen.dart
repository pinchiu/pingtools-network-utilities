import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/dns_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../tool_registry.dart';
import '../widgets.dart';

const String _historyKey = 'dns';

/// Presentation state for the DNS lookup tool.
class DnsViewModel extends ChangeNotifier {
  DnsViewModel() {
    _recent = AppSettings.instance.recent(_historyKey);
  }

  DnsType _type = DnsType.a;
  int _resolverIndex = 0;
  bool _loading = false;
  DnsResult? _result;
  String? _error;
  List<String> _recent = const [];
  int _requestId = 0;
  bool _disposed = false;

  DnsType get type => _type;
  int get resolverIndex => _resolverIndex;
  bool get loading => _loading;
  DnsResult? get result => _result;
  String? get error => _error;
  List<String> get recent => _recent;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setType(DnsType value) {
    if (value == _type) return;
    _type = value;
    _result = null;
    _error = null;
    _notify();
  }

  void setResolver(int index) {
    final count = DnsEngine.resolvers.length;
    final next = count == 0 ? 0 : index.clamp(0, count - 1).toInt();
    if (next == _resolverIndex) return;
    _resolverIndex = next;
    _result = null;
    _error = null;
    _notify();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  String get resolverLabel {
    final resolvers = DnsEngine.resolvers;
    if (resolvers.isEmpty) return 'System';
    return resolvers[_resolverIndex.clamp(0, resolvers.length - 1).toInt()].$1;
  }

  String? get _resolverAddress {
    final resolvers = DnsEngine.resolvers;
    if (resolvers.isEmpty) return null;
    final entry =
        resolvers[_resolverIndex.clamp(0, resolvers.length - 1).toInt()];
    final address = entry.$2;
    return address.isEmpty ? null : address;
  }

  Future<void> lookup(String input) async {
    if (_loading) return;
    final query = normalizeHost(input);
    if (query.isEmpty) {
      _error = 'empty';
      _notify();
      return;
    }
    final type = _type;
    await _run(query: query, type: type, reverse: type == DnsType.ptr);
  }

  Future<void> reverse(String input) async {
    if (_loading) return;
    final query = normalizeHost(input);
    if (query.isEmpty) {
      _error = 'empty';
      _notify();
      return;
    }
    final isIp = isValidIpv4(query) || query.contains(':');
    if (!isIp && !query.endsWith('.arpa')) {
      _error = 'reverseInvalid';
      _notify();
      return;
    }
    await _run(query: query, type: DnsType.ptr, reverse: true);
  }

  Future<void> _run({
    required String query,
    required DnsType type,
    required bool reverse,
  }) async {
    _loading = true;
    _error = null;
    _result = null;
    _notify();
    final id = ++_requestId;
    final resolver = _resolverAddress;
    DnsResult? result;
    try {
      result = reverse
          ? await DnsEngine.reverse(query, resolver: resolver)
          : await DnsEngine.lookup(query, type, resolver: resolver);
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
}

class DnsScreen extends StatefulWidget {
  const DnsScreen({super.key});

  @override
  State<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends State<DnsScreen> {
  final DnsViewModel _vm = DnsViewModel();
  final TextEditingController _query = TextEditingController(
    text: 'example.com',
  );
  Timer? _copiedTimer;
  bool _copied = false;

  Color get _accent => toolById('dns')!.accent;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _query.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _run(String value) {
    FocusScope.of(context).unfocus();
    _vm.lookup(value);
  }

  void _reverse(String value) {
    FocusScope.of(context).unfocus();
    _vm.reverse(value);
  }

  void _runRecent(String value) {
    _query.text = value;
    if (isValidIpv4(value) || value.contains(':')) {
      _reverse(value);
    } else {
      _run(value);
    }
  }

  Future<void> _pickType() async {
    if (_vm.loading) return;
    FocusScope.of(context).unfocus();
    final types = DnsType.values;
    final index = await showFrostedSheet<int>(
      context,
      _PickerSheet(
        title: context.tr('Record type', '紀錄類型'),
        items: [for (final type in types) type.label],
        initialIndex: types.indexOf(_vm.type),
        accent: _accent,
      ),
    );
    if (!mounted || index == null) return;
    _vm.setType(types[index]);
  }

  Future<void> _pickResolver() async {
    if (_vm.loading) return;
    FocusScope.of(context).unfocus();
    final resolvers = DnsEngine.resolvers;
    if (resolvers.isEmpty) return;
    final labels = [
      for (final entry in resolvers)
        entry.$2 == 'system' ? context.tr('System', '系統') : entry.$1,
    ];
    final index = await showFrostedSheet<int>(
      context,
      _PickerSheet(
        title: context.tr('DNS resolver', 'DNS 伺服器'),
        items: labels,
        initialIndex: _vm.resolverIndex,
        accent: _accent,
      ),
    );
    if (!mounted || index == null) return;
    _vm.setResolver(index);
  }

  String _errorText(BuildContext context, String? error) {
    if (error == null) return '';
    if (error.contains('NXDOMAIN')) {
      return context.tr(
        'Domain does not exist (NXDOMAIN).',
        '網域不存在（NXDOMAIN）。',
      );
    }
    if (error.contains('SERVFAIL')) {
      return context.tr(
        'The resolver failed to answer (SERVFAIL).',
        'DNS 伺服器無法回應（SERVFAIL）。',
      );
    }
    final lower = error.toLowerCase();
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return context.tr(
        'The DNS resolver did not respond in time.',
        'DNS 伺服器未及時回應。',
      );
    }
    if (lower.contains('truncated')) {
      return context.tr(
        'The DNS response was truncated — try another resolver.',
        'DNS 回應遭截斷 — 請改用其他伺服器。',
      );
    }
    if (error.contains('Enter a domain name')) {
      return context.tr('Enter a domain or IP address.', '請輸入網域或 IP 位址。');
    }
    if (error.contains('Enter a valid IP address')) {
      return context.tr(
        'Enter a valid IPv4 or IPv6 address for PTR lookup.',
        '請輸入有效的 IPv4 或 IPv6 位址以進行 PTR 查詢。',
      );
    }
    if (lower.contains('network error')) {
      return context.tr(
        'Network error — check your connection and try again.',
        '網路錯誤 — 請檢查連線後再試一次。',
      );
    }
    switch (error) {
      case 'empty':
        return context.tr('Enter a domain or IP address.', '請輸入網域或 IP 位址。');
      case 'reverseInvalid':
        return context.tr(
          'Enter an IPv4, IPv6 or in-addr.arpa address for PTR lookup.',
          '請輸入 IPv4、IPv6 或 in-addr.arpa 位址以進行 PTR 查詢。',
        );
      case 'network':
        return context.tr(
          'Network error — check your connection and try again.',
          '網路錯誤 — 請檢查連線後再試一次。',
        );
      default:
        return error;
    }
  }

  String _resolverValue(BuildContext context) {
    final label = _vm.resolverLabel;
    return label == 'System' ? context.tr('System', '系統') : label;
  }

  String _typeDescription(BuildContext context, DnsType type) {
    switch (type) {
      case DnsType.a:
        return context.tr('IPv4 address', 'IPv4 位址');
      case DnsType.aaaa:
        return context.tr('IPv6 address', 'IPv6 位址');
      case DnsType.cname:
        return context.tr('Canonical name', '正式名稱別名');
      case DnsType.mx:
        return context.tr('Mail exchangers', '郵件伺服器');
      case DnsType.ns:
        return context.tr('Name servers', '名稱伺服器');
      case DnsType.txt:
        return context.tr('Text records', '文字紀錄');
      case DnsType.soa:
        return context.tr('Zone authority', '區域授權');
      case DnsType.srv:
        return context.tr('Service locator', '服務定位');
      case DnsType.caa:
        return context.tr('CA authorization', '憑證授權');
      case DnsType.ptr:
        return context.tr('Reverse pointer', '反解指標');
    }
  }

  String _recordsText(DnsResult result) {
    final buffer = StringBuffer()
      ..writeln(
        '${result.query}  ${result.type.label}  via ${result.resolver}',
      );
    for (final record in result.records) {
      buffer.write('${record.type}\t${record.value}');
      if (record.ttl != null) buffer.write('\t${record.ttl}');
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _copyRecords(DnsResult result) async {
    try {
      await Clipboard.setData(ClipboardData(text: _recordsText(result)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _copied = false);
      return;
    }
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FrostedPage(
      title: context.tr('DNS Lookup', 'DNS 查詢'),
      subtitle: context.tr(
        'A · AAAA · MX · TXT · PTR',
        'A · AAAA · MX · TXT · PTR',
      ),
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
                      onChanged: (_) => _vm.clearError(),
                      suffix: CupertinoButton(
                        padding: const EdgeInsets.only(right: 10, left: 4),
                        onPressed: _vm.loading ? null : () => _run(_query.text),
                        child: Icon(
                          CupertinoIcons.arrow_right_circle_fill,
                          size: 22,
                          color: _accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Chooser(
                            label: context.tr('Type', '類型'),
                            value: _vm.type.label,
                            hint: _typeDescription(context, _vm.type),
                            accent: _accent,
                            onTap: _vm.loading ? null : _pickType,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Chooser(
                            label: context.tr('Resolver', 'DNS 伺服器'),
                            value: _resolverValue(context),
                            hint: context.tr('Tap to change', '點選更換'),
                            accent: _accent,
                            onTap: _vm.loading ? null : _pickResolver,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final lookup = AppButton(
                          label: context.tr('Lookup', '查詢'),
                          icon: CupertinoIcons.search,
                          loading: _vm.loading,
                          onPressed: _vm.loading
                              ? null
                              : () => _run(_query.text),
                        );
                        final reverse = AppButton(
                          label: context.tr('Reverse PTR', '反查 PTR'),
                          secondary: true,
                          onPressed: _vm.loading
                              ? null
                              : () => _reverse(_query.text),
                        );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              lookup,
                              const SizedBox(height: 10),
                              reverse,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: lookup),
                            const SizedBox(width: 10),
                            Expanded(child: reverse),
                          ],
                        );
                      },
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
                          context.tr('Querying DNS…', '正在查詢 DNS…'),
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              if (result != null && !_vm.loading) ...[
                _ResultMeta(result: result, accent: _accent),
                if (result.records.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionLabel(
                    context.tr('Records', '紀錄'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                          onPressed: () => _copyRecords(result),
                          child: Icon(
                            CupertinoIcons.doc_on_doc,
                            size: 18,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < result.records.length; i++) ...[
                          if (i > 0)
                            DividerLine(color: p.border.withValues(alpha: 0.6)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: CopyRow(
                              label: result.records[i].ttl == null
                                  ? result.records[i].type
                                  : '${result.records[i].type} · TTL ${result.records[i].ttl}',
                              value: result.records[i].value,
                              valueColor: p.text,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else if (result.error == null) ...[
                  const SizedBox(height: 8),
                  EmptyState(
                    icon: CupertinoIcons.tray,
                    title: context.tr('No records', '沒有紀錄'),
                    body: context.tr(
                      'The resolver returned an empty answer for this record type.',
                      '此 DNS 伺服器未回傳任何此類型的紀錄。',
                    ),
                  ),
                ],
              ],
              if (result == null && !_vm.loading && error == null) ...[
                const SizedBox(height: 8),
                EmptyState(
                  icon: CupertinoIcons.doc_text_search,
                  title: context.tr('DNS records at a glance', 'DNS 紀錄一目了然'),
                  body: context.tr(
                    'Enter a hostname, choose a record type and resolver, then tap Lookup.',
                    '輸入主機名稱、選擇紀錄類型與 DNS 伺服器，然後點選查詢。',
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
                        onTap: _vm.loading ? null : () => _runRecent(item),
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

class _ResultMeta extends StatelessWidget {
  final DnsResult result;
  final Color accent;

  const _ResultMeta({required this.result, required this.accent});

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
                      context.tr('Result', '結果').toUpperCase(),
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Pill(result.type.label, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(
                result.resolver.startsWith('System')
                    ? result.resolver.replaceFirst(
                        'System',
                        context.tr('System', '系統'),
                      )
                    : result.resolver,
                color: p.muted,
              ),
              Pill(formatDuration(result.durationMs), color: p.muted),
              Pill(
                '${result.records.length} ${context.tr('records', '筆紀錄')}',
                color: p.muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chooser extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color accent;
  final VoidCallback? onTap;

  const _Chooser({
    required this.label,
    required this.value,
    required this.accent,
    this.hint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SpringyTap(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: p.elevated.withValues(alpha: p.isDark ? 0.7 : 0.55),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: p.border, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
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
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 10),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 14, color: accent),
          ],
        ),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final int initialIndex;
  final Color accent;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.initialIndex,
    required this.accent,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late int _index = widget.initialIndex
      .clamp(0, widget.items.length - 1)
      .toInt();
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: _index);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(
      220.0,
      340.0,
    );
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    context.tr('Cancel', '取消'),
                    style: TextStyle(color: p.muted, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => Navigator.of(context).pop(_index),
                  child: Text(
                    context.tr('Done', '完成'),
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: CupertinoPicker(
              scrollController: _controller,
              itemExtent: 40,
              backgroundColor: CupertinoColors.transparent,
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: widget.accent.withValues(alpha: 0.12),
              ),
              onSelectedItemChanged: (index) => _index = index,
              children: [
                for (final item in widget.items)
                  Center(
                    child: Text(
                      item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text, fontSize: 18),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
