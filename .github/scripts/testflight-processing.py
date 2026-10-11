#!/usr/bin/env python3
"""Wait for App Store Connect to process an uploaded TestFlight build.

Reports the result in the job summary and fills the build's "What to Test"
text. Used by the processing job of .github/workflows/testflight.yml, on
Linux, after the release job uploaded the build. Only Python's standard
library and the openssl command are used. Tested against a fake App Store
Connect by testflight-selftest-processing.py.

  testflight-processing.py [--whats-new FILE]

Inputs (environment):
  ASC_APP_ID           variable: the app's Apple ID in App Store Connect
  ASC_KEY_ID           secret: the App Store Connect team API key ID
  ASC_ISSUER_ID        secret: the issuer ID
  ASC_PRIVATE_KEY      secret: the whole text of AuthKey_<key id>.p8
  BUILD_NUMBER         the uploaded build's CFBundleVersion, such as 52.1
  APP_VERSION          its CFBundleShortVersionString, such as 0.5.0
  GITHUB_STEP_SUMMARY  set by GitHub Actions; the report is added to it
  PROCESSING_TIMEOUT   optional: seconds to wait in all; default 3600
  POLL_INTERVAL        optional: seconds between checks; default 30
  ASC_API_URL          tests only: the address of a fake App Store Connect

Exit status: 0 when the build is VALID, and also when it is still being
processed at the timeout (with a warning: Apple may only be slow); 1 when App
Store Connect marks it INVALID or FAILED, refuses the key, or a setting is
missing. A What to Test that cannot be filled is a warning, not a failure.
Never prints the key, the key ID, the issuer ID or a token.
"""

import argparse
import base64
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


API_URL = "https://api.appstoreconnect.apple.com"
# App Store Connect accepts tokens that live at most 20 minutes.
TOKEN_LIFETIME = 900
TOKEN_REUSE = 600
WHATS_NEW_LIMIT = 4000
FINAL_STATES = {"VALID", "INVALID", "FAILED"}
REQUIRED = ("ASC_APP_ID", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "BUILD_NUMBER", "APP_VERSION")
DESCRIPTIONS = {
    "NOT_FOUND": "The build is not in App Store Connect yet.",
    "PROCESSING": "App Store Connect is processing the build.",
    "VALID": "App Store Connect finished processing the build: VALID.",
    "INVALID": "App Store Connect processed the build as INVALID.",
    "FAILED": "App Store Connect could not process the build: FAILED.",
}


class Refused(Exception):
    """An answer that asking again will not change (a refused key, a bad request)."""


class Unreachable(Exception):
    """A lost connection or a server error: worth asking again."""


def annotate(kind, message):
    print(f"::{kind} title=TestFlight processing::{message}", flush=True)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw(der):
    """An ECDSA signature in DER (a SEQUENCE of r and s) as JWS wants it: r || s, 32 bytes each."""

    def length_at(pos):
        first = der[pos]
        if first < 0x80:
            return first, pos + 1
        count = first & 0x7F
        return int.from_bytes(der[pos + 1:pos + 1 + count], "big"), pos + 1 + count

    if not der or der[0] != 0x30:
        raise ValueError("the signature is not a DER sequence")
    _, pos = length_at(1)
    parts = []
    for _ in range(2):
        if der[pos] != 0x02:
            raise ValueError("the signature does not hold two DER integers")
        length, pos = length_at(pos + 1)
        value = der[pos:pos + length].lstrip(b"\0")
        if len(value) > 32:
            raise ValueError("a signature integer is longer than 32 bytes")
        parts.append(value.rjust(32, b"\0"))
        pos += length
    return b"".join(parts)


class Client:
    """App Store Connect API requests signed with the team API key (ES256 JWT)."""

    def __init__(self, key_id, issuer_id, key_path, base_url):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path
        self.base_url = base_url.rstrip("/")
        self._token = None
        self._token_time = 0.0

    def token(self):
        now = time.time()
        if self._token and now - self._token_time < TOKEN_REUSE:
            return self._token
        issued = int(now)
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer_id, "iat": issued, "exp": issued + TOKEN_LIFETIME, "aud": "appstoreconnect-v1"}
        signing_input = ".".join(
            b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload))
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(self.key_path)],
            input=signing_input.encode(), capture_output=True, check=False)
        if signed.returncode != 0:
            raise Refused("openssl could not sign with ASC_PRIVATE_KEY: "
                          + signed.stderr.decode(errors="replace").strip())
        self._token = signing_input + "." + b64url(der_to_raw(signed.stdout))
        self._token_time = now
        return self._token

    def request(self, method, path, query=None, body=None):
        url = self.base_url + path
        if query:
            url += "?" + urllib.parse.urlencode(query, safe="[]")
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", "Bearer " + self.token())
        request.add_header("Accept", "application/json")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                text = response.read()
        except urllib.error.HTTPError as error:
            message = f"App Store Connect answered {method} {path} with HTTP {error.code}{error_detail(error)}"
            if error.code == 429 or error.code >= 500:
                raise Unreachable(message) from None
            raise Refused(message) from None
        except (urllib.error.URLError, OSError, http.client.HTTPException) as error:
            raise Unreachable(f"no answer to {method} {path}: {getattr(error, 'reason', error)}") from None
        try:
            return json.loads(text) if text else {}
        except ValueError:
            raise Unreachable(f"the answer to {method} {path} is not JSON") from None


