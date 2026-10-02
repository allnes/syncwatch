import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/widgets/video_color_filters.dart';

import 'support/legacy_color_filters.dart';

void main() {
  test(
    'neutral adjustments return the original video without filter layers',
    () {
      const video = SizedBox();
      final filters = VideoColorFilters(
        videoSaturation: 0,
        videoHue: 0,
        videoContrast: 0,
        videoBrightness: 0,
      );
      expect(identical(filters.apply(video), video), isTrue);
    },
  );

  for (final settings in <(double, double, double, double)>[
    (0, 0, 0, 0),
    (1, 0, 0, 0),
    (-1, 0, 0, 0),
    (0, 90, 0, 0),
    (0, -180, 0, 0),
    (0, 0, 0.8, -0.2),
    (0.8, 120, 0.7, -0.3),
    (-0.5, -75, -0.4, 0.2),
  ]) {
    testWidgets('preserves baseline pixels for $settings', (tester) async {
      const pattern = SizedBox(
        width: 256,
        height: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black,
                Colors.red,
                Colors.green,
                Colors.blue,
                Color(0x80804020),
                Colors.white,
              ],
            ),
          ),
        ),
      );
      Future<List<int>> pixels(Widget content) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(key: key, child: content),
            ),
          ),
        );
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return data!.buffer.asUint8List().toList();
          } finally {
            image.dispose();
          }
        }))!;
      }

      final expected = await pixels(
        legacyColorFilters(
          pattern,
          settings.$1,
          settings.$2,
          settings.$3,
          settings.$4,
        ),
      );
      final actual = await pixels(
        VideoColorFilters(
          videoSaturation: settings.$1,
          videoHue: settings.$2,
          videoContrast: settings.$3,
          videoBrightness: settings.$4,
        ).apply(pattern),
      );
      expect(actual, expected);
    });
  }
}
