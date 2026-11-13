import GameCore
import GamePresentation
import XCTest

/// Decision 660 (L15-9.2): a new game's blank map opens on the middle of
/// its first town (Mac playtest A9), where a house buys out the town's
/// offices and costs more than a new game's cash. The refusal names the
/// nearest site the cash covers, which builds.
@MainActor
final class FirstBuildingTests: XCTestCase {
    /// The middle of the map as a new game opens: its first town's middle.
    private func openingMiddle(of world: GameWorld) throws -> PlanPoint {
        let region = try XCTUnwrap(WorldRegion.opening(in: world))
        return PlanPoint(x: Int64((region.minX + region.maxX) / 2), y: Int64((region.minY + region.maxY) / 2))
    }

    func testAHouseInTheOpeningMiddleNamesASiteTheCashCovers() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = GameSession(world: GameWorld.newGame(), language: language)
            session.selectTool(.building)
            XCTAssertEqual(session.buildingKind, .house)
            let middle = try openingMiddle(of: session.world)
            XCTAssertTrue(session.tapBuildingTool(at: middle, reach: 100))
            let preview = try XCTUnwrap(session.buildingPreview)
            // The town's middle is dearer than a new game's cash.
            XCTAssertEqual(preview.cost, Money(940_492_800))
            XCTAssertEqual(session.world.economy.balance, Money(900_000_000))
            let cheaper = try XCTUnwrap(preview.cheaperSite, "\(language): no cheaper site is named")
            // Decision 727: 2,304,000 more than before (256 m² × 9,000 a
            // m²), its land raised to the mean of the town's cells round it.
            XCTAssertEqual(cheaper.cost, Money(12_422_400))
            XCTAssertEqual(cheaper.centre, PlanPoint(x: middle.x - 3 * Land.cellLength, y: middle.y - 3 * Land.cellLength))
            let cost = Money(940_492_800).moneyText, cash = Money(900_000_000).moneyText, cheap = Money(12_422_400).moneyText
            XCTAssertEqual(session.buildingPreviewText, language.text(
                "Not enough cash to put up this building: it costs \(cost) and you have \(cash). About 270 m north-west it costs \(cheap).",
                "餘額不足，無法蓋這棟建物：需要 \(cost)，目前只有 \(cash)。往西北約 270 公尺只要 \(cheap)。"
            ))

            // The site named builds, at the price named.
            XCTAssertTrue(session.tapBuildingTool(at: cheaper.centre, reach: 100))
            XCTAssertNil(session.buildingPreview?.problem)
            XCTAssertEqual(session.buildingPreview?.cost, cheaper.cost)
            XCTAssertTrue(session.confirmBuilding())
            XCTAssertEqual(session.world.placedBuildings.count, 1)
            XCTAssertEqual(session.world.economy.balance, Money(900_000_000 - 12_422_400))
        }
    }

    /// A site the cash covers names nothing, and nor does a refusal that
    /// no other site would mend (free play's free building has none).
    func testNothingIsNamedWhereTheCashCoversIt() throws {
        let session = GameSession(world: GameWorld.newGame(), language: .english)
        session.selectTool(.building)
        let middle = try openingMiddle(of: session.world)
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: middle.x + 4 * Land.cellLength, y: middle.y), reach: 100))
        XCTAssertNil(session.buildingPreview?.problem)
        XCTAssertNil(session.buildingPreview?.cheaperSite)
    }
}
