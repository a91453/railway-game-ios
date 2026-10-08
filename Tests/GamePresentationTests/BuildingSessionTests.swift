import GameCore
import GamePresentation
import XCTest

/// City building P0-A (ARCHITECTURE decision 92): the building tool places
/// the chosen building where the player taps, as an edit Undo takes back,
/// and says what happened.
@MainActor
final class BuildingSessionTests: XCTestCase {
    func testPlacingTheChosenBuildingAndUndoingIt() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .english)
        session.selectTool(.building)
        XCTAssertEqual(session.buildingKind, .house, "a house to begin with")
        XCTAssertEqual(session.placedBuildingsText, "0 buildings placed")

        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        XCTAssertEqual(session.world.placedBuildings.map(\.kind), [.house])
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built house #1."))
        XCTAssertEqual(session.placedBuildingsText, "1 building placed")

        session.buildingKind = .office
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 10_000, y: 10_000)))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built office block #2."))
        XCTAssertEqual(session.placedBuildingsText, "2 buildings placed")

        // GameCore refuses ground already built on, and nothing changes.
        let before = session.world
        XCTAssertFalse(session.placeBuilding(at: PlanPoint(x: 5_500, y: 5_000)))
        XCTAssertEqual(session.world, before)
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "That would stand on building #1."))

        session.undo()
        XCTAssertEqual(session.world.placedBuildings.map(\.kind), [.house])
        session.undo()
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
    }

    func testTheBuildingToolReadsInChinese() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .traditionalChinese)
        XCTAssertEqual(PlacedBuildingKind.allCases.map { $0.title(in: .traditionalChinese) }, ["小住宅", "商店", "辦公樓"])
        XCTAssertEqual(PlacedBuildingKind.allCases.map { $0.title(in: .english) }, ["House", "Shop", "Office block"])
        session.buildingKind = .shop
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "蓋好商店 #1。"))
        XCTAssertEqual(session.placedBuildingsText, "已蓋 1 棟")
        session.placeBuilding(at: PlanPoint(x: 100, y: 5_000))
        XCTAssertEqual(session.message?.kind, .failure)
    }
}
