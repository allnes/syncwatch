import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:multiview_desktop/multiview_desktop.dart' as mv;

import '../services/call_engine.dart';
import 'call_window_surface.dart';

class CallWindowView extends StatefulWidget {
  const CallWindowView({
    super.key,
    required this.callEngine,
    required this.microphoneEnabled,
    required this.cameraEnabled,
    required this.onMicrophoneChanged,
    required this.onCameraChanged,
    required this.onHangUp,
  });

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
  late bool _microphoneEnabled = widget.microphoneEnabled;
  late bool _cameraEnabled = widget.cameraEnabled;
  bool _fullscreen = false;
  bool _alwaysOnTop = false;
  Rect? _restoreBounds;
  Future<void> _mediaActions = Future<void>.value();

  mv.MultiViewDesktop get _window => mv.MultiViewDesktop.of(context);

  @override
  void initState() {
    super.initState();
    _updateTrack();
    _events = widget.callEngine.room?.createListener()
      ?..on<TrackSubscribedEvent>((_) => _updateTrack())
      ..on<TrackUnsubscribedEvent>((_) => _updateTrack())
      ..on<TrackMutedEvent>((_) => _updateTrack())
      ..on<TrackUnmutedEvent>((_) => _updateTrack())
      ..on<ParticipantDisconnectedEvent>((_) => _updateTrack());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _showWindow().catchError((Object error, StackTrace stack) async {
            debugPrint('[SyncWatch][CALL_WINDOW] setup failed: $error');
            if (mounted) await widget.onHangUp();
          }),
        );
      }
    });
  }

  void _updateTrack() {
    VideoTrack? next;
    for (final participant
        in widget.callEngine.room?.remoteParticipants.values ??
            <RemoteParticipant>[]) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.source == TrackSource.camera && !publication.muted) {
          next = publication.track;
          if (next != null) break;
        }
      }
      if (next != null) break;
    }
    if (mounted && !identical(next, _remoteTrack)) {
      setState(() => _remoteTrack = next);
    }
  }

  @override
  void dispose() {
    _events?.dispose();
    super.dispose();
  }

  Future<void> _showWindow() async {
    final window = _window;
    await window.setAsFrameless();
    await window.setBackgroundColor(Colors.transparent);
    await window.setResizable(true);
    // Preserve the upstream first-frame resize: after removing the Windows
    // frame, Flutter otherwise keeps the old client bounds until a resize.
    await window.hide();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await window.setSize(const Size(301, 211));
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    await window.setSize(const Size(300, 210));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await window.show();
    await window.focus();
  }

  Future<void> _toggleFullscreen() async {
    final window = _window;
    if (!_fullscreen) {
      _restoreBounds = await window.getBounds();
      await window.maximize();
      if (mounted) setState(() => _fullscreen = true);
    } else {
      await window.unmaximize();
      final bounds = _restoreBounds;
      if (bounds != null) {
        await window.setSize(bounds.size);
        await window.setPosition(bounds.topLeft);
      }
      await window.setAsFrameless();
      await window.setBackgroundColor(Colors.transparent);
      await window.setResizable(true);
      if (mounted) setState(() => _fullscreen = false);
    }
  }

  Future<void> _togglePin() async {
    final next = !_alwaysOnTop;
    await _window.setAlwaysOnTop(next);
    if (mounted) setState(() => _alwaysOnTop = next);
  }

  void _queueMediaAction(Future<void> Function() action) {
    _mediaActions = _mediaActions
        .then((_) async {
          if (mounted) await action();
        })
        .catchError((Object error, StackTrace stack) {
          debugPrint('[SyncWatch][CALL_WINDOW] action failed: $error');
        });
  }

  @override
  Widget build(BuildContext context) {
    final track = _remoteTrack;
    return CallWindowSurface(
      microphoneEnabled: _microphoneEnabled,
      cameraEnabled: _cameraEnabled,
      fullscreen: _fullscreen,
      alwaysOnTop: _alwaysOnTop,
      onDrag: () => unawaited(_window.startDragging()),
      onPin: () => unawaited(_togglePin()),
      onMinimize: () => unawaited(_window.minimize()),
      onFullscreen: () => unawaited(_toggleFullscreen()),
      onMicrophone: () => _queueMediaAction(() async {
        final next = !_microphoneEnabled;
        await widget.onMicrophoneChanged(next);
        if (mounted) setState(() => _microphoneEnabled = next);
      }),
      onCamera: () => _queueMediaAction(() async {
        final next = !_cameraEnabled;
        await widget.onCameraChanged(next);
        if (mounted) setState(() => _cameraEnabled = next);
      }),
      onHangUp: () => _queueMediaAction(widget.onHangUp),
      video: track == null
          ? null
          : VideoTrackRenderer(
              track,
              key: ObjectKey(track),
              fit: VideoViewFit.cover,
              mirrorMode: VideoViewMirrorMode.off,
            ),
      wrapResizeArea: (child) => _CallResizeArea(child: child),
    );
  }
}

/// The same eight-pixel resize edges as window_manager, directed at this view.
class _CallResizeArea extends StatelessWidget {
  const _CallResizeArea({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget edge(mv.ResizeEdge edge, MouseCursor cursor) => MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => mv.MultiViewDesktop.of(context).startResizing(edge),
        onDoubleTap: () {
          if (Platform.isWindows &&
              (edge == mv.ResizeEdge.top || edge == mv.ResizeEdge.bottom)) {
            unawaited(
              mv.MultiViewDesktop.of(context).maximize(vertically: true),
            );
          }
        },
      ),
    );
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 8,
          right: 8,
          height: 8,
          child: edge(mv.ResizeEdge.top, SystemMouseCursors.resizeUp),
        ),
        Positioned(
          bottom: 0,
          left: 8,
          right: 8,
          height: 8,
          child: edge(mv.ResizeEdge.bottom, SystemMouseCursors.resizeDown),
        ),
        Positioned(
          left: 0,
          top: 8,
          bottom: 8,
          width: 8,
          child: edge(mv.ResizeEdge.left, SystemMouseCursors.resizeLeft),
        ),
        Positioned(
          right: 0,
          top: 8,
          bottom: 8,
          width: 8,
          child: edge(mv.ResizeEdge.right, SystemMouseCursors.resizeRight),
        ),
        Positioned(
          top: 0,
          left: 0,
          width: 8,
          height: 8,
          child: edge(mv.ResizeEdge.topLeft, SystemMouseCursors.resizeUpLeft),
        ),
        Positioned(
          top: 0,
          right: 0,
          width: 8,
          height: 8,
          child: edge(mv.ResizeEdge.topRight, SystemMouseCursors.resizeUpRight),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: 8,
          height: 8,
          child: edge(
            mv.ResizeEdge.bottomLeft,
            SystemMouseCursors.resizeDownLeft,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          width: 8,
          height: 8,
          child: edge(
            mv.ResizeEdge.bottomRight,
            SystemMouseCursors.resizeDownRight,
          ),
        ),
      ],
    );
  }
}
