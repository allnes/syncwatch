import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CallProcessDiagnosticApp extends StatefulWidget {
  const CallProcessDiagnosticApp({super.key});

  @override
  State<CallProcessDiagnosticApp> createState() => _CallProcessDiagnosticAppState();
}

class _CallProcessDiagnosticAppState extends State<CallProcessDiagnosticApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.setTitle('SyncWatch Call');
      await windowManager.setSize(const Size(300, 210));
      await windowManager.setMinimumSize(const Size(160, 210));
      await windowManager.setMaximumSize(const Size(1280, 900));
      await windowManager.setResizable(true);
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
      debugPrint('[SyncWatch][CALL_PROCESS] READY pid=$pid');
    });
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
