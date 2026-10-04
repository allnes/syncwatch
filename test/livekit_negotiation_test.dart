// Regression coverage for the pinned SDK patch prepared by the build helpers.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/core/transport.dart';
import 'package:livekit_client/src/internal/types.dart';

const sdp = 'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';

class Peer implements rtc.RTCPeerConnection {
  var state = rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  final remoteReadStarted = Completer<void>();
  final remoteRead = Completer<rtc.RTCSessionDescription?>();
  int offers = 0;
  int answers = 0;
  int activeOffers = 0;
  int maxActiveOffers = 0;
  Completer<void>? offerGate;
  bool failOffer = false;
  int iceRestarts = 0;
  bool closed = false;
  bool disposed = false;
  Map<String, dynamic>? lastOfferOptions;

  @override
  Future<void> restartIce() async {
    iceRestarts++;
  }

  @override
  Future<List<rtc.RTCRtpSender>> getSenders() async => [];

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<rtc.RTCSignalingState?> getSignalingState() async => state;

  @override
  Future<rtc.RTCSessionDescription?> getRemoteDescription() {
    if (!remoteReadStarted.isCompleted) remoteReadStarted.complete();
    return remoteRead.future;
  }

  @override
  Future<void> setRemoteDescription(rtc.RTCSessionDescription value) async {
    answers++;
    state = rtc.RTCSignalingState.RTCSignalingStateStable;
  }

  @override
  Future<rtc.RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    offers++;
    lastOfferOptions = constraints;
    activeOffers++;
    if (activeOffers > maxActiveOffers) maxActiveOffers = activeOffers;
    try {
      await offerGate?.future;
      if (failOffer) {
        failOffer = false;
        throw StateError('native offer failed');
      }
      return rtc.RTCSessionDescription(sdp, 'offer');
    } finally {
      activeOffers--;
    }
  }

  @override
  Future<void> setLocalDescription(rtc.RTCSessionDescription value) async {
    state = rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter &&
        const {
          Symbol('onRenegotiationNeeded='),
          Symbol('onIceCandidate='),
          Symbol('onConnectionState='),
          Symbol('onIceConnectionState='),
          Symbol('onTrack='),
        }.contains(invocation.memberName)) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test(
    'a new track is negotiated when the preceding answer arrives during a remote-description read',
    () async {
      final peer = Peer();
      final transport = await Transport.create(
        (_, [__ = const <String, dynamic>{}]) async => peer,
        connectOptions: const ConnectOptions(),
      );
      final sent = <rtc.RTCSessionDescription>[];
      transport.onOffer = sent.add;

      // A microphone offer is in flight. Publishing the camera requests another
      // offer while the native peer is processing the microphone answer.
      final request = transport.createAndSendOffer();
      await peer.remoteReadStarted.future.timeout(const Duration(seconds: 2));
      final answer = transport.setRemoteDescription(
        rtc.RTCSessionDescription(sdp, 'answer'),
      );
      await Future<void>.delayed(Duration.zero);
      peer.remoteRead.complete(rtc.RTCSessionDescription(sdp, 'answer'));
      await Future.wait([request, answer]);
      await Future<void>.delayed(Duration.zero);

      expect(peer.answers, 1);
      expect(
        sent.length,
        1,
        reason: 'The new camera needs an offer after the previous answer.',
      );
      expect(peer.offers, 1);
    },
  );

  test(
    'overlapping publish requests never create simultaneous native offers',
    () async {
      final peer = Peer()
        ..state = rtc.RTCSignalingState.RTCSignalingStateStable
        ..offerGate = Completer<void>();
      peer.remoteRead.complete(rtc.RTCSessionDescription(sdp, 'answer'));
      final transport = await Transport.create(
        (_, [__ = const <String, dynamic>{}]) async => peer,
        connectOptions: const ConnectOptions(),
      );
      final sent = <rtc.RTCSessionDescription>[];
      transport.onOffer = sent.add;
      final first = transport.createAndSendOffer();
      await Future<void>.delayed(Duration.zero);
      final second = transport.createAndSendOffer();
      await Future<void>.delayed(Duration.zero);
      peer.offerGate!.complete();
      await Future.wait([first, second]);
      await transport.setRemoteDescription(
        rtc.RTCSessionDescription(sdp, 'answer'),
      );
      expect(peer.maxActiveOffers, 1);
      expect(sent.length, 2);
    },
  );

  test(
    'a failed native offer does not block the following publish request',
    () async {
      final peer = Peer()
        ..state = rtc.RTCSignalingState.RTCSignalingStateStable
        ..failOffer = true;
      final transport = await Transport.create(
        (_, [__ = const <String, dynamic>{}]) async => peer,
        connectOptions: const ConnectOptions(),
      );
      final sent = <rtc.RTCSessionDescription>[];
      transport.onOffer = sent.add;
      final first = transport.createAndSendOffer();
      final failed = expectLater(first, throwsStateError);
      final second = transport.createAndSendOffer();
      await Future.wait([failed, second]);
      expect(sent.length, 1);
      expect(peer.offers, 2);
    },
  );
  test('ICE restart retains native restart and offer options', () async {
    final peer = Peer();
    peer.remoteRead.complete(rtc.RTCSessionDescription(sdp, 'answer'));
    final transport = await Transport.create(
      (_, [__ = const <String, dynamic>{}]) async => peer,
      connectOptions: const ConnectOptions(),
    );
    final sent = <rtc.RTCSessionDescription>[];
    transport.onOffer = sent.add;
    await transport.createAndSendOffer(const RTCOfferOptions(iceRestart: true));
    expect(peer.answers, 1);
    expect(peer.iceRestarts, 1);
    expect(peer.lastOfferOptions, {'iceRestart': true});
    expect(sent.length, 1);
  });

  test('a queued publication does not start after disposal', () async {
    final peer = Peer()
      ..state = rtc.RTCSignalingState.RTCSignalingStateStable
      ..offerGate = Completer<void>();
    final transport = await Transport.create(
      (_, [__ = const <String, dynamic>{}]) async => peer,
      connectOptions: const ConnectOptions(),
    );
    transport.onOffer = (_) {};
    final first = transport.createAndSendOffer();
    await Future<void>.delayed(Duration.zero);
    final queued = transport.createAndSendOffer();
    await transport.dispose();
    expect(peer.closed, isTrue);
    expect(peer.disposed, isTrue);
    peer.offerGate!.complete();
    await Future.wait([first, queued]);
    expect(peer.offers, 1);
  });
}
