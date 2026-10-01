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
  late final File _stateFile;
  bool _cameraEnabled = true;
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
    _stateFile = File('$logs${Platform.pathSeparator}call_window.state');
    try { if (_commandFile.existsSync()) _commandFile.deleteSync(); } catch (_) {}
    _commandTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _pollCommand();
      _pollState();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showDiagnosticWindow());
    });
  }

  void _pollState() {
    if (!_stateFile.existsSync()) return;
    try {
      final state = _stateFile.readAsStringSync();
      final enabled = state.contains('camera=on');
      if (enabled != _cameraEnabled && mounted) {
        setState(() => _cameraEnabled = enabled);
        _log('STATE camera=${enabled ? "on" : "off"}');
      }
    } catch (_) {}
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
        // Do not intercept the native close button. With preventClose=false
        // Windows performs the normal close path and terminates this helper.
        await windowManager.setPreventClose(false);
        _log('setResizable/setPreventClose(false) DONE');
        await windowManager.show();
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        // Raise during the ready callback itself. The main process may request
        // focus before this helper has produced its first native window.
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await windowManager.setAlwaysOnTop(false);
        _log(
          'show/focus DONE visible=${await windowManager.isVisible()} '
          'focused=${await windowManager.isFocused()}',
        );
      });
      // A second raise after waitUntilReadyToShow closes the startup race on
      // Windows where show() can report false inside the ready callback.
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await Future<void>.delayed(const Duration(milliseconds: 120));
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _sendAction(
                    _cameraEnabled ? 'camera_off' : 'camera_on',
                  ),
                  icon: Icon(
                    _cameraEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                  ),
                  label: Text(
                    _cameraEnabled ? 'Камера: ВКЛ' : 'Камера: ВЫКЛ',
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: 'Завершить звонок',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _sendAction('hangup'),
                  icon: const Icon(Icons.call_end_rounded),
                ),
              ],
            ),
          ),
        ),
      );
}
