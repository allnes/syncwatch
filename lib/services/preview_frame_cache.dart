import 'dart:typed_data';

/// A per-media LRU cache bounded by both encoded bytes and entry count.
class PreviewFrameCache {
  PreviewFrameCache({this.maxBytes = 8 * 1024 * 1024, this.maxEntries = 32});

  final int maxBytes;
  final int maxEntries;
  final _frames = <int, Uint8List>{};
  String? _mediaPath;
  int _byteCount = 0;

  int get length => _frames.length;
  int get byteCount => _byteCount;

  void selectMedia(String path) {
    if (_mediaPath == path) return;
    clear();
    _mediaPath = path;
  }

  Uint8List? operator [](int bucket) {
    final frame = _frames.remove(bucket);
    if (frame != null) _frames[bucket] = frame;
    return frame;
  }

  void operator []=(int bucket, Uint8List frame) {
    final previous = _frames.remove(bucket);
    _byteCount -= previous?.lengthInBytes ?? 0;
    if (frame.lengthInBytes > maxBytes || maxEntries <= 0) return;
    while (_frames.isNotEmpty &&
        (_frames.length >= maxEntries ||
            _byteCount + frame.lengthInBytes > maxBytes)) {
      _byteCount -= _frames.remove(_frames.keys.first)!.lengthInBytes;
    }
    _frames[bucket] = frame;
    _byteCount += frame.lengthInBytes;
  }

  void clear() {
    _frames.clear();
    _byteCount = 0;
  }
}
