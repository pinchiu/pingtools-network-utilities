import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/subnet_scanner.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../tool_registry.dart';
import '../theme.dart';
import '../widgets.dart';

const String _historyKey = 'subnet';
const int _maxRenderedHosts = 200;

enum SubnetSuggestionKind { gateway, local, subnet }

class SubnetSuggestion {
  final SubnetSuggestionKind kind;
  final String value;
  final String cidr;

  const SubnetSuggestion({
    required this.kind,
    required this.value,
    required this.cidr,
  });
}

/// Presentation state for the subnet scanner.
class SubnetViewModel extends ChangeNotifier {
  SubnetViewModel() {
    _recent = AppSettings.instance.recent(_historyKey);
  }

  final TextEditingController cidrController = TextEditingController(
    text: AppSettings.instance.inputOrDefault('subnet', ''),
  );

  SubnetInfo? _detected;
  bool _detecting = false;
  String? _detectError;
  SubnetInfo? _info;
  List<LanHost> _hosts = const [];
  int _scanned = 0;
  int _total = 0;
  bool _scanning = false;
  bool _includePortProbe =
      AppSettings.instance.prefBool('subnet_ports') ?? false;
  int _durationMs = 0;
  String? _error;
  String? _gateway;
  List<String> _recent = const [];
  StreamSubscription<SubnetScanEvent>? _subscription;
  bool _cidrTouched = false;
  bool _disposed = false;
  int _runId = 0;

  SubnetInfo? get detected => _detected;
  bool get detecting => _detecting;
  String? get detectError => _detectError;
  SubnetInfo? get info => _info;
  List<LanHost> get hosts => _hosts;
  int get scanned => _scanned;
  int get total => _total;
  bool get scanning => _scanning;
  bool get includePortProbe => _includePortProbe;
  int get durationMs => _durationMs;
  String? get error => _error;
  String? get gateway => _gateway;
  List<String> get recent => _recent;

  double get progress => _total <= 0 ? 0 : (_scanned / _total).clamp(0.0, 1.0);

  /// Number of usable addresses for the current input, or 0 when invalid.
  int get plannedHosts {
    final info = parseSubnetInput(cidrController.text);
    if (info == null) return 0;
    return _usableTotal(info);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      AppSettings.instance.rememberInputNow('subnet', cidrController.text),
    );
    try {
      _subscription?.cancel();
    } catch (_) {
      // The stream may already be closed.
    }
    cidrController.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<SubnetSuggestion> get suggestions {
    final info = _detected;
    if (info == null) return const [];
    final out = <SubnetSuggestion>[];
    void add(SubnetSuggestionKind kind, String value, String cidr) {
      if (cidr.trim().isEmpty) return;
      if (out.any((item) => item.cidr == cidr)) return;
      out.add(SubnetSuggestion(kind: kind, value: value, cidr: cidr));
    }

    final prefix = info.prefixLength;
    final gateway = info.gateway;
    if (gateway != null && isValidIpv4(gateway)) {
      add(SubnetSuggestionKind.gateway, gateway, '$gateway/$prefix');
    }
    if (isValidIpv4(info.localIp)) {
      add(SubnetSuggestionKind.local, info.localIp, '${info.localIp}/$prefix');
    }
    add(SubnetSuggestionKind.subnet, info.cidr, info.cidr);
    return out;
  }

  Future<void> detect() async {
    if (_detecting) return;
    _detecting = true;
    _detectError = null;
    _notify();
    SubnetInfo? info;
    try {
      info = await SubnetScanner.detectLocalSubnet();
    } catch (_) {
      info = null;
    }
    if (_disposed) return;
    _detecting = false;
    if (info == null) {
      _detectError = 'detectFailed';
      _notify();
      return;
    }
    _detected = info;
    _gateway = info.gateway;
    if (!_cidrTouched &&
        !_scanning &&
        _info == null &&
        cidrController.text.trim().isEmpty) {
      cidrController.text = info.cidr;
      cidrController.selection = TextSelection.collapsed(
        offset: info.cidr.length,
      );
    }
    _notify();
  }

