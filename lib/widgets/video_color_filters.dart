import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Cached, ordered color operations. Neutral settings need no compositing layer.
/// Do not combine the matrices: each operation clamps its own color output.
class VideoColorFilters {
  VideoColorFilters({
    required double videoSaturation,
    required double videoHue,
    required double videoContrast,
    required double videoBrightness,
  }) {
    if (videoSaturation != 0) {
      final saturation = 1.0 + videoSaturation;
      final s = saturation;
      final ir = (1 - s) * 0.2126;
      final ig = (1 - s) * 0.7152;
      final ib = (1 - s) * 0.0722;

      filters.add(
        ColorFilter.matrix(<double>[
          ir + s,
          ig,
          ib,
          0,
          0,
          ir,
          ig + s,
          ib,
          0,
          0,
          ir,
          ig,
          ib + s,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
      );
    }
    if (videoHue != 0) {
      final hue = videoHue * math.pi / 180.0;
      final cosH = math.cos(hue);
      final sinH = math.sin(hue);
      filters.add(
        ColorFilter.matrix(<double>[
          0.213 + cosH * 0.787 - sinH * 0.213,
          0.715 - cosH * 0.715 - sinH * 0.715,
          0.072 - cosH * 0.072 + sinH * 0.928,
          0,
          0,
          0.213 - cosH * 0.213 + sinH * 0.143,
          0.715 + cosH * 0.285 + sinH * 0.140,
          0.072 - cosH * 0.072 - sinH * 0.283,
          0,
          0,
          0.213 - cosH * 0.213 - sinH * 0.787,
          0.715 - cosH * 0.715 + sinH * 0.715,
          0.072 + cosH * 0.928 + sinH * 0.072,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
      );
    }
    if (videoContrast != 0 || videoBrightness != 0) {
      final contrast = 1.0 + videoContrast;
      final brightness = videoBrightness * 255.0;
      final translate = 128.0 * (1.0 - contrast) + brightness;
      filters.add(
        ColorFilter.matrix(<double>[
          contrast,
          0,
          0,
          0,
          translate,
          0,
          contrast,
          0,
          0,
          translate,
          0,
          0,
          contrast,
          0,
          translate,
          0,
          0,
          0,
          1,
          0,
        ]),
      );
    }
  }

  final List<ColorFilter> filters = [];

  Widget apply(Widget child) {
    var result = child;
    for (final filter in filters) {
      result = ColorFiltered(colorFilter: filter, child: result);
    }
    return result;
  }
}
