#!/usr/bin/env python3
"""Configure media permissions after generating the ignored macOS Flutter host."""
import argparse
import plistlib
import shutil
from pathlib import Path


def configure(root, validation_directory=None, media_file=None, multiview=False):
    runner = root / 'macos' / 'Runner'
    info_path = runner / 'Info.plist'
    if not info_path.exists():
        raise SystemExit('Generate macOS first: flutter create --platforms=macos --no-pub .')
    if multiview:
        templates = Path(__file__).resolve().parent / 'native_macos'
        for name in ('MainFlutterWindow.swift', 'AppDelegate.swift'):
            target = runner / name
            backup = target.with_suffix('.swift.syncwatch-backup')
            if not backup.exists():
                shutil.copy2(target, backup)
            target.write_text((templates / name).read_text())
    with info_path.open('rb') as source:
        info = plistlib.load(source)
    info['NSCameraUsageDescription'] = 'SyncWatch uses your camera for video calls.'
    info['NSMicrophoneUsageDescription'] = 'SyncWatch uses your microphone for voice calls.'
    with info_path.open('wb') as target:
        plistlib.dump(info, target, sort_keys=False)
    for name in ('DebugProfile.entitlements', 'Release.entitlements'):
        path = runner / name
        with path.open('rb') as source:
            entitlements = plistlib.load(source)
        # WebRTC needs incoming UDP as well as outgoing signaling connections.
        for permission in ('network.client', 'network.server', 'device.camera', 'device.audio-input',
                           'files.user-selected.read-only'):
            entitlements[f'com.apple.security.{permission}'] = True
        # Keep App Sandbox enabled. Test-only file access is explicitly scoped
        # to the selected recording and the directory holding config/statistics.
        for suffix, value in (
            ('read-write', str(validation_directory.resolve()) + '/' if validation_directory else None),
            ('read-only', str(media_file.resolve()) if media_file else None),
        ):
            if value:
                key = f'com.apple.security.temporary-exception.files.absolute-path.{suffix}'
                existing = entitlements.setdefault(key, [])
                if value not in existing:
                    existing.append(value)
        with path.open('wb') as target:
            plistlib.dump(entitlements, target, sort_keys=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--validation-directory', type=Path)
    parser.add_argument('--media-file', type=Path)
    parser.add_argument('--multiview', action='store_true',
                        help='Install native multi-view hooks; back up the generated Swift files first')
    args = parser.parse_args()
    configure(args.root, args.validation_directory, args.media_file, args.multiview)
