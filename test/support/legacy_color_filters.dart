// Rendering reference captured from player_screen.dart at eee5854.
// Keep this fixed: regression tests compare pixels, including intermediate clamps.
import 'dart:math' as math;
import 'package:flutter/material.dart';

Widget legacyColorFilters(
  Widget child,
  double videoSaturation,
  double videoHue,
  double videoContrast,
  double videoBrightness,
) {
  Widget result = child;

  final saturation = 1.0 + videoSaturation;
  final s = saturation;
  final ir = (1 - s) * 0.2126;
  final ig = (1 - s) * 0.7152;
  final ib = (1 - s) * 0.0722;

  result = ColorFiltered(
    colorFilter: ColorFilter.matrix(<double>[
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
    child: result,
  );

  final hue = videoHue * math.pi / 180.0;
  final cosH = math.cos(hue);
  final sinH = math.sin(hue);
  result = ColorFiltered(
    colorFilter: ColorFilter.matrix(<double>[
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
    child: result,
  );

  final contrast = 1.0 + videoContrast;
  final brightness = videoBrightness * 255.0;
  final translate = 128.0 * (1.0 - contrast) + brightness;
  result = ColorFiltered(
    colorFilter: ColorFilter.matrix(<double>[
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
    child: result,
  );

  return result;
}
