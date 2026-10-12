import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decisions 99, 175 and 184, later (#420's review, before release): a map
/// bubble keeps its identity while its figure changes; the station master
/// is asked again only after an edit or a new game hour; a fleet list keeps
/// the order it was sorted in; a save keeps the player's speed, not an
/// automatic pause; leaving the app does not read the whole save folder.
@MainActor
final class ReleaseUIFixesTests: XCTestCase {
    // MARK: - 1. Map bubbles

    func testABubbleKeepsItsIdentityWhenItsFigureChanges() {
        let at = PlanPoint(x: 0, y: 0), there = PlanPoint(x: 5_000, y: 0)
        let station = StationID(rawValue: 1)
        XCTAssertEqual(
            MapAlert(kind: .crowded(waiting: 600), station: station, location: at).id,
            MapAlert(kind: .crowded(waiting: 640), station: station, location: at).id
        )
        XCTAssertEqual(
            MapAlert(kind: .crowded(waiting: 900), station: station, location: at).id,
            MapAlert(kind: .full(waiting: 1_000), station: station, location: at).id,
            "a crowded station that fills stays one bubble"
        )
        XCTAssertEqual(
            MapAlert(kind: .trainStuck(TrainID(rawValue: 2)), station: nil, location: at).id,
            MapAlert(kind: .trainStuck(TrainID(rawValue: 2)), station: nil, location: there).id,
            "a train's head moves"
        )
        XCTAssertEqual(
            MapAlert(kind: .insolvency(days: 9), station: station, location: at).id,
            MapAlert(kind: .insolvency(days: 8), station: station, location: at).id
        )
        XCTAssertNotEqual(
            MapAlert(kind: .crowded(waiting: 600), station: station, location: at).id,
            MapAlert(kind: .crowded(waiting: 600), station: StationID(rawValue: 2), location: at).id
        )
        XCTAssertNotEqual(
            MapAlert(kind: .lineWithoutTrains(LineID(rawValue: 1)), station: station, location: at).id,
            MapAlert(kind: .lineLosingMoney(LineID(rawValue: 1)), station: station, location: at).id
        )
    }

    // MARK: - 2. The station master

    func testTheStationMasterIsAskedAgainOnlyAfterAnEditOrANewHour() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480, speed: .normal), language: .english)
        let start = session.stationMasterRefreshKey
        session.advance(realElapsed: .milliseconds(100))
        XCTAssertGreaterThan(session.world.clock.now.seconds, 0, "a tick ran")
        XCTAssertEqual(session.stationMasterRefreshKey, start, "a tick within the hour")

        session.togglePause()
        session.buildingKind = .house
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        let built = session.stationMasterRefreshKey
        XCTAssertNotEqual(built, start, "an edit")
        session.undo()
        XCTAssertNotEqual(session.stationMasterRefreshKey, built, "an undo")
        var later = session.world
        try later.advance(ticks: 60)
        let next = GameSession(world: later, language: .english)
        XCTAssertNotEqual(next.stationMasterRefreshKey, session.stationMasterRefreshKey, "another game")
    }

    // MARK: - 3. The fleet list

    func testTheFleetKeepsTheOrderItWasSortedIn() throws {
        var world = try makeWorld(balance: 1_000_000)
        let ids = try ["A", "B", "C"].map { try world.purchaseTrain(named: $0).id }
        let kept = [ids[2], ids[0], ids[1]]
        XCTAssertEqual(world.fleet(keeping: kept).map(\.id), kept)
        let bought = try world.purchaseTrain(named: "D").id
        XCTAssertEqual(world.fleet(keeping: kept).map(\.id), kept + [bought], "a new train goes last")
        try world.sellTrain(ids[0])
        XCTAssertEqual(world.fleet(keeping: kept).map(\.id), [ids[2], ids[1], bought], "a sold one goes")
    }

    // MARK: - 4. Saving the player's speed

    func testASaveKeepsThePlayersSpeedNotAToolsPause() throws {
        let session = GameSession(world: try makeWorld(speed: .double))
        session.selectTool(.network)
        XCTAssertTrue(session.world.clock.isPaused, "the tool paused it")
        XCTAssertFalse(session.worldToSave.clock.isPaused)
        XCTAssertEqual(session.worldToSave.clock.speed, .double)
        XCTAssertEqual(session.worldToSave.clock.now, session.world.clock.now)

        // The player pauses: that pause is theirs and is kept.
        session.togglePause()
        session.togglePause()
        XCTAssertTrue(session.world.clock.isPaused)
        XCTAssertTrue(session.worldToSave.clock.isPaused)

        let running = GameSession(world: try makeWorld(speed: .normal))
        XCTAssertEqual(running.worldToSave, running.world)
    }

    func testASaveKeepsThePlayersSpeedNotAnEventsPause() throws {
        let session = GameSession(world: try NewsSessionTests.world(day: 3, balance: Money(40_000)), language: .english)
        let tick = try XCTUnwrap(session.beginLoopTick())
        let step = try GameSession.advanced(tick.world, by: 1_440, listening: false)
        XCTAssertTrue(session.finish(tick, with: .success(step)))
        XCTAssertTrue(session.world.clock.isPaused, "cash below zero paused it")
        XCTAssertTrue(session.isPausedForEvent)
        XCTAssertFalse(session.worldToSave.clock.isPaused)
        XCTAssertEqual(session.worldToSave.clock.speed, .normal)
        session.togglePause()
        XCTAssertFalse(session.isPausedForEvent, "the player's speed now")
    }

    func testTheAutosaveOnLeavingTheAppIsTheRunningGame() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReleaseUIFixes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session)
        session.selectTool(.network)
        XCTAssertTrue(session.world.clock.isPaused)
        launcher.setActive(true)
        launcher.setActive(false)
        let autosave = try XCTUnwrap(library.entries().first { $0.kind == .autosave })
        XCTAssertFalse(try library.load(autosave).clock.isPaused, "continued, it runs as the player left it")
    }

    // MARK: - 5. Leaving the app

    func testLeavingTheAppDoesNotReadTheSaveFolderAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReleaseUIFixes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        let listed = launcher.entries
        launcher.setActive(true)
        launcher.setActive(false)
        XCTAssertEqual(library.entries().filter { $0.kind == .autosave }.count, 1, "saved")
        XCTAssertEqual(launcher.entries, listed, "the list is read again on the start screen, not now")
        launcher.returnToStart()
        XCTAssertNotNil(launcher.autosave)
    }
}
