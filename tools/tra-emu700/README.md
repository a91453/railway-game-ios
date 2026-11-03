# EMU700 study

Swift 6.4 only. `tools/tra-emu700/build.sh /absolute/output` exports independent
EMC, EP, ET, EM near/far, then generic eight-car assembly, GLB and geometry audit.
`assembly.json` is the sole placement definition. No operating mapping is changed.

Use shared render/inspect/delivery tools. Source and incomplete validation state:
`docs/art/tra-emu700/README.md`. A successful build is not appearance acceptance.

`inventory.sh OUT [CLEAN_CHECKOUT]` generates a temporary exporter from the
shared implementation, replacing only its default train subset with actual
standard+studies enumeration. It refuses an unrecognised implementation,
leaves the shared tool unchanged, and writes full ten-field FNV/native bytes
plus real pack membership and vertex-array byte counts. Run on unmodified
main and the producer, then `protect.py BASE FINAL REPORT`; do not install its
full lock or pass a guessed `--all` flag.

Cab revision after the explicit rejection of producer 553b3a22:

```sh
tools/tra-emu700/build.sh OUT
node tools/tra-emu700/render.mjs OUT
node tools/tra-emu700/render-mouth.mjs OUT BEFORE_RUN
python3 tools/tra-emu700/sheets.py OUT
node tools/tra-emu700/mouth.mjs OUT
```

BEFORE_RUN must contain the actual rejected 553b3a22 EMC near/far native
payloads. `mouth-comparison.json` fixes their SHA and the metre camera/light.
The colour bowl is a curved shell row, with a continuous ordinary-service
FRP apron and an underside drawgear cavity; the previous frontal square
opening is not an accepted normal-state reference. Only the EMC geometry
and its two placements per complete formation change. The six middle-role
near/far units must remain byte-identical to the previous producer.
