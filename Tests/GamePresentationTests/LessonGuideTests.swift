import GameCore
@testable import GamePresentation
import XCTest

/// Decision 376: lessons 3–6 guided one action a step by the tutorial's
/// engine (decision 188), each step pointing at its control and moving on
/// only once the player has done what it asks.
@MainActor
final class LessonGuideTests: XCTestCase {
    private static let reach: Int64 = 512

    /// The guides, the tutorial's own steps where they fit, and the ids an
    /// earlier guide had kept: a launch that kept one takes the guide up
    /// again there.
    func testTheGuidesOfLessonsThreeToSix() {
        XCTAssertEqual(Lesson.all[2].guide.map(\.id), ["lesson.3.lines", "lesson.addTrain", "lesson.3.loop", "time.play"])
        XCTAssertEqual(Lesson.all[3].guide.map(\.id), [
            "lesson.4", "lesson.4.track", "track.build", "station.mode", "lesson.4.site", "station.first.build", "lesson.4.done",
            "line.open", "lesson.4.stations", "line.create", "time.play",
        ])
        XCTAssertEqual(Lesson.all[4].guide.map(\.id), ["lesson.5", "lesson.5.double", "lesson.5.build", "time.play"])
        XCTAssertEqual(Lesson.all[5].guide.map(\.id), [
            "lesson.6", "lesson.6.advanced", "lesson.6.hours", "lesson.6.headway", "lesson.6.pattern", "time.play",
        ])
        let standard = Set(Tutorial.standardSteps.map(\.id))
        for lesson in Lesson.all[2...5] {
            for step in lesson.guide where standard.contains(step.id) {
                XCTAssertEqual(step, Tutorial.standardSteps.first { $0.id == step.id }, "\(step.id) is the tutorial's own")
            }
            XCTAssertTrue(lesson.guide.allSatisfy { $0.goal != .read }, "lesson \(lesson.number): every step is an action")
        }
        for (number, id) in [(3, "lesson.addTrain"), (4, "lesson.4"), (5, "lesson.5"), (6, "lesson.6")] {
            let session = GameSession(world: .newGame(lesson: Lesson.all[number - 1]), language: .english)
            session.keepTutorialToResume(atStep: id)
            session.resumeTutorial()
            XCTAssertEqual(session.tutorial?.step.id, id, "lesson \(number) is taken up again at the step kept")
        }
    }

