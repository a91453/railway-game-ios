import Foundation
import GameCore
import GamePresentation
import XCTest

/// Who lives where on real-world maps in Taiwan (WorldPop's 1 km grid,
/// `Resources/RealWorld/taiwan_population.json`), and the ridership a
/// managed company's new station there gets from it.
final class PopulationGridTests: XCTestCase {
    private static func bundled() throws -> PopulationGrid {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
    }

    /// Taipei Main Station (`Railway/`'s TRA station point).
    private static let taipei = (latitude: 25.047882, longitude: 121.517219)

    // MARK: - The grid

    func testTheBundledGridHoldsTaiwan() throws {
        let grid = try Self.bundled()
        // WorldPop's 2025 estimate, every cell rounded to whole people.
        XCTAssertEqual(grid.total, 23_163_504)
        let taipei = try XCTUnwrap(grid.people(within: 800, ofLatitude: Self.taipei.latitude, longitude: Self.taipei.longitude))
        XCTAssertTrue((40_000 ... 50_000).contains(taipei), "\(taipei) people within 800 m of Taipei Main Station")
        // Pingxi, a village: a few hundred.
        let pingxi = try XCTUnwrap(grid.people(within: 800, ofLatitude: 25.025_7, longitude: 121.738_1))
        XCTAssertTrue((100 ... 1_000).contains(pingxi), "\(pingxi) people around Pingxi")
    }

    /// Empty land in Taiwan has no one; a place the grid does not reach
    /// (no one within 5 km) is not covered at all.
    func testEmptyLandHasNoOneAndOtherCountriesAreNotCovered() throws {
        let grid = try Self.bundled()
        XCTAssertEqual(grid.people(within: 800, ofLatitude: 23.47, longitude: 120.957), 0, "Yushan's peak")
        XCTAssertNil(grid.people(within: 800, ofLatitude: 35.681_2, longitude: 139.767_1), "Tokyo")
        XCTAssertNil(grid.people(within: 800, ofLatitude: 22.302_7, longitude: 114.177_2), "Hong Kong, west of the grid")
        XCTAssertNil(grid.people(within: 800, ofLatitude: 24.2, longitude: 120.0), "the Taiwan Strait")
    }

