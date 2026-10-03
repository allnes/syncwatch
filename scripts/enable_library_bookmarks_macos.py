#!/usr/bin/env python3
"""Enable library bookmarks in generated macOS hosts without weakening sandbox."""
import plistlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = [root / "macos/Runner" / name for name in (
    "DebugProfile.entitlements", "Release.entitlements"
)]
documents = []
for path in paths:
    if not path.is_file():
        raise SystemExit("Generate the macOS host with flutter create first.")
    data = plistlib.loads(path.read_bytes())
    if data.get("com.apple.security.app-sandbox") is not True:
        raise SystemExit(f"Refusing unsandboxed host: {path}")
    if not (data.get("com.apple.security.files.user-selected.read-only") or
            data.get("com.apple.security.files.user-selected.read-write")):
        raise SystemExit(f"Enable user-selected read access in {path} first.")
    documents.append((path, data))
for path, data in documents:
    if data.get("com.apple.security.files.bookmarks.app-scope") is not True:
        data["com.apple.security.files.bookmarks.app-scope"] = True
        path.write_bytes(plistlib.dumps(data, sort_keys=False))
    print(f"Library bookmarks enabled: {path.relative_to(root)}")
