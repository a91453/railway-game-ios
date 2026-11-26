#!/usr/bin/env python3
"""Which UI tests does a pull request's iOS gate run? (decision 1019)

    ui-gate.py --base REV [--head REV]   prints ui=toolbar or ui=gate
    ui-gate.py --selftest

ios-build.yml's pull request gate runs four UI tests on an iPhone
Simulator (decision 199): the English toolbar (the app opens on its start
screen, a blank new game starts and every tool button can be touched),
Back to Start with large text while the clock runs, and the tutorial's
track and line steps. All four play on a blank map's 2D screen; none opens
the 3D map, a real-world map or an overseas map pack.

A pull request that changes only what those screens never show (a 3D
model or scene, a map's data, the release notes) gets nothing from the
other three that the toolbar test does not already give: the same launch,
the same blank map. So it runs the toolbar test alone (ui=toolbar), some
3.4 minutes less on a hosted runner (PR #2780's run 45877166515: the four
took 72, 36, 91 and 40 s). The full lane (nightly and by hand) still runs
every UI test, the 3D map's among them, and the Linux tests still check
the models (budgets, shapes) and the data.

ui=toolbar only when every changed file (base..head, renames as a delete
and an add) is one of these; anything else, or anything that cannot be
read, is ui=gate and the four run as before:

- a path ios-build.yml does not run for (IGNORED, its paths-ignore: docs,
  tests, tools, the other workflows), or `.gitattributes`;
- a data folder of the app that only the 3D map, the real-world maps and
  the overseas map packs read (DATA): `RailwayGameApp/Resources/`
  MapPacks, RealWorld, RealRailways, RealBuses, RealCoaches, Map3D, Models
  (not BaseMap, whose tiles the blank map's 2D screen draws);
- the release notes: `Sources/GamePresentation/WhatsNew.swift` changed
  only inside its entries (release-notes-only.py's own test), a line in
  `WhatsNewNext/new/` or `fixed/`;
- a `Sources/GamePresentation/Map3D*.swift` file none of whose top-level
  names (the types, extensions, functions and constants it declares,
  before or after the change) appears in the app's own 2D code
  (`RailwayGameApp/App/`, `RailwayGameApp/Views/` but `Views/Map3D/` and
  `CityView3D.swift`, the 3D screens). A 3D file the 2D screens name (the
  3D quality setting, the hand-off from the 2D map, the streets the 2D
  map seeds with `Map3DScene`, a landmark the 2D map draws) takes the
  four. GamePresentation's other files are not read: they reach the
  gate's screens through those views, and the toolbar test opens the same
  blank map and the same views as the other three.

The iPad job's rule (the tutorial's own files) is the changes job's own;
a tutorial file is never one of these, so it always takes the four.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

IGNORED = re.compile(
    r"[^/]*\.md|docs/.*|Tests/.*|GoldenScenarios/.*|SaveFixtures/.*|ReplayFixtures/.*|Web/.*|tools/.*|\.claude/.*"
    r"|\.github/workflows/(ci|wasm-probe|ios-full-lane|release-archive|website-screenshots|claude"
    r"|full-lane-watch|conflict-watch|lessons-link|ios-compilation-cache)\.yml"
    r"|\.github/workflows/testflight[^/]*\.yml|\.github/scripts/swift-shards[^/]*\.sh"
    r"|\.github/scripts/testflight-.*|\.github/scripts/install-swift-linux\.sh|\.github/testflight-whats-new\.md"
    r"|\.gitattributes")
DATA = re.compile(r"RailwayGameApp/Resources/(MapPacks|RealWorld|RealRailways|RealBuses|RealCoaches|Map3D|Models)/.+")
WHATS_NEW = "Sources/GamePresentation/WhatsNew.swift"
NEXT_LINE = re.compile(r"Sources/GamePresentation/WhatsNewNext/(new|fixed)/[^/]+\.txt")
MAP3D = re.compile(r"Sources/GamePresentation/Map3D[^/]*\.swift")
TWO_D = re.compile(r"RailwayGameApp/(App|Views)/.*\.swift")
THREE_D = re.compile(r"RailwayGameApp/Views/(Map3D/.*|CityView3D\.swift)|Sources/GamePresentation/Map3D[^/]*\.swift")
# A top-level declaration (no indentation): its name, or the first part of
# an extension's dotted name.
DECLARATION = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|package|fileprivate|private|final|open|nonisolated|indirect)\s+)*"
    r"(?:struct|class|enum|protocol|actor|typealias|extension|func|let|var)\s+`?([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE)

QUIET = False


def say(text):
    if not QUIET:
        print(text, file=sys.stderr)


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def entries_only():
    """release-notes-only.py's check that WhatsNew.swift changed only in
    its entries, loaded from beside this script."""
    spec = importlib.util.spec_from_file_location("release_notes_only", os.path.join(HERE, "release-notes-only.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.QUIET = True
    return module.entries_only


def declared_names(text):
    return set(DECLARATION.findall(text))


def two_d_text(head, cwd=None):
    """The 2D side's code at head, as one string."""
    paths = [path for path in git("ls-tree", "-r", "--name-only", head, cwd=cwd).splitlines()
             if TWO_D.fullmatch(path) and not THREE_D.fullmatch(path)]
    if not paths:
        return ""
    request = "".join(f"{head}:{path}\n" for path in paths)
    out = subprocess.run(["git", "cat-file", "--batch"], cwd=cwd, check=True, capture_output=True,
                         input=request.encode()).stdout
    return out.decode("utf-8", errors="replace")


