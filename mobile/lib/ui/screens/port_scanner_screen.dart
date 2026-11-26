import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/port_scanner.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';

class PortScannerScreen extends StatefulWidget {
  const PortScannerScreen({super.key});

  @override
  State<PortScannerScreen> createState() => _PortScannerScreenState();
}

class _PortScannerScreenState extends State<PortScannerScreen> {
  final TextEditingController _host = TextEditingController(text: '1.1.1.1');
  final TextEditingController _spec = TextEditingController(
    text: portPresets.first.spec,
  );
  final PortScannerViewModel _vm = PortScannerViewModel();
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _recent = AppSettings.instance.recent('ports');
  }

  @override
  void dispose() {
    _host.dispose();
    _spec.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _refreshRecent() {
    final recent = AppSettings.instance.recent('ports');
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  void _start() {
    final host = normalizeHost(_host.text);
    if (host.isEmpty) {
      _vm.showInputError(
        context.tr('Enter a host name or IP address.', '請輸入主機名稱或 IP 位址。'),
      );
      return;
    }
    List<int> ports;
    try {
      ports = parsePortSpec(_spec.text);
    } on FormatException catch (error) {
      _vm.showInputError(
        '${context.tr('Invalid port spec', '連接埠格式錯誤')}: ${error.message}',
      );
      return;
    }
    if (_host.text != host) _host.text = host;
    _vm.start(host: host, ports: ports);
    unawaited(AppSettings.instance.addRecent('ports', host));
    _refreshRecent();
  }

  void _useRecent(String host) {
    _host.text = host;
    _vm.clearInputError();
  }

  void _applyPreset(PortPreset preset) {
    setState(() => _spec.text = preset.spec);
    _vm.clearInputError();
  }

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAccent(
      context,
      toolById('ports')?.accent ?? AppAccents.amber,
    );
    return FrostedPage(
      title: context.tr('Port Scanner', '連接埠掃描'),
      subtitle: context.tr('TCP ports & service banners', 'TCP 連接埠與服務橫幅'),
      child: AnimatedBuilder(
        animation: _vm,
        builder: (context, _) => _body(context, accent),
      ),
    );
  }

  Widget _body(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final hostField = AppField(
                    label: context.tr('Host', '主機'),
                    controller: _host,
                    placeholder: context.tr('host name or IP', '主機名稱或 IP'),
                    enabled: !vm.running,
                    monospace: true,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => vm.clearInputError(),
                  );
                  final portsField = AppField(
                    label: context.tr('Ports', '連接埠'),
                    controller: _spec,
                    placeholder: '80,443,8000-8100',
                    enabled: !vm.running,
                    monospace: true,
                    keyboardType: TextInputType.text,
                    onChanged: (_) => setState(() {}),
                  );
                  if (constraints.maxWidth >= 560) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: hostField),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: portsField),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hostField,
                      const SizedBox(height: 12),
                      portsField,
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Comma or space separated; ranges like 1-1024.',
                  '以逗號或空格分隔；可用 1-1024 等範圍。',
                ),
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('Presets', '預設'),
                style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in portPresets)
                    _PresetChip(
                      label: _presetLabel(context, preset),
                      selected: _spec.text.trim() == preset.spec,
                      accent: accent,
                      onTap: vm.running ? null : () => _applyPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (vm.running)
                AppButton(
                  label: context.tr('Stop', '停止'),
                  icon: CupertinoIcons.stop_fill,
                  secondary: true,
                  onPressed: vm.stop,
                )
              else
                AppButton(
                  label: context.tr('Start', '開始'),
                  icon: CupertinoIcons.play_arrow_solid,
                  onPressed: _start,
                ),
            ],
          ),
        ),
        if (vm.inputError != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(vm.inputError!),
        ],
        if (vm.error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(_errorText(context, vm.error!)),
        ],
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionLabel(context.tr('Recent', '最近')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final host in _recent.take(6))
                _RecentChip(label: host, onTap: () => _useRecent(host)),
            ],
          ),
        ],
        if (vm.running || vm.scanned > 0 || vm.finished) ...[
          const SizedBox(height: 14),
          _progressCard(context, accent),
        ],
        const SizedBox(height: 18),
        SectionLabel(
          context.tr('Open ports', '開放連接埠'),
          trailing: Text(
            '${vm.open.length}',
            style: TextStyle(color: p.muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        if (vm.error == null && vm.open.isEmpty && vm.finished)
          AppCard(
            child: EmptyState(
              icon: CupertinoIcons.checkmark_shield,
              title: context.tr('No open ports', '沒有開放的連接埠'),
              body: context.tr(
                'All scanned ports were closed or filtered.',
                '所有掃描的連接埠皆為關閉或被過濾。',
              ),
            ),
          )
        else if (vm.error == null && vm.open.isEmpty && vm.stopped)
          AppCard(
            child: EmptyState(
              icon: CupertinoIcons.stop_circle,
              title: context.tr('Scan stopped', '掃描已停止'),
              body: context.tr(
                'No open ports were found before the scan stopped.',
                '掃描停止前未發現開放的連接埠。',
              ),
            ),
          )
        else if (vm.error == null && vm.open.isEmpty && !vm.running)
          AppCard(
            child: EmptyState(
              icon: CupertinoIcons.square_grid_2x2,
              title: context.tr('Ready to scan', '準備掃描'),
              body: context.tr(
                'Choose a preset or enter ports, then start.',
                '選擇預設或輸入連接埠後開始。',
              ),
            ),
          )
        else
          for (final result in vm.open)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PortCard(result: result, accent: accent),
            ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _progressCard(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            context.tr('Progress', '進度'),
            trailing: MonoText(
              '${(vm.progress * 100).round()}%',
              size: 11,
              color: accent,
            ),
          ),
          const SizedBox(height: 10),
          ProgressTrack(vm.progress, color: accent),
          const SizedBox(height: 10),
          Row(
            children: [
              MonoText('${vm.scanned} / ${vm.total}', size: 11, color: p.muted),
              const Spacer(),
              if (vm.running)
                CupertinoActivityIndicator(radius: 6, color: accent)
              else if (vm.durationMs != null)
                Text(
                  formatDuration(vm.durationMs!),
                  style: TextStyle(color: p.muted, fontSize: 11),
                ),
            ],
          ),
          if (vm.resolvedIp != null) ...[
            const SizedBox(height: 6),
            MonoText(
              '${vm.target ?? ''}  →  ${vm.resolvedIp}',
              size: 11,
              color: p.muted,
            ),
          ],
          if (vm.finished && vm.error == null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill(
                  '${vm.open.length} ${context.tr('open', '開放')}',
                  color: p.success,
                ),
                Pill(
                  '${vm.closedCount} ${context.tr('closed', '已關閉')}',
                  color: p.muted,
                ),
                Pill(
                  '${vm.filteredCount} ${context.tr('filtered', '已過濾')}',
                  color: p.warning,
                ),
              ],
            ),
          ],
          if (vm.stopped) ...[
            const SizedBox(height: 10),
            Text(
              context.tr(
                'Stopped early — showing partial results.',
                '已提前停止 — 顯示部分結果。',
              ),
              style: TextStyle(color: p.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _presetLabel(BuildContext context, PortPreset preset) {
    if (!context.isZh) return preset.label;
    switch (preset.label) {
      case 'Top 20':
        return '常用 20 埠';
      case 'Web':
        return '網頁';
      case 'Remote':
        return '遠端';
      case 'Database':
        return '資料庫';
      case 'Full 1-1024':
        return '完整 1-1024';
    }
    return preset.label;
  }

  String _errorText(BuildContext context, String error) {
    final lower = error.toLowerCase();
    if (lower.contains('could not resolve')) {
      return context.tr(
        'Could not resolve the host. Check the name and connection.',
        '無法解析主機，請檢查名稱與網路連線。',
      );
    }
    if (lower.contains('no ports')) {
      return context.tr('Enter at least one port to scan.', '請輸入至少一個要掃描的連接埠。');
    }
    return error;
  }
}

class PortScannerViewModel extends ChangeNotifier {
  StreamSubscription<PortScanEvent>? _sub;
  int _runId = 0;
  bool _disposed = false;

  bool _running = false;
  bool _finished = false;
  bool _stopped = false;
  String? _target;
  String? _resolvedIp;
  String? _error;
  String? _inputError;
  int _scanned = 0;
  int _total = 0;
  int _closedCount = 0;
  int _filteredCount = 0;
  int? _durationMs;
  List<PortResult> _open = const [];

  bool get running => _running;
  bool get finished => _finished;
  bool get stopped => _stopped;
  String? get target => _target;
  String? get resolvedIp => _resolvedIp;
  String? get error => _error;
  String? get inputError => _inputError;
  int get scanned => _scanned;
  int get total => _total;
  int get closedCount => _closedCount;
  int get filteredCount => _filteredCount;
  int? get durationMs => _durationMs;
  List<PortResult> get open => _open;

  double get progress => _total == 0 ? 0 : (_scanned / _total).clamp(0.0, 1.0);

  void showInputError(String message) {
    _inputError = message;
    _emit();
  }

  void clearInputError() {
    if (_inputError == null) return;
    _inputError = null;
    _emit();
  }

  void start({required String host, required List<int> ports}) {
    _cancel();
    final id = _runId;
    _target = host;
    _resolvedIp = null;
    _error = null;
    _inputError = null;
    _open = const [];
    _scanned = 0;
    _total = ports.length;
    _closedCount = 0;
    _filteredCount = 0;
    _durationMs = null;
    _finished = false;
    _stopped = false;
    _running = true;
    _emit();

    final config = PortScanConfig(
      host: host,
      ports: ports,
      concurrency: 64,
      timeoutMs: 900,
      grabBanners: true,
    );
    _sub = PortScanner.scan(config).listen(
      (event) {
        if (id != _runId) return;
        _onEvent(event);
      },
      onError: (Object error) {
        if (id != _runId) return;
        _error = '$error';
        _running = false;
        _finished = true;
        _sub = null;
        _emit();
      },
      onDone: () {
        if (id != _runId) return;
        if (_running) {
          _running = false;
          _finished = true;
          _sub = null;
          _emit();
        }
      },
    );
  }

  void stop() {
    if (!_running) return;
    _runId++;
    _sub?.cancel();
    _sub = null;
    _running = false;
    _stopped = true;
    _emit();
  }

  void _onEvent(PortScanEvent event) {
    switch (event) {
      case PortScanStarted(:final resolvedIp, :final total):
        _resolvedIp = resolvedIp;
        _total = total;
        _emit();
      case PortScanProgressEvent(:final progress):
        _scanned = progress.scanned;
        _total = progress.total;
        _open = List<PortResult>.of(progress.open)
          ..sort((a, b) => a.port.compareTo(b.port));
        _emit();
      case PortScanFinished(:final results, :final durationMs):
        final sorted = List<PortResult>.of(results)
          ..sort((a, b) => a.port.compareTo(b.port));
        _open = sorted
            .where((result) => result.state == PortState.open)
            .toList();
        _closedCount = sorted
            .where((result) => result.state == PortState.closed)
            .length;
        _filteredCount = sorted
            .where((result) => result.state == PortState.filtered)
            .length;
        _scanned = sorted.length;
        _total = sorted.isEmpty ? _total : sorted.length;
        _durationMs = durationMs;
        _running = false;
        _finished = true;
        _sub = null;
        _emit();
      case PortScanFailed(:final message):
        _error = message;
        _running = false;
        _finished = true;
        _sub?.cancel();
        _sub = null;
        _emit();
    }
  }

  void _cancel() {
    _runId++;
    _sub?.cancel();
    _sub = null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _runId++;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

class _PortCard extends StatelessWidget {
  const _PortCard({required this.result, required this.accent});

  final PortResult result;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final service = result.service.trim().isEmpty
        ? context.tr('Unknown service', '未知服務')
        : result.service;
    final banner = result.banner?.trim();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: MonoText(
                  '${result.port}',
                  size: 18,
                  weight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text('TCP', style: TextStyle(color: p.muted, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(context.tr('Open', '開放'), color: p.success),
            ],
          ),
          if (banner != null && banner.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: p.elevated.withValues(alpha: p.isDark ? 0.7 : 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: MonoText(banner, size: 11, color: p.muted, maxLines: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SpringyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : p.elevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.5) : p.border,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? accent : p.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SpringyTap(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: p.elevated,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: p.border, width: 0.7),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.text,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
