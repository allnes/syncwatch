import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:syncwatch/services/call_engine.dart';
import 'package:syncwatch/services/livekit_connection.dart';

class RecordingConnection extends LiveKitConnection {
  RecordingConnection() : super(backendUrl: 'http://unused.invalid');

  final identities = <String>[];

  @override
  Future<Room> connect({
    required String roomName,
    required String identity,
    required String participantName,
  }) async {
    identities.add(identity);
    return EmptyRoom();
  }

  @override
  Future<void> disconnect() async {}
}

class EmptyRoom implements Room {
  @override
  LocalParticipant? get localParticipant => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LiveKitCallEngine client(RecordingConnection connection, {String? identity}) =>
    LiveKitCallEngine(
      connection: connection,
      roomName: 'syncwatch-dev',
      participantName: 'SyncWatch User',
      identity: identity,
    );

void main() {
  test(
    'two ordinary clients join with distinct participant identities',
    () async {
      final first = RecordingConnection();
      final second = RecordingConnection();
      final firstClient = client(first);
      final secondClient = client(second);

      await firstClient.join();
      await secondClient.join();

      expect(first.identities.single, isNot(second.identities.single));
      for (final identity in [...first.identities, ...second.identities]) {
        expect(identity, matches(RegExp(r'^syncwatch-user-[0-9a-f]{32}$')));
      }
      await firstClient.leave();
      await secondClient.leave();
    },
  );

  test(
    'rejoin retains identity and an already joined client does not rejoin',
    () async {
      final connection = RecordingConnection();
      final engine = client(connection);

      await engine.join();
      await engine.join();
      expect(connection.identities, hasLength(1));
      await engine.leave();
      await engine.join();

      expect(connection.identities, hasLength(2));
      expect(connection.identities.last, connection.identities.first);
      await engine.leave();
    },
  );

  test('an explicit participant identity is preserved', () async {
    final connection = RecordingConnection();
    final engine = client(connection, identity: 'existing-client');
    await engine.join();

    expect(connection.identities, ['existing-client']);
    await engine.leave();
  });
}
