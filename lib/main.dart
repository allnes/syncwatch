import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'call_window_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final controller = AppController();
  await controller.load();

  if (args.contains('--call-window')) {
    const options = WindowOptions(
      size: Size(360, 240),
      minimumSize: Size(260, 180),
      center: true,
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );

    runApp(CallWindowApp(controller: controller));

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    return;
  }

  const mockMode = bool.fromEnvironment('SYNCWATCH_MOCK', defaultValue: true);

  runApp(
    SyncWatchApp(
      mockMode: mockMode,
      controller: controller,
    ),
  );
}
