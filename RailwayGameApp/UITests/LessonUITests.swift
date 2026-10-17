import GameCore
import GamePresentation
import XCTest

/// Lessons 1–10 (decisions 266 and 271). Full lane only (decision 199):
/// the Linux LessonTests check the rules; these check what a finger can
/// reach. Run by hand with only_testing=RailwayGameUITests/LessonUITests.
@MainActor
final class LessonUITests: XCTestCase {
    private var app: XCUIApplication!

    func testAFreshInstallShowsTenLessonsAndOnlyTheFirstCanStart() {
        defer { app?.terminate() }
        launch()
        openLessons()
        reveal(app.buttons["lesson.1.start"])
        XCTAssertTrue(app.buttons["lesson.1.start"].becomesHittable(within: 5))
        let title = app.staticTexts["lessons.title"]
        XCTAssertTrue(title.label.contains("0/30"), title.label)
        for number in 1...10 {
            let card = element("lesson.\(number)")
            XCTAssertTrue(app.scrollUntilShown(card, in: list), "Missing lesson \(number)")
            if number > 1 {
                XCTAssertTrue(card.staticTexts["Pass lesson \(number - 1) to open it."].appears(within: 5), "Lesson \(number) must say it is locked")
                XCTAssertFalse(app.buttons["lesson.\(number).start"].exists, "Locked lesson \(number) has a Start button")
            }
        }
    }

    func testTheFourthLessonOpensOnlyAfterTheThirdHasStars() {
        defer { app?.terminate() }
        for (stars, open) in [("3,3,0", false), ("3,3,1", true)] {
            launch(stars: stars)
            openLessons()
            let card = element("lesson.4")
            XCTAssertTrue(app.scrollUntilShown(card, in: list))
            if open {
                reveal(app.buttons["lesson.4.start"])
                XCTAssertTrue(app.buttons["lesson.4.start"].becomesHittable(within: 5))
                XCTAssertFalse(card.staticTexts["Pass lesson 3 to open it."].exists)
            } else {
                XCTAssertTrue(card.staticTexts["Pass lesson 3 to open it."].appears(within: 5))
                XCTAssertFalse(app.buttons["lesson.4.start"].exists)
            }
            app.terminate()
        }
    }

    func testTheFirstLessonsOnlyBuildingToolIsNetworkWithoutLoopOrDepot() {
        defer { app?.terminate() }
        startLesson(1)
        tap(app.buttons["dock.build"])
        XCTAssertTrue(app.buttons["tool.network"].becomesHittable(within: 5))
        XCTAssertTrue(app.buttons["tool.network"].isSelected)
        XCTAssertFalse(app.buttons["tool.train"].exists)
        XCTAssertFalse(app.buttons["tool.building"].exists)
        openControls()
        XCTAssertTrue(mode("Lay").appears(within: 5))
        XCTAssertTrue(mode("Platform").appears(within: 5))
        XCTAssertFalse(mode("Loop").exists)
        XCTAssertFalse(mode("Depot").exists)
    }

    func testAddATrainIsAbsentInTheFirstLessonAndReachableInTheThird() {
        defer { app?.terminate() }
        // The existing later-step fixture supplies lesson 1's line, without
        // changing its scenario or granting tools.
        launch(step: "first.fare")
        dismissGuide()
        pause()
        openLineCard()
        assertAbsent(app.buttons.matching(identifier: "line.addTrain"), through: app.buttons["line.rename"])
        app.terminate()

        startLesson(3)
        dismissGuide()
        pause()
        openLineCard()
        let add = app.buttons["line.addTrain"]
        reveal(add)
        XCTAssertEqual(add.label, "Add a Train")
        XCTAssertTrue(add.becomesHittable(within: 5))
    }

    func testDoubleTrackIsAbsentInTheFourthLessonAndReachableInTheFifth() {
        defer { app?.terminate() }
        for number in [4, 5] {
            startLesson(number)
            dismissGuide()
            pause()
            let fixture = GameWorld.newGame(lesson: Lesson.all[number - 1])
            // Use the actual curved alignment for the tap, away from its
            // stations and the opening's passing loops.
            let alignment = fixture.railwaySnapshot().edges.max { $0.geometry.length < $1.geometry.length }!
            let point = alignment.geometry.location(at: alignment.geometry.length / 3).position
            tapMap(bringMapPointIntoView(PlanPoint(x: point.x, y: point.y), from: fixture.stations[0].location))
            XCTAssertTrue(((map.value as? String) ?? "").contains("Track"), "No track selected: \(String(describing: map.value))")
            openControls()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inspector.line.'")).firstMatch.becomesHittable(within: 5), "The selected track's line card must be open")
            let double = app.buttons["inspector.track.double"]
            if number == 5 {
                XCTAssertTrue(double.appears(within: 10))
                XCTAssertTrue(double.becomesHittable(within: 5))
                XCTAssertEqual(double.label, "Make double track")
            } else {
                XCTAssertFalse(double.exists)
            }
            app.terminate()
        }
    }