    /// Each step reads in both languages, as short as the tutorial's own,
    /// and points at something.
    func testTheGuidesReadInBothLanguages() {
        for lesson in Lesson.all[2...5] {
            for step in lesson.guide {
                XCTAssertFalse(step.targets.isEmpty, "\(step.id) points at something")
                XCTAssertLessThanOrEqual(step.body(in: .english).count, 90, step.id)
                XCTAssertLessThanOrEqual(step.body(in: .traditionalChinese).count, 36, step.id)
                XCTAssertLessThanOrEqual(step.title(in: .english).count, 34, step.id)
                XCTAssertLessThanOrEqual(step.title(in: .traditionalChinese).count, 14, step.id)
                XCTAssertNotEqual(step.body(in: .traditionalChinese), step.body(in: .english), step.id)
            }
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertEqual(Set(lesson.guide.map { $0.title(in: language) }).count, lesson.guide.count, "lesson \(lesson.number)'s titles")
            }
        }
        XCTAssertEqual(Lesson.all[2].guide[1].title(in: .traditionalChinese), "按「加開一列車」")
        XCTAssertEqual(Lesson.all[4].guide[1].title(in: .traditionalChinese), "按「升級為複線」")
        // The panel scrolls to the control the step asks for.
        XCTAssertEqual(Lesson.all[2].guide[1].revealsInPanel, .addTrain)
        XCTAssertEqual(Lesson.all[5].guide.map(\.revealsInPanel), [nil, .advancedSwitch, .serviceHours, .headwayChange, .addPattern, nil])
        XCTAssertTrue(Lesson.all[4].guide[1].usesDetailsCard, "Make double track is on the details card")
    }

    /// Lesson 3: Lines, Add a Train, the passing loop, time.
    func testTheThirdLessonsGuide() throws {
        let session = start(3)
        step(session, "lesson.3.lines") { session.linesPanelDidChange(isShown: true) }
        XCTAssertNotNil(session.selectedLine, "the line is selected for its card")
        let trains = session.selectedLine?.trains.count ?? 0
        step(session, "lesson.addTrain") { session.addTrainToSelectedLine() }
        XCTAssertEqual(session.selectedLine?.trains.count, trains + 1)
        session.linesPanelDidChange(isShown: false)
        XCTAssertEqual(session.tutorial?.step.id, "lesson.3.loop")
        let loops = session.tutorialPlacesToTap
        XCTAssertFalse(loops.isEmpty, "the card keeps clear of the passing loops")
        let station = try XCTUnwrap(session.world.stations.first { !GameSession.isPassingPlace($0, in: session.world) })
        session.selectStation(station.id)
        XCTAssertFalse(session.isTutorialStepDone, "a station is not the loop")
        XCTAssertEqual(session.tutorialHint?.text, "That is a station. The passing loop is the one with no platform.")
        let loop = try XCTUnwrap(session.world.stations.first { GameSession.isPassingPlace($0, in: session.world) })
        XCTAssertTrue(loops.contains(loop.location))
        step(session, "lesson.3.loop") { session.selectStation(loop.id) }
        session.setSpeed(.paused)
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Lesson 4: track from the first town's station on to the third
    /// town, a station there and a second line between the two.
    func testTheFourthLessonsGuide() throws {
        let session = start(4)
        let towns = Lesson.towns(in: session.world.bounds)
        let lines = session.world.lines.count
        let first = try XCTUnwrap(session.world.stations.min { distance($0.location, towns[0]) < distance($1.location, towns[0]) })
        step(session, "lesson.4") { session.selectTool(.network) }
        // From the track's end beside the first town's station.
        let end = try XCTUnwrap(session.world.network.nodes.filter { $0.ends.count == 1 }.map { PlanPoint(x: $0.position.x, y: $0.position.y) }
            .min { distance($0, first.location) < distance($1, first.location) })
        step(session, "lesson.4.track") {
            session.tapNetwork(at: end, reach: Self.reach)
            XCTAssertEqual(session.tutorialHint?.text, "Now tap where it ends.")
            session.tapNetwork(at: towns[2], reach: Self.reach)
            XCTAssertNil(session.networkPreview?.problem)
        }
        step(session, "track.build") { session.buildNetworkTrack() }
        step(session, "station.mode") { session.setNetworkMode(.platform) }
        step(session, "lesson.4.site") { session.tapNetwork(at: towns[2], reach: Self.reach) }
        step(session, "station.first.build") { session.addNetworkPlatform() }
        let new = try XCTUnwrap(session.world.stations.last)
        step(session, "lesson.4.done") { session.selectTool(.select) }
        step(session, "line.open") { session.startPickingLineStops(announces: false) }
        step(session, "lesson.4.stations") {
            session.tapMap(at: first.location, reach: Self.reach)
            XCTAssertEqual(session.tutorialHint?.text, "Now tap the other station.")
            session.tapMap(at: new.location, reach: Self.reach)
        }
        step(session, "line.create") { session.createLineFromDraft() }
        XCTAssertEqual(session.world.lines.count, lines + 1)
        XCTAssertEqual(session.world.lines.last?.stops.first, first.id, "the second line starts at the first town's station")
        session.setSpeed(.paused)
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Lesson 5: a stretch of track picked, Make double track, ✓. The
    /// longest stretch, lesson 4's track on to the third town, has track
    /// too near it for a second: the hint says so and what else to try,
    /// and another stretch is picked, as a player would.
    func testTheFifthLessonsGuide() throws {
        let session = start(5)
        session.setSpeed(.paused)
        XCTAssertEqual(session.tutorial?.step.id, "lesson.5")
        session.selectStation(session.world.stations[0].id)
        XCTAssertEqual(session.tutorialHint?.text, "Tap the track between two stations, away from the trains.")
        let edges = session.world.network.edges.sorted { $0.length > $1.length }
        func tapTrack(_ edge: TrackEdge) {
            guard let geometry = session.world.trackGeometry(of: edge.id) else { return }
            for (part, whole) in [(1, 2), (1, 3), (2, 3)] as [(Int64, Int64)] where session.selectedTrackEdge != edge.id {
                let position = geometry.location(at: geometry.length * part / whole).position
                session.tapMap(at: PlanPoint(x: position.x, y: position.y), reach: Self.reach)
            }
        }
        step(session, "lesson.5") { tapTrack(edges[0]) }
        XCTAssertTrue(session.canDoubleSelectedTrack)
        step(session, "lesson.5.double") { session.beginTrackUpgrade(.doubleTrack) }
        XCTAssertEqual(session.tutorial?.step.id, "lesson.5.build")
        let problem = try XCTUnwrap(session.trackUpgradePreview?.problem)
        XCTAssertEqual(session.tutorialHint, TutorialHint(problem + " Try the other side, This piece only, or another stretch.", isProblem: true))
        var doubled = false
        for edge in edges.dropFirst() where !doubled {
            tapTrack(edge)
            guard session.selectedTrackEdge == edge.id, session.canDoubleSelectedTrack else { continue }
            session.beginTrackUpgrade(.doubleTrack)
            session.trackUpgradeWholeRun = false
            guard session.trackUpgradePreview?.problem == nil else { continue }
            XCTAssertFalse(session.isTutorialStepDone, "drafted, not built")
            session.buildTrackUpgrade()
            doubled = true
        }
        XCTAssertTrue(doubled, "a stretch that can be made double")
        XCTAssertTrue(session.isTutorialStepDone, "lesson.5.build is done")
        session.showNextTutorialStep()
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Lesson 6: Lines, Advanced, the line's hours, its headway, a
    /// stopping pattern, time.
    func testTheSixthLessonsGuide() throws {
        let session = start(6)
        step(session, "lesson.6") { session.linesPanelDidChange(isShown: true) }
        let line = try XCTUnwrap(session.selectedLine)
        step(session, "lesson.6.advanced") { session.linesAdvancedDidChange(isShown: true) }
        step(session, "lesson.6.hours") { session.setSelectedLineAllDay(line.window != .allDay) }
        let change = try XCTUnwrap(GameWorld.staffingHeadways.lazy.compactMap { session.world.lineHeadwayChange(line.id, headway: $0) }
            .first { !$0.isUnchanged && session.world.economy.canAfford($0.cost) })
        step(session, "lesson.6.headway") { session.changeSelectedLineHeadway(change) }
        step(session, "lesson.6.pattern") { session.addPatternToSelectedLine(from: 0, to: line.stops.count - 1, express: true) }
        XCTAssertEqual(session.selectedLine?.patterns.count, 1)
        session.setSpeed(.paused)
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// A step that changes a line waits for the lines panel, and says so.
    func testTheLineStepsSayToOpenLines() {
        let session = start(6)
        session.linesPanelDidChange(isShown: true)
        session.showNextTutorialStep()
        session.linesAdvancedDidChange(isShown: true)
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "lesson.6.hours")
        session.linesPanelDidChange(isShown: false)
        XCTAssertEqual(session.tutorialHint?.text, "Tap Lines to open your line.")
        XCTAssertFalse(session.isTutorialStepDone, "turning Advanced off and on again is not a change of hours")
    }

    // MARK: - Helpers

    /// Lesson `number`'s game with its guide on screen.
    private func start(_ number: Int) -> GameSession {
        let session = GameSession(world: .newGame(lesson: Lesson.all[number - 1]), language: .english)
        session.startTutorial()
        return session
    }

    /// Step `id` is on screen, waits until `action` is done, then is done
    /// and moves on with Next.
    private func step(_ session: GameSession, _ id: String, line: UInt = #line, _ action: () -> Void) {
        XCTAssertEqual(session.tutorial?.step.id, id, line: line)
        XCTAssertFalse(session.isTutorialStepDone, "\(id) waits for its action", line: line)
        action()
        XCTAssertTrue(session.isTutorialStepDone, "\(id) is done", line: line)
        XCTAssertTrue(session.tutorialAdvancesByItself, "\(id) moves on by itself", line: line)
        session.showNextTutorialStep()
    }

    /// The guide's last step: done, it waits for Finish, which ends it.
    private func lastStep(_ session: GameSession, _ id: String, line: UInt = #line, _ action: () -> Void) {
        XCTAssertEqual(session.tutorial?.step.id, id, line: line)
        XCTAssertTrue(session.tutorial?.isLastStep == true, line: line)
        XCTAssertFalse(session.isTutorialStepDone, line: line)
        action()
        XCTAssertTrue(session.isTutorialStepDone, line: line)
        session.showNextTutorialStep()
        XCTAssertNil(session.tutorial, "Finish ends the guide", line: line)
    }

    private func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
