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
