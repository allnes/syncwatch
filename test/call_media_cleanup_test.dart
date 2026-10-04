import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/core/engine.dart';
import 'package:livekit_client/src/core/transport.dart';
import 'package:syncwatch/services/call_engine.dart';
import 'package:syncwatch/services/livekit_connection.dart';

class TestTransceiver implements rtc.RTCRtpTransceiver {
  TestTransceiver(this.id, this.actions, {this.pending, this.fail = false});
  final String id;
  final List<String> actions;
  final Completer<void>? pending;
  final bool fail;

  @override
  rtc.RTCRtpSender get sender => TestSender(id);

  @override
  Future<void> stop() async {
    actions.add('stop:$id');
    await pending?.future;
    if (fail) throw StateError('connection lost');
    actions.add('stopped:$id');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSender implements rtc.RTCRtpSender {
  TestSender(this.senderId);
  @override
  final String senderId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestPeerConnection implements rtc.RTCPeerConnection {
  List<rtc.RTCRtpTransceiver> currentTransceivers = [];
  int reads = 0;
  bool failRepeatedRead = false;
  @override
  Future<List<rtc.RTCRtpTransceiver>> getTransceivers() async {
    reads++;
    if (failRepeatedRead && reads > 1) throw StateError('stopped direction');
    return currentTransceivers;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestTransport implements Transport {
  TestTransport(this.pc);
  @override
  final rtc.RTCPeerConnection pc;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestEngine implements Engine {
  TestEngine(this.publisher);
  @override
  final Transport publisher;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestTrack implements LocalTrack {
  TestTrack(this.transceiver);
  @override
  final rtc.RTCRtpTransceiver? transceiver;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestPublication implements LocalTrackPublication {
  TestPublication(this.sid, this.source, this.track);
  @override
  final String sid;
  @override
  final TrackSource source;
  @override
  final LocalTrack? track;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestParticipant implements LocalParticipant {
  TestParticipant(this.actions);
  final List<String> actions;
  @override
  final trackPublications = <String, LocalTrackPublication>{};
  @override
  List<LocalTrackPublication<LocalVideoTrack>> get videoTrackPublications => [];

  @override
  Future<void> removePublishedTrack(
    String trackSid, {
    bool notify = true,
  }) async {
    actions.add('unpublish:$trackSid');
    trackPublications.remove(trackSid);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setMicrophoneEnabled ||
        invocation.memberName == #setCameraEnabled) {
      return Future<LocalTrackPublication?>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class TestRoom implements Room {
  TestRoom(this.localParticipant, this.engine);
  @override
  final Engine engine;
  @override
  final LocalParticipant localParticipant;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestConnection extends LiveKitConnection {
  TestConnection(this.testRoom) : super(backendUrl: 'http://unused.invalid');
  final Room testRoom;
  int disconnects = 0;
  @override
  Future<Room> connect({
    required String roomName,
    required String identity,
    required String participantName,
  }) async => testRoom;
  @override
  Future<void> disconnect() async => disconnects++;
}

void main() {
  late List<String> actions;
  late TestParticipant participant;
  late TestConnection connection;
  late LiveKitCallEngine engine;
  late TestPeerConnection peerConnection;
  setUp(() async {
    actions = [];
    participant = TestParticipant(actions);
    peerConnection = TestPeerConnection();
    connection = TestConnection(
      TestRoom(participant, TestEngine(TestTransport(peerConnection))),
    );
    engine = LiveKitCallEngine(
      connection: connection,
      roomName: 'cleanup-test',
      participantName: 'Test',
    );
    await engine.join();
  });

  void add(
    String sid,
    TrackSource source, {
    Completer<void>? pending,
    bool fail = false,
  }) {
    participant.trackPublications[sid] = TestPublication(
      sid,
      source,
      TestTrack(TestTransceiver(sid, actions, pending: pending, fail: fail)),
    );
  }

  test('waits for encoder shutdown before SDK unpublish negotiation', () async {
    final pending = Completer<void>();
    add('mic', TrackSource.microphone, pending: pending);
    add('camera', TrackSource.camera);
    add('screen', TrackSource.screenShareVideo);
    final cleanup = engine.stopCallMedia();
    await Future<void>.delayed(Duration.zero);
    expect(actions, ['stop:mic']);
    pending.complete();
    await cleanup;
    expect(actions, [
      'stop:mic',
      'stopped:mic',
      'unpublish:mic',
      'stop:camera',
      'stopped:camera',
      'unpublish:camera',
    ]);
    expect(participant.trackPublications.keys, ['screen']);
    expect(engine.room, same(connection.testRoom));
    expect(connection.disconnects, 0);
  });

  test(
    'a failed transceiver stop does not skip remaining media cleanup',
    () async {
      add('mic', TrackSource.microphone, fail: true);
      add('camera', TrackSource.camera);
      await engine.stopCallMedia();
      expect(actions, [
        'stop:mic',
        'unpublish:mic',
        'stop:camera',
        'stopped:camera',
        'unpublish:camera',
      ]);
      expect(participant.trackPublications, isEmpty);
      expect(connection.disconnects, 0);
    },
  );

  test(
    'repeat hangup is harmless and a later call retires its own senders',
    () async {
      add('first', TrackSource.camera);
      await engine.stopCallMedia();
      await engine.stopCallMedia();
      add('second', TrackSource.camera);
      participant.trackPublications['pending'] = TestPublication(
        'pending',
        TrackSource.microphone,
        TestTrack(null),
      );
      await engine.stopCallMedia();
      expect(actions, [
        'stop:first',
        'stopped:first',
        'unpublish:first',
        'stop:second',
        'stopped:second',
        'unpublish:second',
        'unpublish:pending',
      ]);
      expect(participant.trackPublications, isEmpty);
      expect(connection.disconnects, 0);
    },
  );
  test(
    'uses the negotiated transceiver matching the stable sender ID',
    () async {
      add('camera', TrackSource.camera, fail: true);
      final unrelated = TestTransceiver('other', actions);
      final negotiated = TestTransceiver('camera', actions);
      peerConnection.currentTransceivers = [unrelated, negotiated];
      await engine.stopCallMedia();
      expect(actions, ['stop:camera', 'stopped:camera', 'unpublish:camera']);
    },
  );
  test(
    'resolves all senders before any stopped direction can appear',
    () async {
      add('mic', TrackSource.microphone, fail: true);
      add('camera', TrackSource.camera, fail: true);
      peerConnection.failRepeatedRead = true;
      peerConnection.currentTransceivers = [
        TestTransceiver('mic', actions),
        TestTransceiver('camera', actions),
      ];
      await engine.stopCallMedia();
      expect(peerConnection.reads, 1);
      expect(actions, [
        'stop:mic',
        'stopped:mic',
        'unpublish:mic',
        'stop:camera',
        'stopped:camera',
        'unpublish:camera',
      ]);
    },
  );
}
