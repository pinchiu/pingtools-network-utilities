import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/app_settings.dart';
import '../../core/models.dart';
import '../../core/native_bridge.dart';
import '../../core/net/update_service.dart';
import '../localization.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _SettingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _SettingsViewModel();
    unawaited(_viewModel.loadVersion());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _downloadAndInstall() async {
    while (mounted) {
      final outcome = await _viewModel.downloadAndInstall();
      if (!mounted || outcome == null) return;
      if (outcome.status != InstallStatus.permissionRequired) return;

      final retry = await showConfirmDialog(
        context,
        title: context.tr('Allow installs', '允許安裝'),
        message: context.tr(
          'Android needs permission to install apps from PingTools. '
              'Enable “Allow from this source” in the system settings, then tap Retry.',
          'Android 需要允許 PingTools 安裝應用程式。請在系統設定中開啟「允許來自此來源」，然後點選「重試」。',
        ),
        confirm: context.tr('Retry', '重試'),
        cancel: context.tr('Cancel', '取消'),
      );
      if (!mounted || !retry) return;
    }
  }

  Future<void> _openGithub() async {
    final opened = await NativeBridge.openUrl(
      'https://github.com/${UpdateService.repository}',
    );
    if (!mounted || opened) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(dialogContext.tr('Could not open link', '無法開啟連結')),
        content: Text(
          dialogContext.tr(
            'No browser is available to open GitHub.',
            '沒有可開啟 GitHub 的瀏覽器。',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.tr('OK', '確定')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([settings, _viewModel]),
      builder: (context, _) {
        final p = context.palette;
        final info = _viewModel.info;
        final localeValue = settings.localeCode == 'zh' ? 'zh' : 'en';
        final themeValue =
            const {'system', 'light', 'dark'}.contains(settings.themeMode)
            ? settings.themeMode
            : 'system';
        return FrostedPage(
          title: context.tr('Settings', '設定'),
          subtitle: context.tr('Preferences & updates', '偏好設定與更新'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsCard(
                icon: CupertinoIcons.globe,
                title: context.tr('Language', '語言'),
                subtitle: context.tr('Applies immediately', '立即套用'),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: localeValue,
                    backgroundColor: p.elevated.withValues(alpha: 0.9),
                    children: const {'en': Text('English'), 'zh': Text('繁體中文')},
                    onValueChanged: (value) {
                      if (value != null) unawaited(settings.setLocale(value));
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                icon: CupertinoIcons.brightness,
                title: context.tr('Appearance', '外觀'),
                subtitle: context.tr('System follows your device', '系統會跟隨裝置設定'),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: themeValue,
                    backgroundColor: p.elevated.withValues(alpha: 0.9),
                    children: {
                      'system': Text(context.tr('System', '系統')),
                      'light': Text(context.tr('Light', '淺色')),
                      'dark': Text(context.tr('Dark', '深色')),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        unawaited(settings.setThemeMode(value));
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                icon: CupertinoIcons.arrow_down_circle,
                title: context.tr('Updates', '更新'),
                subtitle: context.tr(
                  'Checked against GitHub releases',
                  '透過 GitHub Releases 檢查',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('Current version', '目前版本'),
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                        ),
                        MonoText(
                          _viewModel.version.isEmpty
                              ? '—'
                              : 'v${_viewModel.version}',
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ],
                    ),
                    if (info?.hasUpdate == true) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('Latest release', '最新版本'),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ),
                          MonoText(
                            info!.latestVersion.isEmpty
                                ? info.tag
                                : 'v${info.latestVersion}',
                            size: 13,
                            weight: FontWeight.w600,
                            color: p.success,
                          ),
                        ],
                      ),
                    ],
                    if (_viewModel.message == _SettingsMessage.upToDate)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Pill(
                          context.tr('You are up to date', '已是最新版本'),
                          color: p.success,
                        ),
                      ),
                    if (info?.hasUpdate == true &&
                        info!.releaseNotes.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: p.elevated.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: _ReleaseNotes(notes: info.releaseNotes),
                      ),
                    ],
                    if (_viewModel.issue != _SettingsIssue.none) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(_issueTitle(context, _viewModel.issue)),
                      if (_viewModel.detail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, left: 2),
                          child: Text(
                            _viewModel.detail!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                    if (_viewModel.downloading) ...[
                      const SizedBox(height: 14),
                      ProgressTrack(_viewModel.progress, color: p.primary),
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'Downloading update… ${(_viewModel.progress * 100).round()}%',
                          '正在下載更新… ${(_viewModel.progress * 100).round()}%',
                        ),
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ],
                    if (_viewModel.installing)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            CupertinoActivityIndicator(
                              radius: 7,
                              color: p.primary,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              context.tr('Opening installer…', '正在開啟安裝程式…'),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    if (_viewModel.message == _SettingsMessage.installerOpened)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.check_mark_circled,
                              size: 16,
                              color: p.success,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                context.tr(
                                  'Installer opened. Follow the system prompt to finish.',
                                  '安裝程式已開啟，請依系統提示完成安裝。',
                                ),
                                style: TextStyle(
                                  color: p.success,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    if (info?.hasUpdate == true)
                      AppButton(
                        label: context.tr('Download & install', '下載並安裝'),
                        icon: CupertinoIcons.arrow_down_to_line,
                        loading: _viewModel.downloading,
                        onPressed: _viewModel.busy
                            ? null
                            : () => unawaited(_downloadAndInstall()),
                      )
                    else
                      AppButton(
                        label: context.tr('Check now', '立即檢查'),
                        icon: CupertinoIcons.arrow_clockwise,
                        secondary: true,
                        loading: _viewModel.checking,
                        onPressed: _viewModel.busy
                            ? null
                            : () => unawaited(_viewModel.check()),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                icon: CupertinoIcons.link,
                title: context.tr('Project', '專案'),
                child: SpringyTap(
                  onTap: _openGithub,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.square_arrow_up,
                          size: 17,
                          color: p.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.tr(
                              'View source on GitHub',
                              '在 GitHub 檢視原始碼',
                            ),
                            style: TextStyle(color: p.text, fontSize: 14),
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_forward,
                          size: 14,
                          color: p.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                icon: CupertinoIcons.lock_shield,
                title: context.tr('Privacy', '隱私'),
                child: Text(
                  context.tr(
                    'Every check runs on this device. No accounts, no ads, no analytics, '
                        'and no data is uploaded by PingTools.',
                    '所有檢查都在本機執行。PingTools 沒有帳號、廣告或分析，也不會上傳任何資料。',
                  ),
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.45),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _viewModel.version.isEmpty
                    ? 'PingTools'
                    : 'PingTools v${_viewModel.version}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'No ads · No trackers · On-device',
                  '無廣告 · 無追蹤 · 裝置端處理',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.muted.withValues(alpha: 0.75),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsViewModel extends ChangeNotifier {
  bool checking = false;
  bool downloading = false;
  bool installing = false;
  double progress = 0;
  UpdateInfo? info;
  String version = '';
  _SettingsIssue issue = _SettingsIssue.none;
  _SettingsMessage message = _SettingsMessage.none;
  String? detail;
  String? _apkPath;
  bool _disposed = false;

  bool get busy => checking || downloading || installing;

  Future<void> loadVersion() async {
    final value = await NativeBridge.appVersion();
    if (_disposed) return;
    version = value;
    notifyListeners();
  }

  Future<void> check() async {
    if (busy) return;
    checking = true;
    issue = _SettingsIssue.none;
    message = _SettingsMessage.none;
    detail = null;
    notifyListeners();
    try {
      final result = await UpdateService.check();
      if (_disposed) return;
      if (result.latestVersion != info?.latestVersion) _apkPath = null;
      info = result;
      if (result.error != null) {
        issue = _SettingsIssue.check;
        detail = result.error;
      } else if (!result.hasUpdate) {
        message = _SettingsMessage.upToDate;
      }
    } catch (error) {
      if (_disposed) return;
      issue = _SettingsIssue.check;
      detail = _detail(error);
    }
    checking = false;
    notifyListeners();
  }

  Future<InstallOutcome?> downloadAndInstall() async {
    if (busy) return null;
    var update = info;
    if (update == null) {
      await check();
      if (_disposed) return null;
      update = info;
      if (update == null) return null;
    }
    if (!update.hasUpdate) {
      message = _SettingsMessage.upToDate;
      notifyListeners();
      return null;
    }

    if (_apkPath == null) {
      downloading = true;
      progress = 0;
      issue = _SettingsIssue.none;
      message = _SettingsMessage.none;
      detail = null;
      notifyListeners();
      try {
        final file = await UpdateService.download(
          update,
          onProgress: (value) {
            if (_disposed) return;
            progress = value;
            notifyListeners();
          },
        );
        if (_disposed) return null;
        _apkPath = file.path;
        progress = 1;
      } catch (error) {
        if (_disposed) return null;
        downloading = false;
        issue = _SettingsIssue.download;
        detail = _detail(error);
        notifyListeners();
        return null;
      }
      downloading = false;
      notifyListeners();
    }

    return _install(_apkPath!);
  }

  Future<InstallOutcome?> _install(String path) async {
    installing = true;
    issue = _SettingsIssue.none;
    message = _SettingsMessage.none;
    detail = null;
    notifyListeners();

    final outcome = await NativeBridge.installApk(path);
    if (_disposed) return outcome;
    installing = false;
    switch (outcome.status) {
      case InstallStatus.launched:
        message = _SettingsMessage.installerOpened;
        break;
      case InstallStatus.permissionRequired:
        break;
      case InstallStatus.error:
        issue = _SettingsIssue.install;
        detail = outcome.message;
        break;
    }
    notifyListeners();
    return outcome;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

enum _SettingsIssue { none, check, download, install }

enum _SettingsMessage { none, upToDate, installerOpened }

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: p.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ReleaseNotes extends StatefulWidget {
  final String notes;

  const _ReleaseNotes({required this.notes});

  @override
  State<_ReleaseNotes> createState() => _ReleaseNotesState();
}

class _ReleaseNotesState extends State<_ReleaseNotes> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final needsToggle =
        widget.notes.length > 280 || '\n'.allMatches(widget.notes).length > 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Release notes', '版本說明'),
          style: TextStyle(
            color: p.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          widget.notes,
          maxLines: _expanded ? 100 : 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.text, fontSize: 12, height: 1.4),
        ),
        if (needsToggle)
          CupertinoButton(
            padding: const EdgeInsets.only(top: 4),
            minimumSize: Size.zero,
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? context.tr('Show less', '顯示較少')
                  : context.tr('Show more', '顯示更多'),
              style: TextStyle(color: p.primary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

String _issueTitle(BuildContext context, _SettingsIssue issue) {
  switch (issue) {
    case _SettingsIssue.check:
      return context.tr('Could not check for updates', '無法檢查更新');
    case _SettingsIssue.download:
      return context.tr('Update download failed', '更新下載失敗');
    case _SettingsIssue.install:
      return context.tr('Could not start the installer', '無法啟動安裝程式');
    case _SettingsIssue.none:
      return '';
  }
}

String _detail(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 220 ? '${text.substring(0, 217)}…' : text;
}
