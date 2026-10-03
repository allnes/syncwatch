import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'widgets/call_window_surface.dart';

class CallProcessDiagnosticApp extends StatefulWidget {
  const CallProcessDiagnosticApp({super.key, required this.logFilePath});
  final String logFilePath;

  @override
  State<CallProcessDiagnosticApp> createState() =>
      _CallProcessDiagnosticAppState();
}

class _CallProcessDiagnosticAppState extends State<CallProcessDiagnosticApp>
    with WindowListener {
  Timer? _commandTimer;
  Timer? _stateTimer;
  late final File _commandFile;
  late final File _actionFile;
  late final File _stateFile;
  bool _cameraEnabled = true;
  bool _microphoneEnabled = true;
  bool _fullscreen = false;
  Rect? _restoreBounds;
  bool _alwaysOnTop = false;

  void _log(String message) {
    final line = '[${DateTime.now().toIso8601String()}] [WINDOW] $message';
    debugPrint(line);
    try {
      File(
        widget.logFilePath,
      ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
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
    try {
      if (_commandFile.existsSync()) _commandFile.deleteSync();
    } catch (_) {}
    _readState();
    _commandTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _pollCommand(),
    );
    _stateTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _readState(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showWindow());
    });
  }

  void _readState() {
    if (!_stateFile.existsSync()) return;
    try {
      final values = <String, String>{};
      for (final line in _stateFile.readAsLinesSync()) {
        final split = line.indexOf('=');
        if (split > 0) {
          values[line.substring(0, split)] = line.substring(split + 1);
        }
      }
      final camera = values['camera'] != 'off';
      final microphone = values['microphone'] != 'off';
      if (camera != _cameraEnabled || microphone != _microphoneEnabled) {
        if (!mounted) return;
        setState(() {
          _cameraEnabled = camera;
          _microphoneEnabled = microphone;
        });
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
      await windowManager.show();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await windowManager.setAlwaysOnTop(false);
    } else if (command == 'close') {
      await _closeWindow();
    }
  }

  Future<void> _closeWindow() async {
    _commandTimer?.cancel();
    _stateTimer?.cancel();
    try {
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  @override
  void onWindowClose() => unawaited(_closeWindow());

  @override
  void dispose() {
    _commandTimer?.cancel();
    _stateTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _showWindow() async {
    _log('FIRST_FRAME');
    try {
      const options = WindowOptions(
        size: Size(300, 210),
        minimumSize: Size(160, 120),
        center: true,
        title: 'SyncWatch Call',
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Color(0xFF0B1C2B),
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        // TitleBarStyle.hidden still leaves the native Windows outline.
        // Remove the HWND frame entirely; the Flutter contour below is the
        // only visible border. Resizing remains available through the native
        // frameless hit-test path.
        await _applyFramelessSurface();
        await windowManager.setPreventClose(false);
        await windowManager.hide();
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await WidgetsBinding.instance.endOfFrame;
        await windowManager.setSize(const Size(301, 211));
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await windowManager.setSize(const Size(300, 210));
        await WidgetsBinding.instance.endOfFrame;
        await windowManager.show();
        await windowManager.focus();
      });
      _log('WINDOW_READY size=${await windowManager.getSize()}');
    } catch (error, stack) {
      _log('WINDOW_ERROR error=$error stack=$stack');
    }
  }

  Future<void> _applyFramelessSurface() async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(true);
  }

  Future<void> _toggleFullscreen() async {
    // Do not use window_manager.setFullScreen() here: on Windows it rewrites
    // native styles and fights our transparent frameless surface. Instead use
    // a reversible borderless maximize, keeping the Flutter chrome alive.
    if (!_fullscreen) {
      _restoreBounds = await windowManager.getBounds();
      await windowManager.maximize();
      if (mounted) setState(() => _fullscreen = true);
      _log('FULLSCREEN emulated enter restore=$_restoreBounds');
    } else {
      await windowManager.unmaximize();
      final restore = _restoreBounds;
      if (restore != null) {
        await windowManager.setBounds(restore);
      }
      await _applyFramelessSurface();
      if (mounted) setState(() => _fullscreen = false);
      _log('FULLSCREEN emulated leave restore=$restore');
    }
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_alwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) setState(() => _alwaysOnTop = next);
  }

  @override
  Widget build(BuildContext context) {
    return CallWindowSurface(
      wrapResizeArea: (child) =>
          DragToResizeArea(resizeEdgeSize: 8, child: child),
      microphoneEnabled: _microphoneEnabled,
      cameraEnabled: _cameraEnabled,
      fullscreen: _fullscreen,
      alwaysOnTop: _alwaysOnTop,
      onDrag: () => unawaited(windowManager.startDragging()),
      onPin: () => unawaited(_toggleAlwaysOnTop()),
      onMinimize: () => unawaited(windowManager.minimize()),
      onFullscreen: () => unawaited(_toggleFullscreen()),
      onMicrophone: () =>
          _sendAction(_microphoneEnabled ? 'microphone_off' : 'microphone_on'),
      onCamera: () => _sendAction(_cameraEnabled ? 'camera_off' : 'camera_on'),
      onHangUp: () => _sendAction('hangup'),
    );
  }
}
