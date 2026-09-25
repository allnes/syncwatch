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
  bool youReady = true;
  bool partnerReady = true;
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
  final GlobalKey volumeButtonKey = GlobalKey();

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
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              await _returnToHome();
            }
          },
          child: Scaffold(
          backgroundColor: syncBackgroundDeep,
          body: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final delta = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
                _changeMovieVolume(delta);
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
                    height: topControlsVisible ? 82 : 40,
                    child: MouseRegion(
                      onEnter: (_) {
                        if (!topControlsVisible) {
                          setState(() => topControlsVisible = true);
                        }
                      },
                      onExit: (_) {
                        if (topControlsVisible) {
                          setState(() => topControlsVisible = false);
                        }
                      },
                      child: topControlsVisible
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _fullscreenWindowBar(),
                                _topBar(context, compact: true),
                              ],
                            )
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
                    height: 70,
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
        bottom: isFullscreen ? 0 : 78,
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
                top: isFullscreen ? 88 : 18,
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

  Widget _fullscreenWindowBar() {
    return Container(
      height: 34,
      color: const Color(0xFF7357C8),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'SyncWatch',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ),
          IconButton(
            tooltip: widget.controller.t('minimize'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
            padding: EdgeInsets.zero,
            onPressed: windowManager.minimize,
            icon: const Icon(Icons.remove_rounded, size: 17),
          ),
          IconButton(
            tooltip: widget.controller.t('fullscreen'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
            padding: EdgeInsets.zero,
            onPressed: _toggleFullscreen,
            icon: const Icon(Icons.fullscreen_exit_rounded, size: 17),
          ),
          IconButton(
            tooltip: widget.controller.t('hide'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
            padding: EdgeInsets.zero,
            onPressed: windowManager.close,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, {bool compact = false}) {
    return Container(
      height: compact ? 48 : 68,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      color: syncBackgroundDeep.withValues(alpha: 0.98),
      child: Row(
        children: [
          IconButton(
            tooltip: widget.controller.t('back'),
            onPressed: _returnToHome,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 6),
          Text(
            'SyncWatch',
            style: TextStyle(
              fontSize: compact ? 17 : 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 20),
          const VerticalDivider(indent: 16, endIndent: 16),
          const SizedBox(width: 8),
          const Icon(Icons.groups_2_rounded, color: syncAccentSoft),
          const SizedBox(width: 8),
          Text(widget.controller.roomName),
          const Spacer(),
          _readyStatusChip(),
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

  Widget _readyStatusChip() {
    final readyCount = (youReady ? 1 : 0) + (partnerReady ? 1 : 0);
    final statusText =
        '$readyCount/2 ${widget.controller.t('ready').toLowerCase()}';

    final tooltipText = [
      '${widget.controller.t('you')} — ${youReady ? widget.controller.t('ready') : widget.controller.t('notReady')}',
      '${widget.controller.t('friend')} — ${partnerReady ? widget.controller.t('ready') : widget.controller.t('notReady')}',
    ].join('\n');

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            readyCount == 2
                ? Icons.circle
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: readyCount == 2 ? syncSuccess : Colors.white54,
          ),
          const SizedBox(width: 6),
          Text(statusText),
        ],
      ),
    );
  }

  Widget _controls() {
    final sliderMax = durationSeconds > 0 ? durationSeconds : 1.0;
    final sliderValue = positionSeconds.clamp(0.0, sliderMax).toDouble();

    return Container(
      height: 70,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      color: syncBackgroundDeep.withValues(alpha: 0.98),
      child: Column(
        children: [
          Row(
            children: [
              Text(_formatSeconds(positionSeconds)),
              Expanded(
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
                      : (value) => setState(() => positionSeconds = value),
                  onChangeEnd:
                      durationSeconds <= 0 ? null : (value) => _seekAbsolute(value),
                  ),
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
              : syncAccent.withValues(alpha: 0.17),
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
    double maxHeight = 280,
  }) async {
    final anchorContext = anchorKey.currentContext;
    if (anchorContext == null || items.isEmpty) return null;

    final anchorBox = anchorContext.findRenderObject() as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorOffset =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorRect = anchorOffset & anchorBox.size;

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
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(index),
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
                                  style: const TextStyle(fontSize: 12.5),
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
      width: 340,
      maxHeight: 300,
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
      width: 300,
      maxHeight: 260,
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
      width: 240,
      maxHeight: 220,
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

  Future<void> _returnToHome() async {
    if (isFullscreen) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _toggleFullscreen() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _enterPlayerFullscreen() async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    if (!mounted) return;
    setState(() {
      isFullscreen = true;
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
                    color: syncBackgroundDeep,
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
                          icon: movieMuted
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          label: movieMuted
                              ? widget.controller.t('unmuteMovie')
                              : widget.controller.t('muteMovie'),
                          onTap: () => Navigator.of(context).pop('mute'),
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
                          icon: Icons.fullscreen_rounded,
                          label: widget.controller.t('fullscreen'),
                          onTap: () => Navigator.of(context).pop('fullscreen'),
                        ),
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
                      color: syncBackgroundDeep,
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
                                              ? Colors.white
                                              : Colors.white38,
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
    if (result == 'settings') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.56),
        builder: (_) => SettingsScreen(controller: widget.controller),
      );
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

  Widget _contextMenuRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onHover,
    bool hasSubmenu = false,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover?.call(),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Icon(icon, size: 15, color: Colors.white70),
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
                const Icon(
                  Icons.arrow_right_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAudioPopover() async {
    final anchorContext = volumeButtonKey.currentContext;
    if (anchorContext == null) return;

    final anchorBox = anchorContext.findRenderObject() as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorOffset =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorRect = anchorOffset & anchorBox.size;

    const width = 310.0;
    const height = 92.0;
    final maxLeft = (overlayBox.size.width - width - 8)
        .clamp(8.0, double.infinity)
        .toDouble();
    final left =
        (anchorRect.center.dx - width / 2).clamp(8.0, maxLeft).toDouble();
    final top =
        (anchorRect.top - height - 10).clamp(8.0, double.infinity).toDouble();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'volume',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: Material(
                elevation: 14,
                color: syncSurfaceRaised,
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
          ],
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
