import 'package:flutter/material.dart';

import '../app.dart';

class RemoteVideoOverlay extends StatefulWidget {
  const RemoteVideoOverlay({super.key, required this.controller});

  final AppController controller;

  @override
  State<RemoteVideoOverlay> createState() => _RemoteVideoOverlayState();
}

class _RemoteVideoOverlayState extends State<RemoteVideoOverlay> {
  Offset position = const Offset(780, 90);
  Size size = const Size(300, 190);
  bool minimized = false;
  bool hidden = false;
  bool fullscreen = false;

  @override
  Widget build(BuildContext context) {
    if (hidden) {
      return Positioned(
        right: 22,
        top: 22,
        child: FloatingActionButton.small(
          tooltip: widget.controller.t('restore'),
          onPressed: () => setState(() => hidden = false),
          child: const Icon(Icons.videocam_rounded),
        ),
      );
    }

    if (fullscreen) {
      return Positioned.fill(
        left: 24,
        top: 24,
        right: 24,
        bottom: 120,
        child: _cameraCard(fullscreenMode: true),
      );
    }

    if (minimized) {
      return Positioned(
        left: position.dx,
        top: position.dy,
        child: GestureDetector(
          onPanUpdate: (details) => setState(() => position += details.delta),
          child: Material(
            color: const Color(0xE6101620),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFF56D38B)),
                  const SizedBox(width: 8),
                  const Text('Friend'),
                  IconButton(
                    tooltip: widget.controller.t('restore'),
                    onPressed: () => setState(() => minimized = false),
                    icon: const Icon(Icons.open_in_full_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: _cameraCard(),
    );
  }

  Widget _cameraCard({bool fullscreenMode = false}) {
    return Material(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF111923),
      borderRadius: BorderRadius.circular(fullscreenMode ? 18 : 14),
      elevation: 12,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: fullscreenMode
                  ? null
                  : (details) =>
                      setState(() => position += details.delta),
              onDoubleTap: () => setState(() => fullscreen = !fullscreen),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF263A4E), Color(0xFF101820)],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 78,
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 15),
                    SizedBox(width: 5),
                    Text('Friend  •  480p'),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!fullscreenMode)
                    IconButton(
                      tooltip: widget.controller.t('minimize'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => minimized = true),
                      icon: const Icon(Icons.remove_rounded, size: 19),
                    ),
                  IconButton(
                    tooltip: widget.controller.t('fullscreen'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => fullscreen = !fullscreen),
                    icon: Icon(
                      fullscreenMode
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      size: 19,
                    ),
                  ),
                  IconButton(
                    tooltip: widget.controller.t('hide'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      fullscreen = false;
                      hidden = true;
                    }),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ),
          if (!fullscreenMode)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    size = Size(
                      (size.width + details.delta.dx).clamp(180.0, 720.0).toDouble(),
                      (size.height + details.delta.dy).clamp(120.0, 480.0).toDouble(),
                    );
                  });
                },
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 17,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
