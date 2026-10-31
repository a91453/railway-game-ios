import GameCore
@testable import GamePresentation
import XCTest

/// Decision 509: zoning has a button of its own in the building tools, the
/// station master points at empty land beside a growing station, the city's
/// first building on land the player zoned is told once, and "Town
/// Planner" counts the zoned cells the city built on.
@MainActor
final class ZoningToolTests: XCTestCase {
    /// A world 32 × 24 cells of 64 m.
    private func world() throws -> GameWorld {
        try makeWorld(width: 131_072, height: 98_304)
    }

    /// The middle of cell (`row`, `column`).
    private func middle(_ row: Int, _ column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
    }

    func testZoningStandsAfterBuildingsAndBeforeBuses() throws {
        let session = GameSession(world: try world(), language: .traditionalChinese)
        XCTAssertEqual(session.buildToolbarButtons, [.network, .train, .building, .zoning, .bus])
        XCTAssertEqual(session.buildToolbarButtons.map { $0.title(in: .traditionalChinese) }, ["路網", "列車", "建物", "分區", "公車"])
        XCTAssertEqual(session.buildToolbarButtons.map(\.identifier), ["tool.network", "tool.train", "tool.building", "tool.zoning", "tool.bus"])
        XCTAssertEqual(BuildingToolMode.buildingModes, [.build, .demolish, .sell], "the building tool no longer offers zoning")
    }

    func testZoningIsTheBuildingToolsZoningMode() throws {
        let session = GameSession(world: try world(), language: .english)
        session.choose(.zoning)
        XCTAssertEqual(session.tool, .building)
        XCTAssertEqual(session.buildingMode, .zone)
        XCTAssertTrue(session.isChosen(.zoning))
        XCTAssertFalse(session.isChosen(.building))

        session.choose(.building)
        XCTAssertEqual(session.buildingMode, .build, "Buildings leaves zoning")
        XCTAssertTrue(session.isChosen(.building))
        XCTAssertFalse(session.isChosen(.zoning))

        session.buildingMode = .sell
        session.choose(.building)
        XCTAssertEqual(session.buildingMode, .sell, "Buildings again keeps its mode")
        session.choose(.network)
        XCTAssertTrue(session.isChosen(.network))
        XCTAssertFalse(session.isChosen(.building))
        XCTAssertFalse(session.isChosen(.zoning))
    }

    func testEmptyLandBesideAStationIsCountedUntilThePlayerZonesThere() throws {
        var world = try world()
        let station = middle(12, 16)
        let empty = try XCTUnwrap(StationMasterAdvice.emptyCellsToZone(near: station, in: world))
        // 400 m round the middle of a 64 m cell: some 120 cells.
        XCTAssertGreaterThan(empty, 100)
        XCTAssertLessThan(empty, 140)

        // Land someone lives on is not empty.
        try world.setLand([LandCell(row: 12, column: 16, use: .residential, residents: 40, jobs: 0)])
        XCTAssertEqual(StationMasterAdvice.emptyCellsToZone(near: station, in: world), empty - 1)
        // Kept free of the city is not empty either, and plans nothing.
        _ = try world.setZone(.noDevelopment, rows: 12...12, columns: 17...17)
        XCTAssertEqual(StationMasterAdvice.emptyCellsToZone(near: station, in: world), empty - 2)
        // A cell zoned for a use: the player plans here already.
        _ = try world.setZone(.office, rows: 10...10, columns: 16...16)
        XCTAssertNil(StationMasterAdvice.emptyCellsToZone(near: station, in: world))
        // One far away does not count.
        _ = try world.setZone(nil, rows: 10...10, columns: 16...16)
        _ = try world.setZone(.office, rows: 0...0, columns: 0...0)
        XCTAssertEqual(StationMasterAdvice.emptyCellsToZone(near: station, in: world), empty - 2)
    }

    func testWhatTheStationMasterSaysOfEmptyLand() {
        let advice = StationMasterAdvice.zoneNearStation(station: StationID(rawValue: 1), name: "Alpha", cells: 30)
        XCTAssertEqual(
            advice.text(in: .english),
            "The town round Alpha is growing, with empty land beside it. Tap here to zone it and choose what the town builds there."
        )
        XCTAssertEqual(advice.text(in: .traditionalChinese), "「Alpha」附近的城市正在成長，旁邊還有空地。點這裡劃分區，決定城市在那裡蓋什麼。")
        XCTAssertFalse(advice.isWorry)
    }

