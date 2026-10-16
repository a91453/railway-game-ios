import GameCore
import GamePresentation
import XCTest

/// Decision 226, later (2026-10-16): the game menu's postcard and
/// achievements in its first level; decision 229, later: the map's 3D
/// button.
final class GameMenuLayoutTests: XCTestCase {
    func testThePostcardAndAchievementsStandInTheFirstLevel() {
        let layout = GameMenuLayout(showsGoals: true, showsTourism: true)
        let first = layout.sections.flatMap { $0 }
        XCTAssertTrue(first.contains(.postcard))
        XCTAssertTrue(first.contains(.achievements))
        XCTAssertEqual(layout.moreRows, [.goals, .tourism, .help, .report], "More keeps the rest, without the postcard")
    }

    func testBackToStartStaysTheThirdRow() {
        // On a phone on its side the menu shows about six rows
        // (TestFlight 54.1): the way out stays in reach.
        let first = GameMenuLayout(showsGoals: false, showsTourism: false).sections.flatMap { $0 }
        XCTAssertEqual(first.firstIndex(of: .backToStart), 2)
        XCTAssertEqual(first, [.saveGame, .saveOptions, .backToStart, .tutorial, .postcard, .achievements, .more, .settings])
    }

    func testMoreListsOnlyWhatTheGameHas() {
        XCTAssertEqual(GameMenuLayout(showsGoals: false, showsTourism: false).moreRows, [.help, .report])
        XCTAssertEqual(GameMenuLayout(showsGoals: true, showsTourism: false).moreRows, [.goals, .help, .report])
        XCTAssertEqual(GameMenuLayout(showsGoals: false, showsTourism: true).moreRows, [.tourism, .help, .report])
    }

    func testTheAchievementsRowSaysWhyItCountsNoneWithUnlimitedFunds() {
        let counted = GameMenuLayout.achievementsRow(unlocked: 3, total: 20, unlimitedFunds: false, in: .english)
        XCTAssertEqual(counted.title, "Achievements 3/20")
        XCTAssertNil(counted.subtitle)
        XCTAssertTrue(counted.isEnabled)
        let unlimited = GameMenuLayout.achievementsRow(unlocked: 3, total: 20, unlimitedFunds: true, in: .traditionalChinese)
        XCTAssertEqual(unlimited.title, "成就 3/20")
        XCTAssertEqual(unlimited.subtitle, "資金無限的局不計成就")
        XCTAssertFalse(unlimited.isEnabled)
    }

    func testThe3DButtonShowsWithTheZoomButtonsOutsideTheTutorial() {
        XCTAssertTrue(Map3DShortcut.isShown(zoomButtonsShow: true, tutorialRuns: false))
        XCTAssertFalse(Map3DShortcut.isShown(zoomButtonsShow: false, tutorialRuns: false), "Gives way beside a wide card, as the zoom buttons do")
        XCTAssertFalse(Map3DShortcut.isShown(zoomButtonsShow: true, tutorialRuns: true))
    }
}
