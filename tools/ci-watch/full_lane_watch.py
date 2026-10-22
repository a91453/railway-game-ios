#!/usr/bin/env python3
"""Tells the work registry (#231) when main's full lane turns red, fails in
other jobs than last time, or turns green again (decision 329).

The full lane is ios-build.yml run on main by ios-full-lane.yml or by hand
(workflow_dispatch) or by its schedule, without `only_testing` (those runs
are named "UI tests by hand: ..."). On 2026-10-20 and 10-21 it was red ten
times in a row and nobody was told: its result shows only on the Actions
page. full-lane-watch.yml runs this when an iOS App Build run of main
completes.

A comment is posted only when the news changes, so a red streak with the
same failing jobs is one comment, not one a run:
- red after a green run (or after none): "turned red";
- red after a red run, with a job that has not failed earlier in this red
  streak (the runs back to the last green one, at most STREAK): "still red,
  and a job turned red";
- green after a red run: "green again".
A cancelled run says nothing (a newer full lane or a release check replaced
it). A run re-run (its attempt 2 or later) is compared with its own attempt
before, which is what the last comment said about it: a red full lane re-run
green says "green again". A run with a newer full lane already finished says
nothing: it is no longer main's latest (PR #945–#961 review). The comment never holds an at sign: the account's comments by a person
start claude.yml when they mention it, and job names come from the workflow.

Python 3 standard library only:
    python3 -I tools/ci-watch/full_lane_watch.py --run <id>             # post when there is news
    python3 -I tools/ci-watch/full_lane_watch.py --run <id> --dry-run   # print, post nothing
    python3 -I tools/ci-watch/full_lane_watch.py --selftest
Environment: GITHUB_REPOSITORY (owner/name), GH_TOKEN (not needed for
--dry-run on a public repository), ISSUE (default 231).
"""
import argparse
import json
import os
import sys
import urllib.request

API = "https://api.github.com"
HAND = "UI tests by hand"
FULL_LANE_EVENTS = ("workflow_dispatch", "schedule")
STREAK = 10


