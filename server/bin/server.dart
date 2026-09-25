import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final livekitUrl = _required(env, 'LIVEKIT_URL');
  _required(env, 'LIVEKIT_API_KEY');
  _required(env, 'LIVEKIT_API_SECRET');
  final port = int.tryParse(env['SYNCWATCH_SERVER_PORT'] ?? '') ?? 8787;

  final router = Router()
    ..get('/health', (_) => _json({'ok': true, 'livekit_url': livekitUrl}));

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    port,
  );
  stdout.writeln('SyncWatch backend listening on port ' + server.port.toString());
}

String _required(DotEnv env, String key) {
  final value = env[key]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable: ' + key);
  }
  return value;
}

Response _json(Object body, [int statusCode = 200]) => Response(
      statusCode,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
