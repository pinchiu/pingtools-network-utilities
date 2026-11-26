import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/ping_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';

class PingScreen extends StatefulWidget {
  const PingScreen({super.key});

  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  final TextEditingController _host = TextEditingController(text: '1.1.1.1');
  final PingViewModel _vm = PingViewModel();
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _recent = AppSettings.instance.recent('ping');
  }

  @override
  void dispose() {
    _host.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _refreshRecent() {
    final recent = AppSettings.instance.recent('ping');
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
    _vm.start(host);
    unawaited(AppSettings.instance.addRecent('ping', host));
    _refreshRecent();
  }

  void _useRecent(String host) {
    _host.text = host;
    _vm.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAccent(
      context,
      toolById('ping')?.accent ?? AppAccents.cyan,
    );
    return FrostedPage(
      title: context.tr('Ping', 'Ping 測試'),
      subtitle: context.tr('ICMP latency, loss & jitter', 'ICMP 延遲、封包遺失與抖動'),
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
                onChanged: (_) {
                  _vm.clearError();
                  setState(() {});
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Continuous', '連續'),
                          style: TextStyle(
                            color: p.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('Ping until you stop', '持續傳送直到停止'),
                          style: TextStyle(color: p.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: context.tr('Continuous ping', '連續 Ping'),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: CupertinoSwitch(
                          value: vm.continuous,
                          onChanged: vm.running ? null : vm.setContinuous,
                        ),
                      ),
                    ),
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
        if (vm.error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(_errorText(context, vm.error!)),
        ],
        if (vm.note != null) ...[
          const SizedBox(height: 10),
          _NoteLine(_noteText(context, vm.note!)),
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
        _hero(context, accent),
        const SizedBox(height: 12),
        _statGrid(context, accent),
        if (vm.summary != null) ...[
          const SizedBox(height: 14),
          _summaryCard(context, vm.summary!),
        ],
        const SizedBox(height: 18),
        _logCard(context),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _hero(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    final mode = vm.mode;
    final modeColor = mode == PingMode.tcp ? p.warning : accent;
    final latest = vm.latest;
    final draftTarget = normalizeHost(_host.text);
    final displayTarget = vm.target ?? draftTarget;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
                      displayTarget.isEmpty
                          ? context.tr('No target', '尚未指定目標')
                          : displayTarget,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MonoText(
                              latest == null ? '—' : fmtLatency(latest),
                              size: 38,
                              weight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            context.tr('latest RTT', '最新延遲'),
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (vm.running) ...[
                          CupertinoActivityIndicator(radius: 6, color: accent),
                          const SizedBox(width: 6),
                        ],
                        Pill(
                          mode == PingMode.tcp ? 'TCP' : 'ICMP',
                          color: modeColor,
                        ),
                      ],
                    ),
                    if (vm.resolvedIp != null) ...[
                      const SizedBox(height: 6),
                      MonoText(vm.resolvedIp!, size: 10, color: p.muted),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (vm.samples.isNotEmpty)
            _Sparkline(samples: vm.samples, color: accent, grid: p.border)
          else
            SizedBox(
              height: 92,
              child: Center(
                child: Text(
                  vm.running
                      ? context.tr('Waiting for replies…', '等待回覆中…')
                      : context.tr('No samples yet', '尚無取樣資料'),
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statGrid(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    final summaryAvg = (vm.summary?.received ?? 0) > 0
        ? vm.summary!.avgMs
        : null;
    final avg = vm.averageMs ?? summaryAvg;
    final tiles = [
      StatTile(label: context.tr('Sent', '已傳送'), value: '${vm.sent}'),
      StatTile(
        label: context.tr('Received', '已接收'),
        value: '${vm.received}',
        accent: vm.received > 0 ? p.success : null,
      ),
      StatTile(
        label: context.tr('Loss', '遺失'),
        value: fmtPercent(vm.lossPercent),
        accent: vm.lossPercent > 0 ? p.danger : p.success,
      ),
      StatTile(
        label: context.tr('Avg', '平均'),
        value: avg == null ? '—' : fmtLatency(avg),
        accent: accent,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth < 430 ? 2 : 4;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context, PingSummary summary) {
    final p = context.palette;
    final hasReplies = summary.received > 0;
    final tiles = [
      StatTile(
        label: context.tr('Min', '最小'),
        value: hasReplies ? fmtLatency(summary.minMs) : '—',
      ),
      StatTile(
        label: context.tr('Avg', '平均'),
        value: hasReplies ? fmtLatency(summary.avgMs) : '—',
      ),
      StatTile(
        label: context.tr('Max', '最大'),
        value: hasReplies ? fmtLatency(summary.maxMs) : '—',
      ),
      StatTile(
        label: context.tr('Jitter', '抖動'),
        value: hasReplies ? fmtLatency(summary.jitterMs) : '—',
      ),
      StatTile(
        label: context.tr('Std dev', '標準差'),
        value: hasReplies ? fmtLatency(summary.stdDevMs) : '—',
      ),
      StatTile(
        label: context.tr('Loss', '遺失'),
        value: fmtPercent(summary.lossPercent),
        accent: summary.lossPercent > 0 ? p.danger : p.success,
      ),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(context.tr('Summary', '摘要')),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final columns = constraints.maxWidth < 430
                  ? 2
                  : (constraints.maxWidth < 620 ? 3 : 4);
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in tiles)
                    SizedBox(width: tileWidth, child: tile),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _logCard(BuildContext context) {
    final p = context.palette;
    final entries = _vm.log;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            context.tr('Reply log', '回覆記錄'),
            trailing: Text(
              '${entries.length}',
              style: TextStyle(color: p.muted, fontSize: 11),
            ),
          ),
          if (entries.isEmpty)
            EmptyState(
              icon: CupertinoIcons.wifi,
              title: context.tr('No replies yet', '尚無回覆'),
              body: context.tr(
                'Start a ping to see live latency and loss.',
                '開始 Ping 以查看即時延遲與遺失。',
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: MonoText(
                  _logText(context, entry),
                  size: 12,
                  color: _logColor(p, entry),
                ),
              ),
        ],
      ),
    );
  }

  String _logText(BuildContext context, PingLogEntry entry) {
    switch (entry.kind) {
      case PingLogKind.reply:
        final ttl = entry.ttl == null ? '' : '  ttl ${entry.ttl}';
        return '#${entry.seq}  ${fmtLatency(entry.rttMs!)}$ttl';
      case PingLogKind.timeout:
        return '#${entry.seq}  ${context.tr('timeout', '逾時')}';
      case PingLogKind.note:
        return _noteText(context, entry.note ?? '');
    }
  }

  Color _logColor(AppPalette p, PingLogEntry entry) {
    switch (entry.kind) {
      case PingLogKind.reply:
        return p.text;
      case PingLogKind.timeout:
        return p.muted;
      case PingLogKind.note:
        return p.warning;
    }
  }

  String _noteText(BuildContext context, String note) {
    final lower = note.toLowerCase();
    if (lower.contains('unavailable')) {
      return context.tr(
        'ICMP is unavailable — using TCP connect probes.',
        'ICMP 無法使用 — 改用 TCP 連線探測。',
      );
    }
    if (lower.contains('tcp')) {
      return context.tr(
        'ICMP is blocked — using TCP connect probes.',
        'ICMP 被封鎖 — 改用 TCP 連線探測。',
      );
    }
    return note;
  }

  String _errorText(BuildContext context, String error) {
    final lower = error.toLowerCase();
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

class PingViewModel extends ChangeNotifier {
  static const int _maxSamples = 60;
  static const int _maxLog = 80;

  StreamSubscription<PingEvent>? _sub;
  int _runId = 0;
  bool _disposed = false;

  bool _running = false;
  bool _continuous = false;
  PingMode? _mode;
  String? _target;
  String? _resolvedIp;
  String? _note;
  String? _error;
  int _sent = 0;
  int _received = 0;
  PingSummary? _summary;
  List<double> _samples = const [];
  int _statCount = 0;
  double _statSum = 0;
  double _statSumSq = 0;
  double _statMin = 0;
  double _statMax = 0;
  double _statLast = 0;
  double _statJitterSum = 0;
  int _statJitterCount = 0;
  List<PingLogEntry> _log = const [];

  bool get running => _running;
  bool get continuous => _continuous;
  PingMode? get mode => _mode;
  String? get target => _target;
  String? get resolvedIp => _resolvedIp;
  String? get note => _note;
  String? get error => _error;
  int get sent => _sent;
  int get received => _received;
  PingSummary? get summary => _summary;
  List<double> get samples => _samples;
  List<PingLogEntry> get log => _log;

  double? get latest => _samples.isEmpty ? null : _samples.last;

  double? get averageMs {
    if (_statCount == 0) return null;
    return _statSum / _statCount;
  }

  double get lossPercent {
    if (_sent == 0) return 0;
    return ((_sent - _received) / _sent * 100).clamp(0.0, 100.0).toDouble();
  }

  void setContinuous(bool value) {
    if (_continuous == value) return;
    _continuous = value;
    _emit();
  }

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
    _mode = null;
    _note = null;
    _error = null;
    _summary = null;
    _sent = 0;
    _received = 0;
    _samples = const [];
    _resetStats();
    _log = const [];
    _running = true;
    _emit();

    final config = PingConfig(host: host, count: _continuous ? 0 : 10);
    _sub = PingEngine.ping(config).listen(
      (event) {
        if (id != _runId) return;
        _onEvent(event);
      },
      onError: (Object error) {
        if (id != _runId) return;
        _error = '$error';
        _running = false;
        _sub = null;
        _emit();
      },
      onDone: () {
        if (id != _runId) return;
        if (_running) {
          _running = false;
          _sub = null;
          if (_sent > 0) _summary ??= _summarize(_sent);
          _emit();
        }
      },
    );
  }

  void stop() {
    if (!_running) return;
    _cancel();
    _running = false;
    if (_sent > 0) _summary ??= _summarize(_sent);
    _emit();
  }

  void _onEvent(PingEvent event) {
    switch (event) {
      case PingStarted(:final resolvedIp, :final mode):
        _resolvedIp = resolvedIp;
        _mode = mode;
        _emit();
      case PingReplyEvent(:final reply):
        _sent++;
        _received++;
        _appendSample(reply.rttMs);
        _appendLog(
          PingLogEntry.reply(
            seq: reply.seq,
            rttMs: reply.rttMs,
            ttl: reply.ttl,
          ),
        );
        _emit();
      case PingTimeoutEvent(:final seq):
        _sent++;
        _appendLog(PingLogEntry.timeout(seq: seq));
        _emit();
      case PingNoteEvent(:final message):
        _note = message;
        _appendLog(PingLogEntry.note(message));
        _emit();
      case PingFinishedEvent(:final summary):
        _sent = summary.sent;
        _received = summary.received;
        _summary = summary;
        _running = false;
        _sub = null;
        _emit();
      case PingFailedEvent(:final message):
        _error = message;
        _running = false;
        _sub?.cancel();
        _sub = null;
        _emit();
    }
  }

  void _appendSample(double rtt) {
    if (rtt.isNaN || rtt.isInfinite) return;
    if (_statCount == 0) {
      _statMin = rtt;
      _statMax = rtt;
    } else {
      if (rtt < _statMin) _statMin = rtt;
      if (rtt > _statMax) _statMax = rtt;
      _statJitterSum += (rtt - _statLast).abs();
      _statJitterCount++;
    }
    _statLast = rtt;
    _statCount++;
    _statSum += rtt;
    _statSumSq += rtt * rtt;
    final next = [..._samples, rtt];
    _samples = next.length > _maxSamples
        ? next.sublist(next.length - _maxSamples)
        : next;
  }

  void _resetStats() {
    _statCount = 0;
    _statSum = 0;
    _statSumSq = 0;
    _statMin = 0;
    _statMax = 0;
    _statLast = 0;
    _statJitterSum = 0;
    _statJitterCount = 0;
  }

  void _appendLog(PingLogEntry entry) {
    final next = [entry, ..._log];
    _log = next.length > _maxLog ? next.sublist(0, _maxLog) : next;
  }

  PingSummary _summarize(int sent) {
    final received = _received;
    final effectiveSent = math.max(sent, received);
    final loss = effectiveSent == 0
        ? 0.0
        : ((effectiveSent - received) / effectiveSent * 100)
              .clamp(0.0, 100.0)
              .toDouble();
    if (_statCount == 0) {
      return PingSummary(
        sent: effectiveSent,
        received: received,
        lossPercent: loss,
        minMs: 0,
        avgMs: 0,
        maxMs: 0,
        jitterMs: 0,
        stdDevMs: 0,
      );
    }
    final count = _statCount;
    final avg = _statSum / count;
    var variance = (_statSumSq / count) - (avg * avg);
    if (variance < 0) variance = 0;
    final jitter = _statJitterCount == 0
        ? 0.0
        : _statJitterSum / _statJitterCount;
    return PingSummary(
      sent: effectiveSent,
      received: received,
      lossPercent: loss,
      minMs: _statMin,
      avgMs: avg,
      maxMs: _statMax,
      jitterMs: jitter,
      stdDevMs: math.sqrt(variance),
    );
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

enum PingLogKind { reply, timeout, note }

class PingLogEntry {
  const PingLogEntry.reply({required this.seq, required this.rttMs, this.ttl})
    : kind = PingLogKind.reply,
      note = null;

  const PingLogEntry.timeout({required this.seq})
    : kind = PingLogKind.timeout,
      rttMs = null,
      ttl = null,
      note = null;

  const PingLogEntry.note(this.note)
    : kind = PingLogKind.note,
      seq = null,
      rttMs = null,
      ttl = null;

  final PingLogKind kind;
  final int? seq;
  final double? rttMs;
  final int? ttl;
  final String? note;
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({
    required this.samples,
    required this.color,
    required this.grid,
  });

  final List<double> samples;
  final Color color;
  final Color grid;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(samples: samples, stroke: color, grid: grid),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.stroke,
    required this.grid,
  });

  final List<double> samples;
  final Color stroke;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.55)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      gridPaint,
    );

    if (samples.isEmpty) return;
    if (samples.length == 1) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(center, 3.2, Paint()..color = stroke);
      return;
    }

    var min = samples.first;
    var max = samples.first;
    for (final sample in samples) {
      if (sample < min) min = sample;
      if (sample > max) max = sample;
    }
    final span = math.max(max - min, 0.5);
    const top = 6.0;
    final bottom = size.height - 8;

    double xAt(int index) => index / (samples.length - 1) * size.width;
    double yAt(double value) =>
        bottom - ((value - min) / span) * (bottom - top);

    final line = Path()..moveTo(xAt(0), yAt(samples.first));
    for (var i = 1; i < samples.length; i++) {
      line.lineTo(xAt(i), yAt(samples[i]));
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [stroke.withValues(alpha: 0.34), stroke.withValues(alpha: 0.0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);

    final last = Offset(xAt(samples.length - 1), yAt(samples.last));
    canvas.drawCircle(last, 3.4, Paint()..color = stroke);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.stroke != stroke ||
        oldDelegate.grid != grid;
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

class _NoteLine extends StatelessWidget {
  const _NoteLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.warning.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 15, color: p.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: p.warning, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
