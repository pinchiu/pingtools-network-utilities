import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// App-wide preferences: locale, appearance, recent inputs and saved devices.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kLocale = 'locale';
  static const _kTheme = 'theme_mode';
  static const _kDevices = 'wol_devices';
  static const _recentLimit = 8;

  late SharedPreferences _prefs;
  String _localeCode = 'en';
  String _themeMode = 'system';

  final Map<String, Timer> _inputTimers = {};
  final Map<String, String> _pendingInputs = {};

  String get localeCode => _localeCode;
  String get themeMode => _themeMode;
  bool get isZh => _localeCode == 'zh';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final systemIsChinese = Platform.localeName.toLowerCase().startsWith('zh');
    _localeCode = _prefs.getString(_kLocale) ?? (systemIsChinese ? 'zh' : 'en');
    _themeMode = _prefs.getString(_kTheme) ?? 'system';
  }

  Future<void> setLocale(String code) async {
    if (code == _localeCode) return;
    _localeCode = code == 'zh' ? 'zh' : 'en';
    await _prefs.setString(_kLocale, _localeCode);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _prefs.setString(_kTheme, mode);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Form input memory
  // -------------------------------------------------------------------------

  /// Saved value for a tool's primary text field, or [fallback].
  String inputOrDefault(String tool, String fallback) {
    final value = _prefs.getString('last_$tool');
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  /// Debounced write while the user types (300 ms).
  void rememberInput(String tool, String value) {
    _pendingInputs[tool] = value;
    _inputTimers.remove(tool)?.cancel();
    _inputTimers[tool] = Timer(const Duration(milliseconds: 300), () {
      _inputTimers.remove(tool);
      final pending = _pendingInputs.remove(tool);
      if (pending != null) {
        _prefs.setString('last_$tool', pending);
      }
    });
  }

  /// Immediate write when starting a run or leaving a screen.
  Future<void> rememberInputNow(String tool, String value) async {
    _inputTimers.remove(tool)?.cancel();
    _pendingInputs.remove(tool);
    await _prefs.setString('last_$tool', value);
  }

  Future<void> flushInputs() async {
    for (final entry in _pendingInputs.entries) {
      _inputTimers.remove(entry.key)?.cancel();
      await _prefs.setString('last_${entry.key}', entry.value);
    }
    _pendingInputs.clear();
  }

  /// Generic preference helpers for dropdowns and switches.
  String? prefString(String key) => _prefs.getString(key);

  bool? prefBool(String key) => _prefs.getBool(key);

  Future<void> setPrefString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> setPrefBool(String key, bool value) =>
      _prefs.setBool(key, value);

  List<String> recent(String tool, {int limit = 5}) {
    final value = _prefs.getString('recent_$tool');
    if (value == null) return const [];
    try {
      final list = (jsonDecode(value) as List).cast<String>();
      return list.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRecent(String tool, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final updated = <String>{
      trimmed,
      ...recent(tool, limit: _recentLimit),
    }.take(_recentLimit).toList();
    await _prefs.setString('recent_$tool', jsonEncode(updated));
  }

  List<WolDevice> savedDevices() {
    final value = _prefs.getString(_kDevices);
    if (value == null) return const [];
    try {
      final list = jsonDecode(value) as List;
      return list
          .whereType<Map>()
          .map((e) => WolDevice.fromJson(Map<String, dynamic>.from(e)))
          .where((d) => d.mac.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveDevice(WolDevice device) async {
    final devices =
        savedDevices()
            .where((d) => d.mac.toUpperCase() != device.mac.toUpperCase())
            .toList()
          ..add(device);
    await _prefs.setString(
      _kDevices,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> removeDevice(String mac) async {
    final devices = savedDevices()
        .where((d) => d.mac.toUpperCase() != mac.toUpperCase())
        .toList();
    await _prefs.setString(
      _kDevices,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }
}
