import Foundation
import GameCore
import GamePresentation
import XCTest

/// The tutorial's interface (set ahead of Stage C5): the step on screen,
/// its text and the controls it is about, Next waiting until the player
/// has done what the step asks (read from the world and the session), Back,
/// Skip and starting again, after the `Ci/` reference's guided tour.
final class TutorialSessionTests: XCTestCase {
    private static let reach: Int64 = 512

    /// Next waits for each step's goal: the network tool chosen, then a
    /// stretch of track built; the last step needs only reading, and its
    /// Next (Done) ends the tutorial. Nothing in the world changes but
    /// what the player built.
    func testNextWaitsForEachStepAndDoneEndsTheTutorial() async throws {
        let world = try makeWorld(width: 16, height: 8, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            XCTAssertNil(session.tutorial)
            XCTAssertFalse(session.isTutorialStepDone, "no tutorial")

            session.startTutorial()
            var tutorial = session.tutorial
            XCTAssertEqual(tutorial?.index, 0)
            XCTAssertEqual(tutorial?.steps.count, 3)
            XCTAssertEqual(tutorial?.step.id, "demo.networkTool")
            XCTAssertEqual(tutorial?.step.targets, [.networkTool])
            XCTAssertEqual(tutorial?.step.goal, .chooseTool(.network))
            XCTAssertEqual(tutorial?.isFirstStep, true)
            XCTAssertEqual(tutorial?.isLastStep, false)
            XCTAssertFalse(session.isTutorialStepDone)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 0, "Next waits for the network tool")

            session.selectTool(.network)
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            tutorial = session.tutorial
            XCTAssertEqual(tutorial?.step.id, "demo.buildTrack")
            XCTAssertEqual(tutorial?.step.targets, [.map, .actionButton])
            XCTAssertEqual(tutorial?.step.goal, .buildTrack)
            XCTAssertFalse(session.isTutorialStepDone)

            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            XCTAssertFalse(session.isTutorialStepDone, "a preview builds nothing")
            session.buildNetworkTrack()
            XCTAssertEqual(session.world.network.edges.count, 1)
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            tutorial = session.tutorial
            XCTAssertEqual(tutorial?.step.id, "demo.end")
            XCTAssertEqual(tutorial?.step.targets, [], "the card in the middle")
            XCTAssertEqual(tutorial?.isLastStep, true)
            XCTAssertTrue(session.isTutorialStepDone, "reading is enough")

            session.showNextTutorialStep()
            XCTAssertNil(session.tutorial, "Done ends it")
        }
    }

    /// The track step waits for track built while it is on screen, not
    /// track that was already there; choosing another tool undoes the
    /// first step's goal.
    func testGoalsAreReadFromTheWorldAndTheSessionAsTheyAreNow() async throws {
        var world = try makeWorld(width: 16, height: 8, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        try world.buildTrackEdge(from: a, to: b)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.startTutorial()
            session.selectTool(.network)
            XCTAssertTrue(session.isTutorialStepDone)
            session.selectTool(.select)
            XCTAssertFalse(session.isTutorialStepDone, "the network tool is no longer chosen")
            session.selectTool(.network)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.goal, .buildTrack)
            XCTAssertFalse(session.isTutorialStepDone, "the edge was there before the step")

            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 10_240, y: 2_048), reach: Self.reach)
            session.buildNetworkTrack()
            XCTAssertEqual(session.world.network.edges.count, 2)
            XCTAssertTrue(session.isTutorialStepDone)
        }
    }

    /// Back goes to the step before (none on the first), Skip ends the
    /// tutorial at any step, and starting again begins at the first step.
    /// None of them changes the world.
    func testBackSkipAndStartingAgain() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.startTutorial()
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 0, "no step before the first")

            session.selectTool(.network)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 1)
            XCTAssertEqual(session.tutorial?.isFirstStep, false)
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 0)
            XCTAssertTrue(session.isTutorialStepDone, "the network tool is still chosen")

            session.showNextTutorialStep()
            session.startTutorial()
            XCTAssertEqual(session.tutorial?.index, 0, "from the first step again")

            session.skipTutorial()
            XCTAssertNil(session.tutorial)
            XCTAssertFalse(session.isTutorialStepDone)
            session.showNextTutorialStep()
            session.showPreviousTutorialStep()
            XCTAssertNil(session.tutorial, "nothing to move through")
            XCTAssertEqual(session.world, world)
        }
    }

    /// The start screen's tutorial entry starts a new game on the first
    /// step, keeping the autosave as starting a new game does.
    func testTheStartScreenStartsANewGameWithTheTutorial() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startTutorial()
            let session = try XCTUnwrap(launcher.session)
            XCTAssertEqual(session.world, .newGame())
            XCTAssertEqual(session.tutorial?.index, 0)
            XCTAssertEqual(session.tutorial?.steps, Tutorial.demoSteps)
        }
    }

    /// Every target has its own stable name, and the tool picker's buttons
    /// are named as their accessibility identifiers (`tool.<tool>`).
    func testEveryTargetHasItsOwnStableName() {
        let names = TutorialTarget.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names, [
            "tool.select", "tool.network", "tool.train", "network.modes", "panel.action",
            "map", "map.zoom", "hud.lines", "hud.speed", "hud.menu",
        ])
        for tool in ConstructionTool.networkTools {
            XCTAssertEqual(TutorialTarget(tool: tool)?.rawValue, "tool.\(tool)")
        }
        XCTAssertNil(TutorialTarget(tool: .buildTrack), "the grid's tools are not offered")
        XCTAssertNil(TutorialTarget(tool: .buildStation))
        XCTAssertNil(TutorialTarget(tool: .removeTrack))
    }

    /// Each step reads in both languages, the Chinese written out by hand.
    func testTheStepsReadInBothLanguages() {
        let steps = Tutorial.demoSteps
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        XCTAssertEqual(steps.map { $0.title(in: .english) }, ["Open the network tool", "Lay a stretch of track", "That's all for now"])
        XCTAssertEqual(steps.map { $0.title(in: .traditionalChinese) }, ["打開路網工具", "鋪一段軌道", "示範到此結束"])
        XCTAssertEqual(steps[1].body(in: .traditionalChinese), "在地圖上點軌道的起點，再點終點，然後按「鋪設軌道」。")
        for step in steps {
            XCTAssertFalse(step.body(in: .english).isEmpty, step.id)
            XCTAssertNotEqual(step.body(in: .traditionalChinese), step.body(in: .english), step.id)
        }
    }
}
