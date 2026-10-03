import 'dart:math' as math;
import 'dart:ui';

/// Render enough pixels for BoxFit.contain at the current display density.
/// Decoding stays at source resolution; only the output texture is resized.
Size? videoOutputSize(Size source, Size viewport, double pixelRatio) {
  if (!source.isFinite ||
      source.isEmpty ||
      !viewport.isFinite ||
      viewport.isEmpty ||
      !pixelRatio.isFinite ||
      pixelRatio <= 0) {
    return null;
  }
  final scale = math.min(
    1.0,
    math.min(
      viewport.width * pixelRatio / source.width,
      viewport.height * pixelRatio / source.height,
    ),
  );
  return Size(
    math
        .min(
          source.width,
          math.min(viewport.width * pixelRatio, source.width * scale),
        )
        .ceilToDouble(),
    math
        .min(
          source.height,
          math.min(viewport.height * pixelRatio, source.height * scale),
        )
        .ceilToDouble(),
  );
}
