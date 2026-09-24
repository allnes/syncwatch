import 'package:flutter/material.dart';

import '../app.dart';
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _header(context),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _movieList(context)),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 2, child: _details(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 18, 16),
      child: Row(
        children: [
          const Text(
            'SYNCWATCH',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${widget.controller.t('room')}: ${widget.controller.roomName}',
            ),
          ),
          const Spacer(),
          const Icon(Icons.circle, size: 9, color: Color(0xFF56D38B)),
          const SizedBox(width: 7),
          Text(widget.controller.t('friendOnline')),
          if (widget.mockMode) ...[
            const SizedBox(width: 12),
            Text(
              widget.controller.t('mockMode'),
              style: const TextStyle(color: Colors.white54),
            ),
          ],
          const SizedBox(width: 14),
          IconButton(
            tooltip: widget.controller.t('settings'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(controller: widget.controller),
                ),
              );
            },
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }

  Widget _movieList(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.controller.t('movies'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.controller.libraryPath,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: demoMovies.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final movie = demoMovies[index];
                final isSelected = movie == selected;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: const Icon(Icons.movie_outlined),
                  title: Text(
                    movie.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatDuration(movie.duration)}  •  ${movie.resolution}',
                  ),
                  onTap: () => setState(() => selected = movie),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => _openPlayer(context, movie),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.fileName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 26),
          _info(widget.controller.t('duration'), _duration(selected.duration)),
          _info(widget.controller.t('resolution'), selected.resolution),
          _info(widget.controller.t('audioTracks'), '${selected.audioTracks}'),
          _info(widget.controller.t('subtitles'), '${selected.subtitleTracks}'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openPlayer(context, selected),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(widget.controller.t('open')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Text(value),
        ],
      ),
    );
  }

  void _openPlayer(BuildContext context, MovieItem movie) {
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _duration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours}:$minutes:00';
  }
}
