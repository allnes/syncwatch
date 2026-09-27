import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_theme.dart';
import 'services/livekit_connection.dart';

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
  late final LiveKitConnection liveKitConnection;
  Room? liveKitRoom;
  VideoTrack? localVideoTrack;
  String? connectionError;

  @override
  void initState() {
    super.initState();
    liveKitConnection = LiveKitConnection(backendUrl: 'http://127.0.0.1:8787');
    _startCommandListener();
    unawaited(_connectLiveKit());
  }

  @override
  void dispose() {
    commandTimer?.cancel();
    unawaited(liveKitConnection.disconnect());
    super.dispose();
  }

  Future<void> _connectLiveKit() async {
    try {
      final room = await liveKitConnection.connect(
        roomName: 'syncwatch-dev',
        identity: 'syncwatch-call-window',
        participantName: widget.controller.username,
      );
      await room.localParticipant?.setMicrophoneEnabled(microphoneEnabled);
      await room.localParticipant?.setCameraEnabled(cameraEnabled);
      final publication = room.localParticipant?.videoTrackPublications
          .where((item) => item.source == TrackSource.camera)
          .firstOrNull;
      final track = publication?.track;
      if (!mounted) return;
      setState(() {
        liveKitRoom = room;
        localVideoTrack = track is VideoTrack ? track : null;
        connectionError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => connectionError = error.toString());
    }
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
                child: localVideoTrack != null && cameraEnabled
                    ? VideoTrackRenderer(localVideoTrack!)
                    : Center(
                        child: connectionError == null
                            ? const Icon(
                                Icons.person_rounded,
                                size: 82,
                                color: Colors.white24,
                              )
                            : const Icon(
                                Icons.videocam_off_rounded,
                                size: 72,
                                color: Colors.white38,
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
                  onPressed: () async {
                    final enabled = !microphoneEnabled;
                    await liveKitRoom?.localParticipant
                        ?.setMicrophoneEnabled(enabled);
                    if (mounted) {
                      setState(() => microphoneEnabled = enabled);
                    }
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
                  onPressed: () async {
                    final enabled = !cameraEnabled;
                    await liveKitRoom?.localParticipant
                        ?.setCameraEnabled(enabled);
                    final publication = liveKitRoom
                        ?.localParticipant
                        ?.videoTrackPublications
                        .where((item) => item.source == TrackSource.camera)
                        .firstOrNull;
                    final track = publication?.track;
                    if (mounted) {
                      setState(() {
                        cameraEnabled = enabled;
                        localVideoTrack =
                            track is VideoTrack ? track : localVideoTrack;
                      });
                    }
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
