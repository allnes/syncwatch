# Surface-free previews under camera and 4K playback load

Application change: `a5779c1`, following [round 2](../round2/README.md).
The normal UI, movie buffering, camera encoding settings, and thumbnail quality
are preserved. The improvements below do **not** establish stall-free playback.

## Implementation

Native previews use a paused libmpv player with `vo=null`, so they no longer
create a hidden Flutter video surface. They open directly at the requested
position; subsequent requests on the same player still seek. Frame readiness
is read off the UI thread before the existing raw-pixel thumbnail capture.
Audio remains disabled and the existing cache limits remain in effect.

Windows selects `d3d11va-copy` for previews. The bundled automatic selector
chose `qsv-copy` for the small lossless H.264 High 4:4:4 Predictive fixture and
returned incorrect colors. The shared production/test configuration now passes
the color check using D3D11 selection with software fallback. Mac previews use
`videotoolbox-copy` on this hardware. Main movie decoding is unchanged.

Idle preview cleanup waits for an already-active movie seek, with cancellation
checks and a two-second polling budget. It cannot prevent contention when
cleanup starts just before a new seek. The benchmark's seek-completion polling
also uses a separate worker reader, so that observation does not block Flutter.

## Matched Windows comparison

Both 150-second release runs use the same source, patched native dependencies,
60 Hz console session, 960×640 window, fixture, and continuously connected Mac
peer. Only `legacyPreviewSurface=true` selects the old preview path. Each run
performs eight previews, nine seeks, and one camera/microphone restart. Preview
requests start at seconds 15, 25, …, 85; concurrent movie seeks start one second
later. Both complete all **18 actions**, restore both media tracks after restart,
and release them at shutdown. All eight preview PNGs are byte-identical.

Windows: i7-12700, 16 GB RAM, UHD 770, Logitech C922. Mac: M1 Max, 32 GB RAM,
built-in camera/microphone. The local generated movie is 3840×2160 / 60 fps,
HEVC Main10 at approximately 80 Mbit/s, with 96 kHz / 24-bit / 7.1 PCM.
This is SDR BT.709. Camera video is transmitted at 640×480 / approximately
15 fps, with nonzero microphone audio in both directions. Windows movie decode
uses D3D11; camera encoding/decoding remains OpenH264/FFmpeg software.

| Metric | Hidden surface | Surface-free |
| --- | ---: | ---: |
| Mean preview completion | 637.3 ms | 249.6 ms |
| Preview range | 423–794 ms | 231–265 ms |
| Median movie seek completion | 95 ms | 105 ms |
| Movie seek range | 85–99 ms | 89–131 ms |
| Mean private RAM, seconds 15–90 | 1670.0 MiB | 1508.5 MiB |
| Peak private RAM, seconds 15–90 | 2455.4 MiB | 2219.8 MiB |
| Mean shared GPU memory, seconds 15–90 | 1131.4 MiB | 930.3 MiB |
| Mean GPU 3D / Video Decode | 69.45% / 18.04% | 70.16% / 18.42% |
| CPU, one logical core = 100% | 118.2% | 109.8% |
| Worst Flutter frame, 10–100 s report windows | 206.8 ms | 44.6 ms |
| Frames over 33 ms in those windows | 10 | 8 |

The absolute RAM difference includes launch variation: pre-preview private RAM
was 1439.4 versus 1342.7 MiB. The preview-phase increase over each run's own
baseline fell from **230.6 to 165.8 MiB**, and the peak increase from
**1016.0 to 877.1 MiB**. Warm shared GPU allocations also differed by about
154 MiB. Do not attribute the entire absolute difference to this change.
Small CPU/GPU differences need repeated comparisons before generalization.

Private RAM uses a separate sampler requested every 100 ms; actual intervals
average about 119 ms. GPU counters retain one-second sampling. UTC timestamps
align both streams to client events. Private and shared GPU bytes are separate
measures and must not be added as physical RAM usage.

## Repeated actions and remaining latency

The five-minute follow-up completes **93 actions**: 30 previews, 60 alternating
window resizes, one seek, and two camera/microphone restarts. Preview completion
is 218–269 ms, without capture failures or fallback. Both restarts show tracks
2 → 0 → 2; all three call segments sustain bidirectional camera and audio.
Final shutdown leaves zero published tracks and exits successfully.

