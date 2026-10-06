#!/usr/bin/env python3
"""Check Xcode's zh-Hant XLIFF against the *pre-export* String Catalog.

Only Python's standard library is required. Xcode does the Swift extraction,
including interpolation types; this script never guesses keys from Swift.
"""

import argparse
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


LANGUAGE = "zh-Hant"
ACCEPTED_STATES = {"translated", "final", "signed-off"}
# Only the internal bundle name stays untranslated. The player-facing
# CFBundleDisplayName must have a translated target, like other UI strings.
APP_NAMES = {"CFBundleName": "RailwayGame"}


def string_units(node):
    """Include every plural/device/substitution variant, not just stringUnit."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "stringUnit":
                yield value
            else:
                yield from string_units(value)


def catalog_issues(catalog):
    issues = []
    if catalog.get("sourceLanguage") != "en":
        issues.append("Catalog sourceLanguage must be en")
    strings = catalog["strings"]
    if not strings:
        issues.append("Catalog contains no strings")
    for key, entry in sorted(strings.items()):
        units = list(string_units(entry.get("localizations", {}).get(LANGUAGE, {})))
        if not units:
            issues.append(f"{key!r}: catalog has no {LANGUAGE} translation")
        for unit in units:
            if unit.get("state") != "translated" or not unit.get("value", "").strip():
                issues.append(f"{key!r}: catalog translation is empty or needs review "
                              f"(state={unit.get('state')!r})")
    return issues


def element_text(element):
    return "" if element is None else "".join(element.itertext())


def check_exports(export_path, catalog):
    issues = catalog_issues(catalog)
    files = ([export_path] if export_path.is_file()
             else sorted(export_path.rglob("*.xliff")))
    if not files:
        return issues + [f"No XLIFF found in {export_path}"]
    count = 0
    localizable_count = 0
    for path in files:
        root = ET.parse(path).getroot()
        if root.tag != "{urn:oasis:names:tc:xliff:document:1.2}xliff":
            issues.append(f"{path}: expected Xcode XLIFF 1.2")
            continue
        ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
        for file in root.findall("x:file", ns):
            original = file.get("original", "")
            language = file.get("target-language")
            if language != LANGUAGE:
                issues.append(f"{path}: {original}: expected target-language={LANGUAGE}, "
                              f"got {language!r}")
            for unit in file.findall(".//x:trans-unit", ns):
                count += 1
                key = unit.get("id", "")
                source = element_text(unit.find("x:source", ns))
                context = f"{source!r} [{original}, id={key!r}]"
                # Xcode also exports generated InfoPlist app-name metadata.
                if (Path(original).name in {"InfoPlist.strings", "RailwayGame-InfoPlist.strings"}
                        and APP_NAMES.get(key) == source):
                    continue
                if Path(original).name in {"Localizable.xcstrings", "Localizable.strings"}:
                    localizable_count += 1
                    # Xcode uses |==| to append catalog plural/device variant IDs.
                    catalog_key = key.split("|==|", 1)[0]
                    if catalog_key not in catalog["strings"]:
                        issues.append(f"{context}: missing from committed Localizable.xcstrings")
                target = unit.find("x:target", ns)
                if target is None or not element_text(target).strip():
                    issues.append(f"{context}: missing {LANGUAGE} target")
                    continue
                # XLIFF state is optional; catalog states are checked separately.
                state = target.get("state")
                if state is not None and state not in ACCEPTED_STATES:
                    issues.append(f"{context}: {LANGUAGE} target needs translation/review "
                                  f"(state={state!r})")
                if unit.get("approved") == "no":
                    issues.append(f"{context}: translation is not approved")
    if not count:
        issues.append("Export contains no trans-unit elements")
    if not localizable_count:
        issues.append("Export contains no Localizable trans-unit elements")
    print(f"Read {len(files)} XLIFF file(s): {count} trans-unit(s), "
          f"{localizable_count} Localizable unit(s), "
          f"{len(catalog['strings'])} committed catalog key(s).")
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", required=True, type=Path,
                        help=".xliff file or directory containing exported .xcloc folders")
    parser.add_argument("--catalog", required=True, type=Path,
                        help="Localizable.xcstrings saved BEFORE xcodebuild exportLocalizations")
    args = parser.parse_args()
    try:
        catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
        issues = check_exports(args.export, catalog)
    except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as error:
        print(f"Localization check could not read inputs: {error}", file=sys.stderr)
        return 1
    for issue in issues:
        print(f"ERROR: {issue}", file=sys.stderr)
    if issues:
        print(f"Localization check failed: {len(issues)} issue(s).", file=sys.stderr)
        return 1
    print("Localization check passed: exported zh-Hant targets and committed catalog are complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
