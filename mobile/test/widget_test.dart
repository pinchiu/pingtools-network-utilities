import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:pingtools/ui/localization.dart';
import 'package:pingtools/ui/theme.dart';
import 'package:pingtools/ui/widgets.dart';

Widget _host(Widget child, {Locale locale = const Locale('en')}) {
  return CupertinoApp(
    theme: buildAppTheme(Brightness.dark),
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  testWidgets('frosted page renders the title and a springy action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        FrostedPage(
          title: 'Ping',
          subtitle: 'Latency',
          showBack: false,
          child: Column(
            children: [
              AppCard(
                child: Text('1.1.1.1', style: TextStyle(color: CupertinoColors.white)),
              ),
              AppButton(label: 'Start', onPressed: () => tapped = true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('1.1.1.1'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('inline localisation switches to Traditional Chinese', (tester) async {
    await tester.pumpWidget(
      _host(
        CupertinoPageScaffold(
          child: Builder(
            builder: (context) => Text(context.tr('Ping', 'Ping 測試')),
          ),
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ping 測試'), findsOneWidget);
  });

  testWidgets('palette follows the Cupertino brightness', (tester) async {
    late AppPalette captured;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            captured = context.palette;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured.isDark, isTrue);
    expect(captured.primary, isNot(captured.bg));
  });
}
