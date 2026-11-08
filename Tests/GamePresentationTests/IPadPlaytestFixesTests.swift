import GameCore
@testable import GamePresentation
import XCTest

/// Decision 643: the iPad playtest of 2026-11-08
/// (`docs/research/MAC_PLAYTEST_2026-11-08.md` §6), the parts that are
/// worked out off Apple's platforms.
@MainActor
final class IPadPlaytestFixesTests: XCTestCase {
    /// An iPad Pro 13-inch held on its side, with what covers its map at
    /// lesson 1's track step, measured from
    /// `docs/art/mac-playtest-2026-11-08/ipad/tutorial-3-town-under-toolbar.jpg`:
    /// the status bar and the tools column, the building panel on the
    /// trailing third and the dock along the bottom.
    private static let viewport = ScreenSize(width: 1376, height: 1032)
    private static let cover = ScreenInsets(top: 92, leading: 82, bottom: 105, trailing: 350)

    /// A1: the track step frames both towns with their walking rings,
    /// clear of the panel and the dock, however far the player zoomed out
    /// at the step before (zoomed all the way out, the second town lay
    /// under the dock).
    func testTheTrackStepFramesBothTownsClearOfThePanelAndTheDock() throws {
        let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .english)
        session.startTutorial()
        XCTAssertNil(session.tutorialFraming, "the first step leaves the map as it opened")
        session.selectTool(.network)
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "map.move")
        XCTAssertNil(session.tutorialFraming, "the player zooms out themselves")
        session.mapDidMove()
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "track.draw")
        let region = try XCTUnwrap(session.tutorialFraming)
        let towns = Lesson.towns(in: session.world.bounds).prefix(2)
        for town in towns {
            XCTAssertTrue(region.contains(WorldCoordinate(x: town.x, y: town.y)))
        }

        let bounds = session.world.bounds
        let opening = PlanCamera(bounds: bounds, viewport: Self.viewport, showing: WorldRegion.opening(in: session.world))
        // Zoomed out twice from the opening, the first town in the middle:
        // the second lay under the dock on the iPad.
        let zoomedOut = opening.zoomedOut().zoomedOut()
        // Dragged so the first town sits under the panel.
        let dragged = opening.panned(byX: -400, y: 0)
        for start in [opening, zoomedOut, dragged] {
            let framed = try XCTUnwrap(start.framing(region, clearOf: Self.cover), "a town is hidden from \(start.pointsPerUnit)")
            for town in towns {
                let reach = Land.catchmentRadius
                for corner in [(-reach, -reach), (-reach, reach), (reach, -reach), (reach, reach)] {
                    let point = WorldCoordinate(x: town.x + corner.0, y: town.y + corner.1)
                    XCTAssertTrue(framed.showsClear(point, of: Self.cover), "\(point) is under the panel or the dock")
                }
            }
            XCTAssertNil(framed.framing(region, clearOf: Self.cover), "framed once, it stays as it is")
        }

        // The next step leaves the camera to the player.
        session.tapNetwork(at: towns.first!, reach: 512)
        session.tapNetwork(at: towns.last!, reach: 512)
        session.buildNetworkTrack()
        session.showNextTutorialStep()
        XCTAssertNotEqual(session.tutorial?.step.id, "track.draw")
        XCTAssertNil(session.tutorialFraming)
    }

    /// Decision 658: what the iPad's tutorial walk (TutorialJourneyUITests)
    /// does once the track step has framed both towns. Laid as the card
    /// says, from one town's middle to the other's, with a station 8 % in
    /// from each end, the line earns its first fares on the first day.
    /// Zoomed back in about the framing's middle and laid along one row,
    /// as the phone's walk does, the stations stood 2.6–3.2 km from either
    /// town and no fares came in three days (0.6.0 (122)'s full lane, run
    /// 42489862739).
    func testTheIPadWalkFromTownToTownEarnsItsFirstFares() throws {
        func walk(townToTown: Bool) throws -> (fares: Bool, nearest: [Double]) {
            let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .english)
            session.startTutorial()
            var camera = PlanCamera(bounds: session.world.bounds, viewport: Self.viewport, showing: WorldRegion.opening(in: session.world)).zoomedOut()
            let towns = Lesson.towns(in: session.world.bounds).prefix(2)
            var ends: [ScreenPoint] = []
            var stops: [ScreenPoint] = []
            func world(_ point: ScreenPoint) -> PlanPoint {
                let position = camera.worldPosition(at: point)
                return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
            }
            func tapNetwork(_ point: ScreenPoint) { session.tapNetwork(at: world(point), reach: camera.worldDistance(12)) }
            for _ in 0..<20 {
                guard let step = session.tutorial?.step.id else { break }
                switch step {
                case "build.network": session.selectTool(.network)
                case "map.move": session.mapDidMove()
                case "track.draw":
                    camera = try XCTUnwrap(camera.lessonFraming(try XCTUnwrap(session.tutorialFraming), clearOf: Self.cover))
                    if townToTown {
                        let (first, second) = (camera.screenPoint(of: towns.first!), camera.screenPoint(of: towns.last!))
                        func along(_ fraction: Double) -> ScreenPoint {
                            ScreenPoint(x: first.x + (second.x - first.x) * fraction, y: first.y + (second.y - first.y) * fraction)
                        }
                        ends = [first, second]
                        stops = [along(0.08), along(0.92)]
                    } else {
                        while camera.pointsPerUnit < 7.0 / 1_024 * 0.999 { camera = camera.zoomedIn() }
                        ends = [ScreenPoint(x: 106, y: 849), ScreenPoint(x: 914, y: 849)]
                        stops = [ScreenPoint(x: 308, y: 849), ScreenPoint(x: 712, y: 849)]
                    }
                    ends.forEach(tapNetwork)
                case "track.build": session.buildNetworkTrack()
                case "station.mode": session.setNetworkMode(.platform)
                case "station.first.site": tapNetwork(stops[0])
                case "station.second.site": tapNetwork(stops[1])
                case "station.first.build", "station.second.build": session.addNetworkPlatform()
                case "build.done": session.selectTool(.select)
                case "line.open": session.startPickingLineStops(announces: false)
                case "line.stations":
                    for stop in stops { session.tapMap(at: world(stop), reach: camera.worldDistance(12)) }
                case "line.create": session.createLineFromDraft()
                case "first.fare":
                    let end = session.world.clock.now.seconds + 3 * GameTime.secondsPerDay
                    while !session.isTutorialStepDone, session.world.clock.now.seconds < end {
                        session.advance(realElapsed: GameSession.maximumStepDuration)
                    }
                    // The two the walk built, not the passing loop a long
                    // line opens with (decision 264).
                    let metres = session.world.stations.filter { !$0.isDepot }.prefix(2).map { station in
                        towns.map { town in
                            let dx = Double(station.point.x - town.x), dy = Double(station.point.y - town.y)
                            return (dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)
                        }.min() ?? .infinity
                    }
                    return (session.isTutorialStepDone, metres)
                default: break
                }
                session.showNextTutorialStep()
            }
            XCTFail("the walk did not reach the first fares")
            return (false, [])
        }
        let laid = try walk(townToTown: true)
        XCTAssertTrue(laid.fares, "no fares from town to town")
        XCTAssertEqual(laid.nearest.count, 2)
        for metres in laid.nearest { XCTAssertLessThan(metres, 800, "a station \(Int(metres)) m from its town") }
        let alongARow = try walk(townToTown: false)
        XCTAssertFalse(alongARow.fares, "the row zoomed in about the middle earns fares again: the iPad walk could go back to it")
        for metres in alongARow.nearest { XCTAssertGreaterThan(metres, 2_000) }
    }

    /// A1 on an iPhone on its side: fitting both towns in the short map
    /// left clear would zoom out to kilometres a tap, so only an iPad
    /// frames them (the gate's TutorialUITests taps 400 points apart).
    func testOnAnIPhoneTheTrackStepLeavesTheZoomToThePlayer() throws {
        let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .english)
        session.startTutorial()
        session.selectTool(.network)
        session.showNextTutorialStep()
        session.mapDidMove()
        session.showNextTutorialStep()
        let region = try XCTUnwrap(session.tutorialFraming)
        let phone = PlanCamera(
            bounds: session.world.bounds, viewport: ScreenSize(width: 874, height: 402), showing: WorldRegion.opening(in: session.world)
        ).zoomedOut()
        let framed = try XCTUnwrap(phone.framing(region, clearOf: ScreenInsets(top: 60, leading: 70, bottom: 60, trailing: 0)))
        let metres = 400 / framed.pointsPerUnit / Double(WorldCoordinate.unitsPerMetre)
        XCTAssertGreaterThan(metres, 8_000, "400 points would lay \(Int(metres)) m")
        XCTAssertNil(phone.lessonFraming(region, clearOf: ScreenInsets(top: 60, leading: 70, bottom: 60, trailing: 0)))
        XCTAssertFalse(WindowLayout(device: .iPhone, compactWidth: false).framesTheLessonsTowns)
        XCTAssertTrue(WindowLayout(device: .iPad, compactWidth: false).framesTheLessonsTowns)
    }

    /// A1: outside a lesson, the tutorial frames nothing.
    func testTheTutorialOutsideALessonFramesNothing() {
        let session = GameSession(world: .newGame(), language: .english)
        session.startTutorial(atStep: "track.draw")
        XCTAssertEqual(session.tutorial?.step.id, "track.draw")
        XCTAssertNil(session.tutorialFraming)
    }

    /// A2: a card raised over the map opens at half the screen on an
    /// iPhone and at its full height on an iPad (by the window since
    /// decision 656, ``WindowLayoutTests``).
    func testACardOpensAtItsFullHeightOnAnIPad() {
        XCTAssertEqual(SheetHeight.offered(in: WindowLayout(device: .iPhone, compactWidth: true)), [.half, .full])
        XCTAssertEqual(SheetHeight.offered(in: WindowLayout(device: .iPad, compactWidth: false)), [.full])
    }

    /// A2: the new line's card shows the tutorial's step while it covers
    /// the tutorial's own card, at that step only.
    func testTheNewLinesCardShowsTheStepItCovers() {
        let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .english)
        session.startTutorial()
        XCTAssertNil(session.tutorialStepInLineCard)
        session.startTutorial(atStep: "line.create")
        XCTAssertEqual(session.tutorialStepInLineCard?.step.id, "line.create")
        XCTAssertEqual(session.tutorialStepInLineCard?.step.title(in: .traditionalChinese), "按 ✓，再按「開通路線」")
    }

    /// A6: on a wide start screen, the ways into a game in one column and
    /// the rest in the other, every button once, in the usual order.
    func testTheStartScreensTwoColumnsHoldEveryButtonOnce() {
        XCTAssertEqual(StartMenuEntry.columns(hasAutosave: true), [[.continueGame, .newGame, .lessons], [.demoMap, .saves, .achievements]])
        XCTAssertEqual(StartMenuEntry.columns(hasAutosave: false), [[.newGame, .lessons], [.demoMap, .saves, .achievements]])
        for hasAutosave in [true, false] {
            XCTAssertEqual(StartMenuEntry.columns(hasAutosave: hasAutosave).flatMap { $0 }, StartMenuEntry.entries(hasAutosave: hasAutosave))
        }
    }

    /// §6.4: the flat fare's stepper starts at the fare in force (it
    /// started at NT$5 under rules of NT$15), or at the city's baseline
    /// under distance fares.
    func testTheFlatFareStepperStartsAtTheFareInForce() {
        XCTAssertEqual(FareRules.standard.flatStart(baseline: FareRules.standardFare), 1_500)
        XCTAssertEqual(FareRules.flat(2_000).flatStart(baseline: FareRules.standardFare), 2_000)
        XCTAssertEqual(FareRules.distance(FareRules.standardBands).flatStart(baseline: 1_800), 1_800)
        XCTAssertEqual(FareRules.flat(50_000).flatStart(baseline: FareRules.standardFare), FareRules.flatFareRange.upperBound)
    }
}
