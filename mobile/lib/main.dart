import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
  runApp(const PingToolsApp());
}