def api(path, token=None, body=None):
    request = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None)
    request.add_header("Accept", "application/vnd.github+json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def is_full_lane(run):
    return (
        run.get("head_branch") == "main"
        and run.get("event") in FULL_LANE_EVENTS
        and not (run.get("display_title") or "").startswith(HAND)
    )


def failed_jobs(jobs):
    return sorted(job["name"] for job in jobs if job.get("conclusion") in ("failure", "timed_out"))


def news(run, failed, previous, streak_failed):
    """The comment's headline for `run` after `previous` (None when there is
    no earlier full lane), or None when there is nothing new to say.
    `streak_failed` is every job that failed in the red runs before `run`
    back to the last green one."""
    conclusion = run.get("conclusion")
    before = previous.get("conclusion") if previous else None
    if conclusion == "success":
        return "main 的 full lane 綠了" if before == "failure" else None
    if conclusion != "failure":
        return None
    if before != "failure":
        return "main 的 full lane 紅了"
    if set(failed) - set(streak_failed):
        return "main 的 full lane 還是紅的，又有 job 紅了"
    return None


def clean(text):
    # No mention of anyone, whatever a job name holds.
    return text.replace("@", "＠")


def comment(run, failed, previous, streak_failed, headline):
    lines = [f"**{headline}**（自動留言，`full-lane-watch.yml`，決策 329）", ""]
    lines.append(f"- run：{run['html_url']}（`{run['head_sha'][:7]}`，{run.get('event')}，{run.get('created_at')}）")
    if failed:
        lines.append("- 紅的 job：" + "、".join(f"`{name}`" for name in failed))
    if previous:
        state = "紅" if previous.get("conclusion") == "failure" else "綠"
        lines.append(f"- 上一次 full lane：{previous['html_url']}（`{previous['head_sha'][:7]}`，{state}）")
        new = sorted(set(failed) - set(streak_failed))
        if streak_failed and new and run.get("conclusion") == "failure":
            lines.append("- 這一段紅燈裡之前沒紅過的：" + "、".join(f"`{name}`" for name in new))
    if run.get("conclusion") == "failure":
        lines += ["", "照 `docs/HANDOFF.md` §1.2「full lane 紅了」查：失敗的測試與行號、和上一次綠的比、交給可疑 PR 的 session。修好以前不發版。"]
    else:
        lines += ["", "要發版的 commit 仍要有自己的一輪綠 full lane（HANDOFF §1.2）。"]
    return clean("\n".join(lines))


def earlier_full_lanes(runs, run):
    """The full lanes of main that finished green or red before `run`, newest first."""
    earlier = [r for r in runs if is_full_lane(r) and r["id"] != run["id"] and r.get("status") == "completed"
               and r.get("conclusion") in ("success", "failure") and r["created_at"] < run["created_at"]]
    return sorted(earlier, key=lambda r: r["created_at"], reverse=True)


def newer_full_lanes(runs, run):
    """The full lanes of main created after `run` that finished green or red."""
    return [r for r in runs if is_full_lane(r) and r["id"] != run["id"] and r.get("status") == "completed"
            and r.get("conclusion") in ("success", "failure") and r["created_at"] > run["created_at"]]


def compared_with(attempt_before, earlier):
    """What `run` is compared with: its own attempt before when it was
    re-run and that attempt finished green or red, else the full lane
    before it."""
    if attempt_before and attempt_before.get("conclusion") in ("success", "failure"):
        return attempt_before
    return earlier[0] if earlier else None


def red_streak(earlier):
    """The red runs at the head of `earlier`, up to the first green one."""
    streak = []
    for r in earlier[:STREAK]:
        if r.get("conclusion") != "failure":
            break
        streak.append(r)
    return streak


def main(argv=None):
    parser = argparse.ArgumentParser(description="main 的 full lane 紅了、換了紅的 job、綠回來時在 #231 留言。")
    parser.add_argument("--run", type=int, help="ios-build.yml 的 run id")
    parser.add_argument("--dry-run", action="store_true", help="只印出留言，不送出")
    parser.add_argument("--selftest", action="store_true")
    options = parser.parse_args(argv)
    if options.selftest:
        return selftest()
    if not options.run:
        parser.error("--run is required")
    repository = os.environ.get("GITHUB_REPOSITORY", "a91453/railway-game-ios")
    token = os.environ.get("GH_TOKEN")
    issue = int(os.environ.get("ISSUE", "231"))

    run = api(f"/repos/{repository}/actions/runs/{options.run}", token)
    if not is_full_lane(run):
        print(f"Run {options.run} is not a full lane of main ({run.get('event')}, {run.get('head_branch')}, {run.get('display_title')!r}); nothing to say.")
        return 0
    runs = api(f"/repos/{repository}/actions/workflows/ios-build.yml/runs?branch=main&status=completed&per_page=50", token)["workflow_runs"]
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    newer = newer_full_lanes(runs, run)
    if newer:
        text = f"Run {run['id']} ({run.get('conclusion')}): a newer full lane ({newer[0]['id']}) has finished, so this is not main's latest; no comment."
        print(text)
        if summary:
            with open(summary, "a", encoding="utf-8") as out:
                out.write(text + "\n")
        return 0
    earlier = earlier_full_lanes(runs, run)
    attempt = run.get("run_attempt") or 1
    attempt_before = api(f"/repos/{repository}/actions/runs/{run['id']}/attempts/{attempt - 1}", token) if attempt > 1 else None
    previous = compared_with(attempt_before, earlier)
    jobs = lambda r: failed_jobs(api(f"/repos/{repository}/actions/runs/{r['id']}/jobs?per_page=100&filter=latest", token)["jobs"])
    failed = jobs(run)
    streak_failed = []
    if run.get("conclusion") == "failure":
        streak_failed = {name for r in red_streak(earlier) for name in jobs(r)}
        if previous is attempt_before and attempt_before.get("conclusion") == "failure":
            # The jobs of the attempt before, not of the run's latest attempt.
            before = api(f"/repos/{repository}/actions/runs/{run['id']}/attempts/{attempt - 1}/jobs?per_page=100", token)["jobs"]
            streak_failed |= set(failed_jobs(before))
        streak_failed = sorted(streak_failed)
    headline = news(run, failed, previous, streak_failed)
    if headline is None:
        text = f"Run {run['id']} ({run.get('conclusion')}): nothing new since the last full lane ({previous['id'] if previous else 'none'}); no comment."
        print(text)
        if summary:
            with open(summary, "a", encoding="utf-8") as out:
                out.write(text + "\n")
        return 0
    body = comment(run, failed, previous, streak_failed, headline) + "\n"
    print(body)
    if summary:
        with open(summary, "a", encoding="utf-8") as out:
            out.write(body)
    if options.dry_run:
        print(f"(dry run: not posted to #{issue})")
        return 0
    posted = api(f"/repos/{repository}/issues/{issue}/comments", token, {"body": body})
    print(f"Posted: {posted.get('html_url')}")
    return 0


def selftest():
    def run(id, conclusion, created, event="workflow_dispatch", title="iOS App Build", branch="main"):
        return {"id": id, "conclusion": conclusion, "status": "completed", "created_at": created, "event": event,
                "display_title": title, "head_branch": branch, "head_sha": f"{id:040x}", "html_url": f"https://example.invalid/{id}"}

    green, red = run(1, "success", "2026-10-20T10:00:00Z"), run(2, "failure", "2026-10-20T14:00:00Z")
    a, b = ["Xcode UI tests, second (iOS Simulator)"], ["Xcode UI tests, lessons (iOS Simulator)"]
    assert news(red, a, green, []) == "main 的 full lane 紅了"
    assert news(red, a, None, []) == "main 的 full lane 紅了"
    assert news(red, a, run(0, "failure", "x"), a) is None, "the same red again is no news"
    assert news(red, a, run(0, "failure", "x"), a + b) is None, "fewer red jobs is no news"
    assert news(red, a + b, run(0, "failure", "x"), a) == "main 的 full lane 還是紅的，又有 job 紅了"
    assert news(green, [], run(0, "failure", "x"), a) == "main 的 full lane 綠了"
    assert news(green, [], run(0, "success", "x"), []) is None
    assert news(run(3, "cancelled", "x"), [], red, a) is None

    hand = run(4, "failure", "2026-10-20T15:00:00Z", title="UI tests by hand: RailwayGameUITests/MapInteractionTests")
    pr = run(5, "failure", "2026-10-20T15:00:00Z", event="pull_request")
    other = run(6, "failure", "2026-10-20T15:00:00Z", branch="claude/bisect-x")
    nightly = run(7, "success", "2026-10-20T16:00:00Z", event="schedule")
    assert [is_full_lane(r) for r in (green, hand, pr, other, nightly)] == [True, False, False, False, True]
    newest = run(8, "failure", "2026-10-20T17:00:00Z")
    earlier = earlier_full_lanes([green, red, hand, pr, other, nightly, newest, run(9, "cancelled", "2026-10-20T16:30:00Z")], newest)
    assert [r["id"] for r in earlier] == [7, 2, 1], earlier
    assert red_streak(earlier) == []
    assert [r["id"] for r in red_streak(earlier[1:])] == [2]

    # A red full lane re-run green is "green again": it is compared with its
    # own red attempt, not the green run before it.
    rerun = dict(red, conclusion="success", run_attempt=2)
    assert news(rerun, [], compared_with(dict(red), [green]), a) == "main 的 full lane 綠了"
    assert compared_with(None, [green]) is green and compared_with(None, []) is None
    assert compared_with(run(2, "cancelled", "x"), [green]) is green
    # A re-run of an older full lane says nothing once a newer one finished.
    assert [r["id"] for r in newer_full_lanes([green, red, hand, nightly, newest], red)] == [7, 8]
    assert newer_full_lanes([green, red, run(10, "cancelled", "2026-10-20T18:00:00Z")], red) == []

    assert failed_jobs([{"name": "b", "conclusion": "failure"}, {"name": "a", "conclusion": "timed_out"},
                        {"name": "c", "conclusion": "success"}, {"name": "d", "conclusion": "skipped"}]) == ["a", "b"]
    text = comment(red, ["job @claude"], green, [], "main 的 full lane 紅了")
    assert "@" not in text and "HANDOFF.md` §1.2" in text and "https://example.invalid/1" in text, text
    print("selftest：all cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
