import XCTest

/// Decision 300: on a phone on its side, the map's zoom buttons stand
/// under the lines panel at the screen's edge rather than beside it in the
/// middle of the map. Full lane only (decision 199): when the row
/// stands under a panel is `MapFocusTests` on Linux; this checks where it
/// shows and that a finger reaches it. Run by hand with
/// only_testing=RailwayGameUITests/ZoomRowUnderPanelUITests.
@MainActor
final class ZoomRowUnderPanelUITests: XCTestCase {
    func testTheZoomButtonsStandUnderTheLinesPanel() {
        let app = launch(["-demo-layout", "-ui-testing-paused"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The demo map opens")
        checkTheRowStandsUnderTheLinesPanel(in: app)
    }

    /// On a real map the row stands in the credits' band, beside the
    /// credit, where the panel keeps its height.
    func testTheZoomButtonsStandInTheCreditsBandOfTheRealWorldDemo() {
        let app = launch([])
        defer { app.terminate() }
        app.openDemo("demo.realWorld")
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The real-world demo opens")
        checkTheRowStandsUnderTheLinesPanel(in: app)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func checkTheRowStandsUnderTheLinesPanel(in app: XCUIApplication) {
        let lines = app.buttons["entry.lines"]
        XCTAssertTrue(lines.appears(within: 10))
        lines.tap()
        // The panel's list, at the trailing side of the screen.
        XCTAssertTrue(app.navigationBars["Lines"].appears(within: 10), "The lines panel opens")
        let panel = trailingList(in: app, within: 10)
        XCTAssertNotNil(panel, "The lines panel's list")
        guard let panel else { return }
        panel.waitUntilStill()

        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.appears(within: 10), "The zoom buttons stay beside the panel")
        XCTAssertTrue(zoomIn.becomesHittable(within: 10), "The zoom buttons are covered")
        XCTAssertGreaterThanOrEqual(zoomIn.frame.minY, panel.frame.maxY, "Under the panel: \(zoomIn.frame) and \(panel.frame)")
        XCTAssertGreaterThan(zoomIn.frame.midX, panel.frame.minX, "At the screen's edge, not out in the map")
    }

    private func trailingList(in app: XCUIApplication, within timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let list = app.collectionViews.allElementsBoundByIndex.first(where: { $0.exists && $0.frame.minX > app.frame.width / 3 }) {
                return list
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return nil
    }
}
