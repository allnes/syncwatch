import 'dart:math';

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
    String? identity,
    required this.participantName,
  }) : identity = identity ?? _createParticipantIdentity();

  static String _createParticipantIdentity() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // Keep one identity across reconnects, without displacing another client.
    return 'syncwatch-user-$suffix';
  }

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
    const quality = '480p4x3';
    const captureOptions = CameraCaptureOptions(
      params: VideoParameters(
        dimensions: VideoDimensionsPresets.h480_43,
        description: quality,
      ),
      maxFrameRate: 15.0,
    );
    const publishOptions = VideoPublishOptions(
      videoCodec: 'h264',
      simulcast: false,
      videoEncoding: VideoEncoding(
        maxFramerate: 15,
        maxBitrate: 850000,
      ),
    );

    _log(
      'CAMERA request enabled=$enabled uiQuality=$quality '
      'capture=${captureOptions.params.dimensions} maxFps=${captureOptions.maxFrameRate} '
      'codec=${publishOptions.videoCodec} simulcast=${publishOptions.simulcast} '
      'sendEncoding=${publishOptions.videoEncoding}',
    );

    final participant = _room?.localParticipant;
    if (participant == null) {
      _log('CAMERA deferred enabled=$enabled reason=room-not-connected');
      return;
    }

    try {
      // Keep one publication/transceiver for the whole call. Re-publishing on
      // every camera toggle causes renegotiation and additional transceivers on
      // Windows. Mute without stopping capture preserves the existing sender.
      final existingTrack = _ownedCameraTrack;
      final existingSid = _ownedCameraPublicationSid;
      if (existingTrack != null &&
          !existingTrack.isDisposed &&
          existingSid != null) {
        if (enabled) {
          await existingTrack.unmute(stopOnMute: true);
          _log('CAMERA unmuted sid=$existingSid persistentTrack=true');
        } else {
          await existingTrack.mute(stopOnMute: true);
          _log('CAMERA muted sid=$existingSid persistentTrack=true captureStopped=true');
        }
        return;
      }

      if (!enabled) {
        _log('CAMERA disabled before publication; no track created');
        return;
      }

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
          _log(
            'CAMERA sender stats t+3s count=${stats.length} '
            'stats=${stats.map((value) => {
              'encoder': value.encoderImplementation,
              'width': value.frameWidth,
              'height': value.frameHeight,
              'fps': value.framesPerSecond,
              'framesSent': value.framesSent,
              'bytesSent': value.bytesSent,
              'qualityLimitation': value.qualityLimitationReason,
            }).toList()}',
          );
          // Reuse LiveKit's existing samples; do not add a polling timer or
          // another getStats request for the remote cameras.
          for (final remote in
              _room?.remoteParticipants.values ?? const <RemoteParticipant>[]) {
            for (final publication in remote.videoTrackPublications) {
              final received = publication.track?.prevStats;
              _log(
                'CAMERA receiver stats t+3s '
                'decoder=${received?.decoderImplementation} '
                'width=${received?.frameWidth} height=${received?.frameHeight} '
                'fps=${received?.framesPerSecond} '
                'framesDecoded=${received?.framesDecoded} '
                'framesDropped=${received?.framesDropped}',
              );
            }
          }
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

    final publications = participant.trackPublications.values
        .where((publication) =>
            publication.source == TrackSource.microphone ||
            publication.source == TrackSource.camera)
        .toList();
    // Snapshot all senders before stopping any of them: native SDK versions
    // may not deserialize a transceiver whose direction is already stopped.
    final transceivers = {
      for (final publication in publications)
        publication.sid: publication.track?.transceiver,
    };

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

    if (publications.isEmpty) return;
    try {
      // Darwin's pre-negotiation object has an empty MID. Resolve the current
      // transceiver by stable sender ID before asking native code to stop it.
      // LiveKit 2.13 exposes this connection only through its engine.
      // ignore: invalid_use_of_internal_member
      final current = await _room?.engine.publisher?.pc.getTransceivers();
      for (final publication in publications) {
        final senderId = transceivers[publication.sid]?.sender.senderId;
        if (senderId == null) continue;
        for (final candidate in current ?? []) {
          if (candidate.sender.senderId == senderId) {
            transceivers[publication.sid] = candidate;
            break;
          }
        }
      }
    } catch (error) {
      _log('MEDIA transceiver lookup failed error=$error');
    }
    for (final publication in publications) {
      // Removing a track alone retains its encoder queues in a connected room.
      // Retire the sender before the SDK negotiates its unpublication.
      try {
        await transceivers[publication.sid]?.stop();
      } catch (error) {
        // A lost connection must not prevent the remaining media cleanup.
        _log('MEDIA transceiver stop failed sid=${publication.sid} error=$error');
      }
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
