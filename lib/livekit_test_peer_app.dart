import 'dart:async';

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
      room = connectedRoom;
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
