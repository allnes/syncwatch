import 'package:media_kit/media_kit.dart';

/// Waits for the paused preview decoder to finish the requested seek.
Future<void> seekPreviewFrame(Player player, Duration position) async {
  final native = player.platform;
  if (native is NativePlayer) {
    // A command reply can precede the actual seek: `seeking=no` may still
    // describe the previous frame. Wait for SEEK then PLAYBACK_RESTART.
    await native.seekAndWaitForFrame(position);
  } else {
    await player.seek(position);
    await Future<void>.delayed(const Duration(milliseconds: 90));
  }
}
