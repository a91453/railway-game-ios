#!/usr/bin/env python3
"""Give keepAlways UI attachments stable names and require the UI evidence."""

import json
from pathlib import Path
import shutil


def export(source: Path, destination: Path, *, tutorial_only: bool = False) -> None:
    manifest = json.loads((source / "manifest.json").read_text())
    expected = set() if tutorial_only else {
        f"{language}-0{index}-{tool}"
        for language in ("en", "zh-Hant")
        for index, tool in enumerate(("select", "network", "train"), 1)
    }
    if not tutorial_only:
        expected.update(
            f"{language}-flow-{index:02d}-{step}"
            for language in ("en", "zh-Hant")
            for index, step in enumerate((
                "start-empty", "demo-map", "menu-save", "game-saved",
                "menu-return", "start-saved", "continued-map", "start-reset",
            ), 1)
        )
    expected.update(
        f"{language}-tutorial-{screen}"
        for language in ("en", "zh-Hant", "en-large-text")
        for screen in ("tool", "map", "landscape")
    )
    expected.add("en-tutorial-station-step")
    found = set()
    destination.mkdir(parents=True, exist_ok=True)
    for test in manifest:
        for attachment in test["attachments"]:
            name = attachment["suggestedHumanReadableName"]
            # xcresulttool appends _<index>_<UUID>.png to the attachment name.
            name = name.split("_", 1)[0].removesuffix(".png")
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
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--tutorial-only", action="store_true")
    args = parser.parse_args()
    export(args.source, args.destination, tutorial_only=args.tutorial_only)
