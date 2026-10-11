#!/usr/bin/env python3
"""Tests testflight-processing.py and testflight-changes.py with fakes only.

A fake App Store Connect and a fake GitHub API run on 127.0.0.1, the API key
is a throwaway P-256 key made here, and the history is a throwaway git
repository: no Apple account, no token and no network. Every request's token
is checked as App Store Connect would check it (ES256 signature, key ID,
issuer, audience, lifetime), and no secret may appear in any output.

Runs anywhere Python 3, openssl and git run; used by testflight-checks.yml.
"""

import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HERE = Path(__file__).resolve().parent
PROCESSING = HERE / "testflight-processing.py"
CHANGES = HERE / "testflight-changes.py"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("processing", PROCESSING)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

KEY_ID = "FAKEKEY001"
ISSUER = "00000000-0000-4000-8000-00000000fa6e"
APP_ID = "1000000001"
BUILD_ID = "fake-build-0001"
GITHUB_TOKEN = "FAKE_GITHUB_TOKEN_DO_NOT_PRINT"
REPOSITORY = "owner/game"


def b64decode(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def der_integer(value):
    value = value.lstrip(b"\0") or b"\0"
    if value[0] & 0x80:
        value = b"\0" + value
    return b"\x02" + bytes([len(value)]) + value


class FakeServer:
    """A local HTTP server; `answer(method, path, query, body)` gives (status, JSON)."""

    def __init__(self, answer):
        self.requests = []
        server = self

        class Handler(BaseHTTPRequestHandler):
            def handle_one(self, method):
                parsed = urllib.parse.urlsplit(self.path)
                query = dict(urllib.parse.parse_qsl(parsed.query))
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length)) if length else None
                server.requests.append({"method": method, "path": parsed.path, "query": query,
                                        "body": body, "headers": dict(self.headers),
                                        "raw_query": parsed.query})
                status, payload = answer(method, parsed.path, query, body)
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

            def log_message(self, *args):
                pass

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def clean_env(**extra):
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"),
           "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost",
           "PYTHONDONTWRITEBYTECODE": "1", "LANG": "C.UTF-8"}
    env.update(extra)
    return env


class Fixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        root = Path(cls.folder.name)
        cls.key_path = root / "AuthKey.p8"
        cls.public_path = root / "public.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256",
                        "-out", str(cls.key_path)], check=True, capture_output=True)
        subprocess.run(["openssl", "pkey", "-in", str(cls.key_path), "-pubout", "-out", str(cls.public_path)],
                       check=True, capture_output=True)
        cls.key_text = cls.key_path.read_text()
        assert cls.key_text.startswith("-----BEGIN PRIVATE KEY-----"), "openssl wrote no PKCS #8 key"
        cls.verified_tokens = set()

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def check_token(self, authorization):
        """The checks App Store Connect makes on a team key's token."""
        self.assertTrue(authorization.startswith("Bearer "))
        token = authorization[len("Bearer "):]
        if token in self.verified_tokens:
            return token
        header_part, payload_part, signature_part = token.split(".")
        header = json.loads(b64decode(header_part))
        payload = json.loads(b64decode(payload_part))
        self.assertEqual(header, {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"})
        self.assertEqual(payload["iss"], ISSUER)
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertLessEqual(payload["exp"] - payload["iat"], 20 * 60)
        self.assertGreater(payload["exp"], time.time())
        self.assertLessEqual(payload["iat"], time.time() + 1)
        raw = b64decode(signature_part)
        self.assertEqual(len(raw), 64)
        sequence = der_integer(raw[:32]) + der_integer(raw[32:])
        der = b"\x30" + bytes([len(sequence)]) + sequence
        with tempfile.TemporaryDirectory() as folder:
            signature = Path(folder) / "signature.der"
            signature.write_bytes(der)
            verified = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", str(self.public_path), "-signature", str(signature)],
                input=f"{header_part}.{payload_part}".encode(), capture_output=True)
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)
        self.verified_tokens.add(token)
        return token

    def assert_no_secret(self, *texts):
        key_lines = [line for line in self.key_text.splitlines() if line and "PRIVATE KEY" not in line]
        for text in texts:
            for secret in [KEY_ID, ISSUER, GITHUB_TOKEN, *key_lines, *self.verified_tokens]:
                self.assertNotIn(secret, text)


