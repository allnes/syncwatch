import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'livekit_connection.dart';

abstract class CallEngine {
  Future<void> join();
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Room? get room;
  LocalVideoTrack? get localVideoTrack;
  Future<void> leave();
}

class LiveKitCallEngine implements CallEngine {
  LiveKitCallEngine({
    required this.connection,
    required this.roomName,
    required this.identity,
    required this.participantName,
  });

  final LiveKitConnection connection;
  final String roomName;
  final String identity;
  final String participantName;

  Room? _room;
  bool _microphoneEnabled = false;
  bool _cameraEnabled = false;

  @override
  Room? get room => _room;
  @override
  LocalVideoTrack? get localVideoTrack {
    final publications = _room?.localParticipant?.videoTrackPublications;
    if (publications == null) return null;
    for (final publication in publications) {
      if (publication.source == TrackSource.camera) {
        return publication.track;
      }
    }
    return null;
  }
  bool get connected => _room != null;

  void _log(String message) {
    final now = DateTime.now().toIso8601String();
    debugPrint('[SyncWatch][CALL][$now] $message');
  }

  @override
  Future<void> join() async {
    if (_room != null) return;
    _log('JOIN room=$roomName identity=$identity');
    final room = await connection.connect(
      roomName: roomName,
      identity: identity,
      participantName: participantName,
    );
    _room = room;
    try {
      await room.localParticipant?.setMicrophoneEnabled(_microphoneEnabled);
      _log('MIC publish ok enabled=$_microphoneEnabled');
    } catch (error) {
      _log('MIC publish failed error=$error');
      rethrow;
    }
    try {
      await room.localParticipant?.setCameraEnabled(_cameraEnabled);
      _log('CAMERA publish ok enabled=$_cameraEnabled');
    } catch (error) {
      _log('CAMERA publish failed error=$error');
      rethrow;
    }
    final publications = room.localParticipant?.videoTrackPublications ?? const [];
    _log('JOINED mic=$_microphoneEnabled camera=$_cameraEnabled videoPublications=${publications.length} videoTrack=${localVideoTrack != null}');
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _microphoneEnabled = enabled;
    _log('MIC enabled=$enabled');
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      _log('MIC toggle ok enabled=$enabled');
    } catch (error) {
      _log('MIC toggle failed error=$error');
      rethrow;
    }
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    _cameraEnabled = enabled;
    _log('CAMERA enabled=$enabled');
    try {
      await _room?.localParticipant?.setCameraEnabled(enabled);
      _log('CAMERA toggle ok enabled=$enabled');
    } catch (error) {
      _log('CAMERA toggle failed error=$error');
      rethrow;
    }
  }

  @override
  Future<void> leave() async {
    _log('LEAVE room=$roomName');
    _room = null;
    await connection.disconnect();
  }
}

class MockCallEngine implements CallEngine {
  @override
  Room? get room => null;
  @override
  LocalVideoTrack? get localVideoTrack => null;
  @override
  Future<void> join() async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> leave() async {}
}
