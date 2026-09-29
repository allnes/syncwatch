import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import '../app.dart';
import '../core/app_theme.dart';
import '../services/call_engine.dart';

class CallWindowView extends StatefulWidget {
  const CallWindowView({
    super.key,
    required this.controller,
    required this.callEngine,
    required this.microphoneEnabled,
    required this.cameraEnabled,
    required this.onMicrophoneChanged,
    required this.onCameraChanged,
    required this.onHangUp,
  });

  final AppController controller;
  final CallEngine callEngine;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final Future<void> Function(bool enabled) onMicrophoneChanged;
  final Future<void> Function(bool enabled) onCameraChanged;
  final Future<void> Function() onHangUp;

  @override
  State<CallWindowView> createState() => _CallWindowViewState();
}

class _CallWindowViewState extends State<CallWindowView> {
  EventsListener<RoomEvent>? _events;
  VideoTrack? _remoteTrack;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _fullscreen = false;
  bool _alwaysOnTop = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    _microphoneEnabled = widget.microphoneEnabled;
    _cameraEnabled = widget.cameraEnabled;
    _remoteTrack = _findRemoteVideoTrack();
    final room = widget.callEngine.room;
    if (room != null) {
      _events = room.createListener()
        ..on<TrackSubscribedEvent>((event) {
          if (event.track is! VideoTrack || !mounted) return;
          setState(() => _remoteTrack = event.track as VideoTrack);
        })
        ..on<TrackUnsubscribedEvent>((event) {
          if (event.track is! VideoTrack || !mounted) return;
          if (identical(_remoteTrack, event.track)) {
            setState(() => _remoteTrack = _findRemoteVideoTrack());
          }
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          if (mounted) setState(() => _remoteTrack = _findRemoteVideoTrack());
        });
    }
  }

  @override
  void dispose() {
    _events?.dispose();
    _events = null;
    super.dispose();
  }

  VideoTrack? _findRemoteVideoTrack() {
    final room = widget.callEngine.room;
    if (room == null) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is VideoTrack && publication.source == TrackSource.camera) {
          return track;
        }
      }
    }
    return null;
  }

  Future<void> _toggleMicrophone() async {
    final next = !_microphoneEnabled;
    await widget.onMicrophoneChanged(next);
    if (mounted) setState(() => _microphoneEnabled = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraEnabled;
    await widget.onCameraChanged(next);
    if (mounted) setState(() => _cameraEnabled = next);
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_alwaysOnTop;
    await MultiViewDesktop.of(context).setAlwaysOnTop(next);
    if (mounted) setState(() => _alwaysOnTop = next);
  }

  Future<void> _toggleFullscreen() async {
    final window = MultiViewDesktop.of(context);
    final next = !await window.isFullScreen();
    await window.setFullScreen(next);
    if (mounted) setState(() => _fullscreen = next);
  }

  Future<void> _hangUp() async {
    if (_ending) return;
    _ending = true;
    await widget.onHangUp();
    if (mounted) {
      await MultiViewDesktop.of(context).closeWindow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localTrack =
        _cameraEnabled ? widget.callEngine.localVideoTrack : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 380 || constraints.maxHeight < 260;
        return Material(
          color: const Color(0xFF0B1C2B),
          child: Stack(
            children: [
              Positioned.fill(
                child: _remoteTrack == null
                    ? const ColoredBox(
                        color: Color(0xFF0B1C2B),
                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 82,
                            color: Colors.white24,
                          ),
                        ),
                      )
                    : VideoTrackRenderer(
                        _remoteTrack!,
                        fit: VideoViewFit.cover,
                        mirrorMode: VideoViewMirrorMode.off,
                      ),
              ),
              if (!_fullscreen)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 48,
                  child: DragToMoveArea(
                    child: ColoredBox(color: Colors.transparent),
                  ),
                ),
              Positioned(
                right: 8,
                top: 7,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chromeButton(
                      tooltip: _alwaysOnTop
                          ? 'Не держать поверх всех окон'
                          : 'Поверх всех окон',
                      icon: Icons.push_pin_rounded,
                      active: _alwaysOnTop,
                      quarterTurns: _alwaysOnTop ? 1 : 0,
                      onPressed: _toggleAlwaysOnTop,
                    ),
                    const SizedBox(width: 4),
                    _chromeButton(
                      tooltip: widget.controller.t('minimize'),
                      icon: Icons.remove_rounded,
                      onPressed: () =>
                          MultiViewDesktop.of(context).minimize(),
                    ),
                    const SizedBox(width: 4),
                    _chromeButton(
                      tooltip: widget.controller.t('fullscreen'),
                      icon: _fullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
              if (!compact)
                Positioned(
                  right: 12,
                  bottom: 66,
                  width: _fullscreen ? 180 : 112,
                  height: _fullscreen ? 120 : 76,
                  child: Material(
                    elevation: 8,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF182634),
                    child: localTrack == null
                        ? const Center(
                            child: Icon(
                              Icons.videocam_off_rounded,
                              color: Colors.white38,
                            ),
                          )
                        : VideoTrackRenderer(
                            localTrack,
                            fit: VideoViewFit.cover,
                            mirrorMode: VideoViewMirrorMode.mirror,
                          ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _callButton(
                      icon: _microphoneEnabled
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      onPressed: _toggleMicrophone,
                    ),
                    const SizedBox(width: 10),
                    _callButton(
                      icon: _cameraEnabled
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      onPressed: _toggleCamera,
                    ),
                    const SizedBox(width: 10),
                    _callButton(
                      icon: Icons.call_end_rounded,
                      destructive: true,
                      onPressed: _hangUp,
                    ),
                  ],
                ),
              ),
              if (!_fullscreen) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(
                      MultiViewDesktop.of(context)
                          .startResizing(ResizeEdge.left),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(
                      MultiViewDesktop.of(context)
                          .startResizing(ResizeEdge.right),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(
                      MultiViewDesktop.of(context)
                          .startResizing(ResizeEdge.top),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(
                      MultiViewDesktop.of(context)
                          .startResizing(ResizeEdge.bottom),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: 18,
                  height: 18,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(
                      MultiViewDesktop.of(context)
                          .startResizing(ResizeEdge.bottomRight),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chromeButton({
    required String tooltip,
    required IconData icon,
    required FutureOr<void> Function() onPressed,
    bool active = false,
    int quarterTurns = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white24 : Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(Future<void>.sync(onPressed)),
          child: SizedBox(
            width: 34,
            height: 34,
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: Icon(icon, size: 19, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _callButton({
    required IconData icon,
    required FutureOr<void> Function() onPressed,
    bool destructive = false,
  }) {
    return FilledButton(
      onPressed: () => unawaited(Future<void>.sync(onPressed)),
      style: FilledButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(12),
        backgroundColor:
            destructive ? const Color(0xFFB3261E) : syncSurfaceRaised,
      ),
      child: Icon(icon, size: 20),
    );
  }
}
