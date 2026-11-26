import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/models.dart';
import '../../core/native_bridge.dart';
import '../../core/net/geo_engine.dart';
import '../../core/net/update_service.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';
import 'connection_screen.dart';
import 'dns_screen.dart';
import 'geo_ping_screen.dart';
import 'http_screen.dart';
import 'ping_screen.dart';
import 'port_scanner_screen.dart';
import 'settings_screen.dart';
import 'subnet_screen.dart';
import 'traceroute_screen.dart';
import 'whois_screen.dart';
import 'wol_screen.dart';

/// Dashboard: connectivity at a glance plus the full tool grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _HomeViewModel();
    unawaited(_viewModel.load());
    unawaited(_viewModel.loadVersion());
    unawaited(_viewModel.checkUpdate());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _openTool(ToolInfo tool) {
    final Widget screen;
    switch (tool.id) {
      case 'ping':
        screen = const PingScreen();
      case 'geo':
        screen = const GeoPingScreen();
      case 'trace':
        screen = const TracerouteScreen();
      case 'ports':
        screen = const PortScannerScreen();
      case 'dns':
        screen = const DnsScreen();
      case 'whois':
        screen = const WhoisScreen();
      case 'subnet':
        screen = const SubnetScreen();
      case 'wol':
        screen = const WolScreen();
      case 'connection':
        screen = const ConnectionScreen();
      case 'http':
        screen = const HttpScreen();
      default:
        return;
    }
    Navigator.of(context)
        .push(CupertinoPageRoute<void>(builder: (_) => screen));
  }

  void _openSettings() {
    Navigator.of(context)
        .push(CupertinoPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final update = _viewModel.update;
        return FrostedPage(
          title: 'PingTools',
          subtitle: context.tr('Network utilities', '網路工具'),
          showBack: false,
          actions: [
            Semantics(
              button: true,
              label: context.tr('Settings', '設定'),
              child: CupertinoButton(
                padding: const EdgeInsets.only(right: 12, left: 8),
                onPressed: _openSettings,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: p.elevated.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: p.border, width: 0.7),
                  ),
                  child: Icon(CupertinoIcons.gear, color: p.text, size: 20),
                ),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectionHero(
                viewModel: _viewModel,
                onRefresh: () => unawaited(_viewModel.load()),
                onOpen: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const ConnectionScreen(),
                  ),
                ),
              ),
              if (update != null && update.hasUpdate) ...[
                const SizedBox(height: 12),
                _UpdateBanner(
                  version: update.latestVersion.isNotEmpty
                      ? update.latestVersion
                      : update.tag,
                  onTap: _openSettings,
                ),
              ],
              if (_viewModel.publicError != null &&
                  _viewModel.publicInfo?.ip == null) ...[
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Public IP lookup is unavailable right now.',
                    '目前無法取得公開 IP。',
                  ),
                  style: TextStyle(color: p.muted, fontSize: 11),
                ),
              ],
              const SizedBox(height: 18),
              SectionLabel(context.tr('Tools', '工具')),
              const SizedBox(height: 10),
              _ToolsGrid(onOpen: _openTool),
              const SizedBox(height: 26),
              _Footer(version: _viewModel.version),
            ],
          ),
        );
      },
    );
  }
}

class _HomeViewModel extends ChangeNotifier {
  ConnectionInfo? connection;
  PublicIpInfo? publicInfo;
  String? connectionError;
  String? publicError;
  bool loading = false;
  bool _disposed = false;

  UpdateInfo? update;
  String version = '';

  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    connectionError = null;
    publicError = null;
    _notify();

    try {
      connection = await NativeBridge.connectionInfo();
    } catch (error) {
      connectionError = _shortError(error);
    }
    _notify();

