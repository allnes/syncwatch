import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decode at the visible preview resolution, preserving BoxFit.cover's aspect.
/// PNG keeps the decoded screenshot colors without another lossy JPEG pass.
Future<Uint8List> resizePreviewThumbnail(
  Uint8List frame, {
  required int width,
  required int height,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(frame);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (sourceWidth, sourceHeight) {
      final scale = math.min(
        1.0,
        math.max(width / sourceWidth, height / sourceHeight),
      );
      return ui.TargetImageSize(
        width: math.max(1, (sourceWidth * scale).ceil()),
        height: math.max(1, (sourceHeight * scale).ceil()),
      );
    },
  );
  try {
    final decoded = await codec.getNextFrame();
    try {
      final bytes = await decoded.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) throw StateError('Preview image encoding failed');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      decoded.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
