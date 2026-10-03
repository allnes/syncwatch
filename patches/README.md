# SyncWatch native media patches

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

Prepare isolated dependencies before Windows builds:

```powershell
flutter pub get
.\scripts\prepare_native_plugins.ps1
flutter pub get
.\scripts\enable_multiview_windows.ps1
flutter build windows --release
```

CI and Windows launch scripts perform these steps. The patches are idempotent and
does not edit the shared pub cache. Its generated `pubspec_overrides.yaml` and
`.dart_tool/syncwatch_plugins/` are ignored. A user-owned override is preserved;
merge both dependency overrides manually. When upgrading either package, remove the
generated override and isolated copy, resolve dependencies again, and review
patch compatibility. Do not commit a lockfile with this temporary path override.

This patch does not include or replace the libwebrtc audio-isolation patch
described above. `build_syncwatch_libwebrtc.ps1` installs its custom DLL into the
dependency selected by `package_config.json`, including the isolated copy.
Crash evidence and validation limits are recorded in
[`docs/measurements/2026-10-03`](../docs/measurements/2026-10-03/README.md).

## Windows video surface lifetime

`media-kit-windows-resize-leak.patch` targets `media_kit_video 2.0.1`. Its ANGLE
surface manager renders into a D3D-backed pbuffer, then copies that surface for
Flutter. The upstream code also binds each new pbuffer to an untracked GL texture;
resizing retains these textures and their allocations until context destruction.
Remove the unused texture binding. Rendering, decoding and DXGI transfer remain
unchanged. The preparation script applies both patches without editing pub cache;
`prepare_webrtc_plugin.ps1` remains a compatibility entry point.

`tool/native_surface_probe` checks pixel readback and records private memory and
live GL texture counts over 60 size changes. Build it with Visual Studio CMake,
passing `MEDIA_KIT_VIDEO_ROOT` (the selected package) and `ANGLE_ROOT` (the
Flutter Windows build's `ANGLE` directory). Put the matching `libEGL.dll` and
`libGLESv2.dll` beside the probe executable. Run each version in a fresh process.
