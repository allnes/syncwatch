import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/native_preview_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('raw preview respects padded BGRA rows and never upscales', () async {
    final pixels = Uint8List.fromList([
      0xCC,
      0x88,
      0x42,
      255,
      0xCC,
      0x88,
      0x42,
      255,
      0,
      255,
      0,
      255,
      0xCC,
      0x88,
      0x42,
      255,
      0xCC,
      0x88,
      0x42,
      255,
      0,
      255,
      0,
      255,
    ]);
    final png = await encodeRawPreviewThumbnail(
      pixels,
      sourceWidth: 2,
      sourceHeight: 2,
      rowBytes: 12,
      width: 384,
      height: 216,
    );
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    try {
      expect((frame.image.width, frame.image.height), (2, 2));
      final result = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      for (var offset = 0; offset < result.length; offset += 4) {
        expect(result.sublist(offset, offset + 4), [0x42, 0x88, 0xCC, 255]);
      }
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });
}
