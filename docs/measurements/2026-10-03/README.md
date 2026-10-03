# Physical cameras and 4K60 stress playback

## Fixture and environment

The replacement fixture is generated, not a downloaded film: 3840×2160 at
60 fps, HEVC Main10, approximately 80 Mbit/s video plus 7.1-channel PCM,
96 kHz / 24 bit. The 480.083-second MKV is 6,002,874,927 bytes (100.03 Mbit/s
combined). It uses BT.709 SDR test patterns and quiet, distinct channel tones;
this is a bandwidth/rendering stress test, not an HDR or listening-quality test.

Generate it on an Intel Quick Sync Windows host after installing FFmpeg:

```powershell
.\scripts\generate_stress_media.ps1 -FFmpeg C:\tools\ffmpeg.exe `
  -OutputDirectory C:\temp\syncwatch-heavy -Profile 4k60 -Seconds 480
```

The script refuses to overwrite existing media. Its 30-second segment can be
copied to another host and loop-remuxed locally to avoid transferring 6 GB.
Both tested segment copies have SHA256
`0eecf8fa126731f9c00fe152aeb3992fa93eb76d6e53f2be9f881b3900390434`.
The optional `8k30` generator profile was not exercised.

- Windows 11 25H2: i7-12700, 16 GB, Intel UHD 770, physical Logitech C922.
- macOS 26.6.2: M1 Max, 32 GB, 32-core GPU, physical FaceTime camera.
- Flutter 3.47.6 / Dart 3.13.5 release builds with matching dependency versions.
- LiveKit 1.13.7 on Windows, reached over the existing private WireGuard mesh.
  The token backend is accessed over an SSH loopback forward.
- Both clients decode the local fixture, exchange camera and microphone tracks,
  display the remote camera, and synchronize through production media classes.
  Cameras retain the application's 640×480 / 15 fps H.264 publication settings.

## Reproduce the client

`tool/synthetic_media_load.dart` is a separate release entry point. Its JSON
configuration accepts `backendUrl`, `room`, `identity`, `mediaPath`, `statsPath`,
`audioInput`, `cameraLabel`, `mediaName`, `durationMs`, `resolution`, `audioTracks`,
`subtitleTracks`, `sampleIntervalMs`, `seconds`, and `restartCallAfterSeconds`.
Select device labels returned by enumeration; do not silently substitute a
virtual camera. Keep credentials and recordings outside Git.

Generate the ignored macOS host, resolve dependencies, then install its native
multi-view hooks and scoped test permissions:

```sh
flutter create --platforms=macos --project-name syncwatch --org dev.syncwatch --no-pub .
flutter pub get
python3 scripts/configure_macos_media.py --multiview \
  --validation-directory /tmp/syncwatch-test
flutter build macos --release -t tool/synthetic_media_load.dart
build/macos/Build/Products/Release/syncwatch.app/Contents/MacOS/syncwatch \
  /tmp/syncwatch-test/config.json
