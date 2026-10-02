# Simultaneous camera, call, and movie load

This is a separate release target using the production `LiveKitCallEngine`,
`LiveKitSyncEngine`, and `PlayerScreen`. Each of two Windows processes captures
and publishes a camera and microphone, renders its peer's received video, and
plays a local 1080p film through libmpv. It does not load user preferences or
change the normal application UI. The existing `--livekit-test-peer` is only a
data peer and is **not** sufficient for this test.

## Prepare the isolated Windows desktop

- Run a local LiveKit server and this repository's token backend. Use distinct
  test credentials and a test room. Keep both clients on the same machine for a
  reproducible GPU/RAM comparison; this does not simulate Internet latency.
- Install the signed [OBS virtual camera](https://obsproject.com/kb/virtual-camera-troubleshooting).
  With portable OBS on Windows, register both supplied camera DLLs before
  starting OBS. Set its canvas/output to 640×480 at 15 fps. Loop a moving clip
  containing speech, scale it into the canvas, and start Virtual Camera.
- Feed that clip's audio through a test loopback capture device. On the validation
  host this is Realtek Stereo Mix, enabled temporarily in Sound → Recording;
  OBS monitors its media source to the corresponding Realtek speakers. Select
  that input explicitly in the test configuration. Restore its disabled state
  after testing. Do not change Windows communications attenuation or other
  applications' volume. RDP must play sound **on the remote PC** to expose these
  devices. Restore the test RDP profile afterward.
- Generate a 180-second movie using FFmpeg:

```powershell
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -f lavfi -i sine=frequency=523:sample_rate=48000 -t 180 -c:v libx264 -preset ultrafast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k synthetic-1080p.mp4
flutter build windows --release -t tool/synthetic_media_load.dart
.\scripts\run_windows_media_load.ps1 -Executable build\windows\x64\runner\Release\syncwatch.exe -MediaPath synthetic-1080p.mp4 -OutputDirectory C:\Temp\syncwatch-load-01
```

## Verify before comparing resources

Both windows must show a moving film and received camera video. JSONL reports
must show increasing sent/decoded video frames, nonzero received audio energy,
advancing playback, and `mediaStopped` with zero local tracks followed by
`finished` for both clients. Inspect stderr and Windows Application Error events
for native crashes. A connected room or a silent microphone is not a pass.

After startup settles, run `measure_windows_resources.ps1` with both client PIDs
and the OBS PID for 60 seconds using `-IncludeGpu`. Report each process separately;
OBS is fixture overhead. Collect the same interval and window geometry for both
revisions. Record actual RTP encoder/decoder implementations and libmpv
`MPV_HEALTH`; an enabled hardware option alone does not prove GPU decoding.

This target replaces the executable in the build directory. Rebuild with
`flutter build windows --release -t lib/main.dart` before using the normal UI.
