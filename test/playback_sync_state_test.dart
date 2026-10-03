import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:syncwatch/services/sync_engine.dart';

class RecordingParticipant implements LocalParticipant {
  final messages = <Map<String, dynamic>>[];

  @override
  String get identity => 'local';

  @override
  Future<void> publishData(
    List<int> data, {
    bool? reliable,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    messages.add(jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingRoom implements Room {
  @override
  final RecordingParticipant localParticipant = RecordingParticipant();
  final emitter = EventsEmitter<RoomEvent>();

  @override
  EventsListener<RoomEvent> createListener({bool synchronized = false}) =>
      EventsListener(emitter, synchronized: synchronized);

  Future<void> receive(Map<String, dynamic> payload) async {
    emitter.streamCtrl.add(
      DataReceivedEvent(
        participant: null,
        topic: null,
        data: utf8.encode(jsonEncode(payload)),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RecordingRoom room;
  late LiveKitSyncEngine sync;
  late String session;

  setUp(() async {
    room = RecordingRoom();
    sync = LiveKitSyncEngine(
      room: room,
      mediaId: () => 'movie',
      position: () => const Duration(seconds: 120),
      isPlaying: () => true,
    );
    await sync.connect();
    await sync.start('movie', Duration.zero);
    session = room.localParticipant.messages.last['sessionId'] as String;
  });

  tearDown(() async {
    await sync.dispose();
    await room.emitter.dispose();
  });

  Future<void> remote(String type, int revision, {bool? playing}) =>
      room.receive({
        'kind': 'playback',
        'sessionId': session,
        'type': type,
        'revision': revision,
        'mediaId': 'movie',
        'positionMs': 120000,
        if (playing != null) 'playing': playing,
      });

  test('seek and state reply retain a pause received from the peer', () async {
    await remote('PAUSE', 2, playing: false);
    await sync.seekTo(const Duration(seconds: 30));
    expect(room.localParticipant.messages.last['playing'], isFalse);
    await room.receive({'kind': 'state_request'});
    expect(room.localParticipant.messages.last['type'], 'STATE');
    expect(room.localParticipant.messages.last['playing'], isFalse);
  });

  test('remote play replaces an earlier local pause', () async {
    await sync.pause();
    await remote('PLAY', 3, playing: true);
    await sync.seekTo(const Duration(seconds: 30));
    expect(room.localParticipant.messages.last['playing'], isTrue);
  });

  test('paused state response replaces local start state', () async {
    await remote('STATE', 2, playing: false);
    await sync.seekTo(const Duration(seconds: 30));
    expect(room.localParticipant.messages.last['playing'], isFalse);
  });

  test('stale and foreign commands cannot change advertised state', () async {
    await remote('PLAY', 5, playing: true);
    await remote('PAUSE', 4, playing: false);
    await room.receive({
      'kind': 'playback',
      'sessionId': 'foreign',
      'type': 'PAUSE',
      'revision': 6,
      'playing': false,
    });
    await sync.seekTo(const Duration(seconds: 30));
    expect(room.localParticipant.messages.last['playing'], isTrue);
  });
}
