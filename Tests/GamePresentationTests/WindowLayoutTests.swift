import GameCore
@testable import GamePresentation
import XCTest

/// Decision 656: the fixes of the L15 review's L15-6, L15-8 and L13-2 that
/// are worked out off Apple's platforms (#1966's iPad layout by the
/// window, the Mac's wording, the demo's lines kept with the save, the
/// speed hint under every sheet and cover).
@MainActor
final class WindowLayoutTests: XCTestCase {
    /// L15-6: an iPad's window in Split View, Slide Over or a small Stage
    /// Manager window (a compact width) is laid out as an iPhone's; an
    /// iPhone stays narrow on its side, where the larger ones are of
    /// regular width.
    func testANarrowWindowIsLaidOutAsAnIPhones() {
        XCTAssertEqual(WindowLayout(device: .iPad, compactWidth: false), .wide)
        XCTAssertEqual(WindowLayout(device: .mac, compactWidth: false), .wide)
        XCTAssertEqual(WindowLayout(device: .iPad, compactWidth: true), .narrow)
        XCTAssertEqual(WindowLayout(device: .mac, compactWidth: true), .narrow)
        XCTAssertEqual(WindowLayout(device: .iPhone, compactWidth: true), .narrow)
        XCTAssertEqual(WindowLayout(device: .iPhone, compactWidth: false), .narrow)

        XCTAssertEqual(SheetHeight.offered(in: .narrow), [.half, .full], "the map stays in sight under a card")
        XCTAssertEqual(SheetHeight.offered(in: .wide), [.full])
        XCTAssertFalse(WindowLayout.narrow.framesTheLessonsTowns)
        XCTAssertTrue(WindowLayout.wide.framesTheLessonsTowns)
    }

