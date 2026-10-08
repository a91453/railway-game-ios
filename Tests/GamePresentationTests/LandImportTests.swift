import Foundation
import GameCore
import GamePresentation
import XCTest

/// Land in the app (Phase 6a, ARCHITECTURE decision 72): a new game's towns
/// or a real-world map's people, the blank map's population layer and the
/// station panel's line.
final class LandImportTests: XCTestCase {
    private static func bundled() throws -> PopulationGrid {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
    }

    private static let taipei = (latitude: 25.047882, longitude: 121.517219)

    private static func frame(_ anchor: GeoAnchor) -> RealWorldFrame {
        RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
    }

    // MARK: - New games

    func testANewGameFoundsTheTownsOfItsSeedUnlessGivenLand() throws {
        XCTAssertEqual(GameWorld.newGame().land, Land.towns(seed: 1, in: .standard))
        XCTAssertEqual(GameWorld.newGame(eventSeed: 77).land, Land.towns(seed: 77, in: .standard))
        let tokyo = try XCTUnwrap(GeoAnchor(latitudeDegrees: 35.681_2, longitudeDegrees: 139.767_1))
        XCTAssertEqual(GameWorld.newGame(anchor: tokyo, eventSeed: 5).land, Land.towns(seed: 5, in: .standard), "a real map without people")
        let cells = [LandCell(row: 3, column: 4, use: .residential, residents: 9, jobs: 0)]
        XCTAssertEqual(GameWorld.newGame(anchor: tokyo, land: cells).land.cells, cells)
        XCTAssertTrue(GameWorld.newGame(land: []).land.isEmpty)
    }

    // MARK: - Importing a real-world map's people

    func testTaipeisPeopleBecomeItsLand() throws {
        let grid = try Self.bundled()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let cells = try XCTUnwrap(LandImport.cells(population: grid, frame: Self.frame(anchor), bounds: GameWorld.newGameBounds))
        var world = GameWorld.newGame(anchor: anchor, land: cells)
        XCTAssertEqual(world.land.cells, cells, "the cells are valid land, in order")
        XCTAssertTrue(cells.allSatisfy { $0.use == .residential && $0.jobs == 0 && $0.residents > 0 })
        // 16 km round Taipei Main Station: most of Taipei and the near
        // side of New Taipei. The WorldPop cells whose middles lie in the
        // square hold 4,777,604 (summed from the file on its own); the land
        // keeps only the share inside of those cut by the edge.
        let total = world.land.totals.residents
        XCTAssertTrue((4_500_000 ... 4_777_604).contains(total), "\(total) people")
        XCTAssertLessThan(total, Int64(grid.total))

        // A station by Taipei Main Station has about the people the grid
        // counts within 800 m of it (the grid's are sampled every 50 m,
        // the land's are whole 64 m cells).
        let station = try world.buildStation(named: "Taipei", at: PlanPoint(x: 524_288, y: 524_288)).id
        let catchment = try XCTUnwrap(world.landCatchment(of: station)).residents
        let sampled = Int64(try XCTUnwrap(grid.people(within: 800, ofLatitude: Self.taipei.latitude, longitude: Self.taipei.longitude)))
        XCTAssertEqual(Double(catchment), Double(sampled), accuracy: Double(sampled) * 0.1, "\(catchment) against \(sampled)")
    }

    /// A WorldPop cell inside the world keeps all its people, shared among
    /// its 64 m cells by the largest remainder; one at the world's edge
    /// only the share of the part inside.
    func testEveryoneInsideIsKeptAndTheEdgeTakesItsShare() throws {
        let grid = try Self.bundled()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        // A small world: 2 km a side, so its edges cut WorldPop cells.
        let bounds = try WorldBounds(width: 131_072, height: 131_072)
        let frame = RealWorldFrame(anchor: anchor, bounds: bounds)
        let cells = try XCTUnwrap(LandImport.cells(population: grid, frame: frame, bounds: bounds))
        // The middle WorldPop cell, wholly inside.
        let middle = frame.coordinate(worldX: 65_536, worldY: 65_536)
        let tiny = 1e-7
        let people = try XCTUnwrap(grid.cells(
            north: middle.latitude + tiny, south: middle.latitude - tiny, west: middle.longitude - tiny, east: middle.longitude + tiny
        ).first)
        func isInMiddleCell(_ cell: LandCell) -> Bool {
            let place = frame.coordinate(worldX: Double(cell.middle.x), worldY: Double(cell.middle.y))
            return place.latitude <= people.northLatitude && place.latitude > people.southLatitude
                && place.longitude >= people.westLongitude && place.longitude < people.eastLongitude
        }
        let inMiddle = cells.filter(isInMiddleCell)
        XCTAssertEqual(inMiddle.reduce(0) { $0 + $1.residents }, Int64(people.count))
        let counts = Set(inMiddle.map(\.residents))
        XCTAssertLessThanOrEqual(counts.count, 2, "shared evenly, some one more")
        // Everyone in the small world is no more than the WorldPop cells it
        // touches hold.
        let corners = (frame.coordinate(worldX: 0, worldY: 0), frame.coordinate(worldX: 131_072, worldY: 131_072))
        let touched = grid.cells(north: corners.0.latitude, south: corners.1.latitude, west: corners.0.longitude, east: corners.1.longitude)
        XCTAssertLessThan(cells.reduce(0) { $0 + $1.residents }, Int64(touched.reduce(0) { $0 + $1.count }))
    }

