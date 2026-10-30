#!/usr/bin/env python3
"""The golden scenarios in New Taiwan dollars (decision 499, golden schema
75): every amount is three times the reference's dollar.

Three steps, each editing the fixtures in place, number by number, so a
file keeps its own layout:

  --rewrite-inputs   scale what a fixture puts into the world: the
                     starting balance, the construction costs, and the
                     fares of `setFareRules`; set `schemaVersion` to 75.
  --apply-log LOG    take the values GameCore gives, from the failures of
                     `swift test --filter GoldenScenarioTests` written to
                     LOG ("steps[i]: expected X, got Y" and the final
                     state's "expected:"/"actual:"), for each number that
                     differs; a difference in anything but a number (a
                     list's length, a key, a string) is printed and left.
  --verify [BASE]    compare every fixture with its copy at BASE (git,
                     default origin/main): each number is unchanged or
                     three times the old one, and only under the keys of
                     MONEY; prints every other change, and exits 1 if
                     there is one not in EXCEPTIONS.

Python 3 standard library only:
python3 -I tools/golden-checks/nt_scale.py --verify
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "GoldenScenarios"
SCHEMA = 75

# The keys whose numbers are amounts of money, in cents.
# `track`, `station` and `train` only under `costs` (elsewhere they are IDs).
MONEY = {
    "balance", "fare", "required", "available",
    "amount", "price", "bookValue", "buildingBookValue", "buildingCost",
    "saleBookValue", "saleProceeds", "landCost", "fareRevenue",
    "operatingCost", "maintenanceCost", "energyCost", "staffCost",
    "propertyCost", "propertyRevenue", "pendingRevenue", "reward", "owed",
    "paid", "value", "base", "servicePremium", "accessPremium",
    "parkPremium", "waterPremium", "companyPremium",
}

COSTS = {"track", "station", "train"}


def is_money(where, key):
    if key in COSTS:
        return where.endswith(f".costs.{key}")
    # A town's growth base is its daily trips, not a land value's base.
    if key == "base" and ".townGrowth." in where:
        return False
    # A building sale's parts (decision 130).
    if key in SALE and ".buildingSale." in where:
        return True
    return key in MONEY


SALE = {"land", "landRight", "building"}


# Changes --verify accepts that are not three times the old value:
# (file, path) → why. Filled from the run, each one explained in the pull
# request.
EXCEPTIONS = {
    ("high-speed.json", ".steps[34].expect.fare"): "NT$4.38 a kilometre (decision 499), not 3 × $0.45",
    ("high-speed.json", ".steps[35].expect.fare"): "NT$4.38 a kilometre (decision 499), not 3 × $0.45",
    ("high-speed.json", ".steps[36].expect.fare"): "NT$4.38 a kilometre (decision 499), not 3 × $0.45",
}

# Fixtures whose ledger amounts may be off 3 × old by up to so many cents:
# file → (cents, why). An hour's costs, a batch of fares and a day's line
# shares are rounded to whole dollars once from 3 times the cents, not
# rounded in dollars and then tripled (decision 499): at most NT$1 a line
# an hour, so NT$24 a day a line and as much in the balance.
ROUNDED = {
    name: (2_100, "an hour's costs rounded to whole NT$ once (decision 499)")
    for name in ("city-buildings-growth.json", "city-buildings-raise.json", "land-value.json",
                 "materials-growth.json", "water-terrain.json", "zoning.json")
}
ROUNDED["economy.json"] = (200, "an hour's costs and a batch of fares rounded to whole NT$ once (decision 499)")
ROUNDED["line-accounts.json"] = (4_800, "an hour's costs rounded to whole NT$ once, on each of two lines (decision 499)")


# A JSON reader that keeps where each number is in the text.

class Num:
    def __init__(self, value, start, end):
        self.value, self.start, self.end = value, start, end


def parse(text):
    pos = 0

    def ws():
        nonlocal pos
        while pos < len(text) and text[pos] in " \t\r\n":
            pos += 1

    def value():
        nonlocal pos
        ws()
        c = text[pos]
        if c == "{":
            pos += 1
            out = {}
            ws()
            if text[pos] == "}":
                pos += 1
                return out
            while True:
                ws()
                key = string()
                ws()
                assert text[pos] == ":"
                pos += 1
                out[key] = value()
                ws()
                if text[pos] == ",":
                    pos += 1
                    continue
                assert text[pos] == "}"
                pos += 1
                return out
        if c == "[":
            pos += 1
            out = []
            ws()
            if text[pos] == "]":
                pos += 1
                return out
            while True:
                out.append(value())
                ws()
                if text[pos] == ",":
                    pos += 1
                    continue
                assert text[pos] == "]"
                pos += 1
                return out
        if c == '"':
            return string()
        m = re.compile(r"-?\d+(\.\d+)?([eE][-+]?\d+)?").match(text, pos)
        if m:
            pos = m.end()
            return Num(json.loads(m.group()), m.start(), m.end())
        for word, v in (("true", True), ("false", False), ("null", None)):
            if text.startswith(word, pos):
                pos += len(word)
                return v
        raise ValueError(f"bad JSON at {pos}")

    def string():
        nonlocal pos
        m = re.compile(r'"(?:[^"\\]|\\.)*"').match(text, pos)
        pos = m.end()
        return json.loads(m.group())

    return value()


def plain(node):
    if isinstance(node, Num):
        return node.value
    if isinstance(node, dict):
        return {k: plain(v) for k, v in node.items()}
    if isinstance(node, list):
        return [plain(v) for v in node]
    return node


def splice(text, edits):
    for start, end, new in sorted(edits, reverse=True):
        text = text[:start] + new + text[end:]
    return text


def fixture_files():
    return sorted(FIXTURES.glob("*.json"))


# --rewrite-inputs

def rewrite_inputs():
    for path in fixture_files():
        text = path.read_text()
        tree = parse(text)
        edits = []

        def times3(num):
            edits.append((num.start, num.end, str(num.value * 3)))

        if tree["schemaVersion"].value != SCHEMA:
            edits.append((tree["schemaVersion"].start, tree["schemaVersion"].end, str(SCHEMA)))
        state = tree["initialState"]
        times3(state["balance"])
        for key in ("track", "station", "train"):
            times3(state["costs"][key])
        for step in tree["steps"]:
            command = step.get("command")
            if not command or command["type"] != "setFareRules":
                continue
            rules = command["rules"]
            if isinstance(rules.get("fare"), Num):
                times3(rules["fare"])
            for band in rules.get("bands", []):
                times3(band["fare"])
        path.write_text(splice(text, edits))


# --apply-log

def apply_log(log):
    lines = pathlib.Path(log).read_text().splitlines()
    by_file = {}
    step_re = re.compile(r"([\w.-]+\.json): steps\[(\d+)\]: expected (.*), got (.*)$")
    final_re = re.compile(r"([\w.-]+\.json): expectedFinalState differs\.")
    for i, line in enumerate(lines):
        m = step_re.search(line)
        if m:
            by_file.setdefault(m.group(1), []).append(("step", int(m.group(2)), json.loads(m.group(4))))
            continue
        m = final_re.search(line)
        if m:
            actual = next(l for l in lines[i + 1:i + 4] if l.strip().startswith("actual:"))
            by_file.setdefault(m.group(1), []).append(("final", None, json.loads(actual.split("actual:", 1)[1])))
    for name, items in sorted(by_file.items()):
        path = FIXTURES / name
        text = path.read_text()
        tree = parse(text)
        edits = []
        for kind, index, actual in items:
            node = tree["expectedFinalState"] if kind == "final" else tree["steps"][index]["expect"]
            where = "expectedFinalState" if kind == "final" else f"steps[{index}].expect"
            merge(node, actual, f"{name}: {where}", edits)
        path.write_text(splice(text, edits))


def merge(node, actual, where, edits):
    if isinstance(node, Num):
        if isinstance(actual, (int, float)) and not isinstance(actual, bool):
            if node.value != actual:
                edits.append((node.start, node.end, json.dumps(actual)))
            return
    elif isinstance(node, dict) and isinstance(actual, dict):
        if set(node) != set(actual):
            print(f"{where}: keys {sorted(set(node) ^ set(actual))} differ; left")
        for key in node.keys() & actual.keys():
            merge(node[key], actual[key], f"{where}.{key}", edits)
        return
    elif isinstance(node, list) and isinstance(actual, list):
        if len(node) != len(actual):
            print(f"{where}: {len(node)} items, GameCore gives {len(actual)}; left")
            return
        for i, (a, b) in enumerate(zip(node, actual)):
            merge(a, b, f"{where}[{i}]", edits)
        return
    if plain(node) != actual:
        print(f"{where}: {json.dumps(plain(node))} → {json.dumps(actual)}; left")


# --verify

def verify(base):
    problems, scaled, exceptions, rounding = [], 0, [], []
    for path in fixture_files():
        rel = path.relative_to(ROOT).as_posix()
        try:
            old_text = subprocess.run(["git", "-C", str(ROOT), "show", f"{base}:{rel}"],
                                      check=True, capture_output=True, text=True).stdout
        except subprocess.CalledProcessError:
            print(f"{path.name}: new at this commit, not compared")
            continue
        old, new = json.loads(old_text), json.loads(path.read_text())

        def walk(a, b, where, key):
            nonlocal scaled
            if isinstance(a, dict) and isinstance(b, dict):
                if set(a) != set(b):
                    problems.append(f"{path.name}: {where}: keys {sorted(set(a) ^ set(b))}")
                for k in a.keys() & b.keys():
                    walk(a[k], b[k], f"{where}.{k}", k)
            elif isinstance(a, list) and isinstance(b, list):
                if len(a) != len(b):
                    problems.append(f"{path.name}: {where}: {len(a)} items → {len(b)}")
                    return
                for i, (x, y) in enumerate(zip(a, b)):
                    walk(x, y, f"{where}[{i}]", key)
            elif a != b:
                if where == ".schemaVersion" and b == SCHEMA:
                    return
                if is_money(where, key) and isinstance(a, int) and b == 3 * a:
                    scaled += 1
                    return
                line = f"{path.name}: {where}: {a} → {b}"
                if is_money(where, key) and isinstance(a, int) and isinstance(b, int):
                    line += f" (3 × old = {3 * a}, off by {b - 3 * a})"
                reason = EXCEPTIONS.get((path.name, where))
                rounded = ROUNDED.get(path.name)
                if not reason and rounded and is_money(where, key) and isinstance(a, int) and isinstance(b, int) \
                        and abs(b - 3 * a) <= rounded[0]:
                    rounding.append(f"{line}: {rounded[1]}")
                    return
                if reason:
                    exceptions.append(f"{line}: {reason}")
                else:
                    problems.append(line)
            elif is_money(where, key) and isinstance(a, int) and a != 0:
                problems.append(f"{path.name}: {where}: {a} unchanged")

        walk(old, new, "", None)
    print(f"{scaled} amounts are three times the old one")
    print(f"{len(rounding)} amounts are within a fixture's rounding of three times the old one (ROUNDED)")
    for line in exceptions:
        print(f"exception: {line}")
    for line in problems:
        print(f"PROBLEM: {line}")
    return 1 if problems else 0


def main(argv):
    if argv[:1] == ["--rewrite-inputs"]:
        rewrite_inputs()
        return 0
    if argv[:1] == ["--apply-log"] and len(argv) == 2:
        apply_log(argv[1])
        return 0
    if argv[:1] == ["--verify"]:
        return verify(argv[1] if len(argv) > 1 else "origin/main")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
