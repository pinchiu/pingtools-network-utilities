import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/traceroute_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';

class TracerouteScreen extends StatefulWidget {
  const TracerouteScreen({super.key});

  @override
  State<TracerouteScreen> createState() => _TracerouteScreenState();
}

class _TracerouteScreenState extends State<TracerouteScreen> {
  final TextEditingController _host = TextEditingController(
    text: AppSettings.instance.inputOrDefault('trace', 'github.com'),
  );
  final TracerouteViewModel _vm = TracerouteViewModel();
  List<String> _recent = const [];
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _recent = AppSettings.instance.recent('trace');
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    unawaited(AppSettings.instance.rememberInputNow('trace', _host.text));
    _host.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _refreshRecent() {
    final recent = AppSettings.instance.recent('trace');
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  void _start() {
    final host = normalizeHost(_host.text);
    if (host.isEmpty) {
      _vm.showError(
        context.tr('Enter a host name or IP address.', '請輸入主機名稱或 IP 位址。'),
      );
      return;
    }
    if (_host.text != host) _host.text = host;
    unawaited(AppSettings.instance.rememberInputNow('trace', host));
    _copiedTimer?.cancel();
    setState(() => _copied = false);
    _vm.start(host);
    unawaited(AppSettings.instance.addRecent('trace', host));
    _refreshRecent();
  }

  void _useRecent(String host) {
    _host.text = host;
    unawaited(AppSettings.instance.rememberInputNow('trace', host));
    _vm.clearError();
  }

  Future<void> _copyAll() async {
    if (_vm.hops.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _resultText()));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _resultText() {
    final buffer = StringBuffer('traceroute to ${_vm.target ?? ''}');
    if (_vm.resolvedIp != null) buffer.write(' (${_vm.resolvedIp})');
    buffer.writeln();
    for (final hop in _vm.hops) {
      buffer.write('${hop.hop.toString().padLeft(2)}  ${hop.address ?? '*'}');
      for (var i = 0; i < 3; i++) {
        if (i < hop.rtts.length) {
          buffer.write('  ${hop.rtts[i].toStringAsFixed(1)} ms');
        } else {
          buffer.write('  *');
        }
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAccent(
      context,
      toolById('trace')?.accent ?? AppAccents.violet,
    );
    return FrostedPage(
      title: context.tr('Traceroute', '路由追蹤'),
      subtitle: context.tr('Hop-by-hop network path', '逐跳網路路徑'),
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
              AppField(
                label: context.tr('Host', '主機'),
                controller: _host,
                placeholder: context.tr('host name or IP', '主機名稱或 IP'),
                enabled: !vm.running,
                monospace: true,
                keyboardType: TextInputType.url,
                onChanged: (value) {
                  AppSettings.instance.rememberInput('trace', value);
                  vm.clearError();
                },
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  '3 probes per hop · up to 30 hops',
                  '每跳 3 次探測 · 最多 30 跳',
                ),
                style: TextStyle(color: p.muted, fontSize: 11),
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
        const SizedBox(height: 14),
        if (vm.target == null && vm.hops.isEmpty)
          AppCard(
            child: EmptyState(
              icon: CupertinoIcons.arrow_branch,
              title: context.tr('No hops yet', '尚無跳點'),
              body: context.tr(
                'Start a trace to map the path to a target.',
                '開始追蹤以描繪到目標的路徑。',
              ),
            ),
          )
        else ...[
          _statusCard(context, accent),
          const SizedBox(height: 18),
          _pathSection(context, accent),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _statusCard(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.target ?? context.tr('No target', '尚未指定目標'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    MonoText(vm.resolvedIp ?? '—', size: 11, color: p.muted),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _statusPill(context, accent),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: context.tr('Hops', '跳數'),
                  value: '${vm.hops.length}',
                  accent: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: context.tr('Elapsed', '耗時'),
                  value: formatDuration(vm.elapsedMs),
                ),
              ),
            ],
          ),
          if (vm.hops.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppButton(
              label: _copied
                  ? context.tr('Copied', '已複製')
                  : context.tr('Copy all', '全部複製'),
              icon: _copied
                  ? CupertinoIcons.checkmark
                  : CupertinoIcons.doc_on_doc,
              secondary: true,
              onPressed: _copyAll,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    if (vm.reachedTarget) {
      return Pill(context.tr('Target reached', '已到達目標'), color: p.success);
    }
    if (vm.running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoActivityIndicator(radius: 6, color: accent),
          const SizedBox(width: 6),
          Pill(context.tr('Tracing', '追蹤中'), color: accent),
        ],
      );
    }
    if (vm.stopped) {
      return Pill(context.tr('Stopped', '已停止'), color: p.warning);
    }
    if (vm.error != null) {
      return Pill(context.tr('Failed', '失敗'), color: p.danger);
    }
    return Pill(context.tr('Finished', '已完成'), color: p.muted);
  }

  Widget _pathSection(BuildContext context, Color accent) {
    final p = context.palette;
    final hops = _vm.hops;
    if (hops.isEmpty) {
      if (_vm.error != null) return const SizedBox.shrink();
      final stopped = _vm.stopped;
      return AppCard(
        child: EmptyState(
          icon: CupertinoIcons.arrow_branch,
          title: stopped
              ? context.tr('Trace stopped', '追蹤已停止')
              : context.tr('Waiting for hops', '等待跳點'),
          body: stopped
              ? context.tr(
                  'No hops were recorded before the trace stopped.',
                  '追蹤停止前未記錄任何跳點。',
                )
              : context.tr(
                  'Probes are still running. Hops will appear here.',
                  '探測仍在進行，跳點將顯示於此。',
                ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          context.tr('Path', '路徑'),
          trailing: Text(
            '${hops.length}',
            style: TextStyle(color: p.muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < hops.length; i++) ...[
                if (i > 0) DividerLine(color: p.border.withValues(alpha: 0.7)),
                _HopRow(hop: hops[i], accent: accent),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _errorText(BuildContext context, String error) {
    final lower = error.toLowerCase();
    if (lower.contains('icmp')) {
      return context.tr(
        'ICMP is blocked on this device; traceroute needs raw ICMP support.',
        '此裝置封鎖了 ICMP；路由追蹤需要原生 ICMP 支援。',
      );
    }
    if (lower.contains('could not resolve')) {
      return context.tr(
        'Could not resolve the host. Check the name and connection.',
        '無法解析主機，請檢查名稱與網路連線。',
      );
    }
    if (lower.contains('enter a host')) {
      return context.tr('Enter a host name or IP address.', '請輸入主機名稱或 IP 位址。');
    }
    return error;
  }
}

class TracerouteViewModel extends ChangeNotifier {
  StreamSubscription<TraceEvent>? _sub;
  Timer? _ticker;
  final Stopwatch _watch = Stopwatch();
  int _runId = 0;
  bool _disposed = false;

  bool _running = false;
  bool _reachedTarget = false;
  bool _stopped = false;
  String? _target;
  String? _resolvedIp;
  String? _error;
  int _elapsedMs = 0;
  List<TraceHop> _hops = const [];

  bool get running => _running;
  bool get reachedTarget => _reachedTarget;
  bool get stopped => _stopped;
  String? get target => _target;
  String? get resolvedIp => _resolvedIp;
  String? get error => _error;
  int get elapsedMs => _elapsedMs;
  List<TraceHop> get hops => _hops;

  void clearError() {
    if (_error == null) return;
    _error = null;
    _emit();
  }

  void showError(String message) {
    _error = message;
    _emit();
  }

  void start(String host) {
    _cancel();
    final id = _runId;
    _target = host;
    _resolvedIp = null;
    _error = null;
    _hops = const [];
    _reachedTarget = false;
    _stopped = false;
    _elapsedMs = 0;
    _running = true;
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (id != _runId) return;
      _elapsedMs = _watch.elapsedMilliseconds;
      _emit();
    });
    _emit();

    final config = TraceConfig(host: host, maxHops: 30, probesPerHop: 3);
    _sub = TracerouteEngine.trace(config).listen(
      (event) {
        if (id != _runId) return;
        _onEvent(event);
      },
      onError: (Object error) {
        if (id != _runId) return;
        _error = '$error';
        _finishRun();
        _emit();
      },
      onDone: () {
        if (id != _runId) return;
        _finishRun();
        _emit();
      },
    );
  }

  void stop() {
    if (!_running) return;
    final elapsed = _watch.elapsedMilliseconds;
    _cancel();
    _running = false;
    _stopped = true;
    _elapsedMs = elapsed;
    _emit();
  }

  void _onEvent(TraceEvent event) {
    switch (event) {
      case TraceStarted(:final resolvedIp):
        _resolvedIp = resolvedIp;
        _emit();
      case TraceHopFound(:final hop):
        final next = [..._hops, hop]..sort((a, b) => a.hop.compareTo(b.hop));
        _hops = next;
        _elapsedMs = _watch.elapsedMilliseconds;
        _emit();
      case TraceFinished(:final hops, :final reachedTarget):
        _hops = List<TraceHop>.of(hops);
        _reachedTarget = reachedTarget;
        _running = false;
        _elapsedMs = _watch.elapsedMilliseconds;
        _finishRun();
        _emit();
      case TraceFailed(:final message):
        _error = message;
        _finishRun();
        _emit();
    }
  }

  void _finishRun() {
    _running = false;
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    _watch.stop();
  }

  void _cancel() {
    _runId++;
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    _watch.stop();
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
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({required this.hop, required this.accent});

  final TraceHop hop;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasAddress = hop.address != null && hop.address!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(7),
            ),
            child: MonoText(
              '${hop.hop}',
              size: 12,
              weight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonoText(
                  hasAddress ? hop.address! : '*',
                  size: 13,
                  weight: FontWeight.w500,
                  color: hasAddress ? p.text : p.muted,
                ),
                if (hop.hostname != null && hop.hostname!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hop.hostname!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (var i = 0; i < 3; i++)
            SizedBox(
              width: 56,
              child: Text(
                i < hop.rtts.length ? fmtLatency(hop.rtts[i]) : '*',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: i < hop.rtts.length ? p.text : p.muted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
        ],
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
