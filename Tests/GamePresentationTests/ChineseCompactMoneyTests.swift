import GameCore
import GamePresentation
import XCTest

/// Decision 523, continued: the Chinese interface writes large amounts in
/// 萬 and 億 where room is short or the figure is large (the status bar,
/// the economy panel's balance, a build's price, the new game's starting
/// cash); English keeps NT$ with every dollar and its ≈ US$ reference.
final class ChineseCompactMoneyTests: XCTestCase {
    private let sign = Money.currencySymbol

    private func zh(_ dollars: Int64) -> String {
        Money(dollars * 100).compactText(in: .traditionalChinese)
    }

    func testUnderTenThousandEveryDollarShows() {
        XCTAssertEqual(zh(0), Money(0).moneyText)
        XCTAssertEqual(zh(9_999), Money(999_900).moneyText)
        XCTAssertEqual(zh(-9_999), Money(-999_900).moneyText)
        XCTAssertEqual(Money(999_949).compactText(in: .traditionalChinese), Money(999_949).moneyText, "9,999.49 rounds to 9,999")
    }

    func testTenThousandUpIsInWanToOneDecimal() {
        XCTAssertEqual(zh(10_000), "\(sign) 1 萬")
        XCTAssertEqual(zh(12_345), "\(sign) 1.2 萬")
        XCTAssertEqual(zh(12_550), "\(sign) 1.3 萬", "half a thousand rounds up")
        XCTAssertEqual(zh(9_000_000), "\(sign) 900 萬", "the starting cash")
        XCTAssertEqual(zh(12_345_678), "\(sign) 1,234.6 萬")
        XCTAssertEqual(zh(-4_047_400), "\(sign) -404.7 萬")
        XCTAssertEqual(zh(99_999_499), "\(sign) 9,999.9 萬")
    }

    func testOneYiUpIsInYiToTwoDecimals() {
        XCTAssertEqual(zh(99_999_500), "\(sign) 1 億", "rounds up to 10,000 萬, written as 1 億")
        XCTAssertEqual(zh(100_000_000), "\(sign) 1 億")
        XCTAssertEqual(zh(123_456_789), "\(sign) 1.23 億")
        XCTAssertEqual(zh(120_000_000), "\(sign) 1.2 億")
        XCTAssertEqual(zh(-2_500_000_000), "\(sign) -25 億")
        XCTAssertEqual(Money(Int64.max).compactText(in: .traditionalChinese), "\(sign) 922,337,203.69 億")
        XCTAssertEqual(Money(Int64.min).compactText(in: .traditionalChinese), "\(sign) -922,337,203.69 億")
    }

    func testEnglishKeepsEveryDollar() {
        XCTAssertEqual(Money(900_000_000).compactText(in: .english), Money(900_000_000).moneyText)
        XCTAssertEqual(
            Money(900_000_000).compactTextWithReference(in: .english),
            Money(900_000_000).moneyTextWithReference(in: .english)
        )
        XCTAssertEqual(Money(900_000_000).compactTextWithReference(in: .traditionalChinese), "\(sign) 900 萬")
    }

    func testTheCashAndItsUnlimitedFunds() {
        let economy = GameEconomy(balance: Money(900_000_000))
        XCTAssertEqual(economy.cashText(in: .traditionalChinese), "\(sign) 900 萬")
        XCTAssertEqual(economy.cashText(in: .english), economy.cashText)
    }

    func testTheIncomeFloat() {
        XCTAssertEqual(IncomePulse(amount: Money(123_400), serial: 1).text(in: .traditionalChinese), "+" + Money(123_400).moneyText)
        XCTAssertEqual(IncomePulse(amount: Money(1_234_500), serial: 1).text(in: .traditionalChinese), "+\(sign) 1.2 萬")
        XCTAssertEqual(IncomePulse(amount: Money(-4_000_000), serial: 1).text(in: .traditionalChinese), "\u{2212}\(sign) 4 萬")
        XCTAssertEqual(IncomePulse(amount: Money(-250_000), serial: 1).text(in: .traditionalChinese), "\u{2212}\(sign) 2,500")
        let loss = IncomePulse(amount: Money(-4_000_000), serial: 1)
        XCTAssertEqual(loss.text(in: .english), loss.text)
    }

    /// Decision 251: the status bar keeps the room of the widest 萬 for
    /// every balance under 1 億, and passing 1 億 never narrows it.
    func testTheStatusBarKeepsOneWidthInWan() {
        let wan = StatusBarWidths.moneyText(Money(0), in: .traditionalChinese)
        XCTAssertEqual(wan, "\(sign) -8,888.8 萬")
        for dollars: Int64 in [0, 5, -1_428, 120_000, 9_000_000, -9_999_999, 99_999_499] {
            let shown = zh(dollars)
            XCTAssertEqual(StatusBarWidths.moneyText(Money(dollars * 100), in: .traditionalChinese), wan)
            XCTAssertTrue(wan.count >= shown.count, shown)
        }
        let yi = StatusBarWidths.moneyText(Money(99_999_500 * 100), in: .traditionalChinese)
        XCTAssertEqual(yi, "\(sign) -8,888.88 億")
        XCTAssertGreaterThan(yi.count, wan.count)
        XCTAssertEqual(StatusBarWidths.moneyText(Money(-987_654_321_000 * 100), in: .traditionalChinese), yi)
        XCTAssertEqual(StatusBarWidths.moneyText(Money(1_234_567_890_000 * 100), in: .traditionalChinese), "\(sign) -88,888.88 億")
        let widest = Money(Int64.max).compactText(in: .traditionalChinese)
        XCTAssertTrue(StatusBarWidths.moneyText(Money(Int64.max), in: .traditionalChinese).count >= widest.count + 1)
    }
}
