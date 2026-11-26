import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;

import 'core/app_settings.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

class PingToolsApp extends StatefulWidget {
  const PingToolsApp({super.key});

  @override
  State<PingToolsApp> createState() => _PingToolsAppState();
}

class _PingToolsAppState extends State<PingToolsApp> with WidgetsBindingObserver {
  Brightness _platformBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  Brightness _effectiveBrightness(AppSettings settings) {
    switch (settings.themeMode) {
      case 'light':
        return Brightness.light;
      case 'dark':
        return Brightness.dark;
      default:
        return _platformBrightness;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final brightness = _effectiveBrightness(settings);
        return CupertinoApp(
          title: 'PingTools',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness),
          locale: Locale(settings.localeCode),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: const [
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale?.languageCode == 'zh') return const Locale('zh');
            return const Locale('en');
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
