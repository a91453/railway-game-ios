#!/usr/bin/env python3
"""Lists every sentence the game writes with `DisplayLanguage.text(english,
chinese)` (decision 1034), keyed the way the game looks up the other
languages (Japanese first, `TranslationTable`):
the English literal with each `\\(...)` replaced by `{0}`, `{1}`, ... in order
(`DisplayTextTemplate` in Sources/GamePresentation/DisplayLanguage.swift
builds the same key at run time).

    python3 -I tools/translations/extract.py strings.json      # every sentence
    python3 -I tools/translations/extract.py --coverage ja     # how many have Japanese

`strings.json` is a list of {key, english, chinese, args, file, line}: `args`
names what each `{n}` stands for (the source of the interpolation), so a
translator knows that `{0}` is a station name or an amount of money.

Only calls whose English is a string literal are listed: a call that passes a
variable (a place's name, a sentence built elsewhere) is looked up by the
finished English text, and its words come from data, not from this list.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCES = ["Sources/GamePresentation", "RailwayGameApp/App", "RailwayGameApp/Views", "RailwayGameApp/MapPackDownloader"]

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


class ParseError(Exception):
    pass


def skip_space(src, i):
    while i < len(src):
        if src[i].isspace():
            i += 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            i = len(src) if j < 0 else j + 1
        elif src.startswith("/*", i):
            j = src.find("*/", i)
            i = len(src) if j < 0 else j + 2
        else:
            break
    return i


def skip_balanced(src, i, close):
    """From just after an opening bracket, returns the index just after its
    matching `close`, skipping nested brackets, strings and comments."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = [close]
    while i < len(src):
        c = src[i]
        if c == '"' or (c == "#" and re.match(r'#+"', src[i:])):
            _, i = parse_literal(src, i)
            continue
        if src.startswith("//", i) or src.startswith("/*", i):
            i = skip_space(src, i)
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif c == stack[-1]:
            stack.pop()
            if not stack:
                return i + 1
        i += 1
    raise ParseError("unbalanced")


