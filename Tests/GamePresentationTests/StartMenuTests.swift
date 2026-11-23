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

/// IPAD-HOME-HALF: where the start screen's menu stands in the screen's
/// height (`StartMenuPlacement`).
final class StartMenuPlacementTests: XCTestCase {
    /// IPAD-HOME-HALF: an iPhone keeps the menu at the top, 40 points
    /// down, whatever its height, as before.
    func testAPhoneKeepsTheMenuAtTheTop() {
        XCTAssertFalse(StartMenuPlacement.centres(on: .iPhone))
        for (screen, menu) in [(874.0, 700.0), (956, 500), (667, 900), (0, 0)] {
            XCTAssertEqual(StartMenuPlacement.roomAbove(screenHeight: screen, menuHeight: menu, on: .iPhone), 40)
        }
    }

    /// IPAD-HOME-HALF: on an iPad (and a Mac) the menu stands a little
    /// above the middle of the screen, and it and its margins fill the
    /// screen's height without scrolling; the room below is never less
    /// than above's 40 either.
    func testAnIPadStandsTheMenuAboveTheMiddle() {
        XCTAssertTrue(StartMenuPlacement.centres(on: .iPad))
        XCTAssertTrue(StartMenuPlacement.centres(on: .mac))
        // An 11-inch iPad on its side (834 tall, the status bar's 24 off)
        // and upright, an iPad mini upright and a 13-inch upright.
        for (screen, menu) in [(810.0, 560.0), (1170, 760), (1109, 760), (1352, 620)] {
            let above = StartMenuPlacement.roomAbove(screenHeight: screen, menuHeight: menu, on: .iPad)
            let below = screen - menu - above
            XCTAssertGreaterThan(above, 40)
            XCTAssertLessThan(above, below, "a little above the middle")
            XCTAssertGreaterThan(above, 0.7 * below, "but near it")
            XCTAssertEqual(above + menu + below, screen, accuracy: 0.001)
        }
        // The 11-inch upright: 410 free, 172.2 of it above.
        XCTAssertEqual(StartMenuPlacement.roomAbove(screenHeight: 1170, menuHeight: 760, on: .iPad), 40 + 330 * 0.42, accuracy: 0.001)
    }

    /// IPAD-HOME-HALF: a menu as tall as the screen or taller (large text,
    /// an iPad mini on its side) starts at the top and scrolls, as on an
    /// iPhone; so does the first layout, before the heights are measured.
    func testATallMenuStillStartsAtTheTop() {
        XCTAssertEqual(StartMenuPlacement.roomAbove(screenHeight: 720, menuHeight: 900, on: .iPad), 40)
        XCTAssertEqual(StartMenuPlacement.roomAbove(screenHeight: 720, menuHeight: 640, on: .iPad), 40)
        XCTAssertEqual(StartMenuPlacement.roomAbove(screenHeight: 0, menuHeight: 0, on: .iPad), 40)
        XCTAssertEqual(StartMenuPlacement.roomAbove(screenHeight: 721, menuHeight: 640, on: .iPad), 40.42, accuracy: 0.001)
    }
}
