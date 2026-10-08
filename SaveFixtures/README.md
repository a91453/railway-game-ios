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

Since version 12 (Phases 6a and 6b, ARCHITECTURE decisions 72 and 73) a
world can hold its land, who lives and works in each 64 m cell, and
`"landDemand"`, whether that land sets a managed company's ridership. Earlier saves have none
and read as before; a build before version 12 refuses a version 12 save
rather than dropping the land when it saves again.

Since version 13 (Phase 6c-1, ARCHITECTURE decision 74) a world can hold
`"cityBuildings"`, whether the city's buildings stand on its land, and
`"buildings"`, the building on each cell (runs of one-cell buildings
numbered one after another). Earlier saves have them off: their land keeps
growing to the fixed 400 residents and 1,200 jobs a cell, and turning them
on puts them up from the land the save holds. A build before version 13
refuses a version 13 save rather than dropping the buildings.

Since version 14 (Phase 6c-2, ARCHITECTURE decision 75) a station's town
growth can hold `"lastService"` and `"lastReached"`, the last day's service
share and stations reached, which raise the city's buildings; each is
written only when not 0. Earlier saves read both as 0 until the next
midnight measures them. A build before version 14 refuses a version 14
save rather than dropping them.

Since version 15 (ARCHITECTURE decision 81) a world can hold
`"transferGroups"`, stations passengers walk between however far apart, and
`"nextTransferGroupID"`. Earlier saves have none and hand out group IDs
from 1. A build before version 15 refuses a version 15 save rather than
dropping the groups and the journeys across them.

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
| `v12-land-towns.json` | 12 | Land (Phase 6a, ARCHITECTURE decision 72): a world 131072 × 98304 units (32 × 24 cells of 64 m) with the first town of seed 1 round its middle as Phase 6a first drew it (half the density 6b settled on), 437 cells with 24,984 residents and 16,614 jobs, saved as runs of cells (`"land"`); no demand from land; a line from West to Middle with a train, a managed company, after 30 minutes. Written by the version 12 build. |
| `v12-land-demand.json` | 12 | Demand from land (Phase 6b, ARCHITECTURE decision 73): the same world and town (at the density 6b settled on), managed, with `"landDemand": true` and town growth; a line from West to East through the town with one train, after two days and ten hours. The land has grown from 437 to 441 cells (50,189 → 51,256 residents) and set both stations' ridership. Written by the version 12 build. |
| `v13-city-buildings.json` | 13 | City buildings (Phase 6c-1, ARCHITECTURE decision 74): `v12-land-demand.json` with an office cell of 5,000 jobs set at row 0, column 0 (existing stock: D4 holds 1,680), the city's buildings turned on (`"cityBuildings": true`, 442 buildings numbered by row and column) and one day more. The land grew two cells that day, and each got its D1 homes, buildings 443 and 444: 444 cells and buildings, 94 D1, 187 D2, 129 D3, 33 D4 and one existing stock. Written by the version 13 build. |
| `v14-city-growth.json` | 14 | City growth (Phase 6c-2, ARCHITECTURE decision 75): `v13-city-buildings.json` a day later. Both stations served all their trips and reached one station (`"lastService": 1000`, `"lastReached": 1`), so each raised two full buildings (63, 67, 89 and 134, D2 to D3) and the land grew to its buildings' capacity: 446 cells and buildings, 96 D1, 183 D2, 133 D3, 33 D4 and one existing stock. Written by the version 14 build. |
| `v15-transfer-group.json` | 15 | Transfer groups (ARCHITECTURE decision 81): the walking-transfer test world with B and B' 600 m apart, too far to walk, linked in transfer group 1 (`"nextTransferGroupID": 2`); five passengers from A rode First to B, walked to B' (432 s at 5 km/h, a virtual transfer) and wait there for Second to C, after 2 minutes. Written by the version 15 build. |
