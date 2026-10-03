import 'dart:async';
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

  MediaKit.ensureInitialized(
    libmpv: Platform.isWindows ? 'syncwatch_mpv.dll' : null,
  );

  // Test Peer does not need the main application's persisted UI settings.
  // Branch before SharedPreferences/window-manager initialization so the
  // auxiliary process cannot contend with the client during startup.
  if (args.contains('--livekit-test-peer')) {
    runApp(const LiveKitTestPeerApp());
    return;
  }

  final startupLog = File(
    '${Directory.current.path}${Platform.pathSeparator}logs'
    '${Platform.pathSeparator}main_startup.log',
  );
  void startup(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    debugPrint('[SyncWatch][STARTUP] $message');
    try {
      startupLog.parent.createSync(recursive: true);
      startupLog.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  startup('windowManager.ensureInitialized BEGIN');
  await windowManager.ensureInitialized();
  startup('windowManager.ensureInitialized DONE');

  final controller = AppController();
  startup('AppController.load BEGIN');
  try {
    await controller.load().timeout(const Duration(seconds: 5));
    startup('AppController.load DONE');
  } on TimeoutException {
    // Never leave the native HWND waiting forever for preferences. Defaults
    // are sufficient to render the app and settings can be changed normally.
    startup('AppController.load TIMEOUT; continuing with defaults');
  } catch (error, stack) {
    startup('AppController.load ERROR error=$error stack=$stack');
  }

  startup('runMultiApp BEGIN');
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
  startup('runMultiApp RETURNED');
}
