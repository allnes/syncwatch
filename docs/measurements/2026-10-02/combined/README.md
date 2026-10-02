# Real combined media load, Windows, 2026-10-02

Source: baseline `eee5854`, optimized production code `67c3b65`; identical
synthetic target from `4262f33` added to both checkouts. Same resolved packages,
Flutter 3.47.6, Windows 11 25H2, i7-12700 (20 logical processors), Intel UHD 770,
16 GB RAM. Stock `libwebrtc.m150.7871.02`; the repository's custom audio-ducking
DLL patch is not present in this validation build.

Each client publishes OBS camera H.264 640×480 at 15 fps / max 850 kbps and
Stereo Mix microphone Opus, receives and renders its peer's camera/audio, and
plays the generated 180-second H.264 1080p30 movie (~18 Mbps) with AAC audio in
production PlayerScreen. OBS loops the Sintel trailer for moving camera imagery
and audio. LiveKit 1.13.7 and the token backend run locally. Both client windows
are visible, 960×640 logical pixels, partially overlapping at x=20 and x=740.
The separate production diagnostic helper window is not part of this harness.

Measurements contain 60 samples per process at roughly one-second intervals
(65 seconds of wall time), after 60 seconds of warm-up; optimized ran first,
baseline second. No builds ran during those measurement intervals. Then real
LiveKit RoomService data messages issued START at 60 s, PAUSE at 63 s, SEEK to
120 s and PLAY. Both clients recorded all commands and corresponding playback
movement; both completed their 180-second run and unpublished every track.

| Per-client mean (two clients) | Baseline | Optimized |
| --- | ---: | ---: |
| Private memory, MiB | 637.8 | 548.0 |
| Working set, MiB | 620.3 | 518.6 |
| GPU shared allocation, MiB | 379.3 | 292.3 |
| GPU 3D utilization, % | 28.21 | 26.50 |
| GPU video decode utilization, % | 4.67 | 5.50 |
| CPU, % of one logical core | 38.4 | 47.8 |

Private memory fell **14.1%** and working set **16.4%**. GPU shared allocation
fell **22.9%**; do not add that allocation to private memory as independent RAM.
CPU was **higher**, not lower, in this pair: about 1.92% → 2.39% of the 20-thread
machine per client. Camera scene phase and loopback audio vary between runs;
these are single-run observations, not a statistically established CPU result.
Per-process GPU counters are not a whole-machine GPU percentage and must not be
summed as if they were. OBS overhead is recorded separately (PID 11436, ~225 MiB
private memory), not counted as SyncWatch.

RTP evidence: approximately 15 fps encoded and decoded in both directions for
170–175 seconds, with positive captured/received audio energy. Actual camera
encoder **OpenH264**, decoder **FFmpeg**: both software. Movie `MPV_HEALTH` shows
**d3d11va-copy** plus active GPU VideoDecode counters. GPU encoding of the camera
has not been achieved. No sustained movie decoder drops; an initial frame drop
appears in some streams, so the logs do not support a blanket zero-drop claim.

## Reliability finding

An earlier prototype run (before making the windows explicitly visible) lost
one client on its first incoming video subscription. Windows reported
`libwebrtc.dll`, exception `0xc0000409`, offset `0x1125209`, PID 12488 at
approximately 21:17:40 UTC. There was no actionable native stack in stderr.
This is an unresolved native failure; a subsequent successful run does not
prove it fixed. No such crash occurred during either complete comparison run.

After the comparison, three additional 70-second two-client runs stopped both
camera and microphone at 35 seconds, waited two seconds, and restarted them
while the movie continued. All six clients had zero published tracks at stop,
two after restart, and zero at final shutdown. Sent/received video stayed at
14.95–15.04 fps before and after restart; captured/received audio energy was
positive in every segment. All processes exited with code zero. No subsequent
SyncWatch Application Error event or native dump was found. These are short
stress checks, not a long-duration soak test.

`stress-*.jsonl` contains these runs; `stress-validation.json` records checks
with `tool/check_media_load.py --require-restart`. The validator was also checked
against deliberately missing receiver data and a missing restart event; both
fail as expected. The runner now retains process handles to avoid Windows
PowerShell reporting a null exit code after an otherwise successful exit.

Final `flutter analyze lib test tool` and all 20 Flutter tests passed. The normal
`lib/main.dart` Windows release target was rebuilt, then all three helper IPC
ready/state/exit cycles passed, including parent-pipe EOF cleanup.

The fixture was shut down afterward: no validation process remained, Stereo Mix
was disabled again, RDP audio returned to "On this computer", and both temporary
OBS camera registrations and the temporary per-application crash-dump setting
were removed. Downloaded tools and test media remain in the isolated validation
directory for reproduction.

CSV files are process/engine measurements. JSONL files preserve native RTC
reports; device identifiers have been removed. Stdout paths are replaced with
`<validation-root>`. `validation.json` is generated by `tool/check_media_load.py`;
all four full comparison logs pass its checks. `resources-summary.json` keeps
individual processes to expose variation concealed by the table average.
