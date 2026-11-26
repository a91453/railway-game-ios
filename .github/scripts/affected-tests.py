#!/usr/bin/env python3
"""The tests a pull request's changed files reach (decision 1012, CI-AFFECTED).

Reads the changed files on stdin (one path per line), run in the repository
root, and prints

    tests=<class> <class> ...
    weight=<seconds of tests, by CLASS_WEIGHTS>
    broad=<seconds of tests the broad tier would run>

or exits 3 with the reason on stderr when the change cannot be narrowed (the
caller then runs the broad tier, swift-shards.sh plan, as before).

What a file reaches, read as text like swift-shards.sh does (a top-level
declaration starts in column 0, the style of every Swift file here):

- A Swift file under Sources/: the names it declares at the top level (types,
  functions, constants), the members it adds to a type from elsewhere, and
  the members of its own types that are not too common a word to follow
  (MEMBER_FILES_LIMIT). The test files whose code names one of them are
  reached. Only direct users among the tests: a source file that calls the
  changed one is not followed (the reverse closure over the sources reaches
  every test through the session and scene types; measured on 40 pull
  requests, 2026-11-26). The push run on main after the merge runs the
  broad tier, which catches what this leaves out, and the nightly run runs
  everything.
- A Swift file under Tests/: its own test classes, and what its names reach.
- A test file reached: its classes run, and the names it declares (helpers,
  a campaign's static generator) reach further test files, until nothing new
  is reached (the test side is followed all the way, as fixture_readers does).
- Any other file (bundled data, a text resource, a fixture, a tool's file a
  test reads): the Swift files that name it in a string, by its file name,
  its name without the extension, or else its nearest folder whose name they
  name; those files count as changed. Nothing names it: the broad tier.
- Any changed file: the test classes whose files spell its path, or a folder
  above it, in a string (`"Sources/GamePresentation"`: a test that scans
  every source file for a pattern) run too.
- Package.swift, Package.resolved, the CI scripts, ci.yml, a deleted Swift
  file, a file whose declarations cannot be followed by name (a top-level
  operator, statements at the top level): the broad tier.

SMOKE always runs beside the reached tests: the golden scenarios, the saves
and replays every build must still read, the world's state machine, a new
game on every start map, the bundled data's loading and the pull request
timetable checkup: whether the change broke the main body of the game.

A narrowed selection is used only when it is at most NARROW_SHARE of what the
broad tier runs; otherwise the broad tier's even shards are no slower.
"""
import os
import re
import sys

SMOKE = [
    "GoldenScenarioTests", "SavedGameTests", "ReplayFixtureTests",
    "WorldStateMachineTests", "Map3DOpenEveryStartTests",
    "RealWorldDataLoadTests", "TimetableCheckupTests",
    "TimetableCheckupTaiwanTests",
]
NARROW_SHARE = 0.5
# A member name declared in more files than this (id, name, count, body) is
# too common a word to say who uses the type; the type's own name still is.
MEMBER_FILES_LIMIT = 12
# Files a broad tier always runs everything for.
FULL_PATHS = re.compile(r"^(Package\.swift|Package\.resolved|\.github/scripts/|\.github/workflows/ci\.yml$)")
# Paths that can change what the package builds or tests (relevant_paths).
# A path in a test's string literal, as a test that reads files spells it.
PATH_LITERAL = re.compile(r'"((?:Sources|Tests|RailwayGameApp|GoldenScenarios|SaveFixtures|ReplayFixtures)(?:/[^"\\\s]*)?)"')
PACKAGE_PATHS = re.compile(r"^(Sources/|Tests/|GoldenScenarios/|SaveFixtures/|ReplayFixtures/|RailwayGameApp/Resources/)")

MODIFIERS = r"(?:(?:public|internal|open|final|nonisolated|private|fileprivate|package|indirect)\s+)*"
ATTRIBUTES = r"(?:@\w+(?:\([^)]*\))?\s+)*"
TOP = re.compile(r"^" + ATTRIBUTES + MODIFIERS + r"(struct|enum|class|actor|protocol|typealias|func|let|var|extension)\s+([A-Za-z_]\w*)?")
MEMBER = re.compile(
    r"^    " + ATTRIBUTES
    + r"(?:(?:public|internal|static|class|mutating|nonmutating|override|nonisolated|final|convenience|required|lazy|private|fileprivate|package|indirect)\s+)*"
    + r"(func|var|let|case|struct|enum|class|actor|typealias|init|subscript)\b\s*([A-Za-z_]\w*)?")