    try {
      final info = await GeoEngine.publicIp();
      if (_disposed) return;
      publicInfo = info;
      publicError = info.error;
    } catch (error) {
      publicError = _shortError(error);
    }
    if (_disposed) return;
    loading = false;
    _notify();
  }

  Future<void> loadVersion() async {
    final value = await NativeBridge.appVersion();
    if (_disposed) return;
    version = value;
    _notify();
  }

  /// Silent background check; failures simply leave the banner hidden.
  Future<void> checkUpdate() async {
    try {
      final result = await UpdateService.check();
      if (_disposed) return;
      update = result;
      _notify();
    } catch (_) {
      // Updates are optional; never disturb the dashboard.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _ConnectionHero extends StatelessWidget {
  final _HomeViewModel viewModel;
  final VoidCallback onRefresh;
  final VoidCallback onOpen;

  const _ConnectionHero({
    required this.viewModel,
    required this.onRefresh,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final info = viewModel.connection;
    final public = viewModel.publicInfo;
    final accent = AppAccents.blue;
    final localIp = info?.localIpv4;
    final prefix = info?.prefixLength;
    final isVpn = info?.isVpn == true;
    final wifiName = info?.wifi?.ssid;

    return AppCard(
      padding: const EdgeInsets.all(18),
      onTap: onOpen,
      color: p.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.3),
                    width: 0.7,
                  ),
                ),
                child: Icon(CupertinoIcons.wifi, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('THIS DEVICE', '本機裝置'),
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _connectionLabel(context, info?.connectionType),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        if (isVpn) Pill('VPN', color: AppAccents.violet),
                      ],
                    ),
                    if (wifiName != null && wifiName.isNotEmpty)
                      Text(
                        wifiName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RefreshButton(
                loading: viewModel.loading,
                accent: accent,
                onTap: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            context.tr('LOCAL IPV4', '區域 IPv4'),
            style: TextStyle(
              color: p.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MonoText(
                    localIp ?? (viewModel.loading ? '…' : '—'),
                    size: 26,
                    weight: FontWeight.w600,
                    color: localIp == null ? p.muted : p.text,
                    maxLines: 1,
                  ),
                ),
              ),
              if (localIp != null && prefix != null)
                Pill('/$prefix', color: accent),
            ],
          ),
          if (viewModel.connectionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tr('Network details unavailable.', '無法取得網路資訊。'),
                style: TextStyle(color: p.danger, fontSize: 11),
              ),
            ),
          const SizedBox(height: 14),
          DividerLine(color: p.border.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(CupertinoIcons.globe, size: 16, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('PUBLIC IP', '公開 IP'),
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (public != null && public.ip != null)
                      Row(
                        children: [
                          Expanded(
                            child: MonoText(
                              public.ip!,
                              size: 16,
                              weight: FontWeight.w600,
                              maxLines: 1,
                            ),
                          ),
                          if (_flag(public.countryCode).isNotEmpty)
                            Text(
                              _flag(public.countryCode),
                              style: const TextStyle(fontSize: 14),
                            ),
                        ],
                      )
                    else if (viewModel.loading)
                      Row(
                        children: [
                          CupertinoActivityIndicator(radius: 6, color: p.muted),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('Fetching…', '取得中…'),
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                        ],
                      )
                    else
                      Text('—', style: TextStyle(color: p.muted, fontSize: 16)),
                    if (public != null && public.ip != null)
                      Text(
                        [
                          if (public.isp != null && public.isp!.isNotEmpty)
                            public.isp,
                          if (public.asn != null && public.asn!.isNotEmpty)
                            public.asn,
                          if (public.city != null && public.city!.isNotEmpty)
                            public.city,
                          if (public.country != null &&
                              public.country!.isNotEmpty)
                            public.country,
                        ].whereType<String>().join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 14,
                  color: p.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final bool loading;
  final Color accent;
  final VoidCallback onTap;

  const _RefreshButton({
    required this.loading,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: context.tr('Refresh network status', '重新整理網路狀態'),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: loading ? null : onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: p.elevated.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.border, width: 0.7),
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(9),
                  child: CupertinoActivityIndicator(radius: 6, color: accent),
                )
              : Icon(CupertinoIcons.arrow_clockwise, size: 17, color: p.text),
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final String version;
  final VoidCallback onTap;

  const _UpdateBanner({required this.version, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = AppAccents.green;
    return SpringyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.arrow_down_circle, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Update available', '有可用的更新'),
                    style: TextStyle(
                      color: p.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    context.tr(
                      version.isEmpty
                          ? 'Open Settings to install the latest build.'
                          : 'Version $version is ready — open Settings to install.',
                      version.isEmpty
                          ? '開啟設定以安裝最新版本。'
                          : '版本 $version 已就緒 — 開啟設定即可安裝。',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_forward, size: 14, color: accent),
          ],
        ),
      ),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  final void Function(ToolInfo tool) onOpen;

  const _ToolsGrid({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 600
            ? 2
            : width < 900
            ? 3
            : 4;
        const spacing = 12.0;
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tool in tools)
              SizedBox(
                width: cardWidth,
                child: _ToolCard(tool: tool, onTap: () => onOpen(tool)),
              ),
          ],
        );
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolInfo tool;
  final VoidCallback onTap;

  const _ToolCard({required this.tool, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SpringyTap(
      onTap: onTap,
      child: Container(
        height: 112,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: p.border.withValues(alpha: 0.8),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tool.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(tool.icon, size: 18, color: tool.accent),
                ),
                const Spacer(),
                if (tool.tag != null) Pill(tool.tag!, color: tool.accent),
              ],
            ),
            const Spacer(),
            Text(
              tool.title(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tool.subtitle(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 10.5, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final String version;

  const _Footer({required this.version});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Text(
          version.isEmpty ? 'PingTools' : 'PingTools v$version',
          style: TextStyle(
            color: p.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('No ads · No trackers · On-device', '無廣告 · 無追蹤 · 裝置端處理'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: p.muted.withValues(alpha: 0.75),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

String _connectionLabel(BuildContext context, String? raw) {
  final value = (raw ?? '').toLowerCase();
  if (value.contains('wifi') || value.contains('wi-fi')) {
    return context.tr('Wi-Fi', 'Wi-Fi');
  }
  if (value.contains('cell') || value.contains('mobile')) {
    return context.tr('Cellular', '行動網路');
  }
  if (value.contains('eth')) {
    return context.tr('Ethernet', '乙太網路');
  }
  if (value.contains('vpn')) {
    return context.tr('VPN', 'VPN');
  }
  if (value.isEmpty || value.contains('unknown')) {
    return context.tr('Unknown', '未知');
  }
  return raw!;
}

String _shortError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 140 ? '${text.substring(0, 137)}…' : text;
}

String _flag(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) return '';
  final code = countryCode.toUpperCase();
  final first = code.codeUnitAt(0);
  final second = code.codeUnitAt(1);
  if (first < 65 || first > 90 || second < 65 || second > 90) return '';
  return String.fromCharCodes([0x1F1E6 + first - 65, 0x1F1E6 + second - 65]);
}
