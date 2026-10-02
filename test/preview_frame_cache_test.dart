import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/preview_frame_cache.dart';

void main() {
  test('evicts least recently used frames within both limits', () {
    final cache = PreviewFrameCache(maxBytes: 10, maxEntries: 2);
    cache.selectMedia('first.mp4');
    cache[0] = Uint8List(4);
    cache[2] = Uint8List(4);
    expect(cache[0], isNotNull);
    cache[4] = Uint8List(5);
    expect(cache[2], isNull);
    expect(cache[0], isNotNull);
    expect(cache.byteCount, 9);
    cache[6] = Uint8List(9);
    expect(cache.length, 1);
    expect(cache.byteCount, 9);
  });

  test('same timestamp cannot return a frame from a different movie', () {
    final cache = PreviewFrameCache();
    cache.selectMedia('first.mp4');
    cache[10] = Uint8List(4);
    cache.selectMedia('second.mp4');
    expect(cache[10], isNull);
    expect(cache.byteCount, 0);
  });

  test('replacement and oversized frames do not exceed the budget', () {
    final cache = PreviewFrameCache(maxBytes: 10);
    cache[0] = Uint8List(8);
    cache[0] = Uint8List(3);
    expect(cache.byteCount, 3);
    cache[2] = Uint8List(11);
    expect(cache[2], isNull);
    expect(cache.byteCount, 3);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.byteCount, 0);
  });
}
