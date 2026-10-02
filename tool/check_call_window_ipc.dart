import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:syncwatch/services/call_window_ipc.dart';

/// Run in an interactive Windows session after building the release client:
/// dart run tool/check_call_window_ipc.dart build/windows/x64/runner/Release/syncwatch.exe
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Pass the path of the built SyncWatch executable.');
    exitCode = 64;
    return;
  }
  for (var cycle = 0; cycle < 3; cycle++) {
    final process = await Process.start(
      File(args.single).absolute.path,
      ['--call-process-diagnostic', '--call-ipc-stdio'],
    );
    final ready = Completer<void>();
    final output = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (decodeCallWindowMessage(line)?['type'] == 'ready' && !ready.isCompleted) {
            ready.complete();
          }
        });
    final errors = process.stderr.listen(stderr.add);
    try {
      await ready.future.timeout(const Duration(seconds: 15));
      process.stdin.writeln(encodeCallWindowMessage({
        'type': 'state', 'camera': false, 'microphone': false, 'active': true,
      }));
      await process.stdin.flush();
      if (cycle == 2) {
        // The helper must not survive its parent closing the command pipe.
        await process.stdin.close();
        await process.exitCode.timeout(const Duration(seconds: 5));
      } else {
        await closeCallProcess(process);
      }
      if (await process.exitCode != 0) throw StateError('Helper exited abnormally');
      stdout.writeln('PASS cycle=$cycle pid=${process.pid} ready/state/exit');
    } finally {
      process.kill();
      await output.cancel();
      await errors.cancel();
    }
  }
}
