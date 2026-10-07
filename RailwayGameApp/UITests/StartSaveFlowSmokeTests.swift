import XCTest

@MainActor
final class StartSaveFlowSmokeTests: XCTestCase {
    func testEnglishStartSaveFlow() {
        captureFlow(language: "en", locale: "en_US")
    }

    func testTraditionalChineseStartSaveFlow() {
        captureFlow(language: "zh-Hant", locale: "zh_TW")
    }

    private func captureFlow(language: String, locale: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        assertEmptyStart(in: app)
        capture(app, name: "\(language)-flow-01-start-empty")

        requiredButton("start.demoMap", in: app).tap()
        assertGame(in: app)
        capture(app, name: "\(language)-flow-02-demo-map")

        // Keep the live clock from rebuilding the native menu while XCTest
        // targets its actions, as in the tutorial UI tests. Use the real HUD.
        requiredButton(app.buttons.matching(NSPredicate(
            format: "label == %@", language == "en" ? "Pause" : "暫停"
        )), name: "Pause").tap()

        openGameMenu(in: app)
        capture(app, name: "\(language)-flow-03-menu-save")

        tapMenuAction("menu.saveGame", in: app)
        assertGame(in: app)
        capture(app, name: "\(language)-flow-04-game-saved")

        openGameMenu(in: app)
        capture(app, name: "\(language)-flow-05-menu-return")

        tapMenuAction("menu.backToStart", in: app)
        _ = requiredButton("start.newGame", in: app)
        _ = requiredButton("start.continue", in: app)
        // Back to Start creates only an autosave. This separate button also
        // proves that Save Game wrote a manual save rather than doing nothing.
        _ = requiredButton("start.savedGames", in: app)
        _ = requiredButton("start.demoMap", in: app)
        capture(app, name: "\(language)-flow-06-start-saved")

        requiredButton("start.continue", in: app).tap()
        assertGame(in: app)
        XCTAssertFalse(app.buttons["start.newGame"].exists, "Continue did not leave the start screen")
        capture(app, name: "\(language)-flow-07-continued-map")

        // Prove that the same installation starts clean again after both a
        // manual save and an autosave, in each language.
        app.terminate()
        app.launch()
        assertEmptyStart(in: app)
        capture(app, name: "\(language)-flow-08-start-reset")
    }

    private func assertEmptyStart(in app: XCUIApplication) {
        _ = requiredButton("start.newGame", in: app)
        _ = requiredButton("start.demoMap", in: app)
        XCTAssertFalse(app.buttons["start.continue"].exists, "A clean launch must not offer Continue")
        XCTAssertFalse(app.buttons["start.savedGames"].exists, "A clean launch must not list saved games")
    }

    private func assertGame(in app: XCUIApplication) {
        // The demo map's accessibility tree is large: on a slow runner one
        // query of it took 9 s, so its waits allow longer than a button's.
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 30), "Missing game map")
        assertHittable(map, timeout: 30, message: "Game map is not visible")
        for identifier in ["tool.select", "tool.network", "tool.train", "hud.menu"] {
            _ = requiredButton(identifier, in: app)
        }
    }

    private func openGameMenu(in app: XCUIApplication) {
        requiredButton("hud.menu", in: app).tap()
        _ = requiredButton("menu.saveGame", in: app)
        _ = requiredButton("menu.backToStart", in: app)
    }

    private func tapMenuAction(_ identifier: String, in app: XCUIApplication) {
        let button = requiredButton(identifier, in: app)
        // XCTest can report a native SwiftUI Menu action as hittable yet
        // fail to compute its activation point when tap() refreshes the
        // tree. Touch the visible frame's center, keeping the hittable and
        // enabled checks and the subsequent real save/return assertions.
        let frame = button.frame, bounds = app.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(bounds.contains(center), "Menu action is outside the app: \(identifier)")
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: center.x - bounds.minX, dy: center.y - bounds.minY))
        point.tap()
        // A row can show its press highlight and still not run its action
        // (run 37196737286: the menu stayed open and the map behind it was
        // never hittable). The menu closes when the action runs, so touch
        // it once more only while it is still open.
        if !menuCloses(app.buttons.matching(identifier: identifier), timeout: 10) {
            point.tap()
        }
    }

    /// Whether no copy of the menu action is left that the player can
    /// touch within `timeout` seconds.
    private func menuCloses(_ query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !query.allElementsBoundByIndex.contains(where: { $0.isHittable }) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    private func requiredButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        requiredButton(app.buttons.matching(identifier: identifier), name: identifier)
    }

    private func requiredButton(_ query: XCUIElementQuery, name: String) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "Missing UI flow button: \(name)")
        // ViewThatFits can also expose an unplaced copy of a menu action.
        // Find the button the player can touch, allowing the transition to
        // finish, and still fail if it is disabled or no copy is tappable.
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let button = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                XCTAssertTrue(button.isEnabled, "UI flow button is disabled: \(name)")
                return button
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("UI flow button cannot be tapped: \(name)")
        return query.firstMatch
    }

    private func assertHittable(_ element: XCUIElement, timeout: TimeInterval, message: String) {
        // Existence can precede the end of a menu or screen transition.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, message)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        // Match the toolbar screenshots: let touch feedback and layout finish
        // rendering after XCTest's idle check, without delaying the app itself.
        Thread.sleep(forTimeInterval: 1)
        // Screenshots are only for a person to look at (CLAUDE.md): a busy
        // runner's "Timed out while requesting screenshot" (run 37635507497)
        // must not fail the test, so its issue is expected, never required.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("A screenshot is an artifact, not a check", options: options) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
