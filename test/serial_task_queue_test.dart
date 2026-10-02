import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/serial_task_queue.dart';

void main() {
  test(
    'cleanup waits for pending capture and runs after a failed publish',
    () async {
      final queue = SerialTaskQueue();
      final capture = Completer<void>();
      final events = <String>[];
      final start = queue.run(() async {
        events.add('capture');
        await capture.future;
        events.add('publish failed');
        throw StateError('test failure');
      });
      final failure = expectLater(start, throwsStateError);
      final stop = queue.run(() async => events.add('dispose'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['capture']);
      capture.complete();
      await failure;
      await stop;
      expect(events, ['capture', 'publish failed', 'dispose']);
    },
  );
}