  void markEdited() {
    _cidrTouched = true;
    AppSettings.instance.rememberInput('subnet', cidrController.text);
    if (_scanning) return;
    _info = null;
    _hosts = const [];
    _scanned = 0;
    _total = 0;
    _durationMs = 0;
    _error = null;
    _notify();
  }

  void applyCidr(String cidr) {
    if (_scanning) return;
    cidrController.text = cidr;
    cidrController.selection = TextSelection.collapsed(offset: cidr.length);
    unawaited(AppSettings.instance.rememberInputNow('subnet', cidr));
    markEdited();
  }

  void setPortProbe(bool value) {
    if (_scanning || value == _includePortProbe) return;
    _includePortProbe = value;
    unawaited(AppSettings.instance.setPrefBool('subnet_ports', value));
    _notify();
  }

  Future<void> scan() async {
    if (_scanning) return;
    final input = cidrController.text.trim();
    final info = parseSubnetInput(input);
    unawaited(AppSettings.instance.rememberInputNow('subnet', input));
    final usable = info == null ? 0 : _usableTotal(info);
    if (info == null || usable <= 0 || usable > 4096) {
      _error = 'invalidInput';
      _notify();
      return;
    }
    final old = _subscription;
    _subscription = null;
    final run = ++_runId;
    _scanning = true;
    _error = null;
    _hosts = const [];
    _scanned = 0;
    _total = usable;
    _durationMs = 0;
    _info = info;
    _notify();
    try {
      await old?.cancel();
    } catch (_) {
      // The old stream may already be closed.
    }
    if (_disposed || run != _runId) return;
    _subscription =
        SubnetScanner.scan(
          SubnetConfig(cidr: info.cidr, includePortProbe: _includePortProbe),
        ).listen(
          (event) => _onEvent(run, event),
          onError: (Object error, StackTrace stackTrace) =>
              _onStreamError(run, error, stackTrace),
          onDone: () => _onStreamDone(run),
          cancelOnError: false,
        );
  }

  Future<void> stop() async {
    if (!_scanning) return;
    _runId += 1;
    _scanning = false;
    _notify();
    final sub = _subscription;
    _subscription = null;
    try {
      await sub?.cancel();
    } catch (_) {
      // Cancellation is best-effort.
    }
    final info = _info;
    if (info != null) unawaited(_remember(info.cidr));
  }

  void _onEvent(int run, SubnetScanEvent event) {
    if (_disposed || run != _runId) return;
    switch (event) {
      case SubnetScanStarted(:final info):
        _info = info;
        _gateway = info.gateway ?? _gateway;
        if (info.totalHosts > 0) _total = info.totalHosts;
      case SubnetScanProgress(:final scanned, :final total, :final found):
        _scanned = scanned;
        if (total > 0) _total = total;
        _hosts = _sorted(found);
      case SubnetScanFinished(:final hosts, :final durationMs):
        _scanning = false;
        _hosts = _sorted(hosts);
        _durationMs = durationMs;
        _error = null;
        _subscription = null;
        unawaited(_remember(_info?.cidr ?? cidrController.text.trim()));
      case SubnetScanFailed(:final message):
        _scanning = false;
        _error = message;
        _subscription = null;
    }
    _notify();
  }

  void _onStreamError(int run, Object error, StackTrace stackTrace) {
    if (_disposed || run != _runId) return;
    _scanning = false;
    _subscription = null;
    _error = 'network';
    _notify();
  }

  void _onStreamDone(int run) {
    if (_disposed || run != _runId) return;
    _subscription = null;
    if (!_scanning) return;
    _scanning = false;
    _error = 'ended';
    _notify();
  }

  static List<LanHost> _sorted(List<LanHost> hosts) {
    final list = List<LanHost>.of(hosts);
    list.sort((a, b) => (ipv4ToInt(a.ip) ?? 0).compareTo(ipv4ToInt(b.ip) ?? 0));
    return list;
  }

