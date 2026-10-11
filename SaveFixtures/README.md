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

Since version 16 (Phase 7a, ARCHITECTURE decision 85) a managed company's
accounts can hold `"assets"`, what each track edge, station, train and car
cost and how far it is written down, `"capitalDays"`, each day's
depreciation, write-offs, purchases and loan movements, and `"years"`, the
closed years with their balance sheets. Earlier saves have none: what they
built is on the books at nothing and is never written down or off. A build
before version 16 refuses a version 16 save rather than dropping what
everything cost.

Since version 17 (decision 86) a world can hold a `"scenario"`, its goals,
ratings and how far they are met, its accounts' days their `"fareTrips"`,
and its clock can run `"fast"` (6000×). Earlier saves have no goals and no
trips counted. A build before version 17 refuses a version 17 save rather
than dropping the scenario or the speed.

Since version 18 (decision 88) a world's sides can be up to 2^25 units
(524 km), and a world whose land is read in as it is needed (the whole of
Taiwan) holds `"landBlocks"`, the 1,024 m blocks read so far, as runs along
a row (`{"row", "column", "count"}`). Earlier saves are at most 2^20 a side
and have their land whole. A build before version 18 refuses a version 18
save rather than calling a larger world damaged or dropping the blocks.

Since version 19 (decision 90) a scenario can hold `"events"`, festivals on
the same day of every 360-day year, and a demand event can be of kind
`"festival"`. Earlier saves have no festivals. A build before version 19
refuses a version 19 save rather than dropping the festivals or refusing
the kind.

Since version 20 (decision 91) land and buildings can also be
`"industrial"`, `"civic"`, `"leisure"`, `"agricultural"` or `"park"` (a
park with no one in it: a run of `"residents": [0, …]` with no `"jobs"`),
and a station's demand can be `"civic"`. The format is otherwise the same,
and earlier saves hold only homes, shops and offices and the four reference
kinds; a build before version 20 refuses a version 20 save rather than
calling the new uses damaged.

Since version 21 (decision 92) a world can have `"placedBuildings"`, the buildings the player
placed (`{"id", "kind", "centre": {"x", "y"}}`, the kind `"house"`, `"shop"`
or `"office"`), and `"nextPlacedBuildingID"`. Earlier saves have none; a
build before version 21 refuses a version 21 save rather than dropping them.

Since version 22 (decision 94) a managed company pays for its buildings: a
building can carry `"residents"`, `"jobs"`, `"buildingCost"` and
`"landCost"` (each written only when it is not zero), each paid-for building
has an asset record of kind `"building"`, a day's account and a year's
statement can carry `"propertyRevenue"` and `"propertyCost"`, a balance
sheet `"buildings"`, and the ledger rows of kind `"dailyProperty"` and `"buildingDemolition"`. A version
21 save's buildings read as empty and free, with no asset record; a build
before version 22 refuses a version 22 save rather than dropping what they
cost.

Since version 23 (decision 98) a world can have `"zones"`, the cells the
player zoned, as runs along a row: `{"row", "column", "zone", "count"}`, the
zone `"residential"`, `"commercial"`, `"office"`, `"industrial"`, `"civic"`,
`"leisure"`, `"noDevelopment"` or `"reserved"`. Earlier saves have none; a
build before version 23 refuses a version 23 save rather than dropping them.

Since version 24 (decision 105) a world can have `"terrain"`, the ground
under its land: `{"water": [{"row", "column", "count"}, …]}`, its cells of
water as runs along a row, in order, apart (two touching runs are one), with
no land on them, and for land read as it is needed only in the blocks read.
Earlier saves have no water and grow as before; a build before version 24
refuses a version 24 save rather than dropping the water.

Since version 25 (decision 111) a placed building can be a `"wharf"` or a
`"marina"`, which stand on the shore. Earlier saves have neither; a build
before version 25 refuses a version 25 save rather than calling those
buildings damaged.

