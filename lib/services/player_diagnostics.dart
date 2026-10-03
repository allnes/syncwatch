import 'dart:typed_data';

/// Optional control surface for the separate desktop performance harness.
/// The ordinary application does not create one.
class PlayerDiagnostics {
  PlayerDiagnostics({
    this.legacyPreviewCapture = false,
    this.synchronousStats = false,
    this.onPreviewReady,
  });

  final bool legacyPreviewCapture;
  final bool synchronousStats;
  final Future<void> Function(int bucket, Uint8List frame)? onPreviewReady;
  Future<void> Function(double seconds)? requestPreview;
}
