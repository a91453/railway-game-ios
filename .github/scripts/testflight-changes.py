#!/usr/bin/env python3
"""Write a TestFlight build's "What to Test": what was merged since the last release.

When the planning session wrote a short text for this release
(CURATED, changed on main since the last release's commit), that text is
the What to Test, as written. Otherwise it lists the pull requests merged
into main since the commit of the last TestFlight run that succeeded,
newest first, with their titles as GitHub has them now. Used by the processing job of .github/workflows/testflight.yml;
testflight-processing.py puts the text into App Store Connect. Only Python's
standard library and git are used. Tested by testflight-selftest-processing.py.

  testflight-changes.py [--repo PATH] > whats-new.txt
  testflight-changes.py --check-text .github/testflight-whats-new.md

The checkout needs main's history (actions/checkout with fetch-depth: 0).
Inputs (environment):
  GITHUB_TOKEN         a token with actions: read and pull-requests: read
  GITHUB_REPOSITORY    owner/name
  GITHUB_RUN_ID        this run, which is not the previous release
  GITHUB_API_URL       set by GitHub Actions; default https://api.github.com
  BUILD_NUMBER_OFFSET  variable, optional: to name the previous build number

When GitHub does not answer it still writes what git alone knows, and says
so on stderr. Exit status 1 only when a setting is missing or git fails.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request


# testflight.yml's job that numbers, signs and uploads the build.
UPLOAD_JOB = "Archive, sign, export, check and upload"
WORKFLOW = "testflight.yml"
LIMIT = 4000
# The last TestFlight run whose first attempt still uploaded "<n>.1"; later
# runs upload the plain number on their first attempt (decision 616).
LAST_DOTTED_RUN = 119
RECENT = 20
# The planning session's short text for the next release: what was decided,
# what stays as it was, what to look at. Under .github because the
# processing job checks out only .github; read from git, not the disk.
CURATED = ".github/testflight-whats-new.md"
MERGE = re.compile(r"^Merge pull request #(\d+) from (\S+)")
SQUASH = re.compile(r"^(.*\S)\s+\(#(\d+)\)$")


# Characters App Store Connect refuses in "What to Test" (HTTP 409 "Text for
# whatsNew contains invalid characters"): run 42443826122 was refused for "✕"
# (U+2715, Dingbats). Apple publishes no list, so this is an ESTIMATE, kept
# narrower than what is known to work: Basic Multilingual Plane only, and none
# of the symbol blocks emoji and dingbats live in, no variation selector or
# joiner, no control character other than a new line, no private use.
REFUSED_RANGES = (
    (0x0000, 0x0008), (0x000B, 0x001F), (0x007F, 0x009F),  # controls (tab and new line stay)
    (0x200B, 0x200F), (0x2028, 0x202E), (0x2060, 0x206F),  # invisible marks, joiners
    (0x2300, 0x23FF),  # Miscellaneous Technical (⌚ ⏰)
    (0x25A0, 0x25FF),  # Geometric Shapes (▶ ◀)
    (0x2600, 0x27BF),  # Miscellaneous Symbols and Dingbats (☀ ✕ ✓ ❤)
    (0x2B00, 0x2BFF),  # Miscellaneous Symbols and Arrows (⭐)
    (0xD800, 0xF8FF),  # surrogates, private use
    (0xFE00, 0xFE0F),  # variation selectors (emoji style)
    (0xFFF0, 0xFFFF),  # specials
    (0x10000, 0x10FFFF),  # outside the BMP: emoji, rare ideographs
)


def invalid_characters(text):
    """[(line, column, character)] App Store Connect would probably refuse in `text` (estimate, see above)."""
    found = []
    for line_number, line in enumerate(text.split("\n"), 1):
        for column, character in enumerate(line, 1):
            code = ord(character)
            if any(low <= code <= high for low, high in REFUSED_RANGES):
                found.append((line_number, column, character))
    return found


def check_text(path):
    """Print one error per refused character in the file; 0 when it is clean."""
    with open(path, encoding="utf-8") as handle:
        found = invalid_characters(handle.read())
    for line, column, character in found:
        print(f"::error file={path},line={line},title=What to Test::"
              f"U+{ord(character):04X} {character!r} (line {line}, column {column}) is a character "
              "App Store Connect may refuse in What to Test; write it as words.", file=sys.stderr)
    return 1 if found else 0


def warn(message):
    print(f"::warning title=What to Test::{message}", file=sys.stderr, flush=True)


def github(path):
    """GET a GitHub REST path; None when GitHub does not answer or refuses."""
    base = (os.environ.get("GITHUB_API_URL") or "https://api.github.com").rstrip("/")
    request = urllib.request.Request(base + path)
    request.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except (urllib.error.URLError, OSError, ValueError) as error:
        warn(f"GitHub did not answer {path.split('?')[0]} ({getattr(error, 'code', None) or error}).")
        return None


def previous_release(repository, run_id):
    """(commit, run number, run attempt) of the last successful TestFlight run before this one."""
    answer = github(f"/repos/{repository}/actions/workflows/{WORKFLOW}/runs"
                    "?branch=main&status=success&per_page=50")
    if answer is None:
        return None
    for run in answer.get("workflow_runs") or []:
        if str(run.get("id")) != run_id and run.get("head_sha"):
            attempt = upload_attempt(repository, run["id"]) or int(run.get("run_attempt") or 1)
            return run["head_sha"], int(run.get("run_number") or 0), attempt
    return None


def build_label(offset, run_number, attempt):
    """The build number that run uploaded, as testflight-preflight.sh made it.

    Since decision 616 the first attempt is the plain number (120) and a re-run
    adds the attempt (120.2); runs up to LAST_DOTTED_RUN always added it (119.1)."""
    number = offset + run_number
    if attempt > 1 or run_number <= LAST_DOTTED_RUN:
        return f"{number}.{attempt}"
    return str(number)


def upload_attempt(repository, run_id):
    """The attempt whose upload job succeeded, which names the build (see build_label).

    The run's own run_attempt is its latest attempt: after only the processing
    job is run again it reads 2, while the build that was uploaded is still
    the first attempt's.
    None when GitHub does not list the jobs."""
    answer = github(f"/repos/{repository}/actions/runs/{run_id}/jobs?filter=all&per_page=100")
    attempts = [int(job.get("run_attempt") or 0) for job in (answer or {}).get("jobs") or []
                if job.get("name") == UPLOAD_JOB and job.get("conclusion") == "success"]
    return max(attempts, default=0) or None


def git(repo, *args, check=True):
    result = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=False)
    if check and result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result


def first_parent_commits(repo, base):
    """main's own commits after `base` (all of them), or the last RECENT when base is None."""
    span = [f"{base}..HEAD"] if base else [f"-{RECENT}", "HEAD"]
    log = git(repo, "log", "--first-parent", "--format=%H%x1f%s%x1f%b%x1e", *span).stdout
    commits = []
    for record in log.split("\x1e"):
        record = record.strip("\n")
        if record:
            sha, subject, body = (record.split("\x1f") + ["", ""])[:3]
            commits.append((sha, subject.strip(), body.strip()))
    return commits


