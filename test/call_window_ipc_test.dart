import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/call_window_ipc.dart';

class _TestProcess implements Process {
  _TestProcess({required this.cooperative}) {
    input = StreamController<List<int>>();
    stdin = IOSink(input.sink);
    input.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        if (cooperative && decodeCallWindowMessage(line)?['type'] == 'close') {
          exited.complete(0);
        }
      },
    );
  }
  final bool cooperative;
  late final StreamController<List<int>> input;
  @override
  late final IOSink stdin;
  final exited = Completer<int>();
  int kills = 0;
  @override
  Future<int> get exitCode => exited.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    if (!exited.isCompleted) exited.complete(1);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('framing preserves ordered actions and ignores native logs', () async {
    final bytes = utf8.encode(
      [
        'native log',
        encodeCallWindowMessage({'type': 'action', 'value': 'camera_off'}),
        encodeCallWindowMessage({'type': 'action', 'value': 'hangup'}),
        '',
      ].join('\n'),
    );
    final decoded = await Stream.fromIterable(bytes.map((b) => [b]))
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(decodeCallWindowMessage)
        .where((message) => message != null)
        .toList();
    expect(decoded.map((message) => message!['value']), [
      'camera_off',
      'hangup',
    ]);
    expect(decodeCallWindowMessage('SYNCWATCH_CALL_V1 broken'), isNull);
    expect(decodeCallWindowMessage('SYNCWATCH_CALL_V1 []'), isNull);
  });

  for (final cooperative in [true, false]) {
    test(
      'shutdown releases a ${cooperative ? "responsive" : "stuck"} helper',
      () async {
        final process = _TestProcess(cooperative: cooperative);
        await closeCallProcess(
          process,
          timeout: const Duration(milliseconds: 20),
        );
        expect(process.exited.isCompleted, isTrue);
        expect(process.kills, cooperative ? 0 : 1);
      },
    );
  }
}
