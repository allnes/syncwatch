// Separate release target: exercises production media classes without changing
// the normal application entry point or loading/writing user preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:media_kit/media_kit.dart' show MediaKit, Player, NativePlayer;
import 'package:multiview_desktop/multiview_desktop.dart' as mv;
import 'package:window_manager/window_manager.dart';

import 'package:syncwatch/app.dart';
import 'package:syncwatch/models/movie_item.dart';
import 'package:syncwatch/screens/player_screen.dart';
import 'package:syncwatch/services/call_engine.dart';
import 'package:syncwatch/services/livekit_connection.dart';
import 'package:syncwatch/services/sync_engine.dart';
import 'package:syncwatch/services/player_diagnostics.dart';
import 'package:syncwatch/services/mpv_stats_reader.dart';

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
  mv.runMultiApp(
    home: (_, _) => SyntheticMediaLoad(config: config),
    config: mv.MultiAppConfig(
      generalParams: const mv.MultiPlatformParams(
        closeMode: mv.CloseMode.softCascade,
      ),
      globalWindowOptions: const mv.WindowOptions(title: 'SyncWatch'),
    ),
  );
  await windowManager.waitUntilReadyToShow(null, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class SyntheticMediaLoad extends StatefulWidget {
  const SyntheticMediaLoad({super.key, required this.config});
  final Map<String, dynamic> config;

  @override
  State<SyntheticMediaLoad> createState() => _SyntheticMediaLoadState();
}

class _SyntheticMediaLoadState extends State<SyntheticMediaLoad>
    with WidgetsBindingObserver {
  final controller = AppController()..timelinePreview = true;
  late final LiveKitCallEngine call;
  late final MovieItem movie;
  LiveKitSyncEngine? sync;
  EventsListener<RoomEvent>? events;
  Timer? timer;
  Timer? stopTimer;
  Timer? cycleTimer;
  Future<void> mediaCycle = Future<void>.value();
  Player? moviePlayer;
  MpvStatsReader? mpvStats;
  MpvStatsReader? seekStats;
  late final PlayerDiagnostics diagnostics;
  final actionTimers = <Timer>[];
  final concurrentActions = <Future<void>>{};
  Future<void> actionQueue = Future<void>.value();
  int lastMpvSampleMs = -5000;
  bool sampling = false;
  bool cycling = false;
  bool failed = false;
  String status = 'Connecting synthetic media';
  final clock = Stopwatch()..start();
  late final IOSink output;

  void record(String type, Map<String, Object?> values) {
    if (type == 'fatal' || type == 'statsError') failed = true;
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
    diagnostics = PlayerDiagnostics(
      synchronousStats: widget.config['synchronousStats'] == true,
      onPreviewReady: widget.config['previewOutputDirectory'] == null
          ? null
          : (bucket, frame) async {
              final directory = Directory(
                widget.config['previewOutputDirectory'] as String,
              );
              await directory.create(recursive: true);
              await File(
                '${directory.path}/preview-$bucket.png',
              ).writeAsBytes(frame);
            },
      legacyPreviewCapture: widget.config['legacyPreviewCapture'] == true,
      legacyPreviewSurface: widget.config['legacyPreviewSurface'] == true,
    );
    output = File(widget.config['statsPath'] as String).openWrite();
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record('lifecycle', {'state': state.name});
  }

  Future<void> start() async {
    try {
      final config = widget.config;
      final mediaPath = config['mediaPath'] as String;
      final devices = await Hardware.instance.enumerateDevices();
      final cameraLabel = config['cameraLabel'] as String?;
      final camera = cameraLabel == null
          ? null
          : devices.firstWhere(
              (d) =>
                  d.kind == 'videoinput' &&
                  d.label.toLowerCase().contains(cameraLabel.toLowerCase()),
            );
      movie = MovieItem(
        fileName: config['mediaName'] as String? ?? 'synthetic-1080p.mp4',
        fullPath: mediaPath,
        duration: Duration(
          milliseconds: config['durationMs'] as int? ?? 180000,
        ),
        resolution: config['resolution'] as String? ?? '1920×1080',
        audioTracks: config['audioTracks'] as int? ?? 1,
        subtitleTracks: config['subtitleTracks'] as int? ?? 0,
      );
      call = LiveKitCallEngine(
        connection: LiveKitConnection(
          backendUrl: config['backendUrl'] as String,
        ),
        roomName: config['room'] as String,
        identity: config['identity'] as String,
        participantName: config['identity'] as String,
        cameraDeviceId: camera?.deviceId,
      );
      await call.join();
      final room = call.room!;
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
        isPlaying: () => moviePlayer?.state.playing ?? false,
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
      final cycleAfter = config['restartCallAfterSeconds'] as int?;
      if (cycleAfter != null) {
        cycleTimer = Timer(Duration(seconds: cycleAfter), () {
          mediaCycle = restartMedia();
        });
      }
      record('ready', {
        'localTracks': room.localParticipant!.trackPublications.length,
      });
      for (final action in config['actions'] as List? ?? const []) {
        final item = Map<String, dynamic>.from(action as Map);
        actionTimers.add(
          Timer(Duration(seconds: item['atSeconds'] as int), () {
            if (item['concurrent'] == true) {
              final pending = runAction(item);
              concurrentActions.add(pending);
              unawaited(
                pending.whenComplete(() => concurrentActions.remove(pending)),
              );
            } else {
              actionQueue = actionQueue.then((_) => runAction(item));
            }
          }),
        );
      }
      timer = Timer.periodic(
        Duration(
          milliseconds: (config['sampleIntervalMs'] as int? ?? 5000).clamp(
            500,
            5000,
          ),
        ),
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

  Future<void> preparePlayer(Player player) async {
    moviePlayer = player;
    mpvStats = MpvStatsReader(player, useWorker: !diagnostics.synchronousStats);
    // Keep seek observation separate from the periodic snapshot's coalescing.
    // The measurement itself must not block Flutter while native decoding waits.
    seekStats = MpvStatsReader(player);
    final native = player.platform;
    if (native is! NativePlayer) return;
    final properties = widget.config['mpvProperties'] as Map? ?? const {};
    for (final entry in properties.entries) {
      await native.setProperty(entry.key as String, '${entry.value}');
    }
    record('mpvConfiguration', {
      for (final name in [
        'mpv-version',
        'hwdec',
        'hwdec-extra-frames',
        'vd-lavc-threads',
        'video-sync',
        'interpolation',
        'cache',
        'cache-on-disk',
        'demuxer-max-bytes',
        'demuxer-max-back-bytes',
        'demuxer-readahead-secs',
      ])
        name: await property(native, name),
    });
  }

  Future<String> property(NativePlayer player, String name) async {
    try {
      return await player.getProperty(name);
    } catch (_) {
      return 'n/a';
    }
  }

  Future<void> runAction(Map<String, dynamic> action) async {
    final player = moviePlayer;
    if (player == null) return;
    final elapsed = Stopwatch()..start();
    record('actionBegin', {'action': action});
    try {
      if (action['type'] == 'seek') {
        final target = Duration(seconds: action['positionSeconds'] as int);
        record('actionPhase', {'phase': 'localSeek'});
        await player.seek(target).timeout(const Duration(seconds: 5));
        record('actionPhase', {'phase': 'publishSeek'});
        await sync!.seekTo(target).timeout(const Duration(seconds: 5));
        record('actionPhase', {'phase': 'settleSeek'});
        final stats = seekStats;
        if (stats != null) {
          while ((await stats.read(['seeking']))['seeking'] == 'yes') {
            if (elapsed.elapsed > const Duration(seconds: 10)) {
              throw TimeoutException('Seek exceeded ten seconds');
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      } else if (action['type'] == 'restartMedia') {
        mediaCycle = restartMedia();
        await mediaCycle;
      } else if (action['type'] == 'resize') {
        await windowManager.setSize(
          Size(
            (action['width'] as num).toDouble(),
            (action['height'] as num).toDouble(),
          ),
        );
      } else if (action['type'] == 'preview') {
        await diagnostics.requestPreview!(
          (action['positionSeconds'] as num).toDouble(),
        );
      } else {
        throw ArgumentError('Unknown test action: ${action['type']}');
      }
      record('actionDone', {
        'action': action,
        'durationMs': elapsed.elapsedMilliseconds,
      });
    } catch (error) {
      record('fatal', {'error': 'Test action: $error'});
    }
  }

  Future<void> sample() async {
    if (sampling || cycling) return;
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
            'candidate-pair',
            'transport',
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
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'framesEnabled': WidgetsBinding.instance.framesEnabled,
        'playing': moviePlayer?.state.playing,
        'buffering': moviePlayer?.state.buffering,
      });
      final native = moviePlayer?.platform;
      if (native is NativePlayer &&
          clock.elapsedMilliseconds - lastMpvSampleMs >= 5000) {
        lastMpvSampleMs = clock.elapsedMilliseconds;
        record(
          'mpv',
          await mpvStats!.read([
            'hwdec-current',
            'frame-drop-count',
            'decoder-frame-drop-count',
            'avsync',
            'demuxer-cache-state',
            'cache-buffering-state',
            'estimated-vf-fps',
            'mistimed-frame-count',
            'vo-delayed-frame-count',
          ]),
        );
      }
      // IOSink drains asynchronously. Explicit flush binds the sink until it
      // completes, so concurrent action/track callbacks must not write during it.
      // Flush only after timers and listeners are stopped in stop().
    } catch (error) {
      record('statsError', {'error': '$error'});
    } finally {
      sampling = false;
    }
  }

  Future<void> restartMedia() async {
    cycling = true;
    while (sampling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    try {
      await call.stopCallMedia();
      record('cycleStopped', {
        'localTracks': call.room?.localParticipant?.trackPublications.length,
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      await call.setMicrophoneEnabled(true);
      await call.setCameraEnabled(true);
      record('cycleRestarted', {
        'localTracks': call.room?.localParticipant?.trackPublications.length,
      });
    } catch (error) {
      record('fatal', {'error': 'Media restart: $error'});
    } finally {
      cycling = false;
    }
  }

  Future<void> stop() async {
    for (final timer in actionTimers) {
      timer.cancel();
    }
    await actionQueue;
    await Future.wait(concurrentActions.toList());
    cycleTimer?.cancel();
    await mediaCycle;
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
    WidgetsBinding.instance.removeObserver(this);
    await output.flush();
    await output.close();
    // Removing the production screen disposes its mpv players before exit.
    setState(() {
      sync = null;
      status = 'Finished';
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    exit(failed ? 1 : 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    stopTimer?.cancel();
    cycleTimer?.cancel();
    for (final timer in actionTimers) {
      timer.cancel();
    }
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
                  preparePlayer: preparePlayer,
                  diagnostics: diagnostics,
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
