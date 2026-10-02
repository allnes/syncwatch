import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/preview_thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [(1920, 1080), (1920, 800), (480, 640), (80, 60)]) {
    test('thumbnail preserves aspect and cover resolution for $size', () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFF4288CC), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.$1, size.$2);
      final original = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      final thumbnail = await resizePreviewThumbnail(
        original!.buffer.asUint8List(),
        width: 384,
        height: 216,
      );
      final codec = await ui.instantiateImageCodec(thumbnail);
      final decoded = await codec.getNextFrame();
      final result = decoded.image;
      expect(result.width, lessThanOrEqualTo(size.$1));
      expect(result.height, lessThanOrEqualTo(size.$2));
      expect(result.width / result.height, closeTo(size.$1 / size.$2, 0.01));
      if (size.$1 >= 384 && size.$2 >= 216) {
        expect(result.width >= 384 && result.height >= 216, isTrue);
        expect(result.width == 384 || result.height == 216, isTrue);
      }
      final pixels = await result.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels!.buffer.asUint8List().take(4), [0x42, 0x88, 0xCC, 0xFF]);
      result.dispose();
      codec.dispose();
    });
  }
}
