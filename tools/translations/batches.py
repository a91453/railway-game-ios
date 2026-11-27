#!/usr/bin/env python3
"""Cuts the sentences a language's table still lacks into batches a
translator (a person, or an AI chat that cannot read the repository) can be
handed one at a time, and records which id is which sentence (decision 1034).

    python3 -I tools/translations/batches.py ja OUT_DIR [--size 22000]

OUT_DIR gets `PROMPT.md` (the rules, said once), `batch-01.md`, ... (each
self-contained: a short reminder, then one JSON object per line) and
`ids.json` (id → what it translates), which merge.py reads with the answers.

Three kinds of text are listed:
- `g…`: the game's sentences, `DisplayLanguage.text(english, chinese)`, keyed
  by the English with `{0}`, `{1}`, ... for its interpolations;
- `c…`: the app's String Catalog (RailwayGameApp/Resources/Localizable.xcstrings),
  whose `%@`, `%lld` and `%1$@` must stay;
- `p…`: InfoPlist.strings (the Home Screen name, the permission prompts).
Sentences of one source file stay together, so a batch is one screen's words.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import extract  # noqa: E402
import table  # noqa: E402

ROOT = extract.ROOT
CATALOG = os.path.join(ROOT, "RailwayGameApp/Resources/Localizable.xcstrings")
PLIST = os.path.join(ROOT, "RailwayGameApp/Resources/{}.lproj/InfoPlist.strings")
PLIST_LINE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.M)

RULES = os.path.join(HERE, "PROMPT-ja.md")


def read_plist(code):
    path = PLIST.format(code)
    if not os.path.exists(path):
        return {}
    text = open(path, encoding="utf-8").read()
    return {k: v.replace('\\"', '"').replace("\\n", "\n") for k, v in PLIST_LINE.findall(text)}


def catalog_rows(code):
    data = json.load(open(CATALOG, encoding="utf-8"))
    rows = []
    for key, entry in data["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        if code in locs:
            continue
        zh = locs.get("zh-Hant", {}).get("stringUnit", {}).get("value", "")
        en = locs.get("en", {}).get("stringUnit", {}).get("value", key)
        rows.append({"kind": "c", "key": key, "en": en, "zh": zh, "note": entry.get("comment", ""), "at": "app"})
    return rows


def plist_rows(code):
    en, zh, have = read_plist("en"), read_plist("zh-Hant"), read_plist(code)
    return [{"kind": "p", "key": k, "en": v, "zh": zh.get(k, ""), "at": "InfoPlist"}
            for k, v in en.items() if k not in have]


def game_rows(code):
    have = table.read(table.path_of(ROOT, code))
    rows = []
    for r in extract.unique(extract.all_calls()):
        if r["key"] in have:
            continue
        row = {"kind": "g", "key": r["key"], "en": r["key"], "zh": r["chinese"],
               "at": os.path.basename(r["file"]).removesuffix(".swift")}
        if r["args"]:
            row["args"] = {str(n): a for n, a in enumerate(r["args"])}
        rows.append(row)
    return rows


def line_of(row, ident):
    out = {"id": ident, "en": row["en"], "zh": row["zh"]}
    if row.get("args"):
        out["args"] = row["args"]
    if row.get("note"):
        out["note"] = row["note"]
    out["at"] = row["at"]
    return json.dumps(out, ensure_ascii=False)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    code, out_dir = argv[1], argv[2]
    size = int(argv[argv.index("--size") + 1]) if "--size" in argv else 22000
    os.makedirs(out_dir, exist_ok=True)
    rows = plist_rows(code) + catalog_rows(code) + game_rows(code)
    ids, batches, current, used = {}, [], [], 0
    counters = {"g": 0, "c": 0, "p": 0}
    last_at = None
    for row in rows:
        counters[row["kind"]] += 1
        ident = "%s%04d" % (row["kind"], counters[row["kind"]])
        ids[ident] = {"kind": row["kind"], "key": row["key"]}
        line = line_of(row, ident)
        # Start a new batch at a file boundary once this one is full, or
        # anywhere once it is far over.
        if current and ((used > size and row["at"] != last_at) or used > size * 1.5):
            batches.append(current)
            current, used = [], 0
        current.append(line)
        used += len(line)
        last_at = row["at"]
    if current:
        batches.append(current)
    rules = open(RULES, encoding="utf-8").read()
    with open(os.path.join(out_dir, "PROMPT.md"), "w", encoding="utf-8") as f:
        f.write(rules)
    total = len(batches)
    for n, lines in enumerate(batches, 1):
        with open(os.path.join(out_dir, "batch-%02d.md" % n), "w", encoding="utf-8") as f:
            f.write(f"第 {n}／{total} 批，共 {len(lines)} 句。照最前面給你的翻譯規則（PROMPT）翻成日文；"
                    "只回一個 ```json 程式碼區塊，每行一個 \"id\": \"日文\"，包成一個 JSON 物件，id 一個都不能少。\n\n")
            f.write("```jsonl\n" + "\n".join(lines) + "\n```\n")
    with open(os.path.join(out_dir, "ids.json"), "w", encoding="utf-8") as f:
        json.dump(ids, f, ensure_ascii=False, indent=0)
    print(f"{len(rows)} sentences in {total} batches → {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
