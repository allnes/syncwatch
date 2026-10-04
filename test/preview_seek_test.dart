import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:syncwatch/services/preview_seek.dart';

class PreviewNativePlayer implements NativePlayer {
  final frameReady = Completer<void>();
  Duration? requestedPosition;

  @override
  Future<void> seekAndWaitForFrame(
    Duration position, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    requestedPosition = position;
    return frameReady.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OtherPreviewPlayer implements PlatformPlayer {
  Duration? requestedPosition;

  @override
  Future<void> seek(Duration position) async {
    requestedPosition = position;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('preview waits for decoding beyond the old timeout', (
    tester,
  ) async {
    final native = PreviewNativePlayer();
    var ready = false;
    final result = seekPreviewFrame(
      Player(platformPlayer: native),
      const Duration(seconds: 20),
    ).then((_) => ready = true);
    await tester.pump(const Duration(seconds: 4));
    expect(native.requestedPosition, const Duration(seconds: 20));
    expect(ready, isFalse);
    native.frameReady.complete();
    await tester.pump();
    await result;
    expect(ready, isTrue);
  });

  test('native timeout propagates without capturing a stale frame', () async {
    final native = PreviewNativePlayer();
    final result = seekPreviewFrame(
      Player(platformPlayer: native),
      Duration.zero,
    );
    final check = expectLater(result, throwsA(isA<TimeoutException>()));
    native.frameReady.completeError(TimeoutException('Decoder stalled'));
    await check;
  });

  test('disposing a pending decoder propagates cancellation', () async {
    final native = PreviewNativePlayer();
    final result = seekPreviewFrame(
      Player(platformPlayer: native),
      Duration.zero,
    );
    final error = StateError('Disposed');
    final check = expectLater(result, throwsA(same(error)));
    native.frameReady.completeError(error);
    await check;
  });

  testWidgets('other platforms retain the existing seek delay', (tester) async {
    final other = OtherPreviewPlayer();
    var ready = false;
    final result = seekPreviewFrame(
      Player(platformPlayer: other),
      const Duration(seconds: 20),
    ).then((_) => ready = true);
    await tester.pump();
    expect(other.requestedPosition, const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 89));
    expect(ready, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await result;
    expect(ready, isTrue);
  });
}
