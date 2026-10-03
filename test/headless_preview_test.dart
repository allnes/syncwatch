import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:syncwatch/services/mpv_stats_reader.dart';
import 'package:syncwatch/services/native_preview_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['SYNCWATCH_TEST_LIBMPV'];
  setUpAll(() {
    if (library != null) MediaKit.ensureInitialized(libmpv: library);
  });

  test(
    'headless previews open and seek at the requested color without a surface',
    () async {
      final player = Player(
        configuration: const PlayerConfiguration(vo: 'null', muted: true),
      );
      final stats = MpvStatsReader(player);
      try {
        final native = player.platform as NativePlayer;
        await configureNativePreviewDecoder(native);
        await player.setAudioTrack(AudioTrack.no());
        await player.open(
          Media(
            File('test/support/preview_colors.mp4').absolute.uri.toString(),
            start: const Duration(milliseconds: 1500),
          ),
          play: false,
        );
        if (player.state.duration == Duration.zero) {
          await player.stream.duration
              .firstWhere((duration) => duration > Duration.zero)
              .timeout(const Duration(seconds: 5));
        }
        var firstFrame = true;
        for (final (milliseconds, rgb) in [
          (1500, [0, 255, 0]),
          (500, [255, 0, 0]),
          (1500, [0, 255, 0]),
          (2500, [0, 0, 255]),
          (500, [255, 0, 0]),
        ]) {
          if (!firstFrame) {
            await player.seek(Duration(milliseconds: milliseconds));
          }
          firstFrame = false;
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (true) {
            final values = await stats.read([
              'seeking',
              'video-out-params',
              'vo',
            ]);
            expect(values['vo'], 'null');
            if (values['seeking'] == 'no' &&
                values['video-out-params']!.isNotEmpty) {
              break;
            }
            expect(DateTime.now().isBefore(deadline), isTrue);
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final bytes = await capturePreviewThumbnail(
            player,
            width: 32,
            height: 18,
          );
          expect(bytes, isNotNull);
          final codec = await ui.instantiateImageCodec(bytes!);
          final image = (await codec.getNextFrame()).image;
          try {
            expect((image.width, image.height), (32, 18));
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final center = (9 * image.width + 16) * 4;
            final snapshot = await stats.read([
              'time-pos',
              'hwdec-current',
              'video-out-params',
            ]);
            for (var channel = 0; channel < 3; channel++) {
              expect(
                rgba[center + channel],
                closeTo(rgb[channel], 5),
                reason:
                    'target=$milliseconds pixel=${rgba.sublist(center, center + 4)} '
                    'native=$snapshot',
              );
            }
            expect(rgba[center + 3], 255);
          } finally {
            image.dispose();
            codec.dispose();
          }
        }
      } finally {
        await player.dispose();
        await Future<void>.delayed(const Duration(seconds: 6));
      }
      expect(await stats.read(['vo']), isEmpty);
    },
    skip: library == null
        ? 'Set SYNCWATCH_TEST_LIBMPV for native integration'
        : false,
  );
}
