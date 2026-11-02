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
