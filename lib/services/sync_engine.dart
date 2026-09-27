abstract class SyncEngine {
  Future<void> connect();
  Future<void> setReady(bool ready);
  Future<void> start(String mediaId, Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> dispose();
}

class MockSyncEngine implements SyncEngine {
  @override
  Future<void> start(String mediaId, Duration position) async {}
  @override
  Future<void> connect() async {}

  @override
  Future<void> setReady(bool ready) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {
    // Synchronization uses an absolute target position.
    // Each client may use its own local skip interval safely.
  }

  @override
  Future<void> dispose() async {}
}
