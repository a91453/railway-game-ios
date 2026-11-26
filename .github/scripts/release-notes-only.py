#!/usr/bin/env python3
"""Does a pull request change only the release notes? (decision 1017)

    release-notes-only.py --base REV [--head REV]   prints notes=true or notes=false
    release-notes-only.py --selftest

The release pull request (decision 415) moves the next build's lines from
`Sources/GamePresentation/WhatsNewNext/` into `WhatsNew.entries` and
rewrites `.github/testflight-whats-new.md`. Because `WhatsNew.swift` is in
the app, every push of it rebuilt the app on a macOS runner (29.9 minutes
of a 31-minute run, CIOPT-17, 0.6.0's release pull request was pushed 8
times) and ran the GamePresentation tests its names reach. Nothing in those
lines can change what the app does but the text of the What's New card, so
such a pull request runs only the tests that read the entries (ci.yml's
`notes` tier) and no iOS job (ios-build.yml's changes job).

notes=true only when all of these hold; anything else, or anything that
cannot be read, is notes=false and the usual checks run:

- Every changed file (base..head, renames as a delete and an add) is one of
  - `Sources/GamePresentation/WhatsNew.swift`, changed (not added or
    deleted), and only inside the `entries` array: the file with the
    array's body taken out is the same before and after, and every line
    of the new body is one of the literal forms the entries are written in
    (BODY_LINES): an `Entry(`, its `id`, `items: [`, `fixes: [`, a
    `Line(` with its `english:` and `chinese:` string, the closers, a
    `//` comment or a blank line. A string with an interpolation (`\\(`)
    or a multi-line string is not a literal form.
  - a `.txt` file in `Sources/GamePresentation/WhatsNewNext/new/` or
    `.../fixed/` (excluded from the package's target in Package.swift, so
    no build reads them; WhatsNewTests does),
  - `.github/testflight-whats-new.md` (read only by testflight.yml),
  - a Markdown file at the top level or anything under `docs/` (neither
    the app nor the package builds them; ci.yml's number check still runs
    for docs).
- At least one of the changed files is in `Sources/GamePresentation/`: a
  pull request of docs and the What to Test text alone is not one the
  Swift or iOS jobs run for anyway.

The Linux build (`swift build --build-tests -Xswiftc -warnings-as-errors`)
still compiles the new entries, so a typo in them is still red.
"""
import os
import re
import subprocess
import sys
import tempfile

WHATS_NEW = "Sources/GamePresentation/WhatsNew.swift"
NEXT_LINE = re.compile(r"Sources/GamePresentation/WhatsNewNext/(new|fixed)/[^/]+\.txt")
CURATED = ".github/testflight-whats-new.md"
ARRAY_START = "    public static let entries: [Entry] = ["
ARRAY_END = "    ]"

# A Swift string literal on one line with no interpolation: any character
# but a quote or a backslash, or a backslash and anything but `(`.
STRING = r'"(?:[^"\\]|\\[^(])*"'
BODY_LINES = [re.compile(pattern) for pattern in (
    r"",
    r"//.*",
    r"Entry\(",
    r"Line\(",
    r"\),?",
    r"id: " + STRING + ",",
    r"(items|fixes): \[",
    r"(items|fixes): \[\],?",
    r"\],?",
    r"english: " + STRING + ",",
    r"chinese: " + STRING + ",?",
)]


QUIET = False


def say(text):
    if not QUIET:
        print(text, file=sys.stderr)


def allowed_path(path):
    """Whether `path` is one of the files a release-notes change may touch."""
    if path == WHATS_NEW or path == CURATED or NEXT_LINE.fullmatch(path):
        return True
    if path.startswith("docs/"):
        return True
    return "/" not in path and path.endswith(".md")


def split_entries(text):
    """(before, body, after) of the entries array, or None when the file
    has not exactly one such array closed by a line of its own."""
    lines = text.split("\n")
    starts = [k for k, line in enumerate(lines) if line == ARRAY_START]
    if len(starts) != 1:
        return None
    start = starts[0]
    for end in range(start + 1, len(lines)):
        if lines[end] == ARRAY_END:
            return lines[:start + 1], lines[start + 1:end], lines[end:]
    return None


def entries_only(old, new):
    """Whether `new` differs from `old` only inside the entries array, and
    the new array holds only literal forms. Says why not on stderr."""
    old_parts, new_parts = split_entries(old), split_entries(new)
    if old_parts is None or new_parts is None:
        say(f"  {WHATS_NEW}: the entries array cannot be found.")
        return False
    if old_parts[0] != new_parts[0] or old_parts[2] != new_parts[2]:
        say(f"  {WHATS_NEW}: code outside the entries array changed.")
        return False
    for number, line in enumerate(new_parts[1], start=len(new_parts[0]) + 1):
        if not any(form.fullmatch(line.strip()) for form in BODY_LINES):
            say(f"  {WHATS_NEW}:{number}: not a literal entry line: {line.strip()}")
            return False
    return True


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def notes_only(base, head, cwd=None):
    """Whether base..head changes only the release notes (the module's
    docstring). Says each file's verdict on stderr."""
    changed = []
    for line in git("diff", "--no-renames", "--name-status", base, head, cwd=cwd).splitlines():
        status, _, path = line.partition("\t")
        if path:
            changed.append((status[:1], path))
    if not changed:
        say("No changed files.")
        return False
    for status, path in changed:
        if not allowed_path(path):
            say(f"  {path}: not a release-notes file.")
            return False
        if path == WHATS_NEW:
            if status != "M":
                say(f"  {path}: added or deleted ({status}).")
                return False
            old = git("show", f"{base}:{path}", cwd=cwd)
            new = git("show", f"{head}:{path}", cwd=cwd)
            if not entries_only(old, new):
                return False
        say(f"  {path}: release notes.")
    if not any(path.startswith("Sources/GamePresentation/") for _, path in changed):
        say("Nothing in Sources/GamePresentation/ changed.")
        return False
    return True


