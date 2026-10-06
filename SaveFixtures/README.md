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

Since version 6 (Stage F3d, ARCHITECTURE decision 54) a world is its
bounds in world units; the map of `w × h` tiles a save before version 6
gives is read as bounds of `1024w × 1024h` units
(`SavedGameTests.testAMapOfTilesMigratesToBoundsAtTheTilesWidth`).

Since version 7 (Stage U2, ARCHITECTURE decision 56) a train following
another under traffic control holds its route only part of the way: its
reservation need not hold all of its route, only what it stands on and
fouls. Earlier saves never hold such a reservation and read as before; a
build before version 7 refuses a version 7 save rather than reading a
reservation it would reject.

Since version 8 (Stage V2, ARCHITECTURE decision 58) a service on its way
to a call may be on its way to, or stand at, a passing place: a berth of
another station where it stands aside out of a deadlock. Earlier saves never
hold one and read as before; a build before version 8 refuses a version 8
save rather than a service it would call damaged.

Since version 11 (Phase 5C/5F), a waiting or riding passenger group can hold
its remaining network journey and an OD pair can hold deterministic route
choice balances. Earlier saves have direct-trip groups and load in direct
routing mode. An older build must reject version 11 so it cannot silently
drop the transfer plan when saving again.

None of these saves holds anything of the grid: the app never wrote one
that did. Since Stage F3c (ARCHITECTURE decision 51) a save with grid
track, a station on tiles or a train on the grid, which only a save made by
hand could hold, is refused with that reason
(`SavedGameTests.testHandMadeSavesWithGridContentAreRefusedWithTheReason`).

| File | Version | What it is |
| --- | --- | --- |
| `v1-demo-90-minutes.json` | 1 | The demo map (`DemoWorld`, English) after 90 game minutes: stations at points, one with two platforms; a surface and an elevated edge; two lines with a train each under traffic control; waiting passengers; a managed company's accounts. Its 32 × 24 map has every tile written out. |
| `v2-demo-90-minutes.json` | 2 | The same after Stage E1 (ARCHITECTURE decision 48): the demo map in the middle of a new game's 1024 × 1024 map, which is saved as its size and its occupied tiles (none); a new game's prices and city (G1d). |
| `v3-demo-90-minutes.json` | 3 | The demo map with ring lines (ARCHITECTURE decision 49): Lines 1 and 2 as before, shorter, and the Ring Line round Central on two circles of track with a two-car train each way (`"ring": true`, `"outerLastDispatch"`), both sent out since it opened. |
| `v4-real-world-demo-90-minutes.json` | 4 | The same demo on a real-world map (Stage E2, ARCHITECTURE decision 50): the world's `"geoAnchor"` puts the middle of the map at Taipei Main Station (`Railway/`'s `tra.json`, in ten-millionths of a degree). Otherwise the version 3 save byte for byte. |
| `v4-demo-siding-90-minutes.json` | 4 | The blank demo map with a siding 192 (3 m) beside Line 1, from (526336, 524096) to (529408, 524096), after 90 game minutes: written by the version 4 build, before Stage F2 (ARCHITECTURE decision 52) made tracks keep 4 m apart. It loads with the siding and Line 1 exempt from the spacing. |
| `v5-demo-siding-90-minutes.json` | 5 | That save read by the Stage F2 build and saved again: the version 4 save with `"saveVersion": 5` and the network's `"spacingExemptions": [[1, 11]]`, byte for byte otherwise. |
| `v6-demo-siding-90-minutes.json` | 6 | The version 5 save read by the Stage F3d build (ARCHITECTURE decision 54) and saved again: `"saveVersion": 6`, the world's `"bounds": {"width": 1048576, "height": 1048576}` in world units instead of the version 5 `"map"` of 1024 × 1024 tiles, and no `"continuation": []` in the four trains' movements; byte for byte otherwise. The version 4 siding save saved again by this build gives it byte for byte too. |
| `v7-demo-siding-90-minutes.json` | 7 | The version 6 save read by the Stage U2 build (ARCHITECTURE decision 56) and saved again: `"saveVersion": 7`, byte for byte otherwise (no train follows another in it). The version 4 siding save and the version 6 save saved again by this build give it byte for byte too. |
| `v8-demo-siding-90-minutes.json` | 8 | The version 7 save read by the Stage V2 build (ARCHITECTURE decision 58) and saved again: `"saveVersion": 8`, byte for byte otherwise (no service in it stands aside at a passing place). The version 4 siding save, and the version 6 and 7 saves, saved again by this build give it byte for byte too. |
| `v11-network-transfer.json` | 11 | A two-line service with five passengers from A waiting at B for the second leg to C. Their original station keeps the conservation ledger; the waiting group holds its remaining journey and transfer ready time. Written by the version 11 build. |
