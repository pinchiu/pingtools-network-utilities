import 'package:flutter_test/flutter_test.dart';
import 'package:pingtools/core/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
  });

  test('remembers a tool input immediately', () async {
    await AppSettings.instance.rememberInputNow('ping', '203.0.113.7');
    expect(
      AppSettings.instance.inputOrDefault('ping', '1.1.1.1'),
      '203.0.113.7',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_ping'), '203.0.113.7');
  });

  test('falls back when nothing usable is stored', () async {
    expect(
      AppSettings.instance.inputOrDefault('whois', 'example.com'),
      'example.com',
    );
    await AppSettings.instance.rememberInputNow('whois', '   ');
    expect(
      AppSettings.instance.inputOrDefault('whois', 'example.com'),
      'example.com',
    );
  });

  test('debounced typing is persisted', () async {
    AppSettings.instance.rememberInput('dns', 'example.org');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_dns'), 'example.org');
  });

  test('boolean and string preferences persist', () async {
    await AppSettings.instance.setPrefBool('subnet_ports', true);
    await AppSettings.instance.setPrefString('dns_type', 'mx');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('subnet_ports'), isTrue);
    expect(prefs.getString('dns_type'), 'mx');
  });
}
