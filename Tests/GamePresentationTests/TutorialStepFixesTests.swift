import Foundation
import GameCore
import GamePresentation
import XCTest

/// The AI testers' first round (2026-11-23, `UI-TESTERS-ROUND1` rows 4 and
/// 5): lesson 1's last step, the first fares, kept its folded card after
/// the fares came in, with no Finish to tap; and a skipped step left the
/// steps after it impossible, with nothing on the card saying why (the
/// station mode skipped, tapping the track drew track instead of picking
/// a station's place, and no ✓ came).
final class TutorialStepFixesTests: XCTestCase {
    private static let reach: Int64 = 512
    private static let tile: Int64 = 1_024

    /// Where the walk lays its track, as `-tutorial-step` does
    /// (``GameLauncher/startTutorial(atStep:)``).
    @MainActor
    private static func point(_ x: Int64, in session: GameSession) -> PlanPoint {
        let bounds = session.world.bounds
        return PlanPoint(x: bounds.width / 2 - 8 * tile + x * tile, y: bounds.height / 2)
    }

    // MARK: - The last step, done

    /// The last step does not move on by itself (decision 177): done, its
    /// card opens, folded or not, so Finish shows; the player's own choice
    /// on the step still holds. Before it is done it stays as any action
    /// step, folded.
    func testTheLastStepOpensOnceDoneSoFinishShows() {
        let fold = TutorialCardFold()
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: true, isLastStep: true))
        XCTAssertFalse(fold.showsFolded(stepChoice: nil, chapterChoice: true, waitsForNext: false, isDone: true, isLastStep: true))
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: false, isLastStep: true))
        XCTAssertTrue(fold.showsFolded(stepChoice: true, chapterChoice: nil, waitsForNext: false, isDone: true, isLastStep: true))
        // Any other action step, done, still moves on folded.
        XCTAssertTrue(fold.showsFolded(stepChoice: nil, chapterChoice: nil, waitsForNext: false, isDone: true))
    }

    /// Lesson 1's guide ends on the first fares (decision 266): once they
    /// are in, the card says to tap Finish, in both languages; before,
    /// and on every step that moves on by itself, it does not.
    func testLessonOnesFareStepSaysToTapFinishOnceTheFaresAreIn() async throws {
        for (language, prompt) in [
            (DisplayLanguage.english, "Fares are in. Tap Finish."), (.traditionalChinese, "車資進帳了，按「完成教學」。"),
        ] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialStepFixesTests-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try await MainActor.run {
                let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: language)
                launcher.startTutorial(atStep: "first.fare")
                let session = try XCTUnwrap(launcher.session)
                XCTAssertEqual(session.tutorial?.step.id, "first.fare")
                XCTAssertEqual(session.tutorial?.isLastStep, true)
                XCTAssertEqual(session.tutorial?.index, 14, "step 15")
                XCTAssertFalse(session.isTutorialStepDone)
                XCTAssertNil(session.tutorialFinishPrompt)
                if session.world.clock.isPaused { session.togglePause() }
                let end = session.world.clock.now.seconds + 2 * GameTime.secondsPerDay
                while !session.isTutorialStepDone, session.world.clock.now.seconds < end {
                    session.advance(realElapsed: GameSession.maximumStepDuration)
                }
                XCTAssertTrue(session.isTutorialStepDone, "no fares in two days")
                XCTAssertFalse(session.tutorialAdvancesByItself, "the last step waits for Finish")
                XCTAssertEqual(session.tutorialFinishPrompt, prompt)
                session.showNextTutorialStep()
                XCTAssertNil(session.tutorial)
                XCTAssertNil(session.tutorialFinishPrompt)
            }
        }
    }

    // MARK: - Skipping a step

    /// Skipping "Tap Station" chose the mode for the player: the next step,
    /// tapping the track, picks the station's place, and its ✓ comes.
    func testSkippingTheStationModeChoosesItSoTheTrackCanBeTapped() async {
        await MainActor.run {
            let session = GameSession(world: GameWorld.newGame(lesson: Lesson.all[0]), language: .english)
            session.startTutorial()
            XCTAssertEqual(session.tutorial?.step.id, "build.network")
            session.selectTool(.network)
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.draw")
            session.tapNetwork(at: Self.point(2, in: session), reach: Self.reach)
            session.tapNetwork(at: Self.point(13, in: session), reach: Self.reach)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.build")
            session.buildNetworkTrack()
            XCTAssertFalse(session.world.network.edges.isEmpty)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.mode")
            XCTAssertEqual(session.networkMode, .build)

            session.skipTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.first.site")
            XCTAssertEqual(session.tool, .network)
            XCTAssertEqual(session.networkMode, .platform, "the skipped step's choice is made")
            session.tapNetwork(at: Self.point(4, in: session), reach: Self.reach)
            XCTAssertTrue(session.isTutorialStepDone, "the track's tap picks the station's place")
            XCTAssertNotNil(session.networkEdgePoint, "the ✓ shows")
        }
    }

    /// Switched to another mode on a station step, the card says to tap
    /// Station first.
    func testAStationStepInAnotherModeSaysToTapStation() async {
        for (language, hint) in [
            (DisplayLanguage.english, "Tap Station first, then your track."), (.traditionalChinese, "先點「車站」，再點軌道。"),
        ] {
            await MainActor.run {
                let session = GameSession(world: GameWorld.newGame(lesson: Lesson.all[0]), language: language)
                session.startTutorial()
                session.selectTool(.network)
                session.tapNetwork(at: Self.point(2, in: session), reach: Self.reach)
                session.tapNetwork(at: Self.point(13, in: session), reach: Self.reach)
                session.buildNetworkTrack()
                session.showNextTutorialStep()
                XCTAssertEqual(session.tutorial?.step.id, "map.move")
                session.skipTutorialStep()
                XCTAssertEqual(session.tutorial?.step.id, "station.mode", "the track steps, done ahead, are passed over")
                session.skipTutorialStep()
                XCTAssertEqual(session.tutorial?.step.id, "station.first.site")
                session.setNetworkMode(.build)
                XCTAssertFalse(session.isTutorialStepDone)
                XCTAssertEqual(session.tutorialHint?.text, hint)
            }
        }
    }

    /// Skipping every step of a new game: each step whose action needs what
    /// a skipped step was to build says what is missing and how to build
    /// it, instead of waiting for a tap that cannot work. The tools and
    /// modes the skipped steps chose are chosen for the player.
    func testSkippedStepsSayWhatIsMissing() async {
        let texts: [(DisplayLanguage, track: String, stations: String, line: String)] = [
            (.english, "No track yet. Tap Lay, then where it starts and where it ends, then ✓.",
             "A line needs two stations. Tap Build, then Station, then your track.",
             "No line yet. Tap Lines, then Pick on Map and your two stations."),
            (.traditionalChinese, "還沒有軌道。點「鋪設」，點起點和終點，再按 ✓。",
             "路線要兩座車站。點「建設」，再點「車站」和你的軌道。",
             "還沒有路線。點「路線」，按「在地圖上選站」，再點兩座車站。"),
        ]
        for text in texts {
            await MainActor.run {
                let session = GameSession(world: GameWorld.newGame(lesson: Lesson.all[0]), language: text.0)
                session.startTutorial()
                var hints: [String: String] = [:]
                var tools: [String: ConstructionTool] = [:]
                while let tutorial = session.tutorial, !tutorial.isLastStep {
                    hints[tutorial.step.id] = session.tutorialHint?.text
                    tools[tutorial.step.id] = session.tool
                    session.skipTutorialStep()
                    XCTAssertNotEqual(session.tutorial?.index, tutorial.index, "\(tutorial.step.id) skipped")
                }
                hints["first.fare"] = session.tutorialHint?.text
                XCTAssertEqual(hints["station.mode"], text.track)
                XCTAssertEqual(hints["station.first.site"], text.track)
                XCTAssertEqual(hints["station.second.build"], text.track)
                XCTAssertEqual(tools["station.mode"], .network, "Build's skipped step chose the network tool")
                XCTAssertEqual(hints["line.open"], text.stations)
                XCTAssertEqual(hints["line.create"], text.stations)
                XCTAssertEqual(tools["line.open"], .select, "✕'s skipped step put the tools away")
                XCTAssertEqual(hints["first.fare"], text.line)
            }
        }
    }
}