def change_line(repository, subject, body, titles):
    """'Title (#n)' for a merged pull request, else the commit's subject."""
    number, title = None, subject
    merge = MERGE.match(subject)
    squash = SQUASH.match(subject)
    if merge:
        number = merge.group(1)
        # The merge commit's body holds the title the pull request had when it
        # was merged, if anything; else the branch name.
        title = next((line for line in body.splitlines() if line.strip()), merge.group(2))
    elif squash:
        title, number = squash.group(1), squash.group(2)
    if number is None:
        return title
    if number not in titles:
        pull = github(f"/repos/{repository}/pulls/{number}")
        titles[number] = (pull or {}).get("title")
    return f"{(titles[number] or title).strip()} (#{number})"


def curated(repo, base):
    """CURATED as it is at HEAD, when it changed since `base`; else None.

    With no known last release there is nothing to tell a fresh text from an
    old one, so the list is used."""
    if base is None:
        return None
    changed = git(repo, "diff", "--name-only", f"{base}..HEAD", "--", CURATED, check=False).stdout.strip()
    if not changed:
        return None
    shown = git(repo, "show", f"HEAD:{CURATED}", check=False)
    text = shown.stdout.strip() if shown.returncode == 0 else ""
    if not text:
        return None
    return text if len(text) <= LIMIT else text[:LIMIT - 1] + "…"


def whats_new(repo, repository, run_id, offset):
    previous = previous_release(repository, run_id)
    base = None
    if previous:
        sha, run_number, attempt = previous
        reachable = git(repo, "merge-base", "--is-ancestor", sha, "HEAD", check=False).returncode == 0
        if reachable:
            base = sha
        else:
            warn(f"The last release's commit {sha[:7]} is not in main's history here.")
    commits = first_parent_commits(repo, base)
    if base:
        since = f"build {build_label(offset, run_number, attempt)}"
        if not commits:
            return f"No changes since {since}: the same commit."
        text = curated(repo, base)
        if text:
            return text
        header = f"Changes since {since}:"
    else:
        header = "Recent changes:"
    titles = {}
    lines = [f"- {change_line(repository, subject, body, titles)}" for _, subject, body in commits]
    # App Store Connect takes at most LIMIT characters; keep room to say how
    # many lines did not fit.
    reserve = len("\n- …and 9999 more")
    text = header
    for index, line in enumerate(lines):
        room = LIMIT if index == len(lines) - 1 else LIMIT - reserve
        if len(text) + 1 + len(line) > room:
            return text + f"\n- …and {len(lines) - index} more"
        text += "\n" + line
    return text


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default=".", help="the checkout (default: the current folder)")
    parser.add_argument("--check-text", metavar="FILE",
                        help="only check FILE for characters App Store Connect refuses, then exit")
    args = parser.parse_args(argv)
    if args.check_text:
        return check_text(args.check_text)
    missing = [name for name in ("GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID") if not os.environ.get(name)]
    for name in missing:
        print(f"::error title=What to Test::{name} is not set.", file=sys.stderr)
    if missing:
        return 1
    offset_text = os.environ.get("BUILD_NUMBER_OFFSET") or "0"
    offset = int(offset_text) if offset_text.isdigit() else 0
    print(whats_new(args.repo, os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_RUN_ID"], offset))
    return 0


if __name__ == "__main__":
    sys.exit(main())
