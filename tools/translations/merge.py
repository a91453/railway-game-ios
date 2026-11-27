#!/usr/bin/env python3
"""Adds a translator's answers to the game (decision 1034).

    python3 -I tools/translations/merge.py ja IDS.json ANSWER.txt [ANSWER.txt ...]

IDS.json is the one batches.py wrote beside the batches; each ANSWER is what
the translator sent back for a batch, as pasted: the ```json block of
`"id": "sentence"` lines, with or without the text around it. The answers go
to:
- `g…` → Sources/GamePresentation/Translations/<Language>.swift;
- `c…` → the language's localizations in RailwayGameApp/Resources/Localizable.xcstrings;
- `p…` → RailwayGameApp/Resources/<code>.lproj/InfoPlist.strings.

An answer is refused, and listed, when its `{n}` names an interpolation the
English lacks or drops one that is not an English-only plural, or when a
catalog answer's `%@`/`%lld` do not match the English. Run batches.py again
afterwards: it lists only what is still missing.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import batches  # noqa: E402
import extract  # noqa: E402
import table  # noqa: E402

ROOT = extract.ROOT
PLACEHOLDER = re.compile(r"\{(\d+)\}")
FORMAT = re.compile(r"%(?:(\d+)\$)?(?:ll|l)?[@dfsu]")
PAIR = re.compile(r'"([gcp]\d{4})"\s*:\s*"((?:[^"\\]|\\.)*)"')


def answers_in(text):
    found = {}
    for m in PAIR.finditer(text):
        found[m.group(1)] = json.loads('"' + m.group(2) + '"')
    return found


def droppable(arg):
    """Whether an interpolation is only English grammar (a plural ending, an
    article), which Japanese may leave out."""
    return bool(re.fullmatch(r'.*\?\s*"[A-Za-z ]*"\s*:\s*"[A-Za-z ]*"', arg)) or arg.strip() in ('"a"', '"an"')


def check_game(key, args, sentence):
    wanted = set(range(len(PLACEHOLDER.findall(key))))
    used = {int(n) for n in PLACEHOLDER.findall(sentence)}
    if used - wanted:
        return "names {%s}, which the English has not" % ",".join(map(str, sorted(used - wanted)))
    missing = [n for n in wanted - used if not (n < len(args) and droppable(args[n]))]
    if missing:
        return "leaves out {%s}" % ",".join(map(str, missing))
    return None


def check_catalog(english, sentence):
    a = [m.group(0) for m in FORMAT.finditer(english)]
    b = [m.group(0) for m in FORMAT.finditer(sentence)]
    strip = lambda s: re.sub(r"%\d+\$", "%", s)
    if sorted(map(strip, a)) != sorted(map(strip, b)):
        return f"format {a} became {b}"
    return None


def write_catalog(code, rows):
    data = json.load(open(batches.CATALOG, encoding="utf-8"))
    for key, sentence in rows.items():
        entry = data["strings"].setdefault(key, {})
        entry.setdefault("localizations", {})[code] = {"stringUnit": {"state": "translated", "value": sentence}}
    with open(batches.CATALOG, "w", encoding="utf-8") as f:
        # Xcode's own layout of a String Catalog.
        f.write(json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")


def write_plist(code, rows):
    path = batches.PLIST.format(code)
    english = open(batches.PLIST.format("en"), encoding="utf-8").read()
    have = batches.read_plist(code)
    have.update(rows)
    out = []
    # Keep the English file's order and comments.
    for block in re.split(r"\n(?=/\*)", english.strip()):
        m = batches.PLIST_LINE.search(block)
        if not m or m.group(1) not in have:
            continue
        comment = block[:m.start()].rstrip()
        value = have[m.group(1)].replace('"', '\\"').replace("\n", "\\n")
        out.append(f'{comment}\n"{m.group(1)}" = "{value}";')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    code, ids_path, answer_paths = argv[1], argv[2], argv[3:]
    ids = json.load(open(ids_path, encoding="utf-8"))
    answers = {}
    for path in answer_paths:
        answers.update(answers_in(open(path, encoding="utf-8").read()))
    args_of = {r["key"]: r["args"] for r in extract.unique(extract.all_calls())}
    english_of = {r["key"]: r["en"] for r in batches.catalog_rows(code)}
    game, catalog, plist, refused, gone = {}, {}, {}, [], []
    for ident, sentence in sorted(answers.items()):
        if ident not in ids:
            refused.append((ident, "not in ids.json"))
            continue
        kind, key = ids[ident]["kind"], ids[ident]["key"]
        if key == key.strip():
            sentence = sentence.strip()
        if kind == "g":
            if key not in args_of:
                gone.append(ident)
                continue
            problem = check_game(key, args_of[key], sentence)
            (refused.append((ident, problem)) if problem else game.__setitem__(key, sentence))
        elif kind == "c":
            problem = check_catalog(english_of.get(key, key), sentence)
            (refused.append((ident, problem)) if problem else catalog.__setitem__(key, sentence))
        else:
            plist[key] = sentence
    path = table.path_of(ROOT, code)
    rows = table.read(path)
    rows.update(game)
    table.write(path, rows, code)
    if catalog:
        write_catalog(code, catalog)
    if plist:
        write_plist(code, plist)
    missing = sorted(set(ids) - set(answers))
    print(f"{len(game)} game sentences, {len(catalog)} catalog, {len(plist)} InfoPlist added; "
          f"{len(refused)} refused, {len(gone)} no longer in the game, {len(missing)} not answered")
    for ident, why in refused:
        print(f"  refused {ident}: {why}")
    if missing:
        print("  not answered: " + " ".join(missing[:50]) + (" …" if len(missing) > 50 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
