#!/usr/bin/env python3
"""Linux/macOS regression tests using a small Xcode-shaped XLIFF fixture."""

import copy
import importlib.util
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
        unit = self.root.findall(".//x:trans-unit", NS)[2]
        unit.find("x:source", NS).text = "A different name"
        self.assertIn("A different name", "\n".join(self.check()))

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


if __name__ == "__main__":
    unittest.main()
