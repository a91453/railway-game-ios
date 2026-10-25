import GameCore
import GamePresentation
import XCTest

/// Decision 226, later (2026-10-16): the game menu's postcard and
/// achievements in its first level; decision 229, later: the map's 3D
/// button.
final class GameMenuLayoutTests: XCTestCase {
    func testThePostcardAndAchievementsStandInTheFirstLevel() {
        let layout = GameMenuLayout(showsGoals: true, showsTourism: true)
        XCTAssertTrue(layout.sections.flatMap { $0 }.contains(.shortcuts))
        XCTAssertEqual(layout.shortcuts, [.tutorial, .postcard, .achievements], "One row, side by side")
        XCTAssertEqual(layout.moreRows, [.goals, .tourism], "More keeps the rest, without the postcard")
    }

    func testTheFirstLevelKeepsToSixRowsWithBackToStartThird() {
        // On a phone on its side the menu shows about six rows
        // (TestFlight 54.1); an eighth row put Settings out of reach (main
        // 84a792e's full lane, run 38861445072).
        let first = GameMenuLayout(showsGoals: false, showsTourism: false).sections.flatMap { $0 }
        XCTAssertLessThanOrEqual(first.count, GameMenuLayout.rowsInReach)
        XCTAssertEqual(GameMenuLayout.rowsInReach, 6)
        XCTAssertEqual(first.firstIndex(of: .backToStart), 2)
        XCTAssertEqual(first, [.saveGame, .saveOptions, .backToStart, .shortcuts, .help, .settings])
        XCTAssertEqual(GameMenuLayout(showsGoals: true, showsTourism: true).sections, GameMenuLayout(showsGoals: false, showsTourism: false).sections)
    }

    /// Decision 414: the idle mode beside Settings, one row, so the first
    /// level keeps its six rows.
    func testTheIdleModeStandsBesideSettings() {
        let layout = GameMenuLayout(showsGoals: false, showsTourism: false)
        XCTAssertEqual(layout.settingsRow, [.ambient, .settings])
        XCTAssertLessThanOrEqual(layout.settingsRow.count, GameMenuLayout.itemsInRow, "one row, side by side")
        XCTAssertEqual(layout.sections.last, [.settings])
    }

    /// Decision 383: Help and Report a Problem in the first level, one tap
    /// after the menu, in every game.
    func testHelpAndReportStandInTheFirstLevel() {
        for goals in [false, true] {
            for tourism in [false, true] {
                let layout = GameMenuLayout(showsGoals: goals, showsTourism: tourism)
                XCTAssertTrue(layout.sections.flatMap { $0 }.contains(.help))
                XCTAssertEqual(Array(layout.helpRow.prefix(2)), [.help, .report])
                XCTAssertLessThanOrEqual(layout.helpRow.count, GameMenuLayout.itemsInRow, "one row, side by side")
                XCTAssertEqual(layout.helpRow.contains(.more), !layout.moreRows.isEmpty, "More only with something under it")
            }
        }
    }

    /// Decision 383: what More held comes up beside Help when it is one
    /// row; with two, More keeps them.
    func testMoreListsOnlyWhatTheGameHas() {
        XCTAssertEqual(GameMenuLayout(showsGoals: false, showsTourism: false).helpRow, [.help, .report])
        XCTAssertEqual(GameMenuLayout(showsGoals: true, showsTourism: false).helpRow, [.help, .report, .goals])
        XCTAssertEqual(GameMenuLayout(showsGoals: false, showsTourism: true).helpRow, [.help, .report, .tourism])
        XCTAssertEqual(GameMenuLayout(showsGoals: true, showsTourism: true).helpRow, [.help, .report, .more])
        XCTAssertEqual(GameMenuLayout(showsGoals: false, showsTourism: true).moreRows, [])
        XCTAssertEqual(GameMenuLayout(showsGoals: true, showsTourism: true).moreRows, [.goals, .tourism])
    }

    func testTheAchievementsSayWhyTheyCountNoneWithUnlimitedFunds() {
        XCTAssertNil(GameMenuLayout.achievementsNote(unlimitedFunds: false, in: .english))
        XCTAssertEqual(GameMenuLayout.achievementsNote(unlimitedFunds: true, in: .traditionalChinese), "資金無限的局不計成就。")
        XCTAssertEqual(GameMenuLayout.achievementsNote(unlimitedFunds: true, in: .english), "Not counted with unlimited funds.")
    }

    func testThe3DButtonShowsWithTheZoomButtonsOutsideTheTutorial() {
        XCTAssertTrue(Map3DShortcut.isShown(zoomButtonsShow: true, tutorialRuns: false))
        XCTAssertFalse(Map3DShortcut.isShown(zoomButtonsShow: false, tutorialRuns: false), "Gives way beside a wide card, as the zoom buttons do")
        XCTAssertFalse(Map3DShortcut.isShown(zoomButtonsShow: true, tutorialRuns: true))
    }
}
