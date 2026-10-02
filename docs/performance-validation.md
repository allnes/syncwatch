# Media resource validation

## Baseline (2026-10-02)

Source: `eee5854`. Test machine: Windows 11, Intel i7-12700,
16 GB RAM, Intel UHD 770. Flutter 3.47.6 / Dart 3.13.5, release build.
Use the same resolved dependency lockfile for the comparison build.

The isolated test environment uses local LiveKit 1.13.7 and the repository's
token server. The test participant publishes the LiveKit CLI demo video.
Test media: [Sintel trailer](https://media.w3.org/2010/05/sintel/trailer.mp4),
52 seconds. No personal media or production credentials are used.

Verified before changes:

- `flutter analyze lib`: passed.
- Backend `dart analyze --fatal-infos`: passed.
- `flutter build windows --release`: passed after generating the Windows host
  and running `scripts/enable_multiview_windows.ps1`.
- Library scan, metadata, movie playback, pause, seek, return to library, and
  retained playback session work in the Windows UI.
- Room connection and outgoing playback messages reach the test participant.

Baseline limitations and findings:

- Windows reports no physical camera. Starting the call does not open the call
  window in this environment. Full bidirectional camera/audio operation is
  therefore **not yet verified**.
- Timeline preview produces a black thumbnail in the observed baseline run.
- The active helper is the diagnostic call window; it has no video renderer.
- Code inspection finds that call shutdown clears `callWindowProcess` before
  checking it, so its forced-termination fallback never runs. Its polling timer
  also survives normal call shutdown and screen disposal.
- Preview disposal can race an in-flight screenshot, and cached bucket numbers
  can refer to a previously selected movie.
- The test build uses the dependency's stock WebRTC DLL. Validation of the
  custom audio-isolation patch remains a separate native-build check.

## Comparison procedure

Run release builds sequentially, at the same window size and media position.
Record process private bytes, working set, CPU-time delta, handles, and threads
for playback, timeline hover, call activity, and teardown. Include all helper
processes. Do not interpret isolated startup samples as an optimization result.

After every change, rerun affected regression tests and analysis. Before final
acceptance, repeat the UI scenarios, synchronization, repeated call start/stop,
and preview disposal. Record unsupported scenarios explicitly rather than
claiming an end-to-end pass.
