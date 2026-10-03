# SyncWatch

SyncWatch is a cross-platform watch-together client for local movie files with synchronized playback and integrated voice/video calling.

## Current milestone

The repository contains the first interactive UI prototype for Windows/macOS:

- text-only local movie library
- Russian and English UI
- dark cinema-first design
- centered rewind / play-pause / fast-forward controls
- configurable local skip interval
- absolute seek model so different skip intervals do not break synchronization
- one audio button with separate Movie and Call volume controls
- mouse wheel changes Movie volume only
- optional audio ducking (off by default)
- movable/resizable remote-video overlay
- remote video fullscreen, minimize and hide/restore
- camera target: 480p
- Syncplay defaults: `syncplay.pl:8997`, room `nevermore`
- Auto Ready enabled by default
- SyncEngine and CallEngine interfaces ready for real backends

The UI is currently a mock. Real media playback, Syncplay protocol integration and WebRTC/LiveKit will be connected incrementally.

## Run on Windows

Prerequisites:

1. Flutter stable SDK
2. Git
3. Visual Studio with **Desktop development with C++**

Clone the repository, then double-click:

```
run_mock.bat
```

On the first run the bootstrap script generates the standard Flutter Windows/macOS host files, downloads Flutter packages and starts the app. After that, the same script launches the project directly without installing/uninstalling an EXE.

For normal development:

```
run_dev.bat
```

For direct Flutter builds, follow the dependency preparation steps in
[patches/README.md](patches/README.md#remote-track-lifetime-in-flutter_webrtc)
before configuring the Windows runner. The launcher and CI prepare the native
WebRTC fix automatically in an isolated dependency copy.

## Architecture

```
Flutter UI
├── Library / Settings / Player
├── SyncEngine
│   └── Syncplay adapter (next)
├── CallEngine
│   └── WebRTC / LiveKit adapter (next)
└── MediaEngine
    └── media_kit / libmpv (next)
```

The client architecture is intentionally platform-neutral so Android TV can be added later. Samsung Tizen will remain a separate frontend.

## License

Apache-2.0.
