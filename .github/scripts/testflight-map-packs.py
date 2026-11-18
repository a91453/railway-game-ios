#!/usr/bin/env python3
"""Name the map packs (asset packs) a TestFlight release has to upload again.

Decision 858: App Store Connect makes a new version of an asset pack at every
upload, the same files or not, and each version is reviewed. So a release
uploads a city's map pack only when it differs from the one the last release
uploaded: its manifest (RailwayGameApp/AssetPacks/<city>.json) or any file of
the folders the manifest names (under RailwayGameApp/Resources), compared by
their git hashes at this commit and at the commit of the last TestFlight run
that succeeded. A run succeeds only when every pack it had to upload was
uploaded (testflight.yml stops at a failed upload), so what that commit holds
is what App Store Connect has.

Prints the assetPackID of each pack to upload, one a line, and why on stderr.
Every pack is named when it cannot tell: no earlier run, GitHub not answering,
the earlier commit not to be had, or the pack's files changed in the working
copy. Only Python's standard library and git are used.

  testflight-map-packs.py [--repo PATH] [--all]
  testflight-map-packs.py --selftest

Inputs (environment; not read with --all or --selftest):
  GITHUB_TOKEN       a token with actions: read
  GITHUB_REPOSITORY  owner/name
  GITHUB_RUN_ID      this run, which is not the previous release
  GITHUB_API_URL     set by GitHub Actions; default https://api.github.com
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

WORKFLOW = "testflight.yml"
MANIFESTS = "RailwayGameApp/AssetPacks"
RESOURCES = "RailwayGameApp/Resources"


def say(message):
    print(message, file=sys.stderr, flush=True)


def previous_release():
    """The commit of the last successful TestFlight run before this one, or None."""
    names = ("GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID")
    if any(not os.environ.get(name) for name in names):
        say("GITHUB_TOKEN, GITHUB_REPOSITORY or GITHUB_RUN_ID is not set.")
        return None
    base = (os.environ.get("GITHUB_API_URL") or "https://api.github.com").rstrip("/")
    path = (f"/repos/{os.environ['GITHUB_REPOSITORY']}/actions/workflows/{WORKFLOW}/runs"
            "?branch=main&status=success&per_page=50")
    request = urllib.request.Request(base + path)
    request.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            answer = json.loads(response.read())
    except (urllib.error.URLError, OSError, ValueError) as error:
        say(f"GitHub did not answer ({getattr(error, 'code', None) or error}).")
        return None
    for run in answer.get("workflow_runs") or []:
        if str(run.get("id")) != os.environ["GITHUB_RUN_ID"] and run.get("head_sha"):
            return run["head_sha"]
    return None


def git(repo, *args):
    """git's output, or None when it fails."""
    done = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False)
    return done.stdout.strip() if done.returncode == 0 else None


def has_commit(repo, commit):
    if git(repo, "cat-file", "-e", f"{commit}^{{commit}}") is not None:
        return True
    # A shallow checkout has only its own commit.
    return git(repo, "fetch", "--quiet", "--depth", "1", "origin", commit) is not None and \
        git(repo, "cat-file", "-e", f"{commit}^{{commit}}") is not None


def packs(repo):
    """[(assetPackID, [paths in the repository])] of the manifests, by name."""
    found = []
    for manifest in sorted((pathlib.Path(repo) / MANIFESTS).glob("*.json")):
        described = json.loads(manifest.read_text(encoding="utf-8"))
        paths = [f"{MANIFESTS}/{manifest.name}"]
        for selector in described.get("fileSelectors") or []:
            for kind in ("directory", "file"):
                if selector.get(kind):
                    paths.append(f"{RESOURCES}/{selector[kind]}")
        found.append((described["assetPackID"], paths))
    return found


def hashes(repo, commit, paths):
    """The git hash of each of `paths` at `commit`; None for one it has not."""
    return [git(repo, "rev-parse", "--verify", "--quiet", f"{commit}:{path}") for path in paths]


