#!/usr/bin/env python3
"""Linux/macOS regression tests using small Xcode-shaped fixtures (XLIFF and a synced catalog)."""

import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


SCRIPT = Path(__file__).with_name("check-localization.py")
FIXTURE = SCRIPT.parent / "localization-fixtures" / "zh-Hant.xliff"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("checker", SCRIPT)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)
NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
CATALOG = {"sourceLanguage": "en", "strings": {
    key: {"localizations": {"zh-Hant": {"stringUnit": {
        "state": "translated", "value": value}}}}
    for key, value in [("Train & station", "列車與車站"), ("%lld trains", "%lld 列車")]
}}


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        output = contextlib.redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)
        self.root = ET.parse(FIXTURE).getroot()
        self.catalog = copy.deepcopy(CATALOG)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.export = self.directory / "zh-Hant.xcloc" / "Localized Contents"
        self.export.mkdir(parents=True)
        self.xliff = self.export / "zh-Hant.xliff"

    def check(self):
        ET.ElementTree(self.root).write(self.xliff, encoding="utf-8")
        return CHECKER.check_exports(self.directory, self.catalog)

    def unit(self):
        return self.root.find(".//x:trans-unit", NS)

    def test_translated_and_optional_state_and_app_names(self):
        self.assertEqual(self.check(), [])

    def test_missing_empty_and_blank_target(self):
        target = self.unit().find("x:target", NS)
        for text in ("", "  ", None):
            with self.subTest(text=text):
                target.text = text
                self.assertIn("missing zh-Hant target", "\n".join(self.check()))
        self.unit().remove(target)
        self.assertIn("Train & station", "\n".join(self.check()))

    def test_untranslated_and_review_states(self):
        for state in ("new", "needs-translation", "needs-review-translation",
                      "needs-review-adaptation", "needs-l10n", "unknown"):
            with self.subTest(state=state):
                self.unit().find("x:target", NS).set("state", state)
                self.assertIn(state, "\n".join(self.check()))

    def test_accepted_xliff_states(self):
        for state in ("translated", "final", "signed-off"):
            with self.subTest(state=state):
                self.unit().find("x:target", NS).set("state", state)
                self.assertEqual(self.check(), [])

    def test_unapproved(self):
        self.unit().set("approved", "no")
        self.assertIn("not approved", "\n".join(self.check()))

    def test_new_code_key_even_if_export_has_translation(self):
        del self.catalog["strings"]["Train & station"]
        self.assertIn("missing from committed", "\n".join(self.check()))

    def test_interpolation_key_and_variant_id(self):
        unit = self.root.findall(".//x:trans-unit", NS)[1]
        unit.set("id", "%lld trains|==|plural.other")
        self.assertEqual(self.check(), [])

    def test_catalog_translation_review_or_missing(self):
        entry = self.catalog["strings"]["Train & station"]
        entry["localizations"]["zh-Hant"]["stringUnit"]["state"] = "needs_review"
        self.assertIn("needs_review", "\n".join(self.check()))
        entry.clear()
        self.assertIn("catalog has no zh-Hant", "\n".join(self.check()))

    def test_all_catalog_variants(self):
        self.catalog["strings"]["%lld trains"]["localizations"]["zh-Hant"] = {
            "variations": {"plural": {
                "other": {"stringUnit": {"state": "translated", "value": "%lld 列車"}},
                "one": {"stringUnit": {"state": "new", "value": "%lld 列車"}}}}}
        self.assertIn("state='new'", "\n".join(self.check()))

    def test_wrong_language(self):
        self.root.find("x:file", NS).set("target-language", "zh-Hans")
        self.assertIn("expected target-language=zh-Hant", "\n".join(self.check()))

    def test_app_name_exception_is_exact(self):
        unit = self.root.findall(".//x:trans-unit", NS)[3]
        unit.find("x:source", NS).text = "A different name"
        self.assertIn("A different name", "\n".join(self.check()))
        unit.find("x:source", NS).text = "RailwayGame"
        self.root.findall("x:file", NS)[1].set("original", "Localizable.xcstrings")
        self.assertIn("missing zh-Hant target", "\n".join(self.check()))

    def test_display_name_requires_translation(self):
        unit = self.root.findall(".//x:trans-unit", NS)[2]
        unit.remove(unit.find("x:target", NS))
        self.assertIn("CFBundleDisplayName", "\n".join(self.check()))
        self.assertIn("missing zh-Hant target", "\n".join(self.check()))

    def test_absent_empty_and_unsupported_exports(self):
        self.assertIn("No XLIFF", "\n".join(CHECKER.check_exports(self.directory, self.catalog)))
        for xml in ('<xliff/>', '<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2"/>'):
            self.xliff.write_text(xml, encoding="utf-8")
            self.assertTrue(CHECKER.check_exports(self.directory, self.catalog))

    def test_cli_exit_status_and_diagnostic(self):
        catalog = self.directory / "Localizable.xcstrings"
        catalog.write_text(json.dumps(self.catalog), encoding="utf-8")
        self.assertEqual(self.check(), [])
        command = [sys.executable, str(SCRIPT), "--export", str(self.directory),
                   "--catalog", str(catalog)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.unit().remove(self.unit().find("x:target", NS))
        self.check()
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Train & station", result.stderr)
        self.xliff.write_text("broken XML", encoding="utf-8")
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not read inputs", result.stderr)


EN_INFOPLIST = """/* Home Screen name. */
"CFBundleDisplayName" = "Along the Line";
// A line comment.
"NSLocationWhenInUseUsageDescription" = "Your location is used \\"once\\".";
"Along the Line Save" = "Along the Line Save";
"""
ZH_INFOPLIST = """"CFBundleDisplayName" = "沿線";
"NSLocationWhenInUseUsageDescription" = "用一次你的位置。";
"Along the Line Save" = "沿線存檔";
"""
INFO = {"CFBundleName": "RailwayGame", "CFBundleDisplayName": "Along the Line",
        "NSLocationWhenInUseUsageDescription": "Your location is used \"once\".",
        "CFBundleIdentifier": "io.github.a91453.RailwayGame",
        "CFBundleDocumentTypes": [{"CFBundleTypeName": "Along the Line Save"}],
        "UTExportedTypeDeclarations": [{"UTTypeDescription": "Along the Line Save"}]}


class SyncedCatalogTests(unittest.TestCase):
    """Decision 638: the build's extraction, synced into a catalog copy."""

    def setUp(self):
        output = contextlib.redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)
        self.catalog = copy.deepcopy(CATALOG)
        # What xcstringstool sync leaves when the code has the same keys.
        self.synced = copy.deepcopy(CATALOG)
        self.info = copy.deepcopy(INFO)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.source = self.directory / "en.InfoPlist.strings"
        self.target = self.directory / "zh-Hant.InfoPlist.strings"
        self.source.write_text(EN_INFOPLIST, encoding="utf-8")
        self.target.write_text(ZH_INFOPLIST, encoding="utf-8")

    def check(self):
        return CHECKER.check_synced(self.synced, self.catalog, self.info,
                                    self.source, self.target)

    def test_complete_passes(self):
        self.assertEqual(self.check(), [])

    def test_strings_file_parser(self):
        pairs = CHECKER.strings_file(self.source)
        self.assertEqual(pairs["NSLocationWhenInUseUsageDescription"],
                         'Your location is used "once".')
        self.assertEqual(len(pairs), 3)
        for broken in ('"a" = "b"', '"a" "b";', '"a = "b";', '/* open', 'a = "b";'):
            with self.subTest(broken=broken):
                self.source.write_text(broken, encoding="utf-8")
                with self.assertRaises(ValueError):
                    CHECKER.strings_file(self.source)

    def test_new_code_key_missing_from_committed_catalog(self):
        # sync adds a key the code uses and the catalog lacks, untranslated.
        self.synced["strings"]["New button"] = {}
        self.assertIn("'New button' [Localizable.xcstrings]: in the app's code but missing "
                      "from committed", "\n".join(self.check()))

    def test_missing_catalog_translation(self):
        del self.catalog["strings"]["Train & station"]["localizations"]["zh-Hant"]
        self.assertIn("catalog has no zh-Hant", "\n".join(self.check()))
        self.catalog["strings"]["Train & station"]["localizations"]["zh-Hant"] = {
            "stringUnit": {"state": "new", "value": ""}}
        self.assertIn("needs review", "\n".join(self.check()))

    def test_stale_keys_are_a_note_but_all_stale_fails(self):
        self.synced["strings"]["Train & station"]["extractionState"] = "stale"
        self.assertEqual(self.check(), [])
        for entry in self.synced["strings"].values():
            entry["extractionState"] = "stale"
        self.assertIn("found none", "\n".join(self.check()))
        self.synced["strings"] = {}
        self.assertIn("found none", "\n".join(self.check()))
        del self.synced["strings"]
        self.assertIn("no strings", "\n".join(self.check()))

    def test_wrong_source_language(self):
        self.synced["sourceLanguage"] = "zh-Hant"
        self.assertIn("sourceLanguage", "\n".join(self.check()))

    def test_infoplist_target_missing_or_blank(self):
        self.target.write_text('"CFBundleDisplayName" = "沿線";\n'
                               '"Along the Line Save" = " ";\n', encoding="utf-8")
        text = "\n".join(self.check())
        self.assertIn("id='NSLocationWhenInUseUsageDescription'", text)
        self.assertIn("id='Along the Line Save'", text)
        self.assertNotIn("CFBundleDisplayName", text)

    def test_built_info_plist_string_missing_from_infoplist_strings(self):
        self.info["NSCameraUsageDescription"] = "Takes a photo."
        self.assertIn("id='NSCameraUsageDescription'", "\n".join(self.check()))
        del self.info["NSCameraUsageDescription"]
        self.info["UTExportedTypeDeclarations"][0]["UTTypeDescription"] = "Another Save"
        self.assertIn("'Another Save' [Info.plist", "\n".join(self.check()))

    def test_app_name_exception_is_exact(self):
        self.info["CFBundleName"] = "Another Name"
        self.assertIn("id='CFBundleName'", "\n".join(self.check()))

    def test_cli(self):
        catalog = self.directory / "catalog.xcstrings"
        synced = self.directory / "synced.xcstrings"
        info = self.directory / "Info.json"
        catalog.write_text(json.dumps(self.catalog), encoding="utf-8")
        info.write_text(json.dumps(self.info), encoding="utf-8")
        command = [sys.executable, str(SCRIPT), "--synced", str(synced), "--catalog",
                   str(catalog), "--info-plist", str(info), "--infoplist-source",
                   str(self.source), "--infoplist-target", str(self.target)]
        synced.write_text(json.dumps(self.synced), encoding="utf-8")
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.synced["strings"]["New button"] = {}
        synced.write_text(json.dumps(self.synced), encoding="utf-8")
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("New button", result.stderr)
        result = subprocess.run(command[:6], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--synced needs", result.stderr)


if __name__ == "__main__":
    unittest.main()
