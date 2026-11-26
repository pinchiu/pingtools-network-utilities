import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/native_bridge.dart';
import '../../core/net/geo_engine.dart';
import '../../core/net/ping_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';

class GeoPingScreen extends StatefulWidget {
  const GeoPingScreen({super.key});

  @override
  State<GeoPingScreen> createState() => _GeoPingScreenState();
}

class _GeoPingScreenState extends State<GeoPingScreen> {
  final TextEditingController _host = TextEditingController(text: '8.8.8.8');
  final GeoPingViewModel _vm = GeoPingViewModel();
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _recent = AppSettings.instance.recent('geo');
  }

  @override
  void dispose() {
    _host.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _refreshRecent() {
    final recent = AppSettings.instance.recent('geo');
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
    unawaited(AppSettings.instance.addRecent('geo', host));
    _refreshRecent();
  }

  void _useRecent(String host) {
    _host.text = host;
    _vm.clearError();
  }

  Future<void> _openMaps(PublicIpInfo geo) async {
    final lat = geo.lat;
    final lon = geo.lon;
    if (lat == null || lon == null) return;
    final opened = await NativeBridge.openUrl(
      'https://www.google.com/maps?q=$lat,$lon',
    );
    if (!mounted) return;
    if (!opened) {
      _vm.showError(context.tr('Could not open Maps.', '無法開啟地圖。'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAccent(
      context,
      toolById('geo')?.accent ?? AppAccents.blue,
    );
    return FrostedPage(
      title: context.tr('Geo Ping', '地理 Ping'),
      subtitle: context.tr('Target location & latency', '目標位置與延遲'),
      child: AnimatedBuilder(
        animation: _vm,
        builder: (context, _) => _body(context, accent),
      ),
    );
  }

  Widget _body(BuildContext context, Color accent) {
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
                  vm.clearError();
                  setState(() {});
                },
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
        const SizedBox(height: 18),
        _locationSection(context, accent),
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: ProgressTrack(vm.progress, color: accent)),
              const SizedBox(width: 10),
              MonoText(
                '${vm.completed.clamp(0, GeoPingViewModel.probeCount)}'
                '/${GeoPingViewModel.probeCount}',
                size: 11,
                color: p.muted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statGrid(BuildContext context, Color accent) {
    final p = context.palette;
    final vm = _vm;
    final tiles = [
      StatTile(
        label: context.tr('Avg', '平均'),
        value: vm.averageMs == null ? '—' : fmtLatency(vm.averageMs!),
        accent: accent,
      ),
      StatTile(
        label: context.tr('Min', '最小'),
        value: vm.minMs == null ? '—' : fmtLatency(vm.minMs!),
      ),
      StatTile(
        label: context.tr('Max', '最大'),
        value: vm.maxMs == null ? '—' : fmtLatency(vm.maxMs!),
      ),
      StatTile(
        label: context.tr('Loss', '遺失'),
        value: fmtPercent(vm.lossPercent),
        accent: vm.lossPercent > 0 ? p.danger : p.success,
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

  Widget _locationSection(BuildContext context, Color accent) {
    final vm = _vm;
    if (vm.target == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(context.tr('Location', '位置')),
        const SizedBox(height: 8),
        if (vm.privateIp)
          _privateCard(context)
        else if (vm.geo != null)
          _locationCard(context, vm.geo!, accent)
        else if (vm.geoError != null)
          ErrorBanner(_geoErrorMessage(context, vm.geoError!))
        else if (vm.geoLoading || vm.running)
          _loadingCard(context, accent)
        else
          _unavailableCard(context),
      ],
    );
  }

  Widget _loadingCard(BuildContext context, Color accent) {
    final p = context.palette;
    return AppCard(
      child: Row(
        children: [
          CupertinoActivityIndicator(radius: 8, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr('Locating target…', '正在定位目標…'),
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unavailableCard(BuildContext context) {
    final p = context.palette;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.globe, size: 20, color: p.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                'Location is unavailable. Run a ping to try again.',
                '目前沒有位置資訊，請重新執行 Ping。',
              ),
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _privateCard(BuildContext context) {
    final p = context.palette;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: p.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(CupertinoIcons.lock, size: 18, color: p.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Private address', '私人位址'),
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                    'Geolocation is unavailable for local network addresses. Ping still works on this network.',
                    '本地網路位址無法查詢地理位置。Ping 在此網路仍可正常使用。',
                  ),
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard(BuildContext context, PublicIpInfo geo, Color accent) {
    final p = context.palette;
    final flag = _flagEmoji(geo.countryCode);
    final subtitle = [
      geo.region,
      geo.country,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');
    final hasCoordinates = geo.lat != null && geo.lon != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: flag == null
                    ? Icon(CupertinoIcons.globe, size: 26, color: accent)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(flag, style: const TextStyle(fontSize: 30)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      geo.city ??
                          geo.country ??
                          geo.ip ??
                          context.tr('Unknown location', '未知位置'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DividerLine(color: p.border.withValues(alpha: 0.8)),
          const SizedBox(height: 10),
          if (geo.ip != null) DataRow('IP', geo.ip!),
          if (geo.isp != null && geo.isp!.isNotEmpty)
            DataRow(context.tr('ISP', '網路供應商'), geo.isp!),
          if (geo.org != null && geo.org!.isNotEmpty && geo.org != geo.isp)
            DataRow(context.tr('Organization', '組織'), geo.org!),
          if (geo.asn != null && geo.asn!.isNotEmpty) DataRow('ASN', geo.asn!),
          if (hasCoordinates)
            DataRow(
              context.tr('Coordinates', '座標'),
              '${geo.lat!.toStringAsFixed(4)}, ${geo.lon!.toStringAsFixed(4)}',
            ),
          if (geo.timezone != null && geo.timezone!.isNotEmpty)
            DataRow(context.tr('Timezone', '時區'), geo.timezone!),
          if (hasCoordinates) ...[
            const SizedBox(height: 12),
            AppButton(
              label: context.tr('Open in Maps', '在地圖中開啟'),
              icon: CupertinoIcons.map,
              secondary: true,
              onPressed: () => _openMaps(geo),
            ),
          ],
        ],
      ),
    );
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

  String _geoErrorMessage(BuildContext context, String error) {
    final lower = error.toLowerCase();
    if (lower.contains('offline') ||
        lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('timed out')) {
      return context.tr(
        'Offline or the location service is unreachable. Ping still works.',
        '離線或無法連線至位置服務，Ping 仍可正常使用。',
      );
    }
    return '${context.tr('Location lookup failed', '位置查詢失敗')} — $error';
  }

  String? _flagEmoji(String? countryCode) {
    if (countryCode == null) return null;
    final code = countryCode.trim().toUpperCase();
    if (code.length != 2) return null;
    final units = code.codeUnits;
    if (units.any((unit) => unit < 0x41 || unit > 0x5A)) return null;
    return String.fromCharCodes(units.map((unit) => 0x1F1E6 + unit - 0x41));
  }
}

class GeoPingViewModel extends ChangeNotifier {
  static const int probeCount = 4;

  StreamSubscription<PingEvent>? _sub;
  int _runId = 0;
  bool _disposed = false;

  bool _running = false;
  bool _geoLoading = false;
  bool _privateIp = false;
  PingMode? _mode;
  String? _target;
  String? _resolvedIp;
  String? _note;
  String? _error;
  String? _geoError;
  PingSummary? _summary;
  PublicIpInfo? _geo;
  int _completed = 0;
  List<double> _samples = const [];

  bool get running => _running;
  bool get geoLoading => _geoLoading;
  bool get privateIp => _privateIp;
  PingMode? get mode => _mode;
  String? get target => _target;
  String? get resolvedIp => _resolvedIp;
  String? get note => _note;
  String? get error => _error;
  String? get geoError => _geoError;
  PingSummary? get summary => _summary;
  PublicIpInfo? get geo => _geo;
  int get completed => _completed;
  List<double> get samples => _samples;

  double get progress => (_completed / probeCount).clamp(0.0, 1.0);

  double? get latest => _samples.isEmpty ? null : _samples.last;

  double? get averageMs {
    if (_samples.isEmpty) return null;
    var total = 0.0;
    for (final sample in _samples) {
      total += sample;
    }
    return total / _samples.length;
  }

  double? get minMs {
    if (_samples.isEmpty) return null;
    var min = _samples.first;
    for (final sample in _samples) {
      if (sample < min) min = sample;
    }
    return min;
  }

  double? get maxMs {
    if (_samples.isEmpty) return null;
    var max = _samples.first;
    for (final sample in _samples) {
      if (sample > max) max = sample;
    }
    return max;
  }

  double get lossPercent {
    if (_summary != null) return _summary!.lossPercent;
    if (_completed == 0) return 0;
    final received = _samples.length;
    return ((_completed - received) / _completed * 100)
        .clamp(0.0, 100.0)
        .toDouble();
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
    _geoError = null;
    _summary = null;
    _geo = null;
    _privateIp = false;
    _geoLoading = false;
    _completed = 0;
    _samples = const [];
    _running = true;
    _emit();

    final config = PingConfig(
      host: host,
      count: probeCount,
      intervalMs: 600,
      timeoutMs: 1500,
    );
    _sub = PingEngine.ping(config).listen(
      (event) {
        if (id != _runId) return;
        _onEvent(event, id);
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
          _emit();
        }
      },
    );
  }

  void stop() {
    if (!_running) return;
    _cancel();
    _running = false;
    _emit();
  }

  void _onEvent(PingEvent event, int id) {
    switch (event) {
      case PingStarted(:final resolvedIp, :final mode):
        _mode = mode;
        _resolvedIp = resolvedIp;
        _emit();
        if (resolvedIp != null && resolvedIp.isNotEmpty) {
          _beginLookup(resolvedIp, id);
        }
      case PingReplyEvent(:final reply):
        _completed++;
        _samples = [..._samples, reply.rttMs];
        _emit();
      case PingTimeoutEvent():
        _completed++;
        _emit();
      case PingNoteEvent(:final message):
        _note = message;
        _emit();
      case PingFinishedEvent(:final summary):
        _summary = summary;
        _completed = summary.sent;
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

  void _beginLookup(String ip, int id) {
    if (isPrivateIp(ip)) {
      _privateIp = true;
      _geoLoading = false;
      _emit();
      return;
    }
    unawaited(_lookup(ip, id));
  }

  Future<void> _lookup(String ip, int id) async {
    _geoLoading = true;
    _geoError = null;
    _emit();
    try {
      final info = await GeoEngine.lookup(ip);
      if (_disposed || id != _runId) return;
      if (info.error != null) {
        _geo = null;
        _geoError = info.error;
      } else {
        _geo = info;
        _geoError = null;
      }
    } catch (error) {
      if (_disposed || id != _runId) return;
      _geoError = '$error';
    } finally {
      if (!_disposed && id == _runId) {
        _geoLoading = false;
        _emit();
      }
    }
  }

  void _cancel() {
    _runId++;
    _sub?.cancel();
    _sub = null;
    _geoLoading = false;
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
