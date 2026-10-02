#!/usr/bin/env python3
"""Give keepAlways UI attachments stable names and require all six PNGs."""

import json
from pathlib import Path
import shutil
import sys


def export(source: Path, destination: Path) -> None:
    manifest = json.loads((source / "manifest.json").read_text())
    expected = {
        f"{language}-0{index}-{tool}"
        for language in ("en", "zh-Hant")
        for index, tool in enumerate(("select", "network", "train"), 1)
    }
    found = set()
    destination.mkdir(parents=True, exist_ok=True)
    for test in manifest:
        for attachment in test["attachments"]:
            name = attachment["suggestedHumanReadableName"]
            # xcresulttool can append an extension to the attachment's name.
            name = name.removesuffix(".png")
            if name not in expected:
                continue
            image = source / attachment["exportedFileName"]
            if image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                raise SystemExit(f"Not a PNG: {image}")
            shutil.copyfile(image, destination / f"{name}.png")
            found.add(name)
    shutil.copyfile(source / "manifest.json", destination / "manifest.json")
    print(f"Exported {len(found)} UI screenshots: {', '.join(sorted(found))}")
    missing = expected - found
    if missing:
        raise SystemExit(f"Missing UI screenshots: {', '.join(sorted(missing))}")


if __name__ == "__main__":
    export(Path(sys.argv[1]), Path(sys.argv[2]))
