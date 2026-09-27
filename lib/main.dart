import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'call_window_app.dart';
import 'livekit_test_peer_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final controller = AppController();
  await controller.load();

  if (args.contains('--livekit-test-peer')) {
    runApp(const LiveKitTestPeerApp());
    return;
  }

  if (args.contains('--call-window')) {
    final commandArg = args.firstWhere(
      (arg) => arg.startsWith('--call-command-file='),
      orElse: () => '',
    );
    final commandFilePath = commandArg.isEmpty
        ? null
        : commandArg.substring('--call-command-file='.length);

    const options = WindowOptions(
      size: Size(260, 180),
      minimumSize: Size(260, 180),
      center: true,
      alwaysOnTop: true,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );

    runApp(
      CallWindowApp(
        controller: controller,
        commandFilePath: commandFilePath,
      ),
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    return;
  }

  runApp(
    SyncWatchApp(controller: controller),
  );
}
