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
        route.tap()
        let platform = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Platform track #", "automatic route")).firstMatch
        XCTAssertTrue(platform.waitForExistence(timeout: 10)); platform.tap()
        XCTAssertTrue(route.label.contains("Platform track #"))
        route.tap()
        let automatic = app.buttons["Automatic physical path"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 10)); automatic.tap()
        XCTAssertTrue(route.label.contains("Automatic physical path"))
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
