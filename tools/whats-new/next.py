#!/usr/bin/env python3
"""The next build's news (decision 415, WHATSNEW-NEXT-FILES).

Prints the lines waiting in Sources/GamePresentation/WhatsNewNext/ as
Swift `Line(english:chinese:)` for the new entry at the top of
`WhatsNew.entries`; `--clear` deletes those files once they are moved.

    python3 -I tools/whats-new/next.py           # print
    python3 -I tools/whats-new/next.py --clear   # delete the moved files
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FOLDER = ROOT / "Sources" / "GamePresentation" / "WhatsNewNext"


def lines(kind):
    out = []
    for path in sorted((FOLDER / kind).glob("*.txt")):
        text = path.read_text(encoding="utf-8").splitlines()
        if len(text) != 2 or not text[0].startswith("en: ") or not text[1].startswith("zh: "):
            sys.exit(f"{path}: needs two lines, 'en: ...' then 'zh: ...'")
        out.append((path, text[0][4:], text[1][4:]))
    return out


def main():
    news = {kind: lines(kind) for kind in ("new", "fixed")}
    if sys.argv[1:] == ["--clear"]:
        for kind in news.values():
            for path, _, _ in kind:
                path.unlink()
                print(f"deleted {path.relative_to(ROOT)}")
        return
    if sys.argv[1:]:
        sys.exit(__doc__)
    for kind, label in (("new", "items"), ("fixed", "fixes")):
        print(f"{label}: [")
        for _, english, chinese in news[kind]:
            print("    Line(")
            print(f"        english: {json.dumps(english, ensure_ascii=False)},")
            print(f"        chinese: {json.dumps(chinese, ensure_ascii=False)}")
            print("    ),")
        print("],")


if __name__ == "__main__":
    main()