    func testDepotModeStartsInTheSeventhLesson() {
        defer { app?.terminate() }
        for number in [6, 7] {
            startLesson(number)
            dismissGuide()
            pause()
            tap(app.buttons["dock.build"])
            XCTAssertTrue(mode("Lay").appears(within: 5))
            if number == 7 {
                tap(mode("Depot"))
                XCTAssertTrue(element("network.depotSidings").appears(within: 5))
                XCTAssertTrue(element("network.depotSidings").becomesHittable(within: 5))
            } else {
                XCTAssertFalse(mode("Depot").exists)
            }
            app.terminate()
        }
    }

    func testFreightYardsStartInTheEighthLesson() {
        defer { app?.terminate() }
        for number in [7, 8] {
            startLesson(number)
            dismissGuide()
            pause()
            let stations = stationPoints()
            XCTAssertFalse(stations.isEmpty)
            // Holding a station is the existing way into its panel.
            coordinate(stations[0]).press(forDuration: 1)
            XCTAssertTrue(element("station.operations").appears(within: 10), "The station panel must be open before looking for freight")
            if number == 8 {
                let freight = app.buttons["station.freight.build"]
                reveal(freight)
                XCTAssertTrue(freight.becomesHittable(within: 5))
            } else {
                assertAbsent(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'station.freight.'")), through: app.buttons["station.remove"])
            }
            app.terminate()
        }
    }

    func testTheNinthLessonsSightOpensItsTourismPanel() {
        defer { app?.terminate() }
        startLesson(9)
        dismissGuide()
        pause()
        let marks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.sight.'"))
        let fixture = GameWorld.newGame(lesson: Lesson.all[8])
        // At the opening's broad zoom the sight is below the map's usable
        // area. Pan it clear of the bottom controls rather than zooming
        // farther out (which leaves it behind those same controls).
        _ = bringMapPointIntoView(fixture.tourism!.attractions[0].point, from: fixture.stations[0].location, zoomIfClamped: true)
        let mark = marks.firstMatch
        XCTAssertTrue(mark.appears(within: 10), "Lesson 9's sight must be visible on the map")
        let id = mark.identifier.replacingOccurrences(of: "map.sight.", with: "")
        tap(mark)
        XCTAssertTrue(app.buttons["tourism.done"].appears(within: 10))
        let row = app.staticTexts.matching(identifier: "tourism.row.\(id)").firstMatch
        XCTAssertTrue(row.appears(within: 10))
        XCTAssertTrue(row.becomesHittable(within: 5))
        XCTAssertTrue(row.label.contains("Seaview Point"), row.label)
    }

    func testTheTenthLessonHasCityRequests() {
        defer { app?.terminate() }
        startLesson(10)
        dismissGuide()
        pause()
        tap(app.buttons["hud.requests"])
        XCTAssertTrue(element("requests.trust").appears(within: 10))
        let offer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'requests.accept.'")).firstMatch
        reveal(offer)
        XCTAssertTrue(offer.becomesHittable(within: 5), "Lesson 10 must have a request the player can take")
    }

    func testNextOnTheFirstLessonsResultStartsTheSecondLesson() {
        defer { app?.terminate() }
        passFirstLesson()
        tap(app.buttons["lessonResult.next"])
        XCTAssertTrue(element("lessonResult.title").disappears(within: 10))
        showGuide()
        XCTAssertEqual(app.staticTexts["tutorial.title"].label, "Extend your line to the third town")
        XCTAssertGreaterThanOrEqual(stationPoints().count, 2, "Lesson 2 starts with the first line")
    }

    func testAgainOnTheFirstLessonsResultRestartsTheFirstLesson() {
        defer { app?.terminate() }
        passFirstLesson()
        tap(app.buttons["lessonResult.again"])
        XCTAssertTrue(element("lessonResult.title").disappears(within: 10))
        showGuide()
        XCTAssertEqual(app.staticTexts["tutorial.title"].label, "Tap Build")
        XCTAssertEqual(stationPoints().count, 0, "Lesson 1 must restart with no stations")
    }

    func testKeepPlayingClosesTheResultAndKeepsTheRailwayRunning() {
        defer { app?.terminate() }
        passFirstLesson()
        let before = stationPoints().count
        tap(app.buttons["lessonResult.keepPlaying"])
        XCTAssertTrue(element("lessonResult.title").disappears(within: 10))
        XCTAssertTrue(map.appears(within: 5))
        XCTAssertEqual(stationPoints().count, before, "Keep Playing must keep the railway")
        // The goal-met event can leave the clock paused after the result
        // closes. Keep Playing preserves this game; the player can resume it.
        let resume = app.buttons["Resume"]
        if resume.appears(within: 2) { tap(resume) }
        XCTAssertTrue(app.buttons["Pause"].becomesHittable(within: 5), "The game can continue running")
        tap(app.buttons["dock.build"])
        XCTAssertTrue(app.buttons["tool.network"].becomesHittable(within: 5))
    }

    // MARK: - Launching and reaching controls

    private var map: XCUIElement { element("map") }
    private var list: XCUIElement { app.collectionViews.firstMatch }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func mode(_ name: String) -> XCUIElement {
        app.segmentedControls.buttons[name].firstMatch
    }

    private func launch(stars: String? = nil, step: String? = nil) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let stars { app.launchArguments += ["-lesson-stars", stars] }
        if let step { app.launchArguments += ["-tutorial-step", step] }
        app.launch()
    }

