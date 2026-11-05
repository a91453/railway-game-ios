#!/usr/bin/env python3
"""The stack frame each function reserves on entry (decision 590).

A function takes its whole stack frame as it is entered, whichever way it
goes; the 112.1 crash was a chain of a few functions with frames of tens of
kilobytes each. This reads the frames from a disassembly:

- x86_64 (Linux, `objdump -d`): `sub $N,%rsp` in the prologue;
- arm64 (Apple, `otool -tV`): `sub sp, sp, #N` (`lsl #12` for the high
  part), and a frame past a page asks `___chkstk_darwin` first, with the
  size over 16 in x15 (`mov`/`movk x15`).

Commands:

  frames.py list FILE...            disassemble (objdump on Linux, otool on
                                    macOS) and print "bytes<TAB>symbol"
  frames.py report --title T [--baseline B] [--min BYTES] [--top N] FILE...
                                    a Markdown report for a job summary: the
                                    N largest frames, and the frames over
                                    BYTES whose symbol is not in B (new ones)
  frames.py baseline [--min BYTES] FILE...
                                    the frames over BYTES, for a baseline

`--disassembly` reads a disassembly saved as text instead of running the
disassembler (for the tests). Symbols are compared mangled and shown
demangled (`swift demangle`, or `xcrun swift-demangle` on macOS).
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# How many instructions of a function's start are read for its prologue.
PROLOGUE = 40

X86_FUNCTION = re.compile(r"^[0-9a-f]+ <(?P<name>[^>]+)>:$")
X86_SUB_RSP = re.compile(r"\bsub[q]?\s+\$0x(?P<n>[0-9a-f]+),%rsp\b")
X86_CALL = re.compile(r"\bcall[q]?\b")

ARM_FUNCTION = re.compile(r"^(?P<name>[^\s:][^\s]*):$")
ARM_INSTRUCTION = re.compile(r"^[0-9a-f]+\s+(?P<op>\S+)\s*(?P<args>.*)$")
ARM_SUB_SP = re.compile(r"^sp,\s*sp,\s*#(?P<n>0x[0-9a-f]+|\d+)(?:,\s*lsl\s*#(?P<shift>\d+))?$")
ARM_X15 = re.compile(r"^x15,\s*#(?P<n>0x[0-9a-f]+|\d+)(?:,\s*lsl\s*#(?P<shift>\d+))?$")


def number(text):
    return int(text, 16) if text.startswith("0x") else int(text)


def x86_frames(lines):
    """`objdump -d` of x86_64 code: {symbol: bytes}."""
    frames, name, seen = {}, None, 0
    for line in lines:
        line = line.rstrip("\n")
        match = X86_FUNCTION.match(line)
        if match:
            name, seen = match.group("name"), 0
            continue
        if name is None or ":" not in line:
            continue
        seen += 1
        if seen > PROLOGUE or X86_CALL.search(line):
            name = None
            continue
        sub = X86_SUB_RSP.search(line)
        if sub:
            frames[name] = frames.get(name, 0) + int(sub.group("n"), 16)
    return frames


def arm_frames(lines):
    """`otool -tV` of arm64 code: {symbol: bytes}."""
    frames, name, seen, x15 = {}, None, 0, 0
    for line in lines:
        line = line.rstrip("\n")
        match = ARM_FUNCTION.match(line)
        if match:
            name, seen, x15 = match.group("name"), 0, 0
            continue
        instruction = ARM_INSTRUCTION.match(line)
        if name is None or not instruction:
            continue
        seen += 1
        op, args = instruction.group("op"), instruction.group("args").strip()
        if seen > PROLOGUE:
            name = None
            continue
        if op in ("mov", "movz", "movk"):
            value = ARM_X15.match(args)
            if value:
                part = number(value.group("n")) << int(value.group("shift") or 0)
                x15 = part if op != "movk" else x15 | part
            continue
        if op == "bl":
            if "chkstk_darwin" in args:
                # `sub sp, sp, x15, lsl #4` follows: x15 is the size over 16.
                frames[name] = frames.get(name, 0) + x15 * 16
                continue
            name = None
            continue
        if op == "sub":
            sub = ARM_SUB_SP.match(args)
            if sub:
                frames[name] = frames.get(name, 0) + (number(sub.group("n")) << int(sub.group("shift") or 0))
    return frames


def disassemble(path):
    """The disassembly of `path` and whether it is arm64 (`otool`)."""
    if sys.platform == "darwin" or (shutil.which("otool") and not shutil.which("objdump")):
        text = subprocess.run(["otool", "-tV", path], check=True, capture_output=True, text=True).stdout
        return text.splitlines(), True
    text = subprocess.run(["objdump", "-d", "--no-show-raw-insn", path], check=True, capture_output=True, text=True).stdout
    return text.splitlines(), False


def read_frames(paths, disassembly=None):
    frames = {}
    if disassembly:
        with open(disassembly, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
        arm = any(ARM_INSTRUCTION.match(line) and "sp, sp" in line for line in lines)
        frames.update(arm_frames(lines) if arm else x86_frames(lines))
        return frames
    def one(path):
        lines, arm = disassemble(path)
        return arm_frames(lines) if arm else x86_frames(lines)

    # One object at a time per core: a whole module's object (170 MB) took
    # objdump over ten minutes, its 545 objects of one file each a second
    # apiece.
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as pool:
        for found in pool.map(one, paths):
            for symbol, size in found.items():
                frames[symbol] = max(size, frames.get(symbol, 0))
    return frames


def demangled(symbols):
    """{mangled: readable}, as far as a demangler is found."""
    symbols = list(symbols)
    if not symbols:
        return {}
    for command in (["swift", "demangle", "--simplified"], ["xcrun", "swift-demangle", "--simplified"]):
        if not shutil.which(command[0]):
            continue
        try:
            out = subprocess.run(command, input="\n".join(symbols) + "\n", check=True, capture_output=True, text=True).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        names = out.splitlines()
        if len(names) == len(symbols):
            return dict(zip(symbols, names))
    return {symbol: symbol for symbol in symbols}


def read_baseline(path):
    if not path:
        return set()
    with open(path, encoding="utf-8") as handle:
        return {line.split("\t")[-1].strip() for line in handle if line.strip() and not line.startswith("#")}


def kilobytes(size):
    return f"{size / 1024:.1f} KB"


def cell(text, limit=160):
    text = text.replace("|", "\\|")
    return text if len(text) <= limit else text[: limit - 1] + "…"


def report(frames, title, baseline, minimum, top):
    largest = sorted(frames.items(), key=lambda item: (-item[1], item[0]))[:top]
    # No baseline (the app's list in ios-build.yml): nothing is "new".
    new = [] if baseline is None else sorted(((s, n) for s, n in frames.items() if n > minimum and s not in baseline), key=lambda item: (-item[1], item[0]))
    names = demangled({s for s, _ in largest} | {s for s, _ in new})
    lines = [f"### {title}", ""]
    if baseline is not None:
        if new:
            lines.append(f"**{len(new)} frame(s) over {kilobytes(minimum)} not in the baseline** (a reminder, not a failure; decision 590):")
            lines += ["", "| Frame | Function |", "| --: | --- |"]
            lines += [f"| {kilobytes(n)} | `{cell(names[s])}` |" for s, n in new]
        else:
            lines.append(f"No new frame over {kilobytes(minimum)}.")
        lines.append("")
    lines.append(f"The {len(largest)} largest frames:")
    lines += ["", "| Frame | Function |", "| --: | --- |"]
    lines += [f"| {kilobytes(n)} | `{cell(names[s])}` |" for s, n in largest]
    return "\n".join(lines) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["list", "report", "baseline"])
    parser.add_argument("files", nargs="*")
    parser.add_argument("--disassembly")
    parser.add_argument("--title", default="Stack frames")
    parser.add_argument("--baseline")
    parser.add_argument("--min", type=int, default=32 * 1024)
    parser.add_argument("--top", type=int, default=20)
    # Intermixed: the files may follow the options (the workflows give
    # them last), and plain parse_args stops at the first option after
    # the command on Python 3.12, CI's (exit 2, "unrecognized arguments").
    args = parser.parse_intermixed_args(argv)
    frames = read_frames(args.files, args.disassembly)
    if args.command == "list":
        for symbol, size in sorted(frames.items(), key=lambda item: (-item[1], item[0])):
            print(f"{size}\t{symbol}")
    elif args.command == "baseline":
        print(f"# Frames over {args.min} bytes (tools/stack-frames/frames.py baseline); a frame here is not reported as new.")
        for symbol, size in sorted(frames.items(), key=lambda item: (-item[1], item[0])):
            if size > args.min:
                print(f"{size}\t{symbol}")
    else:
        baseline = read_baseline(args.baseline) if args.baseline else None
        sys.stdout.write(report(frames, args.title, baseline, args.min, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
