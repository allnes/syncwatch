import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/video_output_size.dart';

void main() {
  test('4K video fits the physical viewport including Retina density', () {
    expect(
      videoOutputSize(const Size(3840, 2160), const Size(960, 530), 2),
      const Size(1885, 1060),
    );
  });

  test('wide and portrait sources preserve their contain aspect ratio', () {
    expect(
      videoOutputSize(const Size(1920, 800), const Size(960, 530), 1),
      const Size(960, 400),
    );
    expect(
      videoOutputSize(const Size(1080, 1920), const Size(960, 530), 1),
      const Size(299, 530),
    );
  });

  test(
    'fullscreen and fractional scaling retain enough pixels without upscaling',
    () {
      expect(
        videoOutputSize(const Size(3840, 2160), const Size(3000, 2000), 2),
        const Size(3840, 2160),
      );
      expect(
        videoOutputSize(const Size(1920, 1080), const Size(800, 450), 1.25),
        const Size(1000, 563),
      );
    },
  );

  test('unavailable metadata and unbounded or hidden layouts are ignored', () {
    expect(videoOutputSize(Size.zero, const Size(960, 530), 2), isNull);
    expect(videoOutputSize(const Size(3840, 2160), Size.zero, 2), isNull);
    expect(videoOutputSize(const Size(3840, 2160), Size.infinite, 2), isNull);
    expect(
      videoOutputSize(const Size(3840, 2160), const Size(960, 530), double.nan),
      isNull,
    );
  });
}
