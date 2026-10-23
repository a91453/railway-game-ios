@testable import GamePresentation
import XCTest

/// Decision 381: the start screen's six buttons and two capsules, and what
/// the Saves button and its list say.
final class StartMenuTests: XCTestCase {
    /// Continue only with an autosave; Saves always, even with no save,
    /// since importing one starts from it; no Challenges, Saved Games or
    /// Import a Save of their own.
    func testTheStartScreenListsSixButtons() {
        XCTAssertEqual(
            StartMenuEntry.entries(hasAutosave: true),
            [.continueGame, .newGame, .lessons, .demoMap, .saves, .achievements]
        )
        XCTAssertEqual(
            StartMenuEntry.entries(hasAutosave: false),
            [.newGame, .lessons, .demoMap, .saves, .achievements]
        )
        XCTAssertEqual(
            StartMenuEntry.allCases.map(\.identifier),
            ["start.continue", "start.newGame", "start.lessons", "start.demoMap", "start.saves", "start.achievements"]
        )
    }

    /// Help and Settings are the only capsules: Language is in Settings,
    /// Data Sources in Help.
    func testTheCapsulesAreHelpAndSettings() {
        XCTAssertEqual(StartMenuChip.allCases.map(\.identifier), ["start.help", "start.settings"])
    }

    /// The Saves button counts the saves, or offers to import one.
    func testTheSavesButtonCountsOrOffersAnImport() {
        XCTAssertEqual(StartMenuEntry.savesTitle(in: .english), "Saves")
        XCTAssertEqual(StartMenuEntry.savesTitle(in: .traditionalChinese), "存檔")
        XCTAssertEqual(StartMenuEntry.savesDetail(count: 0, in: .english), "Import a save from Files or another device")
        XCTAssertEqual(StartMenuEntry.savesDetail(count: 0, in: .traditionalChinese), "從檔案或另一台裝置匯入存檔")
        XCTAssertEqual(StartMenuEntry.savesDetail(count: 1, in: .english), "1 save, or import one from a file")
        XCTAssertEqual(StartMenuEntry.savesDetail(count: 3, in: .english), "3 saves, or import one from a file")
        XCTAssertEqual(StartMenuEntry.savesDetail(count: 3, in: .traditionalChinese), "3 個存檔，也可以從檔案匯入")
    }

    /// The list's import row, and the new game's challenges card that took
    /// the start screen's Challenges button's place.
    func testTheImportRowAndTheChallengesCard() {
        XCTAssertEqual(SaveListText.title(in: .traditionalChinese), "存檔")
        XCTAssertEqual(SaveListText.importTitle(in: .english), "Import from Files")
        XCTAssertEqual(SaveListText.importTitle(in: .traditionalChinese), "從檔案匯入")
        XCTAssertEqual(SaveListText.importIdentifier, "saves.import")
        XCTAssertEqual(NewGameChoice.challengesTitle(in: .traditionalChinese), "挑戰")
        XCTAssertEqual(NewGameChoice.challengesIdentifier, "newGame.challenges")
        XCTAssertFalse(NewGameChoice.allCases.map(\.identifier).contains(NewGameChoice.challengesIdentifier))
    }
}

/// Decision 381: the data sources and licences, two taps away from the
/// start screen (Help, then the row) now that their capsule went.
final class DataSourcesEntryTests: XCTestCase {
    func testTheRowShowsUnlessTheSearchIsForSomethingElse() {
        XCTAssertEqual(DataSourcesEntry.title(in: .english), "Data Sources and Licences")
        XCTAssertEqual(DataSourcesEntry.title(in: .traditionalChinese), "資料來源與授權")
        XCTAssertTrue(DataSourcesEntry.shows(matching: ""))
        XCTAssertTrue(DataSourcesEntry.shows(matching: "  "))
        XCTAssertTrue(DataSourcesEntry.shows(matching: "licence"))
        XCTAssertTrue(DataSourcesEntry.shows(matching: "OpenStreetMap"))
        XCTAssertTrue(DataSourcesEntry.shows(matching: "授權"))
        XCTAssertTrue(DataSourcesEntry.shows(matching: "data sources"))
        XCTAssertFalse(DataSourcesEntry.shows(matching: "loan"))
        XCTAssertFalse(DataSourcesEntry.shows(matching: "票價"))
        XCTAssertNotEqual(DataSourcesEntry.helpIdentifier, DataSourcesEntry.settingsIdentifier)
    }
}