def parse_literal(src, i):
    """Parses the string literal at `i`. Returns ((segments, args), end):
    segments are the literal pieces between interpolations (one more than
    args), args the interpolations' source text."""
    hashes = 0
    while src[i] == "#":
        hashes += 1
        i += 1
    multiline = src.startswith('"""', i)
    i += 3 if multiline else 1
    closer = ('"""' if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    segments, args, cur = [], [], []
    raw_lines_start = i
    while True:
        if i >= len(src):
            raise ParseError("unterminated string")
        if src.startswith(closer, i):
            end = i + len(closer)
            break
        if src.startswith(escape, i):
            j = i + len(escape)
            c = src[j]
            if c == "(":
                close = skip_balanced(src, j + 1, ")")
                segments.append("".join(cur))
                cur = []
                args.append(" ".join(src[j + 1:close - 1].split()))
                i = close
                continue
            if c == "u" and src[j + 1] == "{":
                k = src.index("}", j)
                cur.append(chr(int(src[j + 2:k], 16)))
                i = k + 1
                continue
            if multiline and c == "\n":
                cur.append("\x00CONT")
                i = j + 1
                continue
            if c in ESCAPES:
                cur.append(ESCAPES[c])
                i = j + 1
                continue
            raise ParseError("unknown escape \\" + c)
        if not multiline and src[i] == "\n":
            raise ParseError("newline in string")
        cur.append(src[i])
        i += 1
    segments.append("".join(cur))
    if multiline:
        segments = strip_multiline(segments, src, raw_lines_start, end - len(closer))
    return (segments, args), end


def strip_multiline(segments, src, start, close):
    """Applies a multi-line literal's rules: drop the first line break, strip
    the closing delimiter's indentation from every line, drop the last line
    break, and join lines continued with a backslash."""
    line_start = src.rfind("\n", 0, close) + 1
    indent = src[line_start:close]
    joined = "\x01".join(segments)
    if joined.startswith("\n"):
        joined = joined[1:]
    lines = joined.split("\n")
    lines = [l[len(indent):] if l.startswith(indent) else l.lstrip(" \t") if l.strip() == "" else l for l in lines]
    text = "\n".join(lines)
    if text.endswith("\n"):
        text = text[:-1]
    text = re.sub(r"[ \t]*\x00CONT\n", "", text)
    return text.split("\x01")


def parse_argument(src, i):
    """Parses one argument expression at `i`: a literal (possibly joined with
    `+` to other literals) or anything else. Returns (literal or None, source,
    end)."""
    start = i
    pieces = None
    if src[i] == '"' or re.match(r'#+"', src[i:]):
        (segments, args), j = parse_literal(src, i)
        pieces = (segments, args)
        k = skip_space(src, j)
        if src[k] in ",)":
            return pieces, src[start:j], j
        i = j
    # Not a lone literal: skip to the comma or parenthesis that ends it.
    depth_pairs = {"(": ")", "[": "]", "{": "}"}
    while i < len(src):
        c = src[i]
        if c == '"' or (c == "#" and re.match(r'#+"', src[i:])):
            _, i = parse_literal(src, i)
            continue
        if c in depth_pairs:
            i = skip_balanced(src, i + 1, depth_pairs[c])
            continue
        if c in ",)":
            break
        i += 1
    return None, " ".join(src[start:i].split()), i


def key_of(segments):
    out = []
    for n, seg in enumerate(segments):
        out.append(seg)
        if n < len(segments) - 1:
            out.append("{%d}" % n)
    return "".join(out)


def render(segments, args):
    out = []
    for n, seg in enumerate(segments):
        out.append(seg)
        if n < len(args):
            out.append("\\(" + args[n] + ")")
    return "".join(out)


CALL = re.compile(r"\.text\(")


def calls(path):
    src = open(path, encoding="utf-8").read()
    for m in CALL.finditer(src):
        i = skip_space(src, m.end())
        if not (src[i] == '"' or re.match(r'#+"', src[i:])):
            continue
        line = src.count("\n", 0, m.start()) + 1
        try:
            english, _, j = parse_argument(src, i)
            if english is None:
                continue
            j = skip_space(src, j)
            if src[j] != ",":
                continue
            k = skip_space(src, j + 1)
            if src.startswith("in:", k) or re.match(r"[A-Za-z_]+:", src[k:]):
                continue
            chinese, chinese_src, end = parse_argument(src, k)
            if src[skip_space(src, end)] != ")":
                continue
        except (ParseError, IndexError, ValueError) as error:
            print(f"{path}:{line}: skipped ({error})", file=sys.stderr)
            continue
        segments, args = english
        yield {
            "key": key_of(segments),
            "english": render(segments, args),
            "chinese": render(*chinese) if chinese else chinese_src,
            "args": args,
            "file": os.path.relpath(path, ROOT),
            "line": line,
        }


def all_calls():
    found = []
    for folder in SOURCES:
        base = os.path.join(ROOT, folder)
        for dirpath, _, files in os.walk(base):
            for name in sorted(files):
                if name.endswith(".swift"):
                    found.extend(calls(os.path.join(dirpath, name)))
    found.sort(key=lambda c: (c["file"], c["line"]))
    return found


def unique(found):
    seen = {}
    for c in found:
        if c["key"] not in seen:
            seen[c["key"]] = dict(c, uses=1)
        else:
            seen[c["key"]]["uses"] += 1
    return list(seen.values())


def table_keys(language):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import table  # noqa: E402
    return table.read(table.path_of(ROOT, language))


def main(argv):
    found = all_calls()
    rows = unique(found)
    if argv[1:2] == ["--coverage"]:
        have = table_keys(argv[2] if len(argv) > 2 else "ja")
        done = sum(1 for r in rows if r["key"] in have)
        print(f"{len(found)} calls, {len(rows)} different sentences, {done} with Japanese, {len(rows) - done} fall back to English")
        return 0
    if len(argv) != 2:
        print(__doc__)
        return 2
    with open(argv[1], "w", encoding="utf-8") as out:
        json.dump(rows, out, ensure_ascii=False, indent=1)
    print(f"{len(found)} calls, {len(rows)} different sentences → {argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
