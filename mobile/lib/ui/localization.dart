import 'package:flutter/widgets.dart';

import 'theme.dart';

extension AppLocalization on BuildContext {
  bool get isZh => Localizations.localeOf(this).languageCode == 'zh';

  /// Inline English/Traditional-Chinese localisation.
  String tr(String en, String zh) => isZh ? zh : en;

  AppPalette get palette => AppPalette.of(this);
}
