import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import 'services/livekit_connection.dart';

class LiveKitTestPeerApp extends StatefulWidget {
  const LiveKitTestPeerApp({super.key});

  @override
  State<LiveKitTestPeerApp> createState() => _LiveKitTestPeerAppState();
}

class _LiveKitTestPeerAppState extends State<LiveKitTestPeerApp> {
  final connection =
      LiveKitConnection(backendUrl: 'http://127.0.0.1:8787');
  Room? room;
  String status = 'Connecting…';
  String participants = '';
  final List<String> events = <String>[];
  final Set<String> remoteMovieIds = <String>{};
  final List<Map<String, String>> testLibrary = const [
    {'movieId': 'alien 1979 directors cut', 'fingerprint': '6994000:1920×1080'},
    {'movieId': 'dune 2021 2160p hevc', 'fingerprint': '9326000:3840×2160'},
  ];
  EventsListener<RoomEvent>? roomEvents;
  int playbackRevision = 0;
  String? playbackSessionId;
  String playbackMediaId = '';
  int playbackPositionMs = 0;
  bool playbackPlaying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      final connectedRoom = await connection.connect(
        roomName: 'syncwatch-dev',
        identity: 'partner-bot',
        participantName: 'PartnerBot',
      );
      connectedRoom.addListener(_refresh);
      roomEvents = connectedRoom.createListener()
        ..on<DataReceivedEvent>((event) {
        try {
          final decoded = utf8.decode(event.data);
          final payload = jsonDecode(decoded);
          if (payload is Map<String, dynamic> &&
              payload['kind'] == 'library_request') {
            unawaited(connectedRoom.localParticipant?.publishData(
              utf8.encode(jsonEncode({
                'kind': 'library',
                'items': testLibrary,
                'sentAtMs': DateTime.now().millisecondsSinceEpoch,
              })),
              reliable: true,
            ));
            debugPrint('[SyncWatch][TEST_PEER] TX library response items=${testLibrary.length}');
          }
          if (payload is Map<String, dynamic> &&
              payload['kind'] == 'playback') {
            final type = payload['type'];
            final session = payload['sessionId'];
            final revision = payload['revision'];
            if (session is String && revision is int) {
              if (type == 'START' || type == 'STATE') {
                playbackSessionId = session;
                playbackRevision = revision;
              } else if (session == playbackSessionId &&
                  revision > playbackRevision) {
                playbackRevision = revision;
              }
              final media = payload['mediaId'];
              final position = payload['positionMs'];
              final playing = payload['playing'];
              if (media is String) playbackMediaId = media;
              if (position is int) playbackPositionMs = position;
              if (playing is bool) playbackPlaying = playing;
              if (type == 'END' && session == playbackSessionId) {
                playbackSessionId = null;
              }
            }
          }
          if (payload is Map<String, dynamic> && payload['kind'] == 'state_request') {
            final session = playbackSessionId;
            if (session != null) {
              unawaited(connectedRoom.localParticipant?.publishData(
                utf8.encode(jsonEncode({
                  'kind': 'playback',
                  'type': 'STATE',
                  'sessionId': session,
                  'revision': ++playbackRevision,
                  'mediaId': playbackMediaId,
                  'positionMs': playbackPositionMs,
                  'playing': playbackPlaying,
                  'sentAtMs': DateTime.now().millisecondsSinceEpoch,
                })),
                reliable: true,
              ));
            }
          }
          if (payload is Map<String, dynamic> && payload['kind'] == 'library') {
            final items = payload['items'];
            if (items is List) {
              remoteMovieIds
                ..clear()
                ..addAll(items.whereType<Map>().map((item) => item['movieId']).whereType<String>());
            }
          }
          if (!mounted) return;
          debugPrint('[SyncWatch][TEST_PEER] RX $decoded');
          setState(() {
            events.insert(0, decoded);
            if (events.length > 8) events.removeLast();
          });
        } catch (_) {}
      });
      room = connectedRoom;
      await connectedRoom.localParticipant?.publishData(
        utf8.encode(jsonEncode({
          'kind': 'library',
          'items': testLibrary,
          'sentAtMs': DateTime.now().millisecondsSinceEpoch,
        })),
        reliable: true,
      );
      debugPrint('[SyncWatch][TEST_PEER] TX library items=${testLibrary.length}');
      debugPrint('[SyncWatch][TEST_PEER] CONNECTED room=syncwatch-dev identity=partner-bot');
      _refresh();
    } catch (error) {
      if (mounted) setState(() => status = 'ERROR: $error');
    }
  }

  void _refresh() {
    if (!mounted || room == null) return;
    final remote = room!.remoteParticipants.values
        .map((participant) => participant.identity)
        .join(', ');
    setState(() {
      status = 'CONNECTED';
      participants = remote.isEmpty ? 'No remote participants yet' : remote;
    });
  }

  @override
  void dispose() {
    room?.removeListener(_refresh);
    roomEvents?.dispose();
    roomEvents = null;
    unawaited(connection.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF17131F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SyncWatch LiveKit Test Peer',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
                const SizedBox(height: 20),
                Text(status, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Text(
                  'Remote: $participants',
                  style: const TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Text('Remote library: ${remoteMovieIds.length} movies', style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 12),
                const Text('Data channel', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                for (final event in events)
                  Text(event, style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
