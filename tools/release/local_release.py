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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["packs", "whats-new", "next-build", "record"])
    parser.add_argument("--record", required=True)
    parser.add_argument("--build")
    parser.add_argument("--commit")
    parser.add_argument("--ci-build")
    args = parser.parse_args(argv)
    record = read_record(args.record)

    if args.action == "record":
        pathlib.Path(args.record).write_text(json.dumps({"build": args.build, "commit": args.commit}) + "\n")
        return 0

    if args.action == "next-build":
        # CI makes N and N.2..N.99, never N.1: the Mac takes N.1, then N.1.1,
        # N.1.2... until the next CI release.
        ci = args.ci_build
        last = (record or {}).get("build", "")
        if last == f"{ci}.1":
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