    private func openLessons() {
        let lessons = app.buttons["start.lessons"]
        XCTAssertTrue(lessons.appears(within: 15))
        app.bringStartButtonIntoView(lessons)
        tap(lessons)
        XCTAssertTrue(element("lessons.title").appears(within: 10))
    }

    private func startLesson(_ number: Int) {
        let stars = number > 1 ? Array(repeating: "3", count: number - 1).joined(separator: ",") : nil
        launch(stars: stars)
        openLessons()
        let start = app.buttons["lesson.\(number).start"]
        reveal(start)
        tap(start)
        XCTAssertTrue(map.appears(within: 20))
        XCTAssertTrue(element("lessons.title").disappears(within: 5))
    }

    /// Scrolls `list` until the middle of `control` shows in it, as
    /// `scrollUntilShown` does, but dragging at the list's left edge, clear
    /// of its rows (as `assertAbsent` does): a drag that starts on a row's
    /// menu (a station's "Platform 1: add a platform track") opens the menu
    /// instead of scrolling, and the station panel stayed at that row for
    /// 40 drags, short of its Freight section (main abb306a's full lane,
    /// run 39053855189).
    private func reveal(_ control: XCUIElement) {
        XCTAssertTrue(list.appears(within: 10), "Missing \(list)")
        let onScreen = list.frame.intersection(app.frame)
        let area = onScreen.isEmpty ? list.frame : onScreen
        let band = area.insetBy(dx: 0, dy: 24)
        func shown() -> Bool {
            control.exists && band.minY <= control.frame.midY && control.frame.midY <= band.maxY
        }
        func drag(from: CGFloat, to: CGFloat) {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = area.minX + area.width * 0.02 - app.frame.minX
            origin.withOffset(CGVector(dx: x, dy: area.minY + area.height * from - app.frame.minY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: area.minY + area.height * to - app.frame.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        for _ in 0..<40 {
            if shown() { break }
            if !control.exists {
                drag(from: 0.85, to: 0.15)
            } else if control.frame.midY < band.minY {
                drag(from: 0.35, to: 0.65)
            } else {
                drag(from: 0.65, to: 0.35)
            }
        }
        XCTAssertTrue(shown(), "Cannot scroll to \(control)")
        control.waitUntilSettled()
    }

    /// Negative assertions visit the section, rather than treating an
    /// off-screen lazy row as proof that a locked control is absent.
    private func assertAbsent(_ query: XCUIElementQuery, through marker: XCUIElement) {
        for _ in 0..<60 {
            XCTAssertFalse(query.firstMatch.exists, "Locked control is present: \(query)")
            if marker.exists, list.frame.insetBy(dx: 0, dy: 24).contains(CGPoint(x: marker.frame.midX, y: marker.frame.midY)) {
                marker.waitUntilSettled()
                return
            }
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)),
                       withVelocity: XCUIGestureVelocity(rawValue: 250), thenHoldForDuration: 0.3)
        }
        XCTFail("Did not reach \(marker) while checking locked controls")
    }

