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

        XCTAssertTrue(flip(sounds, from: before), "The sound effects switch did not change")
        XCTAssertTrue(flip(sounds, from: switchValue(sounds)), "The sound effects switch did not change back")
        XCTAssertEqual(switchValue(sounds), before)

        tap(app.buttons["settings.done"], name: "settings.done")
        // The start screen's buttons exist under the sheet too: what shows
        // the sheet closed is its Done button gone.
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 10), "Done did not close the settings")
        XCTAssertTrue(app.buttons["start.newGame"].waitForExistence(timeout: 10))
    }

    func testTheGameMenuOpensTheSameSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        openSettingsFromTheGameMenu(app)
        XCTAssertTrue(app.switches["settings.sounds"].exists, "Missing the sound effects switch")
        tap(app.buttons["settings.done"], name: "settings.done")
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 10), "Done did not go back to the game")
        XCTAssertTrue(app.buttons["hud.menu"].waitForExistence(timeout: 10))
    }

    /// With the Lines panel open (a half-height sheet that leaves the HUD
    /// usable) the game menu's Settings still opens, in the panel's place.
    /// It pins the behaviour only: with Settings back as a sheet of the
    /// HUD's own (#202 reverted) it passed too on the iOS 26.5 Simulator
    /// (run 37730023961), so it is no proof of that change.
    func testTheGameMenuOpensSettingsWithTheLinesPanelOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["Lines"], name: "Lines")
        XCTAssertTrue(app.navigationBars["Lines"].waitForExistence(timeout: 10), "The Lines panel did not open")
        openSettingsFromTheGameMenu(app)
        XCTAssertFalse(app.navigationBars["Lines"].exists, "Settings takes the Lines panel's place")
        tap(app.buttons["settings.done"], name: "settings.done")
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 10), "Done did not go back to the game")
    }

    /// Opens the game menu and chooses Settings, and waits for its music
    /// switch. A native menu's action can report hittable and still fail
    /// to compute its activation point (as in StartSaveFlowSmokeTests):
    /// touch the middle of its frame, and once more if the menu is still
    /// open.
    private func openSettingsFromTheGameMenu(_ app: XCUIApplication) {
        tap(app.buttons["hud.menu"], name: "hud.menu")
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
    }

    private func tap(_ element: XCUIElement, name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "Missing \(name)")
        element.tap()
    }

    /// Taps the switch itself (a tap on a toggle row's label does not
    /// always flip it) until its value is no longer `value`. The sheet may
    /// still be presenting when the switch first exists, and a tap then
    /// can be lost (as the map layers sheet's, MapInteractionTests): wait
    /// until it can be hit, and tap again while it has not changed.
    private func flip(_ toggle: XCUIElement, from value: String) -> Bool {
        for _ in 0..<3 {
            let inner = toggle.switches.firstMatch
            let target = inner.exists ? inner : toggle
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: target)], timeout: 5)
            target.tap()
            if waitForValue(toggle, not: value) { return true }
        }
        return false
    }

    private func switchValue(_ toggle: XCUIElement) -> String {
        toggle.value as? String ?? ""
    }

    private func waitForValue(_ toggle: XCUIElement, not other: String) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if switchValue(toggle) != other { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }
}
