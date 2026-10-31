import GameCore
import GamePresentation
import XCTest

/// Decision 523: amounts are New Taiwan dollars, and the English interface
/// shows a rough US dollar figure beside large ones.
final class USDollarReferenceTests: XCTestCase {
    func testAmountsAreInNewTaiwanDollars() {
        XCTAssertEqual(Money.currencySymbol, "NT" + "$")
    }

    func testTheReferenceIsThirtyNewTaiwanDollarsToTheDollarRounded() {
        XCTAssertEqual(Money(900_000_000).usDollarReferenceText(in: .english), "≈ US$300,000", "the starting cash")
        XCTAssertEqual(Money(150_000).usDollarReferenceText(in: .english), "≈ US$50")
        XCTAssertEqual(Money(148_499).usDollarReferenceText(in: .english), "≈ US$49", "under half a dollar rounds down")
        XCTAssertEqual(Money(148_500).usDollarReferenceText(in: .english), "≈ US$50", "half a dollar rounds up")
        XCTAssertEqual(Money(-148_500).usDollarReferenceText(in: .english), "≈ US$-49", "Math.round(-49.5) is -49, as moneyText rounds")
        XCTAssertEqual(Money(-148_501).usDollarReferenceText(in: .english), "≈ US$-50")
        XCTAssertEqual(Money(Int64.max).usDollarReferenceText(in: .english), "≈ US$3,074,457,345,618,259")
        XCTAssertEqual(Money(Int64.min).usDollarReferenceText(in: .english), "≈ US$-3,074,457,345,618,259")
    }

    func testSmallAmountsAndChineseHaveNoReference() {
        XCTAssertNil(Money(99_999).usDollarReferenceText(in: .english), "under NT$1,000: fares and passes")
        XCTAssertNil(Money(-99_999).usDollarReferenceText(in: .english))
        XCTAssertEqual(Money(100_000).usDollarReferenceText(in: .english), "≈ US$33")
        XCTAssertEqual(Money(-100_000).usDollarReferenceText(in: .english), "≈ US$-33")
        XCTAssertNil(Money(900_000_000).usDollarReferenceText(in: .traditionalChinese))
    }

    func testTheReferenceFollowsTheAmountInBrackets() {
        let cash = Money(900_000_000)
        XCTAssertEqual(cash.moneyTextWithReference(in: .english), "\(cash.moneyText) (≈ US$300,000)")
        XCTAssertEqual(cash.moneyTextWithReference(in: .traditionalChinese), cash.moneyText)
        XCTAssertEqual(Money(1_500).moneyTextWithReference(in: .english), Money(1_500).moneyText)
    }

    func testTheCurrencyIsSaidOnceInEnglish() {
        XCTAssertEqual(Money.currencyNoteText(in: .english), "Prices are in New Taiwan dollars (NT$); the US$ figures are a rough guide.")
        XCTAssertNil(Money.currencyNoteText(in: .traditionalChinese))
    }
}
