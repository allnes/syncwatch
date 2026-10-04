import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// Run with the platform's actual app libmpv path. No windows or media required.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/check_mpv_properties.dart <libmpv>');
    exitCode = 64;
    return;
  }
  MediaKit.ensureInitialized(libmpv: arguments.single);
  const names = [
    'mpv-version',
    'video-sync',
    'autosync',
    'volume',
    'pause',
    'display-fps',
    'syncwatch-nonexistent-property',
  ];
  for (var cycle = 0; cycle < 5; cycle++) {
    final player = Player(configuration: const PlayerConfiguration(vo: 'null'));
    final native = player.platform as NativePlayer;
    final expected = await Future.wait(names.map(native.getProperty));
    for (var round = 0; round < 20; round++) {
      final actual = await Future.wait(
        names.map(native.getPropertyAsync),
      ).timeout(const Duration(seconds: 10));
      for (var index = 0; index < names.length; index++) {
        if (actual[index] != expected[index]) {
          throw StateError(
            '${names[index]}: ${actual[index]} != ${expected[index]}',
          );
        }
      }
    }
    // Attach handlers before disposal can settle requests with an error.
    final pending = List.generate(100, (_) {
      return native
          .getPropertyAsync('mpv-version')
          .then<void>(
            (value) {
              if (value != expected.first) throw StateError('Mismatched reply');
            },
            onError: (Object error) {
              if (error is! StateError) throw error;
            },
          );
    });
    final closing = player.dispose();
    await Future.wait([
      ...pending,
      closing,
    ]).timeout(const Duration(seconds: 10));
    try {
      await native.getPropertyAsync('mpv-version');
      throw AssertionError('Query after disposal succeeded');
    } on StateError {
      // Expected: no native access after disposal.
    }
  }
  // Exercise the package's delayed native destruction before process exit.
  await Future<void>.delayed(const Duration(seconds: 6));
  stdout.writeln('Async property parity, missing values and disposal: PASS');
  exit(0);
}
