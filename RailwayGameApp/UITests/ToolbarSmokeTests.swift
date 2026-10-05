import XCTest

@MainActor
final class ToolbarSmokeTests: XCTestCase {
    func testEnglishToolbar() {
        captureToolbar(language: "en", locale: "en_US", queries: [
            "Select tool", "Track network tool", "Train tool",
        ])
    }

    func testTraditionalChineseScreenshots() {
        // Use identifiers, not translated text: these are visual evidence,
        // not assertions about the wording of the Traditional Chinese UI.
        captureToolbar(language: "zh-Hant", locale: "zh_TW", queries: [
            "tool.select", "tool.network", "tool.train",
        ])
    }

    private func captureToolbar(language: String, locale: String, queries: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        // The app opens on the start screen; start a new game from it.
        let newGame = app.buttons["start.newGame"]
        guard newGame.waitForExistence(timeout: 10) else {
            XCTFail("Missing start screen button: New Game")
            return
        }
        newGame.tap()

        let tools = ["select", "network", "train"]
        for (index, query) in queries.enumerated() {
            let button = app.buttons[query]
            guard button.waitForExistence(timeout: 10) else {
                XCTFail("Missing toolbar button: \(query)")
                return
            }
            XCTAssertTrue(button.isHittable, "Toolbar button cannot be tapped: \(query)")
            button.tap()

            // XCTest's idle check can finish before iOS has rendered the end
            // of touch feedback and the tool panel's layout change. Only the
            // test runner sleeps; the app can finish rendering its new state.
            Thread.sleep(forTimeInterval: 1)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(language)-0\(index + 1)-\(tools[index])"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

/// This class is absent from ios-build.yml's PR gate selection.
@MainActor
final class LineRoutePreferenceUITests: XCTestCase {
    /// Decision 61: a new UI test stays in the full lane. The menu binds a
    /// platform to a real-world demo leg and can restore automatic routing.
    func testALineLegCanSelectAPhysicalPlatform() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let demo = app.buttons["start.realWorldDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        if !demo.isHittable { app.swipeUp() }
        demo.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15)); pause.tap()
        let lines = app.buttons["Lines"]
        XCTAssertTrue(lines.waitForExistence(timeout: 10)); lines.tap()
        let route = app.buttons["line.route.-1.0.1"]
        for _ in 0..<6 where !route.isHittable { app.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 10)); XCTAssertTrue(route.isHittable)
        recordRouteUI("before opening route menu", in: app)
        route.tap()
        recordRouteUI("after opening route menu", in: app)
        let platform = app.buttons["line.route.choice.-1.0.1.0"]
        tapMenuAction(platform, in: app)
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Platform track #"), object: route)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        route.tap()
        let automatic = app.buttons["Automatic physical path"]
        tapMenuAction(automatic, in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Automatic physical path"), object: route)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }

    private func tapMenuAction(_ button: XCUIElement, in app: XCUIApplication) {
        guard button.waitForExistence(timeout: 10) else {
            recordRouteUI("missing menu action", in: app)
            XCTFail("Missing route menu action; see the attached accessibility hierarchy")
            return
        }
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        let frame = button.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(app.frame.contains(center))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: center.x - app.frame.minX, dy: center.y - app.frame.minY)).tap()
    }

    private func recordRouteUI(_ phase: String, in app: XCUIApplication) {
        // Keep the actual AX frames in the full-lane log, including when a
        // native menu fails to expose the expected SwiftUI identifier.
        let hierarchy = app.debugDescription
        print("Route menu diagnostics (\(phase)):\n\(hierarchy)")
        let attachment = XCTAttachment(string: hierarchy)
        attachment.name = "Route menu — \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
