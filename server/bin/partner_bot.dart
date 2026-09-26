import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('server', defaultsTo: 'http://127.0.0.1:8787')
    ..addOption('room', defaultsTo: 'syncwatch-dev')
    ..addOption('identity', defaultsTo: 'partner-bot')
    ..addOption('name', defaultsTo: 'PartnerBot');
  final args = parser.parse(arguments);
  final server = args['server'] as String;

  final health = await http.get(Uri.parse(server + '/health'));
  if (health.statusCode != 200) {
    stderr.writeln('PartnerBot: backend unavailable: ' + health.body);
    exitCode = 1;
    return;
  }

  final tokenResponse = await http.post(
    Uri.parse(server + '/livekit/token'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'room_name': args['room'],
      'participant_identity': args['identity'],
      'participant_name': args['name'],
    }),
  );
  if (tokenResponse.statusCode != 200) {
    stderr.writeln('PartnerBot: token request failed: ' + tokenResponse.body);
    exitCode = 2;
    return;
  }

  final token = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
  stdout.writeln('PartnerBot token ready.');
  stdout.writeln('LiveKit: ' + (token['server_url'] as String));
  stdout.writeln('Room: ' + (token['room_name'] as String));
  stdout.writeln('Identity: ' + (token['participant_identity'] as String));
  stdout.writeln(
    'Token length: ${(token['participant_token'] as String).length}',
  );
}
