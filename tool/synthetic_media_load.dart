// Separate release target: exercises production media classes without changing
// the normal application entry point or loading/writing user preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:window_manager/window_manager.dart';

import 'package:syncwatch/app.dart';
import 'package:syncwatch/models/movie_item.dart';
import 'package:syncwatch/screens/player_screen.dart';
import 'package:syncwatch/services/call_engine.dart';
import 'package:syncwatch/services/livekit_connection.dart';
import 'package:syncwatch/services/sync_engine.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (args.length != 1) throw ArgumentError('Pass a JSON configuration file');
  final config =
      jsonDecode(await File(args.single).readAsString())
          as Map<String, dynamic>;
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(960, 640));
  await windowManager.setPosition(
    Offset(
      (config['windowX'] as num? ?? 20).toDouble(),
      (config['windowY'] as num? ?? 20).toDouble(),
    ),
  );
  runApp(SyntheticMediaLoad(config: config));
  await windowManager.show();
}

class SyntheticMediaLoad extends StatefulWidget {
  const SyntheticMediaLoad({super.key, required this.config});
  final Map<String, dynamic> config;

  @override
  State<SyntheticMediaLoad> createState() => _SyntheticMediaLoadState();
}

class _SyntheticMediaLoadState extends State<SyntheticMediaLoad> {
  final controller = AppController()..timelinePreview = true;
  late final LiveKitCallEngine call;
  late final MovieItem movie;
  LiveKitSyncEngine? sync;
  EventsListener<RoomEvent>? events;
  Timer? timer;
  Timer? stopTimer;
  bool sampling = false;
  String status = 'Connecting synthetic media';
  final clock = Stopwatch()..start();
  late final IOSink output;

  void record(String type, Map<String, Object?> values) {
    output.writeln(
      jsonEncode({
        'type': type,
        'time': DateTime.now().toUtc().toIso8601String(),
        'elapsedMs': clock.elapsedMilliseconds,
        'pid': pid,
        'identity': widget.config['identity'],
        ...values,
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    output = File(widget.config['statsPath'] as String).openWrite();
    unawaited(start());
  }

  Future<void> start() async {
    try {
      final config = widget.config;
      final mediaPath = config['mediaPath'] as String;
      movie = MovieItem(
        fileName: 'synthetic-1080p.mp4',
        fullPath: mediaPath,
        duration: const Duration(seconds: 180),
        resolution: '1920×1080',
        audioTracks: 1,
        subtitleTracks: 0,
      );
      call = LiveKitCallEngine(
        connection: LiveKitConnection(
          backendUrl: config['backendUrl'] as String,
        ),
        roomName: config['room'] as String,
        identity: config['identity'] as String,
        participantName: config['identity'] as String,
      );
      await call.join();
      final room = call.room!;
      final devices = await Hardware.instance.enumerateDevices();
      record('devices', {
        'devices': devices
            .map(
              (d) => {'kind': d.kind, 'label': d.label, 'deviceId': d.deviceId},
            )
            .toList(),
      });
      final input = devices
          .where(
            (d) =>
                d.kind == 'audioinput' &&
                d.label.toLowerCase().contains(
                  (config['audioInput'] as String).toLowerCase(),
                ),
          )
          .first;
      await room.setAudioInputDevice(input);
      await call.setMicrophoneEnabled(true);
      await call.setCameraEnabled(true);
      final engine = LiveKitSyncEngine(
        room: room,
        mediaId: () => movie.movieId,
        position: () => Duration(
          milliseconds: (controller.activeMoviePositionSeconds * 1000).round(),
        ),
        isPlaying: () => true,
      );
      engine.setLibraryProvider(
        () => [
          SharedMediaDescriptor(
            movieId: movie.movieId,
            fingerprint: movie.mediaFingerprint,
          ),
        ],
      );
      engine.addPlaybackHandler(
        (command) => record('sync', {'command': command}),
      );
      await engine.connect();
      events = room.createListener()
        ..on<TrackSubscribedEvent>((event) {
          record('subscribed', {'kind': event.track.kind.name});
          if (mounted) setState(() {});
        })
        ..on<TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        });
      setState(() {
        sync = engine;
        status = 'Running';
      });
      record('ready', {
        'localTracks': room.localParticipant!.trackPublications.length,
      });
      timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(sample()),
      );
      stopTimer = Timer(
        Duration(seconds: config['seconds'] as int? ?? 180),
        () => unawaited(stop()),
      );
    } catch (error, stack) {
      record('fatal', {'error': '$error', 'stack': '$stack'});
      await output.flush();
      try {
        await call.leave().timeout(const Duration(seconds: 5));
      } catch (_) {}
      await output.close();
      exit(1);
    }
  }

  Future<void> sample() async {
    if (sampling) return;
    sampling = true;
    try {
      final room = call.room!;
      final tracks = <Track>[
        ...room.localParticipant!.trackPublications.values
            .map((p) => p.track)
            .whereType<Track>(),
        ...room.remoteParticipants.values
            .expand((p) => p.trackPublications.values)
            .map((p) => p.track)
            .whereType<Track>(),
      ];
      for (final track in tracks) {
        final stats =
            await (track.sender?.getStats() ?? track.receiver?.getStats());
        if (stats == null) continue;
        for (final stat in stats) {
          if ([
            'outbound-rtp',
            'inbound-rtp',
            'media-source',
            'codec',
            'remote-inbound-rtp',
          ].contains(stat.type)) {
            record('rtc', {
              'trackKind': track.kind.name,
              'direction': track.sender != null ? 'send' : 'receive',
              'reportType': stat.type,
              'reportId': stat.id,
              'values': stat.values,
            });
          }
        }
      }
      record('playback', {
        'positionMs': (controller.activeMoviePositionSeconds * 1000).round(),
      });
      await output.flush();
    } catch (error) {
      record('statsError', {'error': '$error'});
    } finally {
      sampling = false;
    }
  }

  Future<void> stop() async {
    timer?.cancel();
    while (sampling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await sample();
    await call.stopCallMedia();
    record('mediaStopped', {
      'localTracks': call.room?.localParticipant?.trackPublications.length,
    });
    await events?.dispose();
    await sync?.dispose();
    await call.leave();
    record('finished', {});
    await output.flush();
    await output.close();
    // Removing the production screen disposes its mpv players before exit.
    setState(() {
      sync = null;
      status = 'Finished';
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    exit(0);
  }

  @override
  void dispose() {
    timer?.cancel();
    stopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = sync;
    final remote = callOrNullRemoteTrack();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: engine == null
          ? Scaffold(body: Center(child: Text(status)))
          : Stack(
              children: [
                PlayerScreen(
                  controller: controller,
                  movie: movie,
                  syncEngine: engine,
                  initialAudioTrack: '',
                  initialSubtitleTrack: '',
                  playlist: [movie],
                  initialIndex: 0,
                ),
                if (remote != null)
                  Positioned(
                    right: 24,
                    top: 70,
                    width: 320,
                    height: 240,
                    child: VideoTrackRenderer(
                      remote,
                      fit: VideoViewFit.contain,
                    ),
                  ),
              ],
            ),
    );
  }

  VideoTrack? callOrNullRemoteTrack() {
    if (sync == null) return null;
    for (final p in call.room!.remoteParticipants.values) {
      for (final publication in p.videoTrackPublications) {
        if (publication.track != null) return publication.track;
      }
    }
    return null;
  }
}
