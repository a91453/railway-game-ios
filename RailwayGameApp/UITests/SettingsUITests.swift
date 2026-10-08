import XCTest

/// The settings screen from the start screen and from the game menu: the
/// music and sound effects switches, which the device keeps. Each test
/// turns a switch back to how it found it, so later tests hear the same.
@MainActor
final class SettingsUITests: XCTestCase {
    func testTheStartScreenSettingsTurnTheSoundEffectsOffAndOn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["start.settings"], name: "start.settings")
        let music = app.switches["settings.music"]
        let sounds = app.switches["settings.sounds"]
        XCTAssertTrue(music.waitForExistence(timeout: 10), "Missing the music switch")
        XCTAssertTrue(sounds.waitForExistence(timeout: 10), "Missing the sound effects switch")
        let before = switchValue(sounds)

        flip(sounds)
        XCTAssertTrue(waitForValue(sounds, not: before), "The sound effects switch did not change")
        flip(sounds)
        XCTAssertTrue(waitForValue(sounds, is: before), "The sound effects switch did not change back")

        tap(app.buttons["settings.done"], name: "settings.done")
        XCTAssertTrue(app.buttons["start.newGame"].waitForExistence(timeout: 10), "Done did not close the settings")
    }

    func testTheGameMenuOpensTheSameSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["hud.menu"], name: "hud.menu")
        // A native menu's action can report hittable and still fail to
        // compute its activation point (as in StartSaveFlowSmokeTests):
        // touch the middle of its frame, and once more if the menu is
        // still open.
        let action = app.buttons["menu.settings"]
        XCTAssertTrue(action.waitForExistence(timeout: 30), "Missing menu.settings")
        let frame = action.frame, bounds = app.frame
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - bounds.minX, dy: frame.midY - bounds.minY))
        point.tap()
        if !app.switches["settings.music"].waitForExistence(timeout: 10), action.exists, action.isHittable {
            point.tap()
        }
        XCTAssertTrue(app.switches["settings.music"].waitForExistence(timeout: 10), "Missing the music switch")
        XCTAssertTrue(app.switches["settings.sounds"].exists, "Missing the sound effects switch")
        tap(app.buttons["settings.done"], name: "settings.done")
        XCTAssertTrue(app.buttons["hud.menu"].waitForExistence(timeout: 10), "Done did not go back to the game")
    }

    private func tap(_ element: XCUIElement, name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "Missing \(name)")
        element.tap()
    }

    /// Taps the switch itself: a tap on a toggle row's label does not
    /// always flip it.
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        (inner.exists ? inner : toggle).tap()
    }

    private func switchValue(_ toggle: XCUIElement) -> String {
        toggle.value as? String ?? ""
    }

    private func waitForValue(_ toggle: XCUIElement, is value: String? = nil, not other: String? = nil) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            let now = switchValue(toggle)
            if let value, now == value { return true }
            if let other, now != other { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }
}
