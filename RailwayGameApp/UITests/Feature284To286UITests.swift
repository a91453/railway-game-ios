import XCTest

/// Full lane only. Linux's FeedbackSeventyThreeTests,
/// DoubleTrackPlatformTests and TourismSessionTests own the rules; these
/// checks own the iPhone's text, scrolling and touches. Launch worlds are
/// Debug-only, paused, and loaded from the app's isolated testing library.
@MainActor
final class Feature284To286UITests: XCTestCase {
    private var app: XCUIApplication!

    func testSeparateTracksExplainTheMissingCrossoverInTheLineDraft() {
        defer { app?.terminate() }
        checkDraft(in: "separate-tracks", containing:
            "海岸 和 山邊 的月台在兩條不相連的軌道上（例如複線的兩條之間沒有渡線）")
    }

    func testTheLineDraftNamesTheStationWithoutAPlatform() {
        defer { app?.terminate() }
        checkDraft(in: "missing-platform", containing: "山邊 還沒有月台：")
    }

    func testConfirmingADoubleTrackPlatformShowsBothPlatformsAtTheStation() {
        defer { app?.terminate() }
        launch("double-platform")
        tap(app.buttons["dock.build"])
        let controls = app.buttons["controls.toggle"]
        if controls.appears(within: 5), controls.label == "展開控制項" { tap(controls) }
        tap(app.segmentedControls.buttons["月台"].firstMatch)
        coordinate(stationPoint()).tap()

        let summary = element("inspector.status")
        XCTAssertTrue(summary.appears(within: 10))
        XCTAssertTrue(summary.becomesHittable(within: 5))
        XCTAssertTrue(summary.label.contains("在這裡設 64 公尺 的月台（兩條軌道）"), summary.label)
        tap(app.buttons["map.build.confirm"])
        XCTAssertTrue(app.buttons["map.build.confirm"].disappears(within: 10))

        tap(app.buttons["tool.select"])
        coordinate(stationPoint()).press(forDuration: 1)
        XCTAssertTrue(element("station.operations").appears(within: 10))
        for index in 0...1 {
            let platform = app.buttons["station.platformTrack.\(index)"]
            reveal(platform)
            XCTAssertTrue(platform.becomesHittable(within: 5), "Platform \(index + 1) must be on screen")
            XCTAssertTrue(platform.label.contains("第 \(index + 1) 月台"), platform.label)
        }
    }

    func testBlueTrainAndHaiFengHaveAReachableSightseeingNoteAndChoice() {
        defer { app?.terminate() }
        launch("catalog")
        tap(app.buttons["entry.lines"])
        let catalog = app.buttons["line.staff.catalog"]
        reveal(catalog)
        tap(catalog)
        tap(app.segmentedControls.buttons["鐵路"].firstMatch)
        showCatalogType("藍皮解憂號")
        checkCatalogType("藍皮解憂號")

        // Choose this closes the showroom and retains the selected type.
        reveal(catalog)
        tap(catalog)
        showCatalogType("海風號")
        checkCatalogType("海風號")
    }

    func testTheSightShowsTheSightseeingTrainBonus() {
        defer { app?.terminate() }
        launch("sightseeing")
        tap(app.buttons["hud.menu"])
        tap(app.buttons["menu.more"])
        tap(app.buttons["menu.tourism"])
        XCTAssertTrue(app.buttons["tourism.done"].appears(within: 10))
        let sight = app.staticTexts.matching(identifier: "tourism.row.1").firstMatch
        reveal(sight)
        XCTAssertTrue(sight.label.contains("海岸老街"), sight.label)
        let bonus = app.staticTexts["有觀光列車停靠（+0.5★）"]
        reveal(bonus)
        XCTAssertTrue(bonus.becomesHittable(within: 5))
        tap(app.buttons["tourism.done"])
        XCTAssertTrue(app.buttons["tourism.done"].disappears(within: 10))
    }

