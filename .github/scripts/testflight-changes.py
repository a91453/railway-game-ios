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
RECENT = 20
# The planning session's short text for the next release: what was decided,
# what stays as it was, what to look at. Under .github because the
# processing job checks out only .github; read from git, not the disk.
CURATED = ".github/testflight-whats-new.md"
MERGE = re.compile(r"^Merge pull request #(\d+) from (\S+)")
SQUASH = re.compile(r"^(.*\S)\s+\(#(\d+)\)$")


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


def upload_attempt(repository, run_id):
    """The attempt whose upload job succeeded, which is the build's number after the dot.

    The run's own run_attempt is its latest attempt: after only the processing
    job is run again it reads 2, while the build that was uploaded is still .1.
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
        since = f"build {offset + run_number}.{attempt}"
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
    args = parser.parse_args(argv)
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
