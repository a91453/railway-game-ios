import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 292 (City Transport Manager study, step M1): the share of the
/// residents and jobs within 800 m of a station, as the coverage layer
/// counts them, on a small map and on Taipei's; and when the coverage
/// layer's switch is offered.
@MainActor
final class CoverageSummaryTests: XCTestCase {
    /// 32 × 24 cells, as `CityMapTests`: 6,156 people round column 5 of
    /// row 5, and 9 at row 20, column 30, 2 km and more away.
    private func world(stations: [PlanPoint] = [PlanPoint(x: 5 * 4_096 + 2_048, y: 5 * 4_096 + 2_048)]) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        try world.setLand([
            LandCell(row: 5, column: 4, use: .residential, residents: 56, jobs: 0),
            LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 0, jobs: 1_000),
            LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 5_000),
            LandCell(row: 20, column: 30, use: .residential, residents: 9, jobs: 0),
        ])
        for (index, point) in stations.enumerated() {
            try world.buildStation(named: "S\(index)", at: point)
        }
        return world
    }

    func testTheShareOfResidentsAndJobsAStationReaches() throws {
        let summary = try world().catchmentCoverage()
        XCTAssertEqual(summary, CoverageSummary(people: 6_165, covered: 6_156))
        XCTAssertEqual(summary.percent, 99, "rounded down: 100% only when everyone is reached")
        XCTAssertEqual(summary.text(in: .traditionalChinese), "車站 800 公尺內的居民與工作：99%（直線範圍的估算）")
        XCTAssertEqual(summary.text(in: .english), "Residents and jobs within 800 m of a station: 99% (straight-line estimate)")
        // The layer counts the same cells.
        XCTAssertEqual(CityMap(world: try world()).coverage, summary)
    }

    /// Two stations whose catchments overlap reach the same people once.
    func testOverlappingCatchmentsCountOnce() throws {
        let both = try world(stations: [
            PlanPoint(x: 5 * 4_096 + 2_048, y: 5 * 4_096 + 2_048),
            PlanPoint(x: 6 * 4_096 + 2_048, y: 5 * 4_096 + 2_048),
        ])
        XCTAssertEqual(both.catchmentCoverage(), CoverageSummary(people: 6_165, covered: 6_156))
    }

    /// A closed station reaches no one (decision 77); no station, no one.
    func testOnlyOpenStationsCount() throws {
        var world = try world()
        try world.setStationOperationMode(world.stations[0].id, to: .closed)
        XCTAssertEqual(world.catchmentCoverage(), CoverageSummary(people: 6_165, covered: 0))
        XCTAssertEqual(world.catchmentCoverage().text(in: .english), "Residents and jobs within 800 m of a station: 0% (straight-line estimate)")
        XCTAssertEqual(try self.world(stations: []).catchmentCoverage().percent, 0)
    }

    /// No land: "—", not a made-up 0%. A sliver: "under 1%".
    func testNoLandSaysADashAndASliverIsNotZero() throws {
        var world = GameWorld(bounds: try WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        try world.buildStation(named: "Alone", at: PlanPoint(x: 20_480, y: 20_480))
        let empty = world.catchmentCoverage()
        XCTAssertNil(empty.percent)
        XCTAssertEqual(empty.text(in: .traditionalChinese), "車站 800 公尺內的居民與工作：—（直線範圍的估算）")
        XCTAssertEqual(empty.shareText(in: .english), "—")

        let sliver = CoverageSummary(people: 1_000, covered: 3)
        XCTAssertEqual(sliver.shareText(in: .english), "under 1%")
        XCTAssertEqual(sliver.shareText(in: .traditionalChinese), "不到 1%")
        XCTAssertEqual(CoverageSummary(people: 4, covered: 4).shareText(in: .english), "100%")
    }

    /// Taipei's new game with its real land (as `CityMapTests` reads it):
    /// three stations reach some of it, a fourth no fewer, and the layer
    /// counts the same.
    func testTaipeisRealLand() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        let places = try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219))
        let cells = try XCTUnwrap(LandImport.cells(
            population: population, places: places, frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds
        ))
        var world = GameWorld.newGame(anchor: anchor, land: cells)
        XCTAssertEqual(world.catchmentCoverage().percent, 0, "no station yet, no one reached")
        for (index, dx) in [Int64(-30_000), 0, 30_000].enumerated() {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: 524_288 + dx, y: 524_288))
        }
        let three = world.catchmentCoverage()
        XCTAssertGreaterThan(three.people, 0)
        XCTAssertGreaterThan(three.covered, 0)
        let percent = try XCTUnwrap(three.percent)
        XCTAssertTrue((1...99).contains(percent), "\(percent)%")
        XCTAssertEqual(CityMap(world: world).coverage, three)
        try world.buildStation(named: "S3", at: PlanPoint(x: 524_288, y: 524_288 + 60_000))
        XCTAssertGreaterThanOrEqual(world.catchmentCoverage().covered, three.covered)
        XCTAssertEqual(world.catchmentCoverage().people, three.people)
    }

    // MARK: - The switch

    // Decision 311 replaced the switch with `BuildingLayerShortcut`
    // (`StationPotentialMapTests`).

    func testTheSwitchIsOfferedWhileBuildingTrackPlatformsOrALine() throws {
        let session = GameSession(world: try world(), language: .english)
        XCTAssertFalse(session.offersCoverageShortcut)
        session.selectTool(.network)
        session.setNetworkMode(.build)
        XCTAssertTrue(session.offersCoverageShortcut)
        session.setNetworkMode(.platform)
        XCTAssertTrue(session.offersCoverageShortcut)
        session.setNetworkMode(.remove)
        XCTAssertFalse(session.offersCoverageShortcut)
        session.selectTool(.select)
        session.startPickingLineStops(announces: false)
        XCTAssertTrue(session.offersCoverageShortcut)
        session.clearLineDraft()
        XCTAssertFalse(session.offersCoverageShortcut)
    }
}
