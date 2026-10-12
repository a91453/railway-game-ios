@testable import GameCore
import GamePresentation
import XCTest

/// Subsidiary businesses (ARCHITECTURE decision 173): the select tool picks
/// one of the company's buildings with a tap, the inspector shows its books,
/// its return and what selling it would bring, and its Sell button opens the
/// sale.
@MainActor
final class SubsidiarySessionTests: XCTestCase {
    /// A managed company with a department store at (10,000, 10,000)
    /// and a house at (5,000, 5,000).
    private func session(language: DisplayLanguage = .english, books: Bool = false) throws -> GameSession {
        var world = try makeWorld(width: 30_720, height: 30_720, balance: 10_000_000_000)
        world.setEconomyMode(.management)
        try world.placeBuilding(.house, at: PlanPoint(x: 5_000, y: 5_000))
        try world.placeBuilding(.departmentStore, at: PlanPoint(x: 10_000, y: 10_000))
        let session = GameSession(world: world, language: language)
        XCTAssertEqual(session.tool, .select)
        return session
    }

    /// Books a day's trade as midnight does.
    private func record(_ world: inout GameWorld, _ id: PlacedBuildingID, sales: Int64, cost: Int64, day: Int64) {
        let index = world.placedBuildings.firstIndex { $0.id == id }!
        world.placedBuildings[index].books.record(sales: Money(sales), cost: Money(cost), day: day)
    }

    func testTheSubsidiariesReadInBothLanguages() {
        XCTAssertEqual(
            [PlacedBuildingKind.departmentStore, .hotel, .amusementPark].map { $0.title(in: .traditionalChinese) }, ["百貨公司", "飯店", "遊樂園"]
        )
        XCTAssertEqual(
            [PlacedBuildingKind.departmentStore, .hotel, .amusementPark].map { $0.title(in: .english) },
            ["Department store", "Hotel", "Amusement park"]
        )
        XCTAssertEqual(LedgerItem.subsidiarySales.displayName(in: .traditionalChinese), "子公司營業收入")
        XCTAssertEqual(LedgerEntry.Kind.dailySubsidiary.displayName(in: .english), "Subsidiaries (daily)")
    }

    func testATapOnABuildingWithTheSelectToolSelectsItAndTheInspectorShowsItsBooks() throws {
        let session = try session()
        XCTAssertNil(session.selectionText())
        // Inside the store's 48 m square (3,072 units a side).
        session.tapMap(at: PlanPoint(x: 10_500, y: 9_500), reach: 400)
        XCTAssertEqual(session.selectedBuildingID, PlacedBuildingID(rawValue: 2))
        XCTAssertNil(session.selectedStationID)
        let text = try XCTUnwrap(session.selectionText())
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(lines[0].hasPrefix("Department store #2 · "), lines[0])
        XCTAssertEqual(lines[1], "This month: sales $ 0, costs $ 0, profit $ 0")
        XCTAssertEqual(lines[2], "Last month: sales $ 0, costs $ 0, profit $ 0")
        XCTAssertEqual(lines[3], "Since opening: profit $ 0")
        XCTAssertEqual(lines[4], "12-month return 0.0% of its cost")
        XCTAssertTrue(lines[5].hasPrefix("Would sell for $ "), lines[5])
        // Nothing changed in the world.
        XCTAssertEqual(session.world.placedBuildings.count, 2)
        // A tap on empty ground lets go of it.
        session.tapMap(at: PlanPoint(x: 20_000, y: 20_000), reach: 400)
        XCTAssertNil(session.selectedBuildingID)
        session.clearSelection()
        XCTAssertNil(session.selectionText())
    }

    /// Undo takes back a building the inspector shows: the selection lets
    /// go of it, so the next building, given the same ID, is not selected
    /// in its place.
    func testUndoingASelectedBuildingLetsGoOfIt() throws {
        let session = try session()
        session.selectTool(.building)
        session.buildingKind = .hotel
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 20_000, y: 20_000)))
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: 20_000, y: 20_000), reach: 400)
        XCTAssertEqual(session.selectedBuildingID, PlacedBuildingID(rawValue: 3))
        session.undo()
        XCTAssertNil(session.world.placedBuilding(id: PlacedBuildingID(rawValue: 3)))
        XCTAssertNil(session.selectedBuildingID)
        XCTAssertNil(session.selectionText())
    }

    func testTheInspectorShowsTheBooksReturnAndPriceInChinese() throws {
        var world = try makeWorld(width: 30_720, height: 30_720, balance: 10_000_000_000)
        world.setEconomyMode(.management)
        let store = try world.placeBuilding(.departmentStore, at: PlanPoint(x: 10_000, y: 10_000))
        // A month of 1,000,000 cents of sales and 400,000 of costs, closed,
        // and a day of 200,000 and 100,000 in the month in progress.
        record(&world, store.id, sales: 1_000_000, cost: 400_000, day: 3)
        record(&world, store.id, sales: 200_000, cost: 100_000, day: 31)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.tapMap(at: PlanPoint(x: 10_000, y: 10_000), reach: 400)
        let lines = try XCTUnwrap(session.selectionText()).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "本月：營收 $ 2,000、成本 $ 1,000、損益 $ 1,000")
        XCTAssertEqual(lines[2], "上月：營收 $ 10,000、成本 $ 4,000、損益 $ 6,000")
        XCTAssertEqual(lines[3], "開業以來：損益 $ 7,000")
        // 7,000 dollars over what it cost.
        let cost = store.cost.amount
        let tenths = 700_000 * 1_000 / cost
        XCTAssertEqual(lines[4], "近 12 個月報酬率 \(tenths / 10).\(tenths % 10)%（占造價）")
        XCTAssertTrue(lines[5].hasPrefix("估計售價 $ "), lines[5])
    }

    func testOtherBuildingsShowWhoIsInThem() throws {
        let session = try session()
        session.tapMap(at: PlanPoint(x: 5_000, y: 5_000), reach: 400)
        XCTAssertEqual(session.selectionText(), "House #1 · 0 of 11 people")
    }

    func testTheSellButtonOpensTheSaleOnTheSelectedBuilding() throws {
        let session = try session()
        session.tapMap(at: PlanPoint(x: 10_000, y: 10_000), reach: 400)
        session.sellSelectedBuilding()
        XCTAssertEqual(session.tool, .building)
        XCTAssertEqual(session.buildingMode, .sell)
        XCTAssertEqual(session.saleCandidate, PlacedBuildingID(rawValue: 2))
        XCTAssertNotNil(session.salePreview)
        XCTAssertTrue(session.salePreviewLines.contains { $0.hasPrefix("Price $ ") })
    }

    func testABusinessWorthMoreThanItsPropertyShowsInTheSaleCard() throws {
        var world = try makeWorld(width: 30_720, height: 30_720, balance: 10_000_000_000)
        world.setEconomyMode(.management)
        let store = try world.placeBuilding(.departmentStore, at: PlanPoint(x: 10_000, y: 10_000))
        record(&world, store.id, sales: 900_000_000, cost: 100_000_000, day: 3)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingMode = .sell
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 10_000, y: 10_000), reach: 400))
        XCTAssertTrue(session.salePreviewLines.contains("Business: 6 × its profit of the last 12 months = $ 48,000,000"), "\(session.salePreviewLines)")
        XCTAssertTrue(session.salePreviewLines.contains("Price $ 48,000,000 · on the books at $ " + (session.salePreview?.quote.bookValue.moneyText.dropFirst(2) ?? "")))
    }
}
