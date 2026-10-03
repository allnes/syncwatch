# Media resource validation

## Mandatory prerequisite: upstream behavior and design

Do not implement, enable, or accept further performance optimizations until
the behavior and visual comparison with `main` of the original upstream
[`nestolen/syncwatch`](https://github.com/nestolen/syncwatch) is complete.
The optimization branch and the fork's `main` are not the reference.
Fetch `upstream/main` and record its exact commit in the external run manifest.

Preserve upstream layout, colors, typography, icons, dimensions, control
visibility, window modes, shortcuts, user workflows, and media quality.
Do not add or remove previews, controls, features, or modes as an optimization.
Check library/settings, playback and tracks, timeline previews, synchronization,
camera/microphone controls, call windows, reconnect, and shutdown on Mac and
Windows using matching media, settings, window sizes, and DPI.

Keep a scenario matrix with expected upstream behavior, observed candidate
behavior, evidence, and pass/fail/unverified status outside the checkout.
Unverified scenarios, unresolved regressions, or an upstream build failure
keep this prohibition in force. Analysis, unit tests, a source diff, and a
diagnostic overlay alone do not satisfy the prerequisite. Critical bug fixes
already authorized by the user must be isolated and verified; that permission
does not permit a redesign or a change to the intended functionality.

## Artifact storage

Keep plans, reports, runtime logs, generated media, CSV/JSONL samples, traces,
crash dumps and captures outside the source checkout. Use a sibling directory,
for example `../artifacts/syncwatch-performance/`, with a fresh directory for
each run. This rule also applies to source copies without Git metadata.
Only reusable tools, regression tests and small permanent fixtures belong in Git.

Historical measurements were moved to the workspace artifact directory under
`historical/docs/measurements/`; the original validation report is preserved as
`historical/docs/performance-validation.md`. These are local artifacts, not files
that a new Git clone is expected to contain. Record the source commit, versions,
configuration and hashes in each external run manifest.

Measurement and fixture scripts reject output paths inside the checkout,
including Windows junctions. The diagnostic Dart target checks `statsPath` and
`previewOutputDirectory` before starting media. It also accepts `repositoryRoot`
for a binary copied outside the source tree. Runtime logs use
`SYNCWATCH_LOG_DIRECTORY`, or a sibling artifact directory during development;
installed/sandboxed clients fall back to the platform temporary directory.
The override must also point outside the checkout.

## Build and regression checks

Run `flutter analyze lib test tool` and `flutter test`. For native coverage,
set `SYNCWATCH_TEST_LIBMPV` to the matching release bundle's `libmpv-2.dll`
on Windows or `Mpv.framework/Mpv` on macOS. On macOS set
`DYLD_FRAMEWORK_PATH` to the bundle's `Contents/Frameworks` and invoke
`bin/cache/dart-sdk/bin/dart bin/cache/flutter_tools.snapshot test` using the
Flutter SDK's absolute paths; the shell launcher can strip that environment.
Do not count skipped native checks as a native pass.

Follow [native plugin preparation](../patches/README.md), then build the normal
release client. Use `dart run tool/check_call_window_ipc.dart <executable>` in
an interactive desktop to check helper ready/state/exit and parent-pipe EOF.
This checks transport and lifecycle, not camera rendering.

## Comparable measurements

Use fresh release processes, matching source/dependencies, window geometry,
DPI, display refresh, power settings, devices and media. Keep RDP and physical
console comparisons separate. Include the main and helper processes; report
fixture overhead separately. Finish media generation and cloud downloads before
profiling local playback. Repeat comparable A/B runs and report launch variance.

Capture RAM/CPU with `scripts/measure_windows_resources.ps1 -ProcessIds <pids>
-Seconds 300 -SampleIntervalMilliseconds 100 -OutputPath <external-memory.csv>`.
Run a separate sampler with `-IncludeGpu` and its default one-second interval
for GPU rate counters. Preserve actual sample intervals and align events with UTC
and monotonic timestamps. Report private bytes, working set and shared/dedicated
GPU memory separately; do not add overlapping measures. GPU engines are separate,
not additive. CPU values use one logical core = 100%.

For the combined diagnostic target and real two-host fixtures, follow
[the media-load instructions](synthetic-media-load.md). Verify sustained sent and
received camera video, nonzero audio energy, advancing movie position, each
restart and final cleanup using `tool/check_media_load.py`. Inspect decoder and
video-output drops separately: counters may reset at seek. An enabled hardware
option does not prove the selected hardware implementation.

## Normal application acceptance

Check actual camera/audio and received video in the ordinary call window on
Mac and Windows, alongside playback, pause, seek, previews, fullscreen, resizing,
subtitles, reconnect and repeated media shutdown. The diagnostic overlay is a
separate rendering path and cannot replace this acceptance. Record known failures
before changing code and do not label a limited successful check end-to-end.

Compare preview/seek and UI p95/p99/max latency, output cadence, track lifetimes,
resource peaks and steady-state memory after repeated actions. For retained
memory, compare equivalent warmed phases over a 30–60 minute run. Preserve
image/audio quality and account for clock uncertainty when comparing clients.

Stop owned test processes and restore temporary test configuration afterward.
Never change unrelated application volumes or global communications attenuation.
Rebuild the normal target after diagnostic runs; verify that signed macOS release
entitlements contain no test-only filesystem exceptions.
