import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_theme.dart';

class CallWindowApp extends StatelessWidget {
  const CallWindowApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: controller.locale,
      theme: buildSyncWatchTheme(),
      home: _CallWindow(controller: controller),
    );
  }
}

class _CallWindow extends StatefulWidget {
  const _CallWindow({required this.controller});

  final AppController controller;

  @override
  State<_CallWindow> createState() => _CallWindowState();
}

class _CallWindowState extends State<_CallWindow> {
  bool microphoneEnabled = true;
  bool cameraEnabled = true;
  bool fullscreen = false;

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
                  onPressed: windowManager.minimize,
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
