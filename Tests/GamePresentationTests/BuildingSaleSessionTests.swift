import GameCore
import GamePresentation
import XCTest

/// City building P0-D (ARCHITECTURE decision 130): the building tool's sell
/// mode chooses one of the company's buildings with a tap, shows what it
/// would bring in part by part and the gain or loss, and the action button
/// sells it to the city, as an edit Undo takes back.
@MainActor
final class BuildingSaleSessionTests: XCTestCase {
    /// A managed company with a house bought at (5,000, 5,000): 512 m² of
    /// floor at NT$120, 6,144,000 cents, and 256 m² of empty land at its
    /// base of 3,000 cents a m², 768,000 (decision 499: times 3).
    private func session(language: DisplayLanguage = .english) throws -> GameSession {
        var world = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        world.setEconomyMode(.management)
        let session = GameSession(world: world, language: language)
        session.selectTool(.building)
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        return session
    }

    func testATapChoosesTheBuildingAndTheCardShowsWhatItBrings() throws {
        let session = try session()
        session.buildingMode = .sell
        XCTAssertNil(session.salePreview)
        XCTAssertEqual(session.salePreviewLines, [])
        XCTAssertFalse(session.tapBuildingTool(at: PlanPoint(x: 15_000, y: 15_000), reach: 500))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tap one of your buildings to sell it."))
        // Within reach of the house (it ends at 5,512): chosen, not sold.
        let before = session.world
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_900, y: 5_000), reach: 500))
        XCTAssertEqual(session.saleCandidate, PlacedBuildingID(rawValue: 1))
        XCTAssertEqual(session.world, before, "a tap only chooses it")
        // Empty: 95% of the land, 243,200, and nothing for the building,
        // against the 2,304,000 it is on the books at.
        XCTAssertEqual(session.salePreview?.quote.price, 729_600)
        XCTAssertEqual(session.salePreviewLines, [
            "House #1 · 0 of 11 people (0%)",
            "Land: 95% of its right now \(Money(768_000).moneyText) = \(Money(729_600).moneyText)",
            "Building: book value \(Money(6_144_000).moneyText) × 0% (under half full) = \(Money(0).moneyText)",
            "Price \(Money(729_600).moneyText) · on the books at \(Money(6_912_000).moneyText)",
            "Realized loss \(Money(6_182_400).moneyText)",
        ])
        XCTAssertEqual(session.saleGainText, "Realized loss \(Money(6_182_400).moneyText)")
        // The map marks the building chosen.
        XCTAssertEqual(session.buildingOverlay?.site, PlanRect(session.world.placedBuildings[0]))
        XCTAssertEqual(session.buildingOverlay?.siteIsBuildable, true)
    }

    func testSellingAndUndoingIt() throws {
        let session = try session()
        session.buildingMode = .sell
        XCTAssertFalse(session.confirmSale())
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tap one of your buildings to sell it."))
        session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0)
        let before = session.world
        XCTAssertTrue(session.confirmSale())
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Sold house #1 to the city for \(Money(729_600).moneyText). Realized loss \(Money(6_182_400).moneyText)."))
        XCTAssertNil(session.saleCandidate, "sold: nothing is chosen")
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance + 729_600)
        session.undo()
        XCTAssertEqual(session.world, before, "Undo buys it back")
    }

    func testChangingModeOrToolDropsTheBuildingChosen() throws {
        let session = try session()
        session.buildingMode = .sell
        session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0)
        XCTAssertNotNil(session.saleCandidate)
        session.buildingMode = .demolish
        XCTAssertNil(session.saleCandidate)
        session.buildingMode = .sell
        session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0)
        session.selectTool(.select)
        XCTAssertNil(session.saleCandidate)
        session.selectTool(.building)
        session.buildingMode = .sell
        session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0)
        session.clearSaleCandidate()
        XCTAssertNil(session.salePreview)
    }

    func testSellingReadsInChineseAndFreePlayHandsItOver() throws {
        XCTAssertEqual(BuildingToolMode.allCases.map { $0.title(in: .traditionalChinese) }, ["建造", "拆除", "出售", "分區"])
        let session = try session(language: .traditionalChinese)
        session.buildingMode = .sell
        session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0)
        XCTAssertEqual(session.salePreviewLines.first, "小住宅 #1 · 入住 0 / 11 人（0%）")
        XCTAssertEqual(session.salePreviewLines[1], "土地：目前的土地使用權 \(Money(768_000).moneyText) × 95% = \(Money(729_600).moneyText)")
        XCTAssertTrue(session.confirmSale())
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "小住宅 #1 賣給城市，收入 \(Money(729_600).moneyText)。已實現損失 \(Money(6_182_400).moneyText)。"))

        let free = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .english)
        free.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        free.selectTool(.building)
        free.buildingMode = .sell
        free.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0)
        XCTAssertEqual(free.salePreviewLines, ["House #1 · 0 of 11 people (0%)", "Free play: the city takes it over for nothing."])
        XCTAssertNil(free.saleGainText)
        XCTAssertTrue(free.confirmSale())
        XCTAssertEqual(free.message, StatusMessage(kind: .success, text: "Handed house #1 to the city."))
    }
}