    func testAGridOutOfShapeIsRefused() {
        XCTAssertThrowsError(try PopulationGrid(data: Data("{}".utf8)))
        XCTAssertThrowsError(try PopulationGrid(data: Data(#"{"north":26,"west":116,"cellDegrees":0,"runs":[]}"#.utf8)))
        XCTAssertThrowsError(try PopulationGrid(data: Data(#"{"north":26,"west":116,"cellDegrees":0.1,"runs":[{"r":0,"c":0,"p":[-1]}]}"#.utf8)))
    }

    /// Every cell counts by the share of the circle in it: a grid of one
    /// person per square metre has π·r² people within r.
    func testACircleCountsTheCellsUnderIt() throws {
        // 0.1° cells, each holding a person per square metre at the
        // equator-ish latitude of the middle row.
        let cells = 0.1 * 110_574.0 * 0.1 * 111_320.0 * cos(0.05 * .pi / 180)
        let file = #"{"north":0.1,"west":0,"cellDegrees":0.1,"runs":[{"r":0,"c":0,"p":[\#(Int(cells.rounded()))]}]}"#
        let grid = try PopulationGrid(data: Data(file.utf8))
        let people = try XCTUnwrap(grid.people(within: 800, ofLatitude: 0.05, longitude: 0.05))
        XCTAssertEqual(Double(people), Double.pi * 800 * 800, accuracy: 2, "a person a square metre")
    }

    func testCellsQueryReturnsNonEmptyCellsInBoundingBox() throws {
        let grid = try Self.bundled()
        // Query around Taipei Main Station (~25.047°N, ~121.517°E) with +/- 0.05° bounding box
        let cells = grid.cells(north: 25.10, south: 25.00, west: 121.45, east: 121.55)
        XCTAssertFalse(cells.isEmpty, "Taipei bounding box must contain population cells")
        for cell in cells {
            XCTAssertGreaterThan(cell.count, 0, "All returned cells must have positive population count")
            XCTAssertGreaterThan(cell.northLatitude, 25.00)
            XCTAssertLessThan(cell.southLatitude, 25.10)
            XCTAssertLessThan(cell.westLongitude, 121.55)
            XCTAssertGreaterThan(cell.eastLongitude, 121.45)
        }
    }

    func testCellsQueryClipsToIntersectingCellsAndAcceptsReversedLimits() throws {
        let grid = try Self.overlayFixture()
        let cells = grid.cells(north: 0.9, south: 0.6, west: 0.1, east: 0.4)
        XCTAssertEqual(cells.map(\.count), [100], "A rectangle inside one cell must not include its neighbours")
        XCTAssertEqual(grid.cells(north: 0.6, south: 0.9, west: 0.4, east: 0.1), cells)
        XCTAssertEqual(grid.cells(north: 1, south: 0.5, west: 0, east: 0.5).map(\.count), [100],
                       "Touching the next row or column at an edge is not an area overlap")
        XCTAssertEqual(grid.cells(north: 0.8, south: 0.2, west: 0.2, east: 0.8).map(\.count), [100, 200, 300, 400])
    }

    func testCellsQueryOutsideTheGridReturnsNone() throws {
        let grid = try Self.overlayFixture()
        for box in [(2.0, 1.1, 0.1, 0.4), (0.9, 0.6, -0.4, -0.1),
                    (-0.1, -0.4, 0.1, 0.4), (0.9, 0.6, 1.1, 1.4)] {
            XCTAssertTrue(grid.cells(north: box.0, south: box.1, west: box.2, east: box.3).isEmpty)
        }
    }

    func testCellsQueryHandlesEmptyNonFiniteAndVeryLargeRectangles() throws {
        let grid = try Self.overlayFixture()
        XCTAssertTrue(grid.cells(north: 0.9, south: 0.9, west: 0.1, east: 0.4).isEmpty)
        XCTAssertTrue(grid.cells(north: 0.9, south: 0.6, west: 0.1, east: 0.1).isEmpty)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertTrue(grid.cells(north: invalid, south: 0, west: 0, east: 1).isEmpty)
            XCTAssertTrue(grid.cells(north: 1, south: invalid, west: 0, east: 1).isEmpty)
            XCTAssertTrue(grid.cells(north: 1, south: 0, west: invalid, east: 1).isEmpty)
            XCTAssertTrue(grid.cells(north: 1, south: 0, west: 0, east: invalid).isEmpty)
        }
        let extent = Double.greatestFiniteMagnitude
        XCTAssertEqual(grid.cells(north: extent, south: -extent, west: -extent, east: extent).map(\.count), [100, 200, 300, 400])
        let empty = try PopulationGrid(data: Data(#"{"north":1,"west":0,"cellDegrees":0.5,"runs":[]}"#.utf8))
        XCTAssertTrue(empty.cells(north: 1, south: 0, west: 0, east: 1).isEmpty)
    }

    /// A place off any real grid (a world anchored at a pole puts its
    /// points at longitudes far beyond ±180°) or not a number has no one,
    /// rather than trapping when it is turned into a cell.
    func testAPlaceOffTheEarthHasNoOneAndNeverTraps() throws {
        let grid = try Self.overlayFixture()
        for (latitude, longitude) in [(0.5, 1e20), (1e20, 0.5), (-1e300, -1e300), (.nan, 0.5), (0.5, .infinity)] {
            XCTAssertNil(grid.people(within: 800, ofLatitude: latitude, longitude: longitude), "\(latitude), \(longitude)")
        }
        XCTAssertNotNil(grid.people(within: 800, ofLatitude: 0.75, longitude: 0.25))
    }

    private static func overlayFixture() throws -> PopulationGrid {
        try PopulationGrid(data: Data(#"{"north":1,"west":0,"cellDegrees":0.5,"runs":[{"r":0,"c":0,"p":[100,200]},{"r":1,"c":0,"p":[300,400]}]}"#.utf8))
    }

    // MARK: - Ridership

    func testRidershipIsFortyTripsForEveryHundredResidents() {
        XCTAssertEqual(StationDemand.realWorld(residents: 44_604), StationDemand(kind: .residential, dailyTrips: 17_800))
        XCTAssertEqual(StationDemand.realWorld(residents: 78_663).dailyTrips, 31_500)
        XCTAssertEqual(StationDemand.realWorld(residents: 386).dailyTrips, 200, "154 to the nearest 100")
        XCTAssertEqual(StationDemand.realWorld(residents: 0).dailyTrips, 100, "at least 100")
        XCTAssertEqual(StationDemand.realWorld(residents: 10_000_000).dailyTrips, StationDemand.maximumDailyTrips)
    }

    // MARK: - The frame

    func testAWorldPointGoesBackToItsPlaceOnTheEarth() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        for place in [(25.047_882, 121.517_219), (25.1, 121.45), (24.98, 121.6)] {
            let point = frame.worldPosition(latitude: place.0, longitude: place.1)
            let back = frame.coordinate(worldX: point.x, worldY: point.y)
            XCTAssertEqual(back.latitude, place.0, accuracy: 1e-9)
            XCTAssertEqual(back.longitude, place.1, accuracy: 1e-9)
        }
        let middle = frame.coordinate(worldX: frame.middleX, worldY: frame.middleY)
        XCTAssertEqual(middle.latitude, anchor.latitudeDegrees, accuracy: 1e-9)
        XCTAssertEqual(middle.longitude, anchor.longitudeDegrees, accuracy: 1e-9)
    }

    // MARK: - New stations

    /// A managed company's station on a real-world map in Taiwan gets the
    /// ridership of the people around it; on a blank map, outside the
    /// grid, or without the grid, the city's.
    func testANewStationOnARealWorldMapHasItsNeighbourhoodsRidership() async throws {
        let grid = try Self.bundled()
        let taipei = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let tokyo = try XCTUnwrap(GeoAnchor(latitudeDegrees: 35.681_2, longitudeDegrees: 139.767_1))
        func world(anchor: GeoAnchor?) throws -> GameWorld {
            var world = GameWorld.newGame(anchor: anchor)
            // A stretch of track through the middle of the map.
            let west = try world.buildTrackNode(at: WorldCoordinate(x: 520_192, y: 524_288))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: 528_384, y: 524_288))
            try world.buildTrackEdge(from: west, to: east)
            return world
        }
        let cases: [(GeoAnchor?, PopulationGrid?, Bool)] = [
            (taipei, grid, true), (nil, grid, false), (tokyo, grid, false), (taipei, nil, false),
        ]
        for (anchor, population, fromGrid) in cases {
            let start = try world(anchor: anchor)
            try await MainActor.run {
                let session = GameSession(world: start)
                session.population = population
                session.selectTool(.network)
                session.setNetworkMode(.platform)
                session.tapNetwork(at: PlanPoint(x: 524_288, y: 524_288), reach: 512)
                session.addNetworkPlatform()
                let station = try XCTUnwrap(session.world.stations.first)
                let demand = try XCTUnwrap(session.world.stationDemand(of: station.id))
                guard fromGrid else {
                    XCTAssertEqual(demand, .cityDefault, "\(String(describing: anchor))")
                    return
                }
                let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
                let place = frame.coordinate(worldX: Double(station.point.x), worldY: Double(station.point.y))
                XCTAssertEqual(place.latitude, Self.taipei.latitude, accuracy: 0.001, "the station is by the anchor")
                let residents = try XCTUnwrap(grid.people(within: 800, ofLatitude: place.latitude, longitude: place.longitude))
                XCTAssertEqual(demand, .realWorld(residents: residents))
                XCTAssertNotEqual(demand, .cityDefault)
                XCTAssertTrue((15_000 ... 20_000).contains(demand.dailyTrips), "\(demand.dailyTrips) trips a day by Taipei Main Station")
            }
        }
    }

    func testStationCatchmentPopulationWithAndWithoutData() async throws {
        let grid = try Self.bundled()
        let taipei = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let tokyo = try XCTUnwrap(GeoAnchor(latitudeDegrees: 35.681_2, longitudeDegrees: 139.767_1))

        func makeWorldWithStation(anchor: GeoAnchor?) throws -> GameWorld {
            var world = GameWorld.newGame(anchor: anchor)
            let west = try world.buildTrackNode(at: WorldCoordinate(x: 520_192, y: 524_288))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: 528_384, y: 524_288))
            try world.buildTrackEdge(from: west, to: east)
            return world
        }

        // 1. With data: Real-world map in Taipei with bundled grid
        let taipeiWorld = try makeWorldWithStation(anchor: taipei)
        try await MainActor.run {
            let session = GameSession(world: taipeiWorld)
            session.population = grid
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 524_288, y: 524_288), reach: 512)
            session.addNetworkPlatform()
            let station = try XCTUnwrap(session.world.stations.first)

            let catchment = session.stationCatchmentPopulation(of: station.id)
            let people = try XCTUnwrap(catchment)
            XCTAssertTrue((40_000 ... 50_000).contains(people), "Catchment population around Taipei station should be 40k-50k")

            // Unknown station ID returns nil
            XCTAssertNil(session.stationCatchmentPopulation(of: StationID(rawValue: 9999)))
        }

        // 2. Without data: Population grid is nil
        try await MainActor.run {
            let session = GameSession(world: taipeiWorld)
            session.population = nil
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 524_288, y: 524_288), reach: 512)
            session.addNetworkPlatform()
            let station = try XCTUnwrap(session.world.stations.first)

            XCTAssertNil(session.stationCatchmentPopulation(of: station.id), "Should be nil when session.population is nil")
        }

        // 3. Without data: Not a real-world map (no anchor)
        let nonRealWorld = try makeWorldWithStation(anchor: nil)
        try await MainActor.run {
            let session = GameSession(world: nonRealWorld)
            session.population = grid
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 524_288, y: 524_288), reach: 512)
            session.addNetworkPlatform()
            let station = try XCTUnwrap(session.world.stations.first)

            XCTAssertNil(session.stationCatchmentPopulation(of: station.id), "Should be nil when world has no real-world frame")
        }

        // 4. Without data: Real-world map outside population grid coverage (Tokyo)
        let tokyoWorld = try makeWorldWithStation(anchor: tokyo)
        try await MainActor.run {
            let session = GameSession(world: tokyoWorld)
            session.population = grid
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 524_288, y: 524_288), reach: 512)
            session.addNetworkPlatform()
            let station = try XCTUnwrap(session.world.stations.first)

            XCTAssertNil(session.stationCatchmentPopulation(of: station.id), "Should be nil when outside grid coverage")
        }
    }
}
