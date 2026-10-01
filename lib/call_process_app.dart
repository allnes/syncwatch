import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CallProcessDiagnosticApp extends StatefulWidget {
  const CallProcessDiagnosticApp({super.key, required this.logFilePath});

  final String logFilePath;

  @override
  State<CallProcessDiagnosticApp> createState() => _CallProcessDiagnosticAppState();
}

class _CallProcessDiagnosticAppState extends State<CallProcessDiagnosticApp> with WindowListener {
  Timer? _commandTimer;
  late final File _commandFile;
  late final File _actionFile;
  void _log(String message) {
    final line = '[${DateTime.now().toIso8601String()}] [WINDOW] $message';
    debugPrint(line);
    try {
      File(widget.logFilePath)
          .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _log('initState pid=$pid');
    windowManager.addListener(this);
    final logs = '${Directory.current.path}${Platform.pathSeparator}logs';
    _commandFile = File('$logs${Platform.pathSeparator}call_window.command');
    _actionFile = File('$logs${Platform.pathSeparator}call_window.action');
    try { if (_commandFile.existsSync()) _commandFile.deleteSync(); } catch (_) {}
    _commandTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _pollCommand();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showDiagnosticWindow());
    });
  }

  void _sendAction(String action) {
    try {
      _actionFile.parent.createSync(recursive: true);
      _actionFile.writeAsStringSync(action, flush: true);
      _log('ACTION $action');
    } catch (error) {
      _log('ACTION_FAILED $action error=$error');
    }
  }

  Future<void> _pollCommand() async {
    if (!_commandFile.existsSync()) return;
    String command = '';
    try {
      command = _commandFile.readAsStringSync().trim();
      _commandFile.deleteSync();
    } catch (_) {
      return;
    }
    if (command == 'focus') {
      _log('COMMAND focus');
      await windowManager.show();
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      // Windows can reject a plain SetForegroundWindow/focus request from a
      // background process. A short topmost transition raises the existing
      // call window above the main SyncWatch window without leaving it pinned.
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await windowManager.setAlwaysOnTop(false);
      _log(
        'COMMAND focus done visible=${await windowManager.isVisible()} '
        'focused=${await windowManager.isFocused()}',
      );
    } else if (command == 'close') {
      _log('COMMAND close');
      await _closeWindow();
    }
  }

  Future<void> _closeWindow() async {
    _log('CLOSE begin');
    _commandTimer?.cancel();
    try {
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  @override
  void onWindowClose() {
    unawaited(_closeWindow());
  }

  @override
  void dispose() {
    _commandTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _showDiagnosticWindow() async {
    _log('FIRST_FRAME');
    try {
      const options = WindowOptions(
        size: Size(300, 210),
        minimumSize: Size(160, 210),
        center: true,
        title: 'SyncWatch Call',
      );
      _log('waitUntilReadyToShow BEGIN');
      await windowManager.waitUntilReadyToShow(options, () async {
        _log('READY_CALLBACK');
        await windowManager.setResizable(true);
        await windowManager.setPreventClose(false);

        // Keep the native window hidden until Flutter has had additional
        // frames to submit the initialized surface. Showing it immediately
        // after the first Dart frame can expose the unpainted white HWND on
        // Windows until a later resize/minimize forces invalidation.
        await windowManager.hide();
        _log('READY hidden; waiting for stable Flutter surface');
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await WidgetsBinding.instance.endOfFrame;

        // Force one real native resize while hidden. This invalidates the
        // backing surface in the same way the previously successful manual
        // minimize/restore did, without exposing the white startup frame.
        const warmSize = Size(301, 211);
        const finalSize = Size(300, 210);
        await windowManager.setSize(warmSize);
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await windowManager.setSize(finalSize);
        await WidgetsBinding.instance.endOfFrame;

        await windowManager.show();
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await windowManager.setAlwaysOnTop(false);
        _log(
          'show/focus DONE visible=${await windowManager.isVisible()} '
          'focused=${await windowManager.isFocused()}',
        );
      });
      // One post-show raise handles Windows foreground activation rules; the
      // surface itself has already been warmed while hidden above.
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await windowManager.setAlwaysOnTop(false);
      _log(
        'waitUntilReadyToShow DONE visible=${await windowManager.isVisible()} '
        'focused=${await windowManager.isFocused()} '
        'size=${await windowManager.getSize()} '
        'position=${await windowManager.getPosition()}',
      );
    } catch (error, stack) {
      _log('WINDOW_ERROR error=$error stack=$stack');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF0B1C2B),
          body: Center(
            child: IconButton.filled(
              tooltip: 'Завершить звонок',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _sendAction('hangup'),
              icon: const Icon(Icons.call_end_rounded),
            ),
          ),
        ),
      );
}
