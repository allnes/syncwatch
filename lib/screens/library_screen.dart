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
  MovieItem selected = demoMovies.first;

  Future<void> _browseFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: widget.controller.t('open'),
    );
    if (path != null && path.isNotEmpty) {
      widget.controller.setLibraryPath(path);
    }
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.56),
      builder: (_) => SettingsScreen(controller: widget.controller),
    );
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
              Text(
                widget.controller.t('movieLibrary'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${demoMovies.length} files',
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
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: widget.controller.t('searchFiles'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: demoMovies.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                final movie = demoMovies[index];
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
                    trailing: Text(
                      _formatShort(movie.duration),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    onTap: () => setState(() => selected = movie),
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
    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: _panelDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.controller.t('selectedMovie'),
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 10),
                Text(
                  selected.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 28,
                  runSpacing: 14,
                  children: [
                    _metric(
                      Icons.schedule_rounded,
                      widget.controller.t('duration'),
                      _formatFull(selected.duration),
                    ),
                    _metric(
                      Icons.monitor_rounded,
                      widget.controller.t('resolution'),
                      selected.resolution,
                    ),
                    _metric(
                      Icons.graphic_eq_rounded,
                      widget.controller.t('audioTracks'),
                      '${selected.audioTracks}',
                    ),
                    _metric(
                      Icons.subtitles_rounded,
                      widget.controller.t('subtitles'),
                      '${selected.subtitleTracks}',
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openPlayer(selected),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(widget.controller.t('startWatching')),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(widget.controller.t('open')),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: syncBackgroundDeep.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: syncBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_copy_outlined,
                          color: syncAccentSoft),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.controller.t('fileLocation')),
                            const SizedBox(height: 3),
                            Text(
                              '${widget.controller.libraryPath}\\${selected.fileName}',
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
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          flex: 3,
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
          const _MemberRow(name: 'You', ready: true),
          const SizedBox(height: 8),
          const _MemberRow(name: 'Friend', ready: true),
        ],
      ),
    );
  }

  Widget _activityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent activity',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 14),
          _ActivityRow(text: 'Friend joined the room', time: '20:15'),
          _ActivityRow(text: 'Friend is ready', time: '20:16'),
          _ActivityRow(text: 'Movie selected', time: '20:17'),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          Icon(icon, color: syncAccentSoft),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          controller: widget.controller,
          movie: movie,
          syncEngine: MockSyncEngine(),
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
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.name, required this.ready});

  final String name;
  final bool ready;

  @override
  Widget build(BuildContext context) {
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
        Icon(
          ready ? Icons.circle : Icons.circle_outlined,
          color: ready ? syncSuccess : Colors.white30,
          size: 9,
        ),
        const SizedBox(width: 6),
        Text(
          ready ? 'Ready' : 'Waiting',
          style: const TextStyle(color: Colors.white60),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.text, required this.time});

  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
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
}
