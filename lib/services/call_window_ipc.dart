import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _prefix = 'SYNCWATCH_CALL_V1 ';

String encodeCallWindowMessage(Map<String, dynamic> message) =>
    '$_prefix${jsonEncode(message)}';

/// The helper shares stdout with native/plugin diagnostics. Only consume our
/// framed messages; ordinary log lines and malformed messages are not actions.
Map<String, dynamic>? decodeCallWindowMessage(String line) {
  if (!line.startsWith(_prefix) || line.length > 4096) return null;
  try {
    final value = jsonDecode(line.substring(_prefix.length));
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

/// Check the actual exit future, independently of the UI's process reference.
Future<void> closeCallProcess(
  Process process, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    process.stdin.writeln(encodeCallWindowMessage({'type': 'close'}));
    await process.stdin.flush().timeout(timeout);
  } catch (_) {
    // The pipe can already be closed after a native crash.
  }
  try {
    await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill();
    await process.exitCode.timeout(timeout);
  } finally {
    unawaited(process.stdin.close().catchError((Object _) {}));
  }
}
