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
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.idsExhausted.playerMessage))
        }
    }

    func testBuildingAStationWithNoIDsLeftChangesNothing() async throws {
        let world = try exhaustedWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(GridPosition(x: 2, y: 2))
            session.selectTool(.buildStation)
            let name = session.stationName

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.stationName, name)
            XCTAssertEqual(session.selection, GridPosition(x: 2, y: 2))
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.idsExhausted.playerMessage))
        }
    }
}
