import 'package:cupertino_ui/cupertino_ui.dart';

class AppAccents {
  static const cyan = Color(0xFF22D3EE);
  static const blue = Color(0xFF60A5FA);
  static const violet = Color(0xFFA78BFA);
  static const amber = Color(0xFFFBBF24);
  static const teal = Color(0xFF2DD4BF);
  static const green = Color(0xFF34D399);
  static const rose = Color(0xFFFB7185);
}

class AppPalette {
  final Brightness brightness;
  final Color bg;
  final Color card;
  final Color elevated;
  final Color border;
  final Color text;
  final Color muted;
  final Color primary;
  final Color onPrimary;
  final Color danger;
  final Color success;
  final Color warning;

  const AppPalette._({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.elevated,
    required this.border,
    required this.text,
    required this.muted,
    required this.primary,
    required this.onPrimary,
    required this.danger,
    required this.success,
    required this.warning,
  });

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette._(
    brightness: Brightness.dark,
    bg: Color(0xFF080D17),
    card: Color(0xFF0F1725),
    elevated: Color(0xFF172234),
    border: Color(0xFF223047),
    text: Color(0xFFE8EEF8),
    muted: Color(0xFF93A5BE),
    primary: Color(0xFF3EDCF2),
    onPrimary: Color(0xFF00202A),
    danger: Color(0xFFFB7185),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
  );

  static const light = AppPalette._(
    brightness: Brightness.light,
    bg: Color(0xFFF5F7FB),
    card: Color(0xFFFFFFFF),
    elevated: Color(0xFFEDF2F9),
    border: Color(0xFFD8E2EF),
    text: Color(0xFF0B1524),
    muted: Color(0xFF54657D),
    primary: Color(0xFF0E7490),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFBE123C),
    success: Color(0xFF047857),
    warning: Color(0xFFB45309),
  );

  static AppPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AppPalette of(BuildContext context) =>
      forBrightness(CupertinoTheme.brightnessOf(context));
}

CupertinoThemeData buildAppTheme(Brightness brightness) {
  final p = AppPalette.forBrightness(brightness);
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: p.primary,
    primaryContrastingColor: p.onPrimary,
    scaffoldBackgroundColor: p.bg,
    barBackgroundColor: p.bg.withValues(alpha: 0.72),
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(color: p.text, fontSize: 16, letterSpacing: -0.2),
      navTitleTextStyle: TextStyle(
        color: p.text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      navLargeTitleTextStyle: TextStyle(
        color: p.text,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      navActionTextStyle: TextStyle(color: p.primary, fontSize: 17),
      actionTextStyle: TextStyle(color: p.primary, fontSize: 17),
      tabLabelTextStyle: TextStyle(color: p.muted, fontSize: 10),
    ),
  );
}

/// Accents used as text/icons need a darker variant on light backgrounds.
Color adaptiveAccent(BuildContext context, Color accent) {
  if (CupertinoTheme.brightnessOf(context) == Brightness.dark) return accent;
  return Color.lerp(accent, const Color(0xFF07121F), 0.55)!;
}
