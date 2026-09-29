import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../core/app_theme.dart';
import '../models/movie_item.dart';
import '../services/sync_engine.dart';
import 'player_settings_screen.dart';
import 'settings_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.movie,
    required this.syncEngine,
    required this.initialAudioTrack,
    required this.initialSubtitleTrack,
    required this.playlist,
    required this.initialIndex,
    this.onShowCall,
    this.onReturnHome,
    this.onMovieChanged,
    this.onEndWatching,
    this.connectionInterrupted = false,
    this.connectionMessage,
    this.active = true,
  });

  final AppController controller;
  final MovieItem movie;
  final SyncEngine syncEngine;
  final String initialAudioTrack;
  final String initialSubtitleTrack;
  final List<MovieItem> playlist;
  final int initialIndex;
  final Future<void> Function()? onShowCall;
  final Future<void> Function()? onReturnHome;
  final ValueChanged<MovieItem>? onMovieChanged;
  final Future<void> Function()? onEndWatching;
  final bool connectionInterrupted;
  final String? connectionMessage;
  final bool active;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  bool get _isLight => Theme.of(context).brightness == Brightness.light;
  Color get _playerBackground =>
      _isLight ? syncLightBackgroundDeep : syncBackgroundDeep;
  Color get _playerChrome =>
      _isLight ? syncLightBackground : syncBackground;
  Color get _playerSurface =>
      _isLight ? syncLightSurfaceRaised : syncSurfaceRaised;
  Color get _playerBorder =>
      _isLight ? syncLightBorder : syncBorder;
  Color get _playerPrimary =>
      _isLight ? syncLightText : Colors.white;
  Color get _playerSecondary =>
      _isLight ? syncLightTextSecondary : Colors.white70;
  late final Player player;
  late final VideoController videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _volumeOsdTimer;
  Timer? _seekDebounceTimer;
  Timer? _previewDebounceTimer;
  Timer? _previewIdleDisposeTimer;
  Timer? _duckingRampTimer;
  Timer? _duckingReleaseTimer;
  Timer? _fullscreenControlsHideTimer;
  double? _queuedSeekTarget;
  double _appliedMovieVolume = -1;
  bool _lastDuckingEnabled = false;
  bool _lastRemoteSpeaking = false;
  bool _seekInFlight = false;
  bool _applyingRemoteCommand = false;
  bool _pausedForConnectionLoss = false;
  int _remoteCommandSerial = 0;
  final Stopwatch _playbackSessionClock = Stopwatch();
  Stopwatch? _bufferingClock;
  DateTime? _lastPlaybackHealthLog;
  bool? _lastBufferingState;
  bool _mpvHealthLogInFlight = false;

  Player? _previewPlayer;
  VideoController? _previewVideoController;
  String? _previewMediaPath;
  Uint8List? _previewFrame;
  double? _previewSeconds;
  double? _previewGlobalX;
  bool _timelineHovering = false;
  bool _previewFailed = false;
  int _previewRequestSerial = 0;
  bool _previewLoadInFlight = false;
  double? _pendingPreviewSeconds;
  int? _pendingPreviewBucket;
  final Map<int, Uint8List> _previewCache = <int, Uint8List>{};

  bool playing = false;
  bool movieMuted = false;
  bool callMuted = false;
  bool isFullscreen = false;
  bool _fullscreenTransition = false;
  bool _restoreFullscreenAfterMinimize = false;
  bool _minimizeInProgress = false;
  bool _resumeFullscreenWhenActivated = false;
  bool topControlsVisible = true;
  bool bottomControlsVisible = true;
  late int currentIndex;
  late MovieItem currentMovie;
  Set<String>? sharedMovieIds;
  String? syncNotice;
  bool remoteLibraryReceived = false;
  bool remoteSessionActive = false;

  int? _sharedNeighborIndex(int direction) {
    var index = currentIndex + direction;
    while (index >= 0 && index < widget.playlist.length) {
      final allowed = sharedMovieIds;
      if (allowed == null) return null;
      if (allowed.contains(widget.playlist[index].movieId)) {
        return index;
      }
      index += direction;
    }
    return null;
  }

  double positionSeconds = 0;
  double durationSeconds = 0;
  double? volumeOsd;

  List<AudioTrack> audioTracks = const [];
  List<SubtitleTrack> subtitleTracks = const [];
  AudioTrack? currentAudioTrack;
  SubtitleTrack? currentSubtitleTrack;

  final GlobalKey playerSettingsButtonKey = GlobalKey();
  final GlobalKey playlistButtonKey = GlobalKey();
  final GlobalKey audioTrackButtonKey = GlobalKey();
  final GlobalKey subtitleButtonKey = GlobalKey();
  final GlobalKey volumeButtonKey = GlobalKey();
  final FocusNode _playerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.controller.addListener(_handleControllerAudioState);
    _lastDuckingEnabled = widget.controller.ducking;
    _lastRemoteSpeaking = widget.controller.remoteSpeaking;
    if (widget.active) {
      unawaited(
        windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        ),
      );
    }

    currentIndex = widget.initialIndex < 0 ? 0 : widget.initialIndex;
    currentMovie = widget.playlist.isEmpty
        ? widget.movie
        : widget.playlist[
            currentIndex.clamp(0, widget.playlist.length - 1).toInt()
          ];

    player = Player();
    videoController = VideoController(player);
    _playbackSessionClock.start();
    _playbackLog(
      'INIT media="${currentMovie.fileName}" path="${currentMovie.fullPath}"',
    );

    _subscriptions.add(
      player.stream.position.listen((position) {
        if (!mounted) return;
        if (_queuedSeekTarget != null || _seekInFlight) return;

        final seconds = position.inMilliseconds / 1000.0;
        widget.controller.updatePlaybackPosition(
          currentMovie.fullPath,
          seconds,
        );
        final now = DateTime.now();
        if (_lastPlaybackHealthLog == null ||
            now.difference(_lastPlaybackHealthLog!) >=
                const Duration(seconds: 10)) {
          _lastPlaybackHealthLog = now;
          _playbackLog(
            'HEALTH pos=${position.inMilliseconds}ms '
            'duration=${player.state.duration.inMilliseconds}ms '
            'playing=${player.state.playing} '
            'buffering=${player.state.buffering} '
            'previewActive=${_previewPlayer != null} '
            'previewHover=$_timelineHovering '
            'previewCache=${_previewCache.length}',
          );
          unawaited(_logMpvPlaybackHealth());
        }
        setState(() => positionSeconds = seconds);
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((duration) {
        if (!mounted) return;
        setState(() => durationSeconds = duration.inMilliseconds / 1000.0);
      }),
    );
    _subscriptions.add(
      player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => playing = value);
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        if (value == _lastBufferingState) return;
        _lastBufferingState = value;
        if (value) {
          _bufferingClock = Stopwatch()..start();
          _playbackLog(
            'BUFFERING_START pos=${player.state.position.inMilliseconds}ms '
            'playing=${player.state.playing}',
          );
        } else {
          final elapsed = _bufferingClock?.elapsedMilliseconds;
          _bufferingClock = null;
          _playbackLog(
            'BUFFERING_END duration=${elapsed ?? -1}ms '
            'pos=${player.state.position.inMilliseconds}ms '
            'playing=${player.state.playing}',
          );
        }
      }),
    );
    _subscriptions.add(
      player.stream.videoParams.listen((params) {
        _playbackLog(
          'VIDEO_PARAMS dw=${params.dw} dh=${params.dh} '
          'aspect=${params.aspect}',
        );
      }),
    );
    _subscriptions.add(
      player.stream.tracks.listen((tracks) {
        final realAudio = tracks.audio
            .where((track) => track.id != 'auto' && track.id != 'no')
            .toList();
        final realSubtitles = tracks.subtitle
            .where((track) => track.id != 'auto')
            .toList();

        if (!mounted) return;
        setState(() {
          audioTracks = realAudio;
          subtitleTracks = realSubtitles;
        });
      }),
    );
    _subscriptions.add(
      player.stream.track.listen((track) {
        if (!mounted) return;
        setState(() {
          currentAudioTrack = track.audio;
          currentSubtitleTrack = track.subtitle;
        });
      }),
    );

    widget.syncEngine.addRemoteSessionHandler(_onRemoteSession);
    widget.syncEngine.addMediaMissingHandler(_onMediaMissing);
    widget.syncEngine.addPlaybackHandler(_onPlaybackCommand);
    widget.syncEngine.addRemoteLibraryHandler(_onRemoteLibrary);
    _openMedia();
    widget.syncEngine.connect().then((_) {
      unawaited(widget.syncEngine.requestPlaybackState());
    });
  }

  Future<void> _handleConnectionInterruption() async {
    if (!widget.connectionInterrupted || _pausedForConnectionLoss) return;
    _pausedForConnectionLoss = true;
    await player.pause();
    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      player.state.position.inMilliseconds / 1000.0,
      persist: true,
    );
    debugPrint('[SyncWatch][SYNC] local playback paused for connection loss');
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.connectionInterrupted && widget.connectionInterrupted) {
      unawaited(_handleConnectionInterruption());
    } else if (oldWidget.connectionInterrupted && !widget.connectionInterrupted) {
      _pausedForConnectionLoss = false;
      unawaited(widget.syncEngine.requestPlaybackState());
    }

    if (oldWidget.active == widget.active) return;

    if (widget.active) {
      unawaited(
        windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        ),
      );
      if (_resumeFullscreenWhenActivated) {
        _resumeFullscreenWhenActivated = false;
        unawaited(_setPlayerFullscreen(true));
      }
      _playerFocusNode.requestFocus();
    } else {
      unawaited(
        windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
          windowButtonVisibility: true,
        ),
      );
      _playerFocusNode.unfocus();
    }
  }

  String get _initialAudioForCurrent {
    if (currentMovie.fullPath == widget.movie.fullPath) {
      return widget.initialAudioTrack;
    }
    if (currentMovie.audioTrackNames.isNotEmpty) {
      return currentMovie.audioTrackNames.first;
    }
    return widget.controller.t('defaultAudio');
  }

  String get _initialSubtitleForCurrent {
    if (currentMovie.fullPath == widget.movie.fullPath) {
      return widget.initialSubtitleTrack;
    }
    if (currentMovie.subtitleTrackNames.isNotEmpty) {
      return currentMovie.subtitleTrackNames.first;
    }
    return widget.controller.t('noSubtitles');
  }

  void _handleControllerAudioState() {
    final duckingChanged = _lastDuckingEnabled != widget.controller.ducking;
    final speakingChanged =
        _lastRemoteSpeaking != widget.controller.remoteSpeaking;
    _lastDuckingEnabled = widget.controller.ducking;
    _lastRemoteSpeaking = widget.controller.remoteSpeaking;
    if (!(duckingChanged || speakingChanged)) return;

    _duckingReleaseTimer?.cancel();
    _duckingReleaseTimer = null;

    if (widget.controller.ducking && widget.controller.remoteSpeaking) {
      _rampMovieVolume();
      return;
    }

    // Keep short gaps between words from pumping the movie volume.
    _duckingReleaseTimer = Timer(const Duration(milliseconds: 280), () {
      _duckingReleaseTimer = null;
      _rampMovieVolume();
    });
  }

  double get _targetMovieVolume {
    if (movieMuted) return 0;
    final base = widget.controller.movieVolume * 100.0;
    return widget.controller.ducking && widget.controller.remoteSpeaking
        ? base * 0.35
        : base;
  }

  void _rampMovieVolume() {
    _duckingRampTimer?.cancel();
    final target = _targetMovieVolume;
    final start = _appliedMovieVolume >= 0
        ? _appliedMovieVolume
        : widget.controller.movieVolume * 100.0;
    final duckingDown = target < start;
    final steps = duckingDown ? 6 : 12;
    final interval = duckingDown
        ? const Duration(milliseconds: 30)
        : const Duration(milliseconds: 50);
    var step = 0;
    _duckingRampTimer = Timer.periodic(interval, (timer) {
      step++;
      final t = (step / steps).clamp(0.0, 1.0);
      final value = start + (target - start) * t;
      _appliedMovieVolume = value;
      unawaited(player.setVolume(value));
      if (step >= steps) {
        timer.cancel();
        _duckingRampTimer = null;
      }
    });
  }

  Future<void> _setEffectiveMovieVolume() async {
    _duckingRampTimer?.cancel();
    final value = _targetMovieVolume;
    _appliedMovieVolume = value;
    await player.setVolume(value);
  }

  void _playbackLog(String message) {
    debugPrint(
      '[SyncWatch][PLAYBACK] '
      't=${_playbackSessionClock.elapsedMilliseconds}ms $message',
    );
  }

  Future<void> _logMpvPlaybackHealth() async {
    if (_mpvHealthLogInFlight) return;
    final native = player.platform;
    if (native is! NativePlayer) {
      _playbackLog('MPV_HEALTH unavailable platform=${native.runtimeType}');
      return;
    }

    _mpvHealthLogInFlight = true;
    try {
      Future<String> property(String name) async {
        try {
          return await native.getProperty(name);
        } catch (_) {
          return 'n/a';
        }
      }

      final values = await Future.wait(<Future<String>>[
        property('video-codec'),
        property('video-format'),
        property('hwdec-current'),
        property('container-fps'),
        property('estimated-vf-fps'),
        property('display-fps'),
        property('frame-drop-count'),
        property('decoder-frame-drop-count'),
        property('video-sync'),
      ]);
      _playbackLog(
        'MPV_HEALTH codec=${values[0]} format=${values[1]} '
        'hwdec=${values[2]} containerFps=${values[3]} '
        'estimatedFps=${values[4]} displayFps=${values[5]} '
        'frameDrops=${values[6]} decoderDrops=${values[7]} '
        'videoSync=${values[8]}',
      );
    } finally {
      _mpvHealthLogInFlight = false;
    }
  }

  Future<void> _openMedia() async {
    final openClock = Stopwatch()..start();
    _playbackLog('OPEN_BEGIN media="${currentMovie.fileName}"');
    final resumePosition =
        widget.controller.playbackPositionFor(currentMovie.fullPath);

    final openingVolume = widget.controller.rememberMovieVolume
        ? widget.controller.movieVolume
        : widget.controller.defaultMovieVolume;
    _appliedMovieVolume = openingVolume * 100.0;
    await player.setVolume(_targetMovieVolume);
    await player.open(
      Media(Uri.file(currentMovie.fullPath).toString()),
      play: false,
    );
    _playbackLog(
      'OPEN_DONE elapsed=${openClock.elapsedMilliseconds}ms '
      'duration=${player.state.duration.inMilliseconds}ms',
    );

    widget.controller.beginPlaybackSession(currentMovie.fullPath);

    if (resumePosition > 0) {
      await player.seek(
        Duration(milliseconds: (resumePosition * 1000).round()),
      );
    }

    // Give libmpv a moment to expose tracks, then apply the preselected values.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _applyInitialTracks();
    _playbackLog(
      'TRACKS_READY elapsed=${openClock.elapsedMilliseconds}ms '
      'audio=${player.state.tracks.audio.length} '
      'subtitle=${player.state.tracks.subtitle.length}',
    );

    // Entering the player via Start/Continue Watching means playback should
    // begin immediately rather than opening on a paused first frame.
    await player.play();
    _playbackLog(
      'PLAY_REQUESTED elapsed=${openClock.elapsedMilliseconds}ms '
      'pos=${player.state.position.inMilliseconds}ms',
    );
    if (!_applyingRemoteCommand) {
      await widget.syncEngine.start(
        currentMovie.movieId,
        player.state.position,
      );
    }
  }

  void _onMediaMissing(String mediaId) {
    if (!mounted) return;
    setState(() => syncNotice = 'У собеседника нет этого фильма');
    Timer(const Duration(seconds: 4), () {
      if (mounted && syncNotice != null) setState(() => syncNotice = null);
    });
  }

  void _onRemoteLibrary(Set<String> remoteIds) {
    if (!mounted) return;
    final localIds = widget.playlist.map((movie) => movie.movieId).toSet();
    setState(() {
      remoteLibraryReceived = true;
      sharedMovieIds = localIds.intersection(remoteIds);
    });
  }

  void _onPlaybackCommand(Map<String, dynamic> command) {
    final serial = ++_remoteCommandSerial;
    unawaited(_applyRemotePlaybackCommand(command, serial));
  }

  void _onRemoteSession(Map<String, dynamic>? state) {
    if (!mounted) return;
    setState(() => remoteSessionActive = state != null);
  }

  Future<void> _applyRemotePlaybackCommand(
    Map<String, dynamic> command,
    int serial,
  ) async {
    while (_applyingRemoteCommand) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (serial != _remoteCommandSerial) return;
    }
    if (serial != _remoteCommandSerial) return;
    final mediaId = command['mediaId'];
    if (mediaId is! String) return;
    if (mediaId != currentMovie.movieId) {
      if (command['type'] != 'START') return;
      final index = widget.playlist.indexWhere((movie) => movie.movieId == mediaId);
      if (index < 0) {
        debugPrint('[SyncWatch][SYNC] MEDIA_MISSING media=$mediaId');
        await widget.syncEngine.mediaMissing(mediaId);
        return;
      }
      final nextMovie = widget.playlist[index];
      setState(() {
        currentIndex = index;
        currentMovie = nextMovie;
        positionSeconds = 0;
        durationSeconds = 0;
      });
      widget.onMovieChanged?.call(nextMovie);
      await player.open(
        Media(Uri.file(nextMovie.fullPath).toString()),
        play: false,
      );
    }
    final type = command['type'];
    final positionMs = command['positionMs'];
    final target = positionMs is int
        ? Duration(milliseconds: positionMs)
        : player.state.position;

    _applyingRemoteCommand = true;
    try {
      if (type == 'END') {
        await player.pause();
        if (widget.onEndWatching != null) {
          await widget.onEndWatching!();
        }
        return;
      }
      if (type == 'STATE') {
        await player.seek(target);
        final remotePlaying = command['playing'];
        if (remotePlaying == true) {
          await player.play();
        } else if (remotePlaying == false) {
          await player.pause();
        }
      } else if (type == 'START' || type == 'SEEK') {
        await player.seek(target);
      }
      if (type == 'START' || type == 'PLAY') {
        if (type == 'PLAY') await player.seek(target);
        await player.play();
      } else if (type == 'PAUSE') {
        await player.seek(target);
        await player.pause();
      }
      if (mounted) {
        setState(() {
          positionSeconds = target.inMilliseconds / 1000.0;
        });
      }
    } finally {
      _applyingRemoteCommand = false;
    }
  }

  Future<void> _applyInitialTracks() async {
    final tracks = player.state.tracks;

    final audio = tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .cast<AudioTrack>()
        .toList();
    if (audio.isNotEmpty) {
      final match = audio.where(
        (track) => _audioLabel(track) == _initialAudioForCurrent,
      );
      await player.setAudioTrack(match.isNotEmpty ? match.first : audio.first);
    }

    final subtitles = tracks.subtitle
        .where((track) => track.id != 'auto')
        .cast<SubtitleTrack>()
        .toList();

    final selected = subtitles.where(
      (track) => _subtitleLabel(track) == _initialSubtitleForCurrent,
    );
    if (selected.isNotEmpty) {
      await player.setSubtitleTrack(selected.first);
    } else if (_initialSubtitleForCurrent == widget.controller.t('subtitlesOff') ||
        _initialSubtitleForCurrent == widget.controller.t('noSubtitles')) {
      await player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(
      windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      ),
    );
    _volumeOsdTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _previewDebounceTimer?.cancel();
    _previewIdleDisposeTimer?.cancel();
    _duckingRampTimer?.cancel();
    _duckingReleaseTimer?.cancel();
    _fullscreenControlsHideTimer?.cancel();
    widget.controller.removeListener(_handleControllerAudioState);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      positionSeconds,
      persist: true,
    );
    widget.syncEngine.removeRemoteSessionHandler(_onRemoteSession);
    widget.syncEngine.removePlaybackHandler(_onPlaybackCommand);
    widget.syncEngine.removeRemoteLibraryHandler(_onRemoteLibrary);
    widget.syncEngine.removeMediaMissingHandler(_onMediaMissing);
    // SyncEngine lifecycle is owned by LibraryScreen and shared with this player.
    _previewPlayer?.dispose();
    _previewVideoController = null;
    player.dispose();
    _playerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              await _returnToHome();
            }
          },
          child: Scaffold(
          backgroundColor: _playerBackground,
          body: KeyboardListener(
            focusNode: _playerFocusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: Listener(
            onPointerDown: (_) => _playerFocusNode.requestFocus(),
            onPointerHover: (event) {

            },
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final delta = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
                _changeMovieVolume(delta);
              }
            },
            child: Stack(
              children: [
                if (widget.connectionInterrupted)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.connectionMessage ?? 'Соединение потеряно. Воспроизведение приостановлено.',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (syncNotice != null)
                  Positioned(
                    top: 86,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          child: Text(
                            syncNotice!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_previewVideoController != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 2,
                    height: 2,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.0,
                        child: Video(
                          controller: _previewVideoController!,
                          controls: NoVideoControls,
                          fit: BoxFit.cover,
                          fill: Colors.black,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(child: _movieSurface(context)),

                if (isFullscreen) ...[
                  // Stable trigger strip: it never changes size when the bar
                  // appears, so revealing controls cannot generate a false exit.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 12,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerHover: (_) => _showFullscreenControls(),
                      onPointerMove: (_) => _showFullscreenControls(),
                      child: MouseRegion(
                        onEnter: (_) => _showFullscreenControls(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  if (topControlsVisible)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 40,
                      child: MouseRegion(
                        onEnter: (_) => _showFullscreenControls(),
                        onExit: (_) => _scheduleFullscreenControlsHide(),
                        child: _mergedTopBar(
                          context,
                          compact: true,
                          fullscreenMode: true,
                        ),
                      ),
                    ),
                ]
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _mergedTopBar(
                      context,
                      fullscreenMode: false,
                    ),
                  ),

                if (isFullscreen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 70,
                    child: MouseRegion(
                      onEnter: (_) => _showFullscreenControls(),
                      onExit: (_) => _scheduleFullscreenControlsHide(),
                      child: bottomControlsVisible
                          ? Align(
                              alignment: Alignment.bottomCenter,
                              child: _controls(),
                            )
                          : const SizedBox.expand(),
                    ),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _controls(),
                  ),

                if (_timelineHovering &&
                    widget.controller.timelinePreview &&
                    _previewSeconds != null)
                  _timelinePreviewOverlay(context),

                if (volumeOsd != null)
                  Positioned(
                    right: 32,
                    top: isFullscreen && !topControlsVisible ? 24 : 76,
                    child: _volumeIndicator(),
                  ),
              ],
            ),
          ),
          ),
        ),
        );
      },
    );
  }

  void _showFullscreenControls() {
    _fullscreenControlsHideTimer?.cancel();
    _fullscreenControlsHideTimer = null;
    if (!topControlsVisible || !bottomControlsVisible) {
      setState(() {
        topControlsVisible = true;
        bottomControlsVisible = true;
      });
    }
  }

  void _scheduleFullscreenControlsHide() {
    _fullscreenControlsHideTimer?.cancel();
    _fullscreenControlsHideTimer =
        Timer(const Duration(milliseconds: 350), () {
      _fullscreenControlsHideTimer = null;
      if (!mounted || !isFullscreen) return;
      if (topControlsVisible || bottomControlsVisible) {
        setState(() {
          topControlsVisible = false;
          bottomControlsVisible = false;
        });
      }
    });
  }

  Future<void> _handleKeyEvent(KeyEvent event) async {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      await _skip(-widget.controller.skipSeconds);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      await _skip(widget.controller.skipSeconds);
      return;
    }
    if (key == LogicalKeyboardKey.space) {
      await _togglePlayback();
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      await _changeMovieVolume(0.05);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      await _changeMovieVolume(-0.05);
      return;
    }
    if (key == LogicalKeyboardKey.keyM) {
      movieMuted = !movieMuted;
      await _setEffectiveMovieVolume();
      if (mounted) setState(() {});
      return;
    }
    if (key == LogicalKeyboardKey.keyF) {
      await _toggleFullscreen();
      return;
    }
    if (key == LogicalKeyboardKey.escape && isFullscreen) {
      await _toggleFullscreen();
    }
  }

  Widget _movieSurface(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: isFullscreen ? 0 : 32,
        bottom: isFullscreen ? 0 : 78,
      ),
      color: Colors.black,
      child: MouseRegion(
        cursor: isFullscreen &&
                widget.controller.hideCursorFullscreen &&
                !topControlsVisible &&
                !bottomControlsVisible
            ? SystemMouseCursors.none
            : SystemMouseCursors.basic,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _toggleFullscreen,
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final video = Video(
                  controller: videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  fill: Colors.black,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    textAlign: TextAlign.center,
                    padding: EdgeInsets.fromLTRB(
                      48,
                      12,
                      48,
                      _subtitleBottomPadding(constraints.maxHeight),
                    ),
                    style: TextStyle(
                      height: 1.16,
                      fontFamily: widget.controller.subtitleFontFamily,
                      fontSize: widget.controller.subtitleFontSize,
                      fontWeight: FontWeight.w700,
                      color: Color(widget.controller.subtitleTextColorValue),
                      backgroundColor: Colors.transparent,
                      shadows: _subtitleOutlineShadows(),
                    ),
                  ),
                );

                return _applyVideoColorAdjustments(video);
              },
            ),

          ],
        ),
      ),
      ),
    );
  }

  Widget _mergedTopBar(
    BuildContext context, {
    bool compact = false,
    required bool fullscreenMode,
  }) {
    final barColor = _playerChrome;
    final barHeight = compact ? 40.0 : 32.0;
    final titleFontSize = compact ? 12.5 : 12.0;
    const buttonWidth = 46.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart:
          fullscreenMode ? null : (_) => windowManager.startDragging(),
      onDoubleTap: _toggleFullscreen,
      child: Container(
        height: barHeight,
        color: barColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 250),
                  child: Tooltip(
                    message: currentMovie.fileName,
                    waitDuration: const Duration(milliseconds: 350),
                    child: Text(
                      currentMovie.fileName,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w600,
                        color: _playerPrimary.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: compact ? 8 : 10,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: widget.controller.t('back'),
                    waitDuration: const Duration(milliseconds: 350),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: _returnToHome,
                      child: SizedBox(
                        height: barHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back_rounded,
                                size: compact ? 17 : 16,
                              ),
                              Text(
                                'SyncWatch',
                                style: TextStyle(
                                  fontSize: compact ? 14.5 : 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 9),
                  SizedBox(
                    height: compact ? 18 : 17,
                    child: const VerticalDivider(width: 1),
                  ),
                  SizedBox(width: compact ? 8 : 7),
                  Icon(
                    Icons.groups_2_rounded,
                    color: syncAccentSoft,
                    size: compact ? 17 : 16,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.controller.roomName,
                    style: TextStyle(fontSize: compact ? 12 : 11.5),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onShowCall != null)
                    IconButton(
                      tooltip: widget.controller.t('goToCall'),
                      visualDensity: VisualDensity.compact,
                      constraints: BoxConstraints(
                        minWidth: compact ? 32 : 34,
                        minHeight: barHeight,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.onShowCall?.call(),
                      icon: Icon(
                        Icons.videocam_rounded,
                        size: compact ? 17 : 16,
                      ),
                    ),
                  IconButton(
                    tooltip: widget.controller.t('settings'),
                    visualDensity: VisualDensity.compact,
                    constraints: BoxConstraints(
                      minWidth: compact ? 32 : 34,
                      minHeight: barHeight,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.56),
                      builder: (_) =>
                          SettingsScreen(controller: widget.controller),
                    ),
                    icon: Icon(
                      Icons.settings_rounded,
                      size: compact ? 17 : 16,
                    ),
                  ),
                  _windowBarButton(
                    tooltip: widget.controller.t('minimize'),
                    width: buttonWidth,
                    height: barHeight,
                    icon: Icons.remove_rounded,
                    iconSize: 14,
                    onPressed: _minimizePlayerWindow,
                  ),
                  _windowBarButton(
                    tooltip: widget.controller.t('fullscreen'),
                    width: buttonWidth,
                    height: barHeight,
                    icon: fullscreenMode
                        ? Icons.fullscreen_exit_rounded
                        : Icons.crop_square_rounded,
                    iconSize: fullscreenMode ? 16 : 13,
                    onPressed: _toggleFullscreen,
                  ),
                  _windowBarButton(
                    tooltip: widget.controller.t('hide'),
                    width: buttonWidth,
                    height: barHeight,
                    icon: Icons.close_rounded,
                    iconSize: 16,
                    onPressed: _endWatchingFromPlayer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowBarButton({
    required String tooltip,
    required double width,
    required double height,
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: height,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.expand(),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(icon, size: iconSize),
        ),
      ),
    );
  }

  Future<void> _endWatchingFromPlayer() async {
    await widget.syncEngine.endSession();
    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      player.state.position.inMilliseconds / 1000.0,
      persist: true,
    );

    if (isFullscreen) {
      await _setPlayerFullscreen(false);
    }

    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );

    if (widget.onEndWatching != null) {
      await widget.onEndWatching!.call();
      return;
    }

    await _returnToHome();
  }

  Future<void> _minimizePlayerWindow() async {
    if (_minimizeInProgress) return;
    _minimizeInProgress = true;
    final wasFullscreen = isFullscreen;
    _restoreFullscreenAfterMinimize = wasFullscreen;

    try {
      if (wasFullscreen) {
        await _setPlayerFullscreen(false);
      }
      await windowManager.minimize();
    } finally {
      _minimizeInProgress = false;
    }
  }

  Widget _applyVideoColorAdjustments(Widget child) {
    Widget result = child;

    final saturation = 1.0 + widget.controller.videoSaturation;
    final s = saturation;
    final ir = (1 - s) * 0.2126;
    final ig = (1 - s) * 0.7152;
    final ib = (1 - s) * 0.0722;

    result = ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        ir + s, ig, ib, 0, 0,
        ir, ig + s, ib, 0, 0,
        ir, ig, ib + s, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: result,
    );

    final hue = widget.controller.videoHue * math.pi / 180.0;
    final cosH = math.cos(hue);
    final sinH = math.sin(hue);
    result = ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        0.213 + cosH * 0.787 - sinH * 0.213,
        0.715 - cosH * 0.715 - sinH * 0.715,
        0.072 - cosH * 0.072 + sinH * 0.928,
        0,
        0,
        0.213 - cosH * 0.213 + sinH * 0.143,
        0.715 + cosH * 0.285 + sinH * 0.140,
        0.072 - cosH * 0.072 - sinH * 0.283,
        0,
        0,
        0.213 - cosH * 0.213 - sinH * 0.787,
        0.715 - cosH * 0.715 + sinH * 0.715,
        0.072 + cosH * 0.928 + sinH * 0.072,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: result,
    );

    final contrast = 1.0 + widget.controller.videoContrast;
    final brightness = widget.controller.videoBrightness * 255.0;
    final translate = 128.0 * (1.0 - contrast) + brightness;
    result = ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        contrast, 0, 0, 0, translate,
        0, contrast, 0, 0, translate,
        0, 0, contrast, 0, translate,
        0, 0, 0, 1, 0,
      ]),
      child: result,
    );

    return result;
  }

  List<Shadow> _subtitleOutlineShadows() {
    final width = widget.controller.subtitleOutlineWidth;
    if (width <= 0) return const <Shadow>[];
    final color = Color(widget.controller.subtitleOutlineColorValue);
    return <Shadow>[
      Shadow(offset: Offset(-width, -width), color: color),
      Shadow(offset: Offset(width, -width), color: color),
      Shadow(offset: Offset(-width, width), color: color),
      Shadow(offset: Offset(width, width), color: color),
      Shadow(offset: Offset(0, -width), color: color),
      Shadow(offset: Offset(0, width), color: color),
      Shadow(offset: Offset(-width, 0), color: color),
      Shadow(offset: Offset(width, 0), color: color),
    ];
  }

  double _subtitleBottomPadding(double videoHeight) {
    final offset = widget.controller.subtitleVerticalOffset;
    final isTop = widget.controller.subtitlePosition == 'top';

    var base = isTop
        ? videoHeight * 0.76 - offset
        : 20.0 + offset;

    if (!isTop && isFullscreen && bottomControlsVisible) {
      base += 56;
    }

    return base.clamp(0.0, videoHeight * 0.90).toDouble();
  }

  Future<void> _showPlayerSettings() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.56),
      builder: (_) => PlayerSettingsScreen(controller: widget.controller),
    );
  }

  void _onTimelineHover(PointerHoverEvent event, double width) {
    _previewIdleDisposeTimer?.cancel();
    if (!widget.controller.timelinePreview || durationSeconds <= 0 || width <= 0) {
      return;
    }

    const edge = 10.0;
    final usableWidth = (width - edge * 2).clamp(1.0, double.infinity);
    final x = (event.localPosition.dx - edge).clamp(0.0, usableWidth);
    final ratio = x / usableWidth;
    final seconds = durationSeconds * ratio;

    setState(() {
      _timelineHovering = true;
      _previewFailed = false;
      _previewSeconds = seconds;
      _previewGlobalX = event.position.dx;
    });

    final bucket = (seconds / 2).round() * 2;
    final cached = _previewCache[bucket];
    if (cached != null) {
      setState(() => _previewFrame = cached);
      return;
    }

    _previewDebounceTimer?.cancel();
    _previewDebounceTimer = Timer(
      const Duration(milliseconds: 110),
      () => _queueTimelinePreviewLoad(seconds, bucket),
    );
  }

  void _hideTimelinePreview() {
    _previewDebounceTimer?.cancel();
    _previewRequestSerial++;
    _pendingPreviewSeconds = null;
    _pendingPreviewBucket = null;
    if (_timelineHovering) {
      setState(() => _timelineHovering = false);
    }
    _previewIdleDisposeTimer?.cancel();
    _previewIdleDisposeTimer = Timer(const Duration(milliseconds: 700), () {
      final preview = _previewPlayer;
      _previewPlayer = null;
      _previewVideoController = null;
      _previewMediaPath = null;
      _previewLoadInFlight = false;
      if (preview != null) {
        unawaited(preview.dispose());
        _playbackLog('PREVIEW_PLAYER_DISPOSED idle');
      }
    });
  }

  void _queueTimelinePreviewLoad(double seconds, int bucket) {
    if (_previewLoadInFlight) {
      _pendingPreviewSeconds = seconds;
      _pendingPreviewBucket = bucket;
      return;
    }
    unawaited(_loadTimelinePreview(seconds, bucket));
  }

  Future<void> _loadTimelinePreview(double seconds, int bucket) async {
    if (!mounted || !widget.controller.timelinePreview) return;
    if (_previewLoadInFlight) {
      _pendingPreviewSeconds = seconds;
      _pendingPreviewBucket = bucket;
      return;
    }
    _previewLoadInFlight = true;

    final previewClock = Stopwatch()..start();
    final request = ++_previewRequestSerial;
    _playbackLog(
      'PREVIEW_BEGIN request=$request target=${seconds.toStringAsFixed(2)}s '
      'bucket=$bucket cache=${_previewCache.length}',
    );

    try {
      if (_previewPlayer == null) {
        final preview = Player();
        _previewPlayer = preview;
        _previewVideoController = VideoController(preview);
        _playbackLog('PREVIEW_PLAYER_CREATED request=$request');

        if (mounted) {
          setState(() {});
          // Let the hidden Video widget attach its native video surface before
          // opening media & requesting screenshots.
          await WidgetsBinding.instance.endOfFrame;
        }
      }

      final preview = _previewPlayer!;

      if (_previewMediaPath != currentMovie.fullPath) {
        _previewCache.clear();
        _previewFrame = null;
        _previewFailed = false;

        await preview.setVolume(0);
        await preview.open(
          Media(Uri.file(currentMovie.fullPath).toString()),
          play: false,
        );
        _previewMediaPath = currentMovie.fullPath;
        _playbackLog(
          'PREVIEW_MEDIA_OPEN elapsed=${previewClock.elapsedMilliseconds}ms '
          'request=$request',
        );

        // Wait until the decoder has actual media metadata before seeking.
        try {
          await preview.stream.duration
              .firstWhere((value) => value > Duration.zero)
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // Some files report duration through state before the stream emits.
        }
      }

      await preview.seek(Duration(seconds: bucket));

      // Give mpv time to decode the target frame after an exact seek.
      await Future<void>.delayed(const Duration(milliseconds: 90));

      Uint8List? frame = await preview.screenshot(
        format: 'image/jpeg',
      );

      // Some codecs need one extra decode cycle after seeking.
      if (frame == null || frame.isEmpty) {
        await preview.play();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await preview.pause();
        frame = await preview.screenshot(
          format: 'image/jpeg',
        );
      }

      if (!mounted || request != _previewRequestSerial) return;

      if (frame == null || frame.isEmpty) {
        setState(() => _previewFailed = true);
        return;
      }

      if (_previewCache.length >= 32) {
        _previewCache.remove(_previewCache.keys.first);
      }
      _previewCache[bucket] = frame;
      _playbackLog(
        'PREVIEW_READY request=$request bucket=$bucket '
        'elapsed=${previewClock.elapsedMilliseconds}ms '
        'bytes=${frame.length} cache=${_previewCache.length}',
      );

      if (_timelineHovering) {
        setState(() {
          _previewFrame = frame;
          _previewFailed = false;
        });
      }
    } catch (error, stackTrace) {
      _playbackLog(
        'PREVIEW_ERROR request=$request '
        'elapsed=${previewClock.elapsedMilliseconds}ms error=$error',
      );
      debugPrint('[SyncWatch][PLAYBACK] PREVIEW_STACK $stackTrace');
      if (mounted && request == _previewRequestSerial) {
        setState(() => _previewFailed = true);
      }
    } finally {
      _previewLoadInFlight = false;
      final pendingSeconds = _pendingPreviewSeconds;
      final pendingBucket = _pendingPreviewBucket;
      _pendingPreviewSeconds = null;
      _pendingPreviewBucket = null;
      if (mounted &&
          _timelineHovering &&
          pendingSeconds != null &&
          pendingBucket != null) {
        _queueTimelinePreviewLoad(pendingSeconds, pendingBucket);
      }
    }
  }

  Widget _timelinePreviewOverlay(BuildContext context) {
    const previewWidth = 192.0;
    const previewHeight = 108.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final centerX = _previewGlobalX ?? screenWidth / 2;
    final left = (centerX - previewWidth / 2)
        .clamp(8.0, screenWidth - previewWidth - 8)
        .toDouble();

    return Positioned(
      left: left,
      bottom: isFullscreen ? 78 : 76,
      width: previewWidth,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF0101C29),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: syncBorder),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 14),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: _previewFrame != null
                      ? Image.memory(
                          _previewFrame!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : _previewFailed
                          ? const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 22,
                                color: Colors.white54,
                              ),
                            )
                          : const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.black38,
                  child: Text(
                    _formatSeconds(_previewSeconds ?? 0),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final sliderMax = durationSeconds > 0 ? durationSeconds : 1.0;
    final sliderValue = positionSeconds.clamp(0.0, sliderMax).toDouble();

    return Container(
      height: 70,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      color: _playerChrome.withValues(alpha: 0.98),
      child: Column(
        children: [
          Row(
            children: [
              Text(_formatSeconds(positionSeconds)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onHover: durationSeconds <= 0
                          ? null
                          : (event) => _onTimelineHover(
                                event,
                                constraints.maxWidth,
                              ),
                      onExit: (_) => _hideTimelinePreview(),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                        ),
                        child: Slider(
                          value: sliderValue,
                          max: sliderMax,
                          onChanged: durationSeconds <= 0
                              ? null
                              : (value) =>
                                  setState(() => positionSeconds = value),
                          onChangeEnd: durationSeconds <= 0
                              ? null
                              : (value) => _seekAbsolute(value),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text(_formatSeconds(durationSeconds)),
            ],
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _menuIconButton(
                          key: playerSettingsButtonKey,
                          icon: Icons.settings_suggest_rounded,
                          tooltip: widget.controller.t('playerSettings'),
                          onPressed: _showPlayerSettings,
                        ),
                        const SizedBox(width: 8),
                        _menuIconButton(
                          key: playlistButtonKey,
                          icon: Icons.playlist_play_rounded,
                          tooltip: widget.controller.t('playlist'),
                          onPressed: _showPlaylistMenu,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _fileControl(
                      tooltip: widget.controller.t('previousFile'),
                      icon: Icons.skip_previous_rounded,
                      onPressed: _sharedNeighborIndex(-1) != null
                          ? () => _switchToIndex(_sharedNeighborIndex(-1)!)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    _roundControl(
                      icon: Icons.fast_rewind_rounded,
                      onPressed: () => _skip(-widget.controller.skipSeconds),
                    ),
                    const SizedBox(width: 8),
                    _roundControl(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: _togglePlayback,
                      prominent: true,
                    ),
                    const SizedBox(width: 8),
                    _roundControl(
                      icon: Icons.fast_forward_rounded,
                      onPressed: () => _skip(widget.controller.skipSeconds),
                    ),
                    const SizedBox(width: 14),
                    _fileControl(
                      tooltip: widget.controller.t('nextFile'),
                      icon: Icons.skip_next_rounded,
                      onPressed: _sharedNeighborIndex(1) != null
                          ? () => _switchToIndex(_sharedNeighborIndex(1)!)
                          : null,
                    ),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (currentMovie.subtitleTracks == 0 &&
                            subtitleTracks
                                .where((track) => track.id != 'no')
                                .isEmpty)
                          _menuIconButton(
                            icon: Icons.subtitles_off_rounded,
                            tooltip: widget.controller.t('noSubtitles'),
                            onPressed: null,
                          )
                        else
                          _menuIconButton(
                            key: subtitleButtonKey,
                            icon: Icons.closed_caption_rounded,
                            tooltip: widget.controller.t('subtitles'),
                            onPressed: _showSubtitleMenu,
                          ),
                        const SizedBox(width: 8),
                        _menuIconButton(
                          key: audioTrackButtonKey,
                          icon: Icons.queue_music_rounded,
                          tooltip: widget.controller.t('audioTracks'),
                          onPressed: _showAudioTrackMenu,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: volumeButtonKey,
                          tooltip: widget.controller.t('audio'),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _showAudioPopover,
                          icon: Icon(
                            movieMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuIconButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: key,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
      ),
    );
  }

  Widget _fileControl({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: _isLight ? syncAccent : null,
          disabledForegroundColor: _isLight
              ? syncLightTextSecondary.withValues(alpha: 0.42)
              : null,
          backgroundColor: _isLight
              ? syncLightBackgroundDeep
              : null,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _roundControl({
    required IconData icon,
    required VoidCallback onPressed,
    bool prominent = false,
  }) {
    return SizedBox(
      width: prominent ? 46 : 38,
      height: prominent ? 46 : 38,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: prominent
              ? syncAccent
              : syncAccent.withValues(alpha: _isLight ? 0.10 : 0.17),
          foregroundColor: prominent
              ? Colors.white
              : (_isLight ? syncAccent : Colors.white),
          side: const BorderSide(color: syncAccent),
          shape: const CircleBorder(),
        ),
        child: Icon(icon, size: prominent ? 26 : 21),
      ),
    );
  }

  Widget _volumeIndicator() {
    final percent = ((volumeOsd ?? 0) * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _playerSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _playerBorder),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.volume_up_rounded),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: volumeOsd,
                minHeight: 5,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 10),
            Text('$percent%'),
          ],
        ),
      ),
    );
  }

  Future<int?> _showAnchoredSelectionMenu({
    required GlobalKey anchorKey,
    required List<String> items,
    required int selectedIndex,
    double width = 360,
    double maxHeight = 280,
  }) async {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    Rect? rectFor(GlobalKey key) {
      final keyContext = key.currentContext;
      if (keyContext == null) return null;
      final renderObject = keyContext.findRenderObject();
      if (renderObject is! RenderBox) return null;
      final offset =
          renderObject.localToGlobal(Offset.zero, ancestor: overlayBox);
      return offset & renderObject.size;
    }

    final anchorRect = rectFor(anchorKey);
    if (anchorRect == null || items.isEmpty) return null;

    final settingsRect = rectFor(playerSettingsButtonKey);
    final playlistRect = rectFor(playlistButtonKey);
    final subtitleRect = rectFor(subtitleButtonKey);
    final audioRect = rectFor(audioTrackButtonKey);
    final volumeRect = rectFor(volumeButtonKey);

    const switchPlaylist = -1001;
    const switchSubtitles = -1002;
    const switchAudio = -1003;
    const switchVolume = -1004;
    const switchSettings = -1005;
    const rowHeight = 34.0;

    final menuHeight =
        (items.length * rowHeight + 8).clamp(48.0, maxHeight).toDouble();
    final maxLeft = (overlayBox.size.width - width - 8)
        .clamp(8.0, double.infinity)
        .toDouble();
    final left =
        (anchorRect.center.dx - width / 2).clamp(8.0, maxLeft).toDouble();
    final top =
        (anchorRect.top - menuHeight - 10).clamp(8.0, double.infinity).toDouble();

    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'player-popup',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 80),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        Widget switchTarget(Rect? rect, int code) {
          if (rect == null) return const SizedBox.shrink();
          return Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(dialogContext).pop(code),
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final delta = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
              unawaited(_changeMovieVolume(delta));
            }
          },
          child: Stack(
            children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: menuHeight,
              child: Material(
                elevation: 14,
                color: _playerSurface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final selected = index == selectedIndex;
                    return InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(index),
                      child: Container(
                        height: rowHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        color: selected
                            ? syncAccent.withValues(alpha: 0.10)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              child: selected
                                  ? const Icon(
                                      Icons.circle,
                                      size: 7,
                                      color: syncAccentSoft,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Tooltip(
                                message: items[index],
                                waitDuration:
                                    const Duration(milliseconds: 350),
                                child: Text(
                                  items[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                    fontSize: 12.5,
                    color: _playerPrimary,
                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (anchorKey != playlistButtonKey)
              switchTarget(playlistRect, switchPlaylist),
            if (anchorKey != subtitleButtonKey)
              switchTarget(subtitleRect, switchSubtitles),
            if (anchorKey != audioTrackButtonKey)
              switchTarget(audioRect, switchAudio),
            if (anchorKey != volumeButtonKey)
              switchTarget(volumeRect, switchVolume),
            switchTarget(settingsRect, switchSettings),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPlaylistMenu() async {
    final labels = [
      for (final movie in widget.playlist) movie.fileName,
    ];
    final selected = await _showAnchoredSelectionMenu(
      anchorKey: playlistButtonKey,
      items: labels,
      selectedIndex: currentIndex,
      width: 340,
      maxHeight: 300,
    );

    if (selected == -1005) {
      await _showPlayerSettings();
      return;
    }
    if (selected == -1002) {
      await _showSubtitleMenu();
      return;
    }
    if (selected == -1003) {
      await _showAudioTrackMenu();
      return;
    }
    if (selected == -1004) {
      await _showAudioPopover();
      return;
    }
    if (selected != null && selected >= 0) {
      await _switchToIndex(selected);
    }
  }

  Future<void> _showAudioTrackMenu() async {
    if (audioTracks.isEmpty) return;
    final labels = [
      for (final track in audioTracks) _audioLabel(track),
    ];
    final selectedIndex = audioTracks.indexWhere(
      (track) => track.id == currentAudioTrack?.id,
    );
    final selected = await _showAnchoredSelectionMenu(
      anchorKey: audioTrackButtonKey,
      items: labels,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      width: 300,
      maxHeight: 260,
    );

    if (selected == -1005) {
      await _showPlayerSettings();
      return;
    }
    if (selected == -1001) {
      await _showPlaylistMenu();
      return;
    }
    if (selected == -1002) {
      await _showSubtitleMenu();
      return;
    }
    if (selected == -1004) {
      await _showAudioPopover();
      return;
    }
    if (selected != null && selected >= 0) {
      await player.setAudioTrack(audioTracks[selected]);
    }
  }

  Future<void> _showSubtitleMenu() async {
    final tracks = <SubtitleTrack>[
      SubtitleTrack.no(),
      ...subtitleTracks.where((track) => track.id != 'no'),
    ];
    final labels = [
      for (final track in tracks) _subtitleLabel(track),
    ];
    final selectedIndex = tracks.indexWhere(
      (track) => track.id == currentSubtitleTrack?.id,
    );
    final selected = await _showAnchoredSelectionMenu(
      anchorKey: subtitleButtonKey,
      items: labels,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      width: 240,
      maxHeight: 220,
    );

    if (selected == -1005) {
      await _showPlayerSettings();
      return;
    }
    if (selected == -1001) {
      await _showPlaylistMenu();
      return;
    }
    if (selected == -1003) {
      await _showAudioTrackMenu();
      return;
    }
    if (selected == -1004) {
      await _showAudioPopover();
      return;
    }
    if (selected != null && selected >= 0) {
      await player.setSubtitleTrack(tracks[selected]);
    }
  }

  Future<void> _switchToIndex(int index) async {
    if (widget.playlist.isEmpty ||
        index < 0 ||
        index >= widget.playlist.length ||
        index == currentIndex) {
      return;
    }

    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      positionSeconds,
      persist: true,
    );

    final nextMovie = widget.playlist[index];
    setState(() {
      currentIndex = index;
      currentMovie = nextMovie;
      positionSeconds = 0;
      durationSeconds = 0;
      audioTracks = const [];
      subtitleTracks = const [];
      currentAudioTrack = null;
      currentSubtitleTrack = null;
    });

    widget.onMovieChanged?.call(nextMovie);

    await _openMedia();
  }

  Future<void> _togglePlayback() async {
    await player.playOrPause();
    if (_applyingRemoteCommand) return;
    if (player.state.playing) {
      await widget.syncEngine.play();
    } else {
      await widget.syncEngine.pause();
    }
  }

  Future<void> _skip(int deltaSeconds) async {
    final base = _queuedSeekTarget ?? positionSeconds;
    _queueSeek(base + deltaSeconds);
  }

  Future<void> _seekAbsolute(double targetSeconds) async {
    _queueSeek(targetSeconds, immediate: true);
  }

  void _queueSeek(
    double targetSeconds, {
    bool immediate = false,
  }) {
    final max = durationSeconds > 0 ? durationSeconds : 0.0;
    final target = targetSeconds.clamp(0.0, max).toDouble();

    _queuedSeekTarget = target;
    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      target,
    );

    if (mounted) {
      setState(() => positionSeconds = target);
    }

    _seekDebounceTimer?.cancel();

    if (immediate) {
      unawaited(_flushQueuedSeek());
      return;
    }

    _seekDebounceTimer = Timer(
      const Duration(milliseconds: 90),
      () => unawaited(_flushQueuedSeek()),
    );
  }

  Future<void> _flushQueuedSeek() async {
    if (_seekInFlight) return;

    final target = _queuedSeekTarget;
    if (target == null) return;

    _seekInFlight = true;
    final duration = Duration(milliseconds: (target * 1000).round());

    try {
      await player.seek(duration);
      if (!_applyingRemoteCommand) {
        await widget.syncEngine.seekTo(duration);
      }
    } finally {
      _seekInFlight = false;

      if (_queuedSeekTarget == target) {
        _queuedSeekTarget = null;
      }

      if (_queuedSeekTarget != null) {
        _seekDebounceTimer?.cancel();
        _seekDebounceTimer = Timer(
          const Duration(milliseconds: 35),
          () => unawaited(_flushQueuedSeek()),
        );
      }
    }
  }

  Future<void> _changeMovieVolume(double delta) async {
    final value = (widget.controller.movieVolume + delta).clamp(0.0, 1.0);
    widget.controller.setMovieVolume(value);
    await _setEffectiveMovieVolume();

    _volumeOsdTimer?.cancel();
    if (mounted) {
      setState(() => volumeOsd = value);
    }
    _volumeOsdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => volumeOsd = null);
    });
  }

  Future<void> _returnToHome() async {
    final stateSeconds =
        player.state.position.inMilliseconds / 1000.0;
    final resumeSeconds =
        stateSeconds > 0 ? stateSeconds : positionSeconds;

    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      resumeSeconds,
      persist: true,
    );

    _resumeFullscreenWhenActivated = isFullscreen;

    // Switch to the library before changing the native window mode, so the
    // fullscreen -> windowed transition happens behind the library view.
    if (widget.onReturnHome != null) {
      await widget.onReturnHome!.call();
    }

    if (isFullscreen) {
      await _setPlayerFullscreen(false);
    }

    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );

    if (!mounted) return;

    if (widget.onReturnHome != null) {
      _playerFocusNode.unfocus();
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _toggleFullscreen() async {
    await _setPlayerFullscreen(!isFullscreen);
  }

  Future<void> _setPlayerFullscreen(bool enabled) async {
    if (_fullscreenTransition || enabled == isFullscreen) return;

    _fullscreenTransition = true;

    try {
      if (enabled) {
        // A maximized Windows window is constrained to the work area and may
        // leave the taskbar visible. Normalize it before entering real
        // fullscreen.
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }

        await windowManager.setFullScreen(true);

        if (!mounted) return;
        setState(() {
          isFullscreen = true;
          // Fullscreen chrome has one state: both bars are either visible or
          // hidden. Do not infer visibility from the pointer coordinates from
          // the pre-fullscreen window.
          topControlsVisible = false;
          bottomControlsVisible = false;
        });
      } else {
        await windowManager.setFullScreen(false);

        if (!mounted) return;
        setState(() {
          isFullscreen = false;
          topControlsVisible = true;
          bottomControlsVisible = true;
        });
      }
    } finally {
      _fullscreenTransition = false;
    }
  }

  @override
  void onWindowRestore() {
    if (!widget.active || !_restoreFullscreenAfterMinimize) return;
    _restoreFullscreenAfterMinimize = false;
    unawaited(_setPlayerFullscreen(true));
  }

  @override
  void onWindowMaximize() {
    if (_fullscreenTransition || isFullscreen) return;
    unawaited(_promoteMaximizeToFullscreen());
  }

  Future<void> _promoteMaximizeToFullscreen() async {
    if (_fullscreenTransition || isFullscreen) return;

    // The native Windows maximize button expands only to the work area and
    // leaves the taskbar visible. Treat it as fullscreen intent in the player.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    if (await windowManager.isMaximized()) {
      await _setPlayerFullscreen(true);
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final audio = player.state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList();
    final subtitles = <SubtitleTrack>[
      SubtitleTrack.no(),
      ...player.state.tracks.subtitle.where(
        (track) => track.id != 'auto' && track.id != 'no',
      ),
    ];

    const mainWidth = 190.0;
    const submenuWidth = 250.0;
    const rowHeight = 30.0;
    const gap = 4.0;

    final mainLeft = globalPosition.dx
        .clamp(8.0, overlay.size.width - mainWidth - 8)
        .toDouble();
    final mainTop = globalPosition.dy
        .clamp(8.0, overlay.size.height - 260)
        .toDouble();

    final openSubmenuRight =
        mainLeft + mainWidth + gap + submenuWidth <= overlay.size.width - 8;
    final submenuLeft = openSubmenuRight
        ? mainLeft + mainWidth + gap
        : (mainLeft - submenuWidth - gap).clamp(8.0, double.infinity).toDouble();

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'context-menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 80),
      pageBuilder: (context, animation, secondaryAnimation) {
        String? submenu;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<({String label, String value, bool selected})> submenuItems() {
              if (submenu == 'playlist') {
                return [
                  for (var i = 0; i < widget.playlist.length; i++)
                    (
                      label: widget.playlist[i].fileName,
                      value: 'playlist:$i',
                      selected: i == currentIndex,
                    ),
                ];
              }

              if (submenu == 'audio') {
                if (audio.isEmpty) {
                  return [
                    (
                      label: widget.controller.t('noAudioTracks'),
                      value: '',
                      selected: false,
                    ),
                  ];
                }
                return [
                  for (final track in audio)
                    (
                      label: _audioLabel(track),
                      value: 'audio:${track.id}',
                      selected: track.id == currentAudioTrack?.id,
                    ),
                ];
              }

              if (submenu == 'subtitles') {
                return [
                  for (final track in subtitles)
                    (
                      label: _subtitleLabel(track),
                      value: 'subtitle:${track.id}',
                      selected: track.id == currentSubtitleTrack?.id,
                    ),
                ];
              }

              if (submenu == 'open') {
                return [
                  (
                    label: widget.controller.t('openAudioTrack'),
                    value: 'open:audio',
                    selected: false,
                  ),
                  (
                    label: widget.controller.t('openSubtitles'),
                    value: 'open:subtitle',
                    selected: false,
                  ),
                ];
              }

              return const [];
            }

            final subItems = submenuItems();
            final submenuHeight =
                (subItems.length * rowHeight + 6).clamp(36.0, 260.0).toDouble();

            return Stack(
              children: [
                Positioned(
                  left: mainLeft,
                  top: mainTop,
                  width: mainWidth,
                  child: Material(
                    elevation: 14,
                    color: _playerSurface,
                    borderRadius: BorderRadius.circular(9),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _contextMenuRow(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: playing
                              ? widget.controller.t('pause')
                              : widget.controller.t('play'),
                          onTap: () => Navigator.of(context).pop('play'),
                        ),
                        _contextMenuRow(
                          icon: Icons.folder_open_rounded,
                          label: widget.controller.t('open'),
                          hasSubmenu: true,
                          onHover: () => setDialogState(
                            () => submenu = 'open',
                          ),
                          onTap: () => setDialogState(
                            () => submenu = 'open',
                          ),
                        ),
                        const Divider(height: 1),
                        _contextMenuRow(
                          icon: Icons.playlist_play_rounded,
                          label: widget.controller.t('playlist'),
                          hasSubmenu: true,
                          onHover: () => setDialogState(
                            () => submenu = 'playlist',
                          ),
                          onTap: () => setDialogState(
                            () => submenu = 'playlist',
                          ),
                        ),
                        _contextMenuRow(
                          icon: Icons.graphic_eq_rounded,
                          label: widget.controller.t('audioTracks'),
                          hasSubmenu: true,
                          onHover: () => setDialogState(
                            () => submenu = 'audio',
                          ),
                          onTap: () => setDialogState(
                            () => submenu = 'audio',
                          ),
                        ),
                        _contextMenuRow(
                          icon: Icons.subtitles_rounded,
                          label: widget.controller.t('subtitles'),
                          hasSubmenu: true,
                          onHover: () => setDialogState(
                            () => submenu = 'subtitles',
                          ),
                          onTap: () => setDialogState(
                            () => submenu = 'subtitles',
                          ),
                        ),
                        const Divider(height: 1),
                        _contextMenuRow(
                          icon: Icons.settings_rounded,
                          label: widget.controller.t('settings'),
                          onTap: () => Navigator.of(context).pop('settings'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (submenu != null)
                  Positioned(
                    left: submenuLeft,
                    top: mainTop + 60,
                    width: submenuWidth,
                    height: submenuHeight,
                    child: Material(
                      elevation: 16,
                      color: _playerSurface,
                      borderRadius: BorderRadius.circular(9),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        itemCount: subItems.length,
                        itemBuilder: (context, index) {
                          final item = subItems[index];
                          final enabled = item.value.isNotEmpty;

                          return InkWell(
                            onTap: enabled
                                ? () => Navigator.of(context).pop(item.value)
                                : null,
                            child: SizedBox(
                              height: rowHeight,
                              child: Row(
                                children: [
                                  const SizedBox(width: 7),
                                  SizedBox(
                                    width: 9,
                                    child: item.selected
                                        ? const Icon(
                                            Icons.circle,
                                            size: 6,
                                            color: syncAccentSoft,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Tooltip(
                                      message: item.label,
                                      waitDuration:
                                          const Duration(milliseconds: 350),
                                      child: Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: enabled
                                              ? _playerPrimary
                                              : _playerSecondary.withValues(alpha: 0.55),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    if (result == 'play') {
      await _togglePlayback();
      return;
    }
    if (result == 'mute') {
      movieMuted = !movieMuted;
      await _setEffectiveMovieVolume();
      if (mounted) setState(() {});
      return;
    }
    if (result == 'timeline-preview') {
      widget.controller.setTimelinePreview(
        !widget.controller.timelinePreview,
      );
      return;
    }
    if (result == 'fullscreen') {
      await _toggleFullscreen();
      return;
    }
    if (result == 'settings') {
      await _showPlayerSettings();
      return;
    }
    if (result == 'open:audio') {
      await _openExternalAudioTrack();
      return;
    }
    if (result == 'open:subtitle') {
      await _openExternalSubtitleTrack();
      return;
    }
    if (result.startsWith('playlist:')) {
      final index = int.tryParse(result.substring('playlist:'.length));
      if (index != null) await _switchToIndex(index);
      return;
    }
    if (result.startsWith('audio:')) {
      final id = result.substring('audio:'.length);
      final match = audio.where((track) => track.id == id);
      if (match.isNotEmpty) await player.setAudioTrack(match.first);
      return;
    }
    if (result.startsWith('subtitle:')) {
      final id = result.substring('subtitle:'.length);
      if (id == 'no') {
        await player.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      final match = subtitles.where((track) => track.id == id);
      if (match.isNotEmpty) await player.setSubtitleTrack(match.first);
    }
  }

  Future<void> _openExternalAudioTrack() async {
    const typeGroup = XTypeGroup(
      label: 'Audio',
      extensions: <String>[
        'aac',
        'ac3',
        'dts',
        'eac3',
        'flac',
        'm4a',
        'mka',
        'mp3',
        'ogg',
        'opus',
        'wav',
      ],
    );

    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (file == null) return;

    final title = _fileNameFromPath(file.path);
    await player.setAudioTrack(
      AudioTrack.uri(
        Uri.file(file.path).toString(),
        title: title,
      ),
    );
  }

  Future<void> _openExternalSubtitleTrack() async {
    const typeGroup = XTypeGroup(
      label: 'Subtitles',
      extensions: <String>[
        'ass',
        'srt',
        'ssa',
        'sub',
        'vtt',
      ],
    );

    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (file == null) return;

    final title = _fileNameFromPath(file.path);
    await player.setSubtitleTrack(
      SubtitleTrack.uri(
        Uri.file(file.path).toString(),
        title: title,
      ),
    );
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  Widget _contextMenuRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onHover,
    bool hasSubmenu = false,
    bool selected = false,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover?.call(),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              const SizedBox(width: 6),
              SizedBox(
                width: 8,
                child: selected
                    ? const Icon(
                        Icons.circle,
                        size: 6,
                        color: syncAccentSoft,
                      )
                    : null,
              ),
              const SizedBox(width: 2),
              Icon(icon, size: 15, color: _playerSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (hasSubmenu)
                Icon(
                  Icons.arrow_right_rounded,
                  size: 16,
                  color: _playerSecondary,
                ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAudioPopover() async {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    Rect? rectFor(GlobalKey key) {
      final keyContext = key.currentContext;
      if (keyContext == null) return null;
      final renderObject = keyContext.findRenderObject();
      if (renderObject is! RenderBox) return null;
      final offset =
          renderObject.localToGlobal(Offset.zero, ancestor: overlayBox);
      return offset & renderObject.size;
    }

    final anchorRect = rectFor(volumeButtonKey);
    if (anchorRect == null) return;

    final settingsRect = rectFor(playerSettingsButtonKey);
    final playlistRect = rectFor(playlistButtonKey);
    final subtitleRect = rectFor(subtitleButtonKey);
    final audioRect = rectFor(audioTrackButtonKey);

    const switchSettings = -1005;
    const switchPlaylist = -1001;
    const switchSubtitles = -1002;
    const switchAudio = -1003;
    const width = 310.0;
    const height = 92.0;

    final maxLeft = (overlayBox.size.width - width - 8)
        .clamp(8.0, double.infinity)
        .toDouble();
    final left =
        (anchorRect.center.dx - width / 2).clamp(8.0, maxLeft).toDouble();
    final top =
        (anchorRect.top - height - 10).clamp(8.0, double.infinity).toDouble();

    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'volume-popup',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 80),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        Widget switchTarget(Rect? rect, int code) {
          if (rect == null) return const SizedBox.shrink();
          return Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(dialogContext).pop(code),
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final delta = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
              unawaited(_changeMovieVolume(delta));
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: width,
                child: Material(
                  elevation: 14,
                  color: _playerSurface,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: AnimatedBuilder(
                      animation: widget.controller,
                      builder: (context, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _volumeRow(
                              label: widget.controller.t('movieVolume'),
                              value: widget.controller.movieVolume,
                              muted: movieMuted,
                              onMute: () async {
                                setState(() => movieMuted = !movieMuted);
                                await _setEffectiveMovieVolume();
                              },
                              onChanged: (value) async {
                                widget.controller.setMovieVolume(value);
                                await _setEffectiveMovieVolume();
                              },
                            ),
                            const SizedBox(height: 2),
                            _volumeRow(
                              label: widget.controller.t('callVolume'),
                              value: widget.controller.callVolume,
                              muted: callMuted,
                              onMute: () =>
                                  setState(() => callMuted = !callMuted),
                              onChanged: widget.controller.setCallVolume,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              switchTarget(settingsRect, switchSettings),
              switchTarget(playlistRect, switchPlaylist),
              switchTarget(subtitleRect, switchSubtitles),
              switchTarget(audioRect, switchAudio),
            ],
          ),
        );
      },
    );

    if (result == switchSettings) {
      await _showPlayerSettings();
      return;
    }
    if (result == switchPlaylist) {
      await _showPlaylistMenu();
      return;
    }
    if (result == switchSubtitles) {
      await _showSubtitleMenu();
      return;
    }
    if (result == switchAudio) {
      await _showAudioTrackMenu();
    }
  }

  Widget _volumeRow({
    required String label,
    required double value,
    required bool muted,
    required FutureOr<void> Function() onMute,
    required FutureOr<void> Function(double) onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          padding: EdgeInsets.zero,
          onPressed: () => onMute(),
          icon: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            size: 18,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 5,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 9,
              ),
            ),
            child: Slider(
              value: value,
              onChanged: (newValue) => onChanged(newValue),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  String _audioLabel(AudioTrack track) {
    final parts = <String>[];
    if (track.title != null && track.title!.trim().isNotEmpty) {
      parts.add(track.title!.trim());
    }
    if (track.language != null && track.language!.trim().isNotEmpty) {
      parts.add(track.language!.toUpperCase());
    }
    if (track.codec != null && track.codec!.trim().isNotEmpty) {
      parts.add(track.codec!.toUpperCase());
    }
    if (track.channels != null && track.channels!.trim().isNotEmpty) {
      parts.add(track.channels!);
    }
    if (parts.isEmpty) {
      return '${widget.controller.t('audioTrack')} ${track.id}';
    }
    return parts.join(' · ');
  }

  String _subtitleLabel(SubtitleTrack track) {
    if (track.id == 'no') return widget.controller.t('noSubtitles');

    final parts = <String>[];
    if (track.title != null && track.title!.trim().isNotEmpty) {
      parts.add(track.title!.trim());
    }
    if (track.language != null && track.language!.trim().isNotEmpty) {
      parts.add(track.language!.toUpperCase());
    }
    if (track.codec != null && track.codec!.trim().isNotEmpty) {
      parts.add(track.codec!.toUpperCase());
    }
    if (parts.isEmpty) {
      return '${widget.controller.t('subtitleTrack')} ${track.id}';
    }
    return parts.join(' · ');
  }

  String _formatSeconds(double value) {
    final total = value.round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