def to_upload(repo, previous):
    """[(assetPackID, why)] of the packs that differ from `previous`'s."""
    listed = packs(repo)
    if previous is None:
        return [(pack, "no earlier release to compare with") for pack, _ in listed]
    if not has_commit(repo, previous):
        return [(pack, f"the last release's commit {previous[:9]} cannot be read") for pack, _ in listed]
    chosen = []
    for pack, paths in listed:
        if git(repo, "status", "--porcelain", "--", *paths) != "":
            chosen.append((pack, "its files differ from this commit's in the working copy"))
            continue
        now, then = hashes(repo, "HEAD", paths), hashes(repo, previous, paths)
        if None in now or now != then:
            changed = [path for path, new, old in zip(paths, now, then) if new is None or new != old]
            chosen.append((pack, f"changed since {previous[:9]}: {', '.join(changed)}"))
        else:
            say(f"{pack}: the same as at the last release ({previous[:9]}); not uploaded again.")
    return chosen


def selftest():
    failures = []

    def expect(name, got, wanted):
        if got != wanted:
            failures.append(f"{name}: got {got!r}, wanted {wanted!r}")

    with tempfile.TemporaryDirectory() as folder:
        repo = pathlib.Path(folder)

        def run(*args):
            subprocess.run(["git", "-C", folder, *args], check=True, capture_output=True)

        def write(path, text):
            file = repo / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding="utf-8")

        def commit(message):
            run("add", "-A")
            run("-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", message)
            return git(folder, "rev-parse", "HEAD")

        run("init", "-q")
        for city in ("alpha", "beta"):
            write(f"{MANIFESTS}/{city}.json", json.dumps({
                "assetPackID": f"mappack-{city}", "fileSelectors": [{"directory": f"MapPacks/{city}"}],
            }))
            write(f"{RESOURCES}/MapPacks/{city}/pack.json", "{}")
            write(f"{RESOURCES}/MapPacks/{city}/data.bin", city)
        first = commit("first")
        ids = lambda found: [pack for pack, _ in found]  # noqa: E731
        expect("nothing changed", ids(to_upload(folder, first)), [])
        expect("no earlier release", ids(to_upload(folder, None)), ["mappack-alpha", "mappack-beta"])
        expect("unknown commit", ids(to_upload(folder, "0" * 40)), ["mappack-alpha", "mappack-beta"])
        write("README.md", "something else")
        commit("elsewhere")
        expect("a change elsewhere", ids(to_upload(folder, first)), [])
        write(f"{RESOURCES}/MapPacks/beta/data.bin", "beta, newer")
        expect("a change not committed", ids(to_upload(folder, first)), ["mappack-beta"])
        second = commit("beta's data")
        expect("one pack's file", ids(to_upload(folder, first)), ["mappack-beta"])
        expect("compared with itself", ids(to_upload(folder, second)), [])
        write(f"{MANIFESTS}/alpha.json", json.dumps({
            "assetPackID": "mappack-alpha", "fileSelectors": [{"directory": "MapPacks/alpha"}], "platforms": ["iOS"],
        }))
        commit("alpha's manifest")
        expect("one pack's manifest", ids(to_upload(folder, second)), ["mappack-alpha"])
        write(f"{MANIFESTS}/gamma.json", json.dumps({
            "assetPackID": "mappack-gamma", "fileSelectors": [{"directory": "MapPacks/gamma"}],
        }))
        write(f"{RESOURCES}/MapPacks/gamma/pack.json", "{}")
        third = commit("a new pack")
        expect("a new pack", ids(to_upload(folder, second)), ["mappack-alpha", "mappack-gamma"])
        expect("all three the same", ids(to_upload(folder, third)), [])
    for failure in failures:
        say(f"FAILED {failure}")
    say("testflight-map-packs.py selftest: " + ("failed" if failures else "passed"))
    return 1 if failures else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default=".", help="the checkout (default: the current folder)")
    parser.add_argument("--all", action="store_true", help="name every pack, whatever changed")
    parser.add_argument("--selftest", action="store_true", help="test this script on a throwaway repository")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.all:
        chosen = [(pack, "asked for") for pack, _ in packs(args.repo)]
    else:
        chosen = to_upload(args.repo, previous_release())
    for pack, why in chosen:
        say(f"{pack}: to upload ({why}).")
        print(pack)
    return 0


if __name__ == "__main__":
    sys.exit(main())