    private func tap(_ control: XCUIElement) {
        XCTAssertTrue(control.appears(within: 10), "Missing \(control)")
        XCTAssertTrue(control.becomesHittable(within: 10), "Covered \(control)")
        control.waitUntilSettled()
        control.tap()
    }

    private func showGuide() {
        let folded = app.buttons["tutorial.unfold"]
        if folded.appears(within: 2) { tap(folded) }
        XCTAssertTrue(app.staticTexts["tutorial.title"].appears(within: 10))
    }

    private func dismissGuide() {
        showGuide()
        tap(app.buttons["tutorial.skip"])
        XCTAssertTrue(app.buttons["tutorial.skip"].disappears(within: 5))
    }

    private func pause() {
        let pause = app.buttons["Pause"]
        if pause.appears(within: 2) { tap(pause) }
        XCTAssertTrue(app.buttons["Resume"].appears(within: 5))
    }

    private func openControls() {
        let toggle = app.buttons["controls.toggle"]
        XCTAssertTrue(toggle.appears(within: 5))
        if toggle.label == "Show Controls" { tap(toggle) }
        XCTAssertEqual(toggle.label, "Hide Controls")
    }

    private func openLineCard() {
        tap(app.buttons["entry.lines"])
        let row = element("line.trainsRow.1")
        reveal(row)
        tap(row)
    }

