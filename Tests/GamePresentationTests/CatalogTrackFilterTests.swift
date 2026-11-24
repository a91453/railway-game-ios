import GameCore
@testable import GamePresentation
import XCTest

/// CATALOG-TRACK-FILTER (REVIEW-L34 P2-1, P3-5; decision 955's later
/// note): the full-screen train types opened for a line (a train's card on
/// a line, the line's refit, its staffing) list only the types its track
/// carries, as the line's menus do; and the fleet gives a train only the
/// lines its track carries it on.
final class CatalogTrackFilterTests: XCTestCase {
    private static let guided: Set<TrainType> = [.monorail, .maglev, .skyRail]

    /// A two-stop line along one edge of `system`, mountain track or not.
    private func line(on system: TrackSystem, mountain: Bool = false) throws -> (world: GameWorld, line: LineID) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 100_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b, mountain: mountain, system: system)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 14_336, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 10_240, to: 14_336)
        let line = try world.createLine(named: "Line", stops: [west, east]).id
        return (world, line)
    }

    @MainActor
    func testALineOnAGuidewayListsOnlyItsTrain() throws {
        let beam = try line(on: .straddle)
        let catalog = RollingStockCatalog(world: beam.world, line: beam.line)
        XCTAssertEqual(catalog.entries.map(\.type), [.monorail])
        XCTAssertEqual(catalog.families, [RollingStockCatalog.Family(.monorail)])
        XCTAssertEqual(catalog.firstOpen, .monorail)
        XCTAssertFalse(catalog.carriesStandardCar)
        XCTAssertEqual(catalog.trackNote(in: .traditionalChinese), "只列這條線的軌道跑得了的車種。")
        XCTAssertEqual(
            catalog.listed(family: nil, order: .price, cars: 4, affordableOnly: false, in: beam.world).map(\.type),
            [.monorail]
        )
        // As the line's own menus list it (decision 955).
        let session = GameSession(world: beam.world)
        XCTAssertEqual(catalog.entries.map(\.type), session.trainTypeCardChoices(forLine: beam.line).map(\.id))
    }

    func testALineOnOrdinaryTrackListsNoGuidewayTrain() throws {
        let rails = try line(on: .conventional)
        let catalog = RollingStockCatalog(world: rails.world, line: rails.line)
        XCTAssertFalse(catalog.entries.isEmpty)
        XCTAssertTrue(catalog.entries.allSatisfy { !Self.guided.contains($0.type) })
        XCTAssertEqual(
            Set(catalog.entries.map(\.type)),
            Set(rails.world.offeredTrainTypes.filter { !Self.guided.contains($0) })
        )
        XCTAssertTrue(catalog.carriesStandardCar)
        XCTAssertEqual(catalog.trackNote(in: .english), "Only the types this line's track carries are listed.")
        XCTAssertEqual(catalog.emptyListText(in: .english), "No train type the company can pay for now.")
    }

    func testALineOnMountainTrackListsOnlyMountainTrains() throws {
        let hill = try line(on: .conventional, mountain: true)
        let catalog = RollingStockCatalog(world: hill.world, line: hill.line)
        XCTAssertFalse(catalog.entries.isEmpty)
        XCTAssertTrue(catalog.entries.allSatisfy(\.type.climbsMountains))
        XCTAssertFalse(catalog.carriesStandardCar)
    }

    func testWithNoLineEveryTypeIsListed() throws {
        let rails = try line(on: .conventional)
        let catalog = RollingStockCatalog(world: rails.world)
        XCTAssertEqual(catalog, RollingStockCatalog(world: rails.world, line: nil))
        XCTAssertEqual(Set(catalog.entries.map(\.type)), Set(rails.world.offeredTrainTypes))
        XCTAssertTrue(catalog.carriesStandardCar)
        XCTAssertNil(catalog.trackNote(in: .english))
        XCTAssertEqual(catalog.emptyListText(in: .traditionalChinese), "目前沒有買得起的車種。")
    }

    /// A guideway no offered train runs on (an era whose only type is the
    /// steam train) lists nothing, and says why.
    func testAnEmptyListSaysTheTrackCarriesNothing() throws {
        let beam = try line(on: .maglev)
        var world = beam.world
        world.setEconomyMode(.management)
        try world.startScenario(Scenario(
            id: "test", goals: [.dailyRiders(1)], goldDays: 10, silverDays: 20, deadlineDays: 30, trainTypes: [.steam]
        ))
        let catalog = RollingStockCatalog(world: world, line: beam.line)
        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertEqual(catalog.emptyListText(in: .english), "No train type runs on this line's track.")
        XCTAssertEqual(catalog.emptyListText(in: .traditionalChinese), "沒有車種跑得了這條線的軌道。")
    }

    /// REVIEW-L34 P3-5: the fleet's "Assign to line…" lists only the lines
    /// whose track carries the train.
    @MainActor
    func testTheFleetOffersOnlyTheLinesATrainRunsOn() throws {
        var (world, beamLine) = try line(on: .straddle)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 12_288))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 12_288))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let north = try world.buildStation(named: "North", at: PlanPoint(x: 3_072, y: 12_800)).id
        let south = try world.buildStation(named: "South", at: PlanPoint(x: 14_336, y: 12_800)).id
        try world.addTrackPlatform(north, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(south, on: edge, from: 10_240, to: 14_336)
        let railLine = try world.createLine(named: "Rails", stops: [north, south]).id
        let monorail = try world.purchaseTrain(named: "Mono", as: .monorail).id
        let standard = try world.purchaseTrain(named: "Plain").id
        let session = GameSession(world: world)
        XCTAssertEqual(session.assignToLineChoices(for: monorail).map(\.id), [beamLine])
        XCTAssertEqual(session.assignToLineChoices(for: standard).map(\.id), [railLine])
        XCTAssertTrue(session.offersAssignToLine(for: monorail))
        XCTAssertEqual(session.assignToLineChoices(for: TrainID(rawValue: 9_999)), [], "no such train")
    }
}
