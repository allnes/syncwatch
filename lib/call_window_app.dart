import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_theme.dart';

class CallWindowApp extends StatelessWidget {
  const CallWindowApp({
    super.key,
    required this.controller,
    required this.commandFilePath,
  });

  final AppController controller;
  final String? commandFilePath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: controller.locale,
      theme: buildSyncWatchTheme(Brightness.light),
      darkTheme: buildSyncWatchTheme(Brightness.dark),
      themeMode: controller.materialThemeMode,
      home: _CallWindow(
        controller: controller,
        commandFilePath: commandFilePath,
      ),
    );
  }
}

class _CallWindow extends StatefulWidget {
  const _CallWindow({
    required this.controller,
    required this.commandFilePath,
  });

  final AppController controller;
  final String? commandFilePath;

  @override
  State<_CallWindow> createState() => _CallWindowState();
}

class _CallWindowState extends State<_CallWindow> {
  Timer? commandTimer;
  String? lastCommand;

  bool microphoneEnabled = true;
  bool cameraEnabled = true;
  bool fullscreen = false;

  @override
  void initState() {
    super.initState();
    _startCommandListener();
  }

  @override
  void dispose() {
    commandTimer?.cancel();
    super.dispose();
  }

  Future<void> _writeMediaCommand() async {
    final path = widget.commandFilePath;
    if (path == null || path.isEmpty) return;
    try {
      await File(path).writeAsString(
        'media:${microphoneEnabled ? 1 : 0}:${cameraEnabled ? 1 : 0}:${DateTime.now().microsecondsSinceEpoch}',
        flush: true,
      );
    } catch (_) {}
  }

  void _startCommandListener() {
    final path = widget.commandFilePath;
    if (path == null || path.isEmpty) return;

    commandTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _pollCommand(path),
    );
  }

  Future<void> _pollCommand(String path) async {
    try {
      final command = await File(path).readAsString();
      if (command == lastCommand) return;
      lastCommand = command;

      if (command.startsWith('restore:')) {
        await windowManager.show();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1C2B),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                if (!fullscreen) {
                  windowManager.startDragging();
                }
              },
              onDoubleTap: _toggleFullscreen,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF20486A), Color(0xFF0A1B2A)],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 82,
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: widget.controller.t('minimize'),
                  onPressed: windowManager.hide,
                  icon: const Icon(Icons.remove_rounded),
                ),
                IconButton(
                  tooltip: widget.controller.t('fullscreen'),
                  onPressed: _toggleFullscreen,
                  icon: Icon(
                    fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _callButton(
                  tooltip: microphoneEnabled
                      ? widget.controller.t('microphoneOn')
                      : widget.controller.t('microphoneOff'),
                  icon: microphoneEnabled
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  onPressed: () {
                    setState(() => microphoneEnabled = !microphoneEnabled);
                    _writeMediaCommand();
                  },
                ),
                const SizedBox(width: 12),
                _callButton(
                  tooltip: cameraEnabled
                      ? widget.controller.t('cameraOn')
                      : widget.controller.t('cameraOff'),
                  icon: cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  onPressed: () {
                    setState(() => cameraEnabled = !cameraEnabled);
                    _writeMediaCommand();
                  },
                ),
                const SizedBox(width: 12),
                _callButton(
                  tooltip: widget.controller.t('endCall'),
                  icon: Icons.call_end_rounded,
                  destructive: true,
                  onPressed: windowManager.close,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool destructive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(14),
          backgroundColor:
              destructive ? const Color(0xFFB3261E) : syncSurfaceRaised,
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    final next = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(next);
    if (mounted) {
      setState(() => fullscreen = next);
    }
  }
}
