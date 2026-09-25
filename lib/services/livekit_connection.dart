import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

class LiveKitConnection {
  LiveKitConnection({required this.backendUrl});

  final String backendUrl;
  Room? _room;

  Room? get room => _room;
  bool get connected => _room != null;

  Future<Room> connect({
    required String roomName,
    required String identity,
    required String participantName,
  }) async {
    await disconnect();
    final response = await http.post(
      Uri.parse(backendUrl + '/livekit/token'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'room_name': roomName,
        'participant_identity': identity,
        'participant_name': participantName,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('LiveKit token request failed: ' + response.body);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final room = Room();
    await room.connect(
      payload['server_url'] as String,
      payload['participant_token'] as String,
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _room = room;
    return room;
  }

  Future<void> disconnect() async {
    final room = _room;
    _room = null;
    if (room == null) return;
    await room.disconnect();
    await room.dispose();
  }
}