def error_detail(error):
    """App Store Connect's own explanation of an HTTP error, which names no secret."""
    try:
        errors = json.loads(error.read()).get("errors") or []
    except (ValueError, AttributeError, OSError):
        return ""
    texts = [": ".join(part for part in (item.get("title"), item.get("detail")) if part)
             for item in errors if isinstance(item, dict)]
    texts = [text for text in texts if text]
    return f" ({'; '.join(texts)})" if texts else ""


def asking_again(call, interval, attempts=3):
    """Call; on Unreachable wait and call again, up to `attempts` times in all."""
    for attempt in range(1, attempts + 1):
        try:
            return call()
        except Unreachable:
            if attempt == attempts:
                raise
            time.sleep(interval)


def find_build(client, app_id, build_number, version):
    query = {
        "filter[app]": app_id,
        "filter[version]": build_number,
        "filter[preReleaseVersion.version]": version,
        "limit": "1",
    }
    builds = client.request("GET", "/v1/builds", query).get("data") or []
    return builds[0] if builds else None


def duration(seconds):
    seconds = int(seconds)
    return f"{seconds // 60} min {seconds % 60:02d} s"


def wait_for_processing(client, app_id, build_number, version, timeout, interval):
    """Returns (build or None, state, seconds waited, whether the wait timed out)."""
    start = time.monotonic()
    build, state, problem = None, None, None
    while True:
        try:
            found = find_build(client, app_id, build_number, version)
        except Unreachable as error:
            if str(error) != problem:
                annotate("warning", f"{error}; asking again.")
            problem = str(error)
        else:
            problem = None
            build = found
            new_state = (found.get("attributes") or {}).get("processingState") if found else "NOT_FOUND"
            if new_state != state:
                state = new_state
                print(f"After {duration(time.monotonic() - start)}: "
                      f"{DESCRIPTIONS.get(state, f'processing state {state}.')}", flush=True)
            if state in FINAL_STATES:
                return build, state, time.monotonic() - start, False
        waited = time.monotonic() - start
        if waited >= timeout:
            return build, state or "NOT_FOUND", waited, True
        time.sleep(min(interval, max(timeout - waited, 0)))


def beta_states(client, build_id, interval):
    detail = asking_again(
        lambda: client.request("GET", f"/v1/builds/{build_id}/buildBetaDetail"), interval)
    attributes = (detail.get("data") or {}).get("attributes") or {}
    return attributes.get("internalBuildState"), attributes.get("externalBuildState")


def fill_whats_new(client, app_id, build_id, text, interval):
    """Sets What to Test in every localization the build has, or creates the app's primary one."""
    localizations = asking_again(
        lambda: client.request("GET", f"/v1/builds/{build_id}/betaBuildLocalizations"), interval
    ).get("data") or []
    if localizations:
        for localization in localizations:
            body = {"data": {"type": "betaBuildLocalizations", "id": localization["id"],
                             "attributes": {"whatsNew": text}}}
            asking_again(lambda: client.request(
                "PATCH", f"/v1/betaBuildLocalizations/{localization['id']}", body=body), interval)
        return [(item.get("attributes") or {}).get("locale", "?") for item in localizations]
    app = asking_again(
        lambda: client.request("GET", f"/v1/apps/{app_id}", {"fields[apps]": "primaryLocale"}), interval)
    locale = ((app.get("data") or {}).get("attributes") or {}).get("primaryLocale")
    if not locale:
        raise Refused("App Store Connect did not give the app's primary language")
    body = {"data": {
        "type": "betaBuildLocalizations",
        "attributes": {"locale": locale, "whatsNew": text},
        "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
    }}
    asking_again(lambda: client.request("POST", "/v1/betaBuildLocalizations", body=body), interval)
    return [locale]


