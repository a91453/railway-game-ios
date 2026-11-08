import GameCore
@testable import GamePresentation
import XCTest

/// Decision 642: the iPad playtest of 2026-11-08
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

    /// A1: outside a lesson, the tutorial frames nothing.
    func testTheTutorialOutsideALessonFramesNothing() {
        let session = GameSession(world: .newGame(), language: .english)
        session.startTutorial(atStep: "track.draw")
        XCTAssertEqual(session.tutorial?.step.id, "track.draw")
        XCTAssertNil(session.tutorialFraming)
    }

    /// A2: a card raised over the map opens at half the screen on an
    /// iPhone and at its full height on an iPad.
    func testACardOpensAtItsFullHeightOnAnIPad() {
        XCTAssertEqual(SheetHeight.offered(on: .iPhone), [.half, .full])
        XCTAssertEqual(SheetHeight.offered(on: .iPad), [.full])
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
