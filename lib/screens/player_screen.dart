import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../core/app_theme.dart';
import '../models/movie_item.dart';
import '../services/sync_engine.dart';
import '../widgets/remote_video_overlay.dart';
import 'settings_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.movie,
    required this.syncEngine,
    required this.initialAudioTrack,
    required this.initialSubtitleTrack,
  });

  final AppController controller;
  final MovieItem movie;
  final SyncEngine syncEngine;
  final String initialAudioTrack;
  final String initialSubtitleTrack;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool playing = false;
  bool movieMuted = false;
  bool callMuted = false;
  bool micMuted = false;
  late double positionSeconds;
  late final double durationSeconds;

  @override
  void initState() {
    super.initState();
    durationSeconds = widget.movie.duration.inSeconds.toDouble();
    positionSeconds = durationSeconds * 0.31;
    widget.syncEngine.connect();
    if (widget.controller.autoReady) {
      widget.syncEngine.setReady(true);
    }
  }

  @override
  void dispose() {
    widget.syncEngine.dispose();
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
                widget.controller.setMovieVolume(
                  widget.controller.movieVolume + delta,
                );
              }
            },
            child: Stack(
              children: [
                Positioned.fill(child: _movieSurface()),
                Positioned(left: 0, right: 0, top: 0, child: _topBar(context)),
                RemoteVideoOverlay(controller: widget.controller),
                Positioned(left: 0, right: 0, bottom: 0, child: _controls()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _movieSurface() {
    return Container(
      margin: const EdgeInsets.only(top: 68, bottom: 118),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.15, -0.15),
          radius: 1.1,
          colors: [
            Color(0xFF183B59),
            Color(0xFF0A2236),
            Color(0xFF06121D),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 32,
            top: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.movie.fileName,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(_formatSeconds(durationSeconds)),
                    const SizedBox(width: 18),
                    const Icon(Icons.monitor_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(widget.movie.resolution),
                    const SizedBox(width: 18),
                    const Icon(Icons.graphic_eq_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(widget.initialAudioTrack),
                    const SizedBox(width: 18),
                    const Icon(Icons.subtitles_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(widget.initialSubtitleTrack),
                  ],
                ),
              ],
            ),
          ),
          Center(
            child: Icon(
              Icons.movie_creation_outlined,
              size: 94,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ],
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
                  value: positionSeconds.clamp(0.0, durationSeconds).toDouble(),
                  max: durationSeconds,
                  onChanged: (value) => setState(() => positionSeconds = value),
                  onChangeEnd: _seekAbsolute,
                ),
              ),
              Text(_formatSeconds(durationSeconds)),
            ],
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundControl(
                      icon: Icons.fast_rewind_rounded,
                      onPressed: () => _skip(-widget.controller.skipSeconds),
                    ),
                    const SizedBox(width: 16),
                    _roundControl(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: _togglePlayback,
                      prominent: true,
                    ),
                    const SizedBox(width: 16),
                    _roundControl(
                      icon: Icons.fast_forward_rounded,
                      onPressed: () => _skip(widget.controller.skipSeconds),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.subtitles_rounded),
                    label: Text(widget.controller.t('subtitles')),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: widget.controller.t('audio'),
                        onPressed: () => _showAudioPopover(context),
                        icon: Icon(
                          movieMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: widget.controller.t('fullscreen'),
                        onPressed: () {},
                        icon: const Icon(Icons.fullscreen_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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

  void _togglePlayback() {
    setState(() => playing = !playing);
    if (playing) {
      widget.syncEngine.play();
    } else {
      widget.syncEngine.pause();
    }
  }

  void _skip(int deltaSeconds) {
    _seekAbsolute(positionSeconds + deltaSeconds);
  }

  void _seekAbsolute(double targetSeconds) {
    final target = targetSeconds.clamp(0.0, durationSeconds).toDouble();
    setState(() => positionSeconds = target);
    widget.syncEngine.seekTo(
      Duration(milliseconds: (target * 1000).round()),
    );
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
                        onMute: () => setState(() => movieMuted = !movieMuted),
                        onChanged: widget.controller.setMovieVolume,
                      ),
                      const SizedBox(height: 16),
                      _volumeRow(
                        label: widget.controller.t('callVolume'),
                        value: widget.controller.callVolume,
                        muted: callMuted,
                        onMute: () => setState(() => callMuted = !callMuted),
                        onChanged: widget.controller.setCallVolume,
                      ),
                      const Divider(height: 26),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(widget.controller.t('ducking')),
                        value: widget.controller.ducking,
                        onChanged: widget.controller.setDucking,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(widget.controller.t('microphone')),
                        secondary: Icon(
                          micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        ),
                        value: !micMuted,
                        onChanged: (enabled) =>
                            setState(() => micMuted = !enabled),
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
    required VoidCallback onMute,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 54, child: Text(label)),
        IconButton(
          onPressed: onMute,
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
        ),
        Expanded(child: Slider(value: value, onChanged: onChanged)),
        SizedBox(
          width: 44,
          child: Text('${(value * 100).round()}%'),
        ),
      ],
    );
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