# Self-test -----------------------------------------------------------------

FILE = """public enum WhatsNew {{
    public static let entries: [Entry] = [
{body}
    ]

    public static var edition: String? {{ entries.first?.id }}
}}
"""
OLD_BODY = """        // 1.
        Entry(
            id: "one",
            items: [
                Line(
                    english: "A line.",
                    chinese: "一行。"
                ),
            ],
            fixes: []
        ),"""
NEW_ENTRY = """        // 2.
        Entry(
            id: "two",
            items: [
                Line(
                    english: "Trains \\"run\\" faster.",
                    chinese: "列車跑得更快。"
                ),
            ],
            fixes: [
                Line(
                    english: "Fixed.",
                    chinese: "修好了。"
                ),
            ]
        ),
"""


def selftest():
    global QUIET
    QUIET = True
    failures = 0

    def check(what, want, files, base_files=None):
        nonlocal failures
        with tempfile.TemporaryDirectory() as repo:
            def commit(contents):
                for path, text in contents.items():
                    full = os.path.join(repo, path)
                    if text is None:
                        os.remove(full)
                        continue
                    os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
                    with open(full, "w", encoding="utf-8") as handle:
                        handle.write(text)
                git("add", "-A", cwd=repo)
                git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "c", cwd=repo)
            git("init", "-q", cwd=repo)
            commit(base_files or {
                WHATS_NEW: FILE.format(body=OLD_BODY),
                "Sources/GamePresentation/WhatsNewNext/new/2026-11-26-a.txt": "en: A.\nzh: 甲。\n",
                CURATED: "old\n",
                "Sources/GamePresentation/GameSession.swift": "let a = 1\n",
                "README.md": "readme\n",
            })
            commit(files)
            try:
                got = notes_only("HEAD^", "HEAD", cwd=repo)
            except subprocess.CalledProcessError as error:
                got = f"error {error}"
        if got == want:
            print(f"ok   pass  release notes: {what} -> {want}")
        else:
            print(f"FAIL release notes: {what}: expected {want}, got {got}")
            failures += 1

    release = {
        WHATS_NEW: FILE.format(body=NEW_ENTRY + OLD_BODY),
        "Sources/GamePresentation/WhatsNewNext/new/2026-11-26-a.txt": None,
        CURATED: "new\n",
    }
    check("the release pull request (entries, the next lines, What to Test)", True, release)
    check("the release pull request with a doc", True, {**release, "docs/handoff/X.md": "x\n", "README.md": "more\n"})
    check("a pull request that only adds a next line", True,
          {"Sources/GamePresentation/WhatsNewNext/fixed/2026-11-27-b.txt": "en: B.\nzh: 乙。\n"})
    check("only the What to Test text", False, {CURATED: "new\n"})
    check("an entry beside another source file", False,
          {**release, "Sources/GamePresentation/GameSession.swift": "let a = 2\n"})
    check("an entry beside a test", False, {**release, "Tests/GamePresentationTests/WhatsNewTests.swift": "x\n"})
    check("code outside the entries array", False,
          {WHATS_NEW: FILE.format(body=OLD_BODY).replace("entries.first?.id", "entries.last?.id")})
    check("code inside the entries array", False,
          {WHATS_NEW: FILE.format(body=OLD_BODY.replace('id: "one",', 'id: makeID(),'))})
    check("an interpolation in a line", False,
          {WHATS_NEW: FILE.format(body=OLD_BODY.replace('"A line."', '"A \\(line)."'))})
    check("a multi-line string", False,
          {WHATS_NEW: FILE.format(body=OLD_BODY.replace('"A line."', '"""\n                    A line.\n                    """'))})
    check("a second array closed early", False,
          {WHATS_NEW: FILE.format(body=OLD_BODY + "\n    ]\n    static let x = 1\n    static let y: [Int] = [")})
    check("the file deleted", False, {WHATS_NEW: None})
    check("a next line outside new/ and fixed/", False,
          {"Sources/GamePresentation/WhatsNewNext/README.md": "x\n"})
    check("a Swift file in WhatsNewNext", False,
          {"Sources/GamePresentation/WhatsNewNext/new/x.swift": "let a = 1\n"})
    check("no change", False, {})
    return failures


def main(argv):
    if argv == ["--selftest"]:
        failures = selftest()
        print(f"release-notes-only.py self-test: {failures} failure(s)")
        return 1 if failures else 0
    base = head = None
    args = list(argv)
    while args:
        flag = args.pop(0)
        if flag == "--base" and args:
            base = args.pop(0)
        elif flag == "--head" and args:
            head = args.pop(0)
        else:
            say(__doc__)
            return 2
    if not base:
        say(__doc__)
        return 2
    try:
        only = notes_only(base, head or "HEAD")
    except (subprocess.CalledProcessError, OSError, UnicodeDecodeError) as error:
        say(f"Could not read the change ({error}); the usual checks run.")
        only = False
    print(f"notes={'true' if only else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
