import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final livekitUrl = _required(env, 'LIVEKIT_URL');
  final apiKey = _required(env, 'LIVEKIT_API_KEY');
  final apiSecret = _required(env, 'LIVEKIT_API_SECRET');
  final port = int.tryParse(env['SYNCWATCH_SERVER_PORT'] ?? '') ?? 8787;

  final router = Router()
    ..get('/health', (_) => _json({'ok': true, 'livekit_url': livekitUrl}))
    ..post('/livekit/token', (Request request) async {
      Map<String, dynamic> body;
      try {
        body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        return _json({'error': 'invalid_json'}, 400);
      }

      final roomName = (body['room_name'] as String? ?? '').trim();
      final identity = (body['participant_identity'] as String? ?? '').trim();
      final participantName =
          (body['participant_name'] as String? ?? identity).trim();
      if (roomName.isEmpty || identity.isEmpty) {
        return _json(
          {'error': 'room_name_and_participant_identity_required'},
          400,
        );
      }

      final token = JWT(
        {
          'name': participantName,
          'video': {
            'roomJoin': true,
            'room': roomName,
            'canPublish': true,
            'canSubscribe': true,
            'canPublishData': true,
          },
        },
        issuer: apiKey,
        subject: identity,
      ).sign(
        SecretKey(apiSecret),
        expiresIn: const Duration(hours: 2),
      );

      return _json({
        'server_url': livekitUrl,
        'participant_token': token,
        'room_name': roomName,
        'participant_identity': identity,
        'participant_name': participantName,
      });
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    port,
  );
  stdout.writeln('SyncWatch backend listening on port ${server.port}');
}

String _required(DotEnv env, String key) {
  final value = env[key]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable: $key');
  }
  return value;
}

Response _json(Object body, [int statusCode = 200]) => Response(
      statusCode,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
