import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/movie_item.dart';
import '../services/sync_engine.dart';
import '../widgets/remote_video_overlay.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.movie,
    required this.syncEngine,
  });

  final AppController controller;
  final MovieItem movie;
  final SyncEngine syncEngine;

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
          backgroundColor: Colors.black,
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
                RemoteVideoOverlay(controller: widget.controller),
                Positioned(left: 18, top: 18, child: _topStatus(context)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _controls(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _movieSurface() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.1, -0.2),
          radius: 1.2,
          colors: [Color(0xFF162538), Color(0xFF05070B), Colors.black],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline_rounded,
              size: 84,
              color: Colors.white12,
            ),
            const SizedBox(height: 16),
            Text(
              widget.movie.fileName,
              style: const TextStyle(color: Colors.white30),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topStatus(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: widget.controller.t('back'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            Text(widget.controller.roomName),
            const SizedBox(width: 12),
            const Icon(Icons.circle, size: 8, color: Color(0xFF56D38B)),
            const SizedBox(width: 6),
            Text(widget.controller.t('connected')),
            const SizedBox(width: 12),
            Text(
              '2/2 ${widget.controller.t('ready')}',
              style: const TextStyle(color: Color(0xFF82AFFF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.94),
            Colors.black.withValues(alpha: 0.70),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_formatSeconds(positionSeconds)),
              Expanded(
                child: Slider(
                  value: positionSeconds.clamp(0, durationSeconds),
                  max: durationSeconds,
                  onChanged: (value) => setState(() => positionSeconds = value),
                  onChangeEnd: _seekAbsolute,
                ),
              ),
              Text(_formatSeconds(durationSeconds)),
            ],
          ),
          SizedBox(
            height: 62,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip:
                          '-${widget.controller.skipSeconds} ${widget.controller.t('seconds')}',
                      iconSize: 34,
                      onPressed: () => _skip(-widget.controller.skipSeconds),
                      icon: const Icon(Icons.fast_rewind_rounded),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(17),
                      ),
                      onPressed: _togglePlayback,
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip:
                          '+${widget.controller.skipSeconds} ${widget.controller.t('seconds')}',
                      iconSize: 34,
                      onPressed: () => _skip(widget.controller.skipSeconds),
                      icon: const Icon(Icons.fast_forward_rounded),
                    ),
                  ],
                ),
                Positioned(
                  right: 0,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: widget.controller.t('audio'),
                        onPressed: () => _showAudioPopover(context),
                        icon: Icon(
                          movieMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: 'CC',
                        onPressed: () {},
                        icon: const Icon(Icons.subtitles_rounded),
                      ),
                      IconButton(
                        tooltip: widget.controller.t('settings'),
                        onPressed: () {},
                        icon: const Icon(Icons.more_vert_rounded),
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

    // Room synchronization receives the final timestamp, not "+10" or "+30".
    widget.syncEngine.seekTo(
      Duration(milliseconds: (target * 1000).round()),
    );
  }

  void _showAudioPopover(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return AlertDialog(
              title: Text(widget.controller.t('audio')),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _volumeRow(
                      label: widget.controller.t('movieVolume'),
                      value: widget.controller.movieVolume,
                      muted: movieMuted,
                      onMute: () => setState(() => movieMuted = !movieMuted),
                      onChanged: widget.controller.setMovieVolume,
                    ),
                    const SizedBox(height: 18),
                    _volumeRow(
                      label: widget.controller.t('callVolume'),
                      value: widget.controller.callVolume,
                      muted: callMuted,
                      onMute: () => setState(() => callMuted = !callMuted),
                      onChanged: widget.controller.setCallVolume,
                    ),
                    const Divider(height: 28),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.controller.t('ducking')),
                      value: widget.controller.ducking,
                      onChanged: widget.controller.setDucking,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Microphone'),
                      secondary: Icon(
                        micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      ),
                      value: !micMuted,
                      onChanged: (enabled) =>
                          setState(() => micMuted = !enabled),
                    ),
                  ],
                ),
              ),
            );
          },
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
        SizedBox(width: 58, child: Text(label)),
        IconButton(
          onPressed: onMute,
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
        ),
        Expanded(child: Slider(value: value, onChanged: onChanged)),
        SizedBox(
          width: 46,
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