    func testTheStationMastersTapOpensZoningAtTheStation() throws {
        var world = try world()
        let station = try world.buildStation(named: "Alpha", at: middle(12, 16)).id
        let session = GameSession(world: world, language: .english)
        session.zoningZone = nil
        session.zone(near: station)
        XCTAssertEqual(session.tool, .building)
        XCTAssertTrue(session.isChosen(.zoning))
        XCTAssertEqual(session.zoningZone, .residential, "homes, not clearing")
        session.zoningZone = .office
        session.zone(near: station)
        XCTAssertEqual(session.zoningZone, .office, "a use chosen stays")
    }

    func testZoningEmptyCellsWaitsForTheCityToBuild() throws {
        var world = try world()
        try world.setLand([LandCell(row: 2, column: 2, use: .residential, residents: 40, jobs: 0)])
        world.setCityBuildings(true)
        XCTAssertNotNil(world.buildings.building(row: 2, column: 2))
        let session = GameSession(world: world, language: .english)
        session.choose(.zoning)
        session.zoningZone = .residential
        XCTAssertTrue(session.zone(CellRectangle(rows: 2...3, columns: 2...2)))
        XCTAssertEqual(session.zonedCellsAwaitingBuilding, [CellPosition(row: 3, column: 2)], "only the empty one")
        session.zoningZone = .noDevelopment
        XCTAssertTrue(session.zone(CellRectangle(rows: 3...3, columns: 2...2)))
        XCTAssertEqual(session.zonedCellsAwaitingBuilding, [], "kept free, the city builds nothing to tell")
    }

    func testTheCitysFirstBuildingOnZonedLandIsToldOnce() throws {
        var world = try world()
        _ = try world.setZone(.residential, rows: 2...2, columns: 2...3)
        try world.setLand([LandCell(row: 2, column: 3, use: .residential, residents: 40, jobs: 0)])
        world.setCityBuildings(true)
        let built = try XCTUnwrap(GameSession.firstBuilt(on: [CellPosition(row: 2, column: 2), CellPosition(row: 2, column: 3)], in: world))
        XCTAssertEqual(built.cell, CellPosition(row: 2, column: 3))
        XCTAssertEqual(built.zone, .residential)
        XCTAssertNil(GameSession.firstBuilt(on: [CellPosition(row: 2, column: 2)], in: world))

        let session = GameSession(world: world, language: .traditionalChinese)
        session.zonedCellsAwaitingBuilding = [CellPosition(row: 2, column: 2)]
        session.noteZonedCellsBuiltOn()
        XCTAssertEqual(session.zonedCellsAwaitingBuilding, [CellPosition(row: 2, column: 2)], "still waiting")
        let before = session.news.items.count

        session.zonedCellsAwaitingBuilding = [CellPosition(row: 2, column: 2), CellPosition(row: 2, column: 3)]
        session.noteZonedCellsBuiltOn()
        XCTAssertEqual(session.zonedCellsAwaitingBuilding, [], "told once")
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "你劃的分區蓋起第一棟建物了：住宅區。"))
        XCTAssertEqual(session.news.items.count, before + 1, "one news item, not the message again")
        let item = try XCTUnwrap(session.news.items.first)
        XCTAssertEqual(item.category, .growth)
        XCTAssertEqual(item.text(in: .english), "The town has put up its first building on land you zoned: Homes.")

        // A zone taken back is forgotten.
        session.zonedCellsAwaitingBuilding = [CellPosition(row: 5, column: 5)]
        session.noteZonedCellsBuiltOn()
        XCTAssertEqual(session.zonedCellsAwaitingBuilding, [])
    }

    func testTownPlannerCountsZonedCellsBuiltForTheirZone() throws {
        var world = try world()
        _ = try world.setZone(.residential, rows: 2...2, columns: 2...3)
        _ = try world.setZone(.office, rows: 4...4, columns: 2...2)
        try world.setLand([
            LandCell(row: 2, column: 2, use: .residential, residents: 40, jobs: 0),
            LandCell(row: 4, column: 2, use: .residential, residents: 40, jobs: 0),
            LandCell(row: 6, column: 2, use: .residential, residents: 40, jobs: 0),
        ])
        world.setCityBuildings(true)
        // Homes on zoned homes count; homes on offices' land and unzoned
        // homes do not.
        XCTAssertEqual(AchievementFacts(world: world).zonedCellsBuilt, 1)
        let planner = try XCTUnwrap(Achievement.named("cityPlanner"))
        var facts = AchievementFacts()
        facts.zonedCellsBuilt = 9
        XCTAssertFalse(planner.isMet(by: facts))
        facts.zonedCellsBuilt = 10
        XCTAssertTrue(planner.isMet(by: facts))
        XCTAssertEqual(planner.title(in: .traditionalChinese), "都市計畫")
    }
}
