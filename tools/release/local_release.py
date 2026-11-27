#!/usr/bin/env python3
"""The last release, for testflight-local.sh: CI's or the Mac's, whichever is newer.

testflight-map-packs.py and testflight-changes.py compare with the commit of
the last successful testflight.yml run. A release made on the Mac is not a
run, so this wrapper runs the same two scripts with their previous_release()
answering the newer of that run and the Mac's last release, recorded in a
JSON file ({"build": "152.1", "commit": "<sha>"}) by `record`:

  local_release.py packs      --record FILE   the map packs to upload
  local_release.py whats-new  --record FILE   the What to Test text
  local_release.py next-build --record FILE --ci-build N
  local_release.py record     --record FILE --build B --commit SHA
  local_release.py external   --record FILE --build B --version V
      add the processed build to every External Testing group and submit it
      to Beta App Review (ASC_APP_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)

The CI scripts read GITHUB_TOKEN, GITHUB_REPOSITORY and GITHUB_RUN_ID as in
CI. Only Python's standard library and git are used.
"""

import argparse
import importlib.util
import json
import pathlib
import subprocess
import sys

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / ".github" / "scripts"


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_record(path):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError):
        return None


def descends(older, newer):
    """True when `newer` has `older` in its history (or they are the same)."""
    done = subprocess.run(["git", "merge-base", "--is-ancestor", older, newer],
                          capture_output=True, check=False)
    return done.returncode == 0


def local_is_newer(record, ci_sha):
    if not record or not record.get("commit"):
        return False
    if not ci_sha:
        return True
    return descends(ci_sha, record["commit"]) and record["commit"] != ci_sha


def external(build, version):
    """Every External Testing group gets the build, then Beta App Review."""
    import os
    processing = load("testflight-processing")
    client = processing.Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"],
                               os.environ["ASC_KEY_PATH"], "https://api.appstoreconnect.apple.com")
    app_id = os.environ["ASC_APP_ID"]
    found = processing.find_build(client, app_id, build, version)
    if not found:
        print(f"Build {version} ({build}) is not in App Store Connect.", file=sys.stderr)
        return 1
    build_id = found["id"]
    groups = client.request("GET", f"/v1/apps/{app_id}/betaGroups", {"limit": "200"}).get("data") or []
    external_groups = [g for g in groups if not (g.get("attributes") or {}).get("isInternalGroup")]
    if not external_groups:
        print("The app has no External Testing group.", file=sys.stderr)
        return 1
    client.request("POST", f"/v1/builds/{build_id}/relationships/betaGroups",
                   body={"data": [{"type": "betaGroups", "id": g["id"]} for g in external_groups]})
    names = ", ".join((g.get("attributes") or {}).get("name", "?") for g in external_groups)
    print(f"Added {version} ({build}) to the external groups: {names}.")
    try:
        client.request("POST", "/v1/betaAppReviewSubmissions", body={"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        print("Submitted to Beta App Review.")
    except Exception as error:  # already submitted, or test information missing
        print(f"Beta App Review submission refused: {error}", file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["packs", "whats-new", "next-build", "record", "external"])
    parser.add_argument("--record", required=True)
    parser.add_argument("--build")
    parser.add_argument("--commit")
    parser.add_argument("--ci-build")
    parser.add_argument("--version")
    args = parser.parse_args(argv)
    record = read_record(args.record)

    if args.action == "record":
        pathlib.Path(args.record).write_text(json.dumps({"build": args.build, "commit": args.commit}) + "\n")
        return 0

    if args.action == "external":
        return external(args.build, args.version)

    if args.action == "next-build":
        # CI makes N and N.2..N.99, never N.1: the Mac takes N.1, then N.1.1,
        # N.1.2... until the next CI release. A Mac release given a whole
        # number of its own (--build 153) counts as that CI number.
        ci = args.ci_build
        last = (record or {}).get("build", "")
        head = last.split(".")[0]
        if head.isdigit() and int(head) > int(ci):
            ci = head
        if last == ci:
            print(f"{ci}.1")
        elif last == f"{ci}.1":
            print(f"{ci}.1.1")
        elif last.startswith(f"{ci}.1."):
            print(f"{ci}.1.{int(last.rsplit('.', 1)[1]) + 1}")
        else:
            print(f"{ci}.1")
        return 0

    if args.action == "packs":
        module = load("testflight-map-packs")
        original = module.previous_release

        def previous_release():
            ci_sha = original()
            if local_is_newer(record, ci_sha):
                module.say(f"The Mac's release {record['build']} is newer than CI's; comparing with it.")
                return record["commit"]
            return ci_sha

        module.previous_release = previous_release
        return module.main([])

    module = load("testflight-changes")
    original = module.previous_release
    chosen = {}

    def previous_release(repository, run_id):
        ci = original(repository, run_id)
        if local_is_newer(record, ci[0] if ci else None):
            chosen["local"] = record["build"]
            return (record["commit"], 0, 1)
        return ci

    label = module.build_label
    module.previous_release = previous_release
    module.build_label = lambda offset, run, attempt: chosen.get("local") or label(offset, run, attempt)
    return module.main([])


if __name__ == "__main__":
    sys.exit(main())
