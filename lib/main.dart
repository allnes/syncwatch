import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:multiview_desktop/multiview_desktop.dart' as mv;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'livekit_test_peer_app.dart';
import 'call_process_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.contains('--call-process-diagnostic')) {
    final logFile = File(
      '${Directory.current.path}${Platform.pathSeparator}logs'
      '${Platform.pathSeparator}call_process.log',
    );
    await logFile.parent.create(recursive: true);
    void log(String message) {
      final line = '[${DateTime.now().toIso8601String()}] [MAIN] $message';
      debugPrint(line);
      logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    }

    log(
      'START pid=$pid args=$args executable="${Platform.resolvedExecutable}" '
      'cwd="${Directory.current.path}"',
    );
    try {
      log('windowManager.ensureInitialized BEGIN');
      await windowManager.ensureInitialized();
      log('windowManager.ensureInitialized DONE');
      log('runApp BEGIN');
      runApp(CallProcessDiagnosticApp(logFilePath: logFile.path));
      log('runApp RETURNED');
    } catch (error, stack) {
      log('FATAL error=$error stack=$stack');
      rethrow;
    }
    return;
  }

  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final controller = AppController();
  await controller.load();

  if (args.contains('--livekit-test-peer')) {
    runApp(const LiveKitTestPeerApp());
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
