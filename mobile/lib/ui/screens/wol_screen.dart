import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/net/wol_engine.dart';
import '../../core/util/format.dart';
import '../localization.dart';
import '../theme.dart';
import '../tool_registry.dart';
import '../widgets.dart';

class WolScreen extends StatefulWidget {
  const WolScreen({super.key});

  @override
  State<WolScreen> createState() => _WolScreenState();
}

class _WolScreenState extends State<WolScreen> {
  late final _WolViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _WolViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _delete(WolDevice device) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.tr('Delete device', '刪除裝置'),
      message: context.tr(
        'Remove “${device.name}” from your saved devices?',
        '要從已儲存的裝置中移除「${device.name}」嗎？',
      ),
      confirm: context.tr('Delete', '刪除'),
      cancel: context.tr('Cancel', '取消'),
    );
    if (!mounted || !confirmed) return;
    await _viewModel.remove(device);
  }

  @override
  Widget build(BuildContext context) {
    final accent = adaptiveAccent(
      context,
      toolById('wol')?.accent ?? AppAccents.rose,
    );
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final p = context.palette;
        final outcome = _viewModel.outcome;
        return FrostedPage(
          title: context.tr('Wake-on-LAN', '網路喚醒'),
          subtitle: context.tr('Send a magic packet', '傳送魔法封包'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (outcome != null) ...[
                _SuccessBanner(outcome: outcome),
                const SizedBox(height: 12),
              ],
              if (_viewModel.errorDetail != null) ...[
                ErrorBanner(
                  context.tr(
                    'The magic packet could not be sent.',
                    '無法傳送魔法封包。',
                  ),
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
              SectionLabel(
                context.tr('Saved devices', '已儲存裝置'),
                trailing: _viewModel.devices.isEmpty
                    ? null
                    : Pill('${_viewModel.devices.length}', color: accent),
              ),
              const SizedBox(height: 8),
              if (_viewModel.devices.isEmpty)
                AppCard(
                  child: EmptyState(
                    icon: CupertinoIcons.power,
                    title: context.tr('No saved devices', '尚無已儲存裝置'),
                    body: context.tr(
                      'Add a MAC address below to wake a computer on your local network.',
                      '在下方新增 MAC 位址，即可喚醒區域網路中的電腦。',
                    ),
                  ),
                )
              else
                for (final device in _viewModel.devices) ...[
                  _DeviceCard(
                    device: device,
                    sending: _viewModel.sendingMac == device.mac,
                    busy: _viewModel.sendingMac != null,
                    accent: accent,
                    onWake: () => unawaited(_viewModel.wake(device)),
                    onDelete: () => unawaited(_delete(device)),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 12),
              SectionLabel(context.tr('Add device', '新增裝置')),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppField(
                      label: context.tr('Name (optional)', '名稱（選填）'),
                      controller: _viewModel.nameController,
                      placeholder: context.tr('Living room PC', '客廳電腦'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    AppField(
                      label: context.tr('MAC address', 'MAC 位址'),
                      controller: _viewModel.macController,
                      placeholder: 'AA:BB:CC:DD:EE:FF',
                      monospace: true,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final broadcastField = AppField(
                          label: context.tr('Broadcast', '廣播位址'),
                          controller: _viewModel.broadcastController,
                          placeholder: '255.255.255.255',
                          monospace: true,
                          textInputAction: TextInputAction.next,
                        );
                        final portField = AppField(
                          label: context.tr('Port', '連接埠'),
                          controller: _viewModel.portController,
                          placeholder: '9',
                          monospace: true,
                          keyboardType: TextInputType.number,
                        );
                        if (constraints.maxWidth < 330) {
                          return Column(
                            children: [
                              broadcastField,
                              const SizedBox(height: 12),
                              portField,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: broadcastField),
                            const SizedBox(width: 10),
                            SizedBox(width: 88, child: portField),
                          ],
                        );
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
                                context.tr('Save to my devices', '儲存到我的裝置'),
                                style: TextStyle(color: p.text, fontSize: 13),
                              ),
                              Text(
                                context.tr(
                                  'Keep this device for one-tap wake.',
                                  '保留此裝置以便一鍵喚醒。',
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
                          label: context.tr('Save this device', '儲存到我的裝置'),
                          child: SizedBox(
                            height: 44,
                            child: Center(
                              child: CupertinoSwitch(
                                value: _viewModel.saveDevice,
                                activeTrackColor: accent,
                                onChanged: _viewModel.setSaveDevice,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_viewModel.issue != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(_issueText(context, _viewModel.issue!)),
                    ],
                    if (_viewModel.storageError != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(
                        context.tr(
                          'Could not update saved devices.',
                          '無法更新已儲存裝置。',
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AppButton(
                      label: context.tr('Add device', '新增裝置'),
                      icon: CupertinoIcons.add,
                      onPressed: _viewModel.add,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(CupertinoIcons.info_circle, size: 17, color: p.muted),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Wake-on-LAN works only on the same local network. The target '
                              'device must be connected by Ethernet and have Wake-on-LAN '
                              'enabled in its firmware or operating system.',
                          '網路喚醒僅能在同一個區域網路內運作。目標裝置必須以乙太網路連線，'
                              '並在韌體或作業系統中啟用網路喚醒功能。',
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
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WolViewModel extends ChangeNotifier {
  final AppSettings _settings = AppSettings.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController macController = TextEditingController();
  final TextEditingController broadcastController = TextEditingController(
    text: '255.255.255.255',
  );
  final TextEditingController portController = TextEditingController(text: '9');

  final List<WolDevice> _session = [];
  List<WolDevice> devices = [];
  bool saveDevice = true;
  String? sendingMac;
  WolOutcome? outcome;
  String? errorDetail;
  String? storageError;
  _WolIssue? issue;
  bool _disposed = false;

  _WolViewModel() {
    _reload();
  }

  void _reload() {
    final merged = <String, WolDevice>{};
    for (final device in _settings.savedDevices()) {
      merged[device.mac.toUpperCase()] = device;
    }
    for (final device in _session) {
      merged[device.mac.toUpperCase()] = device;
    }
    devices = merged.values.toList();
  }

  void setSaveDevice(bool value) {
    saveDevice = value;
    notifyListeners();
  }

  void add() {
    if (_disposed) return;
    issue = null;
    outcome = null;
    errorDetail = null;
    storageError = null;

    final mac = normalizeMac(macController.text);
    if (mac == null) {
      issue = _WolIssue.mac;
      notifyListeners();
      return;
    }
    final port = int.tryParse(portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      issue = _WolIssue.port;
      notifyListeners();
      return;
    }
    var broadcast = broadcastController.text.trim();
    if (broadcast.isEmpty) broadcast = '255.255.255.255';
    if (!_validBroadcast(broadcast)) {
      issue = _WolIssue.broadcast;
      notifyListeners();
      return;
    }

    final typedName = nameController.text.trim();
    final device = WolDevice(
      name: typedName.isEmpty ? mac : typedName,
      mac: mac,
      broadcast: broadcast,
      port: port,
    );
    _session.add(device);
    if (saveDevice) {
      unawaited(_persist(device));
    }
    _reload();
    nameController.clear();
    macController.clear();
    notifyListeners();
  }

  Future<void> _persist(WolDevice device) async {
    try {
      await _settings.saveDevice(device);
    } catch (error) {
      if (_disposed) return;
      storageError = _detail(error);
      notifyListeners();
      return;
    }
    if (_disposed) return;
    _session.removeWhere(
      (saved) => saved.mac.toUpperCase() == device.mac.toUpperCase(),
    );
    _reload();
    notifyListeners();
  }

  Future<void> remove(WolDevice device) async {
    try {
      await _settings.removeDevice(device.mac);
    } catch (error) {
      if (_disposed) return;
      storageError = _detail(error);
      notifyListeners();
      return;
    }
    if (_disposed) return;
    _session.removeWhere(
      (saved) => saved.mac.toUpperCase() == device.mac.toUpperCase(),
    );
    _reload();
    if (outcome?.mac.toUpperCase() == device.mac.toUpperCase()) outcome = null;
    notifyListeners();
  }

  Future<void> wake(WolDevice device) async {
    if (_disposed || sendingMac != null) return;
    sendingMac = device.mac;
    outcome = null;
    errorDetail = null;
    notifyListeners();
    try {
      final result = await WolEngine.wake(
        mac: device.mac,
        broadcast: device.broadcast,
        port: device.port,
      );
      if (_disposed) return;
      outcome = result;
      try {
        await _settings.addRecent('wol', device.mac);
      } catch (_) {
        // A history write must not turn a successful wake into an error.
      }
    } catch (error) {
      if (_disposed) return;
      errorDetail = _detail(error);
    } finally {
      if (!_disposed) {
        sendingMac = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    nameController.dispose();
    macController.dispose();
    broadcastController.dispose();
    portController.dispose();
    super.dispose();
  }
}

enum _WolIssue { mac, port, broadcast }

class _DeviceCard extends StatelessWidget {
  final WolDevice device;
  final bool sending;
  final bool busy;
  final Color accent;
  final VoidCallback onWake;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    required this.sending,
    required this.busy,
    required this.accent,
    required this.onWake,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              CupertinoIcons.desktopcomputer,
              size: 19,
              color: accent,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                MonoText(device.mac, size: 12, color: p.muted),
                Text(
                  '${device.broadcast}:${device.port}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          if (sending)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CupertinoActivityIndicator(radius: 8, color: accent),
            )
          else
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              onPressed: busy ? null : onWake,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  CupertinoIcons.power,
                  size: 17,
                  color: accent,
                  semanticLabel: context.tr(
                    'Wake ${device.name}',
                    '喚醒 ${device.name}',
                  ),
                ),
              ),
            ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            onPressed: busy ? null : onDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: p.danger,
              semanticLabel: context.tr(
                'Delete ${device.name}',
                '刪除 ${device.name}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final WolOutcome outcome;

  const _SuccessBanner({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: p.success.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.check_mark_circled, size: 19, color: p.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Magic packet sent', '魔法封包已傳送'),
                  style: TextStyle(
                    color: p.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                    '${outcome.packetsSent} packets sent to ${outcome.mac} '
                        'via ${outcome.address}:${outcome.port}.',
                    '已傳送 ${outcome.packetsSent} 個封包至 ${outcome.mac}，'
                        '經由 ${outcome.address}:${outcome.port}。',
                  ),
                  style: TextStyle(color: p.muted, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _issueText(BuildContext context, _WolIssue issue) {
  switch (issue) {
    case _WolIssue.mac:
      return context.tr(
        'Enter a valid MAC address, for example AA:BB:CC:DD:EE:FF.',
        '請輸入有效的 MAC 位址，例如 AA:BB:CC:DD:EE:FF。',
      );
    case _WolIssue.port:
      return context.tr(
        'The port must be a number between 1 and 65535.',
        '連接埠必須是 1 到 65535 之間的數字。',
      );
    case _WolIssue.broadcast:
      return context.tr(
        'Enter an IPv4 broadcast address or a resolvable hostname.',
        '請輸入 IPv4 廣播位址或可解析的主機名稱。',
      );
  }
}

bool _validBroadcast(String value) {
  if (isValidIpv4(value)) return true;
  if (value.isEmpty || value.length > 253) return false;
  if (value.contains(' ') || value.contains('/') || value.contains(':')) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(value);
}

String _detail(Object error) {
  var text = error.toString();
  if (error is ArgumentError) {
    text = error.message?.toString() ?? text;
  }
  text = text.replaceFirst('SocketException: ', '');
  text = text.replaceFirst('Exception: ', '');
  return text.length > 180 ? '${text.substring(0, 177)}…' : text;
}