Since version 26 (decision 115) the world's `"terrain"` can have `"steep"`,
its steep slopes as runs alike, in order, apart and none on water (land may
stand on them). Earlier saves have none; a build before version 26 refuses a
version 26 save rather than dropping them.

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
| `v16-assets-closed-year.json` | 16 | Fixed assets and a closed year (Phase 7a, ARCHITECTURE decision 85): a managed company with a 128 m edge (split at 32 m on day 1, its $720 and depreciation shared $180 / $540), a $7,200 station, a $3,600 train with two $360 cars and a $100,000 loan, run through the end of its first year and taken a car off: five asset records written down for 360 days, 361 capital days and year 0 closed (net loss $5,868, closing cash $182,720, equity $94,132). Written by the version 16 build (`SavedGameTests.assetWorld()`, `ASSET_SAVE_NEW=1`). |
| `v17-scenario-fast.json` | 17 | Goals and fast forward (decision 86): five stations 1 km apart in a managed world, a line from the first to the second, and a scenario (`test.fixture`) to connect the first two stations' places and reach 1,000 residents, gold by day 30, silver 60, bronze 120, lost after 30 midnights in the red, Type C and D trains only; run a day and a minute at `fast`: the connection met on day 0, the population not. Written by the version 17 build (`SavedGameTests.scenarioWorld()`, `SCENARIO_SAVE_NEW=1`). |
| `v18-whole-island-land.json` | 18 | The whole of Taiwan's scale (decision 88): a world 33,554,432 × 25,165,824 units (524 × 393 km), a managed company with demand from land and the city's buildings, its land read in as it is needed (`setLandOnDemand`): a station "Far" at (20,000,000, 18,000,000), the 22 blocks within 2 km of it read with five cells round it (1,000 residents, 1,800 jobs) and their five buildings, run ten minutes. Written by the version 18 build (`SavedGameTests.wholeIslandWorld()`, `WHOLE_ISLAND_SAVE_NEW=1`). |
| `v19-scenario-festival.json` | 19 | Festivals (decision 90): the version 17 world's five stations and line with demand events from seed 1, and a scenario (`test.festival`) whose festival at the second station runs 3 days from day 3 of each year at +1500‰, announced 2 days ahead; run a day and ten minutes at `fast`, when it was announced. Written by the version 19 build (`SavedGameTests.festivalWorld()`, `FESTIVAL_SAVE_NEW=1`). |
| `v20-land-uses.json` | 20 | Eight land uses (decision 91): a world 131,072 × 98,304 units (32 × 24 cells), a managed company with demand from land, the city's buildings and town growth; homes, a factory, a school, a sight, a farm and a park along row 5, and a second school at row 15, column 20; "School" alone reaches the second school (a `civic` demand of 400 trips), "Works" the row (`scenic`, the sight's visitors the most), run ten minutes. Written by the version 20 build (`SavedGameTests.landUsesWorld()`, `LAND_USES_SAVE_NEW=1`). |
| `v21-placed-buildings.json` | 21 | Buildings the player placed (decision 92): a blank world 20,480 units (320 m) a side, managed, with a 250 m edge, the station Market on it, and a house, a shop and an office block beside them (`"nextPlacedBuildingID": 4`), run ten minutes. Written by the version 21 build (`SavedGameTests.placedBuildingsWorld()`, `PLACED_BUILDINGS_SAVE_NEW=1`). Since decision 94 a managed company pays for its buildings, so that builder is gone and the test checks the save as it reads. |
| `v22-company-buildings.json` | 22 | The company's buildings (decision 94): a world 131,072 × 98,304 units, managed, with demand from land and town growth, one home cell at row 5, column 5 and the station S0 beside it; a house and an office block bought (2,304,000 and 25,600,000 cents with their land) and on the books, filled twice at a service of 800 (2 residents and 2 jobs, 2 and 26), and the day's rent, upkeep and land tax settled as a `dailyProperty` row. Written by the version 22 build (`CompanyBuildingsTests.companyBuildingsWorld()`, `COMPANY_BUILDINGS_SAVE_NEW=1`; it is in `CompanyBuildingsTests` because it fills and settles through GameCore's internal steps). |
| `v23-zoning.json` | 23 | Zoning (decision 98): the version 22 world's land and station S0, a house bought beside it, homes zoned on row 3 (columns 3 to 7), shops on row 10 (4 to 6), no development on row 12 (0 to 3) and reserved land on row 14 (10 to 12), 15 cells in four runs, run ten minutes. Written by the version 23 build (`ZoningTests.zoningWorld()`, `ZONING_SAVE_NEW=1`). |
| `v24-water.json` | 24 | Water (decision 105): the version 23 world's size, land (one home cell at row 5, column 5) and station S0, managed with demand from land and town growth, by the sea (rows 0 to 2, three runs of 32 cells) with a river down column 10 below it (rows 3 to 23, 21 runs of one cell): 117 cells of water in `"terrain": {"water": [...]}`; a house bought beside the river (touching its edge from the west), homes zoned on rows 2 to 3, columns 3 to 7, of which only row 3's five cells were zoned (row 2 is the sea), run ten minutes. Written by the version 24 build (`TerrainTests.waterWorld()`, `WATER_SAVE_NEW=1`). |
| `v25-shore-buildings.json` | 25 | Shore buildings (decision 111): the version 24 world (the sea on rows 0 to 2, a river down column 10, one home cell, the station S0, homes zoned on row 3), with the house bought beside the river now paying for its land by the water (2,048,000 + 409,600 cents: 256 m² at 1,000 + 600 a m²) and a marina across the river's west bank (rows 14 to 15, columns 9 to 10; 8,192,000 + 1,638,400), run ten minutes. Written by the version 25 build (`TerrainTests.shoreWorld()`, `SHORE_SAVE_NEW=1`). |
| `v26-steep-slopes.json` | 26 | Steep slopes (decision 115): the version 25 world (sea, river, house and marina, homes zoned on row 3) with a hillside of steep slope east of column 20 (columns 20 to 31, rows 3 to 23; 21 runs of 12, 252 cells) in `"terrain"`'s `"steep"`, and a home cell of 50 standing on it at (6, 22), run ten minutes. Written by the version 26 build (`SteepSlopeTests.slopeWorld()`, `SLOPE_SAVE_NEW=1`). |
| `v27-ground-height.json` | 27 | The ground's height (decision 124): the version 26 world (sea, river, steep hillside, house and marina, homes zoned on row 3) with the ground of blocks (0, 0), (0, 1) and (1, 0) read in `"ground"` (17 × 17 corners each, block (r, c)'s corner (i, j) 100 r + 10 c + i + j metres), run ten minutes more. Written by the version 27 build (`GroundTests.groundWorld()`, `GROUND_SAVE_NEW=1`). |
| `v28-terrain-track.json` | 28 | Track over the ground (decision 124): the version 27 world with two automatic edges, each with its `"sections"`: y = 20,480 from x = 30,720 to 53,248 at 24 m (viaduct 10 lengths, bridge 4 over the river, embankment 8) and y = 40,960 from x = 4,096 to 12,288 at 0 m (tunnel 8), run ten minutes more. Written by the version 28 build (`TrackSectionTests.terrainTrackWorld()`, `TERRAIN_TRACK_SAVE_NEW=1`). |
| `v29-building-sale.json` | 29 | Selling the company's buildings (decision 130): a world 131,072 × 98,304 units, managed, with demand from land, town growth and the city's buildings, one home cell at row 5, column 5 and the station S0 beside it; a house and an office block bought beside it (27,904,000 cents with their land, written down 2,583 at the first midnight), filled to 4 and 2 and to 3 and 20, and sold on day 1 for 9,407,242 against a book value of 27,901,417 (`"saleProceeds"`, `"saleBookValue"` in the capital day); their people became the city's home cell (7, 5) and office cell (7, 7) with D1 buildings 2 and 3, run ten minutes more. Written by the version 29 build (`BuildingSaleTests.saleWorld()`, `BUILDING_SALE_SAVE_NEW=1`). |
| `v30-line-runs.json` | 30 | A line's runs (decision 133): Alpha, Beta and Gamma on a straight track, the line Main calling at all three with two runs, Alpha to Gamma leaving at 00:10 (Beta 00:15–00:16, Gamma 00:20) and back leaving Gamma at 00:30 (Beta 00:35–00:36, Alpha 00:40), in `"runs"` (`{"from", "to", "times": [[arrival, departure], …]}`, seconds of the day); the train Blue sent on the run out at 00:05, so `"runDays": [0, null]`, run ten minutes. Written by the version 30 build (`LineRunsTests.world()`, `LINE_RUNS_SAVE_NEW=1`). |
| `v31-distance-demand.json` | 31 | Demand by distance and the outside connections (decision 137): a managed world of the standard bounds with demand from land, `"distanceDemand": true` and `"outsideConnections": true`; a home cell of 1,000 residents in the middle with the station Town on it, West 30,000 units from the west edge and East 60,000 from the east edge (both outside connections, sharing the outside's 6,000 trips a day: 3,000 each), the line Across from West through Town to East, run ten minutes. Written by the version 31 build (`DistanceDemandTests.edgeWorld()`, `DISTANCE_DEMAND_SAVE_NEW=1`). |
| `v32-city-demand.json` | 32 | The city's demand (decision 139): a world 131,072 × 98,304 units (32 × 24 cells), managed, with demand from land and town growth; homes of 300 at row 5, column 5, shops of 40 living and 300 working at column 6 and offices of 600 jobs at column 7, the station S0 at (22,528, 22,528), offices zoned on row 8 (columns 5 to 7), and `"cityDemand": {"baseline": {"shopJobs": 882352, "workJobs": 1764705}}`, the mix of its 340 residents; run a day and a minute. Written by the version 32 build (`CityDemandTests.world()`, `CITY_DEMAND_SAVE_NEW=1`). |
| `v33-city-footprints.json` | 33 | The city's footprints (decision 142): a world 131,072 × 98,304 units (32 × 24 cells), managed, with the city's buildings and `"cityFootprints": true`; a D1 home of 4 residents at row 5, column 5 and a D4 home of 1,000 at column 9, and an office block at (24,320, 22,528) beside the D1 home, clear of its 20 m square so nothing was bought out (26,624,000 cents with its land), run ten minutes. Written by the version 33 build (`CityFootprintsTests.world(footprints:)`, `CITY_FOOTPRINTS_SAVE_NEW=1`). |
| `v34-area-buyout.json` | 34 | Buying out by area (decision 146): a world 131,072 × 98,304 units (32 × 24 cells), managed, with the city's buildings, `"cityFootprints": true` and `"areaBuyOut": true`; D1 homes of 48 residents and 8 jobs at row 5, columns 5 and 6, and an office block at (24,576, 22,528) on the line between them, covering an eighth of each: it paid an eighth of each home's buy-out (30,550,400 cents in all), took 6 residents and 1 job from each, and both cells stayed, run ten minutes. Written by the version 34 build (`AreaBuyOutTests.world(area:)`, `AREA_BUYOUT_SAVE_NEW=1`). |
| `v35-real-coverage.json` | 35 | Real coverage (decision 147): `v34-area-buyout.json`'s world, but cell (5, 5) is known to be 0 % covered and cell (5, 6) 50 %, so the land's runs have `"coverage"`; the office block between them paid nothing for the first and an eighth of the second's 24,576,000 buy-out, run ten minutes. Written by the version 35 build (`RealCoverageTests.world(west:east:)`, `REAL_COVERAGE_SAVE_NEW=1`). |
| `v38-freight.json` | 38 | Freight (decision 155): two stations 64 m apart on a straight track, a managed company, 40,000 industrial jobs in the cell by Alpha, a freight yard at each, the freight line Goods (`"freight": true`) and one train of one car, run five hours and on to the minute its train carries cargo (40 t from Alpha); the world has `"freight"`, with the yards' stock, the load, the totals and the hours' `hourlyFreight` ledger rows. Written by the version 38 build (`FreightTests.testVersionThirtyEightKeepsItsFreight`, `FREIGHT_SAVE_NEW=1`). |
