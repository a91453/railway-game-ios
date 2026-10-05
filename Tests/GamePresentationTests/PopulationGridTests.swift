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
}
