import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('server', defaultsTo: 'http://127.0.0.1:8787')
    ..addOption('room', defaultsTo: 'syncwatch-dev');
  final args = parser.parse(arguments);
  final server = args['server'] as String;
  final response = await http.get(Uri.parse(server + '/health'));
  if (response.statusCode != 200) {
    stderr.writeln('PartnerBot: backend unavailable: ' + response.body);
    exitCode = 1;
    return;
  }
  stdout.writeln('PartnerBot: backend is ready.');
  stdout.writeln('PartnerBot room: ' + (args['room'] as String));
}
