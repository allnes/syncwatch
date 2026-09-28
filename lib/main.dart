import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:multiview_desktop/multiview_desktop.dart' as mv;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
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


  await windowManager.setMinimumSize(const Size(1100, 760));

  mv.runMultiApp(
    home: (_, __) => SyncWatchApp(controller: controller),
    config: mv.MultiAppConfig(
      generalParams: const mv.MultiPlatformParams(
        closeMode: mv.CloseMode.softCascade,
      ),
      globalWindowOptions: const mv.WindowOptions(
        minimumSize: Size(1100, 760),
        title: 'SyncWatch',
      ),
    ),
  );
}
