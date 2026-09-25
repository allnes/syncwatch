import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../app.dart';
import '../core/app_theme.dart';
import '../models/movie_item.dart';
import '../services/call_engine.dart';
import '../services/sync_engine.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool get _isLight => Theme.of(context).brightness == Brightness.light;
  Color get _pageBackgroundDeep =>
      _isLight ? syncLightBackgroundDeep : syncBackgroundDeep;
  Color get _panelSurface =>
      _isLight ? syncLightSurface : syncSurface;
  Color get _panelBorder =>
      _isLight ? syncLightBorder : syncBorder;
  Color get _secondaryText =>
      _isLight ? syncLightTextSecondary : Colors.white54;
  Color get _secondaryTextStrong =>
      _isLight ? syncLightTextSecondary : Colors.white70;
  static const _videoExtensions = <String>{
    '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.webm', '.wmv',
    '.mpg', '.mpeg', '.ts', '.m2ts',
  };

  static const _subtitleExtensions = <String>{
    '.srt', '.ass', '.ssa', '.vtt', '.sub',
  };

  static const _externalAudioExtensions = <String>{
    '.aac', '.ac3', '.dts', '.eac3', '.flac', '.m4a', '.mka', '.mp3',
    '.ogg', '.opus', '.wav',
  };

  List<MovieItem> movies = demoMovies;
  MovieItem? selected = demoMovies.first;
  String searchQuery = '';
  bool scanning = false;
  bool callActive = false;
  Process? callProcess;
  String? callCommandFilePath;
  bool metadataLoading = false;
  String? metadataPath;
  bool microphoneEnabled = true;
  bool cameraEnabled = true;
  bool youReady = true;
  bool partnerReady = true;
  final CallEngine callEngine = MockCallEngine();
  int selectedAudioIndex = 0;
  int selectedSubtitleIndex = 0;
  String? expandedTrackMenu;
  final ScrollController trackMenuScrollController = ScrollController();
  final GlobalKey audioSelectorKey = GlobalKey();
  final GlobalKey subtitleSelectorKey = GlobalKey();

  MovieItem? activePlayerMovie;
  String activePlayerAudioTrack = '';
  String activePlayerSubtitleTrack = '';
  int playerSessionId = 0;
  bool showingPlayer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanLibrary());
  }

  @override
  void dispose() {
    trackMenuScrollController.dispose();
    callProcess?.kill();
    final commandPath = callCommandFilePath;
    if (commandPath != null) {
      try {
        File(commandPath).deleteSync();
      } catch (_) {}
    }
    if (callActive) {
      callEngine.leave();
    }
    super.dispose();
  }

  Future<void> _startCall() async {
    if (callActive) {
      await _focusCallWindow();
      return;
    }

    await callEngine.join();
    await callEngine.setMicrophoneEnabled(microphoneEnabled);
    await callEngine.setCameraEnabled(cameraEnabled);

    try {
      final commandFile = File(
        '${Directory.systemTemp.path}\\syncwatch_call_$pid.cmd',
      );
      await commandFile.writeAsString('ready:0', flush: true);
      callCommandFilePath = commandFile.path;

      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          '--call-window',
          '--call-command-file=${commandFile.path}',
        ],
        mode: ProcessStartMode.normal,
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      callProcess = process;
      process.exitCode.then((_) async {
        await callEngine.leave();
        if (!mounted) return;
        setState(() {
          callActive = false;
          callProcess = null;
          callCommandFilePath = null;
        });
      });
    } catch (_) {
      await callEngine.leave();
      rethrow;
    }

    if (!mounted) return;
    setState(() => callActive = true);
  }

  Future<void> _focusCallWindow() async {
    final process = callProcess;
    final commandPath = callCommandFilePath;
    if (process == null || commandPath == null) return;

    try {
      await File(commandPath).writeAsString(
        'restore:${DateTime.now().microsecondsSinceEpoch}',
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _browseFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: widget.controller.t('open'),
    );
    if (path != null && path.isNotEmpty) {
      widget.controller.setLibraryPath(path);
      await _scanLibrary(forceEmpty: true);
    }
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.56),
      builder: (_) => SettingsScreen(controller: widget.controller),
    );
    await _scanLibrary(forceEmpty: true);
  }

  String _normalizedDir(String path) {
    var normalized = Directory(path).absolute.path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  bool _isDirectlyInside(String filePath, String directoryPath) {
    return _normalizedDir(File(filePath).parent.path) == directoryPath;
  }

  bool _isInsideOneChildFolder(String filePath, String directoryPath) {
    final parent = File(filePath).parent;
    final parentPath = _normalizedDir(parent.path);
    if (parentPath == directoryPath) return false;
    return _normalizedDir(parent.parent.path) == directoryPath;
  }

  bool _looksLikeMovieBundle({
    required File videoFile,
    required List<File> allVideos,
    required List<File> subtitleFiles,
    required List<File> audioFiles,
  }) {
    final movieDir = _normalizedDir(videoFile.parent.path);

    final videosInSameFolder = allVideos.where(
      (candidate) => _isDirectlyInside(candidate.path, movieDir),
    );

    if (videosInSameFolder.length != 1) {
      return false;
    }

    bool isRelatedExtra(File extra) {
      return _isDirectlyInside(extra.path, movieDir) ||
          _isInsideOneChildFolder(extra.path, movieDir);
    }

    return subtitleFiles.any(isRelatedExtra) || audioFiles.any(isRelatedExtra);
  }

  Future<void> _scanLibrary({bool forceEmpty = false}) async {
    final directory = Directory(widget.controller.libraryPath);
    if (!await directory.exists()) {
      if (forceEmpty && mounted) {
        setState(() {
          movies = [];
          selected = null;
          selectedAudioIndex = 0;
          selectedSubtitleIndex = 0;
        });
      }
      return;
    }

    if (mounted) setState(() => scanning = true);

    final videoFiles = <File>[];
    final subtitleFiles = <File>[];
    final externalAudioFiles = <File>[];

    try {
      await for (final entity in directory.list(
        recursive: widget.controller.scanSubfolders,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final ext = _extension(entity.path);
        if (_videoExtensions.contains(ext)) {
          videoFiles.add(entity);
        } else if (_subtitleExtensions.contains(ext)) {
          subtitleFiles.add(entity);
        } else if (_externalAudioExtensions.contains(ext)) {
          externalAudioFiles.add(entity);
        }
      }

      videoFiles.sort(
        (a, b) => _fileName(a.path)
            .toLowerCase()
            .compareTo(_fileName(b.path).toLowerCase()),
      );

      final previousByPath = <String, MovieItem>{
        for (final item in movies) item.fullPath: item,
      };

      final scanned = videoFiles.map((file) {
        final fileName = _fileName(file.path);
        final base = _baseName(fileName).toLowerCase();

        final matchingSubs = subtitleFiles
            .where((subtitle) {
              final subName = _fileName(subtitle.path).toLowerCase();
              return subName.startsWith('$base.');
            })
            .map((subtitle) => _fileName(subtitle.path))
            .toList()
          ..sort();

        final isFolderMovie = _looksLikeMovieBundle(
          videoFile: file,
          allVideos: videoFiles,
          subtitleFiles: subtitleFiles,
          audioFiles: externalAudioFiles,
        );

        final previous = previousByPath[file.path];
        if (previous != null &&
            previous.duration > Duration.zero &&
            previous.audioTrackNames.isNotEmpty) {
          return MovieItem(
            fileName: fileName,
            fullPath: file.path,
            duration: previous.duration,
            resolution: previous.resolution,
            audioTracks: previous.audioTracks,
            subtitleTracks: previous.subtitleTracks,
            audioTrackNames: previous.audioTrackNames,
            subtitleTrackNames: previous.subtitleTrackNames,
            isFolderMovie: isFolderMovie,
          );
        }

        return MovieItem(
          fileName: fileName,
          fullPath: file.path,
          duration: Duration.zero,
          resolution: _inferResolution(fileName),
          audioTracks: 0,
          subtitleTracks: matchingSubs.length,
          audioTrackNames: const [],
          subtitleTrackNames: matchingSubs,
          isFolderMovie: isFolderMovie,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        movies = scanned;
        selected = scanned.isEmpty ? null : scanned.first;
        selectedAudioIndex = 0;
        selectedSubtitleIndex = 0;
      });

      // Populate real media metadata for the whole visible library, not only
      // the initially selected movie. Audio cannot be inferred from filenames.
      for (final movie in List<MovieItem>.from(scanned)) {
        if (!mounted) break;
        await _probeMovie(movie);
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _probeMovie(MovieItem movie) async {
    if (metadataLoading && metadataPath == movie.fullPath) return;
    if (movie.duration > Duration.zero && movie.audioTrackNames.isNotEmpty) {
      return;
    }

    setState(() {
      metadataLoading = true;
      metadataPath = movie.fullPath;
    });

    final probe = Player();
    try {
      await probe.open(
        Media(Uri.file(movie.fullPath).toString()),
        play: false,
      );

      Duration duration = probe.state.duration;
      if (duration == Duration.zero) {
        try {
          duration = await probe.stream.duration
              .firstWhere((value) => value > Duration.zero)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      var tracks = probe.state.tracks;
      if (tracks.audio.isEmpty && tracks.subtitle.isEmpty) {
        try {
          tracks = await probe.stream.tracks
              .firstWhere(
                (value) =>
                    value.audio.isNotEmpty || value.subtitle.isNotEmpty,
              )
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      final audio = tracks.audio
          .where((track) => track.id != 'auto' && track.id != 'no')
          .toList();
      final embeddedSubtitles = tracks.subtitle
          .where((track) => track.id != 'auto' && track.id != 'no')
          .toList();

      final externalSubtitles = movie.subtitleTrackNames
          .where(
            (name) =>
                name != widget.controller.t('noSubtitles') &&
                name != widget.controller.t('subtitlesOff'),
          )
          .toList();

      final width = probe.state.width;
      final height = probe.state.height;
      final resolution = width != null && height != null
          ? '$width×$height'
          : movie.resolution;

      final updated = MovieItem(
        fileName: movie.fileName,
        fullPath: movie.fullPath,
        duration: duration,
        resolution: resolution,
        audioTracks: audio.length,
        subtitleTracks: embeddedSubtitles.length + externalSubtitles.length,
        audioTrackNames: [
          for (final track in audio) _audioTrackLabel(track),
        ],
        subtitleTrackNames: [
          widget.controller.t('noSubtitles'),
          for (final track in embeddedSubtitles) _subtitleTrackLabel(track),
          ...externalSubtitles,
        ],
        isFolderMovie: movie.isFolderMovie,
      );

      if (!mounted) return;
      setState(() {
        final index = movies.indexWhere(
          (item) => item.fullPath == updated.fullPath,
        );
        if (index >= 0) {
          movies[index] = updated;
        }
        if (selected?.fullPath == updated.fullPath) {
          selected = updated;
          selectedAudioIndex = 0;
          selectedSubtitleIndex = 0;
        }
      });
    } finally {
      await probe.dispose();
      if (mounted && metadataPath == movie.fullPath) {
        setState(() => metadataLoading = false);
      }
    }
  }

  String _audioTrackLabel(AudioTrack track) {
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

  String _subtitleTrackLabel(SubtitleTrack track) {
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

  List<MovieItem> get _visibleMovies {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return movies;
    return movies
        .where((movie) => movie.fileName.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final libraryView = Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isLight
                    ? const [
                        Color(0xFFEAF1F6),
                        syncLightBackground,
                        syncLightBackgroundDeep,
                      ]
                    : const [
                        Color(0xFF0B2440),
                        syncBackground,
                        syncBackgroundDeep,
                      ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _header(),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(width: 360, child: _libraryPanel()),
                          const SizedBox(width: 14),
                          Expanded(child: _mainPanel()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final movie = activePlayerMovie;
        final playerView = movie == null
            ? const SizedBox.shrink()
            : PlayerScreen(
                key: ValueKey(playerSessionId),
                controller: widget.controller,
                movie: movie,
                syncEngine: MockSyncEngine(),
                initialAudioTrack: activePlayerAudioTrack,
                initialSubtitleTrack: activePlayerSubtitleTrack,
                playlist: movies,
                initialIndex: movies.indexWhere(
                  (item) => item.fullPath == movie.fullPath,
                ),
                onShowCall: callActive ? _focusCallWindow : null,
                onReturnHome: _showLibraryFromPlayer,
                onMovieChanged: _handlePlayerMovieChanged,
                onEndWatching: _endActivePlaybackSession,
                active: showingPlayer,
              );

        return IndexedStack(
          index: showingPlayer && movie != null ? 1 : 0,
          children: [
            libraryView,
            playerView,
          ],
        );
      },
    );
  }

  Widget _header() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: syncAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.play_arrow_rounded, size: 28),
          ),
          const SizedBox(width: 12),
          const Text(
            'SyncWatch',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 22),
          const VerticalDivider(indent: 15, endIndent: 15),
          const SizedBox(width: 12),
          const Icon(Icons.groups_2_rounded, color: syncAccentSoft),
          const SizedBox(width: 8),
          Text(
            widget.controller.roomName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          const Icon(Icons.circle, size: 10, color: syncSuccess),
          const SizedBox(width: 7),
          Text(widget.controller.t('friendOnline')),
          const SizedBox(width: 22),
          Icon(
            callActive ? Icons.call_rounded : Icons.call_outlined,
            color: callActive ? syncSuccess : Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 7),
          Text(
            callActive
                ? widget.controller.t('callActive')
                : widget.controller.t('callInactive'),
          ),
          const SizedBox(width: 22),
          _readyStatusChip(),
          const SizedBox(width: 12),
          if (callActive)
            IconButton(
              tooltip: widget.controller.t('goToCall'),
              onPressed: _focusCallWindow,
              icon: const Icon(Icons.videocam_rounded),
            ),
          IconButton(
            tooltip: widget.controller.t('settings'),
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }

  Widget _libraryPanel() {
    final visibleMovies = _visibleMovies;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_rounded,
                color: _isLight ? syncAccent : syncAccentSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.controller.t('movieLibrary'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${movies.length} ${widget.controller.t('files')}',
                style: TextStyle(color: _secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: _pageBackgroundDeep.withValues(alpha: _isLight ? 0.72 : 0.55),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _panelBorder),
                  ),
                  child: Text(
                    widget.controller.libraryPath,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _secondaryTextStrong),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: widget.controller.t('browse'),
                onPressed: _browseFolder,
                icon: const Icon(Icons.folder_open_rounded),
              ),
              IconButton(
                tooltip: widget.controller.t('rescan'),
                onPressed: scanning ? null : () => _scanLibrary(forceEmpty: true),
                icon: scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => searchQuery = value),
            decoration: InputDecoration(
              hintText: widget.controller.t('searchFiles'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: visibleMovies.isEmpty
                ? Center(
                    child: Text(
                      widget.controller.t('noMovies'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _secondaryText),
                    ),
                  )
                : ListView.separated(
                    itemCount: visibleMovies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 5),
                    itemBuilder: (context, index) {
                      final movie = visibleMovies[index];
                      final active = movie == selected;
                      return Material(
                        color: active
                            ? syncAccent.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        child: ListTile(
                          dense: true,
                          selected: active,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                            side: BorderSide(
                              color: active ? syncAccent : Colors.transparent,
                            ),
                          ),
                          leading: Icon(
                            movie.isFolderMovie
                                ? Icons.folder_rounded
                                : Icons.movie_outlined,
                            color: active
                                ? (_isLight ? syncAccent : syncAccentSoft)
                                : (_isLight
                                    ? syncLightTextSecondary
                                    : Colors.white60),
                          ),
                          title: Text(
                            movie.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: movie.duration == Duration.zero
                              ? null
                              : Text(
                                  _formatShort(movie.duration),
                                  style:
                                      TextStyle(color: _secondaryText),
                                ),
                          onTap: () async {
                            setState(() {
                              selected = movie;
                              selectedAudioIndex = 0;
                              selectedSubtitleIndex = 0;
                              expandedTrackMenu = null;
                            });
                            await _probeMovie(movie);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mainPanel() {
    final movie = selected;

    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedHeight =
            (constraints.maxHeight * 0.54).clamp(345.0, 375.0);

        return Column(
          children: [
            SizedBox(
              height: selectedHeight,
              child: Container(
                width: double.infinity,
                decoration: _panelDecoration(),
                clipBehavior: Clip.antiAlias,
                child: movie == null
                    ? Center(
                        child: Text(
                          widget.controller.t('noMovies'),
                          style: TextStyle(color: _secondaryText),
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: _movieDetails(movie),
                            ),
                          ),
                          if (expandedTrackMenu != null)
                            Positioned.fill(
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (event) {
                                  final audioHit = _globalKeyContains(
                                    audioSelectorKey,
                                    event.position,
                                  );
                                  final subtitleHit = _globalKeyContains(
                                    subtitleSelectorKey,
                                    event.position,
                                  );

                                  if (audioHit) {
                                    setState(() {
                                      expandedTrackMenu =
                                          expandedTrackMenu == 'audio'
                                              ? null
                                              : 'audio';
                                    });
                                    return;
                                  }

                                  if (subtitleHit) {
                                    setState(() {
                                      expandedTrackMenu =
                                          expandedTrackMenu == 'subtitles'
                                              ? null
                                              : 'subtitles';
                                    });
                                    return;
                                  }

                                  setState(() => expandedTrackMenu = null);
                                },
                              ),
                            ),
                          if (expandedTrackMenu != null)
                            _trackMenuOverlay(movie),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _roomCard()),
                  const SizedBox(width: 14),
                  Expanded(child: _activityCard()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isLivePlaybackMovie(MovieItem movie) {
    final active = activePlayerMovie;
    return active != null && active.fullPath == movie.fullPath;
  }

  Widget _movieDetails(MovieItem movie) {
    final probingThisMovie =
        metadataLoading && metadataPath == movie.fullPath;
    final audioNames = movie.audioTrackNames.isEmpty
        ? ['…']
        : movie.audioTrackNames;
    final subtitleNames = movie.subtitleTrackNames.isEmpty
        ? [widget.controller.t('noSubtitles')]
        : movie.subtitleTrackNames;

    selectedAudioIndex = selectedAudioIndex.clamp(0, audioNames.length - 1).toInt();
    selectedSubtitleIndex =
        selectedSubtitleIndex.clamp(0, subtitleNames.length - 1).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.controller.t('selectedMovie'),
          style: TextStyle(color: _secondaryText),
        ),
        const SizedBox(height: 10),
        _adaptiveMovieTitle(movie.fileName),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _metric(
                Icons.schedule_rounded,
                widget.controller.t('duration'),
                movie.duration == Duration.zero
                    ? widget.controller.t('unknown')
                    : _formatFull(movie.duration),
              ),
            ),
            Expanded(
              child: _metric(
                Icons.monitor_rounded,
                widget.controller.t('resolution'),
                movie.resolution.isEmpty
                    ? widget.controller.t('unknown')
                    : movie.resolution,
              ),
            ),
            Expanded(
              child: _trackSelector(
                icon: Icons.graphic_eq_rounded,
                label: widget.controller.t('audioTracks'),
                controlKey: audioSelectorKey,
                menuKey: 'audio',
                items: audioNames,
                value: selectedAudioIndex,
                onChanged: (value) =>
                    setState(() => selectedAudioIndex = value),
              ),
            ),
            Expanded(
              child: movie.subtitleTracks == 0
                  ? _metric(
                      Icons.subtitles_rounded,
                      widget.controller.t('subtitles'),
                      widget.controller.t('noSubtitles'),
                    )
                  : _trackSelector(
                      icon: Icons.subtitles_rounded,
                      label: widget.controller.t('subtitles'),
                      controlKey: subtitleSelectorKey,
                      menuKey: 'subtitles',
                      items: subtitleNames,
                      value: selectedSubtitleIndex,
                      onChanged: (value) =>
                          setState(() => selectedSubtitleIndex = value),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _openPlayer(movie),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                _isLivePlaybackMovie(movie)
                    ? widget.controller.t('continueWatching')
                    : widget.controller.t('startWatching'),
              ),
            ),
            if (_isLivePlaybackMovie(movie)) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _endActivePlaybackSession,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: Text(widget.controller.t('endWatching')),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 62,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _pageBackgroundDeep.withValues(alpha: _isLight ? 0.64 : 0.38),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _panelBorder),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_copy_outlined,
                color: _isLight ? syncAccent : syncAccentSoft,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.controller.t('fileLocation')),
                    const SizedBox(height: 3),
                    Text(
                      movie.fullPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _secondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }

  Widget _adaptiveMovieTitle(String text) {
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 350),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const maxFontSize = 31.0;
          const minFontSize = 20.0;

          double fontSize = maxFontSize;
          while (fontSize > minFontSize) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
              maxLines: 1,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);

            if (!painter.didExceedMaxLines &&
                painter.width <= constraints.maxWidth) {
              break;
            }
            fontSize -= 1;
          }

          return Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          );
        },
      ),
    );
  }

  Widget _trackMenuOverlay(MovieItem movie) {
    final audioNames = movie.audioTrackNames.isEmpty
        ? [widget.controller.t('noAudioTracks')]
        : movie.audioTrackNames;
    final subtitleNames = movie.subtitleTrackNames.isEmpty
        ? [widget.controller.t('noSubtitles')]
        : movie.subtitleTrackNames;

    final isAudio = expandedTrackMenu == 'audio';
    final items = isAudio ? audioNames : subtitleNames;
    final selectedIndex =
        isAudio ? selectedAudioIndex : selectedSubtitleIndex;

    return Positioned(
      top: 136,
      right: isAudio ? 220 : 18,
      width: isAudio ? 250 : 220,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        color: syncBackgroundDeep,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 155),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _panelBorder),
          ),
          child: Scrollbar(
            controller: trackMenuScrollController,
            thumbVisibility: items.length > 4,
            child: ListView.builder(
              controller: trackMenuScrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final selected = index == selectedIndex;
                return ListTile(
                  dense: true,
                  minLeadingWidth: 18,
                  horizontalTitleGap: 6,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  visualDensity: const VisualDensity(vertical: -4),
                  selected: selected,
                  leading: selected
                      ? const Icon(Icons.circle, size: 7, color: syncAccentSoft)
                      : const SizedBox(width: 7),
                  title: Tooltip(
                    message: items[index],
                    waitDuration: const Duration(milliseconds: 350),
                    child: Text(
                      items[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      if (isAudio) {
                        selectedAudioIndex = index;
                      } else {
                        selectedSubtitleIndex = index;
                      }
                      expandedTrackMenu = null;
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _globalKeyContains(GlobalKey key, Offset globalPosition) {
    final keyContext = key.currentContext;
    if (keyContext == null) return false;

    final renderObject = keyContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    return rect.contains(globalPosition);
  }

  Widget _trackSelector({
    Key? controlKey,
    required IconData icon,
    required String label,
    required String menuKey,
    required List<String> items,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final selectedText =
        items.isEmpty ? widget.controller.t('unknown') : items[value];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _isLight ? syncAccent : syncAccentSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _secondaryText)),
                const SizedBox(height: 5),
                InkWell(
                  key: controlKey,
                  borderRadius: BorderRadius.circular(8),
                  onTap: items.length <= 1
                      ? null
                      : () {
                          setState(() {
                            expandedTrackMenu =
                                expandedTrackMenu == menuKey ? null : menuKey;
                          });
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (items.length > 1)
                          Icon(
                            expandedTrackMenu == menuKey
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
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

  Widget _readyStatusChip({bool compact = false}) {
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
            size: compact ? 8 : 10,
            color: readyCount == 2 ? syncSuccess : Colors.white54,
          ),
          SizedBox(width: compact ? 5 : 7),
          Text(statusText),
        ],
      ),
    );
  }

  Widget _roomCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.controller.t('roomStatus'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(
                Icons.groups_2_rounded,
                color: _isLight ? syncAccent : syncAccentSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.controller.roomName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _readyStatusChip(compact: true),
            ],
          ),
          const SizedBox(height: 8),
          _memberRow(widget.controller.t('you')),
          const SizedBox(height: 5),
          _memberRow(widget.controller.t('friend')),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                padding: const EdgeInsets.symmetric(vertical: 9),
              ),
              onPressed: callActive ? _focusCallWindow : _startCall,
              icon: Icon(
                callActive
                    ? Icons.open_in_new_rounded
                    : Icons.video_call_rounded,
              ),
              label: Text(
                callActive
                    ? widget.controller.t('goToCall')
                    : widget.controller.t('startCall'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(String name) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor:
              _isLight ? syncLightBackgroundDeep : syncSurfaceRaised,
          child: Icon(
            Icons.person_rounded,
            size: 14,
            color: _isLight ? syncAccent : Colors.white70,
          ),
        ),
        const SizedBox(width: 9),
        Text(name),
        const Spacer(),
        const Icon(Icons.circle, color: syncSuccess, size: 9),
        const SizedBox(width: 6),
        Text(
          widget.controller.t('ready'),
          style: TextStyle(color: _secondaryText),
        ),
      ],
    );
  }

  Widget _activityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.controller.t('recentActivity'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _activityRow(widget.controller.t('friendJoined'), '20:15'),
          _activityRow(widget.controller.t('friendReady'), '20:16'),
          _activityRow(widget.controller.t('movieSelected'), '20:17'),
        ],
      ),
    );
  }

  Widget _activityRow(String text, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: syncSuccess),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          Text(time, style: TextStyle(color: _secondaryText)),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: syncAccentSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _secondaryText)),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: _panelSurface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _panelBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x25000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Future<void> _endActivePlaybackSession() async {
    if (activePlayerMovie == null) return;

    if (mounted) {
      setState(() {
        showingPlayer = false;
        activePlayerMovie = null;
        activePlayerAudioTrack = '';
        activePlayerSubtitleTrack = '';
        playerSessionId++;
      });
    }

    widget.controller.endPlaybackSession();
  }

  Future<void> _openPlayer(MovieItem movie) async {
    // If this exact movie is already the live playback session, simply reveal
    // the existing PlayerScreen. Nothing is reopened or seeked.
    if (_isLivePlaybackMovie(movie)) {
      if (mounted) {
        setState(() => showingPlayer = true);
      }
      return;
    }

    final audioNames = movie.audioTrackNames.isEmpty
        ? [widget.controller.t('noAudioTracks')]
        : movie.audioTrackNames;
    final subtitleNames = movie.subtitleTrackNames.isEmpty
        ? [widget.controller.t('noSubtitles')]
        : movie.subtitleTrackNames;

    final audioIndex =
        selectedAudioIndex.clamp(0, audioNames.length - 1).toInt();
    final subtitleIndex =
        selectedSubtitleIndex.clamp(0, subtitleNames.length - 1).toInt();

    if (!mounted) return;
    setState(() {
      activePlayerMovie = movie;
      activePlayerAudioTrack = audioNames[audioIndex];
      activePlayerSubtitleTrack = subtitleNames[subtitleIndex];
      playerSessionId++;
      showingPlayer = true;
    });
  }

  void _handlePlayerMovieChanged(MovieItem movie) {
    if (!mounted) return;
    setState(() {
      activePlayerMovie = movie;
      selected = movies.firstWhere(
        (item) => item.fullPath == movie.fullPath,
        orElse: () => movie,
      );
    });
  }

  Future<void> _showLibraryFromPlayer() async {
    if (!mounted) return;
    setState(() => showingPlayer = false);
  }

  String _formatShort(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _formatFull(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours}:$minutes:$seconds';
  }

  String _extension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    return name.substring(dot).toLowerCase();
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  String _baseName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? fileName : fileName.substring(0, dot);
  }

  String _inferResolution(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k')) return '3840×2160';
    if (lower.contains('1440p')) return '2560×1440';
    if (lower.contains('1080p')) return '1920×1080';
    if (lower.contains('720p')) return '1280×720';
    return '';
  }
}
