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

class _CallProcessDiagnosticAppState extends State<CallProcessDiagnosticApp> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showDiagnosticWindow());
    });
  }

  Future<void> _showDiagnosticWindow() async {
    _log('FIRST_FRAME');
    try {
      const options = WindowOptions(
        size: Size(300, 210),
        minimumSize: Size(160, 210),
        maximumSize: Size(1280, 900),
        center: true,
        title: 'SyncWatch Call',
      );
      _log('waitUntilReadyToShow BEGIN');
      await windowManager.waitUntilReadyToShow(options, () async {
        _log('READY_CALLBACK');
        await windowManager.setResizable(true);
        _log('setResizable DONE');
        await windowManager.show();
        _log('show DONE visible=${await windowManager.isVisible()}');
        await windowManager.focus();
        _log('focus DONE focused=${await windowManager.isFocused()}');
      });
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
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: Color(0xFF0B1C2B),
          child: SizedBox.expand(),
        ),
      );
}