class ProcessingTests(Fixture):
    def run_processing(self, answer, whats_new="Changes since build 51.1:\n- Level track (#375)", **env):
        server = FakeServer(answer)
        self.addCleanup(server.close)
        with tempfile.TemporaryDirectory() as folder:
            summary = Path(folder) / "summary.md"
            arguments = []
            if whats_new is not None:
                (Path(folder) / "whats-new.txt").write_text(whats_new + "\n", encoding="utf-8")
                arguments = ["--whats-new", str(Path(folder) / "whats-new.txt")]
            settings = {
                "ASC_APP_ID": APP_ID, "ASC_KEY_ID": KEY_ID, "ASC_ISSUER_ID": ISSUER,
                # As a paste may give it: CR line endings and a blank line first.
                "ASC_PRIVATE_KEY": "\r\n" + self.key_text.replace("\n", "\r\n"),
                "BUILD_NUMBER": "52.1", "APP_VERSION": "0.5.0", "ASC_API_URL": server.url,
                "GITHUB_STEP_SUMMARY": str(summary), "POLL_INTERVAL": "0.05", "PROCESSING_TIMEOUT": "20",
            }
            settings.update(env)
            started = time.monotonic()
            result = subprocess.run([sys.executable, "-I", str(PROCESSING), *arguments],
                                    env=clean_env(**{k: v for k, v in settings.items() if v is not None}),
                                    capture_output=True, text=True, timeout=60)
            result.seconds = time.monotonic() - started
            result.summary = summary.read_text(encoding="utf-8") if summary.exists() else ""
        for request in server.requests:
            self.check_token(request["headers"].get("Authorization", ""))
        self.assert_no_secret(result.stdout, result.stderr, result.summary)
        result.requests = server.requests
        return result

    @staticmethod
    def store(states, internal="READY_FOR_BETA_TESTING", localizations=None, primary="en-US",
              patch_status=200):
        """A fake App Store Connect whose build goes through `states`, one per list request."""
        polls = iter(states)
        last = {"state": None}
        localizations = [] if localizations is None else localizations

        def answer(method, path, query, body):
            if method == "GET" and path == "/v1/builds":
                state = next(polls, last["state"])
                last["state"] = state
                if isinstance(state, int):
                    return state, {"errors": [{"title": "Fake error", "detail": f"status {state}"}]}
                if state is None:
                    return 200, {"data": []}
                return 200, {"data": [{"type": "builds", "id": BUILD_ID,
                                       "attributes": {"version": "52.1", "processingState": state}}]}
            if method == "GET" and path == f"/v1/builds/{BUILD_ID}/buildBetaDetail":
                return 200, {"data": {"type": "buildBetaDetails", "id": "detail",
                                      "attributes": {"internalBuildState": internal,
                                                     "externalBuildState": "READY_FOR_BETA_SUBMISSION"}}}
            if method == "GET" and path == f"/v1/builds/{BUILD_ID}/betaBuildLocalizations":
                return 200, {"data": localizations}
            if method == "PATCH" and path.startswith("/v1/betaBuildLocalizations/"):
                return patch_status, {"data": body["data"]} if patch_status == 200 else {
                    "errors": [{"title": "Conflict", "detail": "fake refusal"}]}
            if method == "GET" and path == f"/v1/apps/{APP_ID}":
                return 200, {"data": {"type": "apps", "id": APP_ID, "attributes": {"primaryLocale": primary}}}
            if method == "POST" and path == "/v1/betaBuildLocalizations":
                return 201, {"data": {"type": "betaBuildLocalizations", "id": "new", **body["data"]}}
            return 404, {"errors": [{"title": "Not found", "detail": path}]}

        return answer

    def requests_to(self, result, method, path):
        return [request for request in result.requests if request["method"] == method and request["path"] == path]

    def test_waits_until_valid_and_fills_every_localization(self):
        localizations = [{"type": "betaBuildLocalizations", "id": "loc-en", "attributes": {"locale": "en-US"}},
                         {"type": "betaBuildLocalizations", "id": "loc-zh", "attributes": {"locale": "zh-Hant"}}]
        result = self.run_processing(self.store([None, None, "PROCESSING", "PROCESSING", "VALID"],
                                                internal="MISSING_EXPORT_COMPLIANCE",
                                                localizations=localizations))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        polls = self.requests_to(result, "GET", "/v1/builds")
        self.assertEqual(len(polls), 5)
        self.assertEqual(polls[0]["query"], {"filter[app]": APP_ID, "filter[version]": "52.1",
                                             "filter[preReleaseVersion.version]": "0.5.0", "limit": "1"})
        self.assertIn("filter[app]=", polls[0]["raw_query"])
        patches = [r for r in result.requests if r["method"] == "PATCH"]
        self.assertEqual([r["path"] for r in patches],
                         ["/v1/betaBuildLocalizations/loc-en", "/v1/betaBuildLocalizations/loc-zh"])
        for patch in patches:
            self.assertEqual(patch["body"]["data"]["attributes"],
                             {"whatsNew": "Changes since build 51.1:\n- Level track (#375)"})
            self.assertEqual(patch["headers"].get("Content-Type"), "application/json")
        self.assertIn("The build is not in App Store Connect yet.", result.stdout)
        self.assertIn("App Store Connect is processing the build.", result.stdout)
        self.assertIn("VALID", result.stdout)
        self.assertIn("Missing Compliance", result.stdout)
        self.assertIn("| Build | 0.5.0 (52.1) |", result.summary)
        self.assertIn("**VALID**", result.summary)
        self.assertIn("`MISSING_EXPORT_COMPLIANCE`", result.summary)
        self.assertIn("filled in (en-US, zh-Hant)", result.summary)
        self.assertIn("- Level track (#375)", result.summary)

    def test_creates_the_primary_localization_when_there_is_none(self):
        result = self.run_processing(self.store(["VALID"], primary="zh-Hant"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        posts = self.requests_to(result, "POST", "/v1/betaBuildLocalizations")
        self.assertEqual(len(posts), 1)
        self.assertEqual(posts[0]["body"], {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "zh-Hant", "whatsNew": "Changes since build 51.1:\n- Level track (#375)"},
            "relationships": {"build": {"data": {"type": "builds", "id": BUILD_ID}}}}})
        self.assertEqual(self.requests_to(result, "GET", f"/v1/apps/{APP_ID}")[0]["query"],
                         {"fields[apps]": "primaryLocale"})
        self.assertIn("filled in (zh-Hant)", result.summary)

    def test_invalid_build_fails(self):
        result = self.run_processing(self.store(["PROCESSING", "INVALID"]))
        self.assertEqual(result.returncode, 1)
        self.assertIn("::error", result.stdout)
        self.assertIn("INVALID", result.stdout)
        self.assertIn("**INVALID**", result.summary)
        self.assertFalse([r for r in result.requests if r["method"] in ("PATCH", "POST")])

    def test_failed_build_fails(self):
        result = self.run_processing(self.store(["FAILED"]))
        self.assertEqual(result.returncode, 1)
        self.assertIn("**FAILED**", result.summary)

    def test_still_processing_at_the_timeout_only_warns(self):
        result = self.run_processing(self.store(["PROCESSING"]), PROCESSING_TIMEOUT="1", POLL_INTERVAL="0.1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(result.seconds, 15)
        self.assertIn("::warning", result.stdout)
        self.assertIn("still being processed", result.stdout)
        self.assertIn("still being processed", result.summary)
        self.assertFalse([r for r in result.requests if r["method"] in ("PATCH", "POST")])

    def test_never_found_at_the_timeout_only_warns(self):
        result = self.run_processing(self.store([None]), PROCESSING_TIMEOUT="1", POLL_INTERVAL="0.1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("not in App Store Connect yet after", result.stdout)

    def test_refused_key_fails_at_once(self):
        result = self.run_processing(self.store([401]))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(result.requests), 1)
        self.assertIn("HTTP 401 (Fake error: status 401)", result.stdout)
        self.assertIn("not checked: App Store Connect answered GET /v1/builds with HTTP 401", result.summary)

    def test_server_errors_and_rate_limits_are_asked_again(self):
        result = self.run_processing(self.store([503, 503, 429, "VALID"]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.requests_to(result, "GET", "/v1/builds")), 4)
        # One warning per new problem, not one per request.
        self.assertEqual(result.stdout.count("::warning"), 2)

    def test_refused_whats_new_only_warns(self):
        localizations = [{"type": "betaBuildLocalizations", "id": "loc-en", "attributes": {"locale": "en-US"}}]
        result = self.run_processing(self.store(["VALID"], localizations=localizations, patch_status=409))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Could not fill in What to Test", result.stdout)
        self.assertIn("not filled in: App Store Connect refused it", result.summary)

    def test_no_whats_new_file(self):
        result = self.run_processing(self.store(["VALID"]), whats_new=None)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse([r for r in result.requests if "betaBuildLocalizations" in r["path"]])
        self.assertIn("not filled in: no text", result.summary)

    def test_long_whats_new_is_cut_to_the_limit(self):
        result = self.run_processing(self.store(["VALID"]), whats_new="x" * 5000)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text = self.requests_to(result, "POST", "/v1/betaBuildLocalizations")[0]["body"]["data"]["attributes"]["whatsNew"]
        self.assertEqual(len(text), 4000)
        self.assertTrue(text.endswith("…"))

    def test_missing_settings_are_all_named_and_nothing_is_asked(self):
        result = self.run_processing(self.store(["VALID"]), ASC_APP_ID=None, ASC_KEY_ID=None,
                                     ASC_PRIVATE_KEY=None, BUILD_NUMBER=None)
        self.assertEqual(result.returncode, 1)
        for name in ("ASC_APP_ID", "ASC_KEY_ID", "ASC_PRIVATE_KEY", "BUILD_NUMBER"):
            self.assertIn(f"{name} is not set", result.stdout)
        self.assertEqual(result.requests, [])

    def test_bad_key_fails_without_printing_it(self):
        result = self.run_processing(self.store(["VALID"]),
                                     ASC_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nnot a key\n-----END PRIVATE KEY-----")
        self.assertEqual(result.returncode, 1)
        self.assertIn("openssl could not sign", result.stdout)
        self.assertNotIn("not a key", result.stdout + result.stderr)
        self.assertEqual(result.requests, [])

    def test_der_to_raw(self):
        # r with its high bit set (DER adds a zero byte), s one byte short.
        r, s = b"\x80" + b"\x11" * 31, b"\x22" * 31
        sequence = b"\x02\x21\x00" + r + b"\x02\x1f" + s
        self.assertEqual(MODULE.der_to_raw(b"\x30" + bytes([len(sequence)]) + sequence), r + b"\0" + s)
        for bad in (b"", b"\x31\x00", b"\x30\x06\x02\x01\x01\x03\x01\x01", b"\x30\x24\x02\x22" + b"\x01" * 34):
            with self.assertRaises((ValueError, IndexError)):
                MODULE.der_to_raw(bad)


class ChangesTests(Fixture):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.repo = Path(cls.folder.name) / "repo"
        cls.git_env = clean_env(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                                GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                                GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        git = cls.git
        git("init", "-q", "-b", "main", str(cls.repo), cwd=cls.folder.name)
        cls.commit("base")
        cls.released = git("rev-parse", "HEAD").strip()
        # PR 10: merged with an empty body, as recent merges on main are.
        cls.branch_and_merge("one", "Merge pull request #10 from owner/claude/one")
        # PR 11: merged with the title in the body; GitHub no longer has it.
        cls.branch_and_merge("two", "Merge pull request #11 from owner/claude/two\n\nTitle from the merge body")
        # A side branch that merged main and then itself was merged as PR 13.
        git("checkout", "-q", "-b", "three")
        cls.commit("three")
        git("checkout", "-q", "main")
        cls.commit("squashed: Squashed change (#12)")
        git("checkout", "-q", "three")
        git("merge", "-q", "--no-ff", "-m", "Merge branch 'main' into three", "main")
        git("checkout", "-q", "main")
        git("merge", "-q", "--no-ff", "-m", "Merge pull request #13 from owner/claude/three", "three")
        cls.head = git("rev-parse", "HEAD").strip()

    @classmethod
    def git(cls, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or cls.repo, env=cls.git_env, check=True,
                              capture_output=True, text=True).stdout

    @classmethod
    def commit(cls, message):
        name = message.split(":")[0]
        (cls.repo / f"{name}.txt").write_text(message)
        cls.git("add", ".")
        cls.git("commit", "-q", "-m", message.split(": ", 1)[-1])

    @classmethod
    def branch_and_merge(cls, name, message):
        cls.git("checkout", "-q", "-b", name)
        cls.commit(name)
        cls.git("checkout", "-q", "main")
        cls.git("merge", "-q", "--no-ff", "-m", message, name)

    def github(self, runs, titles, runs_status=200):
        def answer(method, path, query, body):
            if path == f"/repos/{REPOSITORY}/actions/workflows/testflight.yml/runs":
                if runs_status != 200:
                    return runs_status, {"message": "fake failure"}
                return 200, {"total_count": len(runs), "workflow_runs": runs}
            prefix = f"/repos/{REPOSITORY}/pulls/"
            if path.startswith(prefix) and path[len(prefix):] in titles:
                return 200, {"number": int(path[len(prefix):]), "title": titles[path[len(prefix):]]}
            return 404, {"message": "Not Found"}
        return answer

    def run_changes(self, answer, **env):
        server = FakeServer(answer)
        self.addCleanup(server.close)
        settings = {"GITHUB_TOKEN": GITHUB_TOKEN, "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_RUN_ID": "900",
                    "GITHUB_API_URL": server.url}
        settings.update(env)
        result = subprocess.run([sys.executable, "-I", str(CHANGES), "--repo", str(self.repo)],
                                env=clean_env(**{k: v for k, v in settings.items() if v is not None}),
                                capture_output=True, text=True, timeout=60)
        for request in server.requests:
            self.assertEqual(request["headers"].get("Authorization"), f"Bearer {GITHUB_TOKEN}")
        self.assert_no_secret(result.stdout, result.stderr)
        result.requests = server.requests
        return result

    def runs(self, sha=None, number=51, attempt=1):
        # The newest first, as GitHub lists them; this run itself comes first.
        return [{"id": 900, "head_sha": self.head, "run_number": 53, "run_attempt": 1},
                {"id": 800, "head_sha": sha or self.released, "run_number": number, "run_attempt": attempt}]

    def test_lists_the_merges_since_the_last_release_newest_first(self):
        result = self.run_changes(self.github(self.runs(), {"10": "First change, as titled now", "13": "Third change"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "Changes since build 51.1:\n"
                                        "- Third change (#13)\n"
                                        "- Squashed change (#12)\n"
                                        "- Title from the merge body (#11)\n"
                                        "- First change, as titled now (#10)\n")
        query = dict(urllib.parse.parse_qsl(result.requests[0]["raw_query"]))
        self.assertEqual(query, {"branch": "main", "status": "success", "per_page": "50"})

    def test_names_the_previous_build_with_the_offset(self):
        result = self.run_changes(self.github(self.runs(number=51, attempt=2), {}), BUILD_NUMBER_OFFSET="100")
        self.assertTrue(result.stdout.startswith("Changes since build 151.2:\n"), result.stdout)
        # Without a title from GitHub: the merge body, else the branch name.
        self.assertIn("- owner/claude/one (#10)\n", result.stdout)

    def test_same_commit_as_the_last_release(self):
        result = self.run_changes(self.github(self.runs(sha=self.head), {}))
        self.assertEqual(result.stdout, "No changes since build 51.1: the same commit.\n")

    def test_github_down_falls_back_to_recent_history(self):
        result = self.run_changes(self.github([], {}, runs_status=500))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("Recent changes:\n- owner/claude/three (#13)\n"), result.stdout)
        self.assertIn("- base\n", result.stdout)
        self.assertIn("::warning", result.stderr)

    def test_unknown_release_commit_falls_back_to_recent_history(self):
        result = self.run_changes(self.github(self.runs(sha="0" * 40), {}))
        self.assertTrue(result.stdout.startswith("Recent changes:\n"), result.stdout)
        self.assertIn("is not in main's history here", result.stderr)

    def test_first_release_has_no_previous_run(self):
        result = self.run_changes(self.github(self.runs()[:1], {}))
        self.assertTrue(result.stdout.startswith("Recent changes:\n"), result.stdout)

    def test_long_lists_stop_within_the_limit(self):
        module = load(CHANGES, "changes")
        lines = [(f"sha{n}", f"Merge pull request #{n} from owner/b{n}", "T" * 300) for n in range(400)]
        module.first_parent_commits = lambda repo, base: lines
        module.previous_release = lambda repository, run_id: ("abc", 51, 1)
        module.git = lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, "", "")
        module.github = lambda path: None
        text = module.whats_new(".", REPOSITORY, "900", 0)
        self.assertLessEqual(len(text), 4000)
        self.assertRegex(text.splitlines()[-1], r"^- …and \d+ more$")
        shown = len(text.splitlines()) - 2
        self.assertEqual(int(text.splitlines()[-1].split()[2]) + shown, 400)

    def test_missing_settings(self):
        result = self.run_changes(self.github(self.runs(), {}), GITHUB_TOKEN=None, GITHUB_RUN_ID=None)
        self.assertEqual(result.returncode, 1)
        self.assertIn("GITHUB_TOKEN is not set", result.stderr)
        self.assertIn("GITHUB_RUN_ID is not set", result.stderr)
        self.assertEqual(result.stdout, "")


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


if __name__ == "__main__":
    unittest.main(verbosity=2)
