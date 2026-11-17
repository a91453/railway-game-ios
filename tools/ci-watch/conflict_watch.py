#!/usr/bin/env python3
"""Tells each open pull request into main that conflicts with main, on that
pull request, that it does (decision 830).

A pull request that conflicts with its base gets no CI run: GitHub cannot
make the merge commit the pull_request event checks out, so the checks of
its newest head never start, and nothing turns red. On 2026-11-17 #2367
waited like this while the planner said it was "running its tests", and
the owner asked how else they would find out but by looking themselves.
The sessions that open pull requests subscribe to them, so a comment on the
pull request wakes the session that owns it, which merges main and pushes,
with no planner's check-in and no owner's click in between.

conflict-watch.yml runs this after every push to main (and by hand). For
each open pull request whose base is main, draft or not, it asks GitHub for
the pull request itself: GitHub works out whether it merges only when asked
after the base moved (`mergeable` null, `mergeable_state` "unknown" until
then), so the pull requests not yet worked out are asked again, ROUNDS
times, WAIT seconds apart. A pull request that conflicts (`mergeable`
false, or `mergeable_state` "dirty") gets one comment per head: the
comment ends with a hidden marker naming the head it was about, and a pull
request whose newest such comment from github-actions[bot] names its
current head is not told again. After the session merges main the head
changes, so a later conflict is told again. A pull request still not
worked out after the last round is listed in the log and left to the next
push.

The comment never holds an at sign: the account's comments by a person
start claude.yml when they mention it, and this posts nothing a pull
request's author wrote (no titles, no branch names).

Python 3 standard library only:
    python3 -I tools/ci-watch/conflict_watch.py --main <sha>            # comment where needed
    python3 -I tools/ci-watch/conflict_watch.py --main <sha> --dry-run  # print, post nothing
    python3 -I tools/ci-watch/conflict_watch.py --selftest
Environment: GITHUB_REPOSITORY (owner/name), GH_TOKEN (not needed for
--dry-run on a public repository), GITHUB_STEP_SUMMARY (optional).
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

API = "https://api.github.com"
BASE = "main"
BOT = "github-actions[bot]"
MARKER = "<!-- conflict-watch head="
MARKED_HEAD = re.compile(r"<!-- conflict-watch head=([0-9a-f]{40}) -->")
ROUNDS = 8
WAIT = 15
NEXT_LINK = re.compile(r'<([^>]+)>;\s*rel="next"')


def request(path, token=None, body=None):
    url = path if path.startswith("https://") else API + path
    request = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None)
    request.add_header("Accept", "application/vnd.github+json")
    if token:
        request.add_unredirected_header("Authorization", f"Bearer {token}")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(request, timeout=60)


def api(path, token=None, body=None):
    with request(path, token, body) as response:
        return json.load(response)


def every_page(path, token=None):
    """The items of every page of a list endpoint, following its Link header."""
    items, url = [], path
    while url:
        with request(url, token) as response:
            items.extend(json.load(response))
            match = NEXT_LINK.search(response.headers.get("Link") or "")
        url = match.group(1) if match else None
    return items


def state_of(pr):
    """"conflict", "unknown" (GitHub has not worked it out yet) or "merges"."""
    if pr.get("mergeable") is False or pr.get("mergeable_state") == "dirty":
        return "conflict"
    if pr.get("mergeable") is None:
        return "unknown"
    return "merges"


def last_told_head(comments):
    """The head named by the newest comment of this tool on a pull request,
    or None. Only github-actions[bot]'s comments count."""
    told = None
    for comment in comments:
        if (comment.get("user") or {}).get("login") != BOT:
            continue
        found = MARKED_HEAD.findall(comment.get("body") or "")
        if found:
            told = found[-1]
    return told


def ask_until_known(numbers, fetch, sleep, rounds=ROUNDS, wait=WAIT):
    """Asks for each pull request until GitHub has worked out whether it
    merges: ({number: pull request} of the known ones, [numbers still
    unknown]). Pull requests closed meanwhile or no longer into main are
    dropped."""
    known, pending = {}, list(numbers)
    for round in range(rounds):
        still = []
        for number in pending:
            pr = fetch(number)
            if pr.get("state") != "open" or (pr.get("base") or {}).get("ref") != BASE:
                continue
            if state_of(pr) == "unknown":
                still.append(number)
            else:
                known[number] = pr
        pending = still
        if not pending:
            break
        if round + 1 < rounds:
            sleep(wait)
    return known, pending


def clean(text):
    # No mention of anyone, whatever a value holds.
    return text.replace("@", "＠")


def comment(pr, main_sha):
    head = pr["head"]["sha"]
    lines = [
        "**和 main 衝突，CI 不會跑，請併 main。**（自動留言，`conflict-watch.yml`，決策 830）",
        "",
        f"- 這張 PR 的 head：`{head[:7]}`",
        f"- main：`{main_sha[:7]}`",
        "- GitHub 做不出合併後的版本，這個 head 的 CI 不會開始，也不會變紅。",
        "- 做法：`git fetch origin main && git merge origin/main`，解完衝突、本機快檢後推上來，新的 head 才會跑 CI。",
        "- 同一個 head 只留這一則；併過 main 之後又衝突會再留。",
        "",
        f"{MARKER}{head} -->",
    ]
    text = clean("\n".join(lines)) + "\n"
    assert "@" not in text
    return text


