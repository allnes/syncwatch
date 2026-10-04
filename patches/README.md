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

## Remote media lifetime

`flutter-webrtc-remote-media-lifetime.patch` targets `flutter_webrtc
1.6.2+hotfix.3`. Its signaling callbacks update remote track/stream caches while
platform-channel handlers read them. `RemoteMediaCache` copies owning references
under a mutex; native calls and releases run outside that mutex. Handlers retain
their track reference until the operation finishes.

Before Windows builds, run `flutter pub get`,
`.\scripts\prepare_webrtc_plugin.ps1`, then `flutter pub get` again. The script
patches an isolated `.dart_tool` copy and generates an ignored override; it never
edits the shared pub cache. Existing custom overrides are preserved. For an
already isolated dependency under `.dart_tool`, use `-UseResolvedPlugin`.
Review the patch before upgrading WebRTC. Keep the original hosted dependency
in the committed lockfile. CI and Windows launch scripts prepare the patch.

This changes neither codec/capture settings nor `libwebrtc.dll`; the audio
isolation requirement above still applies. Run the native lifetime/concurrency
check using `tools/webrtc/CMakeLists.txt`, supplying `WEBRTC_INCLUDE_DIR` for
the resolved plugin's `third_party/libwebrtc/include`, then `ctest` in that
external build directory. On Clang, `-DENABLE_TSAN=ON` enables ThreadSanitizer.
