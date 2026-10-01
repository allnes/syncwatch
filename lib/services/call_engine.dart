import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'livekit_connection.dart';

abstract class CallEngine {
  Future<void> join();
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> stopCallMedia();
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
  LocalVideoTrack? _ownedCameraTrack;
  String? _ownedCameraPublicationSid;

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
    const quality = '480p';
    const captureOptions = CameraCaptureOptions(
      params: VideoParameters(
        dimensions: VideoDimensionsPresets.h480_43,
        description: quality,
      ),
      maxFrameRate: 15.0,
    );
    const publishOptions = VideoPublishOptions(
      simulcast: false,
      videoEncoding: VideoEncoding(
        maxFramerate: 15,
        maxBitrate: 850000,
      ),
    );

    _log(
      'CAMERA request enabled=$enabled uiQuality=$quality '
      'capture=${captureOptions.params.dimensions} maxFps=${captureOptions.maxFrameRate} '
      'simulcast=${publishOptions.simulcast} '
      'sendEncoding=${publishOptions.videoEncoding}',
    );

    final participant = _room?.localParticipant;
    if (participant == null) {
      _log('CAMERA deferred enabled=$enabled reason=room-not-connected');
      return;
    }

    try {
      if (!enabled) {
        final sid = _ownedCameraPublicationSid;
        final track = _ownedCameraTrack;
        if (sid != null) {
          try {
            await participant.removePublishedTrack(sid);
            _log('CAMERA unpublished sid=$sid');
          } catch (error) {
            _log('CAMERA unpublish failed sid=$sid error=$error');
          }
        }
        if (track != null && !track.isDisposed) {
          try {
            await track.dispose();
            _log('CAMERA track disposed');
          } catch (error) {
            _log('CAMERA track dispose failed error=$error');
          }
        }
        _ownedCameraPublicationSid = null;
        _ownedCameraTrack = null;
        _log('CAMERA disabled ok fullyDisposed=true');
        return;
      }

      // Never retain a stale manually-created camera track across OFF -> ON.
      final staleSid = _ownedCameraPublicationSid;
      final staleTrack = _ownedCameraTrack;
      if (staleSid != null) {
        try { await participant.removePublishedTrack(staleSid); } catch (_) {}
      }
      if (staleTrack != null && !staleTrack.isDisposed) {
        try { await staleTrack.dispose(); } catch (_) {}
      }
      _ownedCameraPublicationSid = null;
      _ownedCameraTrack = null;

      final track = await LocalVideoTrack.createCameraTrack(captureOptions);
      _ownedCameraTrack = track;
      _log(
        'CAMERA track created options=${track.currentOptions} '
        'mediaTrackId=${track.mediaStreamTrack.id}',
      );
      try {
        final dynamic mediaTrack = track.mediaStreamTrack;
        final dynamic settings = await mediaTrack.getSettings();
        _log('CAMERA capture actual settings=$settings');
      } catch (error) {
        _log('CAMERA capture settings unavailable error=$error');
      }

      final publication = await participant.publishVideoTrack(
        track,
        publishOptions: publishOptions,
      );
      _ownedCameraPublicationSid = publication.sid;
      _log(
        'CAMERA published sid=${publication.sid} source=${publication.source} '
        'muted=${publication.muted} simulcast=${publishOptions.simulcast} '
        'capture=${track.currentOptions} publish=${track.lastPublishOptions}',
      );

      Future<void>.delayed(const Duration(seconds: 3), () async {
        if (_room == null || !_cameraEnabled || track.isDisposed) return;
        try {
          final stats = await track.getSenderStats();
          _log('CAMERA sender stats t+3s count=${stats.length} stats=$stats');
        } catch (error) {
          _log('CAMERA sender stats t+3s failed error=$error');
        }
      });
    } catch (error) {
      _log('CAMERA toggle failed enabled=$enabled error=$error');
      rethrow;
    }
  }
  @override
  Future<void> stopCallMedia() async {
    _microphoneEnabled = false;
    _cameraEnabled = false;
    final participant = _room?.localParticipant;
    if (participant == null) return;

    // Dispose the manually-owned camera track first; removePublishedTrack alone
    // does not guarantee that the capture source is released.
    final ownedTrack = _ownedCameraTrack;
    _ownedCameraTrack = null;
    _ownedCameraPublicationSid = null;
    if (ownedTrack != null && !ownedTrack.isDisposed) {
      try {
        await ownedTrack.dispose();
        _log('MEDIA camera track disposed');
      } catch (error) {
        _log('MEDIA camera track dispose failed error=$error');
      }
    }

    final publications = participant.trackPublications.values
        .where((publication) =>
            publication.source == TrackSource.microphone ||
            publication.source == TrackSource.camera)
        .toList();
    for (final publication in publications) {
      try {
        await participant.removePublishedTrack(publication.sid);
        _log(
          'MEDIA unpublished sid=${publication.sid} source=${publication.source}',
        );
      } catch (error) {
        _log(
          'MEDIA unpublish failed sid=${publication.sid} '
          'source=${publication.source} error=$error',
        );
      }
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
  Future<void> stopCallMedia() async {}

  @override
  Future<void> leave() async {}
}
