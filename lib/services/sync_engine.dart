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
typedef LibraryProvider = List<SharedMediaDescriptor> Function();
typedef PlaybackHandler = void Function(Map<String, dynamic> command);
typedef MediaMissingHandler = void Function(String mediaId);
typedef RemoteSessionHandler = void Function(Map<String, dynamic>? state);

abstract class SyncEngine {
  Future<void> connect();
  Future<void> setReady(bool ready);
  Future<void> publishLibrary(List<SharedMediaDescriptor> media);
  Future<void> requestLibrary();
  Future<void> start(String mediaId, Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  void setRemoteLibraryHandler(RemoteLibraryHandler? handler);
  void addRemoteLibraryHandler(RemoteLibraryHandler handler);
  void removeRemoteLibraryHandler(RemoteLibraryHandler handler);
  void setLibraryProvider(LibraryProvider? provider);
  void setPlaybackHandler(PlaybackHandler? handler);
  void addPlaybackHandler(PlaybackHandler handler);
  void removePlaybackHandler(PlaybackHandler handler);
  Future<void> mediaMissing(String mediaId);
  Future<void> requestPlaybackState();
  Future<void> endSession();
  void setMediaMissingHandler(MediaMissingHandler? handler);
  void addMediaMissingHandler(MediaMissingHandler handler);
  void removeMediaMissingHandler(MediaMissingHandler handler);
  void setRemoteSessionHandler(RemoteSessionHandler? handler);
  void addRemoteSessionHandler(RemoteSessionHandler handler);
  void removeRemoteSessionHandler(RemoteSessionHandler handler);
  Future<void> dispose();
}

class LiveKitSyncEngine implements SyncEngine {
  LiveKitSyncEngine({
    required this.room,
    required this.mediaId,
    required this.position,
    required this.isPlaying,
  });

  final Room room;
  final String Function() mediaId;
  final Duration Function() position;
  final bool Function() isPlaying;
  bool? _playingOverride;
  int _revision = 0;
  int _lastRemoteRevision = 0;
  String? _sessionId;
  bool get hasActiveSession => _sessionId != null;

  void _log(String message) {
    final now = DateTime.now().toIso8601String();
    print('[SyncWatch][SYNC][$now] $message');
  }
  RemoteLibraryHandler? _remoteLibraryHandler;
  final Set<RemoteLibraryHandler> _remoteLibraryHandlers = {};
  LibraryProvider? _libraryProvider;
  PlaybackHandler? _playbackHandler;
  final Set<PlaybackHandler> _playbackHandlers = {};
  MediaMissingHandler? _mediaMissingHandler;
  final Set<MediaMissingHandler> _mediaMissingHandlers = {};
  RemoteSessionHandler? _remoteSessionHandler;
  final Set<RemoteSessionHandler> _remoteSessionHandlers = {};
  EventsListener<RoomEvent>? _listener;

