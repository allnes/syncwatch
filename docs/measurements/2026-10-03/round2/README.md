# GPU surface lifetime, UI latency, and preview capture

This round uses the same physical cameras, Windows/Mac hosts and generated
4K60 HEVC Main10 + 7.1 PCM fixture described in the [parent report](../README.md).
The starting application commit is `937c02f`.

## Native surface regression

The `media_kit_video 2.0.1` Windows ANGLE manager creates an untracked GL texture
on every resize. That binding retains the old pbuffer allocation until context
teardown. The rendering path uses the pbuffer framebuffer and a DXGI copy, so
the extra GL texture is unnecessary.

`tool/native_surface_probe` alternates 960×540 and 1920×1080 sixty times in a
fresh process. Every iteration clears the framebuffer and checks its pixel
against RGBA (51, 102, 153, 255), with one unit of RGB rounding tolerance.
Both builds pass every color assertion and exit with code 0.

| Metric | Original dependency | Patched dependency |
| --- | ---: | ---: |
| Initial private memory | 70.33 MiB | 70.31 MiB |
| Private memory after 60 resizes | 499.21 MiB | 83.99 MiB |
| Live GL textures after 60 resizes | 60 | 0 |

The patched process reaches a plateau rather than retaining one surface per
resize. These are isolated native-surface figures, not whole-application RAM.
Raw observations: [original](baseline-surface.csv), [patched](patched-surface.csv).
The isolated dependency preparation is idempotent and its Windows release
build succeeds. Production changes are `a4a80ff`, `5768f32`, and `42e0ddb`.

## Simultaneous camera, call, and 4K playback

Windows: i7-12700, 16 GB RAM, UHD 770, Logitech C922. Mac: M1 Max,
32 GB RAM, built-in camera/microphone. Both run release clients and exchange
real camera video and microphone audio through the private test LiveKit server.
The generated local fixture is 3840×2160, 60 fps, HEVC Main10 at approximately
80 Mbit/s, with 96 kHz / 24-bit / 7.1 PCM audio. It is SDR BT.709; neither HDR
correctness nor a physical eight-speaker listening test is covered.

The diagnostic target uses production playback, preview, synchronization, and
call services. Its remote-video overlay is separate from the normal call helper.
Camera capture stays at the existing 640×480 / 15 fps configuration. Windows
uses OpenH264/FFmpeg for camera encoding/decoding; movie decode uses
`d3d11va-copy`. Mac movie/camera hardware acceleration uses VideoToolbox.
No main-movie quality, audio format, or normal UI setting was reduced.

### Surface fix and asynchronous health snapshots

`pair2-before` and `pair2-after` are fresh 220-second processes in the same RDP
session. Each completes 60 alternating 1200×800 / 960×640 window resizes,
two seeks, four previews, and a camera/microphone restart: 67 actions total.
Both still use the old JPEG capture, isolating the surface and diagnostic changes.
The after configuration's experimental preview filter had no effect: output
bytes matched the original capture, and that option was removed.

| Mean metric / client interval | Before | After |
| --- | ---: | ---: |
| Private memory, steady 20–39 s | 1476.9 MiB | 1343.2 MiB |
| Private memory, after resizes 103–114 s | 1752.8 MiB | 1388.8 MiB |
| GPU shared memory, after resizes | 1735.9 MiB | 1152.8 MiB |
| Private memory, preview phase 141–166 s | 2345.0 MiB | 1973.2 MiB |
| Private memory, after call restart | 1796.6 MiB | 1426.4 MiB |
| GPU 3D, steady | 69.88% | 67.72% |
| GPU Video Decode, steady | 18.10% | 18.88% |
| CPU, steady, one core = 100% | 108.35% | 97.43% |

The post-restart memory comparison has only ten after samples. Initial movie
positions differ because the peer supplies room state; the later seeks match.
Small CPU/GPU differences are not proof of a general throughput improvement.
During resizing CPU rose from 97.90% to 107.88% of one core, and median resize
command completion increased from 36 to 53.5 ms. Releasing native resources
has a cost; it prevents the demonstrated retained-surface growth.

The SDK's synchronous `getProperty` blocked the UI even though its Dart API
returned a Future. Bounded worker snapshots now free native property strings,
coalesce overlapping reads, and finish before player destruction. In steady
10–40-second frame windows, frames over 33 ms fell from 4 to 0, and worst
frame time from 145.9 to 31.2 ms. During resizing the worst frame fell from
149.6 to 34.6 ms. This RDP display is 32 Hz, so these runs do not prove 60 fps.

### Raw preview capture and concurrent input

The old SDK screenshot encoded a full 4K JPEG before making a small thumbnail.
Its screenshot operation also held the SDK's shared player lock, delaying a
main-movie seek behind preview work. Capture now uses bundled libmpv's public
`screenshot-raw` API in a worker, preserves the returned dimensions/stride,
scales in the image engine, and encodes only the small PNG. Native allocations
and Flutter image resources are explicitly released. Unsupported pixel formats
fall back to the previous path. The preview cache remains bounded to 32 entries
and 8 MiB; the normal preview size and aspect ratio are preserved.

`final-before` and `final-after` use the same patched native dependencies and
asynchronous diagnostics; only the former enables `legacyPreviewCapture`.
Both reset movie position at second 5, request previews at 15/25/35/45 seconds,
and schedule a main-movie seek one second after each preview starts. A continuous
Mac peer is present throughout both runs.

| Metric | Full-size JPEG | Raw pixels |
| --- | ---: | ---: |
| Four preview completion times | 2334–2683 ms | 428–803 ms |
| Capture portion | 1804–1958 ms | 67–84 ms |
| Concurrent main-movie seek | 1342–1693 ms | 86–92 ms |
| Mean private memory, 15–49 s | 1868.3 MiB | 1574.8 MiB |
| Peak private memory, 15–49 s | 2390.0 MiB | 2324.1 MiB |
| Mean private memory, 70–85 s | 1509.7 MiB | 1406.9 MiB |

