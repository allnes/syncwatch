abstract class CallEngine {
  Future<void> join();
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> leave();
}

class MockCallEngine implements CallEngine {
  @override
  Future<void> join() async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> leave() async {}
}
