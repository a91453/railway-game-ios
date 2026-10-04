import GameCore
import GamePresentation
import XCTest

/// What the action button does with each tool, whatever the world (Stage
/// F3c: the grid's track, station and remove tools are gone, and these
/// rules moved here from their tests).
final class ToolActionTests: XCTestCase {
    private static let point = PlanPoint(x: 3_584, y: 2_560)

    func testActionsNeedASelectionAndDoNothingInSelectOrNetworkMode() async throws {
        var world = try makeWorld()
        try world.purchaseTrain(named: "T1")
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.applyTool()
            XCTAssertEqual(session.world, world, "nothing selected")
            XCTAssertNil(session.message)

            session.tapMap(at: Self.point, reach: 0)
            for tool in [ConstructionTool.select, .network] {
                session.selectTool(tool)
                session.applyTool()
                XCTAssertEqual(session.world, world, "\(tool) does nothing with the button")
                XCTAssertNil(session.message)
            }
        }
    }

    func testSelectingAnotherPointOrToolClearsTheMessage() async throws {
        var world = try makeWorld()
        try world.purchaseTrain(named: "T1")
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.tapMap(at: Self.point, reach: 0)

            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select a station to place T1 at."))
            session.tapMap(at: Self.point, reach: 0)
            XCTAssertNotNil(session.message, "tapping the same point keeps the message")
            session.tapMap(at: PlanPoint(x: 512, y: 512), reach: 0)
            XCTAssertNil(session.message)

            session.applyTool()
            session.selectTool(.select)
            XCTAssertNil(session.message)

            session.selectTool(.train)
            session.applyTool()
            session.dismissMessage()
            XCTAssertNil(session.message)
        }
    }
}
