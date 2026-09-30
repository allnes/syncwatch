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

// The regular call UI members are intentionally retained while the static
// secondary-view A/B diagnostic replaces build(). They become referenced again
// when the diagnostic is reverted.
// ignore_for_file: unused_field, unused_element

class _CallWindowViewState extends State<CallWindowView> {
  // Temporary A/B diagnostic: keep the real secondary call window and all
  // media tracks active, but do not attach WebRTC video renderers/textures.
  static const bool _disableVideoRenderingDiagnostic = true;
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

  Future<void> _runUiAction(
    String action,
    FutureOr<void> Function() callback,
  ) async {
    final clock = Stopwatch()..start();
    debugPrint('[SyncWatch][UI] TAP surface=call action=$action');
    debugPrint('[SyncWatch][UI] ACTION_BEGIN surface=call action=$action');
    try {
      await Future<void>.sync(callback);
      debugPrint(
        '[SyncWatch][UI] ACTION_DONE surface=call action=$action '
        'elapsedMs=${clock.elapsedMilliseconds}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SyncWatch][UI] ACTION_ERROR surface=call action=$action '
        'elapsedMs=${clock.elapsedMilliseconds} error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Temporary A/B diagnostic: keep the secondary Flutter view/window alive,
    // but make its scene completely static. No WebRTC renderers, controls,
    // timers, gradients, participant lookups, or media-driven rebuild content.
    return const ColoredBox(
      color: Color(0xFF0B1C2B),
      child: SizedBox.expand(),
    );
  }

  Widget _chromeButton({
    required String tooltip,
    required IconData icon,
    required FutureOr<void> Function() onPressed,
    bool active = false,
    int quarterTurns = 0,
    double scale = 1.0,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white24 : Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(_runUiAction(tooltip, onPressed)),
          child: SizedBox(
            width: 34 * scale,
            height: 34 * scale,
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: Icon(icon, size: 19 * scale, color: Colors.white),
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
    double scale = 1.0,
  }) {
    final action = destructive
        ? 'hang_up'
        : icon == Icons.mic_rounded || icon == Icons.mic_off_rounded
            ? 'microphone'
            : 'camera';
    return FilledButton(
      onPressed: () => unawaited(_runUiAction(action, onPressed)),
      style: FilledButton.styleFrom(
        shape: const CircleBorder(),
        padding: EdgeInsets.all(12 * scale),
        backgroundColor:
            destructive ? const Color(0xFFB3261E) : syncSurfaceRaised,
      ),
      child: Icon(icon, size: 20 * scale),
    );
  }
}
