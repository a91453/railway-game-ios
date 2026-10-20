import XCTest

/// The new line's draft in one line (City Transport Manager study 4.2,
/// step M0), on a blank map and on a real map of Taiwan: once two stations
/// are picked, the line shows at the top of the lines panel's draft. Full
/// lane only (decision 199): what it says is `LineDraftSummaryTests` on
/// Linux; this checks that it shows. Run by hand with
/// only_testing=RailwayGameUITests/LineDraftSummaryUITests.
@MainActor
final class LineDraftSummaryUITests: XCTestCase {
    private var app: XCUIApplication!

    func testTheDraftsLineShowsOnTheDemoMap() {
        defer { app?.terminate() }
        launch(["-demo-layout", "-ui-testing-paused"])
        XCTAssertTrue(map.appears(within: 30), "The demo map opens")
        pickTwoStationsAndFindTheLine()
    }

    func testTheDraftsLineShowsOnTheRealWorldDemo() {
        defer { app?.terminate() }
        launch([])
        app.openDemo("demo.realWorld")
        XCTAssertTrue(map.appears(within: 60), "The real-world demo opens")
        let pause = app.buttons["Pause"]
        if pause.appears(within: 5) { tap(pause) }
        XCTAssertTrue(app.buttons["Resume"].appears(within: 10))
        pickTwoStationsAndFindTheLine()
    }

    // MARK: - Steps

    private func pickTwoStationsAndFindTheLine() {
        let clear = map.frame.insetBy(dx: 90, dy: 90)
        let points = stationPoints().filter { clear.contains($0) }
        XCTAssertGreaterThanOrEqual(points.count, 2, "Two stations clear of the map's buttons")

        selectStation(at: points[0])
        tap(app.buttons["entry.lines"])
        // Both maps open with lines, so the panel lists them first and folds
        // the new line's form into "New Line…" below them (decision 196),
        // off the screen on a phone: scrolled to, not waited for.
        if !app.buttons["Add Selected Station"].appears(within: 3) {
            let newLine = app.buttons["line.new"]
            reveal(newLine)
            tap(newLine)
            // A tap while the list still glides only stops it (run
            // 39456665951): the row is selected once its form is open.
            if !isSelected(newLine, within: 3) { tap(newLine) }
            XCTAssertTrue(isSelected(newLine, within: 3), "The new line's form did not open")
        }
        reveal(app.buttons["Add Selected Station"])
        tap(app.buttons["Add Selected Station"])
        let summary = element("line.draft.summary")
        reveal(summary, above: true)
        XCTAssertTrue(summary.label.hasPrefix("1 stop"), summary.label)
        tap(app.navigationBars["Lines"].buttons["Done"])

        selectStation(at: points[1])
        tap(app.buttons["entry.lines"])
        reveal(app.buttons["Add Selected Station"])
        tap(app.buttons["Add Selected Station"])
        reveal(summary, above: true)
        XCTAssertFalse(summary.label.isEmpty)
        XCTAssertFalse(summary.label.hasPrefix("1 stop"), "The line moves on with the second station: \(summary.label)")
        XCTAssertTrue(list.frame.contains(CGPoint(x: summary.frame.midX, y: summary.frame.midY)), "The line is on the panel's list")
    }

    // MARK: - Helpers

    private var map: XCUIElement { element("map") }
    private var list: XCUIElement { app.collectionViews.firstMatch }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func tap(_ control: XCUIElement) {
        XCTAssertTrue(control.appears(within: 10), "Missing \(control)")
        XCTAssertTrue(control.becomesHittable(within: 10), "Covered \(control)")
        control.waitUntilSettled()
        control.tap()
    }

    private func isSelected(_ control: XCUIElement, within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(control.exists && control.isSelected) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    /// `above`: the row is above the list's place, as the draft's summary
    /// at the top of its form is above "Add Selected Station"; a row the
    /// list has not loaded is otherwise looked for further down.
    private func reveal(_ control: XCUIElement, above: Bool = false) {
        // Measured while the panel still slides in, the list's place is
        // its trailing edge, and every drag there misses it (run
        // 39461248592: 40 drags at x 835).
        XCTAssertTrue(list.appears(within: 10), "The lines panel's list")
        list.waitUntilStill()
        // Not loaded, the summary was looked for below, 40 drags away from
        // it (run 39476430973).
        for _ in 0..<12 where above && !control.exists {
            let area = list.frame
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: area.minX + 8 - app.frame.minX, dy: area.minY + area.height * 0.2 - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: area.height * 0.6)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        // Wholly on screen and under the bar: a row whose middle was in
        // the list's band lay at its bottom edge and never became hittable
        // (run 39471415591, "New Line…" under "Add a Train").
        let bar = app.navigationBars["Lines"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(control, in: list, below: bar.exists ? bar.frame.maxY : nil), "Cannot scroll to \(control)")
        control.waitUntilSettled()
    }

    private func selectStation(at point: CGPoint) {
        // A hold selects the station even when its train is over it.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
            .press(forDuration: 1)
        XCTAssertTrue(element("station.operations").appears(within: 10), "The station's card opens")
        tap(app.navigationBars.buttons["Done"].firstMatch)
        XCTAssertTrue(element("station.operations").disappears(within: 5))
    }

    /// Where the stations are on the map, once it has settled (as
    /// `LessonUITests` reads them).
    private func stationPoints() -> [CGPoint] {
        let readout = element("map.stations")
        XCTAssertTrue(readout.appears(within: 10))
        let deadline = Date().addingTimeInterval(60)
        var last = readout.value as? String ?? ""
        var since = Date()
        var settled = false
        while !settled {
            Thread.sleep(forTimeInterval: 0.1)
            let value = readout.value as? String ?? ""
            if value != last {
                last = value
                since = Date()
            } else {
                settled = Date().timeIntervalSince(since) >= 0.5
            }
            if !settled, Date() >= deadline { break }
        }
        XCTAssertTrue(settled, "The map did not settle: \(last)")
        return last.split(separator: ";").compactMap { pair in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return nil }
            return CGPoint(x: map.frame.minX + xy[0], y: map.frame.minY + xy[1])
        }
    }
}
