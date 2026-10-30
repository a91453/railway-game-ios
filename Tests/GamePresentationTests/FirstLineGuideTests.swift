import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 508 (98.1: "I opened Lines and there was nothing to press"):
/// a player who skipped the tutorial is told, before the first line, what
/// is missing and which control makes it.
@MainActor
final class FirstLineGuideTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)

    private func world(stations: Int, track: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000)
        if track { try Self.line.build(in: &world) }
        for (index, name) in ["Alpha", "Beta", "Gamma"].prefix(stations).enumerated() {
            try Self.line.buildStation(named: name, beside: 1 + 6 * index, at: 0, in: &world)
        }
        return world
    }

    // MARK: - The lines panel

    func testTheLinesPanelSaysWhatTheFirstLineNeeds() throws {
        XCTAssertEqual(FirstLineNeed(world: try world(stations: 0, track: false)), .stations(0))
        XCTAssertEqual(FirstLineNeed(world: try world(stations: 0)), .stations(0))
        XCTAssertEqual(FirstLineNeed(world: try world(stations: 1)), .stations(1))
        XCTAssertEqual(FirstLineNeed(world: try world(stations: 2)), .line)
        var made = try world(stations: 2)
        try made.createLine(named: "Main", stops: made.stations.map(\.id))
        XCTAssertNil(FirstLineNeed(world: made), "a line made: the panel is as before")

        XCTAssertEqual(FirstLineNeed.stations(0).title(in: .traditionalChinese), "先蓋兩座車站")
        XCTAssertEqual(FirstLineNeed.stations(1).title(in: .traditionalChinese), "再蓋一座車站")
        XCTAssertEqual(FirstLineNeed.line.title(in: .traditionalChinese), "把車站連成路線")
        XCTAssertEqual(FirstLineNeed.stations(0).action, .build)
        XCTAssertEqual(FirstLineNeed.stations(1).action, .build)
        XCTAssertEqual(FirstLineNeed.line.action, .pickStations)
        // The buttons say what the controls they open say.
        XCTAssertEqual(FirstLineNeed.stations(0).buttonTitle(in: .traditionalChinese), "到「建設」")
        XCTAssertEqual(FirstLineNeed.line.buttonTitle(in: .traditionalChinese), "在地圖上選站")
        XCTAssertEqual(FirstLineNeed.stations(0).buttonSymbol, FirstLineGuide.buildSymbol)
    }

    func testThePanelCardGivesWayToPickingAndToTheTutorial() throws {
        let session = GameSession(world: try world(stations: 2))
        XCTAssertEqual(session.linesPanelFirstLineNeed, .line)
        session.startPickingLineStops()
        XCTAssertNil(session.linesPanelFirstLineNeed, "the form leads once picking starts")
        session.stopPickingLineStops()
        XCTAssertEqual(session.linesPanelFirstLineNeed, .line)
        session.startTutorial()
        XCTAssertNil(session.linesPanelFirstLineNeed, "the tutorial's card leads")
    }

    // MARK: - The station master's offer

    func testTheTutorialIsOfferedInAFreeGameWithNoLine() throws {
        let session = GameSession(world: try world(stations: 0, track: false))
        XCTAssertTrue(FirstLineGuide.offers(in: session, tutorialCompleted: false, choice: nil))
        XCTAssertFalse(FirstLineGuide.offers(in: session, tutorialCompleted: true, choice: nil), "the tutorial was finished")
        XCTAssertFalse(FirstLineGuide.offers(in: session, tutorialCompleted: false, choice: .selfGuided), "answered before")
        XCTAssertFalse(FirstLineGuide.offers(in: session, tutorialCompleted: false, choice: .tutorial), "answered before")

        var made = try world(stations: 2)
        try made.createLine(named: "Main", stops: made.stations.map(\.id))
        XCTAssertFalse(FirstLineGuide.offers(in: GameSession(world: made), tutorialCompleted: false, choice: nil), "a line made")

        session.startTutorial()
        XCTAssertFalse(FirstLineGuide.offers(in: session, tutorialCompleted: false, choice: nil), "in the tutorial")
    }

    func testTheOfferIsNotMadeInALessonOrAChallenge() {
        let launcher = GameLauncher(library: SaveLibrary(directory: makeDirectory()), language: .english)
        launcher.startLesson(Lesson.all[1])
        let lesson = launcher.session!
        lesson.skipTutorial()
        XCTAssertFalse(FirstLineGuide.offers(in: lesson, tutorialCompleted: false, choice: nil))
        XCTAssertNil(FirstLineGuide.hint(in: lesson, choice: .selfGuided))
    }

    func testTheAnswerIsKeptAndTheTutorialStartsLessonOne() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertNil(launcher.preferences.firstLineGuide)
        launcher.chooseFirstLineGuide(.selfGuided)
        XCTAssertEqual(launcher.preferences.firstLineGuide, .selfGuided)
        XCTAssertNil(launcher.session, "I'll do it myself starts nothing")
        let later = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertEqual(later.preferences.firstLineGuide, .selfGuided, "kept on the device")

        later.chooseFirstLineGuide(.tutorial)
        XCTAssertEqual(later.preferences.firstLineGuide, .tutorial)
        XCTAssertEqual(later.session?.lesson?.id, Lesson.all[0].id)
        XCTAssertNotNil(later.session?.tutorial, "its guide on its first step")
    }

    func testAnOlderPreferencesFileReadsWithNoAnswer() throws {
        let older = Data(#"{"firstGameCardDismissed":true,"hasLaunched":true,"newGameOptions":{},"tutorialCompleted":false}"#.utf8)
        let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: older)
        XCTAssertNil(preferences.firstLineGuide)
    }

    // MARK: - "I'll do it myself"

    /// Each step of the first line names the control on screen, and the
    /// tutorial's ring goes round it.
    func testEachStepNamesItsControl() throws {
        func hint(_ world: GameWorld, tool: ConstructionTool = .select, mode: NetworkToolMode = .build,
                  lines: Bool = false, picking: Bool = false) -> FirstLineGuide.Hint {
            FirstLineGuide.hint(world: world, tool: tool, networkMode: mode, linesPanelShown: lines, picking: picking)
        }
        let empty = try world(stations: 0, track: false)
        XCTAssertEqual(hint(empty).target, .buildEntry)
        XCTAssertEqual(hint(empty).symbol, FirstLineGuide.buildSymbol)
        XCTAssertEqual(hint(empty).text(in: .traditionalChinese), "點左下的鐵鎚「建設」，開始鋪軌道。")
        XCTAssertNil(hint(empty, tool: .network).target, "the track is drawn on the map")
        XCTAssertEqual(hint(empty, tool: .network, mode: .remove).target, .networkModes)
        XCTAssertEqual(hint(empty, tool: .train).target, .networkTool)

        let track = try world(stations: 0)
        XCTAssertEqual(hint(track).target, .buildEntry)
        XCTAssertEqual(hint(track, tool: .network).target, .networkModes)
        XCTAssertEqual(hint(track, tool: .network).text(in: .traditionalChinese), "點「月台」，再點軌道上要蓋車站的地方。")
        XCTAssertNil(hint(track, tool: .network, mode: .platform).target)
        XCTAssertNotEqual(hint(track, tool: .network, mode: .platform),
                          hint(try world(stations: 1), tool: .network, mode: .platform), "the second station is its own step")

        let two = try world(stations: 2)
        XCTAssertEqual(hint(two, tool: .network).target, .selectTool, "Done first")
        XCTAssertEqual(hint(two).target, .linesButton)
        XCTAssertEqual(hint(two).symbol, FirstLineGuide.linesSymbol)
        XCTAssertEqual(hint(two).text(in: .traditionalChinese), "點左下的「路線」，開一條路線。")
        XCTAssertEqual(hint(two, lines: true).target, .pickLineStops)
        XCTAssertNil(hint(two, lines: true, picking: true).target)
    }

    func testTheStepsAreForThoseWhoChoseThemUntilTheFirstLine() throws {
        let session = GameSession(world: try world(stations: 2))
        XCTAssertNil(FirstLineGuide.hint(in: session, choice: nil))
        XCTAssertNil(FirstLineGuide.hint(in: session, choice: .tutorial))
        XCTAssertEqual(FirstLineGuide.hint(in: session, choice: .selfGuided)?.target, .linesButton)
        session.linesPanelDidChange(isShown: true)
        XCTAssertEqual(FirstLineGuide.hint(in: session, choice: .selfGuided)?.target, .pickLineStops)

        var made = try world(stations: 2)
        try made.createLine(named: "Main", stops: made.stations.map(\.id))
        XCTAssertNil(FirstLineGuide.hint(in: GameSession(world: made), choice: .selfGuided), "the line is made")
    }

    /// The station master's words name the buttons as they are labelled.
    func testTheAdviceNamesTheButtonsAsLabelled() {
        XCTAssertEqual(StationMasterAdvice.buildTrack.text(in: .traditionalChinese), "歡迎！點左下的鐵鎚「建設」，鋪一段軌道吧。")
        XCTAssertEqual(StationMasterAdvice.createLine.text(in: .traditionalChinese), "車站都好了。打開「路線」，把它們連成一條路線。")
        XCTAssertTrue(StationMasterAdvice.createLine.isFirstLineStep)
        XCTAssertFalse(StationMasterAdvice.inDebt.isFirstLineStep)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FirstLineGuideTests-\(UUID().uuidString)", isDirectory: true)
    }
}
