import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Waits for the paused preview decoder to finish the requested exact seek.
Future<void> seekPreviewFrame(Player player, Duration position) async {
  await player.seek(position);
  final native = player.platform;
  if (native is! NativePlayer) {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    return;
  }

  final ready = Completer<void>();
  await native.observeProperty('seeking', (value) async {
    if (value == 'no' && !ready.isCompleted) ready.complete();
  });
  try {
    // Register before reading: completion between these operations must not
    // leave us waiting for a change that has already happened.
    if (await native.getProperty('seeking') != 'no') {
      await ready.future.timeout(const Duration(seconds: 3));
    }
  } finally {
    await native.unobserveProperty('seeking');
  }
}