    /// The lesson's track step's region, as lesson 1 gives it.
    private func lessonRegion() throws -> (GameSession, WorldRegion) {
        let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .english)
        session.startTutorial()
        session.selectTool(.network)
        session.showNextTutorialStep()
        session.mapDidMove()
        session.showNextTutorialStep()
        return (session, try XCTUnwrap(session.tutorialFraming))
    }

    /// L15-6: the framing is left out where it would zoom out farther than
    /// 5 km across 400 points: the iPad's own windows frame the towns, an
    /// iPad's Split View window (as thin as an iPhone, the panel along its
    /// bottom) does not, even where a window's width class says regular.
    func testTheLessonIsNotFramedWhereItWouldZoomOutTooFar() throws {
        let (session, region) = try lessonRegion()
        func metres(_ camera: PlanCamera) -> Double {
            400 / camera.pointsPerUnit / Double(WorldCoordinate.unitsPerMetre)
        }
        let panel = ScreenInsets(top: 92, leading: 82, bottom: 105, trailing: 350)
        let along = ScreenInsets(top: 92, leading: 82, bottom: 105, trailing: 0)
        for (viewport, insets, frames) in [
            (ScreenSize(width: 1376, height: 1032), panel, true),
            (ScreenSize(width: 1032, height: 1376), panel, true),
            (ScreenSize(width: 440, height: 1032), along, false),
            (ScreenSize(width: 375, height: 1000), along, false),
        ] {
            let opening = PlanCamera(bounds: session.world.bounds, viewport: viewport, showing: WorldRegion.opening(in: session.world))
            let start = opening.zoomedOut()
            let framed = try XCTUnwrap(start.framing(region, clearOf: insets), "\(viewport): a town is hidden")
            if frames {
                XCTAssertEqual(start.lessonFraming(region, clearOf: insets), framed)
                XCTAssertLessThanOrEqual(metres(framed), PlanCamera.farthestLessonFramingMetres)
            } else {
                XCTAssertGreaterThan(metres(framed), PlanCamera.farthestLessonFramingMetres, "\(viewport)")
                XCTAssertNil(start.lessonFraming(region, clearOf: insets))
            }
        }
    }

    /// L15-8.3: the step's framing waits for the panel to be measured a
    /// frame late, moves the camera once, and leaves the player's camera
    /// alone after that, until the next step's region.
    func testTheLessonIsFramedOnceAStepAfterThePanelIsMeasured() throws {
        let (session, region) = try lessonRegion()
        let viewport = ScreenSize(width: 1376, height: 1032)
        let panel = ScreenInsets(top: 92, leading: 82, bottom: 105, trailing: 350)
        let opening = PlanCamera(bounds: session.world.bounds, viewport: viewport, showing: WorldRegion.opening(in: session.world))
        let start = opening.panned(byX: -400, y: 0)
        XCTAssertNotNil(start.framing(region, clearOf: panel), "the panel hides a town")
        // Both towns in the whole view, as they show before the panel and
        // the dock are measured; once they are, a town is under one.
        let far = opening.showing(region, clearOf: ScreenInsets())
        XCTAssertNotNil(far.framing(region, clearOf: panel), "the panel or the dock hides a town")
        XCTAssertNil(far.framing(region, clearOf: ScreenInsets()), "nothing hides one before the panel is measured")

        var latch = LessonFramingLatch()
        XCTAssertNil(latch.camera(for: region, from: far, clearOf: ScreenInsets(), layout: .wide, settling: true), "not measured yet")
        let framed = try XCTUnwrap(latch.camera(for: region, from: far, clearOf: panel, layout: .wide, settling: true))
        XCTAssertEqual(framed, far.lessonFraming(region, clearOf: panel))
        XCTAssertNil(latch.camera(for: region, from: start, clearOf: panel, layout: .wide, settling: true), "once a step")

        // A step that showed the towns clear, once it has settled, stays as
        // the player leaves it.
        var settled = LessonFramingLatch()
        XCTAssertNil(settled.camera(for: region, from: far, clearOf: ScreenInsets(), layout: .wide, settling: false))
        XCTAssertNil(settled.camera(for: region, from: start, clearOf: panel, layout: .wide, settling: false))
        // The next step's region starts again; no region resets it.
        XCTAssertNil(settled.camera(for: nil, from: start, clearOf: panel, layout: .wide, settling: false))
        XCTAssertNotNil(settled.camera(for: region, from: start, clearOf: panel, layout: .wide, settling: true))

        var narrow = LessonFramingLatch()
        XCTAssertNil(narrow.camera(for: region, from: start, clearOf: panel, layout: .narrow, settling: true), "a narrow window frames nothing")
    }

    /// L15-8.1: a Mac running the iPad app is called a Mac, and has no
    /// silent mode or app switcher to name.
    func testAMacIsCalledAMac() {
        XCTAssertEqual(DeviceFamily.mac.name, "Mac")
        XCTAssertEqual(LanguageChoice.system.title(in: .traditionalChinese, on: .mac), "跟隨 Mac")
        XCTAssertFalse(DeviceFamily.mac.soundNote(in: .english).contains("silent"))
        XCTAssertFalse(DeviceFamily.mac.soundNote(in: .traditionalChinese).contains("靜音"))
        XCTAssertEqual(
            DeviceFamily.iPad.soundNote(in: .traditionalChinese),
            "車站鈴聲在列車到站時響。其他音效：建造、換工具、收入與警告。iPad 在靜音模式時，遊戲不會發出聲音。"
        )
        XCTAssertEqual(
            DeviceFamily.iPhone.soundNote(in: .english),
            "Station chimes ring when a train arrives. Other effects: building, changing tools, income and warnings. In silent mode the game makes no sound."
        )
        XCTAssertEqual(
            LanguageChoice.system.restartNote(in: .english, on: .mac),
            "The game will use the Mac's language the next time it opens. Quit it and open it again."
        )
        XCTAssertEqual(
            LanguageChoice.english.restartNote(in: .traditionalChinese, on: .iPhone),
            "下次開啟遊戲時會換成English。請從多工畫面關掉遊戲，再重新開啟。"
        )
    }

    /// L15-8.2: the lines the demo laid are kept in the news log, which the
    /// save keeps, so the passing-loop card still leaves them out once the
    /// game is read back; a log written before has none.
    func testTheDemosLinesAreKeptWithTheSave() throws {
        var log = NewsLog()
        log.isDemo = true
        log.demoLines = [LineID(rawValue: 3), LineID(rawValue: 1)]
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(NewsLog.self, from: data), log)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""demoLines":[1,3]"#), "in order, so a save is the same each time")

        let empty = try JSONEncoder().encode(NewsLog())
        XCTAssertFalse(String(decoding: empty, as: UTF8.self).contains("demoLines"), "a log with none writes as before")
        XCTAssertEqual(try JSONDecoder().decode(NewsLog.self, from: empty).demoLines, [])

        let session = GameSession(world: try makeWorld(speed: .paused))
        session.linesLaidByTheDemo = [LineID(rawValue: 2)]
        XCTAssertEqual(session.news.demoLines, [LineID(rawValue: 2)])
    }

    /// L13-2: the speed hint waits while any sheet or full-screen cover is
    /// over the 2D map, as it does under the 3D map, and comes once every
    /// one has gone.
    func testTheSpeedHintWaitsUnderEverySheetAndCover() throws {
        let session = GameSession(world: try makeWorld(speed: .paused))
        for second in 1...21 {
            session.speedLagWatch.record(real: .seconds(second), speed: .x10, permille: 100, heat: .nominal)
        }
        let roster = session.coverOpened()
        let chooser = session.coverOpened()
        XCTAssertTrue(session.isMapCovered)
        session.syncSpeedLagHint()
        XCTAssertNotNil(session.speedLagWatch.hint)
        XCTAssertNil(session.speedLagHint, "a cover is over the 2D map")
        session.coverClosed(roster)
        XCTAssertNil(session.speedLagHint, "the chooser is still up")
        session.coverClosed(roster)
        XCTAssertNil(session.speedLagHint, "a token closes once")
        session.coverClosed(chooser)
        XCTAssertFalse(session.isMapCovered)
        XCTAssertEqual(session.speedLagHint?.speed, .x10, "every cover gone: it comes")

        // One on screen goes as a sheet comes, and comes again after.
        let sheet = session.coverOpened()
        XCTAssertNil(session.speedLagHint)
        session.coverClosed(sheet)
        XCTAssertNotNil(session.speedLagHint)
        // Under a cover and the 3D map, it waits for both.
        let cover = session.coverOpened()
        session.setMap3DOpen(true)
        session.coverClosed(cover)
        XCTAssertNil(session.speedLagHint, "the 3D map is still open")
        session.setMap3DOpen(false)
        XCTAssertNotNil(session.speedLagHint)
    }
}