WORD = re.compile(r"[A-Za-z_]\w*")
DOTTED = re.compile(r"\b([A-Z]\w*)\.([A-Za-z_]\w*)")


def tokens(line):
    """The words of a line, and its Type.member pairs."""
    return set(WORD.findall(line)) | {f"{a}.{b}" for a, b in DOTTED.findall(line)}


class Unfollowed(Exception):
    pass


def code_lines(text):
    """The lines without comments, as swift-shards.sh code_lines reads them."""
    out = []
    for line in text.splitlines():
        if re.match(r"\s*(//|/\*|\*)", line):
            continue
        out.append(re.sub(r"\s//.*$", "", line))
    return out


def followable(name):
    """A name specific enough to say who uses it: a type's (capitalised) or a
    camel-case one. A one-word lower-case name (place, track, height, sets)
    is also every other file's local variable."""
    return len(name) >= 3 and any(c.isupper() for c in name)


class Block:
    """A top-level declaration and the lines up to the next one."""

    def __init__(self):
        self.declared = set()   # every name it declares, private ones too
        self.exported = set()   # the names another file can use
        self.owner = None       # the type it declares or extends in this file
        self.words = set()


class SwiftFile:
    def __init__(self, path):
        self.path = path
        self.module = path.split("/")[1]
        with open(path, encoding="utf-8", errors="replace") as handle:
            self.text = handle.read()
        lines = code_lines(self.text)
        self.words = set(WORD.findall("\n".join(lines)))
        self.opaque = None      # why the declarations cannot be followed
        self.classes = {}       # class name -> superclass (first inherited name)
        self.members = set()    # members of the file's own types
        self.blocks = []
        own = set()
        for line in lines:
            match = TOP.match(line)
            if match and match.group(1) != "extension" and match.group(2):
                own.add(match.group(2))
        top = None              # the current top-level declaration's first block
        block = None            # the block the lines go to: top, or one member
        extending = None        # the type an extension of another file's type extends
        inside_own = False
        private = False
        for line in lines:
            if re.match(r"^[A-Za-z@]", line) and not re.match(r"^@\w+(\([^)]*\))?\s*$", line):
                extending, inside_own = None, False
                if re.match(r"^(@testable\s+)?import\s", line):
                    continue
                top = block = Block()
                self.blocks.append(block)
                private = bool(re.match(r"^" + ATTRIBUTES + r"(private|fileprivate)\s", line))
                match = TOP.match(line)
                if not match or not match.group(2):
                    if not private:
                        self.opaque = self.opaque or f"a top-level line: {line.strip()[:60]}"
                    block.words |= tokens(line)
                    continue
                kind, name = match.groups()
                rest = line[match.end():]
                if kind == "extension":
                    # An extension of a test class from another file holds
                    # that class's tests.
                    block.owner = name
                    if name in own:
                        inside_own = True
                    else:
                        extending = name
                        # A conformance added to a type from elsewhere is
                        # used through that type.
                        if re.match(r"\s*[:<]", rest) or " where " in rest:
                            block.exported.add(name)
                else:
                    block.declared.add(name)
                    block.owner = name
                    if not private:
                        block.exported.add(name)
                    inside_own = kind in ("struct", "enum", "class", "actor", "protocol")
                    if kind == "class":
                        parent = re.match(r"\s*(?:<[^>]*>)?\s*:\s*([A-Za-z_]\w*)", rest)
                        self.classes[name] = parent.group(1) if parent else None
                block.words |= tokens(rest)
                continue
            if top is None:
                continue
            match = MEMBER.match(line) if (extending or inside_own) else None
            if not match:
                block.words |= tokens(line)
                continue
            # Each member of a type is a block of its own: a test reaches the
            # helper it calls, not every helper beside it.
            kind, name = match.groups()
            block = Block()
            block.owner = top.owner
            self.blocks.append(block)
            block.words |= tokens(line[match.end():])
            if name:
                block.declared.add(name)
            if private or re.match(r"^    " + ATTRIBUTES + r"(private|fileprivate)\s", line):
                continue
            if extending:
                # An init, subscript or operator is used through the type.
                if kind in ("init", "subscript") or not name:
                    block.exported.add(extending)
                else:
                    block.exported.add(name)
            elif name and kind not in ("init", "subscript"):
                self.members.add(name)
                if path.startswith("Tests/"):
                    # A test file's own type is used through its name
                    # (SavedGameTests.fixtures); its other members are tests.
                    block.exported.add(f"{top.owner}.{name}")
                else:
                    # A source type's members name it for the tests that
                    # reach it through an instance.
                    block.exported.add(name)
        for block in self.blocks:
            block.exported = {n for n in block.exported if followable(n)}
        # A file that only adds what no test can name to another file's type
        # (a model's encoded mesh) is reached through that type.
        if not any(b.exported for b in self.blocks):
            for block in self.blocks:
                if block.owner and block.owner not in own and followable(block.owner):
                    block.exported.add(block.owner)
        self.names = set().union(*(b.exported for b in self.blocks)) if self.blocks else set()


