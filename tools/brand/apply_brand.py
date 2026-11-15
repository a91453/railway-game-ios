#!/usr/bin/env python3
"""Put the released game's brand into a working copy before Xcode builds it.

The public repository carries only the neutral brand (GameBrand.neutral in
Sources/GamePresentation/GameBrand.swift): the released game's name, save
extension, website and mailbox are kept in the private assets repository
(branding/game-brand.json) and in the repository secret GAME_BRAND_JSON.
This script writes them into the files the app is built from:

  RailwayGameApp/Resources/GameBrand.json         what the app reads
  RailwayGameApp/Resources/en.lproj/InfoPlist.strings
  RailwayGameApp/Resources/zh-Hant.lproj/InfoPlist.strings
  RailwayGameApp/Info.plist                       the save type's name and extension

It changes the working copy only: never commit what it writes
(GameBrandTests fails when the committed files are not neutral). Undo it with

  git checkout -- RailwayGameApp/Resources/GameBrand.json \\
    RailwayGameApp/Resources/en.lproj/InfoPlist.strings \\
    RailwayGameApp/Resources/zh-Hant.lproj/InfoPlist.strings RailwayGameApp/Info.plist

Usage:
  python3 -I tools/brand/apply_brand.py <brand.json> [--github-mask]

--github-mask first prints a GitHub Actions ::add-mask:: line for each value,
so that the public logs of a run never show them.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "RailwayGameApp"
NEUTRAL = {"english": "Railway Game", "chinese": "鐵道遊戲", "saveExtension": "railwaygame"}
FIELDS = {"english", "chinese", "saveExtension", "website", "contactEmail"}


def fail(message):
    print(f"apply_brand: {message}", file=sys.stderr)
    sys.exit(1)


def read_brand(path):
    try:
        brand = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        fail(f"cannot read the brand: {error}")
    if not isinstance(brand, dict) or not set(brand) <= FIELDS:
        fail(f"the brand must be an object with only {sorted(FIELDS)}")
    for key in ("english", "chinese", "saveExtension"):
        if not isinstance(brand.get(key), str) or not brand[key].strip():
            fail(f"the brand has no {key}")
    for key, value in brand.items():
        if value is not None and (not isinstance(value, str) or re.search(r'["\\<>&\n]', value)):
            fail(f"{key} must be text with no quote, backslash, angle bracket, ampersand or newline")
    if not re.fullmatch(r"[A-Za-z0-9]+", brand["saveExtension"]):
        fail("saveExtension must be letters and digits only")
    website = brand.get("website")
    if website is not None and not re.fullmatch(r"[A-Za-z0-9.-]+", website):
        fail("website must be a host name only, such as www.example.com")
    email = brand.get("contactEmail")
    if email is not None and "@" not in email:
        fail("contactEmail must be a mail address")
    return brand


def replace(path, pairs):
    text = path.read_text(encoding="utf-8")
    for old, new, count in pairs:
        found = text.count(old)
        if found != count:
            fail(f"{path.relative_to(ROOT)}: expected {count} of {old!r}, found {found} (already applied?)")
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1 or any(a not in ("--github-mask",) for a in argv if a.startswith("--")):
        fail("usage: apply_brand.py <brand.json> [--github-mask]")
    brand = read_brand(args[0])
    if "--github-mask" in argv:
        for value in brand.values():
            if value:
                print(f"::add-mask::{value}")
    english, chinese = brand["english"], brand["chinese"]
    replace(APP / "Resources/en.lproj/InfoPlist.strings", [
        ('"CFBundleDisplayName" = "Railway Game";', f'"CFBundleDisplayName" = "{english}";', 1),
        ('"Railway Game Save" = "Railway Game Save";', f'"{english} Save" = "{english} Save";', 1),
    ])
    replace(APP / "Resources/zh-Hant.lproj/InfoPlist.strings", [
        ('"CFBundleDisplayName" = "鐵道遊戲";', f'"CFBundleDisplayName" = "{chinese}";', 1),
        ('"Railway Game Save" = "鐵道遊戲存檔";', f'"{english} Save" = "{chinese}存檔";', 1),
    ])
    replace(APP / "Info.plist", [
        ("<string>Railway Game Save</string>", f"<string>{english} Save</string>", 2),
        ("<string>railwaygame</string>", f"<string>{brand['saveExtension']}</string>", 1),
    ])
    current = json.loads((APP / "Resources/GameBrand.json").read_text(encoding="utf-8"))
    if current != NEUTRAL:
        fail("RailwayGameApp/Resources/GameBrand.json is not the neutral brand (already applied?)")
    out = {key: brand[key] for key in ("english", "chinese", "saveExtension", "website", "contactEmail") if brand.get(key)}
    (APP / "Resources/GameBrand.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n", encoding="utf-8")
    print("apply_brand: the brand is in the working copy (do not commit it).")


if __name__ == "__main__":
    main(sys.argv[1:])
