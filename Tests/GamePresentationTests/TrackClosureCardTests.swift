import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 716, continued: the select tool's track card closes the picked
/// track from switch to switch, all of it together, and opens it again, as
/// one command the log keeps and undo takes back.
@MainActor
final class TrackClosureCardTests: XCTestCase {
    /// A west track in two pieces (edges 1 and 2) to a switch, and two
    /// branches from it (edges 3 and 4). Paused.
    private func session() throws -> GameSession {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        let points: [(Int64, Int64)] = [(1_024, 4_096), (4_096, 4_096), (8_192, 4_096), (14_336, 4_096), (14_336, 6_144)]
        let nodes = try points.map { try world.buildTrackNode(at: WorldCoordinate(x: $0.0, y: $0.1)) }
        try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        try world.buildTrackEdge(from: nodes[2], to: nodes[3])
        try world.buildTrackEdge(from: nodes[2], to: nodes[4])
        return GameSession(world: world, language: .english)
    }

    private func pick(_ x: Int64, _ y: Int64 = 4_096, in session: GameSession) {
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: x, y: y), reach: 256)
    }

    func testTheCardClosesTheRunToTheSwitchAndOpensIt() throws {
        let session = try session()
        XCTAssertFalse(session.canCloseSelectedTrack, "no track picked")
        pick(2_048, in: session)
        XCTAssertEqual(session.selectedTrackEdge, .edge(1))
        XCTAssertTrue(session.canCloseSelectedTrack)
        XCTAssertFalse(session.isSelectedTrackClosed)

        session.toggleSelectedTrackClosure()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.closedTrack, [.edge(1), .edge(2)], "both pieces before the switch, not the branches")
        XCTAssertTrue(session.isSelectedTrackClosed)
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(.edit(.closeTrack(edges: [1, 2]))))

        // Picked at its other piece, it is the same closed run.
        pick(6_144, in: session)
        XCTAssertEqual(session.selectedTrackEdge, .edge(2))
        XCTAssertTrue(session.isSelectedTrackClosed)
        session.toggleSelectedTrackClosure()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.closedTrack, [])
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(.edit(.openTrack(edges: [1, 2]))))

        // Undo takes the opening back, then the closing.
        session.undo()
        XCTAssertEqual(session.world.closedTrack, [.edge(1), .edge(2)])
        session.undo()
        XCTAssertEqual(session.world.closedTrack, [])
    }

    // Decision 716, continued: before, a train on any piece refused the
    // whole run; now the whole run is being closed until it has left.
    func testATrainOnAnyPieceKeepsTheWholeRunClosingUntilItLeaves() throws {
        let session = try session()
        let train = try session.performEdit { world throws(GameError) in
            let id = try world.purchaseTrain(named: "T").id
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(2), direction: .forward), offset: 2_048))
            return id
        }
        pick(2_048, in: session)
        XCTAssertEqual(session.selectedTrackEdge, .edge(1))
        XCTAssertEqual(session.selectedTrackClosure, .open)
        let before = session.world
        session.toggleSelectedTrackClosure()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.message?.text, "Closing once trains have passed. No new trains are sent this way.")
        XCTAssertEqual(session.world.closingTrack, [.edge(1), .edge(2)], "edge 1 is not closed alone, ahead of the train")
        XCTAssertEqual(session.world.closedTrack, [])
        XCTAssertEqual(session.selectedTrackClosure, .closing)
        XCTAssertFalse(session.isSelectedTrackClosed)
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(.edit(.closeTrack(edges: [1, 2]))))
        XCTAssertEqual(session.commandLog.entries.last?.refused, false)

        // The card calls it off: open as it was.
        session.toggleSelectedTrackClosure()
        XCTAssertEqual(session.message?.text, "Closing called off. The track stays open.")
        XCTAssertEqual(session.world, before)
        XCTAssertEqual(session.selectedTrackClosure, .open)
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(.edit(.openTrack(edges: [1, 2]))))

        // Closing again, and the train sent out onto a branch: once it has
        // left, the run is closed and the card says so.
        session.toggleSelectedTrackClosure()
        XCTAssertEqual(session.selectedTrackClosure, .closing)
        _ = try session.performEdit { world throws(GameError) in
            try world.setTrainMovementRate(train, to: 1_024)
            try world.setTrainContinuation(train, along: [TrackTraversal(edge: .edge(3), direction: .forward)], stoppingAt: 5_120)
        }
        _ = try session.performEdit { world throws(GameError) in
            world.setSpeed(.normal)
            try world.advance(ticks: 10)
        }
        XCTAssertEqual(session.world.closedTrack, [.edge(1), .edge(2)])
        XCTAssertEqual(session.world.closingTrack, [])
        XCTAssertEqual(session.selectedTrackClosure, .closed)
        XCTAssertTrue(session.isSelectedTrackClosed)

        // A branch no train is on closes at once.
        pick(11_264, 5_120, in: session)
        if session.selectedTrackEdge == .edge(4) {
            session.toggleSelectedTrackClosure()
            XCTAssertEqual(session.message?.text, "Track closed. Trains go another way or wait.")
            XCTAssertEqual(session.world.closedTrack, [.edge(1), .edge(2), .edge(4)])
        } else {
            XCTFail("the lower branch was not picked: \(String(describing: session.selectedTrackEdge))")
        }
    }

    func testTheCommandsKeepTheirFormThroughTheLog() throws {
        for edit in [PlayerCommand.Edit.closeTrack(edges: [1, 2]), .openTrack(edges: [7])] {
            let data = try JSONEncoder().encode(PlayerCommand.edit(edit))
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), .edit(edit))
        }
    }
}
