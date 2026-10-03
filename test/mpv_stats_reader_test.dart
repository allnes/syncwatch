import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:syncwatch/services/mpv_stats_reader.dart';

// Native integration coverage: supply the libmpv from a desktop release build.
// Ordinary unit tests remain usable on hosts without the native library.
void main() {
  final library = Platform.environment['SYNCWATCH_TEST_LIBMPV'];
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    if (library != null) MediaKit.ensureInitialized(libmpv: library);
  });

  test(
    'native snapshots survive concurrent reads and player disposal',
    () async {
      for (var cycle = 0; cycle < 5; cycle++) {
        final player = Player();
        final reader = MpvStatsReader(player);
        final snapshot = await reader.read(['mpv-version', 'missing-property']);
        expect(snapshot['mpv-version'], contains('mpv'));
        expect(snapshot['missing-property'], isEmpty);

        final pending = reader.read(['mpv-version']);
        expect(identical(pending, reader.read(['mpv-version'])), isTrue);
        // Player disposal must await the worker before releasing its native handle.
        final disposing = player.dispose();
        await pending;
        await disposing;
        expect(await reader.read(['mpv-version']), isEmpty);
        await reader.close();
      }
      // media_kit delays native destruction; let those callbacks actually run.
      await Future<void>.delayed(const Duration(seconds: 6));
    },
    skip: library == null
        ? 'Set SYNCWATCH_TEST_LIBMPV for native integration'
        : false,
  );
}