    private func stationPoints() -> [CGPoint] {
        let readout = element("map.stations")
        XCTAssertTrue(readout.appears(within: 10))
        var last: String?
        var since = Date()
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = readout.value as? String ?? ""
            if last != value { last = value; since = Date(); return false }
            return Date().timeIntervalSince(since) >= 0.5
        }, object: readout)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 10), .completed, "The map did not settle")
        return (last ?? "").split(separator: ";").compactMap { pair in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return nil }
            return CGPoint(x: map.frame.minX + xy[0], y: map.frame.minY + xy[1])
        }
    }

    /// Calibrate from the app's existing camera/station readouts; fixture
    /// coordinates locate gestures only, never decide whether a UI passes.
    private func project(_ point: PlanPoint, from known: PlanPoint) -> CGPoint {
        let first = stationPoints()[0]
        let zoom = element("map.camera")
        XCTAssertTrue(zoom.appears(within: 5))
        let scale = Double(zoom.value as? String ?? "")!
        return CGPoint(x: first.x + Double(point.x - known.x) * scale,
                       y: first.y + Double(point.y - known.y) * scale)
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }

    private func tapMap(_ point: CGPoint) {
        XCTAssertTrue(map.frame.contains(point), "Map point is off screen: \(point)")
        coordinate(point).tap()
    }

    /// Leave the HUD, dock and bottom zoom controls clear. The world point
    /// may start under any of them; dragging from bare map moves it into
    /// reach without tapping the overlay in its place.
    private func bringMapPointIntoView(_ point: PlanPoint, from known: PlanPoint, zoomIfClamped: Bool = false) -> CGPoint {
        let middle = CGPoint(x: map.frame.midX, y: map.frame.midY)
        let clear = CGRect(x: middle.x - 130, y: middle.y - 60, width: 260, height: 120)
        var at = project(point, from: known)
        for _ in 0..<16 {
            if clear.contains(at) { return at }
            let destination = CGPoint(x: middle.x + max(-140, min(140, middle.x - at.x)),
                                      y: middle.y + max(-90, min(90, middle.y - at.y)))
            coordinate(middle).press(forDuration: 0.1, thenDragTo: coordinate(destination),
                                     withVelocity: XCUIGestureVelocity(rawValue: 200), thenHoldForDuration: 0.3)
            let moved = project(point, from: known)
            if zoomIfClamped, hypot(moved.x - at.x, moved.y - at.y) < 4 {
                // Near the world's edge, the current zoom has no more room
                // to pan. A closer view gives the camera room to move.
                let zoom = app.buttons["Zoom in"]
                XCTAssertTrue(zoom.isEnabled, "Cannot move the map point clear of the controls")
                tap(zoom)
                at = project(point, from: known)
            } else {
                at = moved
            }
        }
        XCTAssertTrue(clear.contains(at), "Map point did not come clear of controls: \(at)")
        return at
    }

    private func selectStation(_ index: Int) {
        // A hold selects the station even when its train is over it.
        coordinate(stationPoints()[index]).press(forDuration: 1)
        XCTAssertTrue(element("station.operations").appears(within: 10))
        tap(app.navigationBars.buttons["Done"].firstMatch)
        XCTAssertTrue(element("station.operations").disappears(within: 5))
    }

    // MARK: - Passing lesson 1 through the UI

    private func passFirstLesson() {
        launch(step: "line.open")
        dismissGuide()
        pause()
        let middle = WorldBounds.standard.width / 2
        // GameLauncher.startTutorial(atStep:) builds this short fixture.
        let known = PlanPoint(x: middle - 4 * 1_024, y: middle)
        let town = Land.townCentres(seed: 1, in: .standard)[1]
        let east = town.x >= middle
        let junction = PlanPoint(x: middle + (east ? 5_120 : -6_144), y: middle)
        let dx = Double(town.x - junction.x), dy = Double(town.y - junction.y)
        let span = hypot(dx, dy)
        let margin = Double(800 * WorldCoordinate.unitsPerMetre)
        let end = PlanPoint(x: town.x + Int64(dx / span * margin), y: town.y + Int64(dy / span * margin))
        // The joined track curves away from the short fixture's end. Use
        // its centre line for the platform tap, within the town's catchment.
        let curve = NetworkBuilding.curve(from: junction, leaving: PlanVector(dx: east ? 1 : -1, dy: 0), to: end, leaving: nil)!
        let geometry = TrackGeometry(from: WorldCoordinate(x: junction.x, y: junction.y),
                                     to: WorldCoordinate(x: end.x, y: end.y), curve: curve)!
        let site = geometry.points.min {
            hypot(Double($0.x - town.x), Double($0.y - town.y)) < hypot(Double($1.x - town.x), Double($1.y - town.y))
        }!

        tap(app.buttons["dock.build"])
        tap(mode("Lay"))
        for _ in 0..<10 {
            let point = project(end, from: known)
            let safe = map.frame.insetBy(dx: 150, dy: 100)
            if safe.contains(point) { break }
            tap(app.buttons["Zoom out"])
        }
        tapMap(project(junction, from: known))
        tapMap(project(end, from: known))
        tap(app.buttons["map.build.confirm"])
        XCTAssertTrue(app.buttons["map.build.confirm"].disappears(within: 5))

        openControls()
        tap(mode("Platform"))
        tapMap(project(PlanPoint(x: site.x, y: site.y), from: known))
        tap(app.buttons["map.build.confirm"])
        XCTAssertTrue(app.buttons["map.build.confirm"].disappears(within: 5))
        XCTAssertEqual(stationPoints().count, 3, "Build the second town's station")
        tap(app.buttons["tool.select"])
        pause()

        // Select before opening the panel, so its overlay cannot take a
        // map tap. The draft keeps its stops when Lines is closed.
        selectStation(0)
        tap(app.buttons["entry.lines"])
        if app.buttons["line.new"].exists {
            reveal(app.buttons["line.new"])
            tap(app.buttons["line.new"])
        }
        reveal(app.buttons["Add Selected Station"])
        tap(app.buttons["Add Selected Station"])
        tap(app.navigationBars["Lines"].buttons["Done"])
        selectStation(2)
        tap(app.buttons["entry.lines"])
        reveal(app.buttons["Add Selected Station"])
        tap(app.buttons["Add Selected Station"])
        let create = app.buttons["line.draft.create"]
        reveal(create)
        XCTAssertTrue(create.isEnabled)
        tap(create)
        if app.navigationBars["Lines"].exists { tap(app.navigationBars["Lines"].buttons["Done"]) }
        let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Speed:'")).firstMatch
        tap(speed)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '6000 times real time'")).firstMatch)
        if app.buttons["Resume"].exists { tap(app.buttons["Resume"]) }

        XCTAssertTrue(element("lessonResult.title").appears(within: 180), "Lesson 1 must meet its real goals")
        XCTAssertEqual(element("lessonResult.title").label, "Lesson 1 passed")
        XCTAssertTrue(element("lessonResult.stars").appears(within: 5))
        XCTAssertFalse(element("lessonResult.stars").label.hasPrefix("0 "))
        for name in ["next", "again", "keepPlaying"] {
            XCTAssertTrue(app.buttons["lessonResult.\(name)"].becomesHittable(within: 10), "Result action \(name) is covered")
        }
    }
}
