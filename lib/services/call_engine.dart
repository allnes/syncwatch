import 'package:livekit_client/livekit_client.dart';

import 'livekit_connection.dart';

abstract class CallEngine {
  Future<void> join();
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Room? get room;
  VideoTrack? get localVideoTrack;
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
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;

  @override
  Room? get room => _room;
  @override
  VideoTrack? get localVideoTrack {
    final publications = _room?.localParticipant?.videoTrackPublications;
    if (publications == null) return null;
    for (final publication in publications) {
      if (publication.source == TrackSource.camera &&
          publication.track is VideoTrack) {
        return publication.track as VideoTrack;
      }
    }
    return null;
  }
  bool get connected => _room != null;

  void _log(String message) {
    final now = DateTime.now().toIso8601String();
    print('[SyncWatch][CALL][$now] $message');
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
    await room.localParticipant?.setMicrophoneEnabled(_microphoneEnabled);
    await room.localParticipant?.setCameraEnabled(_cameraEnabled);
    _log('JOINED mic=$_microphoneEnabled camera=$_cameraEnabled videoTrack=${localVideoTrack != null}');
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _microphoneEnabled = enabled;
    _log('MIC enabled=$enabled');
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    _cameraEnabled = enabled;
    _log('CAMERA enabled=$enabled');
    await _room?.localParticipant?.setCameraEnabled(enabled);
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
  VideoTrack? get localVideoTrack => null;
  @override
  Future<void> join() async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> leave() async {}
}
