import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 82: Undo, ported from MapBuilder's `handleUndo`.
/// Every edit goes through `GameSession.performEdit(_:)`, which keeps the
/// whole world as it was before a successful edit, at most 25 of them (the
/// bundle's `B.I6`); Undo puts the last one back, money included. Game
/// time moving on, a new game and a loaded save leave nothing to undo.
@MainActor
final class UndoSessionTests: XCTestCase {
    private static let west = PlanPoint(x: 1_024, y: 1_024)
    private static let east = PlanPoint(x: 6_144, y: 1_024)

    /// Two stations, paused, with money for a few more and a train.
    private func makeStationWorld(speed: GameSpeed = .paused) throws -> GameWorld {
        var world = try makeWorld(balance: 20_000, speed: speed)
        try world.buildStation(named: "West", at: Self.west)
        try world.buildStation(named: "East", at: Self.east)
        return world
    }

    func testUndoPutsTheWorldBackAndRefundsTheCost() throws {
        let world = try makeStationWorld()
        let session = GameSession(world: world)
        XCTAssertFalse(session.canUndo)
        XCTAssertEqual(GameSession.undoLimit, 25, "MapBuilder's B.I6")

        session.purchaseTrain()
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - 5_000)
        XCTAssertEqual(session.undoCount, 1)
        XCTAssertTrue(session.canUndo)

        session.undo()
        XCTAssertEqual(session.world, world, "the whole world, the train's price refunded")
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Undid the last edit."))
        XCTAssertFalse(session.canUndo)

