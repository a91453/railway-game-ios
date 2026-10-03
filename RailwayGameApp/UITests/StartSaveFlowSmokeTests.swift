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

        openGameMenu(in: app)
        capture(app, name: "\(language)-flow-03-menu-save")

        requiredMenuAction("menu.saveGame", in: app).tap()
        assertGame(in: app)
        capture(app, name: "\(language)-flow-04-game-saved")

        openGameMenu(in: app)
        capture(app, name: "\(language)-flow-05-menu-return")

        requiredMenuAction("menu.backToStart", in: app).tap()
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
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10), "Missing game map")
        assertHittable(map, message: "Game map is not visible")
        for identifier in ["tool.select", "tool.network", "tool.train", "hud.menu"] {
            _ = requiredButton(identifier, in: app)
        }
    }

    private func openGameMenu(in app: XCUIApplication) {
        requiredButton("hud.menu", in: app).tap()
        _ = requiredMenuAction("menu.saveGame", in: app)
        _ = requiredMenuAction("menu.backToStart", in: app)
    }

    private func requiredButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing UI flow button: \(identifier)")
        XCTAssertTrue(button.isEnabled, "UI flow button is disabled: \(identifier)")
        assertHittable(button, message: "UI flow button cannot be tapped: \(identifier)")
        return button
    }

    private func requiredMenuAction(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing UI flow button: \(identifier)")
        XCTAssertTrue(button.isEnabled, "UI flow button is disabled: \(identifier)")
        // Native SwiftUI menus expose their action's identifier on a Button
        // inside a collection-view cell. On iOS 26 that inner Button has no
        // hittable point; the visible cell is the actual tap target. Keep the
        // identifier query and require the row to become tappable before use.
        let row = app.collectionViews.cells.containing(.button, identifier).element
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Missing menu row: \(identifier)")
        assertHittable(row, message: "UI flow menu action cannot be tapped: \(identifier)")
        return row
    }

    private func assertHittable(_ element: XCUIElement, message: String) {
        // Existence can precede the end of a menu or screen transition.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, message)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        // Match the toolbar screenshots: let touch feedback and layout finish
        // rendering after XCTest's idle check, without delaying the app itself.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
