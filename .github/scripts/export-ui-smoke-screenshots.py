#!/usr/bin/env python3
"""Give the UI tests' screenshots stable file names.

The screenshots are evidence for a person to look at, not a check: what the UI
tests assert is decided by the tests themselves. So this never fails because a
screenshot is missing or has a new name; it exports every PNG attachment and
says how many it found. It fails only on a PNG attachment that is not a PNG.
"""

import json
from pathlib import Path
import shutil


def export(source: Path, destination: Path) -> int:
    manifest = json.loads((source / "manifest.json").read_text())
    destination.mkdir(parents=True, exist_ok=True)
    found = set()
    for test in manifest:
        for attachment in test["attachments"]:
            image = source / attachment["exportedFileName"]
            # Failure videos and issue descriptions are attachments too.
            if image.suffix.lower() != ".png":
                continue
            # xcresulttool appends _<index>_<UUID>.png to the attachment name.
            name = attachment["suggestedHumanReadableName"].split("_", 1)[0].removesuffix(".png")
            if image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                raise SystemExit(f"Not a PNG: {image}")
            shutil.copyfile(image, destination / f"{name}.png")
            found.add(name)
    shutil.copyfile(source / "manifest.json", destination / "manifest.json")
    print(f"Exported {len(found)} UI screenshots: {', '.join(sorted(found))}")
    if not found:
        # Not an error: a run that failed early has none, and the tests'
        # own result says why.
        print("::warning title=No UI screenshots::The UI tests attached no screenshots.")
    return len(found)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    export(args.source, args.destination)