        session.undo()
        XCTAssertEqual(session.world, world)
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Nothing to undo."))
    }

    func testPerformEditReturnsTheCommandsResult() throws {
        let session = GameSession(world: try makeStationWorld(), language: .traditionalChinese)
        let station = try session.performEdit { world throws(GameError) in
            try world.buildStation(named: "North", at: PlanPoint(x: 3_072, y: 4_096))
        }
        XCTAssertEqual(session.world.station(id: station.id)?.name, "North")
        XCTAssertEqual(session.undoCount, 1)

        // An edit that changes nothing leaves nothing to undo.
        XCTAssertEqual(session.performEdit { _ in 42 }, 42)
        XCTAssertEqual(session.undoCount, 1)

        session.undo()
        XCTAssertNil(session.world.station(id: station.id))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已復原上一步編輯。"))
        session.undo()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "沒有可復原的編輯。"))
    }

    /// A refused edit changes neither the world nor the history, even when
    /// it changed part of the world before it was refused.
    func testAFailedEditLeavesNoSnapshot() throws {
        let world = try makeStationWorld()
        let session = GameSession(world: world)
        let west = try XCTUnwrap(world.stations.first?.id)

        XCTAssertThrowsError(try session.performEdit { world throws(GameError) in
            try world.renameStation(west, to: "Harbour")
            try world.renameStation(west, to: "")
        })
        XCTAssertEqual(session.world, world, "all or nothing")
        XCTAssertEqual(session.undoCount, 0)

        session.selectStation(west)
        session.renameSelectedStation(to: "")
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)
        XCTAssertFalse(session.canUndo)
    }

    /// The history keeps the latest 25 edits; the oldest go.
    func testTheHistoryKeepsTheLatestTwentyFiveEdits() throws {
        let session = GameSession(world: try makeStationWorld())
        let west = try XCTUnwrap(session.world.stations.first?.id)
        for number in 1...30 {
            try session.performEdit { world throws(GameError) in try world.renameStation(west, to: "Name \(number)") }
        }
        XCTAssertEqual(session.undoCount, 25)

        for _ in 1...25 { session.undo() }
        XCTAssertEqual(session.world.station(id: west)?.name, "Name 5", "the 25 edits before the last one's")
        XCTAssertFalse(session.canUndo)
    }

    /// One drag of the rate slider (`beginEditGesture()` …
    /// `endEditGesture()`) is one edit: however many rates it sets, one
    /// snapshot, and one Undo goes back to the rate before the drag.
    func testADragOfTheRateIsOneEdit() throws {
        var world = DemoWorld.make(in: .english)
        world.pause()
        let session = GameSession(world: world)
        let start = session.world
        let train = try XCTUnwrap(session.selectedTrain)
        XCTAssertNotNil(train.position, "the demo's trains are on the track")
        let before = train.movement.rate

        session.beginEditGesture()
        for rate: Int64 in [100, 200, 300, 400] {
            session.selectedTrainRate = rate
        }
        session.endEditGesture()
        XCTAssertEqual(session.selectedTrainRate, 400)
        XCTAssertEqual(session.undoCount, 1)

        session.undo()
        XCTAssertEqual(session.selectedTrainRate, before)
        XCTAssertEqual(session.world, start)
        XCTAssertFalse(session.canUndo)

        // Outside a drag each rate is an edit of its own.
        session.selectedTrainRate = 100
        session.selectedTrainRate = 200
        XCTAssertEqual(session.undoCount, 2)

        // A drag that sets nothing new keeps nothing.
        session.beginEditGesture()
        session.selectedTrainRate = 200
        session.endEditGesture()
        XCTAssertEqual(session.undoCount, 2)
    }

    /// Undo during a drag takes the drag back; its next change keeps a new
    /// snapshot.
    func testUndoDuringADragLetsItsNextChangeKeepASnapshot() throws {
        var world = DemoWorld.make(in: .english)
        world.pause()
        let session = GameSession(world: world)
        let before = session.selectedTrainRate

        session.beginEditGesture()
        session.selectedTrainRate = 100
        session.selectedTrainRate = 200
        session.undo()
        XCTAssertEqual(session.selectedTrainRate, before)
        session.selectedTrainRate = 300
        session.selectedTrainRate = 400
        session.endEditGesture()
        XCTAssertEqual(session.undoCount, 1)
        session.undo()
        XCTAssertEqual(session.selectedTrainRate, before)
    }

    /// Any tick of game time empties the history; pausing, the speed and the
    /// selection are not edits.
    func testGameTimeMovingOnEmptiesTheHistory() throws {
        let session = GameSession(world: try makeStationWorld(speed: .normal))
        session.purchaseTrain()
        session.setSpeed(.double)
        session.togglePause()
        session.togglePause()
        session.selectStation(try XCTUnwrap(session.world.stations.first?.id))
        session.clearSelection()
        session.selectTool(.network)
        XCTAssertEqual(session.undoCount, 1, "only the purchase was an edit")

        session.advance(realElapsed: .milliseconds(50))
        XCTAssertEqual(session.undoCount, 1, "half a tick: game time has not moved")
        session.advance(realElapsed: .milliseconds(50))
        XCTAssertEqual(session.undoCount, 0, "one tick")
        XCTAssertFalse(session.canUndo)

        // Paused, real time passes but game time does not.
        session.purchaseTrain()
        session.togglePause()
        session.advance(realElapsed: .seconds(5))
        XCTAssertEqual(session.undoCount, 1)
    }

    /// Pausing and the speed are not edits, so Undo leaves them as they are.
    func testUndoKeepsTheClocksSpeed() throws {
        let world = try makeStationWorld(speed: .normal)
        let session = GameSession(world: world)
        session.purchaseTrain()
        session.setSpeed(.double)
        session.togglePause()

        session.undo()
        XCTAssertTrue(session.world.clock.isPaused, "still paused")
        XCTAssertEqual(session.world.clock.runningSpeed, .double)
        XCTAssertEqual(session.world.trains, world.trains)
        XCTAssertEqual(session.world.economy, world.economy)
        XCTAssertEqual(session.world.clock.now, world.clock.now)
    }

    /// Undo lets go of the stations, trains, lines and track the world no
    /// longer has, and keeps the selection of what it still has.
    func testUndoDropsTheSelectionOfWhatIsGone() throws {
        let session = GameSession(world: try makeStationWorld())
        let west = try XCTUnwrap(session.world.stations.first?.id)
        session.selectStation(west)
        session.addSelectedStationToLineDraft()

        let north = try session.performEdit { world throws(GameError) in
            try world.buildStation(named: "North", at: PlanPoint(x: 3_072, y: 4_096)).id
        }
        session.selectStation(north)
        session.addSelectedStationToLineDraft()
        session.platformStationID = north
        session.createLineFromDraft()
        let line = try XCTUnwrap(session.selectedLineID)
        session.purchaseTrain()
        let train = try XCTUnwrap(session.selectedTrainID)
        XCTAssertNotNil(session.world.train(id: train))
        session.selectStation(north)
        session.addSelectedStationToLineDraft()
        XCTAssertEqual(session.lineDraft, [north])

        session.undo()
        XCTAssertNil(session.world.train(id: train))
        XCTAssertNil(session.selectedTrainID)
        XCTAssertEqual(session.selectedLineID, line, "the line is still there")
        XCTAssertEqual(session.selectedStationID, north)

        session.undo()
        XCTAssertNil(session.world.line(id: line))
        XCTAssertNil(session.selectedLineID)
        XCTAssertEqual(session.selectedStationID, north)

        session.undo()
        XCTAssertNil(session.world.station(id: north))
        XCTAssertNil(session.selectedStationID)
        XCTAssertEqual(session.selectedPoint, PlanPoint(x: 3_072, y: 4_096), "a point is not an entity")
        XCTAssertNil(session.platformStationID)
        XCTAssertEqual(session.lineDraft, [], "the station that is gone leaves the draft")
        XCTAssertFalse(session.canUndo)
    }

    /// Track picks for the next stretch let go of the nodes and edges
    /// Undo removed.
    func testUndoDropsTheNetworkPicksOfTrackThatIsGone() throws {
        let session = GameSession(world: try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000))
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 3_072), reach: 512)
        session.tapNetwork(at: PlanPoint(x: 9_216, y: 3_072), reach: 512)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 3_072), reach: 512)
        guard case .node(let node) = session.networkStart else { return XCTFail("the west end's node") }
        XCTAssertNotNil(session.world.network.node(node))
        session.setNetworkMode(.remove)
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 3_072), reach: 512)
        XCTAssertNotNil(session.networkEdgePoint)

        session.undo()
        XCTAssertTrue(session.world.network.edges.isEmpty)
        XCTAssertNil(session.networkEdgePoint)
        XCTAssertNil(session.networkStart)
    }

    /// The tutorial's steps compare the world with the IDs they saw, so
    /// Undo is off while it is on screen and back once it ends.
    func testUndoIsOffDuringTheTutorial() throws {
        let session = GameSession(world: try makeStationWorld())
        session.purchaseTrain()
        let bought = session.world
        session.startTutorial()
        XCTAssertFalse(session.canUndo)
        session.undo()
        XCTAssertEqual(session.world, bought)
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Undo is off during the tutorial."))
        XCTAssertNotNil(session.tutorial, "the tutorial goes on")

        session.skipTutorial()
        XCTAssertTrue(session.canUndo)
    }

    /// A new game, a loaded save and the start screen leave nothing to
    /// undo: the history belongs to the session and is never saved.
    func testANewGameOrALoadedSaveHasNothingToUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UndoSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        let first = try XCTUnwrap(launcher.session)
        first.togglePause()
        first.purchaseTrain()
        XCTAssertTrue(first.canUndo)
        launcher.saveCurrentGame()

        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.undoCount, 0, "a new game")
        launcher.returnToStart()
        XCTAssertNil(launcher.session)

        launcher.continueGame()
        XCTAssertEqual(launcher.session?.undoCount, 0, "the autosave continued")
        launcher.returnToStart()
        let save = try XCTUnwrap(launcher.otherSaves.first)
        launcher.load(save)
        let loaded = try XCTUnwrap(launcher.session)
        XCTAssertEqual(loaded.undoCount, 0, "a loaded save")
        XCTAssertFalse(loaded.canUndo)
    }
}
