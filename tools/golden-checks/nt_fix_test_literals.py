#!/usr/bin/env python3
# Temporary helper of decision 499 (NT$ PR-1); delete before the pull request is ready.
"""Patch test literals from XCTAssertEqual failures where actual == 3 * expected.

usage: nt_fix_test_literals.py FAILS_FILE [--apply] [--only File.swift ...]
Each line of FAILS_FILE: Tests/<path>:<line>: error: ... XCTAssertEqual failed: ("A") is not equal to ("B")
"""
import re, sys, collections, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2] / 'Tests'
NUM = re.compile(r'(?<![\w.])-?\d[\d_]*(?![\w.])')


def nums(s):
    return [int(x) for x in re.findall(r'-?\d+', s)]


def fmt(v, like):
    neg = v < 0
    s = str(abs(v))
    if abs(v) >= 1_000:
        groups = []
        while len(s) > 3:
            groups.insert(0, s[-3:])
            s = s[:-3]
        groups.insert(0, s)
        s = '_'.join(groups)
    return ('-' if neg else '') + s


def main():
    args = sys.argv[1:]
    apply = '--apply' in args
    only = set()
    if '--only' in args:
        only = set(args[args.index('--only') + 1:])
    fails = pathlib.Path(args[0]).read_text().splitlines()
    pat = re.compile(r'^(\S+?\.swift):(\d+): error: (\S+) : XCTAssertEqual failed: \("(.*)"\) is not equal to \("(.*)"\)')
    per_line = collections.defaultdict(list)
    unhandled = []
    for f in fails:
        m = pat.match(f)
        if not m:
            unhandled.append(f[:300])
            continue
        path, line = m.group(1), int(m.group(2))
        if only and pathlib.Path(path).name not in only:
            continue
        a, b = nums(m.group(4)), nums(m.group(5))
        if len(a) != len(b):
            unhandled.append(f'{path}:{line}: count differs: {f[-250:]}')
            continue
        mapping = {}
        bad = False
        for x, y in zip(a, b):
            if x == y:
                continue
            if x == 3 * y:
                if mapping.get(y, x) != x:
                    bad = True
                mapping[y] = x
            else:
                bad = True
        if bad:
            unhandled.append(f'{path}:{line}: not 3x: A={a[:12]} B={b[:12]}')
            continue
        per_line[(path, line)].append(mapping)
    edits = collections.defaultdict(dict)
    for (path, line), maps in per_line.items():
        merged = {}
        conflict = False
        for mp in maps:
            for k, v in mp.items():
                if merged.get(k, v) != v:
                    conflict = True
                merged[k] = v
        if conflict:
            unhandled.append(f'{path}:{line}: conflicting values across runs')
            continue
        edits[path][line] = merged
    for path, lines in edits.items():
        p = ROOT / path.split('Tests/', 1)[-1] if not path.startswith('/') else pathlib.Path(path)
        p = ROOT / path if (ROOT / path).exists() else p
        text = p.read_text().split('\n')
        for line, mapping in sorted(lines.items()):
            # the statement: from line until parentheses balance
            i = line - 1
            depth = 0
            end = i
            started = False
            for j in range(i, min(i + 40, len(text))):
                for ch in text[j]:
                    if ch == '(':
                        depth += 1; started = True
                    elif ch == ')':
                        depth -= 1
                end = j
                if started and depth <= 0:
                    break
            changed = set()
            for j in range(i, end + 1):
                src = text[j]
                def rep(m):
                    v = int(m.group().replace('_', ''))
                    if v in mapping:
                        changed.add(v)
                        return fmt(mapping[v], m.group())
                    return m.group()
                # skip string literals and comments: only replace outside quotes
                parts = re.split(r'("(?:[^"\\]|\\.)*"|//.*$)', src)
                parts = [pt if (pt.startswith('"') or pt.startswith('//')) else NUM.sub(rep, pt) for pt in parts]
                new = ''.join(parts)
                if new != src:
                    print(f'{path}:{j+1}:\n  - {src.strip()}\n  + {new.strip()}')
                    text[j] = new
            missing = set(mapping) - changed
            if missing:
                unhandled.append(f'{path}:{line}: literals not found for {sorted(missing)} (computed?)')
        if apply:
            p.write_text('\n'.join(text))
    print('\n# UNHANDLED')
    for u in unhandled:
        print(u)


main()
