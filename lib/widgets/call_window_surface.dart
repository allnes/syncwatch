import 'package:flutter/material.dart';

/// The upstream call-window chrome, shared by the real and diagnostic views.
/// Native window operations stay with the owner of each OS window.
class CallWindowSurface extends StatelessWidget {
  const CallWindowSurface({
    super.key,
    required this.microphoneEnabled,
    required this.cameraEnabled,
    required this.fullscreen,
    required this.alwaysOnTop,
    required this.onDrag,
    required this.onPin,
    required this.onMinimize,
    required this.onFullscreen,
    required this.onMicrophone,
    required this.onCamera,
    required this.onHangUp,
    this.video,
    this.wrapResizeArea,
  });

  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool fullscreen;
  final bool alwaysOnTop;
  final VoidCallback onDrag;
  final VoidCallback onPin;
  final VoidCallback onMinimize;
  final VoidCallback onFullscreen;
  final VoidCallback onMicrophone;
  final VoidCallback onCamera;
  final VoidCallback onHangUp;
  final Widget? video;
  final Widget Function(Widget child)? wrapResizeArea;

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required double size,
    Color background = const Color(0xFF183247),
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
          minimumSize: Size(size, size),
          maximumSize: Size(size, size),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: size * 0.50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = fullscreen ? 0.0 : 22.0;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                !fullscreen &&
                constraints.maxWidth <= 340 &&
                constraints.maxHeight <= 260;
            final callButtonSize = fullscreen ? 40.0 : (compact ? 34.0 : 40.0);
            final callButtonGap = fullscreen ? 10.0 : (compact ? 8.0 : 10.0);
            final bottomInset = fullscreen ? 16.0 : (compact ? 12.0 : 16.0);
            final content = ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1C2B),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: const Color(0xFF29485E), width: 1),
                ),
                child: Stack(
                  children: [
                    if (video != null)
                      Positioned.fill(
                        left: 1,
                        top: 1,
                        right: 1,
                        bottom: 1,
                        child: video!,
                      ),
                    Positioned(
                      left: 10,
                      right: 8,
                      top: 7,
                      height: 36,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => onDrag(),
                        child: Row(
                          children: [
                            const Spacer(),
                            IconButton(
                              tooltip: alwaysOnTop
                                  ? 'Открепить от переднего плана'
                                  : 'Закрепить поверх окон',
                              onPressed: onPin,
                              icon: RotatedBox(
                                // Vertical when inactive, horizontal when pinned.
                                quarterTurns: alwaysOnTop ? 1 : 0,
                                child: const Icon(
                                  Icons.push_pin_rounded,
                                  size: 18,
                                ),
                              ),
                              color: alwaysOnTop
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            IconButton(
                              tooltip: 'Свернуть',
                              onPressed: onMinimize,
                              icon: const Icon(Icons.remove_rounded, size: 18),
                              color: Colors.white70,
                            ),
                            IconButton(
                              tooltip: fullscreen
                                  ? 'Выйти из полноэкранного режима'
                                  : 'На весь экран',
                              onPressed: onFullscreen,
                              icon: Icon(
                                fullscreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                size: 20,
                              ),
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomInset,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _roundButton(
                            tooltip: microphoneEnabled
                                ? 'Выключить микрофон'
                                : 'Включить микрофон',
                            icon: microphoneEnabled
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            size: callButtonSize,
                            onPressed: onMicrophone,
                          ),
                          SizedBox(width: callButtonGap),
                          _roundButton(
                            tooltip: cameraEnabled
                                ? 'Выключить камеру'
                                : 'Включить камеру',
                            icon: cameraEnabled
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            size: callButtonSize,
                            onPressed: onCamera,
                          ),
                          SizedBox(width: callButtonGap),
                          _roundButton(
                            tooltip: 'Завершить звонок',
                            icon: Icons.call_end_rounded,
                            background: const Color(0xFFB3261E),
                            size: callButtonSize,
                            onPressed: onHangUp,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
            return wrapResizeArea?.call(content) ?? content;
          },
        ),
      ),
    );
  }
}