class Repository:
    def __init__(self):
        self.files = {}
        for root in ("Sources", "Tests"):
            for directory, _, names in os.walk(root):
                for name in sorted(names):
                    if name.endswith(".swift"):
                        path = os.path.join(directory, name)
                        self.files[path] = SwiftFile(path)
        self.literals = None
        self.sources = [f for p, f in sorted(self.files.items()) if p.startswith("Sources/")]
        self.tests = [f for p, f in sorted(self.files.items()) if p.startswith("Tests/")]
        member_files = {}
        for f in self.sources:
            for name in f.members:
                member_files[name] = member_files.get(name, 0) + 1
        self.common = {n for n, k in member_files.items() if k > MEMBER_FILES_LIMIT}
        # Test classes: directly, or through another test class, an XCTestCase.
        parents = {}
        for f in self.tests:
            parents.update(f.classes)
        tested = {}

        def is_test(name, depth=0):
            if name == "XCTestCase":
                return True
            if name not in parents or depth > 20:
                return False
            if name not in tested:
                tested[name] = parents[name] is not None and is_test(parents[name], depth + 1)
            return tested[name]

        for f in self.tests:
            f.test_classes = {c for c in f.classes if is_test(c)}
        self.all_classes = {c: f for f in self.tests for c in f.test_classes}
        # Which test declarations name a word.
        self.index = {}
        for f in self.tests:
            for block in f.blocks:
                block.file = f
                for word in block.words:
                    self.index.setdefault(word, []).append(block)

    def path_readers(self, path):
        """The test files that read the file or a folder above it by its path
        (a test that scans every source file of a module for a pattern)."""
        if self.literals is None:
            self.literals = {
                f: set(PATH_LITERAL.findall(f.text)) for f in self.tests
            }
        return [
            f for f, found in self.literals.items()
            if any(path == lit or path.startswith(lit.rstrip("/") + "/") for lit in found)
        ]

    def followed_names(self, f):
        if f.opaque:
            raise Unfollowed(f"{f.path}: {f.opaque}")
        names = f.names - (self.common & f.members)
        if not names:
            raise Unfollowed(f"{f.path}: declares nothing a test can name")
        return names

    def naming(self, component):
        """The Swift files that name a path component in a string."""
        pattern = re.compile(r'["/]' + re.escape(component) + r'["/.]')
        return [f for f in self.files.values() if pattern.search(f.text)]

    def reached_by_data(self, path):
        parts = path.split("/")
        if parts[0] in ("Sources", "Tests"):
            parts = parts[2:]
        elif parts[:2] == ["RailwayGameApp", "Resources"]:
            parts = parts[2:]
        base = parts[-1]
        stem = base.rsplit(".", 1)[0]
        candidates = [base] + ([stem] if stem != base and len(stem) >= 4 else [])
        candidates += [p for p in reversed(parts[:-1]) if len(p) >= 4]
        for component in candidates:
            hits = self.naming(component)
            if hits:
                return component, hits
        raise Unfollowed(f"{path}: no Swift file names it or its folders")


def weights_from(text):
    weights = {}
    for pair in text.split():
        if ":" in pair:
            name, value = pair.split(":", 1)
            try:
                weights[name] = int(value)
            except ValueError:
                pass
    return weights