    private func checkDraft(in world: String, containing text: String) {
        launch(world)
        tap(app.buttons["entry.lines"])
        let gap = app.staticTexts["line.draft.gap"]
        reveal(gap)
        XCTAssertTrue(gap.becomesHittable(within: 5))
        XCTAssertTrue(gap.label.contains(text), gap.label)

        // The draft's actual buttons are reachable, and the warning follows
        // their edits rather than being static text in the launch scene.
        let remove = app.buttons["移除最後一站"]
        reveal(remove)
        tap(remove)
        XCTAssertTrue(gap.disappears(within: 5))
        let add = app.buttons["加入選取的車站"]
        reveal(add)
        tap(add)
        reveal(gap)
        XCTAssertTrue(gap.appears(within: 5))
        XCTAssertTrue(gap.label.contains(text), gap.label)
    }

    private func showCatalogType(_ name: String) {
        let previous = app.buttons["上一款"]
        // Navigate by the showroom's name, so adding another train type
        // does not change the test. A matching thumbnail farther down the
        // scroll view is not the title above the arrows.
        for _ in 0..<40 {
            XCTAssertTrue(app.scrollUntilShown(previous, in: app.scrollViews.firstMatch))
            previous.waitUntilSettled()
            let title = app.staticTexts[name].firstMatch
            if title.exists, !title.frame.isEmpty, title.frame.maxY <= previous.frame.minY {
                XCTAssertTrue(title.becomesHittable(within: 5))
                return
            }
            tap(previous)
        }
        XCTFail("The showroom never showed \(name)")
    }

    private func checkCatalogType(_ name: String) {
        let heading = app.staticTexts[name].firstMatch
        XCTAssertTrue(heading.appears(within: 5))
        XCTAssertTrue(heading.becomesHittable(within: 5), "The showroom must show \(name)")
        let note = app.staticTexts["觀光列車：停靠景點 800 公尺內的車站時，景點加 0.5 星，觀光客會變多。"]
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(app.scrollUntilShown(note, in: scroll))
        XCTAssertTrue(note.becomesHittable(within: 5))
        let choose = app.buttons["catalog.choose"]
        XCTAssertTrue(app.scrollUntilShown(choose, in: scroll))
        tap(choose)
        XCTAssertTrue(app.buttons["catalog.cancel"].disappears(within: 10))
    }

    private func launch(_ world: String) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-world", world,
                               "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        XCTAssertTrue(element("map").appears(within: 30))
        element("map").waitUntilSettled()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ control: XCUIElement) {
        XCTAssertTrue(control.appears(within: 10), "Missing \(control)")
        XCTAssertTrue(control.becomesHittable(within: 10), "Covered \(control)")
        control.waitUntilSettled()
        control.tap()
    }

    private func reveal(_ control: XCUIElement) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.appears(within: 10))
        let bar = app.navigationBars.firstMatch
        // Drag beside menu rows, and below the panel's navigation bar.
        XCTAssertTrue(app.dragUntilWhollyOnScreen(control, in: list, below: bar.frame.maxY), "Cannot reveal \(control)")
        control.waitUntilSettled()
    }

    /// Existing debug readout locates a gesture only; it never supplies the
    /// expected UI result. Wait for the opening camera and tool layout to
    /// settle before touching the station on the main track.
    private func stationPoint() -> CGPoint {
        let readout = element("map.stations")
        XCTAssertTrue(readout.appears(within: 10))
        var previous = ""
        var since = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = readout.value as? String ?? ""
            if value != previous { previous = value; since = Date(); return false }
            return !value.isEmpty && Date().timeIntervalSince(since) >= 0.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 20), .completed)
        let xy = previous.split(separator: ";")[0].split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(xy.count, 2)
        let map = element("map").frame
        return CGPoint(x: map.minX + xy[0], y: map.minY + xy[1])
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        XCTAssertTrue(element("map").frame.contains(point))
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }
}