    private static func bundledPlaces() throws -> PlaceGrid {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
    }

    /// Phase 6b: the places round a real-world map become its jobs, and a
    /// station there takes the ridership of its share of the land.
    func testTheirPlacesBecomeJobsAndAStationTakesItsShare() throws {
        let grid = try Self.bundled()
        let places = try Self.bundledPlaces()
        // Taiwan's places make some 8.6 million jobs.
        let jobs = PlaceGrid.Kind.allCases.reduce(Int64(0)) { $0 + Int64(places.total(of: $1)) * (LandImport.jobsPerPlace[$1] ?? 0) }
        XCTAssertEqual(jobs, 8_561_200)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let cells = try XCTUnwrap(LandImport.cells(population: grid, places: places, frame: Self.frame(anchor), bounds: GameWorld.newGameBounds))
        let without = try XCTUnwrap(LandImport.cells(population: grid, frame: Self.frame(anchor), bounds: GameWorld.newGameBounds))
        var world = GameWorld.newGame(anchor: anchor, land: cells)
        XCTAssertEqual(world.land.totals.residents, without.reduce(0) { $0 + $1.residents }, "the same people")
        XCTAssertTrue((1_500_000 ... 3_000_000).contains(world.land.totals.jobs), "\(world.land.totals.jobs) jobs round Taipei")
        XCTAssertEqual(Set(cells.map(\.use)), Set(LandUse.allCases), "homes, shops and offices")
        // Taipei Main Station: an office station, its ridership its share.
        let station = try world.buildStation(named: "Taipei", at: PlanPoint(x: 524_288, y: 524_288)).id
        let demand = try XCTUnwrap(world.stationDemand(of: station))
        XCTAssertEqual(demand.kind, .office)
        XCTAssertEqual(demand, LandDemand.shares(of: world.land, among: world.stations)[station]?.demand)
    }

