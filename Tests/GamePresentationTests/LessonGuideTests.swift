import GameCore
@testable import GamePresentation
import XCTest

/// Decision 376: lessons 3–10 guided one action a step by the tutorial's
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
        XCTAssertEqual(Lesson.all[6].guide.map(\.id), [
            "lesson.7", "lesson.7.mode", "lesson.7.end", "lesson.7.build", "lesson.7.done", "lesson.7.lines", "lesson.7.depot", "lesson.7.hours",
            "time.play",
        ])
        XCTAssertEqual(Lesson.all[7].guide.map(\.id), [
            "lesson.8", "lesson.8.panel", "lesson.8.yard", "lesson.8.second", "lesson.8.panel2", "lesson.8.yard2",
            "line.open", "lesson.8.stations", "lesson.8.freight", "time.play",
        ])
        XCTAssertEqual(Lesson.all[8].guide.map(\.id), [
            "lesson.9", "lesson.9.track", "track.build", "station.mode", "lesson.9.site", "station.first.build", "lesson.9.done",
            "line.open", "lesson.9.stations", "line.create", "lesson.9.buildings", "lesson.9.hotel", "lesson.9.site.hotel", "lesson.9.put",
            "time.play",
        ])
        XCTAssertEqual(Lesson.all[9].guide.map(\.id), ["lesson.10", "time.play"])
        for lesson in Lesson.all[2...9] {
            for step in lesson.guide where standard.contains(step.id) {
                XCTAssertEqual(step, Tutorial.standardSteps.first { $0.id == step.id }, "\(step.id) is the tutorial's own")
            }
            XCTAssertTrue(lesson.guide.allSatisfy { $0.goal != .read }, "lesson \(lesson.number): every step is an action")
        }
        for (number, id) in [
            (3, "lesson.addTrain"), (4, "lesson.4"), (5, "lesson.5"), (6, "lesson.6"),
            (7, "lesson.7"), (8, "lesson.8"), (9, "lesson.9"), (10, "lesson.10"),
        ] {
            let session = GameSession(world: .newGame(lesson: Lesson.all[number - 1]), language: .english)
            session.keepTutorialToResume(atStep: id)
            session.resumeTutorial()
            XCTAssertEqual(session.tutorial?.step.id, id, "lesson \(number) is taken up again at the step kept")
        }
    }

    /// Each step reads in both languages, as short as the tutorial's own,
    /// and points at something (decision 390: lessons 1 and 2 too).
    func testTheGuidesReadInBothLanguages() {
        for lesson in Lesson.all {
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
        XCTAssertEqual(Lesson.all[6].guide[6].revealsInPanel, .lineDepot)
        XCTAssertEqual(Lesson.all[7].guide.compactMap(\.revealsInPanel), [.freightYard, .freightYard])
        XCTAssertTrue(Lesson.all[8].guide[11].usesDetailsCard, "Hotel is on the details card")
        XCTAssertEqual(Lesson.all[1].guide.compactMap(\.revealsInPanel), [.addSelectedStation, .lineLoss])
        XCTAssertEqual(Lesson.all[6].guide[7].revealsInPanel, .serviceHours)
    }

    /// Decision 390: lesson 1's cards say to run the track from one town
    /// to the other and put a station in each, which its goal asks for,
    /// and the card keeps clear of the two towns. The step is not held for
    /// it (docs/HANDOFF.md).
    func testTheFirstLessonsCardsLinkTheTwoTowns() throws {
        let guide = Lesson.all[0].guide
        XCTAssertEqual(guide.map(\.id), [
            "build.network", "map.move", "track.draw", "track.build", "station.mode", "station.first.site", "station.first.build",
            "station.second.site", "station.second.build", "build.done", "line.open", "line.stations", "line.create", "time.play",
            "first.fare",
        ])
        XCTAssertEqual(guide[2].title(in: .english), "Tap one town, then the other")
        XCTAssertEqual(guide[7].title(in: .traditionalChinese), "點另一座城鎮裡的軌道")
        for step in guide {
            let standard = try XCTUnwrap(Tutorial.standardSteps.first { $0.id == step.id }, step.id)
            XCTAssertEqual(step.goal, standard.goal, step.id)
            XCTAssertEqual(step.targets, standard.targets, step.id)
        }

        let session = start(1)
        session.setSpeed(.paused)
        let towns = Lesson.towns(in: session.world.bounds)
        step(session, "build.network") { session.selectTool(.network) }
        session.mapDidMove()
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "track.draw")
        XCTAssertEqual(Set(session.tutorialPlacesToTap), Set(towns.prefix(2)), "the card keeps clear of the two towns")
        // 400 m inside the first town: long enough, but short of the other.
        session.tapNetwork(at: towns[0], reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: towns[0].x + 400 * WorldCoordinate.unitsPerMetre, y: towns[0].y), reach: Self.reach)
        XCTAssertNil(session.networkPreview?.problem)
        XCTAssertTrue(session.isTutorialStepDone, "lesson 1's first track is not held")
        XCTAssertEqual(session.tutorialHint, nil, "a step done says nothing more")
        XCTAssertFalse(GameSession.passes(session.networkPreview?.points ?? [], within: Land.catchmentRadius, of: towns[1]))
        session.tapNetwork(at: towns[1], reach: Self.reach)
        XCTAssertTrue(GameSession.passes(session.networkPreview?.points ?? [], within: Land.catchmentRadius, of: towns[1]))
    }

    /// Decision 390, lesson 2: track from the station nearest the third
    /// town on to it, a station there and the station added to the line,
    /// one action each. Track or a station short of the town is not taken.
    func testTheSecondLessonsGuide() throws {
        let session = start(2)
        session.setSpeed(.paused)
        let towns = Lesson.towns(in: session.world.bounds)
        let line = try XCTUnwrap(session.world.lines.first)
        let first = try XCTUnwrap(session.world.stations.min { distance($0.location, towns[2]) < distance($1.location, towns[2]) })
        step(session, "lesson.extend") { session.selectTool(.network) }
        XCTAssertEqual(session.tutorialPlacesToTap, [towns[2]], "the card keeps clear of the third town")
        let end = try XCTUnwrap(session.world.network.nodes.filter { $0.ends.count == 1 }.map { PlanPoint(x: $0.position.x, y: $0.position.y) }
            .min { distance($0, first.location) < distance($1, first.location) })
        XCTAssertEqual(session.tutorial?.step.id, "lesson.2.track")
        session.tapNetwork(at: end, reach: Self.reach)
        // Halfway: long enough for stations, but not into the town.
        session.tapNetwork(at: PlanPoint(x: (end.x + towns[2].x) / 2, y: (end.y + towns[2].y) / 2), reach: Self.reach)
        XCTAssertNil(session.networkPreview?.problem)
        XCTAssertFalse(session.isTutorialStepDone, "track short of the third town is not taken")
        XCTAssertEqual(session.tutorialHint?.text, "It doesn't reach the town yet. Tap the end among its houses.")
        session.tapNetwork(at: towns[2], reach: Self.reach)
        XCTAssertTrue(session.isTutorialStepDone, "lesson.2.track is done")
        session.showNextTutorialStep()
        step(session, "track.build") { session.buildNetworkTrack() }
        step(session, "station.mode") { session.setNetworkMode(.platform) }
        XCTAssertEqual(session.tutorial?.step.id, "lesson.2.site")
        // On the new track, but outside the town.
        let track = try XCTUnwrap(session.world.network.edges.last.flatMap { session.world.trackGeometry(of: $0.id) })
        session.tapNetwork(at: track.location(at: track.length / 4).position.plan, reach: Self.reach)
        XCTAssertNotNil(session.platformSitePlanPoint)
        XCTAssertFalse(session.isTutorialStepDone, "a station outside the third town is not taken")
        XCTAssertEqual(
            session.tutorialHint?.text, "That spot is outside the town that needs a station. Tap your track there."
        )
        session.tapNetwork(at: towns[2], reach: Self.reach)
        XCTAssertTrue(session.isTutorialStepDone, "lesson.2.site is done")
        session.showNextTutorialStep()
        step(session, "station.first.build") { session.addNetworkPlatform() }
        let new = try XCTUnwrap(session.world.stations.last)
        step(session, "lesson.2.done") { session.selectTool(.select) }
        XCTAssertEqual(session.tutorialPlacesToTap, [new.location])
        session.selectStation(first.id)
        XCTAssertFalse(session.isTutorialStepDone, "a station on the line already")
        XCTAssertEqual(session.tutorialHint?.text, "That station is on a line already. Tap the new one.")
        step(session, "lesson.2.station") { session.selectStation(new.id) }
        step(session, "lesson.2.lines") { session.linesPanelDidChange(isShown: true) }
        XCTAssertEqual(session.selectedLineID, line.id)
        XCTAssertEqual(session.selectedStationID, new.id, "the station stays picked for the button")
        step(session, "lesson.2.add") { session.addStationToSelectedLine(new.id) }
        XCTAssertTrue(session.world.lines.first?.stops.contains(new.id) == true)
        XCTAssertEqual(session.tutorial?.step.id, "line.card.read", "the panel is open: its step is passed over")
        XCTAssertTrue(session.world.isMet(Lesson.all[1].challenge.scenario(seed: Lesson.seed, in: session.world.bounds).goals[0]))
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

    /// Lesson 5: a stretch of track, Make double track, ✓, time. Decision
    /// 378: the card keeps clear of the stretch the guide points at, the
    /// hint says where it is, and it is built at the first try.
    func testTheFifthLessonsGuide() throws {
        let session = start(5)
        session.setSpeed(.paused)
        XCTAssertEqual(session.tutorial?.step.id, "lesson.5")
        let stretch = try XCTUnwrap(session.tutorialDoubleTrackStretch)
        XCTAssertEqual(session.tutorialPlacesToTap.count, 1, "the card keeps clear of the stretch")
        let place = try XCTUnwrap(session.tutorialPlacesToTap.first)
        XCTAssertEqual(session.tutorialHint?.text, "Tap the track by \u{201C}S1\u{201D}, with no train on it.")
        session.selectStation(session.world.stations[0].id)
        XCTAssertFalse(session.isTutorialStepDone, "a station is not track")
        step(session, "lesson.5") { session.tapMap(at: place, reach: Self.reach) }
        XCTAssertEqual(session.selectedTrackEdge, stretch)
        XCTAssertTrue(session.canDoubleSelectedTrack)
        step(session, "lesson.5.double") { session.beginTrackUpgrade(.doubleTrack) }
        XCTAssertEqual(session.tutorial?.step.id, "lesson.5.build")
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        XCTAssertTrue(preview.note?.contains("Crossovers join the two tracks at both ends.") ?? false, preview.note ?? "")
        XCTAssertNil(session.tutorialHint)
        XCTAssertFalse(session.isTutorialStepDone, "drafted, not built")
        session.buildTrackUpgrade()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.isTutorialStepDone, "lesson.5.build is done")
        session.showNextTutorialStep()
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Decision 378: lesson 5's longest track, out to the third town, is
    /// no longer refused for running within 4 m of itself (its second
    /// track is laid in pieces round its sharp curve); it costs more than
    /// the lesson's cash, and the hint points to the stretch that can be
    /// built.
    func testTheFifthLessonsLongestTrackSaysWhatItCostsAndWhereToGo() throws {
        for whole in [true, false] {
            let session = start(5)
            session.setSpeed(.paused)
            let longest = try XCTUnwrap(session.world.network.edges.max { $0.length < $1.length })
            XCTAssertNotEqual(longest.id, session.tutorialDoubleTrackStretch, "a train stands at its station")
            let geometry = try XCTUnwrap(session.world.trackGeometry(of: longest.id))
            session.tapMap(at: geometry.location(at: geometry.length / 3).position.plan, reach: Self.reach)
            XCTAssertEqual(session.selectedTrackEdge, longest.id)
            session.showNextTutorialStep()
            session.trackUpgradeWholeRun = whole
            session.beginTrackUpgrade(.doubleTrack)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "lesson.5.build")
            let draft = try XCTUnwrap(session.trackUpgradeDraft)
            XCTAssertNotNil(draft.command, "the second track is laid: it is only too dear")
            let problem = try XCTUnwrap(draft.preview.problem)
            XCTAssertTrue(problem.hasPrefix("Not enough cash"), problem)
            XCTAssertEqual(session.tutorialHint, TutorialHint(problem + " Tap the track by \u{201C}S1\u{201D}, with no train on it.", isProblem: true))
        }
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

    /// Lesson 7: Build, Depot, the end of a track, its sidings, Done,
    /// Lines, the line's depot ticked, time.
    func testTheSeventhLessonsGuide() throws {
        let session = start(7)
        session.setSpeed(.paused)
        step(session, "lesson.7") { session.selectTool(.network) }
        step(session, "lesson.7.mode") { session.setNetworkMode(.depot) }
        let ends = session.tutorialPlacesToTap
        XCTAssertFalse(ends.isEmpty, "the card keeps clear of the ends of the tracks")
        XCTAssertEqual(session.tutorialHint?.text, "Tap where a track ends.")
        var built = false
        for end in ends where !built {
            session.tapNetwork(at: end, reach: Self.reach)
            guard session.networkDepotPreview?.problem == nil else {
                XCTAssertEqual(session.tutorialHint?.isProblem, true, "a refused end says why")
                continue
            }
            XCTAssertTrue(session.isTutorialStepDone, "lesson.7.end is done")
            session.showNextTutorialStep()
            step(session, "lesson.7.build") { session.addDepotYard() }
            built = true
        }
        XCTAssertTrue(built, "an end a depot can go at")
        step(session, "lesson.7.done") { session.selectTool(.select) }
        step(session, "lesson.7.lines") { session.linesPanelDidChange(isShown: true) }
        let line = try XCTUnwrap(session.selectedLine)
        let depot = try XCTUnwrap(session.world.depotRow(of: line.id, in: .english)?.choices.first, "the line selected can use the depot")
        step(session, "lesson.7.depot") { session.toggleSelectedLineDepot(depot.station) }
        XCTAssertEqual(session.selectedLine?.depots, [depot.station])
        // Decision 390: the lessons' lines run all day; at 06:00–24:00 the
        // trains go to the depot after the last.
        XCTAssertEqual(session.selectedLine?.window, .allDay)
        step(session, "lesson.7.hours") { session.setSelectedLineAllDay(false) }
        XCTAssertNotEqual(session.selectedLine?.window, .allDay)
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Review G: lessons 6 and 7 taken up again after the app was closed
    /// at a step that asks for a change to a line (its hours, its headway,
    /// a stopping pattern, its depot): the change made after resuming
    /// moves the guide on, as it does in a lesson never left.
    func testALessonTakenUpAgainMovesOnWithAChangeToALine() throws {
        let six = GameSession(world: .newGame(lesson: Lesson.all[5]), language: .english)
        six.keepTutorialToResume(atStep: "lesson.6.hours")
        six.resumeTutorial()
        six.linesPanelDidChange(isShown: true)
        let line = try XCTUnwrap(six.world.lines.first)
        six.selectLine(line.id)
        step(six, "lesson.6.hours") { six.setSelectedLineAllDay(line.window != .allDay) }
        let change = try XCTUnwrap(GameWorld.staffingHeadways.lazy.compactMap { six.world.lineHeadwayChange(line.id, headway: $0) }
            .first { !$0.isUnchanged && six.world.economy.canAfford($0.cost) })
        step(six, "lesson.6.headway") { six.changeSelectedLineHeadway(change) }
        step(six, "lesson.6.pattern") { six.addPatternToSelectedLine(from: 0, to: line.stops.count - 1, express: true) }

        // Lesson 7, closed with its depot built, at the line's depot.
        let seven = start(7)
        seven.setSpeed(.paused)
        step(seven, "lesson.7") { seven.selectTool(.network) }
        step(seven, "lesson.7.mode") { seven.setNetworkMode(.depot) }
        var built = false
        for end in seven.tutorialPlacesToTap where !built {
            seven.tapNetwork(at: end, reach: Self.reach)
            guard seven.networkDepotPreview?.problem == nil else { continue }
            seven.showNextTutorialStep()
            seven.addDepotYard()
            built = true
        }
        XCTAssertTrue(built, "an end a depot can go at")
        let resumed = GameSession(world: seven.world, language: .english)
        resumed.keepTutorialToResume(atStep: "lesson.7.depot")
        resumed.resumeTutorial()
        resumed.linesPanelDidChange(isShown: true)
        let depotLine = try XCTUnwrap(resumed.world.lines.first)
        resumed.selectLine(depotLine.id)
        let depot = try XCTUnwrap(resumed.world.depotRow(of: depotLine.id, in: .english)?.choices.first)
        step(resumed, "lesson.7.depot") { resumed.toggleSelectedLineDepot(depot.station) }
    }

    /// Review H: in lesson 2, a short stretch built with ✓ short of the
    /// third town, then a stretch drawn on to the town, leaves the guide
    /// at "Tap ✓", not past it: the stretch that reaches is not built yet.
    func testTheSecondLessonWaitsForTheStretchThatReachesTheTownToBeBuilt() throws {
        let session = start(2)
        session.setSpeed(.paused)
        let town = Lesson.towns(in: session.world.bounds)[2]
        func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
            let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        let nearest = try XCTUnwrap(session.world.stations.min { distance($0.location, town) < distance($1.location, town) })
        session.selectTool(.network)
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "lesson.2.track")
        let end = try XCTUnwrap(session.world.network.nodes.filter { $0.ends.count == 1 }.map { PlanPoint(x: $0.position.x, y: $0.position.y) }
            .min { distance($0, nearest.location) < distance($1, nearest.location) })
        session.tapNetwork(at: end, reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: (end.x + town.x) / 2, y: (end.y + town.y) / 2), reach: Self.reach)
        XCTAssertFalse(session.isTutorialStepDone)
        session.buildNetworkTrack()
        let edges = session.world.network.edges.count
        session.tapNetwork(at: town, reach: Self.reach)
        XCTAssertTrue(session.isTutorialStepDone, "the stretch drawn reaches the town")
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "track.build")
        XCTAssertFalse(session.isTutorialStepDone, "the stretch that reaches the town is not built yet")
        XCTAssertEqual(session.world.network.edges.count, edges)
        session.buildNetworkTrack()
        XCTAssertTrue(session.isTutorialStepDone)
    }

    /// Review H: lesson 2 taken up again at its track step (the app closed
    /// there) still waits for track to the third town, as a lesson never
    /// left does: the railway the lesson began with is not that track.
    func testTheSecondLessonTakenUpAgainStillWaitsForTrackToTheTown() throws {
        let session = GameSession(world: .newGame(lesson: Lesson.all[1]), language: .english)
        session.setSpeed(.paused)
        session.keepTutorialToResume(atStep: "lesson.2.track")
        session.resumeTutorial()
        XCTAssertEqual(session.tutorial?.step.id, "lesson.2.track")
        session.selectTool(.network)
        XCTAssertFalse(session.isTutorialStepDone, "nothing is built toward the third town")
    }

    /// Lesson 8: a freight yard at two stations, through the station
    /// panel, then a freight line between them from the new line's card.
    func testTheEighthLessonsGuide() throws {
        let session = start(8)
        session.setSpeed(.paused)
        let stations = session.world.stations.filter { GameSession.takesFreightYard($0, in: session.world) }
        XCTAssertGreaterThanOrEqual(stations.count, 2)
        XCTAssertEqual(Set(session.tutorialPlacesToTap), Set(stations.map(\.location)))
        step(session, "lesson.8") { session.selectStation(stations[0].id) }
        XCTAssertEqual(session.tutorialHint?.text, nil)
        step(session, "lesson.8.panel") { session.stationPanelDidChange(isShown: true) }
        step(session, "lesson.8.yard") { session.buildFreightYardAtSelectedStation() }
        session.stationPanelDidChange(isShown: false)
        XCTAssertEqual(session.tutorial?.step.id, "lesson.8.second")
        XCTAssertFalse(session.isTutorialStepDone, "the first station has its yard")
        XCTAssertEqual(session.tutorialHint?.text, "That station has a freight yard. Tap another one.")
        let second = stations.last!
        step(session, "lesson.8.second") { session.selectStation(second.id) }
        step(session, "lesson.8.panel2") { session.stationPanelDidChange(isShown: true) }
        step(session, "lesson.8.yard2") { session.buildFreightYardAtSelectedStation() }
        session.stationPanelDidChange(isShown: false)
        let lines = session.world.lines.count
        step(session, "line.open") { session.startPickingLineStops(announces: false) }
        step(session, "lesson.8.stations") {
            session.tapMap(at: stations[0].location, reach: Self.reach)
            session.tapMap(at: second.location, reach: Self.reach)
        }
        XCTAssertEqual(session.tutorial?.step.id, "lesson.8.freight")
        session.confirmLineDraft()
        XCTAssertTrue(session.lineConfirmationOffersFreight, "both stops have a freight yard")
        // On the first morning the two yards leave too little for the
        // train: the card says so, and the fares pay for it as time runs.
        let shortfall = try XCTUnwrap(session.lineConfirmationPreview?.shortfall)
        XCTAssertEqual(session.tutorialHint, TutorialHint(shortfall + " " + Self.faresRemedy, isProblem: true))
        earn(session) { session.lineConfirmationPreview?.shortfall == nil }
        XCTAssertNil(session.lineConfirmationPreview?.shortfall, "the fares paid for it")
        XCTAssertEqual(session.tutorialHint?.text, "Turn on Freight line on the card.")
        step(session, "lesson.8.freight") {
            session.updateLineConfirmation { var card = $0; card.isFreight = true; return card }
            XCTAssertNil(session.lineConfirmationPreview?.shortfall)
            session.confirmLine()
        }
        XCTAssertEqual(session.world.lines.count, lines + 1)
        let freight = try XCTUnwrap(session.world.lines.last)
        XCTAssertTrue(freight.isFreight)
        XCTAssertFalse(freight.assignedTrains.isEmpty, "the freight line opens with its train")
        XCTAssertTrue(session.world.isFreightTrain(freight.assignedTrains[0]))
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Lesson 9: track from the second town's station to the sight, a
    /// station there, a line to it, then a hotel beside it.
    func testTheNinthLessonsGuide() throws {
        let session = start(9)
        session.setSpeed(.paused)
        let towns = Lesson.towns(in: session.world.bounds)
        let sight = Lesson.sight(in: session.world.bounds)
        let second = try XCTUnwrap(session.world.stations.min { distance($0.location, towns[1]) < distance($1.location, towns[1]) })
        step(session, "lesson.9") { session.selectTool(.network) }
        let end = try XCTUnwrap(session.world.network.nodes.filter { $0.ends.count == 1 }.map { PlanPoint(x: $0.position.x, y: $0.position.y) }
            .min { distance($0, second.location) < distance($1, second.location) })
        step(session, "lesson.9.track") {
            session.tapNetwork(at: end, reach: Self.reach)
            session.tapNetwork(at: sight, reach: Self.reach)
            XCTAssertNil(session.networkPreview?.problem)
        }
        step(session, "track.build") { session.buildNetworkTrack() }
        step(session, "station.mode") { session.setNetworkMode(.platform) }
        step(session, "lesson.9.site") { session.tapNetwork(at: sight, reach: Self.reach) }
        // The track to the sight leaves too little for its station on the
        // first morning: the card says to let the fares come in.
        XCTAssertEqual(session.tutorial?.step.id, "station.first.build")
        session.addNetworkPlatform()
        let refused = try XCTUnwrap(session.message?.text)
        XCTAssertEqual(session.tutorialHint, TutorialHint(refused + " " + Self.faresRemedy, isProblem: true))
        earn(session) { session.networkPlatformCost.map(session.world.economy.canAfford) == true }
        step(session, "station.first.build") { session.addNetworkPlatform() }
        let new = try XCTUnwrap(session.world.stations.last)
        step(session, "lesson.9.done") { session.selectTool(.select) }
        step(session, "line.open") { session.startPickingLineStops(announces: false) }
        step(session, "lesson.9.stations") {
            session.tapMap(at: second.location, reach: Self.reach)
            session.tapMap(at: new.location, reach: Self.reach)
        }
        let lines = session.world.lines.count
        step(session, "line.create") { session.confirmLineDraft() }
        XCTAssertEqual(session.world.lines.count, lines + 1)
        step(session, "lesson.9.buildings") { session.selectTool(.building) }
        XCTAssertNotEqual(session.buildingKind, .hotel)
        step(session, "lesson.9.hotel") { session.buildingKind = .hotel }
        // A site within the sight's reach, clear of the track: refused, if
        // at all, only for the cash.
        let attraction = try XCTUnwrap(session.world.tourism?.attractions.first { distance($0.point, sight) == 0 })
        let around = (1...12).flatMap { ring in
            (0..<8).map { turn -> PlanPoint in
                let dx: [Int64] = [1, 1, 0, -1, -1, -1, 0, 1], dy: [Int64] = [0, 1, 1, 1, 0, -1, -1, -1]
                return PlanPoint(x: sight.x + dx[turn] * Int64(ring) * Self.reach, y: sight.y + dy[turn] * Int64(ring) * Self.reach)
            }
        }
        let site = try XCTUnwrap(around.first { point in
            guard session.world.bounds.contains(point) else { return false }
            session.buildingSite = point
            defer { session.buildingSite = nil }
            guard let preview = session.buildingPreview, let cost = preview.cost else { return false }
            return preview.problem == nil || !session.world.economy.canAfford(cost)
        })
        // A hotel costs more than the first days leave: the card says to let
        // the fares come in, and the site is taken once they have.
        session.tapBuildingTool(at: site, reach: Self.reach)
        let problem = try XCTUnwrap(session.buildingPreview?.problem)
        XCTAssertEqual(session.tutorialHint, TutorialHint(problem + " " + Self.faresRemedy, isProblem: true))
        XCTAssertEqual(session.tutorial?.step.id, "lesson.9.site.hotel")
        earn(session, rounds: 240) { session.isTutorialStepDone }
        XCTAssertNil(session.buildingPreview?.problem)
        XCTAssertTrue(session.tutorialAdvancesByItself)
        session.showNextTutorialStep()
        step(session, "lesson.9.put") { session.confirmBuilding() }
        XCTAssertEqual(session.world.placedBuildings.last?.kind, .hotel)
        XCTAssertEqual(session.world.hotelsNear(attraction), 1, "the hotel adds to the sight's stars")
        lastStep(session, "time.play") { session.setSpeed(.normal) }
    }

    /// Lesson 10: one of the city's requests taken on.
    func testTheTenthLessonsGuide() throws {
        let session = start(10)
        session.setSpeed(.paused)
        let offer = try XCTUnwrap(session.world.cityRequests?.offers.first, "the city asks from the lesson's first day")
        step(session, "lesson.10") { session.acceptRequest(offer.id) }
        XCTAssertEqual(session.world.cityRequests?.active.map(\.id), [offer.id])
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

    private static let faresRemedy = "Tap \u{25B6}\u{FE0E} and let fares come in."

    /// Runs the game, an hour at a time for at most two days, until
    /// `enough`, then pauses it again.
    private func earn(_ session: GameSession, rounds: Int = 48, line: UInt = #line, until enough: () -> Bool) {
        // ▶︎ again whenever an event paused the game.
        for _ in 0..<rounds where !enough() {
            session.setSpeed(.normal)
            if session.world.clock.isPaused { session.togglePause() }
            session.advance(ticks: 60)
        }
        session.setSpeed(.paused)
        XCTAssertTrue(enough(), "the fares paid for it", line: line)
    }

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
        XCTAssertNil(session.tutorial?.step.id, "Finish ends the guide", line: line)
    }

    private func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
