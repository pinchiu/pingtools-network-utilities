import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/native_bridge.dart';
import '../../core/net/geo_engine.dart';
import '../localization.dart';
import '../theme.dart';
import '../widgets.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final _ConnectionViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _ConnectionViewModel();
    unawaited(_viewModel.load(initial: true));
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccents.blue;
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final p = context.palette;
        final connection = _viewModel.connection;
        final public = _viewModel.publicInfo;
        final wifi = connection?.wifi;

        return FrostedPage(
          title: context.tr('Connection Info', '連線資訊'),
          subtitle: context.tr('Local & public network', '區域與公開網路'),
          actions: [
            Semantics(
              button: true,
              label: context.tr('Refresh connection info', '重新整理連線資訊'),
              child: CupertinoButton(
                padding: const EdgeInsets.only(right: 12, left: 8),
                onPressed: _viewModel.refreshing || _viewModel.loading
                    ? null
                    : () => unawaited(_viewModel.load()),
                child: _viewModel.refreshing || _viewModel.loading
                    ? Padding(
                        padding: const EdgeInsets.all(7),
                        child: CupertinoActivityIndicator(
                          radius: 8,
                          color: accent,
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: p.elevated.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: p.border, width: 0.7),
                        ),
                        child: Icon(
                          CupertinoIcons.arrow_clockwise,
                          size: 20,
                          color: p.text,
                        ),
                      ),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroCard(
                connection: connection,
                loading: _viewModel.loading,
                accent: accent,
              ),
              if (wifi?.ssid != null && wifi!.ssid!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _WifiSummaryCard(wifi: wifi, accent: accent),
              ],
              const SizedBox(height: 18),
              SectionLabel(context.tr('Connection', '連線')),
              const SizedBox(height: 8),
              if (_viewModel.connectionError != null)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ErrorBanner(
                        context.tr(
                          'Could not read this device’s network details.',
                          '無法讀取此裝置的網路資訊。',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _viewModel.connectionError!,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _DetailsCard(
                  children: [
                    if (connection?.connectionType != null)
                      DataRow(
                        context.tr('Type', '類型'),
                        _connectionLabel(context, connection!.connectionType),
                      ),
                    if (connection?.localIpv4 != null)
                      CopyRow(
                        label: context.tr('Local IPv4', '區域 IPv4'),
                        value: connection!.localIpv4!,
                      ),
                    if (connection?.prefixLength != null)
                      DataRow(
                        context.tr('Prefix length', '前綴長度'),
                        '/${connection!.prefixLength}',
                      ),
                    if (connection?.gateway != null)
                      CopyRow(
                        label: context.tr('Gateway', '閘道'),
                        value: connection!.gateway!,
                      ),
                    if (connection?.localIpv6 != null)
                      CopyRow(
                        label: context.tr('Local IPv6', '區域 IPv6'),
                        value: connection!.localIpv6!,
                      ),
                    if (connection != null && connection.dnsServers.isNotEmpty)
                      CopyRow(
                        label: context.tr('DNS servers', 'DNS 伺服器'),
                        value: connection.dnsServers.join(', '),
                      ),
                    if (connection?.mobileOperator != null &&
                        connection!.mobileOperator!.isNotEmpty)
                      DataRow(
                        context.tr('Mobile operator', '行動網路業者'),
                        connection.mobileOperator!,
                      ),
                    if (connection?.isVpn == true)
                      DataRow(
                        context.tr('VPN', 'VPN'),
                        context.tr('Active', '已啟用'),
                        valueColor: p.warning,
                      ),
                    if (connection == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: CupertinoActivityIndicator(
                            radius: 9,
                            color: accent,
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              SectionLabel(context.tr('Public network', '公開網路')),
              const SizedBox(height: 8),
              if (public != null && public.ip != null)
                _PublicCard(info: public, accent: accent)
              else if (_viewModel.loading)
                _DetailsCard(
                  children: [
                    Row(
                      children: [
                        CupertinoActivityIndicator(radius: 8, color: accent),
                        const SizedBox(width: 10),
                        Text(
                          context.tr('Looking up public IP…', '正在查詢公開 IP…'),
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                )
              else if (public?.error != null || _viewModel.publicError != null)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ErrorBanner(
                        context.tr(
                          'Public IP information is unavailable. Check your connection.',
                          '無法取得公開 IP 資訊，請檢查網路連線。',
                        ),
                      ),
                      if (_viewModel.publicError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _viewModel.publicError!,
                            style: TextStyle(
                              color: p.muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                _DetailsCard(
                  children: [
                    Text(
                      context.tr('No public network data.', '沒有公開網路資料。'),
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              SectionLabel(context.tr('Wi-Fi', 'Wi-Fi')),
              const SizedBox(height: 8),
              if (wifi == null || wifi.ssid == null || wifi.ssid!.isEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              CupertinoIcons.wifi,
                              size: 18,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr(
                                    'Wi-Fi details are hidden',
                                    'Wi-Fi 資訊已隱藏',
                                  ),
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  context.tr(
                                    'Android requires nearby-Wi-Fi or location permission '
                                        'before the SSID and signal details can be read.',
                                    'Android 需要鄰近 Wi-Fi 或位置權限，才能讀取 SSID 與訊號資訊。',
                                  ),
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_viewModel.wifiDenied)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ErrorBanner(
                            context.tr(
                              'Permission was denied. You can enable it later in system settings.',
                              '權限已被拒絕，之後可在系統設定中開啟。',
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: context.tr('Allow Wi-Fi access', '允許 Wi-Fi 存取'),
                        icon: CupertinoIcons.location,
                        secondary: true,
                        loading: _viewModel.requestingWifi,
                        onPressed: _viewModel.requestingWifi
                            ? null
                            : () => unawaited(_viewModel.requestWifi()),
                      ),
                    ],
                  ),
                )
              else
                _DetailsCard(
                  children: [
                    if (wifi.ssid != null)
                      CopyRow(
                        label: context.tr('SSID', 'SSID'),
                        value: wifi.ssid!,
                      ),
                    if (wifi.bssid != null)
                      CopyRow(
                        label: context.tr('BSSID', 'BSSID'),
                        value: wifi.bssid!,
                      ),
                    if (wifi.rssiDbm != null)
                      DataRow(
                        context.tr('Signal', '訊號'),
                        '${wifi.rssiDbm} dBm'
                        '${_wifiQuality(context, wifi.rssiDbm) == null ? '' : ' · ${_wifiQuality(context, wifi.rssiDbm)}'}',
                      ),
                    if (wifi.linkSpeedMbps != null)
                      DataRow(
                        context.tr('Link speed', '連線速度'),
                        '${wifi.linkSpeedMbps} Mbps',
                      ),
                    if (wifi.frequencyMhz != null)
                      DataRow(
                        context.tr('Frequency', '頻率'),
                        '${wifi.frequencyMhz} MHz'
                        '${wifi.frequencyMhz! >= 5000 ? ' · 5 GHz' : ' · 2.4 GHz'}',
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionViewModel extends ChangeNotifier {
  ConnectionInfo? connection;
  PublicIpInfo? publicInfo;
  bool loading = true;
  bool refreshing = false;
  bool requestingWifi = false;
  bool wifiDenied = false;
  String? connectionError;
  String? publicError;
  bool _inFlight = false;
  bool _disposed = false;

  Future<void> load({bool initial = false}) async {
    if (_disposed || _inFlight) return;
    _inFlight = true;
    if (initial) {
      loading = true;
    } else {
      refreshing = true;
    }
    connectionError = null;
    publicError = null;
    notifyListeners();

    try {
      try {
        connection = await NativeBridge.connectionInfo();
      } catch (error) {
        connectionError = _shortError(error);
      }
      _notify();

      try {
        final info = await GeoEngine.publicIp();
        publicInfo = info;
        publicError = info.error;
      } catch (error) {
        publicError = _shortError(error);
      }
      _notify();
    } finally {
      _inFlight = false;
      if (!_disposed) {
        loading = false;
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> requestWifi() async {
    if (requestingWifi) return;
    requestingWifi = true;
    wifiDenied = false;
    notifyListeners();
    try {
      final granted = await NativeBridge.requestWifiPermissions();
      if (_disposed) return;
      requestingWifi = false;
      wifiDenied = !granted;
      notifyListeners();
      if (granted) await load();
    } catch (_) {
      if (_disposed) return;
      requestingWifi = false;
      wifiDenied = true;
      notifyListeners();
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

class _HeroCard extends StatelessWidget {
  final ConnectionInfo? connection;
  final bool loading;
  final Color accent;

  const _HeroCard({
    required this.connection,
    required this.loading,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final localIp = connection?.localIpv4;
    return AppCard(
      padding: const EdgeInsets.all(18),
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
                child: Icon(
                  CupertinoIcons.info_circle,
                  size: 21,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('CONNECTED VIA', '連線方式'),
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
                            loading && connection == null
                                ? context.tr('Checking…', '檢查中…')
                                : _connectionLabel(
                                    context,
                                    connection?.connectionType,
                                  ),
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
                        if (connection?.isVpn == true)
                          Pill('VPN', color: AppAccents.violet),
                      ],
                    ),
                  ],
                ),
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
                    localIp ?? (loading ? '…' : '—'),
                    size: 26,
                    weight: FontWeight.w600,
                    color: localIp == null ? p.muted : p.text,
                    maxLines: 1,
                  ),
                ),
              ),
              if (localIp != null) _CopyButton(value: localIp),
              if (connection?.prefixLength != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Pill('/${connection!.prefixLength}', color: accent),
                ),
            ],
          ),
          if (connection?.gateway != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${context.tr('Gateway', '閘道')} ${connection!.gateway}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicCard extends StatelessWidget {
  final PublicIpInfo info;
  final Color accent;

  const _PublicCard({required this.info, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ip = info.ip ?? '';
    final flag = _flag(info.countryCode);
    final location = [
      flag,
      info.city,
      info.country,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.globe, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoText(
                      ip,
                      size: 18,
                      weight: FontWeight.w600,
                      maxLines: 1,
                    ),
                    if (location.isNotEmpty)
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              _CopyButton(value: ip),
            ],
          ),
          const SizedBox(height: 12),
          DividerLine(color: p.border.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          if (info.isp != null && info.isp!.isNotEmpty)
            DataRow(context.tr('ISP', 'ISP'), info.isp!),
          if (info.org != null && info.org!.isNotEmpty)
            DataRow(context.tr('Organization', '組織'), info.org!),
          if (info.asn != null && info.asn!.isNotEmpty)
            DataRow('ASN', info.asn!),
          if (info.region != null && info.region!.isNotEmpty)
            DataRow(context.tr('Region', '地區'), info.region!),
          if (info.timezone != null && info.timezone!.isNotEmpty)
            DataRow(context.tr('Timezone', '時區'), info.timezone!),
          if (info.lat != null && info.lon != null)
            DataRow(
              context.tr('Coordinates', '座標'),
              '${info.lat!.toStringAsFixed(3)}, ${info.lon!.toStringAsFixed(3)}',
            ),
        ],
      ),
    );
  }
}

class _WifiSummaryCard extends StatelessWidget {
  final WifiDetails wifi;
  final Color accent;

  const _WifiSummaryCard({required this.wifi, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(CupertinoIcons.wifi, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wifi.ssid ?? context.tr('Wi-Fi', 'Wi-Fi'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if (wifi.rssiDbm != null) '${wifi.rssiDbm} dBm',
                    if (_wifiQuality(context, wifi.rssiDbm) != null)
                      _wifiQuality(context, wifi.rssiDbm)!,
                  ].join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (wifi.linkSpeedMbps != null)
            Pill('${wifi.linkSpeedMbps} Mbps', color: accent),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final List<Widget> children;

  const _DetailsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final visible = children.where((child) => child is! SizedBox).toList();
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 8),
              DividerLine(color: p.border.withValues(alpha: 0.55)),
              const SizedBox(height: 8),
            ],
            visible[i],
          ],
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  final String value;

  const _CopyButton({required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: context.tr('Copy', '複製'),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        onPressed: () async {
          try {
            await Clipboard.setData(ClipboardData(text: value));
            HapticFeedback.selectionClick();
          } catch (_) {
            // Clipboard access can be unavailable on some platforms.
          }
        },
        child: Icon(CupertinoIcons.doc_on_doc, size: 16, color: p.muted),
      ),
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
  if (value.contains('vpn')) return context.tr('VPN', 'VPN');
  if (value.isEmpty || value.contains('unknown')) {
    return context.tr('Unknown', '未知');
  }
  return raw!;
}

String? _wifiQuality(BuildContext context, int? rssi) {
  if (rssi == null) return null;
  if (rssi >= -50) return context.tr('Excellent', '極佳');
  if (rssi >= -60) return context.tr('Good', '良好');
  if (rssi >= -70) return context.tr('Fair', '普通');
  return context.tr('Weak', '微弱');
}

String _shortError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 160 ? '${text.substring(0, 157)}…' : text;
}

String _flag(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) return '';
  final code = countryCode.toUpperCase();
  final first = code.codeUnitAt(0);
  final second = code.codeUnitAt(1);
  if (first < 65 || first > 90 || second < 65 || second > 90) return '';
  return String.fromCharCodes([0x1F1E6 + first - 65, 0x1F1E6 + second - 65]);
}
