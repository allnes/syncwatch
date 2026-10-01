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
  bool _alwaysOnTop = false;

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
        minimumSize: Size(300, 210),
        center: true,
        title: 'SyncWatch Call',
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Color(0xFF0B1C2B),
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setResizable(true);
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

  Future<void> _toggleFullscreen() async {
    final next = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _fullscreen = next);
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_alwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) setState(() => _alwaysOnTop = next);
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color background = const Color(0xFF183247),
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
          minimumSize: const Size(40, 40),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const radius = 22.0;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0B1C2B),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: const Color(0xFF29485E),
                  width: 1,
                ),
              ),
              child: Stack(
              children: [
                Positioned(
                  left: 10,
                  right: 8,
                  top: 7,
                  height: 36,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => windowManager.startDragging(),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          tooltip: _alwaysOnTop
                              ? 'Открепить от переднего плана'
                              : 'Закрепить поверх окон',
                          onPressed: () => unawaited(_toggleAlwaysOnTop()),
                          icon: RotatedBox(
                            // Vertical when inactive, horizontal when pinned.
                            quarterTurns: _alwaysOnTop ? 1 : 0,
                            child: const Icon(Icons.push_pin_rounded, size: 18),
                          ),
                          color: _alwaysOnTop
                              ? Colors.white
                              : Colors.white70,
                        ),
                        IconButton(
                          tooltip: 'Свернуть',
                          onPressed: () => windowManager.minimize(),
                          icon: const Icon(Icons.remove_rounded, size: 18),
                          color: Colors.white70,
                        ),
                        IconButton(
                          tooltip: _fullscreen
                              ? 'Выйти из полноэкранного режима'
                              : 'На весь экран',
                          onPressed: () => unawaited(_toggleFullscreen()),
                          icon: Icon(
                            _fullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            size: 20,
                          ),
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _roundButton(
                        tooltip: _microphoneEnabled
                            ? 'Выключить микрофон'
                            : 'Включить микрофон',
                        icon: _microphoneEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        onPressed: () => _sendAction(
                          _microphoneEnabled
                              ? 'microphone_off'
                              : 'microphone_on',
                        ),
                      ),
                      const SizedBox(width: 10),
                      _roundButton(
                        tooltip: _cameraEnabled
                            ? 'Выключить камеру'
                            : 'Включить камеру',
                        icon: _cameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        onPressed: () => _sendAction(
                          _cameraEnabled ? 'camera_off' : 'camera_on',
                        ),
                      ),
                      const SizedBox(width: 10),
                      _roundButton(
                        tooltip: 'Завершить звонок',
                        icon: Icons.call_end_rounded,
                        background: const Color(0xFFB3261E),
                        onPressed: () => _sendAction('hangup'),
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