def toolbar_only(base, head, cwd=None):
    """Whether base..head needs only the toolbar test (the module's
    docstring). Says why not on stderr."""
    changed = []
    for line in git("diff", "--no-renames", "--name-status", base, head, cwd=cwd).splitlines():
        status, _, path = line.partition("\t")
        if path:
            changed.append((status[:1], path))
    if not changed:
        say("No changed files.")
        return False
    three_d = []
    for status, path in changed:
        if IGNORED.fullmatch(path) or DATA.fullmatch(path) or NEXT_LINE.fullmatch(path):
            continue
        if path == WHATS_NEW:
            if status != "M":
                say(f"  {path}: added or deleted ({status}).")
                return False
            if not entries_only()(git("show", f"{base}:{path}", cwd=cwd), git("show", f"{head}:{path}", cwd=cwd)):
                say(f"  {path}: changed outside its entries.")
                return False
            continue
        if MAP3D.fullmatch(path):
            three_d.append((status, path))
            continue
        say(f"  {path}: a screen the gate's UI tests show may use it.")
        return False
    if three_d:
        names = set()
        for status, path in three_d:
            if status != "A":
                names |= declared_names(git("show", f"{base}:{path}", cwd=cwd))
            if status != "D":
                names |= declared_names(git("show", f"{head}:{path}", cwd=cwd))
        text = two_d_text(head, cwd=cwd)
        for name in sorted(names):
            if re.search(r"\b" + re.escape(name) + r"\b", text):
                say(f"  {name} (a Map3D file's) is named by the 2D screens' code.")
                return False
    return True


# Self-test -----------------------------------------------------------------

WHATS_NEW_FILE = """public enum WhatsNew {{
    public static let entries: [Entry] = [
{body}
    ]

    public static var edition: String? {{ entries.first?.id }}
}}
"""
ENTRY = """        Entry(
            id: "{id}",
            items: [],
            fixes: []
        ),"""

BASE_FILES = {
    WHATS_NEW: WHATS_NEW_FILE.format(body=ENTRY.format(id="one")),
    "Sources/GamePresentation/Map3DCastle.swift": "public enum Map3DCastle {\n    static let parts = 1\n}\n",
    "Sources/GamePresentation/Map3DCastleMesh.swift": "extension Map3DCastle {\n    static let mesh = [0]\n}\n",
    "Sources/GamePresentation/Map3DQuality.swift": "public struct Map3DQuality {}\n",
    "Sources/GamePresentation/Map3DLandmarkRegistryList.swift": "extension Map3DLandmarkRegistry {\n    static let all = [Map3DCastle.self]\n}\n",
    "Sources/GamePresentation/Map3DLandmarkRegistry.swift": "public enum Map3DLandmarkRegistry {}\n",
    "Sources/GamePresentation/GameSession.swift": "let a = 1\n",
    "RailwayGameApp/Views/ControlPanel.swift": "let quality = Map3DQuality()\n",
    "Sources/GamePresentation/RealTemples.swift": "let castle = Map3DCastle.parts\n",
    "RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift": "let castle = Map3DCastle.parts\n",
    "RailwayGameApp/Views/TutorialOverlay.swift": "let a = 1\n",
    "RailwayGameApp/Resources/MapPacks/fukuoka/pack.json": "{}\n",
    "RailwayGameApp/Resources/BaseMap/style.json": "{}\n",
    "RailwayGameApp/Resources/Localizable.xcstrings": "{}\n",
    "README.md": "readme\n",
}


