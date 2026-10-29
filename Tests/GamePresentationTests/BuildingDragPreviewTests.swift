import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 488 (95.1: a shop dragged over the real map, the game paused,
/// dropped to 11–50 fps): the building tool's preview is worked out once
/// for each site of a drag however many times the views read it, the same
/// as worked out afresh, and again when the world changes.
@MainActor
final class BuildingDragPreviewTests: XCTestCase {
    private func session() throws -> GameSession {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 3)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .shop
        return session
    }

    func testADragWorksThePreviewOutOnceAStep() throws {
        let session = try session()
        let start = PlanPoint(x: 18_000, y: 22_528)
        session.tapBuildingTool(at: start, reach: 0)
        XCTAssertTrue(session.buildingDragMoves(from: start))
        let before = session.buildingPreviewWorkedOut
        let steps = 12
        for step in 1...steps {
            session.dragBuildingSite(from: start, to: PlanPoint(x: start.x + Int64(step) * 512, y: start.y))
            // What the map, the card and its button read at each step.
            for _ in 0..<5 {
                _ = session.buildingOverlay
                _ = session.buildingPreviewText
                _ = session.buildingPreview?.cost
            }
            let site = try XCTUnwrap(session.buildingSite)
            XCTAssertEqual(session.buildingPreview, session.workOutBuildingPreview(at: site), "step \(step)")
        }
        XCTAssertEqual(session.buildingPreviewWorkedOut - before, steps, "once a step")
        // The drag crossed the home's cell: some steps buy it out, some stand clear.
        session.endBuildingDrag(from: start, to: PlanPoint(x: start.x + Int64(steps) * 512, y: start.y))
        XCTAssertNotNil(session.buildingPreview?.cost)
    }

    func testThePreviewFollowsTheWorldTheKindAndTheLook() throws {
        let session = try session()
        session.tapBuildingTool(at: PlanPoint(x: 40_000, y: 40_000), reach: 0)
        let shop = try XCTUnwrap(session.buildingPreview)
        XCTAssertEqual(shop.kind, .shop)
        session.buildingKind = .park
        XCTAssertEqual(session.buildingPreview?.kind, .park)
        let garden = session.buildingPreview
        session.buildingLook = 1
        XCTAssertEqual(session.buildingPreview, session.workOutBuildingPreview(at: PlanPoint(x: 40_000, y: 40_000)))
        XCTAssertNotNil(garden)
        // A building put up beside it: the site is now in its way.
        session.buildingKind = .shop
        XCTAssertNil(session.buildingPreview?.problem)
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 40_500, y: 40_000)))
        session.tapBuildingTool(at: PlanPoint(x: 40_000, y: 40_000), reach: 0)
        XCTAssertEqual(session.buildingPreview?.problem, "That would stand on another building.")
        // Out of the building tool, none.
        session.selectTool(.select)
        XCTAssertNil(session.buildingPreview)
    }
}
