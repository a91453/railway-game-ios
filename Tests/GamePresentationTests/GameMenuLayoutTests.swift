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

    /// Decision 498 (UI_AUDIT B2): the rows side by side show their items'
    /// titles where the screen is tall enough (an iPad, a phone held
    /// upright), so Settings, Help and the tutorial are not guessed from an
    /// icon; on a phone on its side, icons, so the six rows stay in reach
    /// (decision 226, later; SettingsUITests went red when they did not).
    func testTheRowsSideBySideShowTheirTitlesWhereTheScreenIsTallEnough() {
        let layout = GameMenuLayout(showsGoals: true, showsTourism: true)
        XCTAssertEqual(GameMenuLayout.itemStyle(compactHeight: false), .titled)
        XCTAssertEqual(GameMenuLayout.itemStyle(compactHeight: true), .iconsOnly)
        // A phone on its side: some 330 points under the status bar and
        // the HUD. Titled, the six rows would not fit; icons only, they do.
        let phoneOnItsSide = 330.0
        XCTAssertGreaterThan(layout.height(itemStyle: .titled), phoneOnItsSide)
        XCTAssertLessThanOrEqual(layout.height(itemStyle: .iconsOnly), phoneOnItsSide)
        // The shortest screen of regular height, an iPhone SE upright (667
        // points), less its status bar and the HUD: titled, they fit.
        XCTAssertLessThanOrEqual(layout.height(itemStyle: .titled), 667 - 140)
        // Every row side by side holds at most what titled items show.
        for row in [layout.shortcuts.count, layout.helpRow.count, layout.settingsRow.count] {
            XCTAssertLessThanOrEqual(row, GameMenuLayout.itemsInRow)
        }
    }

    /// Decision 498 (UI_GAPS D11): help says where sharing the network
    /// with a friend is (decision 409), found by either language's words.
    func testHelpSaysHowToShareTheNetwork() throws {
        for query in ["分享路網", "share network friend", "朋友"] {
            XCTAssertTrue(HelpGuide.entries(matching: query).contains { $0.id == "shareNetwork" }, query)
        }
        let entry = try XCTUnwrap(HelpGuide.entries.first { $0.id == "shareNetwork" })
        XCTAssertTrue(entry.answer(in: .traditionalChinese).contains("做明信片"))
        XCTAssertTrue(entry.answer(in: .traditionalChinese).contains("分享路網"))
        XCTAssertTrue(entry.answer(in: .english).contains("Make a Postcard"))
        XCTAssertTrue(entry.answer(in: .english).contains("Share Network"))
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
