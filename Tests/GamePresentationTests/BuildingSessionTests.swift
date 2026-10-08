import GameCore
import GamePresentation
import XCTest

/// City building P0-A (ARCHITECTURE decision 92): the building tool places
/// the chosen building where the player taps, as an edit Undo takes back,
/// and says what happened. P0-C1 (decision 94): a managed company pays for
/// it and can demolish it.
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

    func testAManagedCompanyIsToldWhatItPaysAndCanDemolish() throws {
        var world = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        world.setEconomyMode(.management)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        XCTAssertEqual(session.buildingMode, .build)
        // A house: 512 m² of floor at $40, and 256 m² of empty land at
        // $10 a m² (its base value).
        XCTAssertEqual(session.buildingQuoteText, "House: $ 20,480 to build, plus the land's value for 256 m²")
        XCTAssertNil(session.buildingEconomyText, "nothing built yet")

        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 500))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built house #1 for $ 23,040."))
        XCTAssertEqual(session.world.economy.balance, 100_000_000 - 2_304_000)
        // Empty, so no rent; upkeep 2 bp of 2,048,000 is 410 cents, tax
        // 1 bp of 256,000 is 26.
        XCTAssertEqual(session.buildingEconomyText, "Rent $ 0.00 a day · upkeep and land tax $ 4.36")

        // Demolishing: a tap on it or within reach of it (the house is
        // 1,024 units across, so it ends at 5,512); a tenth of what it cost.
        session.buildingMode = .demolish
        let before = session.world
        XCTAssertFalse(session.tapBuildingTool(at: PlanPoint(x: 9_000, y: 9_000), reach: 500))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tap one of your buildings to demolish it."))
        XCTAssertEqual(session.world, before)
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_900, y: 5_000), reach: 500))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Demolished house #1 for $ 2,304."))
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
        XCTAssertEqual(session.world.economy.balance, 100_000_000 - 2_304_000 - 230_400)
        XCTAssertNil(session.buildingEconomyText)

        session.undo()
        XCTAssertEqual(session.world, before, "Undo puts it back")
        XCTAssertFalse(session.demolishBuilding(PlacedBuildingID(rawValue: 9)))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "There is no building #9."))
    }

    func testDemolishingInFreePlayIsFreeAndReadsInChinese() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .traditionalChinese)
        XCTAssertEqual(BuildingToolMode.allCases.map { $0.title(in: .traditionalChinese) }, ["建造", "拆除"])
        XCTAssertNil(session.buildingQuoteText, "free play builds for nothing")
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "蓋好小住宅 #1。"))
        XCTAssertNil(session.buildingEconomyText)
        session.buildingMode = .demolish
        XCTAssertFalse(session.tapBuildingTool(at: PlanPoint(x: 15_000, y: 15_000), reach: 0))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "請點選要拆除的建物。"))
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "拆除小住宅 #1。"))
        XCTAssertEqual(session.world.economy.balance, 10_000, "free")
    }
}