```

Put test media/configuration under that validation directory. The script backs
up the generated Swift files, retains App Sandbox, and grants network/camera/
microphone permissions. Its registrar adapter supplies the main Flutter view
to legacy plugins: `window_manager` otherwise crashes while force-unwrapping
an absent implicit view in a multi-view engine. Native bootstrap files are
tracked under `scripts/native_macos/`, not in the generated host.

## Measurement boundaries

The test harness renders a remote camera overlay. The ordinary call helper
still uses the repository's diagnostic window; this run does not certify that
helper's camera UI. System audio attenuation settings were not changed.
Physical 7.1 output and subjective speech/music quality were not verified;
Windows speakers remained muted in their initial state.

Windows PDH measurements are per process; shared GPU memory is a separate
metric and must not be added to private bytes. CPU 100% means one logical core.
Mac RSS is not equivalent to Windows private bytes. Mac `powermetrics` GPU
residency covers the whole machine, including other applications, and is not
per-process attribution. Windows desktop observations use RDP, whose presentation
cadence limits conclusions about local-monitor 60 fps smoothness.

## Before and after output texture sizing

The baseline is `0ea9f24`; the second run adds viewport-sized movie output.
mpv still decodes the complete source using hardware acceleration. Only its
output texture follows the visible physical pixel size, with a 150 ms debounce.
Growth and fullscreen restore the required resolution without changing layout,
controls, camera publication settings, or playback behavior.

Each resource capture contains 180 samples; the table excludes the first
30 seconds. Movie health and RTC summaries cover client seconds 30–200. This
comparison predates the subsequent native race and keyboard fixes.

| Windows metric | Before | After |
| --- | ---: | ---: |
| Private memory, MiB | 1525.02 | 1405.39 |
| Working set, MiB | 1445.85 | 1351.87 |
| Shared GPU memory, MiB | 1131.93 | 999.51 |
| GPU 3D utilization | 73.62% | 70.04% |
| GPU video decode utilization | 18.40% | 18.29% |
| CPU, one logical core | 94.66% | 109.48% |
| mpv frame-drop counter increase / second | 28.73 | 8.05 |

Private memory improves 7.8%, shared GPU memory 11.7%, and the mpv drop rate
72.0%. CPU increases 15.7% relative (4.73% → 5.47% across 20 logical CPUs).
Both runs use `d3d11va-copy` and report zero decoder drops. RDP/Flutter cadence
remains about 32 frames/second: the lower mpv drop counter does **not** establish
60 fps presentation on a physical Windows display.

Mac RSS is 453.07 → 457.18 MiB; CPU is 48.53% → 49.67% of one core. Both runs
use VideoToolbox, report zero movie drops, and produce about 60 Flutter frames
per second. The Mac content height differed by 32 logical pixels between runs;
global GPU residency also includes RDP and other applications. These results
do not establish a Mac memory or GPU utilization improvement.

During both steady windows, camera reception is approximately 640×480 / 15 fps,
with zero reported packet loss, video drops, or freezes. Mac camera encoding
and decoding use VideoToolbox; Windows camera encoding uses OpenH264 software
and decoding uses FFmpeg software. Movie hardware decoding does not change that.
Mac's server RTT is about 68–69 ms. Clock-adjusted baseline playback positions
have median Mac-minus-Windows offset −30.4 ms (range −40.7…−19.7 ms, 150 pairs),
but clock calibration uncertainty is approximately ±99 ms.

Both long runs released all local tracks, restarted the call at 300 seconds,
and finished at 420 seconds with zero local tracks. After the measurement
window, a focused Back button consumed Space and returned the Mac to its library
(approximately 308 seconds before, 254 seconds after). Consequently neither
run is claimed as uninterrupted 420-second movie playback.

## Bugs found and regression checks

- Player shortcuts now consume control keys before focused buttons activate.
  Space previously paused and activated Back together. A widget regression
  verifies Space is consumed once while Enter still activates the button, and
  that another focused route retains text input.
- macOS helper/test-peer processes use an implicit Flutter view; the ordinary
  multi-view window uses the registrar adapter described above. The release
  library window opens, and three helper ready/state/exit IPC cycles pass.
- A Windows native crash occurred during remote audio subscription:
  `0xc0000409`, fast-fail parameter 7, `libwebrtc.dll+0x1125209`. Minidump
  disassembly shows an abort through a virtual call from the plugin's remote
  track lookup. Source inspection finds unsynchronized cache replacement and
  reference copying. This strongly supports a track lifetime race, although
  the upstream DLL has no supplied PDB and the stack is not fully symbolicated.
  The plugin patch locks all remote track/stream cache access; native stream
  calls run outside the lock. Dumps remain private and are not committed.

Manual checks on both platforms cover pause/resume, synchronized seek, fullscreen
and return to the window. Output grows from 927×521 to 1512×851 on Windows and
1771×996 to 3024×1701 on Mac, then returns to its previous size. Real remote
camera images were visually confirmed. Client analysis and all 26 unit/widget
tests pass on both platforms; release harness builds pass on both platforms.

After the native patch, ten fresh Windows processes joined the continuously
running Mac client: one 60-second run and nine 20-second runs, each restarting
camera/microphone publication once. All ten exchanged nonzero audio/video bytes
in both directions, progressed through the heavy movie, recorded `finished`,
and released all local tracks. No new SyncWatch Application Error events or
surviving client processes were found. The Mac run also finished after six
minutes with zero local tracks. This is bounded regression evidence, not proof
that a rare native race can never recur. The launcher did not capture numeric
process exit codes; completion is verified from lifecycle records and Windows
events. See `native-regression-summary.json` for each cycle.

Final ordinary release builds also pass on Windows and macOS. Generated Mac
test-only absolute-path entitlements were removed before its final build.

Implemented changes: `6cec897` (output sizing and keyboard handling), `aac5b01`
(native WebRTC lifetime lock and macOS helper view selection).

## Cleanup

All test clients, private LiveKit/token/clock services, four temporary scheduled
tasks, and two SSH forwards were stopped. Both original Windows firewall block
rules were restored and the two narrowly scoped test allow rules removed.
Verification found no remaining test listeners or scheduled tasks. The ordinary
Windows library opened successfully; it was stopped explicitly after the UI
check, so a normal-window close gesture is not certified by this run. Synthetic
media, local SDKs, and private diagnostic logs remain available for reproduction.

The adjacent sanitized resource CSVs and JSON summaries preserve the measured
data without camera frames, microphone recordings, credentials, or process IDs.
