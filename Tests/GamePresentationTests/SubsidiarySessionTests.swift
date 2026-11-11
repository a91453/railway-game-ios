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
        XCTAssertEqual(lines[1], "This month: sales \(Money(0).moneyText), costs \(Money(0).moneyText), profit \(Money(0).moneyText)")
        XCTAssertEqual(lines[2], "Last month: sales \(Money(0).moneyText), costs \(Money(0).moneyText), profit \(Money(0).moneyText)")
        XCTAssertEqual(lines[3], "Since opening: profit \(Money(0).moneyText)")
        XCTAssertEqual(lines[4], "12-month return 0.0% of its cost")
        XCTAssertTrue(lines[5].hasPrefix("Would sell for \(Money.currencySymbol) "), lines[5])
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
        XCTAssertEqual(lines[1], "本月：營收 \(Money(200_000).moneyText)、成本 \(Money(100_000).moneyText)、損益 \(Money(100_000).moneyText)")
        XCTAssertEqual(lines[2], "上月：營收 \(Money(1_000_000).moneyText)、成本 \(Money(400_000).moneyText)、損益 \(Money(600_000).moneyText)")
        XCTAssertEqual(lines[3], "開業以來：損益 \(Money(700_000).moneyText)")
        // 7,000 dollars over what it cost.
        let cost = store.cost.amount
        let tenths = 700_000 * 1_000 / cost
        XCTAssertEqual(lines[4], "近 12 個月報酬率 \(tenths / 10).\(tenths % 10)%（占造價）")
        XCTAssertTrue(lines[5].hasPrefix("估計售價 \(Money.currencySymbol) "), lines[5])
    }

    func testOtherBuildingsShowWhoIsInThem() throws {
        let session = try session()
        session.tapMap(at: PlanPoint(x: 5_000, y: 5_000), reach: 400)
        // Decision 692: every building of a managed company shows what it
        // would sell for beside what it cost. An empty house sells for 95%
        // of its land alone.
        let house = try XCTUnwrap(session.world.placedBuilding(id: PlacedBuildingID(rawValue: 1)))
        let price = try XCTUnwrap(session.world.saleQuote(of: house.id)).price
        XCTAssertLessThan(price, house.cost)
        let tenths = (house.cost.amount - price.amount) * 1_000 / house.cost.amount
        XCTAssertEqual(
            session.selectionText(),
            "House #1 · 0 of 11 people\nWould sell for \(price.moneyText) · paid \(house.cost.moneyText) (down \(tenths / 10).\(tenths % 10)%)"
        )
        // Free play keeps no accounts: nothing was paid and nothing comes in.
        var world = session.world
        world.setEconomyMode(.free)
        let free = GameSession(world: world, language: .english)
        free.tapMap(at: PlanPoint(x: 5_000, y: 5_000), reach: 400)
        XCTAssertEqual(free.selectionText(), "House #1 · 0 of 11 people")
    }

    func testTheChangeFromWhatWasPaidReadsUpOrDownInTenthsOfAPercent() throws {
        let english = try session(), chinese = try session(language: .traditionalChinese)
        XCTAssertEqual(english.changeText(from: Money(1_000), to: Money(1_125)), " (up 12.5%)")
        XCTAssertEqual(chinese.changeText(from: Money(1_000), to: Money(1_125)), "（漲 12.5%）")
        XCTAssertEqual(english.changeText(from: Money(1_000), to: Money(3_400)), " (up 240.0%)")
        XCTAssertEqual(english.changeText(from: Money(1_000), to: Money(118)), " (down 88.2%)")
        XCTAssertEqual(chinese.changeText(from: Money(1_000), to: Money(118)), "（跌 88.2%）")
        XCTAssertEqual(english.changeText(from: Money(1_000), to: Money(1_000)), " (up 0.0%)")
        // Free play pays nothing: nothing to compare with.
        XCTAssertEqual(english.changeText(from: .zero, to: Money(500)), "")
    }

    func testTheInspectorAndTheSaleCardSayHowFarThePriceIsAboveWhatWasPaid() throws {
        var world = try makeWorld(width: 30_720, height: 30_720, balance: 10_000_000_000)
        world.setEconomyMode(.management)
        let store = try world.placeBuilding(.departmentStore, at: PlanPoint(x: 10_000, y: 10_000))
        record(&world, store.id, sales: 900_000_000, cost: 100_000_000, day: 3)
        // Its business sells for what building it anew costs.
        let price = try XCTUnwrap(world.saleQuote(of: store.id)).price
        XCTAssertGreaterThanOrEqual(price, store.cost)
        let tenths = (price.amount - store.cost.amount) * 1_000 / store.cost.amount
        let change = "\(tenths / 10).\(tenths % 10)%"
        let session = GameSession(world: world, language: .traditionalChinese)
        session.tapMap(at: PlanPoint(x: 10_000, y: 10_000), reach: 400)
        let lines = try XCTUnwrap(session.selectionText()).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[5], "估計售價 \(price.moneyText) · 買價 \(store.cost.moneyText)（漲 \(change)）")
        session.sellSelectedBuilding()
        XCTAssertEqual(session.salePreviewLines.dropLast().last, "買價 \(store.cost.moneyText)（漲 \(change)）")
        let english = GameSession(world: world, language: .english)
        english.tapMap(at: PlanPoint(x: 10_000, y: 10_000), reach: 400)
        XCTAssertEqual(english.selectionText()?.split(separator: "\n").last.map(String.init), "Would sell for \(price.moneyText) · paid \(store.cost.moneyText) (up \(change))")
    }

    func testTheSellButtonOpensTheSaleOnTheSelectedBuilding() throws {
        let session = try session()
        session.tapMap(at: PlanPoint(x: 10_000, y: 10_000), reach: 400)
        session.sellSelectedBuilding()
        XCTAssertEqual(session.tool, .building)
        XCTAssertEqual(session.buildingMode, .sell)
        XCTAssertEqual(session.saleCandidate, PlacedBuildingID(rawValue: 2))
        XCTAssertNotNil(session.salePreview)
        XCTAssertTrue(session.salePreviewLines.contains { $0.hasPrefix("Price \(Money.currencySymbol) ") })
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
        // Decision 692: six times its profit is more than building it
        // anew costs, so it sells for that.
        let quote = try XCTUnwrap(session.salePreview?.quote)
        XCTAssertTrue(quote.businessCapped)
        let anew = (store.buildingCost + quote.landRight).moneyText
        XCTAssertTrue(session.salePreviewLines.contains("Business: trading well, it sells for what building it anew costs now = \(anew)"), "\(session.salePreviewLines)")
        XCTAssertTrue(session.salePreviewLines.contains("Price \(anew) · on the books at \(quote.bookValue.moneyText)"))
        XCTAssertTrue(session.salePreviewLines.contains("Paid \(store.cost.moneyText)\(session.changeText(from: store.cost, to: quote.price))"), "\(session.salePreviewLines)")
        // One that earns less shows the multiple.
        var modest = try makeWorld(width: 30_720, height: 30_720, balance: 10_000_000_000)
        modest.setEconomyMode(.management)
        let small = try modest.placeBuilding(.departmentStore, at: PlanPoint(x: 10_000, y: 10_000))
        let profit = (small.buildingCost.amount - 6) / 6
        record(&modest, small.id, sales: profit, cost: 0, day: 3)
        let other = GameSession(world: modest, language: .traditionalChinese)
        other.selectTool(.building)
        other.buildingMode = .sell
        XCTAssertTrue(other.tapBuildingTool(at: PlanPoint(x: 10_000, y: 10_000), reach: 400))
        XCTAssertTrue(other.salePreviewLines.contains("營業價值：近 12 個月營業利益 × 6 = \(Money(6 * profit).moneyText)"), "\(other.salePreviewLines)")
    }
}
