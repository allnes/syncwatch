import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../core/app_theme.dart';
import '../models/movie_item.dart';
import '../services/sync_engine.dart';
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
  });

  final AppController controller;
  final MovieItem movie;
  final SyncEngine syncEngine;
  final String initialAudioTrack;
  final String initialSubtitleTrack;
  final List<MovieItem> playlist;
  final int initialIndex;
  final Future<void> Function()? onShowCall;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  late final Player player;
  late final VideoController videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _volumeOsdTimer;

  bool playing = false;
  bool movieMuted = false;
  bool callMuted = false;
  bool isFullscreen = false;
  bool topControlsVisible = true;
  bool bottomControlsVisible = true;
  bool nativeTitleBarVisibleInFullscreen = false;
  late int currentIndex;
  late MovieItem currentMovie;

  double positionSeconds = 0;
  double durationSeconds = 0;
  double? volumeOsd;

  List<AudioTrack> audioTracks = const [];
  List<SubtitleTrack> subtitleTracks = const [];
  AudioTrack? currentAudioTrack;
  SubtitleTrack? currentSubtitleTrack;

  final GlobalKey playlistButtonKey = GlobalKey();
  final GlobalKey audioTrackButtonKey = GlobalKey();
  final GlobalKey subtitleButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    currentIndex = widget.initialIndex < 0 ? 0 : widget.initialIndex;
    currentMovie = widget.playlist.isEmpty
        ? widget.movie
        : widget.playlist[
            currentIndex.clamp(0, widget.playlist.length - 1).toInt()
          ];

    player = Player();
    videoController = VideoController(player);

    _subscriptions.add(
      player.stream.position.listen((position) {
        if (!mounted) return;
        final seconds = position.inMilliseconds / 1000.0;
        widget.controller.updatePlaybackPosition(
          currentMovie.fullPath,
          seconds,
        );
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

    _openMedia();
    widget.syncEngine.connect();
    if (widget.controller.autoReady) {
      widget.syncEngine.setReady(true);
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

  Future<void> _openMedia() async {
    final resumePosition =
        widget.controller.playbackPositionFor(currentMovie.fullPath);

    await player.setVolume(widget.controller.movieVolume * 100.0);
    await player.open(
      Media(Uri.file(currentMovie.fullPath).toString()),
      play: false,
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
    if (isFullscreen) {
      unawaited(
        windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
          windowButtonVisibility: true,
        ),
      );
    }
    _volumeOsdTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    widget.controller.updatePlaybackPosition(
      currentMovie.fullPath,
      positionSeconds,
      persist: true,
    );
    widget.syncEngine.dispose();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: syncBackgroundDeep,
          body: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final delta = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
                _changeMovieVolume(delta);
              }
            },
            child: MouseRegion(
              onHover: (event) {
                if (isFullscreen &&
                    nativeTitleBarVisibleInFullscreen &&
                    event.localPosition.dy > 90) {
                  _hideFullscreenTopChrome();
                }
              },
              child: Stack(
              children: [
                Positioned.fill(child: _movieSurface(context)),

                if (isFullscreen)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 90,
                    child: MouseRegion(
                      onEnter: (_) => _showFullscreenTopChrome(),
                      child: topControlsVisible
                          ? _topBar(context)
                          : const SizedBox.expand(),
                    ),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _topBar(context),
                  ),

                if (isFullscreen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 140,
                    child: MouseRegion(
                      onEnter: (_) {
                        if (!bottomControlsVisible) {
                          setState(() => bottomControlsVisible = true);
                        }
                      },
                      onExit: (_) {
                        if (bottomControlsVisible) {
                          setState(() => bottomControlsVisible = false);
                        }
                      },
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

                if (volumeOsd != null)
                  Positioned(
                    right: 32,
                    top: isFullscreen && !topControlsVisible ? 28 : 96,
                    child: _volumeIndicator(),
                  ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Widget _movieSurface(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: isFullscreen ? 0 : 68,
        bottom: isFullscreen ? 0 : 118,
      ),
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _toggleFullscreen,
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: videoController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            ),
            if (!isFullscreen || topControlsVisible)
              Positioned(
                left: 24,
                top: isFullscreen ? 82 : 18,
                right: 24,
                child: IgnorePointer(
                  child: Text(
                    currentMovie.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: syncBackgroundDeep.withValues(alpha: 0.98),
      child: Row(
        children: [
          IconButton(
            tooltip: widget.controller.t('back'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 6),
          const Text(
            'SyncWatch',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 20),
          const VerticalDivider(indent: 16, endIndent: 16),
          const SizedBox(width: 12),
          const Icon(Icons.groups_2_rounded, color: syncAccentSoft),
          const SizedBox(width: 8),
          Text(widget.controller.roomName),
          const Spacer(),
          const Icon(Icons.circle, size: 9, color: syncSuccess),
          const SizedBox(width: 6),
          Text('2/2 ${widget.controller.t('ready')}'),
          const SizedBox(width: 16),
          if (widget.onShowCall != null)
            IconButton(
              tooltip: widget.controller.t('goToCall'),
              onPressed: () => widget.onShowCall?.call(),
              icon: const Icon(Icons.videocam_rounded),
            ),
          IconButton(
            tooltip: widget.controller.t('settings'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.56),
              builder: (_) => SettingsScreen(controller: widget.controller),
            ),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final sliderMax = durationSeconds > 0 ? durationSeconds : 1.0;
    final sliderValue = positionSeconds.clamp(0.0, sliderMax).toDouble();

    return Container(
      height: 118,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
      color: syncBackgroundDeep.withValues(alpha: 0.98),
      child: Column(
        children: [
          Row(
            children: [
              Text(_formatSeconds(positionSeconds)),
              Expanded(
                child: Slider(
                  value: sliderValue,
                  max: sliderMax,
                  onChanged: durationSeconds <= 0
                      ? null
                      : (value) => setState(() => positionSeconds = value),
                  onChangeEnd:
                      durationSeconds <= 0 ? null : (value) => _seekAbsolute(value),
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
                    child: _menuIconButton(
                      key: playlistButtonKey,
                      icon: Icons.playlist_play_rounded,
                      tooltip: widget.controller.t('playlist'),
                      onPressed: _showPlaylistMenu,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _fileControl(
                      tooltip: widget.controller.t('previousFile'),
                      icon: Icons.skip_previous_rounded,
                      onPressed: currentIndex > 0
                          ? () => _switchToIndex(currentIndex - 1)
                          : null,
                    ),
                    const SizedBox(width: 22),
                    _roundControl(
                      icon: Icons.fast_rewind_rounded,
                      onPressed: () => _skip(-widget.controller.skipSeconds),
                    ),
                    const SizedBox(width: 12),
                    _roundControl(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: _togglePlayback,
                      prominent: true,
                    ),
                    const SizedBox(width: 12),
                    _roundControl(
                      icon: Icons.fast_forward_rounded,
                      onPressed: () => _skip(widget.controller.skipSeconds),
                    ),
                    const SizedBox(width: 22),
                    _fileControl(
                      tooltip: widget.controller.t('nextFile'),
                      icon: Icons.skip_next_rounded,
                      onPressed: currentIndex < widget.playlist.length - 1
                          ? () => _switchToIndex(currentIndex + 1)
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
                            icon: Icons.subtitles_rounded,
                            tooltip: widget.controller.t('subtitles'),
                            onPressed: _showSubtitleMenu,
                          ),
                        const SizedBox(width: 8),
                        _menuIconButton(
                          key: audioTrackButtonKey,
                          icon: Icons.graphic_eq_rounded,
                          tooltip: widget.controller.t('audioTracks'),
                          onPressed: _showAudioTrackMenu,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: widget.controller.t('audio'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _showAudioPopover(context),
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
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
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
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
      ),
    );
  }

  Widget _roundControl({
    required IconData icon,
    required VoidCallback onPressed,
    bool prominent = false,
  }) {
    return SizedBox(
      width: prominent ? 62 : 50,
      height: prominent ? 62 : 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: prominent
              ? syncAccent
              : syncAccent.withValues(alpha: 0.17),
          side: const BorderSide(color: syncAccent),
          shape: const CircleBorder(),
        ),
        child: Icon(icon, size: prominent ? 32 : 28),
      ),
    );
  }

  Widget _volumeIndicator() {
    final percent = ((volumeOsd ?? 0) * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6122538),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: syncBorder),
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
  }) async {
    final anchorContext = anchorKey.currentContext;
    if (anchorContext == null || items.isEmpty) return null;

    final anchorBox = anchorContext.findRenderObject() as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorOffset =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorRect = anchorOffset & anchorBox.size;

    const rowHeight = 44.0;
    final menuHeight =
        (items.length * rowHeight + 8).clamp(52.0, 330.0).toDouble();
    final maxLeft = (overlayBox.size.width - width - 8)
        .clamp(8.0, double.infinity)
        .toDouble();
    final left =
        (anchorRect.center.dx - width / 2).clamp(8.0, maxLeft).toDouble();
    final top =
        (anchorRect.top - menuHeight - 10).clamp(8.0, double.infinity).toDouble();

    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              height: menuHeight,
              child: Material(
                elevation: 14,
                color: syncBackgroundDeep,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final selected = index == selectedIndex;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      leading: selected
                          ? const Icon(Icons.check_rounded, size: 18)
                          : const SizedBox(width: 18),
                      title: Text(
                        items[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(index),
                    );
                  },
                ),
              ),
            ),
          ],
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
      width: 420,
    );
    if (selected != null) {
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
      width: 400,
    );
    if (selected != null) {
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
      width: 380,
    );
    if (selected != null) {
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

    await _openMedia();
  }

  Future<void> _togglePlayback() async {
    await player.playOrPause();
    if (player.state.playing) {
      await widget.syncEngine.play();
    } else {
      await widget.syncEngine.pause();
    }
  }

  Future<void> _skip(int deltaSeconds) async {
    await _seekAbsolute(positionSeconds + deltaSeconds);
  }

  Future<void> _seekAbsolute(double targetSeconds) async {
    final max = durationSeconds > 0 ? durationSeconds : 0.0;
    final target = targetSeconds.clamp(0.0, max).toDouble();
    final duration = Duration(milliseconds: (target * 1000).round());

    await player.seek(duration);
    await widget.syncEngine.seekTo(duration);
  }

  Future<void> _changeMovieVolume(double delta) async {
    final value = (widget.controller.movieVolume + delta).clamp(0.0, 1.0);
    widget.controller.setMovieVolume(value);
    await player.setVolume(value * 100.0);

    _volumeOsdTimer?.cancel();
    if (mounted) {
      setState(() => volumeOsd = value);
    }
    _volumeOsdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => volumeOsd = null);
    });
  }

  Future<void> _toggleFullscreen() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _showFullscreenTopChrome() async {
    if (!isFullscreen) return;

    if (!nativeTitleBarVisibleInFullscreen) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
    }

    if (!mounted) return;
    setState(() {
      nativeTitleBarVisibleInFullscreen = true;
      topControlsVisible = true;
    });
  }

  Future<void> _hideFullscreenTopChrome() async {
    if (!isFullscreen) return;

    if (nativeTitleBarVisibleInFullscreen) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }

    if (!mounted) return;
    setState(() {
      nativeTitleBarVisibleInFullscreen = false;
      topControlsVisible = false;
    });
  }

  Future<void> _enterPlayerFullscreen() async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    if (!mounted) return;
    setState(() {
      isFullscreen = true;
      nativeTitleBarVisibleInFullscreen = false;
      topControlsVisible = false;
      bottomControlsVisible = false;
    });
  }

  Future<void> _leavePlayerFullscreen() async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );

    if (!mounted) return;
    setState(() {
      isFullscreen = false;
      nativeTitleBarVisibleInFullscreen = false;
      topControlsVisible = true;
      bottomControlsVisible = true;
    });
  }

  @override
  void onWindowMaximize() {
    unawaited(_enterPlayerFullscreen());
  }

  @override
  void onWindowUnmaximize() {
    unawaited(_leavePlayerFullscreen());
  }

  @override
  void onWindowEnterFullScreen() {
    unawaited(_enterPlayerFullscreen());
  }

  @override
  void onWindowLeaveFullScreen() {
    unawaited(_leavePlayerFullscreen());
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final audio = player.state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList();
    final subtitles = player.state.tracks.subtitle
        .where((track) => track.id != 'auto')
        .toList();

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'play',
          child: ListTile(
            dense: true,
            leading: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            title: Text(
              playing
                  ? widget.controller.t('pause')
                  : widget.controller.t('play'),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: ListTile(
            dense: true,
            leading: Icon(
              movieMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            ),
            title: Text(
              movieMuted
                  ? widget.controller.t('unmuteMovie')
                  : widget.controller.t('muteMovie'),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'fullscreen',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.fullscreen_rounded),
            title: Text(widget.controller.t('fullscreen')),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text(widget.controller.t('audioTracks')),
        ),
        for (final track in audio)
          PopupMenuItem(
            value: 'audio:${track.id}',
            child: Text(
              '${currentAudioTrack?.id == track.id ? '✓ ' : ''}${_audioLabel(track)}',
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text(widget.controller.t('subtitles')),
        ),
        PopupMenuItem(
          value: 'subtitle:no',
          child: Text(
            '${currentSubtitleTrack?.id == 'no' ? '✓ ' : ''}${widget.controller.t('noSubtitles')}',
          ),
        ),
        for (final track in subtitles.where((track) => track.id != 'no'))
          PopupMenuItem(
            value: 'subtitle:${track.id}',
            child: Text(
              '${currentSubtitleTrack?.id == track.id ? '✓ ' : ''}${_subtitleLabel(track)}',
            ),
          ),
      ],
    );

    if (result == null) return;
    if (result == 'play') {
      await _togglePlayback();
      return;
    }
    if (result == 'mute') {
      movieMuted = !movieMuted;
      await player.setVolume(
        movieMuted ? 0 : widget.controller.movieVolume * 100.0,
      );
      if (mounted) setState(() {});
      return;
    }
    if (result == 'fullscreen') {
      await _toggleFullscreen();
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

  void _showAudioPopover(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) {
        return Dialog(
          alignment: Alignment.bottomRight,
          insetPadding: const EdgeInsets.only(right: 72, bottom: 116),
          child: SizedBox(
            width: 350,
            child: Padding(
              padding: const EdgeInsets.all(18),
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
                          await player.setVolume(
                            movieMuted
                                ? 0
                                : widget.controller.movieVolume * 100.0,
                          );
                        },
                        onChanged: (value) async {
                          widget.controller.setMovieVolume(value);
                          await player.setVolume(value * 100.0);
                        },
                      ),
                      const SizedBox(height: 16),
                      _volumeRow(
                        label: widget.controller.t('callVolume'),
                        value: widget.controller.callVolume,
                        muted: callMuted,
                        onMute: () => setState(() => callMuted = !callMuted),
                        onChanged: widget.controller.setCallVolume,
                      ),

                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
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
        SizedBox(width: 54, child: Text(label)),
        IconButton(
          onPressed: () => onMute(),
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
        ),
        Expanded(
          child: Slider(
            value: value,
            onChanged: (newValue) => onChanged(newValue),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(value * 100).round()}%'),
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
