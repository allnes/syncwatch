# Performance change requirements

## Preserve the upstream application

The reference is `main` of the original `nestolen/syncwatch` repository, not
the fork's `main` or an older optimization branch. Fetch `upstream/main` and
record its exact commit before starting a comparison.

Do not change design, functionality, controls, workflows, window behavior,
shortcuts, previews, localization, or media quality to improve performance.
Preserve video resolution, frame rate, audio channels and processing settings.
Do not automatically restore experiments from an archived optimization branch.

Establish working behavior before optimizing. Compare the ordinary release
application on Mac and Windows before and after each isolated change using
the same media, settings, devices, window geometry and display conditions.
Check playback, tracks, previews, seeking, fullscreen, synchronization,
camera, microphone, call windows, reconnect and shutdown. A diagnostic target
does not replace the ordinary application. Unverified scenarios and unresolved
regressions block acceptance of performance changes.

Critical bug fixes authorized by the owner must be isolated, reproduced before
and after, and preserve the intended workflow and appearance. Record existing
upstream defects separately; a successful build is not proof that a call works.

## Validation and artifact storage

Run `flutter analyze lib test`, `flutter test` and the affected desktop release
builds. Keep each change focused and rerun equivalent behavioral checks.
Report measured resource usage and latency with their verification limits;
separate short samples from sustained memory-growth checks and RDP from the
physical Windows console. Hardware flags alone do not prove GPU execution.

Do not infer GPU resource leaks from Windows per-process memory counters alone.
Correlate repeated lifecycle samples with resource ownership, DXGI process
usage and whole-adapter memory. Preserve conflicting raw measurements and
investigate the discrepancy before changing cleanup behavior. Diagnostic
resource opens can affect lifetime; use a live-resource positive control and
repeat measurements without that probe. Remove diagnostic instrumentation
from the final ordinary release.

Keep plans, reports, logs, samples, screenshots, dumps and generated media
outside the source checkout, including copies without Git metadata. Use a
sibling artifact directory and launch test clients with an external working
directory. Only reusable tests, tools and permanent rules belong in Git.

Keep macOS sandbox protection enabled. Follow `patches/README.md`: never alter
another application's volume or global Windows communications attenuation.
Stop owned test processes and restore temporary test configuration afterward.
