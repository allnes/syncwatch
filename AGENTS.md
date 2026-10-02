# Repository Guidelines

## Project Structure & Module Organization

`lib/` contains the Flutter desktop client: screens in `screens/`, reusable UI in `widgets/`, calling and synchronization in `services/`, models in `models/`, and localization/themes in `core/`. `server/bin/` contains the Dart token server and diagnostic partner bot. Client regression tests live in `test/`, with fixtures in `test/support/`. Desktop host directories are generated and ignored. Native WebRTC patches live in `patches/` and `tools/webrtc/`.

## Build, Test, and Development Commands

Use Flutter stable and the Dart SDK range in `pubspec.yaml`. Windows builds require Visual Studio with Desktop development with C++.

- `flutter pub get`: install client dependencies.
- `./run_dev.bat`: bootstrap and run the Windows development environment.
- `flutter analyze lib test tool`: check client code, tests, and validation tools.
- `flutter test`: run client regression tests.
- `dart format <changed-files>`: format changed Dart files with two-space indentation.
- `.\scripts\enable_multiview_windows.ps1`: configure the generated Windows runner before building.
- `flutter build windows --release`: build a release client for resource measurements.
- From `server/`, run `dart pub get`, `dart analyze --fatal-infos`, and `dart run bin/server.dart` to prepare, check, and start the backend.

## Coding Style & Naming Conventions

Follow `flutter_lints` and Dart formatter output. Use `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members; prefix private members with `_`. Use existing `debugPrint` diagnostics rather than `print`. Keep shared UI strings in `lib/core/app_strings.dart`.

## Testing Guidelines

Name tests `*_test.dart`; use `flutter_test`. No coverage threshold is configured. For media changes, run release builds on Windows and verify playback, synchronization, preview cleanup, and call shutdown. Follow `docs/performance-validation.md`; record hardware limitations explicitly. Run `dart run tool/check_call_window_ipc.dart <exe>` in an interactive Windows session to check helper-process lifecycle.

## Commit & Pull Request Guidelines

History uses concise imperative subjects, such as “Restore vertical resize and adaptive call controls.” Keep commits focused. PRs should describe the problem, resulting behavior, validation, and relevant issues; include screenshots for UI changes.

## Configuration & Audio Safety

Copy `server/.env.example` to `server/.env`; never commit credentials. Preserve the audio-isolation requirement in `patches/README.md`: do not change global Windows communications settings or other applications’ volume.
