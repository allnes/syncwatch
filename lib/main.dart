import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:multiview_desktop/multiview_desktop.dart' as mv;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'livekit_test_peer_app.dart';
import 'call_process_app.dart';

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

  if (args.contains('--call-process-diagnostic')) {
    runApp(const CallProcessDiagnosticApp());
    return;
  }



  mv.runMultiApp(
    home: (_, __) => SyncWatchApp(controller: controller),
    config: mv.MultiAppConfig(
      generalParams: const mv.MultiPlatformParams(
        closeMode: mv.CloseMode.softCascade,
      ),
      // Keep main-window constraints on window_manager only. Multi-view
      // global options are inherited by every secondary OS window.
      globalWindowOptions: const mv.WindowOptions(
        title: 'SyncWatch',
      ),
    ),
  );
}
