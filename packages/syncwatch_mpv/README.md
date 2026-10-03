# Windows mpv lifecycle adapter

When media_kit asynchronously observes audio devices, the mpv bundled by
`media_kit_libs_windows_video` creates its WASAPI device monitor on its MTA
core thread, then destroys it on the caller of `mpv_terminate_destroy`.
That destructor calls `CoUninitialize` on the caller.
Disposing library probes on Flutter's STA therefore consumes COM references
owned by the runner and connectivity plugin. A later WebRTC initialization
exposes this as `no internet connection` on reconnect.

`syncwatch_mpv.dll` forwards the media_kit C API to the existing `libmpv-2.dll`.
Only `mpv_destroy` and `mpv_terminate_destroy` run on a fresh native thread with
cookie-based MTA membership. The caller waits for completion; the worker joins
and releases its MTA cookie. There is no persistent worker, player cache, COM
hook, changed decoder, playback option or media quality setting. Mac keeps the
original library path. Failure to allocate the teardown thread/MTA is logged
and leaves that handle unreleased; it must never fall back to destroying the
caller's COM context.

The export list matches the bundled mpv 652a1dd C API, including render APIs.
Recheck it when updating media_kit or its native libraries. This adapter covers
media_kit's asynchronous device observation; a synchronous audio-device query
can initialize COM on its caller and needs a separate lifecycle review.
Keep the original mpv DLL shipped by media_kit; the native video
renderer and this adapter must share that DLL and its handles.

Windows lifecycle regression: `scripts/check_mpv_lifecycle.ps1 -BuildDirectory
<release-directory> -OutputDirectory <external-artifact-directory>`. It checks
STA/MTA/no-COM callers, audio-device enumeration, secondary handles, repeated
teardown, and an existing Network List Manager after disposal. The baseline
mode runs in a separate process because the original DLL can invalidate its
COM proxies. Also test the ordinary application: library scanning, repeated
Connect/Disconnect, movie open/close, tracks, previews and reconnect after
playback. Logs and test executables belong outside the checkout.
