import Foundation
@testable import GamePresentation
import XCTest

/// Decision 1034: the game in Japanese. The table the translators filled,
/// the language menu's Japanese, and Japan's stations and lines by their
/// official Japanese names.
@MainActor
final class JapaneseGameTests: XCTestCase {
    /// The table holds the game's sentences; a sentence it lacks shows in
    /// English. `tools/translations/extract.py --coverage ja` counts the
    /// sentences of the code that fall back.
    func testTheTableHoldsTheGamesSentences() {
        let count = TranslationTable.japanese.count
        print("Japanese table: \(count) sentences")
        XCTAssertGreaterThanOrEqual(count, 4_000)
        XCTAssertEqual(DisplayLanguage.japanese.text("Pause", "暫停"), "一時停止")
        XCTAssertEqual(LanguageChoice.system.title(in: .japanese, on: .iPhone), "iPhoneと同じ")
    }

    /// A sentence written out with interpolations reaches the table
    /// finished (Swift takes the literal as a `String`), so the table finds
    /// its key by its words and puts what stood in the interpolations into
    /// the Japanese, in the Japanese order.
    func testAFinishedSentenceIsFoundByItsWords() {
        let table = TranslationTable(source: """
        Same as {0}\t{0}と同じ
        {0} left {1} min ago\t{1}分前に{0}を発車
        {0} train{1}\t列車{0}本
        {0} at {1}\t{1}の{0}
        Leaves {0} at {1}\t{1}に{0}を発車
        {0} · {1}\t{0} · {1}
        """)
        XCTAssertEqual(table.translate("Same as iPhone"), "iPhoneと同じ")
        XCTAssertEqual(table.translate("Hakata left 5 min ago"), "5分前にHakataを発車")
        XCTAssertEqual(table.translate("3 trains"), "列車3本")
        XCTAssertEqual(table.translate("1 train"), "列車1本")
        // The key with the most words of its own wins over " at ".
        XCTAssertEqual(table.translate("Leaves Hakata at 06:10"), "06:10にHakataを発車")
        XCTAssertEqual(table.translate("Hakata at 06:10"), "06:10のHakata")
        // Not a sentence of the table: as it is, a second time too.
        XCTAssertEqual(table.translate("Something else"), "Something else")
        XCTAssertEqual(table.translate("Something else"), "Something else")
        // A key with no letter of its own is not matched.
        XCTAssertEqual(table.translate("A · B"), "A · B")
        // The game's own: the language menu's system row.
        XCTAssertEqual(TranslationTable.japanese.translate("Same as iPhone"), "iPhoneと同じ")
    }

    func testAStationInJapanHasItsJapaneseName() throws {
        let railways = try FukuokaRailwaysTests.railways()
        let meinohama = try XCTUnwrap(railways.stations.first { $0.system.id == "fksubway" && $0.chinese == "姪濱" })
        XCTAssertEqual(meinohama.japanese, "姪浜")
        XCTAssertEqual(meinohama.name(in: .japanese), "姪浜")
        XCTAssertEqual(meinohama.name(in: .english), "Meinohama")
        XCTAssertEqual(meinohama.name(in: .traditionalChinese), "姪濱")
        // A station named in Japanese is found by that name, as one named in
        // English or Chinese is.
        XCTAssertTrue(railways.stations(named: "姪浜", near: nil).contains(meinohama))
        // A station with no Japanese name shows its English one, as in
        // English; Taiwan's have the site data's Japanese.
        let taipei = try XCTUnwrap(railways.stations.first { $0.chinese == "台北" && $0.english != nil })
        XCTAssertEqual(taipei.name(in: .japanese), taipei.japanese ?? taipei.name(in: .english))
        if let unnamed = railways.stations.first(where: { $0.japanese == nil && $0.english != nil }) {
            XCTAssertEqual(unnamed.name(in: .japanese), unnamed.name(in: .english))
        }
    }

    func testALineInJapanHasItsJapaneseName() {
        let relay = RealBranchLine(network: "RK", english: "Relay Kamome", chinese: "海鷗接力號", stops: [], system: "jrkyushu", tier: .branch)
        XCTAssertEqual(relay.name(in: .japanese), "リレーかもめ")
        XCTAssertEqual(relay.name(in: .english), "Relay Kamome")
        XCTAssertEqual(relay.name(in: .traditionalChinese), "海鷗接力號")
        // Each Japanese name is of a line on sale.
        let sold = Set(RealBranchLine.overseasLines.map { "\($0.system)|\($0.network)" })
        for key in RealBranchLine.japaneseNames.keys {
            XCTAssertTrue(sold.contains(key), key)
        }
    }

    func testTheNeutralBrandHasAJapaneseName() {
        XCTAssertEqual(GameBrand.neutral.name(in: .japanese), "鉄道ゲーム")
    }
}
