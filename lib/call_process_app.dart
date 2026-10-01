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
      const options = WindowOptions(
        size: Size(300, 210),
        minimumSize: Size(160, 210),
        maximumSize: Size(1280, 900),
        center: true,
        title: 'SyncWatch Call',
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setResizable(true);
        await windowManager.show();
        await windowManager.focus();
      });
      debugPrint(
        '[SyncWatch][CALL_PROCESS] READY pid=$pid executable="${Platform.resolvedExecutable}"',
      );
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
