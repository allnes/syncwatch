# Media resource validation

Latest: [surface-free preview comparison and output-drop audit](measurements/2026-10-03/round3/README.md)
records faster previews, lower transient memory, and a 93-action camera/call
stress run. Decoder drops remain zero, but Windows video-output drops and
restart/resize stalls are still unresolved; both counters are now reported.

Previous: [4K60 camera/call resize and preview comparison](measurements/2026-10-03/round2/README.md)
records the native GPU-surface leak fix, asynchronous mpv health reads, and raw
preview capture, including a five-minute run with 75 actions and explicit limits.

Follow-up: [camera + call + 1080p movie comparison](measurements/2026-10-02/combined/README.md)
now covers two clients exchanging real audio/video, playback synchronization,
and repeated media restarts. It records a 14.1% private-memory reduction and an
unresolved native WebRTC crash from an earlier prototype. The earlier playback
measurements and their narrower scope are retained below.

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
- Incoming `START` commands sent through LiveKit RoomService reach the player
  and restart playback at the requested position.

Baseline limitations and findings:

- Windows reports no physical camera. Starting the call does not open the call
  window in this environment. Full bidirectional camera/audio operation is
  therefore **not yet verified**.
- After that failed call, the LiveKit participant still has a published,
  unmuted `MICROPHONE` (`audio/opus`) track while the UI says the call has not
  started. This confirms a capture/publication leak in the baseline.
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

## Implemented changes and checks

- Neutral color settings add no color-filter layers; non-neutral operations
  retain their order and intermediate clamping. Eight raster comparisons
  against the original implementation are pixel-identical.
- Preview images are decoded to the physical display size, with preserved
  aspect ratio; the LRU cache is bounded to 32 entries and 8 MiB. The separate
  preview player's demuxer budget is 4 MiB, with audio disabled. Main playback
  buffering and camera quality are unchanged.
- Position ticks rebuild the timeline only. Preview motion/frame updates
  rebuild the preview overlay only.
- Native screenshot work completes before preview decoder disposal; media
  changes invalidate cached thumbnails immediately.
- Call device mutations are serialized. Failed startup releases published
  media, and shutdown waits for actual process exit, with a termination fallback.
- Normal call windows use framed stdio events instead of three disk-polling
  timers. The standalone diagnostic launch retains its legacy file interface.

Verification of the exact repository sources at `ab0cdc6`: 20 automated tests
passed, `flutter analyze lib test tool` passed, the changed application/test
files passed `dart format --output=none --set-exit-if-changed`, and the Windows
release build passed.
The native helper test `dart run tool/check_call_window_ipc.dart <exe>` passed
three cycles in an interactive Windows session, including parent-pipe EOF.
The helper reported ready, was sent a state message, and exited with code 0
each time; no helper processes remained afterward. This checks transport and
lifecycle, not camera rendering or the visual state of its controls.

The failed-start scenario was repeated twice on Windows after the change. In
both cases, logs show the microphone publication being removed after camera
creation fails; LiveKit RoomService reports an active participant with **zero
published tracks**. The baseline retained an unmuted microphone in this case.

Use `scripts/measure_windows_resources.ps1 -ProcessIds <pid> -Seconds 30
-OutputPath <file.csv> -IncludeGpu` for CPU, RAM, and GPU samples. Include the
main and helper PIDs when a call is active. The companion `<file>-gpu.csv`
preserves individual GPU adapter/engine counters. Without `-IncludeGpu`, GPU
fields stay empty; this mode was checked separately on Windows.

GPU sampling uses a continuous Windows PDH session at one-second intervals.
Engine categories and the overall process value use the busiest engine, not
an addition of simultaneous engines, following [Microsoft's interpretation](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/).
Shared GPU memory is reported separately from process private bytes; do not
add them together as an estimate of physical RAM. CPU is expressed as a
percentage of one logical core; divide by 20 on this test machine to compare
with Task Manager's whole-machine percentage. English performance-counter
names are required by the script; unavailable counters cause an error.

The player retains `hwdec=auto`. This host selects `d3d11va-copy`, confirmed
by both mpv logs and active Video Decode counters. Forcing `d3d11va` is not a
validated replacement for this Flutter/libmpv texture integration: the
[mpv manual](https://mpv.io/manual/stable/#options-hwdec) specifies compatible
video outputs/contexts for direct D3D11 decoding. No zero-copy claim is made.

## Measured playback comparison

The table compares `eee5854` with `ab0cdc6` in the same RDP session and window
size, using the H.264 854x480, 24 fps trailer. Both clients were newly launched,
connected to the local test room, and played for at least 20 seconds before an
incoming `START` reset the position to zero. Sampling began three seconds
later: 30 one-second samples, without timeline hover or a call. The optimized
process spent additional time idle in the library before starting playback.
Both runs reported `d3d11va-copy` and zero decoder/frame drops in the sampled
interval. These are short playback measurements, not a 1080p/4K or combined
camera/call stress test.

| Mean metric | Baseline | Optimized |
| --- | ---: | ---: |
| Process private memory | 516.1 MiB | 379.5 MiB |
| Process working set | 502.0 MiB | 351.1 MiB |
| GPU 3D / busiest engine | 23.86% | 11.99% |
| GPU Video Decode | 1.79% | 2.24% |
| GPU shared memory | 285.6 MiB | 163.9 MiB |
| CPU, one logical core = 100% | 12.7% | 11.8% |

This pair shows 26% less private memory and 50% less GPU 3D activity. Hardware
decoding remains active; the smaller 3D value measures less rendering work,
not disabled GPU acceleration. Earlier CPU-only runs varied, including an
optimized run at 19.8% of one core, so no stable CPU improvement is claimed.

Raw data: [baseline](measurements/2026-10-02/baseline-gpu-playback.csv),
[optimized fresh](measurements/2026-10-02/optimized-gpu-fresh.csv), and an
[additional optimized warm run](measurements/2026-10-02/optimized-gpu-playback.csv).
Each has a companion `-gpu.csv` with individual engine and memory counters.
The warm run measured 336.1 MiB private memory and 12.34% GPU 3D; it is retained
as supporting data, not substituted for the fresh comparison.

After-change UI checks also passed incoming `START`/`PAUSE`, seek, keyboard
fullscreen and Escape, return to library, playback-session retention, ending
watching, and application exit. Full camera calling and the custom WebRTC DLL
remain outside the verified scope described above.

## Preview startup regression

The baseline's black preview was reproduced at the 14-second bucket after the
resource changes. The first screenshot was captured before the decoder had
finished initializing/seeking; a nonempty black image was then cached. Preview
loading now waits for the first native frame and mpv's `seeking=no`, with
bounded waits and request-cancellation checks. It does not classify legitimate
black movie frames as errors.

On Windows, the 14- and 34-second previews now show their corresponding scenes.
The native preview output resizes to 192x108 at this session's device pixel
ratio, and logs confirm decoder/texture disposal after leaving the timeline.
Re-entering the timeline creates a new decoder and shows the new target frame;
see the [lifecycle trace](measurements/2026-10-02/preview-lifecycle.txt).
The final preview change passed formatting, analysis, all 20 tests, and another
Windows release build. The playback table above predates this preview-only
fix and was measured with the preview decoder inactive.