def main(argv=None):
    parser = argparse.ArgumentParser(description="和 main 衝突的 open PR，在那張 PR 上留一則留言（決策 830）。")
    parser.add_argument("--main", help="剛推上 main 的 commit")
    parser.add_argument("--dry-run", action="store_true", help="只印出留言，不送出")
    parser.add_argument("--rounds", type=int, default=ROUNDS)
    parser.add_argument("--wait", type=int, default=WAIT, help="兩輪之間等幾秒")
    parser.add_argument("--selftest", action="store_true")
    options = parser.parse_args(argv)
    if options.selftest:
        return selftest()
    if not options.main or not re.fullmatch(r"[0-9a-f]{40}", options.main):
        parser.error("--main <40-character sha> is required")
    repository = os.environ.get("GITHUB_REPOSITORY", "a91453/railway-game-ios")
    token = os.environ.get("GH_TOKEN")
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    report = []

    def say(text):
        print(text)
        report.append(text)

    listed = every_page(f"/repos/{repository}/pulls?state=open&base={BASE}&per_page=100", token)
    say(f"Open pull requests into {BASE}: {len(listed)} (main `{options.main[:7]}`).")
    known, unknown = ask_until_known(
        [pr["number"] for pr in listed],
        lambda number: api(f"/repos/{repository}/pulls/{number}", token),
        time.sleep, options.rounds, options.wait)
    for number in sorted(known):
        pr = known[number]
        state = state_of(pr)
        if state != "conflict":
            say(f"- #{number}: merges ({pr.get('mergeable_state')}).")
            continue
        head = pr["head"]["sha"]
        comments = every_page(f"/repos/{repository}/issues/{number}/comments?per_page=100", token)
        if last_told_head(comments) == head:
            say(f"- #{number}: conflicts; already told about head `{head[:7]}`.")
            continue
        body = comment(pr, options.main)
        if options.dry_run:
            say(f"- #{number}: conflicts; would comment (dry run):")
            print(body)
            continue
        posted = api(f"/repos/{repository}/issues/{number}/comments", token, {"body": body})
        say(f"- #{number}: conflicts; told: {posted.get('html_url')}")
    for number in unknown:
        say(f"- #{number}: GitHub had not worked out whether it merges after {options.rounds} rounds; left to the next push.")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as out:
            out.write("\n".join(report) + "\n")
    return 0


def selftest():
    def pr(number, mergeable, state, head="a" * 40, open_=True, base=BASE):
        return {"number": number, "mergeable": mergeable, "mergeable_state": state, "state": "open" if open_ else "closed",
                "head": {"sha": head}, "base": {"ref": base}}

    # What GitHub says, as the REST API words it. A draft pull request has
    # its own mergeable_state on some days ("draft"); `mergeable` still
    # tells a conflict.
    assert state_of(pr(1, False, "dirty")) == "conflict"
    assert state_of(pr(1, False, "draft")) == "conflict", "a draft that conflicts is told too"
    assert state_of(pr(1, None, "dirty")) == "conflict"
    assert state_of(pr(1, None, "unknown")) == "unknown"
    for merges in ("clean", "unstable", "blocked", "behind", "draft", "has_hooks"):
        assert state_of(pr(1, True, merges)) == "merges", merges

    # One comment per head: the newest marker of the bot's own comments.
    head, newer = "1" * 40, "2" * 40
    told = comment(pr(7, False, "dirty", head=head), "f" * 40)
    assert last_told_head([]) is None
    assert last_told_head([{"user": {"login": BOT}, "body": told}]) == head
    assert last_told_head([{"user": {"login": "someone"}, "body": told}]) is None, "only the bot's comments count"
    assert last_told_head([{"user": {"login": BOT}, "body": told},
                           {"user": {"login": BOT}, "body": comment(pr(7, False, "dirty", head=newer), "f" * 40)}]) == newer
    assert last_told_head([{"user": {"login": BOT}, "body": "full lane 紅了"}, {"user": None, "body": None}]) is None

    # The comment: what to do, the head, no at sign.
    assert told.startswith("**和 main 衝突，CI 不會跑，請併 main。**"), told
    assert "`1111111`" in told and "`fffffff`" in told and "git merge origin/main" in told, told
    assert "@" not in told and told.rstrip().endswith(f"{MARKER}{head} -->"), told
    assert clean("a @claude b") == "a ＠claude b"

    # Asking until GitHub has worked it out: unknown twice, then a conflict;
    # one closed meanwhile; one retargeted; one that never settles.
    answers = {
        1: [pr(1, None, "unknown"), pr(1, None, "unknown"), pr(1, False, "dirty")],
        2: [pr(2, True, "clean")],
        3: [pr(3, None, "unknown"), pr(3, None, "unknown", open_=False)],
        4: [pr(4, None, "unknown", base="claude/other")],
        5: [pr(5, None, "unknown")] * 10,
    }
    asked, slept = [], []

    def fetch(number):
        asked.append(number)
        replies = answers[number]
        return replies.pop(0) if len(replies) > 1 else replies[0]

    known, pending = ask_until_known([1, 2, 3, 4, 5], fetch, slept.append, rounds=4, wait=9)
    assert sorted(known) == [1, 2] and state_of(known[1]) == "conflict" and state_of(known[2]) == "merges", known
    assert pending == [5], pending
    assert slept == [9, 9, 9], "no wait after the last round"
    assert asked.count(2) == 1 and asked.count(5) == 4, asked
    known, pending = ask_until_known([], fetch, slept.append)
    assert known == {} and pending == []
    print("selftest：all cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