Separate Mac capture checks also produced correct 384×216 thumbnails: four
preview times changed from 2551–2734 ms to 407–471 ms. These shorter Mac runs
are latency checks, not a matched whole-process memory comparison.

### Five-minute soak and console check

`final-after` continues to 300 seconds with 60 resizes, four additional previews,
and another camera/microphone restart: **75 completed actions**. Both restarts
show local tracks 2 → 0 → 2, and final shutdown leaves zero tracks. Incoming
camera video averages 15.0 fps over 299 seconds; all three outgoing track
lifetimes average 15.0 fps. Audio energy increases in both directions. There
are no capture fallbacks/errors, unexpected movie buffering samples, or movie
decoder drops. The longer run's private-memory peak is 2377.8 MiB; in its final
230–280-second interval memory averages 1437.1 MiB (range 1431.0–1443.2 MiB).
This is a bounded five-minute check, not proof against every long-term leak.

Some latency remains: preview windows include isolated frames up to 190.7 ms,
resizing includes frames up to 34.9 ms, and the last steady window includes two
frames over 33 ms (maximum 63.1 ms). Explicit media restart pauses publication
and can increment peer freeze counters; it is not uninterrupted calling.

A separate fresh 60-second `final-console` run moves Windows from the 32 Hz
RDP display to its 60 Hz console. After startup, Flutter reports approximately
55–57 frames/s and no frames over 33 ms; one preview takes 416 ms, concurrent
seek 89 ms, and movie decoder drops remain zero. The Mac peer intentionally
restarts near the end, so only its first continuous receive segment is used by
the checker. This different display mode is not an optimization comparison.

After correcting host clocks using a postflight, lowest-RTT sample, 243 stable
movie-position comparisons have median Windows-minus-Mac offset −58.9 ms and
absolute p95 64.4 ms. Clock uncertainty is approximately ±65.8 ms; one-second
position samples cannot establish input-to-photon latency. The largest sampled
transient is 340.2 ms. See [position check](sync-position-check.json).

## Reproduction and verification

Build the separate target with
`flutter build windows --release -t tool/synthetic_media_load.dart`, following
the [fixture and two-host instructions](../README.md). JSON configuration accepts
`mpvProperties`, `synchronousStats`, `legacyPreviewCapture`,
`previewOutputDirectory`, and `actions`. The two legacy switches are diagnostic
comparators, not user preferences. For example:

```json
{"actions":[
  {"atSeconds":15,"type":"preview","positionSeconds":50},
  {"atSeconds":16,"type":"seek","positionSeconds":90,"concurrent":true},
  {"atSeconds":30,"type":"resize","width":1200,"height":800},
  {"atSeconds":60,"type":"restartMedia"}
]}
```

Actions are serialized unless explicitly concurrent. Output writes are buffered
until shutdown; an earlier diagnostic-only periodic `IOSink.flush` raced action
records and invalidated initial runs. Those runs are excluded. Verify completion
with `python3 tool/check_media_load.py <stats.jsonl> --expected-actions 75` and
inspect every restart's track and RTP-counter sequence. `--require-restart`
currently checks exactly one restart, so use it for the 67-action paired runs.

For native lifetime coverage, set `SYNCWATCH_TEST_LIBMPV` to the release build's
`libmpv-2.dll` on Windows or `Mpv.framework/Mpv` on macOS before `flutter test`.
On macOS also supply the bundle's `DYLD_FRAMEWORK_PATH` and invoke the cached
`flutter_tools.snapshot` with Dart directly so the shell launcher does not strip
that variable. All **28 tests** pass on both hosts, including five native
create/read/coalesce/dispose cycles and the SDK's delayed destruction callbacks.
Analysis passes on both hosts. Normal release builds are rebuilt after the
diagnostic target; macOS test-only absolute-path entitlements are removed.
`dart run tool/check_call_window_ipc.dart <normal-executable>` passes all three
ready/state/exit cycles on both hosts, including parent-pipe EOF. No helper
processes remain. Windows reports no application crash events for the final
comparison/test interval. The normal Mac library opens and Cmd+Q exits cleanly;
this startup check is not a complete layout or accessibility audit.

The normal call helper still needs its separate camera-rendering acceptance
described in the parent report; the IPC lifecycle check alone does not prove it.
No global audio attenuation settings or unrelated application volumes change.
All owned test clients, scheduled tasks, service listeners, and local SSH
forwards are stopped afterward. Both pre-existing Windows firewall block rules
are restored and temporary allow rules removed; cleanup reports zero temporary
listeners/tasks and no remaining client.

## Experiments not adopted

- Forcing `hwdec=d3d11va,auto` still selects `d3d11va-copy` with this integration.
  No zero-copy or hardware camera-encoder claim is made.
- Reducing `hwdec-extra-frames` from 6 to 2 did not establish a repeatable benefit
  beyond normal run variance; the production value remains 6.
- The bundled libmpv lacks the tested scaling filter. A setter returning normally
  was insufficient evidence of activation. The failing/ineffective filter runs
  are excluded from preview-performance claims.

## Evidence

Sanitized `*-resources.csv` files contain client-relative timestamps and process
CPU/RAM/GPU counters. `*-metrics.json` contains action, frame, and lifecycle
summaries; `*-validation.json` contains acceptance-check output. No room tokens,
camera frames, device identifiers, or personal movie content are included.
Process private bytes and GPU shared bytes are separate measures and must not be
added to estimate physical RAM. GPU values use the busiest engine in each class.