  Future<void> _publish(
    String type, {
    bool? playing,
    String? mediaIdOverride,
    Duration? positionOverride,
  }) async {
    final payload = <String, Object?>{
      'kind': 'playback',
      'sessionId': _sessionId,
      'type': type,
      'revision': ++_revision,
      'mediaId': mediaIdOverride ?? mediaId(),
      'positionMs': (positionOverride ?? position()).inMilliseconds,
      'playing': playing ?? _playingOverride ?? isPlaying(),
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
    if (_listener != null) return;
    _log('LISTENER attach');
    _listener = room.createListener()
      ..on<DataReceivedEvent>((event) {
        try {
          final payload = jsonDecode(utf8.decode(event.data));
          if (payload is! Map<String, dynamic>) return;
          _log('RX kind=${payload['kind']} from=${event.participant?.identity ?? 'server'} payload=${jsonEncode(payload)}');
          if (payload['kind'] == 'library_request') {
            _log('RX LIBRARY_REQUEST');
            return;
          }
          if (payload['kind'] == 'state_request') {
            if (_sessionId == null) {
              _log('RX STATE_REQUEST; no active session');
              return;
            }
            _log('RX STATE_REQUEST; replying with current playback state');
            _publish('STATE', playing: _playingOverride ?? isPlaying());
            return;
          }
          if (payload['kind'] == 'media_missing') {
            final missingId = payload['mediaId'];
            if (missingId is String) {
              _mediaMissingHandler?.call(missingId);
              for (final handler in _mediaMissingHandlers.toList()) {
                handler(missingId);
              }
            }
            return;
          }
          if (payload['kind'] == 'playback') {
            final remoteSession = payload['sessionId'];
            final type = payload['type'];
            if ((type == 'START' || type == 'STATE') && remoteSession is String) {
              final localSession = _sessionId;
              if (localSession == null ||
                  (type == 'START' && remoteSession.compareTo(localSession) < 0)) {
                _sessionId = remoteSession;
                _lastRemoteRevision = 0;
                _log('SESSION accepted id=$remoteSession');
              } else if (remoteSession != localSession) {
                _log('DROP competing session=$remoteSession active=$localSession');
                return;
              }
            } else if (_sessionId != null && remoteSession != _sessionId) {
              _log('DROP foreign session=$remoteSession active=$_sessionId');
              return;
            }
            final revision = payload['revision'];
            if (revision is int && revision <= _lastRemoteRevision) {
              _log('DROP stale playback rev=$revision last=$_lastRemoteRevision');
              return;
            }
            if (revision is int) {
              _lastRemoteRevision = revision;
              if (revision > _revision) _revision = revision;
            }
            _playbackHandler?.call(payload);
            for (final handler in _playbackHandlers.toList()) {
              handler(payload);
            }
            if (type == 'START' || type == 'STATE') {
              _remoteSessionHandler?.call(payload);
              for (final handler in _remoteSessionHandlers.toList()) {
                handler(payload);
              }
            }
            if (type == 'END') {
              _remoteSessionHandler?.call(null);
              for (final handler in _remoteSessionHandlers.toList()) {
                handler(null);
              }
              _sessionId = null;
              _lastRemoteRevision = 0;
              _playingOverride = false;
            }
            return;
          }
          if (payload['kind'] != 'library') return;
          final items = payload['items'];
          if (items is! List) return;
          final ids = items
              .whereType<Map>()
              .map((item) => item['movieId'])
              .whereType<String>()
              .toSet();
          _remoteLibraryHandler?.call(ids);
          for (final handler in _remoteLibraryHandlers.toList()) {
            handler(ids);
          }
        } catch (_) {}
      });
  }

  @override
  Future<void> requestLibrary() async {
    _log('TX LIBRARY_REQUEST');
    await room.localParticipant?.publishData(
      utf8.encode(jsonEncode({
        'kind': 'library_request',
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      })),
      reliable: true,
    );
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
  Future<void> start(String mediaId, Duration position) {
    _sessionId ??= '${room.localParticipant?.identity ?? 'client'}-${DateTime.now().microsecondsSinceEpoch}';
    _playingOverride = true;
    return _publish(
        'START',
        playing: true,
        mediaIdOverride: mediaId,
        positionOverride: position,
      );
  }

  @override
  Future<void> endSession() async {
    final active = _sessionId;
    if (active == null) return;
    _log('TX END session=$active');
    await room.localParticipant?.publishData(
      utf8.encode(jsonEncode({
        'kind': 'playback',
        'type': 'END',
        'sessionId': active,
        'revision': ++_revision,
        'mediaId': mediaId(),
        'positionMs': position().inMilliseconds,
        'playing': false,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      })),
      reliable: true,
    );
    _sessionId = null;
    _revision = 0;
    _lastRemoteRevision = 0;
    _playingOverride = false;
  }

  @override
  Future<void> requestPlaybackState() async {
    _log('TX STATE_REQUEST');
    await room.localParticipant?.publishData(
      utf8.encode(jsonEncode({
        'kind': 'state_request',
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      })),
      reliable: true,
    );
  }

  @override
  Future<void> mediaMissing(String mediaId) async {
    _log('TX MEDIA_MISSING media=$mediaId');
    await room.localParticipant?.publishData(
      utf8.encode(jsonEncode({
        'kind': 'media_missing',
        'mediaId': mediaId,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      })),
      reliable: true,
    );
  }

  @override
  Future<void> play() {
    _playingOverride = true;
    return _publish('PLAY', playing: true);
  }

  @override
  Future<void> pause() {
    _playingOverride = false;
    return _publish('PAUSE', playing: false);
  }

  @override
  Future<void> seekTo(Duration position) =>
      _publish('SEEK', positionOverride: position);

  @override
  void setRemoteLibraryHandler(RemoteLibraryHandler? handler) {
    _remoteLibraryHandler = handler;
  }

  @override
  void addRemoteLibraryHandler(RemoteLibraryHandler handler) {
    _remoteLibraryHandlers.add(handler);
  }

  @override
  void removeRemoteLibraryHandler(RemoteLibraryHandler handler) {
    _remoteLibraryHandlers.remove(handler);
  }

  @override
  void setLibraryProvider(LibraryProvider? provider) {
    _libraryProvider = provider;
  }

  @override
  void setPlaybackHandler(PlaybackHandler? handler) {
    _playbackHandler = handler;
  }

  @override
  void addPlaybackHandler(PlaybackHandler handler) {
    _playbackHandlers.add(handler);
  }

  @override
  void removePlaybackHandler(PlaybackHandler handler) {
    _playbackHandlers.remove(handler);
  }

  @override
  void setMediaMissingHandler(MediaMissingHandler? handler) {
    _mediaMissingHandler = handler;
  }

  @override
  void addMediaMissingHandler(MediaMissingHandler handler) {
    _mediaMissingHandlers.add(handler);
  }

  @override
  void removeMediaMissingHandler(MediaMissingHandler handler) {
    _mediaMissingHandlers.remove(handler);
  }

  @override
  void setRemoteSessionHandler(RemoteSessionHandler? handler) {
    _remoteSessionHandler = handler;
  }

  @override
  void addRemoteSessionHandler(RemoteSessionHandler handler) {
    _remoteSessionHandlers.add(handler);
  }

  @override
  void removeRemoteSessionHandler(RemoteSessionHandler handler) {
    _remoteSessionHandlers.remove(handler);
  }

  @override
  Future<void> dispose() async {
    _log('LISTENER dispose');
    _listener?.dispose();
    _listener = null;
    _remoteLibraryHandler = null;
    _playbackHandler = null;
    _mediaMissingHandler = null;
    _remoteSessionHandler = null;
    _remoteLibraryHandlers.clear();
    _playbackHandlers.clear();
    _mediaMissingHandlers.clear();
    _remoteSessionHandlers.clear();
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
  Future<void> requestLibrary() async {}
  @override
  Future<void> endSession() async {}
  @override
  Future<void> requestPlaybackState() async {}
  @override
  Future<void> mediaMissing(String mediaId) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  void setRemoteLibraryHandler(RemoteLibraryHandler? handler) {}
  @override
  void addRemoteLibraryHandler(RemoteLibraryHandler handler) {}
  @override
  void removeRemoteLibraryHandler(RemoteLibraryHandler handler) {}
  @override
  void setLibraryProvider(LibraryProvider? provider) {}
  @override
  void setPlaybackHandler(PlaybackHandler? handler) {}
  @override
  void addPlaybackHandler(PlaybackHandler handler) {}
  @override
  void removePlaybackHandler(PlaybackHandler handler) {}
  @override
  void setMediaMissingHandler(MediaMissingHandler? handler) {}
  @override
  void addMediaMissingHandler(MediaMissingHandler handler) {}
  @override
  void removeMediaMissingHandler(MediaMissingHandler handler) {}
  @override
  void setRemoteSessionHandler(RemoteSessionHandler? handler) {}
  @override
  void addRemoteSessionHandler(RemoteSessionHandler handler) {}
  @override
  void removeRemoteSessionHandler(RemoteSessionHandler handler) {}
  @override
  Future<void> dispose() async {}
}