def read_whats_new(path):
    if not path:
        return None
    try:
        text = Path(path).read_text(encoding="utf-8").strip()
    except OSError as error:
        annotate("warning", f"No What to Test text to fill in ({error.strerror}).")
        return None
    if not text:
        annotate("warning", "The What to Test text is empty; it is not filled in.")
        return None
    if len(text) > WHATS_NEW_LIMIT:
        text = text[:WHATS_NEW_LIMIT - 1].rstrip() + "…"
    return text


def write_summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as summary:
        summary.write("\n".join(lines) + "\n")


def setting(name, default, low, high):
    raw = os.environ.get(name) or str(default)
    try:
        value = float(raw)
    except ValueError:
        value = float("nan")
    if not low <= value <= high:
        raise SystemExit(f"{name} must be a number of seconds from {low} to {high}.")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--whats-new", help="a file holding the What to Test text")
    args = parser.parse_args(argv)

    missing = [name for name in REQUIRED if not os.environ.get(name)]
    for name in missing:
        annotate("error", f"{name} is not set.")
    if missing:
        return 1
    timeout = setting("PROCESSING_TIMEOUT", 3600, 1, 6 * 3600)
    interval = setting("POLL_INTERVAL", 30, 0, 600)
    app_id = os.environ["ASC_APP_ID"]
    build_number = os.environ["BUILD_NUMBER"]
    version = os.environ["APP_VERSION"]
    whats_new = read_whats_new(args.whats_new)

    summary = ["### App Store Connect processing", "", "| | |", "| --- | --- |",
               f"| Build | {version} ({build_number}) |"]
    with tempfile.TemporaryDirectory() as folder:
        key_path = Path(folder) / "key.p8"
        # Drop CR line endings and leading blank lines a paste may have added.
        key_text = os.environ["ASC_PRIVATE_KEY"].replace("\r", "").lstrip("\n") + "\n"
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as key_file:
            key_file.write(key_text)
        client = Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], key_path,
                        os.environ.get("ASC_API_URL") or API_URL)
        try:
            build, state, waited, timed_out = wait_for_processing(
                client, app_id, build_number, version, timeout, interval)
        except Refused as error:
            annotate("error", f"{error}. Check the API key and ASC_APP_ID "
                     "(docs/TESTFLIGHT_GITHUB_ACTIONS.md).")
            write_summary(summary + [f"| Processing | not checked: {error} |"])
            return 1

        if timed_out:
            where = "not in App Store Connect yet" if state == "NOT_FOUND" else "still being processed"
            annotate("warning", f"Build {version} ({build_number}) is {where} after {duration(waited)}. "
                     "Apple is sometimes slow; check App Store Connect, or re-run this job.")
            write_summary(summary + [f"| Processing | {where} after {duration(waited)} (`{state}`) |",
                                     "| What to Test | not filled in: the build is not processed yet |"])
            return 0
        if state != "VALID":
            annotate("error", f"App Store Connect marked build {version} ({build_number}) {state}. "
                     "Apple's email to the account holder says why; nothing reaches testers.")
            write_summary(summary + [f"| Processing | **{state}** after {duration(waited)} |"])
            return 1

        rows = [f"| Processing | **VALID** after {duration(waited)} |"]
        build_id = build["id"]
        try:
            internal, external = beta_states(client, build_id, interval)
        except (Refused, Unreachable) as error:
            annotate("warning", f"Could not read the TestFlight states: {error}.")
            internal = external = None
        rows.append(f"| Internal testing | `{internal or 'unknown'}` |")
        rows.append(f"| External testing | `{external or 'unknown'}` |")
        if "MISSING_EXPORT_COMPLIANCE" in (internal, external):
            annotate("notice", "TestFlight waits for the export compliance answer (Missing Compliance) "
                     "in App Store Connect before testers get the build.")

        details = []
        if whats_new is None:
            rows.append("| What to Test | not filled in: no text |")
        else:
            try:
                locales = fill_whats_new(client, app_id, build_id, whats_new, interval)
            except (Refused, Unreachable) as error:
                annotate("warning", f"Could not fill in What to Test: {error}.")
                rows.append("| What to Test | not filled in: App Store Connect refused it |")
            else:
                print(f"What to Test filled in for {', '.join(locales)}.", flush=True)
                rows.append(f"| What to Test | filled in ({', '.join(locales)}) |")
            details = ["", "<details><summary>What to Test</summary>", "", "```text",
                       whats_new.replace("```", "'''"), "```", "", "</details>"]
    write_summary(summary + rows + details)
    print(f"Build {version} ({build_number}) is VALID.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
