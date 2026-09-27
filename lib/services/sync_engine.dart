import 'dart:convert';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';

class SharedMediaDescriptor {
  const SharedMediaDescriptor({required this.movieId, required this.fingerprint});
  final String movieId;
  final String fingerprint;
  Map<String, String> toJson() => {'movieId': movieId, 'fingerprint': fingerprint};
}

typedef RemoteLibraryHandler = void Function(Set<String> movieIds);

abstract class SyncEngine {
  Future<void> connect();
  Future<void> setReady(bool ready);
  Future<void> publishLibrary(List<SharedMediaDescriptor> media);
  Future<void> start(String mediaId, Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  void setRemoteLibraryHandler(RemoteLibraryHandler? handler);
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

  void _log(String message) {
    final now = DateTime.now().toIso8601String();
    print('[SyncWatch][SYNC][$now] $message');
  }
  RemoteLibraryHandler? _remoteLibraryHandler;
  EventsListener<RoomEvent>? _listener;

  Future<void> _publish(
    String type, {
    bool? playing,
    String? mediaIdOverride,
    Duration? positionOverride,
  }) async {
    final payload = <String, Object?>{
      'kind': 'playback',
      'type': type,
      'revision': ++_revision,
      'mediaId': mediaIdOverride ?? mediaId(),
      'positionMs': (positionOverride ?? position()).inMilliseconds,
      'playing': playing,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    _log('TX $type rev=${payload['revision']} media=${payload['mediaId']} posMs=${payload['positionMs']} playing=${payload['playing']}');
    await room.localParticipant?.publishData(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      reliable: true,
    );
  }

  @override
  Future<void> connect() async {
    _listener ??= room.createListener()
      ..on<DataReceivedEvent>((event) {
        try {
          final payload = jsonDecode(utf8.decode(event.data));
          if (payload is! Map<String, dynamic>) return;
          _log('RX kind=${payload['kind']} from=${event.participant?.identity ?? 'server'} payload=${jsonEncode(payload)}');
          if (payload['kind'] != 'library') return;
          final items = payload['items'];
          if (items is! List) return;
          final ids = items
              .whereType<Map>()
              .map((item) => item['movieId'])
              .whereType<String>()
              .toSet();
          _remoteLibraryHandler?.call(ids);
        } catch (_) {}
      });
  }

  @override
  Future<void> publishLibrary(List<SharedMediaDescriptor> media) async {
    _log('TX library items=${media.length}');
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
    _log('TX ready=$ready');
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
  Future<void> start(String mediaId, Duration position) => _publish(
        'START',
        playing: true,
        mediaIdOverride: mediaId,
        positionOverride: position,
      );

  @override
  Future<void> play() => _publish('PLAY', playing: true);

  @override
  Future<void> pause() => _publish('PAUSE', playing: false);

  @override
  Future<void> seekTo(Duration position) =>
      _publish('SEEK', positionOverride: position);

  @override
  void setRemoteLibraryHandler(RemoteLibraryHandler? handler) {
    _remoteLibraryHandler = handler;
  }

  @override
  Future<void> dispose() async {
    _listener?.dispose();
    _listener = null;
  }
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
  void setRemoteLibraryHandler(RemoteLibraryHandler? handler) {}
  @override
  Future<void> dispose() async {}
}
