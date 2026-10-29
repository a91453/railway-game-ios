import XCTest

/// Decision 478: the load charts show where a finger reaches them. What
/// they say is `LoadChartTests` (Linux); this only opens them on the
/// freight scene (`ScreenshotScene.freight`), which has passenger lines
/// and a played morning, so the passenger plan is there.
@MainActor
final class LoadChartUITests: XCTestCase {
    func testTheLineAndSectionLoadChartsOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-screenshot-scene", "freight"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }

        // A passenger line picked: its riders between stops, below its
        // operations.
        let report = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.report.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(report, in: list), "A passenger line's row comes into view")
        report.tap()
        let chart = app.descendants(matching: .any)["line.load.chart"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(chart, in: list), "The line's riders between stops come into view")

        // The network's flow report, its sections page: a section hour by
        // hour.
        let flow = app.buttons["lines.networkFlow"]
        XCTAssertTrue(flow.becomesHittable(within: 5), "The flow report's button is there")
        flow.tap()
        let page = app.segmentedControls["networkFlow.page"]
        XCTAssertTrue(page.appears(within: 10), "The flow report opens")
        page.buttons.element(boundBy: 1).tap()
        // Below decision 472's ranking of the fullest sections: a list
        // builds a row only as it is scrolled to.
        // The chart is taller than the band a phone on its side leaves:
        // its summary line is brought in.
        XCTAssertTrue(app.dragUntilWhollyOnScreen(app.descendants(matching: .any)["networkFlow.hourly.summary"].firstMatch),
                      "A section's riders hour by hour show")
        XCTAssertTrue(app.descendants(matching: .any)["networkFlow.hourly.chart"].firstMatch.exists, "Its chart is there")
    }
}
