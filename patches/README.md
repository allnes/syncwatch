# SyncWatch Windows libwebrtc patch

SyncWatch must never change the volume of unrelated Windows applications.

Stock WebRTC marks its Windows Core Audio stream as `AudioCategory_Communications`.
Windows can therefore attenuate unrelated media sessions when a call starts.

The patch in this directory keeps the communications category (so WebRTC can
retain its normal communications/AEC behavior) but, after the render
`IAudioClient` is initialized, obtains `IAudioClientDuckingControl` from
that exact stream and requests
`AUDIO_DUCKING_OPTIONS_DO_NOT_DUCK_OTHER_STREAMS`.

This is deliberately implemented in the WebRTC stream itself. Do not replace it
with:
- changing Windows' global Communications setting;
- changing another process' volume;
- opting Chrome/Spotify/etc. sessions out on their behalf.

Those approaches violate SyncWatch's audio isolation requirement.

The API requires Windows 10 build 20348 or newer. SyncWatch targets Windows
10/11; on older builds the patch logs that the interface is unavailable.

## Remote track lifetime in flutter_webrtc

`flutter-webrtc-remote-media-lock.patch` is a separate C++ plugin fix, tested
against `flutter_webrtc 1.6.2+hotfix.3`. Signaling callbacks replace cached track
references while platform-channel lookups copy them. Protect both remote media
maps and reference copies with a mutex. Copy the stream map before calling
native stream methods, which may wait for the signaling thread.

Prepare an isolated dependency before Windows builds:

```powershell
flutter pub get
.\scripts\prepare_webrtc_plugin.ps1
flutter pub get
.\scripts\enable_multiview_windows.ps1
flutter build windows --release
```

CI and Windows launch scripts perform these steps. The patch is idempotent and
does not edit the shared pub cache. Its generated `pubspec_overrides.yaml` and
`.dart_tool/syncwatch_plugins/` are ignored. A user-owned override is preserved;
merge its dependency override manually. When upgrading WebRTC, remove the
generated override and isolated copy, resolve dependencies again, and review
patch compatibility. Do not commit a lockfile with this temporary path override.

This patch does not include or replace the libwebrtc audio-isolation patch
described above. Crash evidence and validation limits are recorded in
[`docs/measurements/2026-10-03`](../docs/measurements/2026-10-03/README.md).
