import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 200: what the screens say of a game with unlimited funds: the
/// cash reads "∞" and is never in the red, nothing is refused for want of
/// money, the save list shows "∞", and the month's report has no cash to
/// compare.
final class UnlimitedFundsTextTests: XCTestCase {
    func testTheCashReadsInfinityAndIsNeverInTheRed() {
        var economy = GameWorld.newGame(balance: -5_000).economy
        XCTAssertEqual(economy.cashText, "$ -50")
        XCTAssertTrue(economy.showsInTheRed)
        var world = GameWorld.newGame(balance: -5_000)
        world.setUnlimitedFunds(true)
        economy = world.economy
        XCTAssertEqual(economy.cashText, "∞")
        XCTAssertFalse(economy.showsInTheRed)
        XCTAssertTrue(economy.canAfford(Money(.max)))
        XCTAssertEqual(GameEconomy.uncountedText(in: .traditionalChinese), "資金無限的局不計成就與公司評等。")
    }

    func testTheSaveListShowsInfinity() throws {
        var world = GameWorld.newGame()
        let paying = SaveSummary(world: world)
        XCTAssertEqual(paying.text(in: .english), "Day 1 · 00:00 · $ 3,000,000 · 0 stations · 0 lines · 0 trains")
        let encoded = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(paying)) as? [String: Any])
        XCTAssertNil(encoded["unlimitedFunds"], "written only when on")
        world.setUnlimitedFunds(true)
        let unlimited = SaveSummary(world: world)
        XCTAssertEqual(unlimited.unlimitedFunds, true)
        XCTAssertEqual(unlimited.text(in: .traditionalChinese), "第 1 日 · 00:00 · ∞ · 0 座車站 · 0 條路線 · 0 列列車")
        XCTAssertTrue(unlimited.dateAndFundsText(in: .traditionalChinese).hasSuffix(" · 資金 ∞"))
        XCTAssertEqual(try JSONDecoder().decode(SaveSummary.self, from: JSONEncoder().encode(unlimited)), unlimited)
    }
}
