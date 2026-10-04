#!/usr/bin/env python3
"""Validate/apply the external-texture fix to the pinned Flutter engine checkout."""

import argparse
from pathlib import Path
import subprocess


ENGINE_REVISION = "692136cb6582dbfc5af3fb33c2515a069f2f66d0"
SOURCE_ROOT = Path(__file__).resolve().parents[1]
PATCH = SOURCE_ROOT / "patches/flutter-macos-external-texture-cache.patch"


def git(checkout, *args):
    return subprocess.run(
        ["git", "-C", str(checkout), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path, help="External Flutter engine Git root")
    parser.add_argument("--apply", action="store_true", help="Apply after validation")
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    if checkout == SOURCE_ROOT or SOURCE_ROOT in checkout.parents:
        parser.error("Keep engine sources and build artifacts outside the app checkout.")
    revision = git(checkout, "rev-parse", "HEAD")
    if revision.returncode or revision.stdout.strip() != ENGINE_REVISION:
        parser.error(f"The patch requires exactly Flutter engine {ENGINE_REVISION}.")
    applied = git(checkout, "apply", "--reverse", "--check", str(PATCH))
    if applied.returncode == 0:
        print("Pinned engine patch already applied; no files changed.")
        return
    compatible = git(checkout, "apply", "--check", str(PATCH))
    if compatible.returncode:
        parser.error("Engine source differs from the reviewed patch; preserving it.\n"
                     + compatible.stderr)
    if not args.apply:
        print("Pinned engine is compatible. Use --apply to prepare it.")
        return
    result = git(checkout, "apply", str(PATCH))
    if result.returncode:
        parser.error(result.stderr)
    print("Prepared pinned engine. Build the framework and run its texture tests.")


if __name__ == "__main__":
    main()