Private RAM peaks at **2377.3 MiB** during the more intensive combined sequence.
After the actions, seconds 250–280 average **1531.7 MiB**, range
1526.2–1538.1 MiB. The interval between restarts averages 1527.5 MiB. This
bounded run does not show a retained allocation per action, but is not a
long-duration leak guarantee. Shared GPU memory in the tail averages 1183.2 MiB.

Latency remains. The largest Flutter frames are **334.7 and 350.5 ms during
explicit camera restarts**; resize windows reach **156.0 ms**. Restart actions
take approximately 2.8 seconds and temporarily interrupt publication. The
matched seek comparison also shows a small regression, including one 131 ms
completion. These costs remain unresolved.

Movie decoder drops are zero, but **video-output drops are not zero**. During
the paired runs' steady 115–145-second intervals, the mpv output counter grows
by about 11.4 and 13.8 frames/s respectively. The counter resets on seeks;
its maximum is not a cumulative total. The checker now reports decoder and
output counters separately. Successful call/action checks therefore do not
constitute a smooth-60-fps acceptance result.

A separate 60-second `video-sync=audio` probe confirms the requested option
is active, but still observes about 10.9 output drops/s over seconds 20–55.
It does not resolve the output problem and is not adopted. The integration's
render scheduling needs further profiling. mpv documents the distinction
between [decoder and VO drops](https://mpv.io/manual/stable/#property-list)
and the [render API's timing contract](https://github.com/mpv-player/mpv/blob/v0.36.0/libmpv/render.h).

## Mac and synchronization

The final Mac companion runs for 703 seconds and shuts down with zero local
tracks. Its four previews take **201–216 ms**, compared with 407–471 ms in
round 2; all four PNGs are byte-identical to those earlier captures. This is a
preview comparison, not a paired Mac whole-process memory experiment. Both
Mac decoder and output drop counters remain zero throughout this run.

Clock-corrected stable position samples show absolute p95 offsets of 40.6 ms
in the optimized paired run and 59.2 ms in the soak. Clock uncertainty is
approximately ±99.2 ms, so these samples cannot prove sub-100-ms synchronization
or input-to-photon latency. See [position evidence](sync-position-check.json).

## Verification and reproduction

`flutter analyze lib test tool`, normal release builds, and all **29 tests**
pass on both hosts. Native tests use each release bundle's actual libmpv and
cover opening at a nonzero position, forward/backward seeks, thumbnail colors,
and disposal. Set `SYNCWATCH_TEST_LIBMPV` as described in the
[round 2 instructions](../round2/README.md#reproduction-and-verification).

Build the diagnostic target with
`flutter build windows --release -t tool/synthetic_media_load.dart`. Use the
[two-host fixture setup](../README.md), `legacyPreviewSurface=true` only for
the comparator, and the same actions for both builds. Collect RAM with
`-SampleIntervalMilliseconds 100` in a separate sampler; `-IncludeGpu` requires
the default one-second interval. Check paired JSONL logs with
`python3 tool/check_media_load.py <file> --expected-actions 18 --require-restart`.
Use `--expected-actions 93` for the soak and verify both restart segments,
as recorded in [soak-restarts.json](soak-restarts.json).

The harness uses production playback/call services and a real remote-video
overlay. The ordinary call helper still has no video renderer; its separate
rendering acceptance remains unresolved. No HDR or physical eight-speaker
listening acceptance is claimed. Global Windows audio settings and unrelated
application volumes are unchanged.

The normal helper's three ready/state/exit IPC cycles pass on each host,
including parent-pipe EOF. The normal Mac library opens and Cmd+Q exits; this
is a startup check, not a full layout audit. No SyncWatch application crash
events/files are observed in the final test interval. The signed normal Mac
bundle keeps App Sandbox enabled and has zero temporary filesystem exceptions.

All owned test processes, scheduled tasks, service listeners, and local SSH
forwards are stopped. Both original Windows firewall block rules are restored,
temporary allow rules are removed, and the user's RDP session is restored.
See [cleanup-verification.json](cleanup-verification.json) and
[verification.json](verification.json).

CSV and JSON evidence is sanitized: no room credentials, camera images,
device identifiers, or personal movie content is included. Early QSV-corrupted
previews and intermediate prototypes are excluded from the final comparison.
