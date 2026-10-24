#!/usr/bin/env python3
"""Tests game_center_setup.py against a fake App Store Connect on 127.0.0.1.

No Apple account, no secret and no network: the API key is a throwaway P-256
key, every request's token is checked the way App Store Connect checks it
(the TestFlight processing tests' Fixture), and no key, key ID, issuer ID or
token may appear in any output. Used by testflight-checks.yml.

  python3 -I tools/game-center-setup/test_game_center_setup.py
"""

import contextlib
import datetime
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCRIPT = HERE / "game_center_setup.py"
sys.dont_write_bytecode = True


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


setup = load("game_center_setup", SCRIPT)
selftest = load("testflight_selftest", ROOT / ".github" / "scripts" / "testflight-selftest-processing.py")
APP_ID, KEY_ID, ISSUER = selftest.APP_ID, selftest.KEY_ID, selftest.ISSUER
DETAIL = "fake-detail-1"
WRITES = ("POST", "PATCH", "PUT", "DELETE")
# A Saturday afternoon in Taiwan: the first period starts Monday 00:00 there.
NOW = datetime.datetime(2026, 10, 24, 6, 0, tzinfo=datetime.timezone.utc)


class FakeConnect:
    """A small App Store Connect: Game Center details, leaderboards, achievements,
    their versions, localizations and images, and an upload address."""

    def __init__(self):
        self.requests = []
        self.resources = {}
        self.uploads = {}
        self.counter = 0
        self.has_detail = True
        self.refuse_writes = None
        self.page_size = 200
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def handle_one(self, method):
                parsed = urllib.parse.urlsplit(self.path)
                query = dict(urllib.parse.parse_qsl(parsed.query))
                raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
                body = json.loads(raw) if raw and method != "PUT" else None
                fake.requests.append({"method": method, "path": parsed.path, "query": query, "body": body,
                                      "raw": raw, "headers": dict(self.headers)})
                status, payload = fake.answer(method, parsed.path, query, body, raw)
                data = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                self.handle_one("GET")

            def do_POST(self):
                self.handle_one("POST")

            def do_PATCH(self):
                self.handle_one("PATCH")

            def do_PUT(self):
                self.handle_one("PUT")

            def do_DELETE(self):
                self.handle_one("DELETE")

            def log_message(self, *args):
                pass

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    # The store.

    def add(self, kind, attributes, **links):
        self.counter += 1
        resource = {"type": kind, "id": f"{kind}-{self.counter}", "attributes": dict(attributes), "links": links}
        self.resources[resource["id"]] = resource
        return resource

    def children(self, kind, link, parent):
        return [item for item in self.resources.values() if item["type"] == kind and item["links"].get(link) == parent]

    def add_existing(self, kind, attributes, state="PREPARE_FOR_SUBMISSION", localizations=(), image=True):
        """An item App Store Connect already has, with one version and the given localizations."""
        item = self.add(kind, {"archived": False, **attributes}, detail=DETAIL)
        version_kind = kind[:-1] + "Versions"
        version = self.add(version_kind, {"version": 1, "state": state}, parent=item["id"])
        for entry in localizations:
            localization = self.add(kind[:-1] + "Localizations", entry, version=version["id"])
            if image and kind == "gameCenterAchievements":
                self.add("gameCenterAchievementImages",
                         {"fileName": "old.png", "fileSize": 1, "assetDeliveryState": {"state": "COMPLETE"}},
                         localization=localization["id"])
        return item

    def listing(self, kind, query):
        items = self.children(kind, "detail", DETAIL)
        start = int(query.get("cursor", "0"))
        page = items[start:start + self.page_size]
        data, included = [], []
        for item in page:
            versions = self.children(kind[:-1] + "Versions", "parent", item["id"])
            data.append({**self.public(item), "relationships": {"versions": {"data": [
                {"type": version["type"], "id": version["id"]} for version in versions]}}})
            if query.get("include") == "versions":
                included += [self.public(version) for version in versions]
        answer = {"data": data, "included": included, "links": {}}
        if start + self.page_size < len(items):
            answer["links"]["next"] = f"{self.url}/v1/gameCenterDetails/{DETAIL}/{kind}V2?" + urllib.parse.urlencode(
                {**query, "cursor": str(start + self.page_size)})
        return answer

    @staticmethod
    def public(resource):
        return {"type": resource["type"], "id": resource["id"], "attributes": resource["attributes"]}

    def answer(self, method, path, query, body, raw):
        parts = path.strip("/").split("/")
        if method in WRITES and self.refuse_writes:
            return self.refuse_writes
        if method == "GET" and path == f"/v1/apps/{APP_ID}/gameCenterDetail":
            if not self.has_detail:
                return 404, {"errors": [{"status": "404", "title": "The specified resource does not exist"}]}
            return 200, {"data": {"type": "gameCenterDetails", "id": DETAIL}}
        if method == "GET" and parts[:3] == ["v1", "gameCenterDetails", DETAIL]:
            kind = {"gameCenterLeaderboardsV2": "gameCenterLeaderboards",
                    "gameCenterAchievementsV2": "gameCenterAchievements"}[parts[3]]
            return 200, self.listing(kind, query)
        if method == "GET" and len(parts) == 4 and parts[3] == "versions":
            versions = self.children(parts[1][:-1] + "Versions", "parent", parts[2])
            return 200, {"data": [self.public(version) for version in versions]}
        if method == "GET" and len(parts) == 4 and parts[3] == "localizations":
            kind = parts[1].replace("Versions", "Localizations")
            data, included = [], []
            for localization in self.children(kind, "version", parts[2]):
                images = self.children("gameCenterAchievementImages", "localization", localization["id"])
                relationships = {"image": {"data": {"type": images[0]["type"], "id": images[0]["id"]}
                                           if images else None}}
                data.append({**self.public(localization), "relationships": relationships})
                if query.get("include") == "image":
                    included += [self.public(image) for image in images]
            return 200, {"data": data, "included": included}
        if method == "POST" and path in ("/v2/gameCenterLeaderboards", "/v2/gameCenterAchievements"):
            kind = parts[1]
            data = body["data"]
            if any(self.public(item)["attributes"].get("vendorIdentifier") == data["attributes"]["vendorIdentifier"]
                   for item in self.children(kind, "detail", DETAIL)):
                return 409, {"errors": [{"status": "409", "title": "The vendor identifier is taken"}]}
            assert data["relationships"]["gameCenterDetail"]["data"]["id"] == DETAIL
            local = data["relationships"]["versions"]["data"][0]["id"]
            assert [item["id"] for item in body["included"]] == [local]
            item = self.add(kind, {**data["attributes"], "archived": False}, detail=DETAIL)
            self.add(kind[:-1] + "Versions", {"version": 1, "state": "PREPARE_FOR_SUBMISSION"}, parent=item["id"])
            return 201, {"data": self.public(item)}
        if method == "POST" and path in ("/v2/gameCenterLeaderboardLocalizations",
                                         "/v2/gameCenterAchievementLocalizations"):
            data = body["data"]
            version = data["relationships"]["version"]["data"]["id"]
            assert self.resources[version]["type"] == data["relationships"]["version"]["data"]["type"]
            item = self.add(parts[1], data["attributes"], version=version)
            return 201, {"data": self.public(item)}
        if method == "POST" and path == "/v2/gameCenterAchievementImages":
            data = body["data"]
            localization = data["relationships"]["localization"]["data"]["id"]
            size = data["attributes"]["fileSize"]
            item = self.add("gameCenterAchievementImages", {**data["attributes"],
                            "assetDeliveryState": {"state": "AWAITING_UPLOAD"}}, localization=localization)
            half = size // 2
            item["attributes"]["uploadOperations"] = [
                {"method": "PUT", "url": f"{self.url}/upload/{item['id']}/0", "offset": 0, "length": half,
                 "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]},
                {"method": "PUT", "url": f"{self.url}/upload/{item['id']}/1", "offset": half, "length": size - half,
                 "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}]
            return 201, {"data": self.public(item)}
        if method == "PUT" and parts[0] == "upload":
            self.uploads.setdefault(parts[1], {})[int(parts[2])] = raw
            return 200, {}
        if method == "PATCH" and parts[:2] == ["v2", "gameCenterAchievementImages"]:
            item = self.resources[parts[2]]
            assert body["data"]["attributes"] == {"uploaded": True}
            item["attributes"]["assetDeliveryState"] = {"state": "UPLOAD_COMPLETE"}
            return 200, {"data": self.public(item)}
        return 404, {"errors": [{"status": "404", "title": f"no fake for {method} {path}"}]}

    def writes(self):
        return [request for request in self.requests if request["method"] in WRITES]


class SetupTests(selftest.Fixture):
    def setUp(self):
        os.environ["NO_PROXY"] = os.environ["no_proxy"] = "127.0.0.1,localhost"
        self.fake = FakeConnect()
        self.addCleanup(self.fake.close)
        self.data = setup.load()
        # The JSON with a stand-in image for every achievement, as after #1158.
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.data_path = Path(folder.name) / "game-center.json"
        shutil.copy(setup.DATA, self.data_path)
        for number, item in enumerate(self.data["achievements"]):
            path = setup.image_path(item, self.data_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"\x89PNG fake image " + item["vendorIdentifier"].encode() * (number + 1))

    def run_tool(self, apply, only="all", data=None, data_path=None):
        data_path = data_path or self.data_path
        client = setup.asc.Client(KEY_ID, ISSUER, self.key_path, self.fake.url)
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as folder:
            summary = Path(folder) / "summary.md"
            os.environ["GITHUB_STEP_SUMMARY"] = str(summary)
            try:
                with contextlib.redirect_stdout(out):
                    status, store = setup.run(client, APP_ID, apply, only, data or self.data, data_path, NOW)
            finally:
                del os.environ["GITHUB_STEP_SUMMARY"]
            text = summary.read_text(encoding="utf-8") if summary.exists() else ""
        for request in self.fake.requests:
            if request["path"].startswith("/upload/"):
                self.assertNotIn("Authorization", request["headers"])
            else:
                self.check_token(request["headers"].get("Authorization", ""))
        self.assert_no_secret(out.getvalue(), text)
        return status, store, out.getvalue(), text

    def posted(self, path):
        return [request["body"]["data"] for request in self.fake.requests
                if request["method"] == "POST" and request["path"] == path]

    def test_a_dry_run_sends_no_write_and_lists_everything(self):
        status, store, out, summary = self.run_tool(apply=False)
        self.assertEqual(status, 0)
        self.assertEqual(self.fake.writes(), [])
        self.assertEqual(store.writes, 0)
        self.assertIn("新的項目 39 個、語言 78 個、圖 76 張；先不建 0 個。", out)
        self.assertIn("這是 dry run", out)
        for item in self.data["leaderboards"] + self.data["achievements"]:
            self.assertIn(f"`{item['vendorIdentifier']}`：新建", out)
            self.assertIn(f"`{item['vendorIdentifier']}`：新建", summary)

    def test_apply_creates_every_row_of_the_table(self):
        status, store, out, summary = self.run_tool(apply=True)
        self.assertEqual(status, 0, out)
        self.assertIn("全部建好了", out)
        achievements = self.posted("/v2/gameCenterAchievements")
        self.assertEqual(len(self.data["achievements"]), 38)
        self.assertEqual([item["attributes"] for item in achievements], [
            {"referenceName": item["referenceName"], "points": item["points"],
             "showBeforeEarned": item["showBeforeEarned"], "repeatable": item["repeatable"],
             "vendorIdentifier": item["vendorIdentifier"]} for item in self.data["achievements"]])
        localizations = self.posted("/v2/gameCenterAchievementLocalizations")
        wanted = sorted((entry["locale"], entry["name"], entry["description"])
                        for item in self.data["achievements"] for entry in item["localizations"])
        self.assertEqual(sorted((item["attributes"]["locale"], item["attributes"]["name"],
                                 item["attributes"]["beforeEarnedDescription"]) for item in localizations), wanted)
        for item in localizations:
            self.assertEqual(item["attributes"]["afterEarnedDescription"], item["attributes"]["beforeEarnedDescription"])
        # Every image arrived whole, in its parts, and was marked uploaded.
        images = [item for item in self.fake.resources.values() if item["type"] == "gameCenterAchievementImages"]
        self.assertEqual(len(images), 76)
        by_name = {item["vendorIdentifier"]: item for item in self.data["achievements"]}
        for image in images:
            self.assertEqual(image["attributes"]["assetDeliveryState"], {"state": "UPLOAD_COMPLETE"})
            parts = self.fake.uploads[image["id"]]
            achievement = by_name[image["attributes"]["fileName"][:-len(".png")]]
            self.assertEqual(parts[0] + parts[1], setup.image_path(achievement, self.data_path).read_bytes())

        leaderboard = self.posted("/v2/gameCenterLeaderboards")
        self.assertEqual(len(leaderboard), 1)
        self.assertEqual(leaderboard[0]["attributes"], {
            "referenceName": "Weekly challenge days v2", "vendorIdentifier": "weekly.days.v2",
            "defaultFormatter": "INTEGER", "submissionType": "BEST_SCORE", "scoreSortType": "ASC",
            "scoreRangeStart": "1", "scoreRangeEnd": "1080",
            "recurrenceStartDate": "2026-10-25T16:00:00Z", "recurrenceDuration": "PT168H",
            "recurrenceRule": "FREQ=WEEKLY;INTERVAL=1"})
        self.assertEqual(sorted((item["attributes"]["locale"], item["attributes"]["name"],
                                 item["attributes"]["formatterSuffixSingular"], item["attributes"]["formatterSuffix"])
                                for item in self.posted("/v2/gameCenterLeaderboardLocalizations")),
                         [("en-US", "Weekly Challenge", " day", " days"), ("zh-Hant", "每週挑戰", " 天", " 天")])
        # The full list is printed before the first write.
        self.assertLess(out.index("achievement.fleetInvestment`：新建"), out.index("建好了：weekly.days.v2"))
        self.assertFalse([request for request in self.fake.requests if request["method"] == "DELETE"])

    def test_a_second_apply_skips_everything(self):
        self.run_tool(apply=True)
        before = len(self.fake.writes())
        status, store, out, _ = self.run_tool(apply=True)
        self.assertEqual(status, 0)
        self.assertEqual(store.writes, 0)
        self.assertEqual(len(self.fake.writes()), before)
        self.assertIn("新的項目 0 個、語言 0 個、圖 0 張", out)
        self.assertIn("沒有要建立的東西", out)

    def test_an_existing_id_is_not_changed_only_completed(self):
        first = self.data["achievements"][0]
        english = next(entry for entry in first["localizations"] if entry["locale"] == "en-US")
        existing = self.fake.add_existing("gameCenterAchievements", {
            "vendorIdentifier": first["vendorIdentifier"], "referenceName": first["referenceName"],
            "points": first["points"] + 5, "showBeforeEarned": True, "repeatable": False},
            localizations=[{"locale": "en-US", "name": english["name"], "beforeEarnedDescription": "Old",
                            "afterEarnedDescription": english["description"]}])
        self.fake.add_existing("gameCenterLeaderboards", {"vendorIdentifier": "weekly.days.v2",
                                                         "referenceName": "Weekly challenge days v2"},
                               localizations=[{"locale": "en-US", "name": "Weekly Challenge"},
                                              {"locale": "zh-Hant", "name": "每週挑戰"}])
        status, _, out, _ = self.run_tool(apply=True)
        self.assertEqual(status, 0, out)
        self.assertNotIn(first["vendorIdentifier"],
                         [item["attributes"]["vendorIdentifier"] for item in self.posted("/v2/gameCenterAchievements")])
        self.assertEqual(self.posted("/v2/gameCenterLeaderboards"), [])
        self.assertEqual(self.posted("/v2/gameCenterLeaderboardLocalizations"), [])
        self.assertEqual(len(self.posted("/v2/gameCenterAchievements")), 37)
        # Only the missing language (and its image) was added to the existing one.
        version = self.fake.children("gameCenterAchievementVersions", "parent", existing["id"])[0]
        added = [item for item in self.posted("/v2/gameCenterAchievementLocalizations")
                 if item["relationships"]["version"]["data"]["id"] == version["id"]]
        self.assertEqual([item["attributes"]["locale"] for item in added], ["zh-Hant"])
        patched = [request["path"] for request in self.fake.requests if request["method"] == "PATCH"]
        self.assertTrue(all(path.startswith("/v2/gameCenterAchievementImages/") for path in patched))
        self.assertEqual(self.fake.resources[existing["id"]]["attributes"]["points"], first["points"] + 5)
        self.assertIn("注意（不會改）：points is", out)
        self.assertIn("en-US: beforeEarnedDescription is 'Old'", out)
        self.assertIn(f"`{first['vendorIdentifier']}`：已經有了，不動", out)

    def test_a_version_past_editing_gets_nothing(self):
        first = self.data["achievements"][0]
        self.fake.add_existing("gameCenterAchievements", {
            "vendorIdentifier": first["vendorIdentifier"], "referenceName": first["referenceName"],
            "points": first["points"], "showBeforeEarned": True, "repeatable": False}, state="LIVE")
        status, _, out, _ = self.run_tool(apply=True, only="achievements")
        self.assertEqual(status, 0, out)
        self.assertIn("its version is LIVE", out)
        self.assertEqual(len(self.posted("/v2/gameCenterAchievementLocalizations")), 37 * 2)

    def test_a_refused_key_stops_with_the_role_hint(self):
        self.fake.refuse_writes = (403, {"errors": [{"status": "403", "code": "FORBIDDEN_ERROR",
                                                     "title": "This request is forbidden for security reasons",
                                                     "detail": "The API key in use does not allow this request"}]})
        status, _, out, _ = self.run_tool(apply=True)
        self.assertEqual(status, 1)
        self.assertEqual(len(self.fake.writes()), 1)
        self.assertIn("HTTP 403", out)
        self.assertIn("要 Admin 或 App Manager", out)

    def test_no_game_center_yet(self):
        self.fake.has_detail = False
        status, _, out, _ = self.run_tool(apply=True)
        self.assertEqual(status, 1)
        self.assertIn("this app has no Game Center in App Store Connect yet", out)
        self.assertEqual(self.fake.writes(), [])

    def test_achievements_wait_for_their_images(self):
        with tempfile.TemporaryDirectory() as folder:
            data_path = Path(folder) / "game-center.json"
            shutil.copy(setup.DATA, data_path)
            status, _, out, _ = self.run_tool(apply=True, data_path=data_path)
        self.assertEqual(status, 0, out)
        self.assertEqual(len(self.posted("/v2/gameCenterLeaderboards")), 1)
        self.assertEqual(self.posted("/v2/gameCenterAchievements"), [])
        self.assertIn("先不建 38 個", out)

    def test_only_leaderboards_reads_no_achievements(self):
        status, _, out, _ = self.run_tool(apply=False, only="leaderboards")
        self.assertEqual(status, 0)
        self.assertFalse([request for request in self.fake.requests if "Achievement" in request["path"]])
        self.assertIn("新的項目 1 個", out)

    def test_lists_are_read_page_by_page(self):
        self.run_tool(apply=True)
        self.fake.page_size = 5
        status, store, out, _ = self.run_tool(apply=False)
        self.assertEqual(status, 0)
        self.assertIn("新的項目 0 個", out)

    def test_the_tool_as_the_workflow_runs_it(self):
        settings = {"ASC_APP_ID": APP_ID, "ASC_KEY_ID": KEY_ID, "ASC_ISSUER_ID": ISSUER,
                    "ASC_PRIVATE_KEY": "\r\n" + self.key_text.replace("\n", "\r\n"), "ASC_API_URL": self.fake.url}
        result = subprocess.run([sys.executable, "-I", str(SCRIPT)], env=selftest.clean_env(**settings),
                                capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("這是 dry run", result.stdout)
        self.assertEqual(self.fake.writes(), [])
        self.assert_no_secret(result.stdout, result.stderr)
        missing = subprocess.run([sys.executable, "-I", str(SCRIPT), "--apply"],
                                 env=selftest.clean_env(ASC_APP_ID=APP_ID), capture_output=True, text=True, timeout=60)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("ASC_KEY_ID is not set.", missing.stdout)


class DataTests(unittest.TestCase):
    def test_the_doc_shows_the_json(self):
        result = subprocess.run([sys.executable, "-I", str(SCRIPT), "--check-doc"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_the_table(self):
        data = setup.load()
        self.assertEqual(len(data["achievements"]), 38)
        self.assertEqual(sum(item["points"] for item in data["achievements"]), 800)
        self.assertEqual([item["vendorIdentifier"] for item in data["leaderboards"]], ["weekly.days.v2"])

    def test_the_first_period_starts_on_the_next_taiwan_monday(self):
        recurrence = setup.load()["leaderboards"][0]["recurrence"]
        utc = datetime.timezone.utc
        cases = [
            (datetime.datetime(2026, 10, 24, 6, 0, tzinfo=utc), "2026-10-25T16:00:00Z"),
            # Sunday 23:59 in Taiwan: tomorrow.
            (datetime.datetime(2026, 10, 25, 15, 59, tzinfo=utc), "2026-10-25T16:00:00Z"),
            # Monday 00:00 in Taiwan exactly: the week after, never the past.
            (datetime.datetime(2026, 10, 25, 16, 0, tzinfo=utc), "2026-11-01T16:00:00Z"),
        ]
        for now, start in cases:
            self.assertEqual(setup.iso(setup.recurrence_start(recurrence, now)), start)


if __name__ == "__main__":
    unittest.main(verbosity=2)