def selftest():
    global QUIET
    QUIET = True
    failures = 0

    def check(what, want, files):
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
            commit(BASE_FILES)
            commit(files)
            try:
                got = toolbar_only("HEAD^", "HEAD", cwd=repo)
            except subprocess.CalledProcessError as error:
                got = f"error {error}"
        if got == want:
            print(f"ok   pass  UI gate: {what} -> {'toolbar' if want else 'gate'}")
        else:
            print(f"FAIL UI gate: {what}: expected {want}, got {got}")
            failures += 1

    castle = {"Sources/GamePresentation/Map3DCastleMesh.swift": "extension Map3DCastle {\n    static let mesh = [0, 1]\n}\n"}
    check("a 3D model's mesh", True, castle)
    check("a new 3D model and the registry's list", True, {
        "Sources/GamePresentation/Map3DTower.swift": "public enum Map3DTower {}\n",
        "Sources/GamePresentation/Map3DLandmarkRegistryList.swift":
            "extension Map3DLandmarkRegistry {\n    static let all = [Map3DCastle.self, Map3DTower.self]\n}\n",
    })
    check("a 3D model deleted", True, {"Sources/GamePresentation/Map3DCastleMesh.swift": None})
    check("a 3D model with a map pack, a doc and a release note", True, {
        **castle,
        "RailwayGameApp/Resources/MapPacks/fukuoka/pack.json": "{\"v\": 2}\n",
        "docs/handoff/X.md": "x\n",
        "Sources/GamePresentation/WhatsNewNext/new/2026-11-27-castle.txt": "en: A castle.\nzh: 城。\n",
        WHATS_NEW: WHATS_NEW_FILE.format(body=ENTRY.format(id="two") + "\n" + ENTRY.format(id="one")),
    })
    check("only a map's data", True, {"RailwayGameApp/Resources/MapPacks/fukuoka/pack.json": "{\"v\": 2}\n"})
    check("a 3D file the 2D side names", False, {"Sources/GamePresentation/Map3DQuality.swift": "public struct Map3DQuality { var a = 1 }\n"})
    check("a 3D file whose old name the 2D side named", False, {
        "Sources/GamePresentation/Map3DQuality.swift": "public struct Map3DLevel {}\n",
        "RailwayGameApp/Views/ControlPanel.swift": "let quality = Map3DLevel()\n",
    })
    check("a 3D file only GamePresentation's other files name", True,
          {"Sources/GamePresentation/Map3DCastle.swift": "public enum Map3DCastle {\n    static let parts = 2\n}\n"})
    check("a 3D model beside a 2D source file", False, {**castle, "Sources/GamePresentation/GameSession.swift": "let b = 2\n"})
    check("a 3D model beside the tutorial", False, {**castle, "RailwayGameApp/Views/TutorialOverlay.swift": "let a = 2\n"})
    check("the base map", False, {"RailwayGameApp/Resources/BaseMap/style.json": "{\"v\": 2}\n"})
    check("the string catalog", False, {"RailwayGameApp/Resources/Localizable.xcstrings": "{\"v\": 2}\n"})
    check("What's New outside its entries", False,
          {WHATS_NEW: WHATS_NEW_FILE.format(body=ENTRY.format(id="one")).replace("first", "last")})
    check("this workflow", False, {".github/workflows/ios-build.yml": "x\n"})
    check("only docs (the iOS jobs do not run; the toolbar would do)", True, {"docs/x.md": "x\n"})
    check("no change", False, {})
    return failures


def main(argv):
    if argv == ["--selftest"]:
        failures = selftest()
        print(f"ui-gate.py self-test: {failures} failure(s)")
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
        toolbar = toolbar_only(base, head or "HEAD")
    except (subprocess.CalledProcessError, OSError, UnicodeDecodeError, ImportError, AttributeError) as error:
        say(f"Could not read the change ({error}); the gate's four UI tests run.")
        toolbar = False
    print(f"ui={'toolbar' if toolbar else 'gate'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
