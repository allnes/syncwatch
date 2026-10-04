import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:syncwatch/services/preview_seek.dart';

class PreviewNativePlayer implements NativePlayer {
  String seeking = 'yes';
  Duration? requestedPosition;
  String? observedProperty;
  Future<void> Function(String)? listener;
  Future<void> Function()? onObserve;
  bool unobserved = false;

  @override
  Future<void> seek(Duration duration, {bool synchronized = true}) async {
    requestedPosition = duration;
  }

  @override
  Future<void> observeProperty(
    String property,
    Future<void> Function(String) callback, {
    bool waitForInitialization = true,
  }) async {
    observedProperty = property;
    listener = callback;
    await onObserve?.call();
  }

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async => seeking;

  @override
  Future<void> unobserveProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    unobserved = true;
    listener = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('slow decoder cannot expose its previous frame', (tester) async {
    final native = PreviewNativePlayer();
    var ready = false;
    final result = seekPreviewFrame(
      Player(platformPlayer: native),
      const Duration(seconds: 20),
    ).then((_) => ready = true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(native.requestedPosition, const Duration(seconds: 20));
    expect(native.observedProperty, 'seeking');
    expect(ready, isFalse);
    native.seeking = 'no';
    await native.listener!('no');
    await tester.pump();
    await result;
    expect(ready, isTrue);
    expect(native.unobserved, isTrue);
  });

  test('already finished seek does not require another event', () async {
    final native = PreviewNativePlayer()..seeking = 'no';
    await seekPreviewFrame(Player(platformPlayer: native), Duration.zero);
    expect(native.unobserved, isTrue);
  });

  test('completion during observer registration is not lost', () async {
    final native = PreviewNativePlayer();
    native.onObserve = () async {
      native.seeking = 'no';
      await native.listener!('no');
    };
    await seekPreviewFrame(Player(platformPlayer: native), Duration.zero);
    expect(native.unobserved, isTrue);
  });

  testWidgets('stalled seek fails and releases its observer', (tester) async {
    final native = PreviewNativePlayer();
    final result = seekPreviewFrame(
      Player(platformPlayer: native),
      const Duration(seconds: 40),
    );
    final check = expectLater(result, throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await check;
    expect(native.unobserved, isTrue);
  });
}
