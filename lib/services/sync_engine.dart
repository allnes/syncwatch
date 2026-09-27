import 'dart:convert';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';

class SharedMediaDescriptor {
  const SharedMediaDescriptor({required this.movieId, required this.fingerprint});
  final String movieId;
  final String fingerprint;
  Map<String, String> toJson() => {'movieId': movieId, 'fingerprint': fingerprint};
}

abstract class SyncEngine {
  Future<void> connect();
  Future<void> setReady(bool ready);
  Future<void> publishLibrary(List<SharedMediaDescriptor> media);
  Future<void> start(String mediaId, Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> dispose();
}

class LiveKitSyncEngine implements SyncEngine {
  LiveKitSyncEngine({
    required this.room,
    required this.mediaId,
    required this.position,
  });

  final Room room;
  final String Function() mediaId;
  final Duration Function() position;
  int _revision = 0;

  Future<void> _publish(String type, {bool? playing}) async {
    final payload = <String, Object?>{
      'kind': 'playback',
      'type': type,
      'revision': ++_revision,
      'mediaId': mediaId(),
      'positionMs': position().inMilliseconds,
      'playing': playing,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await room.localParticipant?.publishData(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      reliable: true,
    );
  }

  @override
  Future<void> connect() async {}

  @override
  Future<void> publishLibrary(List<SharedMediaDescriptor> media) async {
    await room.localParticipant?.publishData(
      Uint8List.fromList(utf8.encode(jsonEncode({
        'kind': 'library',
        'items': media.map((item) => item.toJson()).toList(),
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      }))),
      reliable: true,
    );
  }

  @override
  Future<void> setReady(bool ready) async {
    await room.localParticipant?.publishData(
      Uint8List.fromList(utf8.encode(jsonEncode({
        'kind': 'ready',
        'ready': ready,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      }))),
      reliable: true,
    );
  }

  @override
  Future<void> start(String mediaId, Duration position) =>
      _publish('START', playing: true);

  @override
  Future<void> play() => _publish('PLAY', playing: true);

  @override
  Future<void> pause() => _publish('PAUSE', playing: false);

  @override
  Future<void> seekTo(Duration position) => _publish('SEEK');

  @override
  Future<void> dispose() async {}
}

class MockSyncEngine implements SyncEngine {
  @override
  Future<void> start(String mediaId, Duration position) async {}
  @override
  Future<void> connect() async {}
  @override
  Future<void> setReady(bool ready) async {}
  @override
  Future<void> publishLibrary(List<SharedMediaDescriptor> media) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> dispose() async {}
}
