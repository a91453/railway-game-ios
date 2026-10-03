# Save Fixtures

Committed saves that every later build must still load (Stage C4,
ARCHITECTURE decision 45). Each file is GameCore's `SavedGame` in JSON:
`{"saveVersion": n, "world": {...}}`, written by the build that introduced
version `n`. `Tests/GameCoreTests/SavedGameTests.swift` loads every file here,
round-trips it and runs it on.

Rules, as for the golden scenarios:

- Never edit or regenerate a file here to make a test pass. A save that no
  longer loads means old saves on players' devices no longer load.
- When a change to the world's format cannot read older saves as they are,
  raise `SavedGame.currentVersion`, add the step that turns the previous
  version into the new one in `SavedGame.init(from:)`, and add a fixture of
  the new version next to the old ones (the reference pack's
  `01_MIGRATION_MAP.md`: "Every schema change should have an explicit
  migration function and regression fixture").

| File | Version | What it is |
| --- | --- | --- |
| `v1-demo-90-minutes.json` | 1 | The demo map (`DemoWorld`, English) after 90 game minutes: stations at points, one with two platforms; a surface and an elevated edge; two lines with a train each under traffic control; waiting passengers; a managed company's accounts. Its 32 × 24 map has every tile written out. |
| `v2-demo-90-minutes.json` | 2 | The same after Stage E1 (ARCHITECTURE decision 48): the demo map in the middle of a new game's 1024 × 1024 map, which is saved as its size and its occupied tiles (none); a new game's prices and city (G1d). |
| `v3-demo-90-minutes.json` | 3 | The demo map with ring lines (ARCHITECTURE decision 49): Lines 1 and 2 as before, shorter, and the Ring Line round Central on two circles of track with a two-car train each way (`"ring": true`, `"outerLastDispatch"`), both sent out since it opened. |
