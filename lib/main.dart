import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  const mockMode = bool.fromEnvironment('SYNCWATCH_MOCK', defaultValue: true);
  final controller = AppController();
  await controller.load();

  runApp(
    SyncWatchApp(
      mockMode: mockMode,
      controller: controller,
    ),
  );
}