    /// Phase 6c-1 (ARCHITECTURE decision 74): a new game of Taipei puts up
    /// a building on each of its cells, every one an ordinary city building
    /// holding all who live and work there.
    func testTaipeisCellsGetTheirBuildings() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let cells = try XCTUnwrap(LandImport.cells(population: Self.bundled(), places: Self.bundledPlaces(), frame: Self.frame(anchor), bounds: GameWorld.newGameBounds))
        let world = GameWorld.newGame(anchor: anchor, land: cells)
        XCTAssertTrue(world.cityBuildings)
        XCTAssertEqual(world.buildings.all.count, world.land.cells.count)
        var counts: [LandUse: [Int]] = [.residential: [0, 0, 0, 0], .commercial: [0, 0, 0, 0], .office: [0, 0, 0, 0]]
        for building in world.buildings.all {
            XCTAssertEqual(building.kind, .city, "no cell is too full for D4")
            counts[building.use]![building.density.rawValue - 1] += 1
        }
        // 64,829 cells by density, D1 to D4: no cell needs D4, as each is
        // chosen by its main count only (residents of homes, jobs of shops
        // and offices; the fullest office cell, 78 residents and 285 jobs,
        // is D3).
        XCTAssertEqual(counts[.residential], [26_392, 32_303, 2_214, 0])
        XCTAssertEqual(counts[.commercial], [1_462, 0, 0, 0])
        XCTAssertEqual(counts[.office], [390, 1_873, 195, 0])
        for cell in world.land.cells {
            let capacity = try XCTUnwrap(world.buildingCapacity(row: cell.row, column: cell.column))
            XCTAssertGreaterThanOrEqual(capacity.residents, cell.residents)
            XCTAssertGreaterThanOrEqual(capacity.jobs, cell.jobs)
        }
    }

    func testNoOneThereIsNoLand() throws {
        let grid = try Self.bundled()
        let tokyo = try XCTUnwrap(GeoAnchor(latitudeDegrees: 35.681_2, longitudeDegrees: 139.767_1))
        XCTAssertNil(LandImport.cells(population: grid, frame: Self.frame(tokyo), bounds: GameWorld.newGameBounds))
    }

    func testTheLauncherGivesARealMapItsPeople() async throws {
        let grid = try Self.bundled()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LandImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startNewGame(at: anchor)
            let seed = try XCTUnwrap(launcher.session?.world.demandEvents?.seed)
            XCTAssertEqual(launcher.session?.world.land, Land.towns(seed: seed, in: .standard), "without the app's people, towns")
            launcher.returnToStart()
            launcher.population = grid
            launcher.startNewGame(at: anchor)
            let expected = LandImport.cells(population: grid, frame: Self.frame(anchor), bounds: GameWorld.newGameBounds)
            XCTAssertEqual(launcher.session?.world.land.cells, expected)
            launcher.returnToStart()
            launcher.startNewGame()
            let blank = try XCTUnwrap(launcher.session?.world)
            XCTAssertEqual(blank.land, Land.towns(seed: try XCTUnwrap(blank.demandEvents?.seed), in: .standard), "a blank map has towns")
        }
    }

    // MARK: - On the map and in the panel

    func testTheBlankMapsPopulationLayerIsItsLand() throws {
        var land = GameWorld(bounds: .standard, economy: GameEconomy(balance: 0, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        try land.setLand([
            LandCell(row: 2, column: 3, use: .residential, residents: 41, jobs: 0),
            LandCell(row: 2, column: 4, use: .office, residents: 0, jobs: 500),
            LandCell(row: 5, column: 0, use: .commercial, residents: 1, jobs: 9),
        ])
        let tiles = LandMap.tiles(of: land.land)
        XCTAssertEqual(tiles.count, 2, "only cells with residents")
        XCTAssertEqual(tiles[0].minX, 12_288)
        XCTAssertEqual(tiles[0].minY, 8_192)
        XCTAssertEqual(tiles[0].maxX, 16_384)
        XCTAssertEqual(tiles[0].value, 41)
        // 41 residents in 0.004096 km² is 10,010 a km², the gradient's end;
        // 1 is 244, its first step.
        XCTAssertEqual(tiles[0].color, PopTravel.populationBandColor(PopTravel.populationBands - 1))
        XCTAssertEqual(tiles[1].color, PopTravel.populationBandColor(0))
    }

    func testTheStationPanelSaysWhoLivesAndWorksNearBy() throws {
        var world = GameWorld.newGame()
        let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 524_288, y: 524_288)).id
        XCTAssertEqual(world.landCatchmentText(of: station, in: .english), "Within 800 m: 50,189 residents · 33,276 jobs")
        XCTAssertEqual(world.landCatchmentText(of: station, in: .traditionalChinese), "800 公尺內：居民 50,189 人 · 就業 33,276 個")
        XCTAssertNil(world.landCatchmentText(of: StationID(rawValue: 99), in: .english))
        // Phase 6c-1: the first town's cells by their buildings' density.
        XCTAssertEqual(world.catchmentBuildingsText(of: station, in: .english), "Cells within 800 m by density: low-rise 88 · mid-rise 188 · high-rise 134 · towers 27")
        XCTAssertEqual(world.catchmentBuildingsText(of: station, in: .traditionalChinese), "800 公尺內各密度的格：低層 88 格 · 中層 188 格 · 高層 134 格 · 超高層 27 格")
        XCTAssertNil(world.catchmentBuildingsText(of: StationID(rawValue: 99), in: .english))
        try world.setLand([
            LandCell(row: 128, column: 128, use: .office, residents: 0, jobs: 5_000),
            LandCell(row: 128, column: 127, use: .residential, residents: 300, jobs: 0),
        ])
        XCTAssertEqual(world.catchmentBuildingsText(of: station, in: .english), "Cells within 800 m by density: high-rise 1 · existing stock 1")
        XCTAssertEqual(world.catchmentBuildingsText(of: station, in: .traditionalChinese), "800 公尺內各密度的格：高層 1 格 · 既有存量 1 格")
        world.setCityBuildings(false)
        XCTAssertNil(world.catchmentBuildingsText(of: station, in: .english), "no buildings, no line")
        try world.setLand([])
        XCTAssertNil(world.landCatchmentText(of: station, in: .english), "no land, no line")
    }

    /// Phase 6c-2 (ARCHITECTURE decision 75): the station panel says what
    /// town growth measured and whether full buildings rise. The version 14
    /// save measured both stations at full service and one station reached;
    /// the version 13 save, a day earlier, had measured nothing yet.
    func testTheStationPanelSaysWhetherBuildingsRise() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures")
        let measured = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: fixtures.appendingPathComponent("v14-city-growth.json"))).world
        let station = StationID(rawValue: 1)
        XCTAssertEqual(measured.cityGrowthText(of: station, in: .english), "Yesterday: 100% of trips served · 1 station reached · full buildings rise")
        XCTAssertEqual(measured.cityGrowthText(of: station, in: .traditionalChinese), "昨日：旅次服務 100% · 可達 1 站 · 滿格的建物會升級")
        let earlier = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: fixtures.appendingPathComponent("v13-city-buildings.json"))).world
        XCTAssertEqual(earlier.cityGrowthText(of: station, in: .english),
                       "Yesterday: 0% of trips served · 0 stations reached · full buildings rise at 80% served and 1 station reached")
        XCTAssertEqual(earlier.cityGrowthText(of: station, in: .traditionalChinese),
                       "昨日：旅次服務 0% · 可達 0 站 · 服務達 80% 且可達至少 1 站時，滿格的建物才會升級")
        XCTAssertNil(measured.cityGrowthText(of: StationID(rawValue: 99), in: .english))
        var off = measured
        off.setCityBuildings(false)
        XCTAssertNil(off.cityGrowthText(of: station, in: .english), "no buildings, no line")
    }
}
