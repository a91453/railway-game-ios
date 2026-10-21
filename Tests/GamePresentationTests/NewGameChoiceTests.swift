import GameCore
@testable import GamePresentation
import XCTest

/// Decision 316: the new game's page, the maps it lists and what it says
/// of them and of the options both start with.
final class NewGameChoiceTests: XCTestCase {
    /// Blank first, then real-world: one card each, each its own
    /// identifier.
    func testThePageListsBothMaps() {
        XCTAssertEqual(NewGameChoice.allCases, [.blank, .realWorld])
        XCTAssertEqual(NewGameChoice.allCases.map(\.identifier), ["newGame.blank", "newGame.realWorld"])
        XCTAssertEqual(NewGameChoice.blank.title(in: .english), "Blank Map")
        XCTAssertEqual(NewGameChoice.realWorld.title(in: .traditionalChinese), "實景地圖")
        XCTAssertEqual(NewGameChoice.entryDetail(in: .english), "A blank map or a real place")
        XCTAssertEqual(NewGameChoice.entryDetail(in: .traditionalChinese), "空白地圖或真實地點")
    }

    /// A blank map's card says its cash, from the options; a real-world
    /// map's says where it is.
    func testTheCardsSayWhatTheyStartWith() {
        var options = NewGameOptions()
        XCTAssertEqual(NewGameChoice.blank.detail(in: .english, options: options), "An empty map and $ 3,000,000 to build with")
        XCTAssertEqual(NewGameChoice.blank.detail(in: .traditionalChinese, options: options), "空白地圖，起始資金 $ 3,000,000")
        options.difficulty = .easy
        XCTAssertEqual(NewGameChoice.blank.detail(in: .english, options: options), "An empty map and $ 5,000,000 to build with")
        options.funds = .unlimited
        XCTAssertEqual(NewGameChoice.blank.detail(in: .traditionalChinese, options: options), "空白地圖，資金無限")
        XCTAssertEqual(NewGameChoice.realWorld.detail(in: .english, options: options), "Build on a map of a real place")
        XCTAssertEqual(NewGameChoice.realWorld.detail(in: .traditionalChinese, options: options), "在真實地點的地圖上建造")
    }

    /// The options' row says the rules, difficulty and cash, and the note
    /// under it that both maps start with them.
    func testTheOptionsRowSaysBothMapsUseIt() {
        var options = NewGameOptions()
        XCTAssertEqual(NewGameChoice.optionsSummary(options, in: .english), "New Game Options · Simple · Standard · $ 3,000,000")
        XCTAssertEqual(NewGameChoice.optionsSummary(options, in: .traditionalChinese), "新遊戲選項 · 簡單規則 · 標準 · $ 3,000,000")
        options.funds = .unlimited
        XCTAssertEqual(NewGameChoice.optionsSummary(options, in: .english), "New Game Options · Simple · Standard · ∞")
        XCTAssertEqual(NewGameChoice.optionsNote(in: .english), "Both maps start with these options.")
        XCTAssertEqual(NewGameChoice.optionsNote(in: .traditionalChinese), "兩種地圖都套用這些選項。")
    }
}
