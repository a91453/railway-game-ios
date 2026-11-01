import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Every amount of money the game shows is written by `Money`'s format
/// functions (``Money/moneyText``, ``Money/wholeText``, ``Money/centsText``,
/// ``Money/signedText``, ``TrainRoster/shortMoney(_:in:)``), and the tests
/// expect what those functions write, so the currency changes in one place
/// (the New Taiwan dollar, docs/research/NT_DOLLAR_SWITCH_2026-10-27.md
/// §5.2 PR-0).
final class MoneyTextSourceTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// A `$` that begins an amount or names the currency: followed by a
    /// space, an interpolation, the end of a string, an amount ("$12",
    /// "$5,000", "$4k") or punctuation. A closure's `$0` is none of these.
    private static let currency = try! NSRegularExpression(
        pattern: #"\$( |\\\(|"|[0-9][0-9]|[0-9],[0-9]{3}|[0-9]+[kM]\b|[；）)，。])"#
    )

    /// Lines that may keep a `$` of their own, with why.
    private static let allowed = [
        // The one place the sign is written.
        "public static let currencySymbol = \"NT$\"",
        // The US dollar reference beside large amounts, and the sentence
        // that names both currencies (decision 523).
        "return \"≈\\u{00A0}US$\" + dollars.groupedText",
        "Prices are in New Taiwan dollars (NT$); the US$ figures are a rough guide.",
        // A String Catalog key (Localizable.xcstrings), changed with its
        // translation when the currency changes (decision 523).
        "Land value: NT$ a square metre, higher near good train service",
    ]

    private func linesWithCurrency(in directory: String, matching pattern: NSRegularExpression) throws -> [String] {
        let base = Self.root.appendingPathComponent(directory)
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: base.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted()
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: base.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !Self.allowed.contains(where: { line.contains($0) }) else { continue }
                if pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    found.append("\(directory)/\(file):\(index + 1): \(code)")
                }
            }
        }
        return found
    }

    func testThePlayersTextWritesNoCurrencyOfItsOwn() throws {
        for directory in ["Sources/GamePresentation", "RailwayGameApp/Views"] {
            let found = try linesWithCurrency(in: directory, matching: Self.currency)
            XCTAssertEqual(found, [], "write amounts with Money.moneyText and its kin, and the sign as Money.currencySymbol")
        }
    }

    /// An amount as the format functions write it ("$ 12", "+$ 3",
    /// "−$40k", "$2.1k") in what a test expects.
    private static let writtenAmount = try! NSRegularExpression(
        pattern: #"\$ -?[0-9]|[+\-\x{2212}]\$ |\\u\{2212\}\$|"[+-]?\$[0-9.]+[kM]?""#
    )

    func testTheTestsExpectWhatTheFormatFunctionsWrite() throws {
        let found = try linesWithCurrency(in: "Tests/GamePresentationTests", matching: Self.writtenAmount)
        XCTAssertEqual(found, [], "expect Money(…).moneyText and its kin, not an amount written out")
    }

    func testTheFormatFunctionsShareOneSign() {
        let sign = Money.currencySymbol
        XCTAssertTrue(Money(123_400).moneyText.hasPrefix(sign + " "))
        XCTAssertTrue(Money(55).centsText.hasPrefix(sign + " "))
        XCTAssertEqual(Money(500_000_000).wholeText, sign + "5,000,000")
        XCTAssertEqual(Money(-142_800).wholeText, sign + "-1,428")
        XCTAssertEqual(Money(120_000).signedText, "+" + sign + " 1,200")
        XCTAssertEqual(Money(-142_800).signedText, "-" + sign + " 1,428")
        XCTAssertEqual(Money(-40).signedText, "-" + sign + " 0", "a loss under half a dollar is still a loss")
        XCTAssertEqual(Money(30_000_000_000).roundText(in: .english), sign + "300 million")
        XCTAssertEqual(Money(30_000_000_000).roundText(in: .traditionalChinese), "3 億")
        XCTAssertEqual(Money(123_456).roundText(in: .english), Money(123_456).wholeText)
        XCTAssertEqual(TrainRoster.shortMoney(Money(210_000), in: .english), sign + "2.1k")
        XCTAssertEqual(IncomePulse(amount: Money(-4_000_000), serial: 1).text, "\u{2212}" + sign + "40k")
    }
}
