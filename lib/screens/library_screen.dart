import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../core/app_theme.dart';
import '../models/movie_item.dart';
import '../services/sync_engine.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.mockMode,
  });

  final AppController controller;
  final bool mockMode;

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
  int selectedAudioIndex = 0;
  int selectedSubtitleIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanLibrary());
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
          audioTracks: 1,
          subtitleTracks: matchingSubs.length,
          audioTrackNames: [widget.controller.t('defaultAudio')],
          subtitleTrackNames: [
            widget.controller.t('subtitlesOff'),
            ...matchingSubs,
          ],
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        movies = scanned;
        selected = scanned.isEmpty ? null : scanned.first;
        selectedAudioIndex = 0;
        selectedSubtitleIndex = 0;
      });
    } finally {
      if (mounted) setState(() => scanning = false);
    }
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
          const Icon(Icons.check_circle_rounded, color: syncSuccess, size: 20),
          const SizedBox(width: 7),
          Text(widget.controller.t('bothReady')),
          const SizedBox(width: 12),
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
                          onTap: () {
                            setState(() {
                              selected = movie;
                              selectedAudioIndex = 0;
                              selectedSubtitleIndex = 0;
                            });
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

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: _panelDecoration(),
            child: movie == null
                ? Center(
                    child: Text(
                      widget.controller.t('noMovies'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _movieDetails(movie),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 182,
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
  }

  Widget _movieDetails(MovieItem movie) {
    final audioNames = movie.audioTrackNames.isEmpty
        ? [widget.controller.t('defaultAudio')]
        : movie.audioTrackNames;
    final subtitleNames = movie.subtitleTrackNames.isEmpty
        ? [widget.controller.t('subtitlesOff')]
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
        const SizedBox(height: 24),
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
                items: audioNames,
                value: selectedAudioIndex,
                onChanged: (value) =>
                    setState(() => selectedAudioIndex = value),
              ),
            ),
            Expanded(
              child: _trackSelector(
                icon: Icons.subtitles_rounded,
                label: widget.controller.t('subtitles'),
                items: subtitleNames,
                value: selectedSubtitleIndex,
                onChanged: (value) =>
                    setState(() => selectedSubtitleIndex = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _openPlayer(movie),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(widget.controller.t('startWatching')),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _openPlayer(movie),
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(widget.controller.t('open')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
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
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _trackSelector({
    required IconData icon,
    required String label,
    required List<String> items,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
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
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: value,
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < items.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            items[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (newValue) {
                      if (newValue != null) onChanged(newValue);
                    },
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
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.controller.t('roomStatus'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const Icon(Icons.groups_2_rounded, color: syncAccentSoft),
              const SizedBox(width: 10),
              Text(
                widget.controller.roomName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              const Icon(Icons.circle, size: 9, color: syncSuccess),
              const SizedBox(width: 6),
              Text(widget.controller.t('bothReady')),
            ],
          ),
          const Spacer(),
          _memberRow(widget.controller.t('you')),
          const SizedBox(height: 8),
          _memberRow(widget.controller.t('friend')),
        ],
      ),
    );
  }

  Widget _memberRow(String name) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: syncSurfaceRaised,
          child: Icon(Icons.person_rounded, size: 16),
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

  void _openPlayer(MovieItem movie) {
    final audioNames = movie.audioTrackNames.isEmpty
        ? [widget.controller.t('defaultAudio')]
        : movie.audioTrackNames;
    final subtitleNames = movie.subtitleTrackNames.isEmpty
        ? [widget.controller.t('subtitlesOff')]
        : movie.subtitleTrackNames;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          controller: widget.controller,
          movie: movie,
          syncEngine: MockSyncEngine(),
          initialAudioTrack: audioNames[selectedAudioIndex],
          initialSubtitleTrack: subtitleNames[selectedSubtitleIndex],
        ),
      ),
    );
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
