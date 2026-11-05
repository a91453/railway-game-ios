# Stack frames (decision 590)

A function reserves its whole stack frame as it is entered, whichever way it
goes. TestFlight 112.1 ran out of the main thread's stack on a chain of a few
functions whose frames were tens of kilobytes each (decision 590). This tool
reads those frames from a disassembly, so that a new large one is seen when
it comes in.

- `frames.py list FILE...` prints `bytes<TAB>symbol` for each function, largest
  first.
- `frames.py report --title T [--baseline B] [--min 32768] [--top 20] FILE...`
  writes Markdown for a job summary: the frames over `--min` whose symbol is
  not in the baseline, and the `--top` largest.
- `frames.py baseline FILE...` writes the frames over `--min`, for
  `baseline-linux-x86_64.txt`.

It runs `objdump -d` on Linux (`sub $N,%rsp` in the prologue) and `otool -tV`
on macOS (`sub sp, sp, #N`, and `___chkstk_darwin` with the size over 16 in
`x15` for a frame past a page). Symbols are compared mangled and shown
demangled.

Where it runs:

- `ci.yml`, job `stack-frames`: a pull request that changes GameCore or
  GamePresentation builds them with `-c release` and lists the new frames over
  32 KB and the 20 largest in its summary. A reminder only: the gate does not
  wait for it.
- `ios-build.yml`, the build job: the app's 20 largest frames (Debug,
  Simulator) in its summary.

Read the objects of one source file each (`.build/out/Intermediates.noindex/*/Release-linux-x86_64/GamePresentation-t.build/Objects-normal/x86_64/*.o`),
not the module's whole `GamePresentation.o`: objdump took over ten minutes on
the 170 MB object and about five seconds on the 668 small ones.

When a large frame is meant to stay (or one in the baseline is gone), write
the baseline again from an optimised build:

```sh
swift build -c release --target GamePresentation
python3 -I tools/stack-frames/frames.py baseline $(find .build -path '*Release*' \( -path '*/GameCore-t.build/*' -o -path '*/GamePresentation-t.build/*' \) -name '*.o') \
  > tools/stack-frames/baseline-linux-x86_64.txt
```

Tests: `python3 -I -m unittest discover -s tools/stack-frames -p 'test_*.py'`.
