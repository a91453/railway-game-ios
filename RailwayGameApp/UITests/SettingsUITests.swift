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
        XCTAssertTrue(music.appears(within: 10), "Missing the music switch")
        XCTAssertTrue(sounds.appears(within: 10), "Missing the sound effects switch")
        let before = switchValue(sounds)

        XCTAssertTrue(flip(sounds, from: before), "The sound effects switch did not change")
        XCTAssertTrue(flip(sounds, from: switchValue(sounds)), "The sound effects switch did not change back")
        XCTAssertEqual(switchValue(sounds), before)

        // Decision 219, stage 2: the three volumes under the switches. On
        // a phone on its side, since the Language section above them
        // (decision 381), they start below the fold, and a List makes a
        // row only as it comes near (full lane 40026341039). Checked after
        // the switch: at the list's top the switch stays above the band
        // the drags bring a row into (run 40046083471).
        for volume in ["music", "chimes", "effects"] {
            XCTAssertTrue(app.dragUntilWhollyOnScreen(app.sliders["settings.volume.\(volume)"]), "Missing the \(volume) volume")
        }

        tap(app.buttons["settings.done"], name: "settings.done")
        // The start screen's buttons exist under the sheet too: what shows
        // the sheet closed is its Done button gone.
        XCTAssertTrue(app.buttons["settings.done"].disappears(within: 10), "Done did not close the settings")
        XCTAssertTrue(app.buttons["start.newGame"].appears(within: 10))
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
        XCTAssertTrue(app.buttons["settings.done"].disappears(within: 10), "Done did not go back to the game")
        XCTAssertTrue(app.buttons["hud.menu"].appears(within: 10))
    }

    /// Decision 152: the settings' 3D city preview opens full screen, its
    /// page comes from the game's website (decision 163), and the close
    /// button goes back to the settings. It waits for the loading indicator
    /// to go (`cityView.loading`, shown until the web view finishes loading
    /// the page): the website answered, whether or not the Simulator's
    /// WebGL then draws the city. A page the web view could not load shows
    /// why (`cityView.error`), and the test reports it.
    func testTheCityPreviewLoadsItsPageAndCloses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["start.settings"], name: "start.settings")
        XCTAssertTrue(app.switches["settings.sounds"].appears(within: 10), "The settings did not open")
        // A phone on its side shows only the first sections, and a List
        // makes a row only once it scrolls into view: since the Map section
        // (decision 182) the preview starts below the fold. On its side
        // neither the app's own swipe (it began on the navigation bar and
        // scrolled nothing) nor the row's own tap (it landed at the screen's
        // left edge, beside the row) reached it (PR #427's runs), so drag
        // the row into the middle of the screen and tap the centre of its
        // frame, as openSettingsFromTheGameMenu taps the menu's Settings.
        // The drags pass the volume sliders and must not start on one.
        let preview = app.buttons["settings.cityView"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(preview, clearOf: .slider), "The 3D city preview never came into view")
        let frame = preview.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY))
            .tap()
        XCTAssertTrue(app.buttons["cityView.close"].appears(within: 10), "The 3D city preview did not open")
        let loading = app.descendants(matching: .any)["cityView.loading"]
        let error = app.staticTexts["cityView.error"]
        let done = loading.disappears(within: 60)
        if error.exists {
            XCTFail(error.label)
        }
        XCTAssertTrue(done, "The page did not load from the website, and the web view reported no error")
        tap(app.buttons["cityView.close"], name: "cityView.close")
        XCTAssertTrue(app.buttons["cityView.close"].disappears(within: 10), "Close did not close the 3D city preview")
        XCTAssertTrue(app.buttons["settings.done"].appears(within: 10))
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
        XCTAssertTrue(app.navigationBars["Lines"].appears(within: 10), "The Lines panel did not open")
        openSettingsFromTheGameMenu(app)
        XCTAssertFalse(app.navigationBars["Lines"].exists, "Settings takes the Lines panel's place")
        tap(app.buttons["settings.done"], name: "settings.done")
        XCTAssertTrue(app.buttons["settings.done"].disappears(within: 10), "Done did not go back to the game")
    }

    /// Decision 193: from a game, the report can carry its save and
    /// commands, off until the player turns it on; turned on, it says what
    /// it holds, and Report a Problem still shares.
    func testTheGameMenusReportCanAttachTheSaveAndCommands() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        openSettingsFromTheGameMenu(app)
        let attach = app.switches["settings.report.attach"]
        // The screen's drags reached it after 21 of their 24 before
        // decision 381 lengthened the settings, and ran out after it (full
        // lane 40026341039). Drags on the list's own left edge, on a phone
        // on its side, moved nothing (run 40044305336).
        XCTAssertTrue(app.dragUntilWhollyOnScreen(attach, drags: 40, clearOf: .slider), "The attach switch never came into view")
        XCTAssertEqual(switchValue(attach), "0", "off until the player turns it on")
        XCTAssertTrue(flip(attach, from: "0"), "The attach switch did not turn on")
        let attached = app.staticTexts["settings.report.attached"]
        XCTAssertTrue(attached.appears(within: 30), "What is attached is not said")
        XCTAssertTrue(attached.label.contains("command-log.json"), attached.label)
        XCTAssertTrue(app.buttons["settings.report"].isEnabled, "Report a Problem shares with the file")
        XCTAssertTrue(flip(attach, from: "1"), "The attach switch did not turn off")
        XCTAssertFalse(attached.exists)
    }

    /// TestFlight 54.1: a player found the report only in the settings.
    /// The game menu's More opens the same rows on their own, with the
    /// game's save and commands to attach.
    func testTheGameMenuOpensTheProblemReport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tapHittable("hud.menu", in: app)
        // Decision 383: in the menu's first level.
        tapHittable("menu.report", in: app)
        XCTAssertTrue(app.buttons["settings.report"].appears(within: 10), "Missing Report a Problem")
        XCTAssertTrue(app.switches["settings.report.attach"].exists, "Missing the attach switch")
        XCTAssertFalse(app.switches["settings.music"].exists, "The report opens on its own, not the settings")
        tap(app.buttons["report.done"], name: "report.done")
        XCTAssertTrue(app.buttons["report.done"].disappears(within: 10), "Done did not go back to the game")
    }

    /// On a phone on its side the game menu shows about six rows: its
    /// Settings, the last, stays in reach without scrolling (main
    /// 84a792e's full lane, run 38861445072: an eighth row put it out of
    /// reach).
    func testTheGameMenusSettingsIsInReachOnAPhoneOnItsSide() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        openSettingsFromTheGameMenu(app)
        tap(app.buttons["settings.done"], name: "settings.done")
        XCTAssertTrue(app.buttons["settings.done"].disappears(within: 10), "Done did not go back to the game")
    }

    /// 2026-10-16: the shortcuts one tap from the game: the map's 3D
    /// button opens this game's 3D map; the postcard and the achievements
    /// stand in the game menu's first level; the train card shows its
    /// timetable with the lines panel's Advanced off (a phone's default).
    func testTheMapAndMenuShortcutsOpenTheirScreens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-paused", "-demo-layout", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 10))

        tapHittable("map.open3D", in: app)
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 15), "The 3D button opens the 3D map")
        tap(app.buttons["map3D.close"], name: "map3D.close")
        XCTAssertTrue(app.buttons["map3D.close"].disappears(within: 10), "Close goes back to the game")

        tapHittable("hud.menu", in: app)
        tapHittable("menu.postcard", in: app)
        tap(app.buttons["postcard.done"], name: "postcard.done")
        XCTAssertTrue(app.buttons["postcard.done"].disappears(within: 10))

        tapHittable("hud.menu", in: app)
        tapHittable("menu.achievements", in: app)
        tap(app.buttons["achievements.done"], name: "achievements.done")
        XCTAssertTrue(app.buttons["achievements.done"].disappears(within: 10))

        tap(app.buttons["dock.build"], name: "dock.build")
        let trainTool = app.buttons["tool.train"]
        XCTAssertTrue(trainTool.appears(within: 10))
        trainTool.waitUntilSettled()
        trainTool.tap()
        XCTAssertTrue(app.buttons["train.fleetOverview"].appears(within: 10))
        XCTAssertTrue(app.buttons["train.timetable"].appears(within: 10), "The timetable shows with Advanced off")
    }

    /// Taps the copy of the button `identifier` that can be touched: a
    /// native menu can hold an unplaced copy of an action
    /// (`WebsiteScreenshotTests.tapButton`).
    private func tapHittable(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let buttons = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(buttons.firstMatch.appears(within: timeout), "Missing \(identifier)")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let button = buttons.allElementsBoundByIndex.first(where: { $0.isHittable && $0.isEnabled }) {
                button.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("\(identifier) cannot be tapped")
    }

    /// Opens the game menu and chooses Settings, and waits for its music
    /// switch. A native menu's action can report hittable and still fail
    /// to compute its activation point (as in StartSaveFlowSmokeTests):
    /// touch the middle of its frame once the menu has finished opening
    /// (a frame read while it opens is not where the action ends up), and
    /// once more if the menu is still open.
    private func openSettingsFromTheGameMenu(_ app: XCUIApplication) {
        tap(app.buttons["hud.menu"], name: "hud.menu")
        let action = app.buttons["menu.settings"]
        XCTAssertTrue(action.appears(within: 30), "Missing menu.settings")
        action.waitUntilSettled()
        let frame = action.frame, bounds = app.frame
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - bounds.minX, dy: frame.midY - bounds.minY))
        point.tap()
        if !app.switches["settings.music"].appears(within: 10), action.exists, action.isHittable {
            point.tap()
        }
        XCTAssertTrue(app.switches["settings.music"].appears(within: 10), "Missing the music switch")
    }

    private func tap(_ element: XCUIElement, name: String) {
        XCTAssertTrue(element.appears(within: 30), "Missing \(name)")
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