def plan(paths, repo, log):
    names = set()
    classes = set()
    test_files = set()
    readers_of = {}
    for path in paths:
        if FULL_PATHS.match(path):
            raise Unfollowed(f"{path}: the package or the CI scripts")
        if path.startswith("tools/"):
            hits = [f for f in repo.tests if path in f.text]
            if hits:
                test_files.update(f.path for f in hits)
                log(f"  {path}: read by {', '.join(f.path for f in hits)}")
            continue
        if not PACKAGE_PATHS.match(path):
            continue
        readers = [f for f in repo.path_readers(path) if f.path != path]
        if readers:
            for f in readers:
                for c in f.test_classes:
                    readers_of.setdefault(c, path)
            log(f"  {path}: its path is read by {', '.join(f.path for f in readers)}")
        if path.endswith(".swift") and path.startswith(("Sources/", "Tests/")):
            f = repo.files.get(path)
            if f is None:
                raise Unfollowed(f"{path}: deleted or renamed")
            if path.startswith("Sources/") and f.module not in ("GameCore", "GamePresentation"):
                raise Unfollowed(f"{path}: module {f.module}")
            if path.startswith("Tests/"):
                test_files.add(path)
                log(f"  {path}: its own classes and what its names reach")
            else:
                found = repo.followed_names(f)
                names |= found
                log(f"  {path}: {len(found)} names")
            continue
        component, hits = repo.reached_by_data(path)
        for f in hits:
            if f.path.startswith("Tests/"):
                test_files.add(f.path)
            else:
                names |= repo.followed_names(f)
        log(f"  {path}: named as '{component}' by {len(hits)} Swift files")
    # The test side, followed to the end: a changed test file's classes, and
    # the declarations the names reach, through the names those declare
    # (a private helper only inside its own file).
    for path in test_files:
        f = repo.files[path]
        if f.opaque:
            raise Unfollowed(f"{f.path}: {f.opaque}")
        classes |= f.test_classes
        names |= f.names
    reason = {}
    queue = [(name, None, "changed") for name in sorted(names)]
    seen = set()
    hit = set()
    while queue:
        name, inside, why = queue.pop()
        if (name, inside) in seen:
            continue
        seen.add((name, inside))
        for block in repo.index.get(name, ()):
            if id(block) in hit or (inside is not None and block.file is not inside):
                continue
            hit.add(id(block))
            if block.owner in repo.all_classes and block.owner not in classes:
                classes.add(block.owner)
                reason[block.owner] = name if why == "changed" else f"{name} <- {why}"
            for other in block.exported:
                queue.append((other, None, name))
            for other in block.declared - block.exported - repo.common:
                queue.append((other, block.file, name))
    for c, path in readers_of.items():
        if c not in classes:
            classes.add(c)
            reason[c] = f"reads {path} by its path"
    plan.reason = reason
    return classes


def main():
    paths = [line.strip() for line in sys.stdin if line.strip()]
    weights = weights_from(os.environ.get("CLASS_WEIGHTS", ""))
    default = int(os.environ.get("CLASS_WEIGHT_DEFAULT", "1"))
    broad_tier = os.environ.get("BROAD_TIER", "full")
    broad_tests = os.environ.get("BROAD_TESTS", "").split()

    def log(message):
        print(message, file=sys.stderr)

    def weight(names):
        return sum(weights.get(c, default) for c in names)

    repo = Repository()
    try:
        reached = plan(paths, repo, log)
    except Unfollowed as reason:
        log(f"Narrowing: not possible ({reason}); the broad tier runs.")
        return 3
    if broad_tier == "full":
        broad = set(repo.all_classes)
    else:
        broad = set()
        for word in broad_tests:
            if word.endswith(".*"):
                module = word[:-2]
                broad |= {c for c, f in repo.all_classes.items() if f.module == module}
            else:
                broad.add(word)
    selected = (reached | set(SMOKE)) & set(repo.all_classes)
    narrow, wide = weight(selected), weight(broad)
    log(f"Narrowing: {len(reached)} classes reached and {len(SMOKE)} smoke classes, "
        f"{narrow} s of tests against the broad tier's {wide} s ({broad_tier}).")
    if wide and narrow > NARROW_SHARE * wide:
        log(f"Narrowing: more than {NARROW_SHARE:.0%} of the broad tier; the broad tier runs.")
        return 3
    for name in sorted(selected):
        log(f"  {name}: {plan.reason.get(name, 'smoke' if name in SMOKE else 'a changed test file')}")
    print("tests=" + " ".join(sorted(selected)))
    print(f"weight={narrow}")
    print(f"broad={wide}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
