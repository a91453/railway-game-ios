import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 311 (City Transport Manager study 4.1): where a station would
/// have riders while building, on a small map and on Taipei's; the
/// building layer's switch.
@MainActor
final class StationPotentialMapTests: XCTestCase {
    private static func middle(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
    }

    /// 64 × 48 cells: a core of nine cells of 1,000 people round row 11,
    /// column 11 (homes to the west, offices to the east), and a village of
    /// 500 at row 20, column 50, 2.5 km and more away.
    private func world(stations: [PlanPoint] = []) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * 4_096, height: 48 * 4_096),
                              economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        var cells: [LandCell] = []
        for row in 10...12 {
            cells.append(LandCell(row: row, column: 10, use: .residential, residents: 1_000, jobs: 0))
            cells.append(LandCell(row: row, column: 11, use: .commercial, residents: 500, jobs: 500))
            cells.append(LandCell(row: row, column: 12, use: .office, residents: 0, jobs: 1_000))
        }
        cells.append(LandCell(row: 20, column: 50, use: .residential, residents: 500, jobs: 0))
        try world.setLand(cells)
        for (index, point) in stations.enumerated() {
            _ = try world.buildStation(named: "S\(index)", at: point)
        }
        return world
    }

    /// With no new line, a cell's value is the people a station there
    /// reaches, as GameCore counts a station's catchment.
    func testEachCellCountsTheCatchmentAStationThereWouldHave() throws {
        let world = try world()
        let map = StationPotentialMap(world: world)
        for (row, column) in [(11, 11), (11, 20), (11, 24), (5, 5), (20, 50), (20, 38), (0, 0), (47, 63)] {
            let totals = world.land.totals(within: Land.catchmentRadius, of: Self.middle(row: row, column: column))
            XCTAssertEqual(map.value(row: row, column: column), totals.residents + totals.jobs, "cell \(row), \(column)")
        }
        XCTAssertEqual(map.value(row: 11, column: 11), 9_000)
        XCTAssertEqual(map.value(row: 99, column: 0), 0, "off the map")
    }

    /// The highest cells are those that reach the whole core; the village
    /// is lower, and an empty corner draws nothing.
    func testTheHighestCellIsWhereTheMostPeopleAre() throws {
        let map = StationPotentialMap(world: try world())
        var best: (value: Int64, cells: [CellPosition]) = (0, [])
        for row in 0..<48 {
            for column in 0..<64 {
                let value = map.value(row: row, column: column)
                if value > best.value { best = (value, [CellPosition(row: row, column: column)]) } else if value == best.value { best.cells.append(CellPosition(row: row, column: column)) }
            }
        }
        XCTAssertEqual(best.value, 9_000)
        XCTAssertTrue(best.cells.contains(CellPosition(row: 11, column: 11)))
        XCTAssertTrue(best.cells.allSatisfy { abs($0.row - 11) <= 12 && abs($0.column - 11) <= 12 }, "all round the core")
        XCTAssertEqual(map.value(row: 20, column: 50), 500)

        let tiles = map.tiles(in: WorldRegion(minX: 0, minY: 0, maxX: 64 * 4_096, maxY: 48 * 4_096))
        let core = try XCTUnwrap(tiles.first { $0.minX == 11 * 4_096 && $0.minY == 11 * 4_096 })
        XCTAssertEqual(core.value, 9_000)
        XCTAssertEqual(StationPotentialMap.band(of: 9_000), 3)
        XCTAssertEqual(core.color, StationPotentialMap.colors[3])
        XCTAssertNil(tiles.first { $0.minX == 0 && $0.minY == 0 }, "no one near the corner, nothing drawn")
        XCTAssertNil(StationPotentialMap.band(of: 249))
        XCTAssertEqual(StationPotentialMap.band(of: 20_000), 5)
    }

    /// Blocks merged when zoomed out are scaled to a catchment of their
    /// density, so a block of the core does not read as the whole core.
    func testMergedBlocksKeepACatchmentsScale() throws {
        let map = StationPotentialMap(world: try world())
        let blocks = map.tiles(in: WorldRegion(minX: 0, minY: 0, maxX: 64 * 4_096, maxY: 48 * 4_096), blockSize: 16)
        let core = try XCTUnwrap(blocks.first { $0.minX == 0 && $0.minY == 0 })
        // The 16-cell block holds the nine core cells: 9,000 people over
        // 256 cells, scaled to the 489 cells a catchment holds.
        XCTAssertEqual(core.value, 9_000 * 489 / 256)
        XCTAssertEqual(core.maxX - core.minX, 16 * 4_096)
    }

    /// With a new line's station picked, trips from it ride far more than
    /// near (decision 137), and a cell another station reaches is paler.
    func testANewLinesStationsWeighByDistanceAndFadeServedCells() throws {
        var world = try world(stations: [Self.middle(row: 11, column: 11), Self.middle(row: 20, column: 50)])
        world.setDistanceDemand(true)
        let draft = world.stations[0].id
        let plain = StationPotentialMap(world: world)
        let picked = StationPotentialMap(world: world, drafts: [draft])
        XCTAssertTrue(picked.key.hasDrafts)
        XCTAssertFalse(plain.key.hasDrafts)
        // At the picked station itself: a tenth (within 500 m, people walk).
        XCTAssertEqual(picked.value(row: 11, column: 11), 9_000 * DistanceDemand.nearShare / 1_000)
        // The village, 2.5 km away, rides in full, but the other station
        // already reaches it.
        XCTAssertEqual(picked.value(row: 20, column: 50), 500 * StationPotentialMap.servedShare / 1_000)
        XCTAssertLessThan(picked.value(row: 20, column: 50), plain.value(row: 20, column: 50))
        // Closed, it no longer reaches the village: full again.
        try world.setStationOperationMode(world.stations[1].id, to: .closed)
        XCTAssertEqual(StationPotentialMap(world: world, drafts: [draft]).value(row: 20, column: 50), 500)
        // Without decision 137's share, distance does not weigh.
        world.setDistanceDemand(false)
        XCTAssertEqual(StationPotentialMap(world: world, drafts: [draft]).value(row: 11, column: 11), 9_000)
    }

    /// The morning weighs offices up and homes down; the evening the other
    /// way round; the whole day counts everyone once.
    func testMorningAndEveningWeighHomesAndJobsByWhenTripsArrive() throws {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * 4_096, height: 48 * 4_096),
                              economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 30, column: 50, use: .office, residents: 0, jobs: 1_000),
        ])
        func value(_ period: PotentialPeriod, _ row: Int, _ column: Int) -> Int64 {
            StationPotentialMap(world: world, period: period).value(row: row, column: column)
        }
        XCTAssertEqual(value(.allDay, 5, 5), 1_000)
        XCTAssertEqual(value(.allDay, 30, 50), 1_000)
        XCTAssertGreaterThan(value(.evening, 5, 5), value(.morning, 5, 5), "homes: trips come back in the evening")
        XCTAssertGreaterThan(value(.morning, 30, 50), value(.evening, 30, 50), "offices: trips arrive in the morning")
        XCTAssertEqual(value(.morning, 30, 50), (1_316 + 1_492 + 1_316) / 3)
        XCTAssertEqual(value(.morning, 5, 5), 933)
        XCTAssertEqual(PotentialPeriod.allDay.weight(of: .office), 1_000)
    }

    /// Coverage counts only the open stations, the ones a passenger can
    /// use, as the coverage layer always has.
    func testCoverageCountsOnlyOpenStations() throws {
        var world = try world(stations: [Self.middle(row: 11, column: 11)])
        let region = WorldRegion(minX: 0, minY: 0, maxX: 64 * 4_096, maxY: 48 * 4_096)
        let open = CityMap(world: world).tiles(for: .coverage, in: region)
        XCTAssertEqual(open.first { $0.minX == 11 * 4_096 && $0.minY == 11 * 4_096 }?.color, CityMap.coveredColor)
        try world.setStationOperationMode(world.stations[0].id, to: .closed)
        let closed = CityMap(world: world).tiles(for: .coverage, in: region)
        XCTAssertEqual(closed.first { $0.minX == 11 * 4_096 && $0.minY == 11 * 4_096 }?.color, CityMap.uncoveredColor)
    }

    /// The key stays equal while time runs, so the map is not worked out
    /// again on a tick; a command that builds a station, or another hour
    /// or station picked, makes a new one. Chunks are worked out once.
    func testTheMapIsKeptUntilACommandChangesWhatItReads() throws {
        var world = try world(stations: [Self.middle(row: 11, column: 11)])
        let key = StationPotentialMap.Key(world: world, drafts: [], period: .allDay)
        try world.advance(ticks: 30)
        XCTAssertEqual(StationPotentialMap.Key(world: world, drafts: [], period: .allDay), key, "ticks change nothing it reads")
        XCTAssertNotEqual(StationPotentialMap.Key(world: world, drafts: [], period: .morning), key)
        XCTAssertNotEqual(StationPotentialMap.Key(world: world, drafts: [world.stations[0].id], period: .allDay), key)
        _ = try world.buildStation(named: "New", at: Self.middle(row: 30, column: 30))
        XCTAssertNotEqual(StationPotentialMap.Key(world: world, drafts: [], period: .allDay), key, "a command does")

        let map = StationPotentialMap(key: key)
        let region = WorldRegion(minX: 0, minY: 0, maxX: 20 * 4_096, maxY: 20 * 4_096)
        let first = map.tiles(in: region)
        XCTAssertEqual(map.chunksWorkedOut, 1)
        XCTAssertEqual(map.tiles(in: region), first)
        XCTAssertEqual(map.chunksWorkedOut, 1, "kept, not worked out again")
        _ = map.tiles(in: WorldRegion(minX: 0, minY: 0, maxX: 64 * 4_096, maxY: 48 * 4_096))
        XCTAssertEqual(map.chunksWorkedOut, 4, "only the chunks brought into view")
    }

    func testTheLegendsWords() {
        XCTAssertEqual(StationPotentialMap.title(hasDrafts: false, in: .traditionalChinese), "哪裡人多")
        XCTAssertEqual(StationPotentialMap.title(hasDrafts: true, in: .traditionalChinese), "從你的站可以去哪")
        XCTAssertEqual(StationPotentialMap.title(hasDrafts: false, in: .english), "Where people are")
        XCTAssertEqual(StationPotentialMap.title(hasDrafts: true, in: .english), "Where your stations reach")
        for hasDrafts in [false, true] {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let line = StationPotentialMap.line(hasDrafts: hasDrafts, in: language)
                XCTAssertFalse(line.isEmpty)
                XCTAssertFalse(line.contains("800"), "no formula in the player's words")
            }
        }
        XCTAssertEqual(PotentialPeriod.allCases.map { $0.title(in: .traditionalChinese) }, ["全天", "早上", "傍晚"])
        XCTAssertFalse(StationPotentialMap.info(in: .english).isEmpty)
    }

    // MARK: - The switch

    func testBuildingShowsWherePeopleAreAndPutsTheLayerBackAfter() {
        var shortcut = BuildingLayerShortcut()
        XCTAssertEqual(shortcut.layer(over: .landValue), .landValue)
        shortcut.buildingBegan(autoShows: true)
        XCTAssertEqual(shortcut.layer(over: .landValue), .potential)
        XCTAssertTrue(shortcut.isOn)
        shortcut.choose(.coverage)
        XCTAssertEqual(shortcut.layer(over: .landValue), .coverage)
        shortcut.choose(.zoning)
        XCTAssertEqual(shortcut.layer(over: .landValue), .coverage, "only the two")
        shortcut.buildingEnded()
        XCTAssertEqual(shortcut.layer(over: .landValue), .landValue, "the player's own layer, untouched")
        XCTAssertEqual(shortcut.layer(over: nil), nil)
        XCTAssertEqual(shortcut.layer(over: .potential), nil, "never the player's own")
        // The choice is kept for the next time.
        shortcut.buildingBegan(autoShows: true)
        XCTAssertEqual(shortcut.layer(over: nil), .coverage)
    }

    func testTheCornerButtonPutsItAwayAndBringsItBack() {
        var shortcut = BuildingLayerShortcut()
        shortcut.buildingBegan(autoShows: true)
        XCTAssertFalse(shortcut.toggle(), "put away: not shown next time either")
        XCTAssertEqual(shortcut.layer(over: .population), .population)
        shortcut.buildingEnded()
        shortcut.buildingBegan(autoShows: false)
        XCTAssertFalse(shortcut.isOn)
        XCTAssertTrue(shortcut.toggle())
        XCTAssertEqual(shortcut.layer(over: .population), .potential)
        // The player picks a layer of their own while building.
        shortcut.playerChoseLayer()
        XCTAssertEqual(shortcut.layer(over: .zoning), .zoning)
    }

    // MARK: - Timing

    /// How long Taipei's new game takes (anchor 25.047882, 121.517219, the
    /// densest land the game has), for the record: printed, not asserted.
    /// The whole 16 km map zoomed out as a phone shows it (some 400 points
    /// wide, blocks of 4 cells), and a phone's screen of single cells at
    /// the middle (66 × 140 cells, each over 6 points).
    func testTaipeisDenseLandIsWorkedOutInView() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        let places = try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219))
        let cells = try XCTUnwrap(LandImport.cells(
            population: population, places: places, frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds
        ))
        var world = GameWorld.newGame(anchor: anchor, land: cells)
        for (index, dx) in [Int64(-30_000), 0, 30_000].enumerated() {
            _ = try world.buildStation(named: "S\(index)", at: PlanPoint(x: 524_288 + dx, y: 524_288))
        }
        let drafts = [world.stations[0].id]
        let bounds = world.bounds
        let whole = WorldRegion(minX: 0, minY: 0, maxX: Double(bounds.width), maxY: Double(bounds.height))
        let screen = WorldRegion(minX: 524_288 - 33 * 4_096, minY: 524_288 - 70 * 4_096, maxX: 524_288 + 33 * 4_096, maxY: 524_288 + 70 * 4_096)
        for (name, region, blockSize) in [("whole map, blocks of 4", whole, 4), ("a screen of cells", screen, 1)] {
            for picked in [[], drafts] {
                let map = StationPotentialMap(world: world, drafts: picked, period: .morning)
                let start = ContinuousClock.now
                let tiles = map.tiles(in: region, blockSize: blockSize)
                let first = ContinuousClock.now - start
                let again = ContinuousClock.now
                XCTAssertEqual(map.tiles(in: region, blockSize: blockSize).count, tiles.count)
                let kept = ContinuousClock.now - again
                print("Potential for Taipei, \(name)\(picked.isEmpty ? "" : ", a station picked"): \(tiles.count) tiles, \(map.chunksWorkedOut) chunks in \(first), kept \(kept)")
                XCTAssertFalse(tiles.isEmpty)
            }
        }
        // The densest place reaches more than the whole small map.
        let map = StationPotentialMap(world: world)
        XCTAssertGreaterThan(map.value(row: 128, column: 128), 20_000)
    }
}
