import Foundation
import GameCore
import GamePresentation
import XCTest

/// When GameCore has no IDs left for a kind, the session shows its refusal
/// like any other, and neither the world nor what the session selects
/// changes.
final class IDExhaustionSessionTests: XCTestCase {
    /// A world with one train, saved with both ID counters at `Int.max`
    /// (every station and train ID handed out) and loaded again.
    private func exhaustedWorld() throws -> GameWorld {
        var world = try makeWorld(balance: 1_000_000)
        try world.purchaseTrain(named: "Train 1")
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(world)) as? [String: Any])
        saved["nextStationID"] = Int.max
        saved["nextTrainID"] = Int.max
        return try JSONDecoder().decode(GameWorld.self, from: try JSONSerialization.data(withJSONObject: saved))
    }

    func testBuyingATrainWithNoIDsLeftChangesNothing() async throws {
        let world = try exhaustedWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            let selected = session.selectedTrainID

            session.purchaseTrain()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.selectedTrainID, selected)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.idsExhausted.playerMessage(in: .english)))
        }
    }

    func testBuildingAStationWithNoIDsLeftChangesNothing() async throws {
        var world = try exhaustedWorld()
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 3_072))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 7_680, y: 3_072))
        try world.buildTrackEdge(from: west, to: east)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 4_096, y: 3_072), reach: 256)
            let picked = session.networkEdgePoint
            let name = session.stationName

            session.addNetworkPlatform()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.stationName, name)
            XCTAssertEqual(session.networkEdgePoint, picked)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.idsExhausted.playerMessage(in: .english)))
        }
    }
}
