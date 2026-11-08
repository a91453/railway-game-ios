#!/usr/bin/env python3
"""Check the app's zh-Hant translations against the committed String Catalog.

Two inputs say which strings the app's code uses, both made by Xcode:

- --synced (decision 638, what CI uses): a copy of the committed catalog that
  `xcrun xcstringstool sync` updated from the .stringsdata files the Swift
  compiler wrote while building the app with SWIFT_EMIT_LOC_STRINGS=YES,
  plus the en and zh-Hant InfoPlist.strings (--infoplist-source/-target).
- --export: Xcode's zh-Hant XLIFF from `xcodebuild -exportLocalizations`,
  which builds the whole app again (CI used it until decision 638).

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


def strings_file(path):
    """Keys and values of an old-style .strings file (InfoPlist.strings)."""
    text = path.read_text(encoding="utf-8")
    pairs, tokens, i = {}, [], 0
    escapes = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'"}
    while i < len(text):
        char = text[i]
        if char.isspace():
            i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError(f"{path}: unterminated comment")
            i = end + 2
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
        elif char in "=;":
            tokens.append(char)
            i += 1
        elif char == '"':
            value, i = [], i + 1
            while i < len(text) and text[i] != '"':
                if text[i] == "\\" and i + 1 < len(text):
                    value.append(escapes.get(text[i + 1], text[i + 1]))
                    i += 2
                else:
                    value.append(text[i])
                    i += 1
            if i >= len(text):
                raise ValueError(f"{path}: unterminated string")
            tokens.append(("s", "".join(value)))
            i += 1
        else:
            raise ValueError(f"{path}: unexpected {char!r} at offset {i}")
    for start in range(0, len(tokens), 4):
        entry = tokens[start:start + 4]
        if (len(entry) != 4 or not isinstance(entry[0], tuple) or entry[1] != "="
                or not isinstance(entry[2], tuple) or entry[3] != ";"):
            raise ValueError(f"{path}: expected \"key\" = \"value\"; entries")
        pairs[entry[0][1]] = entry[2][1]
    return pairs


# Info.plist keys whose values players see, as Xcode exports them to
# InfoPlist.strings; plus any key ending in UsageDescription.
INFO_PLIST_KEYS = {"CFBundleDisplayName", "CFBundleName", "CFBundleSpokenName",
                   "NSHumanReadableCopyright"}


def info_plist_strings(info):
    """(key, value) of the built Info.plist strings that are localized."""
    found = []
    for key, value in info.items():
        if isinstance(value, str) and (key in INFO_PLIST_KEYS
                                       or key.endswith("UsageDescription")):
            found.append((key, value))
    # Document and exported type names are localized by their value.
    for group, name in (("CFBundleDocumentTypes", "CFBundleTypeName"),
                        ("UTExportedTypeDeclarations", "UTTypeDescription"),
                        ("UTImportedTypeDeclarations", "UTTypeDescription")):
        for entry in info.get(group, []):
            if isinstance(entry, dict) and isinstance(entry.get(name), str):
                found.append((entry[name], entry[name]))
    return found


def check_synced(synced, catalog, info, infoplist_source, infoplist_target):
    """The same failures as check_exports, from the build's own extraction.

    The export's Localizable units are the synced catalog's keys (with their
    plural and device variants, which catalog_issues checks in the committed
    catalog), and its InfoPlist units are the en InfoPlist.strings keys and
    the built Info.plist's player-facing strings, with the zh-Hant
    InfoPlist.strings values as targets.
    """
    issues = catalog_issues(catalog)
    strings = synced.get("strings")
    if not isinstance(strings, dict):
        return issues + ["Synced catalog has no strings"]
    if synced.get("sourceLanguage") != "en":
        issues.append("Synced catalog sourceLanguage must be en")
    for key in sorted(strings):
        if key not in catalog["strings"]:
            issues.append(f"{key!r} [Localizable.xcstrings]: in the app's code but missing "
                          f"from committed Localizable.xcstrings")
    stale = sorted(key for key, entry in strings.items()
                   if entry.get("extractionState") == "stale")
    in_code = len(strings) - len(stale)
    # A sync that read no .stringsdata marks every key stale: then nothing
    # was checked against the code, which must not pass.
    if not in_code:
        issues.append("The sync found none of the catalog's strings in the app's code "
                      "(no .stringsdata read?)")
    for key in stale:
        print(f"Note: {key!r} is in the committed catalog but no longer in the app's code.")
    source, target = strings_file(infoplist_source), strings_file(infoplist_target)
    if not source:
        issues.append(f"{infoplist_source}: no strings")
    # Xcode's export lists these from the built Info.plist even when
    # InfoPlist.strings lacks them, with no target.
    for key, value in info_plist_strings(info):
        if key not in source and APP_NAMES.get(key) != value:
            issues.append(f"{value!r} [Info.plist, id={key!r}]: missing from "
                          f"{infoplist_source.name}, so it has no {LANGUAGE} target")
    for key, value in sorted(source.items()):
        if APP_NAMES.get(key) == value:
            continue
        context = f"{value!r} [InfoPlist.strings, id={key!r}]"
        if not target.get(key, "").strip():
            issues.append(f"{context}: missing {LANGUAGE} target")
    print(f"Read the synced catalog: {len(strings)} key(s), {in_code} in the app's code, "
          f"{len(stale)} no longer in it; {len(source)} InfoPlist string(s); "
          f"{len(catalog['strings'])} committed catalog key(s).")
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--export", type=Path,
                        help=".xliff file or directory containing exported .xcloc folders")
    source.add_argument("--synced", type=Path,
                        help="a copy of the committed catalog after xcstringstool sync "
                             "with the app build's .stringsdata")
    parser.add_argument("--catalog", required=True, type=Path,
                        help="Localizable.xcstrings as committed, before any build or export")
    parser.add_argument("--info-plist", type=Path,
                        help="the built app's Info.plist as JSON (with --synced)")
    parser.add_argument("--infoplist-source", type=Path,
                        help="en.lproj/InfoPlist.strings (with --synced)")
    parser.add_argument("--infoplist-target", type=Path,
                        help="zh-Hant.lproj/InfoPlist.strings (with --synced)")
    args = parser.parse_args()
    if args.synced and not (args.info_plist and args.infoplist_source
                            and args.infoplist_target):
        parser.error("--synced needs --info-plist, --infoplist-source and --infoplist-target")
    try:
        catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
        if args.synced:
            synced = json.loads(args.synced.read_text(encoding="utf-8"))
            info = json.loads(args.info_plist.read_text(encoding="utf-8"))
            issues = check_synced(synced, catalog, info,
                                  args.infoplist_source, args.infoplist_target)
        else:
            issues = check_exports(args.export, catalog)
    except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as error:
        print(f"Localization check could not read inputs: {error}", file=sys.stderr)
        return 1
    for issue in issues:
        print(f"ERROR: {issue}", file=sys.stderr)
    if issues:
        print(f"Localization check failed: {len(issues)} issue(s).", file=sys.stderr)
        return 1
    print("Localization check passed: the app's zh-Hant strings and committed catalog are complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
