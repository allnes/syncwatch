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

## Windows video surface lifetime

`media-kit-video-surface-lifetime.patch` targets `media_kit_video 2.0.1`.
Its ANGLE renderer bound each new pbuffer to an unused GL texture whose name
was discarded. Those bindings retained old surface storage through subsequent
resizes. The patch removes the unused binding; the default-framebuffer rendering,
D3D shared-texture copy, synchronization, formats and dimensions stay unchanged.
It does not alter playback quality, decoder selection or interpolation.

`prepare_webrtc_plugin.ps1` also prepares this patch in an isolated video-plugin
copy. It accepts its previous WebRTC-only generated override and upgrades it
to include both dependencies. Custom overrides remain untouched; with
`-UseResolvedPlugin`, both resolved plugins must be inside this checkout's
`.dart_tool` directory. Review both patches when upgrading dependencies.

After a Windows release build, run `scripts/check_video_surface_lifetime.ps1`
with `-BuildDirectory build/windows/x64/runner/Release` and an external
`-OutputDirectory`. Add `-VerifyBaselineFailure` to reproduce the original
leak in a separate source copy. The native check uses the actual ANGLE DLLs,
two rendering contexts, repeated 4K/1080p surfaces, independent D3D pixel
readback and resource counters. Ordinary playback, preview, resize/fullscreen,
call and shutdown checks are still required by `docs/performance-validation.md`.

## macOS video texture cache lifetime

`media-kit-video-macos-texture-cache.patch` targets `media_kit_video 2.0.1`.
Core Video's OpenGL cache retains retired textures and their IOSurfaces across
resizes; flushing the cache alone does not release them. After retiring the old
GL wrappers, replace their cache before allocating the next three buffers.
Pixel buffers already retained by Flutter remain valid. Buffer count, dimensions,
format, decoder choice, rendering and synchronization remain unchanged.

Before macOS builds, run `flutter pub get`,
`dart run scripts/prepare_macos_video_plugin.dart`, then `flutter pub get` again.
The script patches an isolated `.dart_tool` copy, preserves custom overrides and
leaves the shared pub cache untouched. Use `--use-resolved-plugin` only with an
already isolated `.dart_tool` dependency. Review the patch on version upgrades.

After a release build, run `bash scripts/check_macos_texture_cache.sh` with the
plugin directory, the app's `Contents/Frameworks`, the parent directory of the
unstripped `FlutterMacOS.framework` (normally `build/macos/Build/Products/Release`),
and an external output directory. It compiles the selected plugin's actual
`TextureHW`, uses the app's mpv, cycles 4K/1080p buffers, checks dimensions and
pixels including a retained old frame, and verifies bounded physical memory.
For the original hosted package, add `--expect-growth` to verify reproduction.
This native check supplements the ordinary-app checks required above.