  static int _usableTotal(SubnetInfo info) {
    if (info.cidr.contains('/')) {
      final range = subnetRange(info);
      final usable = range.broadcast - range.network - 1;
      return usable < 0 ? 0 : usable;
    }
    return info.totalHosts;
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

class SubnetScreen extends StatefulWidget {
  const SubnetScreen({super.key});

  @override
  State<SubnetScreen> createState() => _SubnetScreenState();
}

class _SubnetScreenState extends State<SubnetScreen> {
  final SubnetViewModel _vm = SubnetViewModel();
  Timer? _copiedTimer;
  bool _copied = false;

  Color get _accent => adaptiveAccent(context, toolById('subnet')!.accent);

  @override
  void initState() {
    super.initState();
    _vm.detect();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _vm.dispose();
    super.dispose();
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

  Future<void> _copyHosts() async {
    final hosts = _vm.hosts;
    if (hosts.isEmpty) return;
    final lines = <String>[];
    for (final host in hosts) {
      final parts = <String>[host.ip];
      if (host.isGateway || host.ip == _vm.gateway) parts.add('gateway');
      if (host.mac != null) parts.add(host.mac!);
      if (host.hostname != null) parts.add(host.hostname!);
      if (host.openPorts.isNotEmpty) {
        parts.add('ports=${host.openPorts.join(',')}');
      }
      lines.add(parts.join('\t'));
    }
    try {
      await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    } catch (_) {
      return;
    }
    HapticFeedback.selectionClick();
    _flashCopied();
  }

  String _errorText(BuildContext context, String? error) {
    if (error == null) return '';
    if (error.contains('Invalid subnet') ||
        error.contains('too large') ||
        error.contains('does not contain')) {
      return context.tr(
        'Enter a valid CIDR or range (/8 to /30, max 4096 hosts).',
        '請輸入有效的 CIDR 或範圍（/8 至 /30，最多 4096 台主機）。',
      );
    }
    if (error.contains('Unable to run ping')) {
      return context.tr(
        'Ping is not available on this device, so the subnet could not be scanned.',
        '此裝置無法執行 ping，因此無法掃描子網路。',
      );
    }
    switch (error) {
      case 'invalidInput':
        return context.tr(
          'Enter a valid CIDR or range (/8 to /30, max 4096 hosts).',
          '請輸入有效的 CIDR 或範圍（/8 至 /30，最多 4096 台主機）。',
        );
      case 'network':
        return context.tr(
          'Network error while scanning. Try again.',
          '掃描時發生網路錯誤，請再試一次。',
        );
      case 'ended':
        return context.tr(
          'The scan ended unexpectedly. Try again.',
          '掃描意外結束，請再試一次。',
        );
      default:
        return error;
    }
  }

  String _suggestionLabel(BuildContext context, SubnetSuggestion suggestion) {
    switch (suggestion.kind) {
      case SubnetSuggestionKind.gateway:
        return '${context.tr('Gateway', '閘道')} · ${suggestion.value}';
      case SubnetSuggestionKind.local:
        return '${context.tr('This device', '本機')} · ${suggestion.value}';
      case SubnetSuggestionKind.subnet:
        return '${context.tr('Subnet', '子網路')} · ${suggestion.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FrostedPage(
      title: context.tr('Subnet Scanner', '子網路掃描'),
      subtitle: context.tr('LAN host discovery', '區域網路裝置探索'),
      child: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final hosts = _vm.hosts;
          final info = _vm.info;
          final error = _vm.error;
          final visible = hosts.length > _maxRenderedHosts
              ? hosts.take(_maxRenderedHosts).toList()
              : hosts;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_vm.detecting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
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
                            context.tr('Detecting your network…', '正在偵測您的網路…'),
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_vm.detectError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    color: p.warning.withValues(alpha: 0.08),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 16,
                          color: p.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              'Could not detect your network. Enter a subnet manually.',
                              '無法自動偵測網路，請手動輸入子網路。',
                            ),
                            style: TextStyle(
                              color: p.text,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: _vm.detecting || _vm.scanning
                              ? null
                              : () {
                                  FocusScope.of(context).unfocus();
                                  _vm.detect();
                                },
                          child: Text(
                            context.tr('Retry', '重試'),
                            style: TextStyle(
                              color: _accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          context.tr('Target subnet', '目標子網路'),
                          style: TextStyle(
                            color: p.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Pill(
                          _vm.plannedHosts > 0
                              ? '${_vm.plannedHosts} ${context.tr('hosts', '台主機')}'
                              : context.tr('Enter a range', '請輸入範圍'),
                          color: _vm.plannedHosts > 0 ? p.muted : p.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppField(
                      label: context.tr('CIDR or IP range', 'CIDR 或 IP 範圍'),
                      controller: _vm.cidrController,
                      placeholder: '192.168.1.0/24',
                      monospace: true,
                      enabled: !_vm.scanning,
                      onChanged: (_) => _vm.markEdited(),
                      suffix: CupertinoButton(
                        padding: const EdgeInsets.only(right: 10, left: 4),
                        onPressed: _vm.scanning || _vm.detecting
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                _vm.detect();
                              },
                        child: Icon(
                          CupertinoIcons.location,
                          size: 20,
                          color: _accent,
                          semanticLabel: context.tr(
                            'Detect local subnet',
                            '偵測區域子網路',
                          ),
                        ),
                      ),
                    ),
                    if (_vm.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final suggestion in _vm.suggestions)
                            SpringyTap(
                              onTap: _vm.scanning
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();
                                      _vm.applyCidr(suggestion.cidr);
                                    },
                              child: Pill(
                                _suggestionLabel(context, suggestion),
                                color: _accent,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            CupertinoIcons.square_grid_2x2,
                            size: 16,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('Probe common ports', '探測常用連接埠'),
                                style: TextStyle(
                                  color: p.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '22, 80, 443, 445, 3389, 8080',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label: context.tr('Probe common ports', '探測常用連接埠'),
                          child: SizedBox(
                            height: 44,
                            child: Center(
                              child: CupertinoSwitch(
                                value: _vm.includePortProbe,
                                onChanged: _vm.scanning
                                    ? null
                                    : (value) => _vm.setPortProbe(value),
                                activeTrackColor: _accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: _vm.scanning
                          ? context.tr('Stop', '停止')
                          : context.tr('Scan', '掃描'),
                      icon: _vm.scanning
                          ? CupertinoIcons.stop_fill
                          : CupertinoIcons.arrow_clockwise,
                      secondary: _vm.scanning,
                      onPressed: _vm.scanning
                          ? () => _vm.stop()
                          : (_vm.detecting
                                ? null
                                : () {
                                    FocusScope.of(context).unfocus();
                                    _vm.scan();
                                  }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                ErrorBanner(_errorText(context, error)),
                const SizedBox(height: 12),
              ],
              if (_vm.scanning) ...[
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const CupertinoActivityIndicator(radius: 8),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr('Scanning subnet…', '正在掃描子網路…'),
                              style: TextStyle(color: p.text, fontSize: 13),
                            ),
                          ),
                          MonoText(
                            '${_vm.scanned} / ${_vm.total}',
                            size: 12,
                            color: p.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ProgressTrack(_vm.progress, color: _accent),
                      const SizedBox(height: 8),
                      Text(
                        _vm.includePortProbe &&
                                _vm.total > 0 &&
                                _vm.scanned >= _vm.total
                            ? context.tr(
                                'Host scan complete — probing common ports…',
                                '主機掃描完成 — 正在探測常用連接埠…',
                              )
                            : '${hosts.length} ${context.tr('hosts found', '台主機找到')}',
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if ((hosts.isNotEmpty || (info != null && !_vm.scanning)) &&
                  (error == null || hosts.isNotEmpty)) ...[
                SectionLabel(
                  context.tr('Hosts', '主機'),
                  trailing: hosts.isEmpty
                      ? null
                      : Row(
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
                              onPressed: _copyHosts,
                              child: Icon(
                                CupertinoIcons.doc_on_doc,
                                size: 18,
                                color: p.muted,
                                semanticLabel: context.tr(
                                  'Copy host list',
                                  '複製主機清單',
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                if (!_vm.scanning) ...[
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: context.tr('Hosts found', '找到主機'),
                          value: '${hosts.length}',
                          accent: _accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: context.tr('Duration', '耗時'),
                          value: _vm.durationMs > 0
                              ? formatDuration(_vm.durationMs)
                              : '--',
                          accent: _accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${info?.cidr ?? _vm.cidrController.text} · '
                    '${context.tr('scanned', '已掃描')} ${_vm.scanned}/${_vm.total}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                ],
                if (visible.isEmpty && !_vm.scanning)
                  EmptyState(
                    icon: CupertinoIcons.antenna_radiowaves_left_right,
                    title: context.tr('No hosts found', '未找到主機'),
                    body: context.tr(
                      'Try a wider range, or confirm this device is on the same Wi-Fi or LAN.',
                      '嘗試更大的範圍，或確認本機連線到同一個 Wi-Fi 或區域網路。',
                    ),
                  )
                else
                  for (final host in visible) ...[
                    _HostCard(
                      host: host,
                      gateway: _vm.gateway,
                      accent: _accent,
                    ),
                    const SizedBox(height: 8),
                  ],
                if (hosts.length > visible.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.tr(
                        'Showing first ${visible.length} of ${hosts.length} hosts.',
                        '僅顯示前 ${visible.length} / ${hosts.length} 台主機。',
                      ),
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                  ),
                if (hosts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(CupertinoIcons.info, size: 14, color: p.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr(
                            'Android 10+ may hide MAC addresses for privacy. IP and latency are still shown.',
                            'Android 10 以上可能基於隱私隱藏 MAC 位址；IP 與延遲仍可正常顯示。',
                          ),
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ] else if (!_vm.scanning && !_vm.detecting && error == null) ...[
                const SizedBox(height: 8),
                EmptyState(
                  icon: CupertinoIcons.antenna_radiowaves_left_right,
                  title: context.tr('Ready to scan', '準備掃描'),
                  body: context.tr(
                    'Choose a suggested subnet or type a range, then tap Scan.',
                    '選擇建議的子網路或輸入範圍，然後點選掃描。',
                  ),
                ),
              ],
              if (_vm.recent.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionLabel(context.tr('Recent', '最近掃描')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in _vm.recent.take(5))
                      SpringyTap(
                        onTap: _vm.scanning
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                _vm.applyCidr(item);
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

class _HostCard extends StatelessWidget {
  final LanHost host;
  final String? gateway;
  final Color accent;

  const _HostCard({required this.host, required this.accent, this.gateway});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isGateway = host.isGateway || host.ip == gateway;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isGateway
                      ? CupertinoIcons.wifi
                      : CupertinoIcons.desktopcomputer,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoText(host.ip, size: 15, weight: FontWeight.w600),
                    const SizedBox(height: 2),
                    Text(
                      host.hostname ?? context.tr('No hostname', '無主機名稱'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (isGateway) Pill(context.tr('Gateway', '閘道'), color: accent),
              if (host.rttMs != null)
                Pill(fmtLatency(host.rttMs!), color: p.success),
              Pill(
                host.mac ?? context.tr('MAC unavailable', 'MAC 無法取得'),
                color: host.mac == null ? p.warning : p.muted,
              ),
              for (final port in host.openPorts.take(10))
                Pill(
                  serviceNameForPort(port).isEmpty
                      ? '$port'
                      : '$port · ${serviceNameForPort(port)}',
                  color: accent,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
