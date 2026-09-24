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
  static const _videoExtensions = <String>{
    '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.webm', '.wmv',
    '.mpg', '.mpeg', '.ts', '.m2ts',
  };

  static const _subtitleExtensions = <String>{
    '.srt', '.ass', '.ssa', '.vtt', '.sub',
  };

  List<MovieItem> movies = demoMovies;
  MovieItem? selected = demoMovies.first;
  String searchQuery = '';
  bool scanning = false;
  bool callActive = false;
  Process? callProcess;
  bool metadataLoading = false;
  String? metadataPath;
  bool microphoneEnabled = true;
  bool cameraEnabled = true;
  final CallEngine callEngine = MockCallEngine();
  int selectedAudioIndex = 0;
  int selectedSubtitleIndex = 0;
  String? expandedTrackMenu;
  final ScrollController trackMenuScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanLibrary());
  }

  @override
  void dispose() {
    trackMenuScrollController.dispose();
    callProcess?.kill();
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
      final process = await Process.start(
        Platform.resolvedExecutable,
        const ['--call-window'],
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
    if (process == null) return;

    final command = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class SyncWatchWindow {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsWindow(IntPtr hWnd);
}
"@

$targetPid = [uint32]PID_PLACEHOLDER
$script:found = [IntPtr]::Zero

$callback = [SyncWatchWindow+EnumWindowsProc]{
  param([IntPtr]$hWnd, [IntPtr]$lParam)

  [uint32]$windowPid = 0
  [SyncWatchWindow]::GetWindowThreadProcessId($hWnd, [ref]$windowPid) | Out-Null

  if ($windowPid -eq $targetPid -and [SyncWatchWindow]::IsWindow($hWnd)) {
    $script:found = $hWnd
    return $false
  }

  return $true
}

[SyncWatchWindow]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

if ($script:found -ne [IntPtr]::Zero) {
  # SW_RESTORE = 9. Works for minimized and hidden top-level windows.
  [SyncWatchWindow]::ShowWindowAsync($script:found, 9) | Out-Null
  Start-Sleep -Milliseconds 80
  [SyncWatchWindow]::SetForegroundWindow($script:found) | Out-Null
}
'''.replaceAll('PID_PLACEHOLDER', process.pid.toString());

    await Process.run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      runInShell: true,
    );
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
        }
      }

      videoFiles.sort(
        (a, b) => _fileName(a.path)
            .toLowerCase()
            .compareTo(_fileName(b.path).toLowerCase()),
      );

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

        return MovieItem(
          fileName: fileName,
          fullPath: file.path,
          duration: Duration.zero,
          resolution: _inferResolution(fileName),
          audioTracks: 0,
          subtitleTracks: matchingSubs.length,
          audioTrackNames: const [],
          subtitleTrackNames: matchingSubs,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        movies = scanned;
        selected = scanned.isEmpty ? null : scanned.first;
        selectedAudioIndex = 0;
        selectedSubtitleIndex = 0;
      });

      if (scanned.isNotEmpty) {
        await _probeMovie(scanned.first);
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
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
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
          const Icon(Icons.check_circle_rounded, color: syncSuccess, size: 20),
          const SizedBox(width: 7),
          Text(widget.controller.t('bothReady')),
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
              const Icon(Icons.folder_rounded, color: syncAccentSoft),
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
                style: const TextStyle(color: Colors.white54),
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
                    color: syncBackgroundDeep.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: syncBorder),
                  ),
                  child: Text(
                    widget.controller.libraryPath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
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
                      style: const TextStyle(color: Colors.white54),
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
                            Icons.movie_outlined,
                            color: active ? syncAccentSoft : Colors.white60,
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
                                      const TextStyle(color: Colors.white54),
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
                          style: const TextStyle(color: Colors.white54),
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
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () {
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

  Widget _movieDetails(MovieItem movie) {
    final probingThisMovie =
        metadataLoading && metadataPath == movie.fullPath;
    final audioNames = movie.audioTrackNames.isEmpty
        ? [
            probingThisMovie
                ? '…'
                : widget.controller.t('noAudioTracks'),
          ]
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
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 10),
        Text(
          movie.fileName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w800,
          ),
        ),
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
                widget.controller.hasPlaybackSessionFor(movie.fullPath)
                    ? widget.controller.t('continueWatching')
                    : widget.controller.t('startWatching'),
              ),
            ),

          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 62,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: syncBackgroundDeep.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: syncBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_copy_outlined, color: syncAccentSoft),
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
                      style: const TextStyle(color: Colors.white54),
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
            border: Border.all(color: syncBorder),
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
                      ? const Icon(Icons.check_rounded, size: 16)
                      : const SizedBox(width: 16),
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

  Widget _trackSelector({
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
          Icon(icon, color: syncAccentSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 5),
                InkWell(
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
              const Icon(Icons.groups_2_rounded, color: syncAccentSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.controller.roomName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.circle, size: 9, color: syncSuccess),
              const SizedBox(width: 6),
              Text(widget.controller.t('bothReady')),
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
        const CircleAvatar(
          radius: 12,
          backgroundColor: syncSurfaceRaised,
          child: Icon(Icons.person_rounded, size: 14),
        ),
        const SizedBox(width: 9),
        Text(name),
        const Spacer(),
        const Icon(Icons.circle, color: syncSuccess, size: 9),
        const SizedBox(width: 6),
        Text(
          widget.controller.t('ready'),
          style: const TextStyle(color: Colors.white60),
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
          Text(time, style: const TextStyle(color: Colors.white54)),
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
                Text(label, style: const TextStyle(color: Colors.white54)),
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
      color: syncSurface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: syncBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x25000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Future<void> _openPlayer(MovieItem movie) async {
    final audioNames = movie.audioTrackNames.isEmpty
        ? [widget.controller.t('noAudioTracks')]
        : movie.audioTrackNames;
    final subtitleNames = movie.subtitleTrackNames.isEmpty
        ? [widget.controller.t('noSubtitles')]
        : movie.subtitleTrackNames;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          controller: widget.controller,
          movie: movie,
          syncEngine: MockSyncEngine(),
          initialAudioTrack: audioNames[selectedAudioIndex],
          initialSubtitleTrack: subtitleNames[selectedSubtitleIndex],
          playlist: movies,
          initialIndex: movies.indexWhere(
            (item) => item.fullPath == movie.fullPath,
          ),
          onShowCall: callActive ? _focusCallWindow : null,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
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
