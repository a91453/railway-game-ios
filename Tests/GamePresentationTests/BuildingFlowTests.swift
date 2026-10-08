import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 103: building one building after another. A tap
/// on the building shown builds it; with building on tap every tap builds;
/// a drag that starts on the building shown moves it, and the preview
/// follows; nothing is built until the player builds it.
@MainActor
final class BuildingFlowTests: XCTestCase {
    private func makeSession() throws -> GameSession {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .english)
        session.selectTool(.building)
        return session
    }

    func testATapOnTheBuildingShownBuildsIt() throws {
        let session = try makeSession()
        let site = PlanPoint(x: 5_000, y: 5_000)
        XCTAssertTrue(session.tapBuildingTool(at: site, reach: 256))
        XCTAssertTrue(session.world.placedBuildings.isEmpty, "the first tap shows it")
        XCTAssertNotNil(session.buildingPreview)

        // A tap elsewhere moves it; a tap on it builds it.
        let other = PlanPoint(x: 8_000, y: 5_000)
        session.tapBuildingTool(at: other, reach: 256)
        XCTAssertEqual(session.buildingSite, other)
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
        let inside = PlanPoint(x: other.x + PlacedBuildingKind.house.side / 2 - 1, y: other.y)
        XCTAssertTrue(session.tapBuildingTool(at: inside, reach: 256))
        XCTAssertEqual(session.world.placedBuildings.map(\.kind), [.house])
        XCTAssertNil(session.buildingSite, "built: the next tap shows the next one")
        XCTAssertEqual(session.undoCount, 1)
    }

    func testATapOnABuildingThatCannotStandThereMovesItInstead() throws {
        let session = try makeSession()
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        let overlapping = PlanPoint(x: 5_200, y: 5_000)
        session.tapBuildingTool(at: overlapping, reach: 256)
        XCTAssertNotNil(session.buildingPreview?.problem)
        session.tapBuildingTool(at: overlapping, reach: 256)
        XCTAssertEqual(session.world.placedBuildings.count, 1, "refused ground is never built on")
        XCTAssertEqual(session.buildingSite, overlapping)
    }

    func testBuildingOnTapBuildsEveryTap() throws {
        let session = try makeSession()
        session.buildingBuildsOnTap = true
        session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 256)
        session.tapBuildingTool(at: PlanPoint(x: 7_000, y: 5_000), reach: 256)
        session.tapBuildingTool(at: PlanPoint(x: 9_000, y: 5_000), reach: 256)
        XCTAssertEqual(session.world.placedBuildings.count, 3)
        XCTAssertEqual(session.undoCount, 3, "each one an edit undo takes back")
        session.tapBuildingTool(at: PlanPoint(x: 9_100, y: 5_000), reach: 256)
        XCTAssertEqual(session.world.placedBuildings.count, 3, "refused: it would stand on the last")
        XCTAssertEqual(session.message?.kind, .failure)
    }

    func testDraggingTheBuildingShownMovesIt() throws {
        let session = try makeSession()
        let site = PlanPoint(x: 5_000, y: 5_000)
        session.tapBuildingTool(at: site, reach: 256)
        XCTAssertTrue(session.buildingDragMoves(from: PlanPoint(x: 5_100, y: 4_950)))
        XCTAssertFalse(session.buildingDragMoves(from: PlanPoint(x: 9_000, y: 9_000)), "off it, a drag moves the map")

        let grab = PlanPoint(x: 5_100, y: 4_950)
        session.dragBuildingSite(from: grab, to: PlanPoint(x: 6_100, y: 5_950))
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 6_000, y: 6_000), "it moves as far as the finger")
        session.endBuildingDrag(from: grab, to: PlanPoint(x: 7_100, y: 4_950))
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 7_000, y: 5_000))
        XCTAssertTrue(session.world.placedBuildings.isEmpty, "moving builds nothing")

        session.dragBuildingSite(from: PlanPoint(x: 7_000, y: 5_000), to: PlanPoint(x: 9_000, y: 5_000))
        session.cancelBuildingDrag()
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 7_000, y: 5_000), "a cancelled drag puts it back")

        session.selectTool(.select)
        XCTAssertFalse(session.buildingDragMoves(from: PlanPoint(x: 7_000, y: 5_000)))
    }

    func testTheStartingCostIsAManagedCompanysBuildingCost() throws {
        let session = try makeSession()
        XCTAssertNil(session.buildingStartingCost(.house), "free play builds for free")
    }
}
