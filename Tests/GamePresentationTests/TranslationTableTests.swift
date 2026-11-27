@testable import GamePresentation
import XCTest

/// Decision 1034: Japanese is looked up by the English sentence's key, the
/// literal with `{n}` for each interpolation; a sentence the table has no
/// Japanese for shows its English.
final class TranslationTableTests: XCTestCase {
    func testTheKeyIsTheLiteralWithNumberedInterpolations() {
        let name = "Hakata", count = 3
        let template: DisplayTextTemplate = "\(count) trains at \(name) Station"
        XCTAssertEqual(template.text, "3 trains at Hakata Station")
        XCTAssertEqual(template.key, "{0} trains at {1} Station")
        XCTAssertEqual(template.arguments, ["3", "Hakata"])
        let plain: DisplayTextTemplate = "Net profit"
        XCTAssertEqual(plain.key, "Net profit")
        XCTAssertEqual(plain.text, "Net profit")
        XCTAssertEqual(plain.arguments, [])
    }

    func testEnglishAndChineseAreUnchanged() {
        let name = "Hakata"
        XCTAssertEqual(DisplayLanguage.english.text("Trains at \(name)", "\(name) 的列車"), "Trains at Hakata")
        XCTAssertEqual(DisplayLanguage.traditionalChinese.text("Trains at \(name)", "\(name) 的列車"), "Hakata 的列車")
        let built = "Built elsewhere"
        XCTAssertEqual(DisplayLanguage.english.text(built, "別處寫好"), built)
        XCTAssertEqual(DisplayLanguage.traditionalChinese.text(built, "別處寫好"), "別處寫好")
    }

    func testJapaneseFallsBackToEnglishWithoutATableEntry() {
        let unlikely: DisplayTextTemplate = "A sentence no table will ever hold \(42)"
        XCTAssertFalse(TranslationTable.japanese.has(unlikely))
        XCTAssertEqual(DisplayLanguage.japanese.text("A sentence no table will ever hold \(42)", "中文"),
                       "A sentence no table will ever hold 42")
    }

    func testTheJapaneseMayReorderRepeatOrDropInterpolations() {
        let table = TranslationTable.parse("{0} trains at {1} Station\t{1}駅の列車 {0} 本\nEvery {0} {1}\t{0}日ごと\n")
        let template: DisplayTextTemplate = "\(3) trains at \("Hakata") Station"
        XCTAssertEqual(TranslationTable.render(table[template.key]!, template.arguments), "Hakata駅の列車 3 本")
        let days = [2].count + 1
        let plural: DisplayTextTemplate = "Every \(days) \(days == 1 ? "day" : "days")"
        XCTAssertEqual(TranslationTable.render(table[plural.key]!, plural.arguments), "2日ごと")
        // A Japanese naming an interpolation the English lacks is not used.
        XCTAssertNil(TranslationTable.render(TranslationTable.pieces(of: "{2}"), ["a"]))
    }

    func testTheTableFormatEscapesTabsLineBreaksAndBackslashes() {
        let table = TranslationTable.parse("Line\\none\tひと\\tつ\\\\\n{x} and {\tそのまま {x} {\n")
        XCTAssertEqual(TranslationTable.render(table["Line\none"]!, []), "ひと\tつ\\")
        XCTAssertEqual(TranslationTable.render(table["{x} and {"]!, []), "そのまま {x} {")
    }

    func testJaPicksJapanese() {
        XCTAssertEqual(DisplayLanguage(localization: "ja"), .japanese)
        XCTAssertEqual(DisplayLanguage(localization: "ja-JP"), .japanese)
        XCTAssertEqual(DisplayLanguage(localization: "zh-Hant"), .traditionalChinese)
        XCTAssertEqual(DisplayLanguage(localization: "en"), .english)
        XCTAssertEqual(DisplayLanguage.japanese.base, .english)
        XCTAssertEqual(DisplayLanguage.traditionalChinese.base, .traditionalChinese)
    }

    /// Every Japanese in the generated table names only interpolations its
    /// English has, so none of them falls back for a wrong `{n}`.
    func testEveryTableEntryUsesOnlyItsEnglishInterpolations() {
        for (key, pieces) in TranslationTable.japanese.entries {
            let count = key.components(separatedBy: "{").count - 1
            for case .argument(let n) in pieces {
                XCTAssertLessThan(n, count, "\(key): {\(n)}")
            }
        }
    }
}
