import XCTest

/// Stage E2: a real-world game starts from a place in the list and is
/// played over Apple's map. The map's tiles need the network, so nothing
/// here looks at them: only that the game starts on a real-world map,
/// that its style can be changed, and that its save says what it is.
@MainActor
final class RealWorldMapUITests: XCTestCase {
    func testARealWorldGameStartsFromAPlaceAndIsSavedAsOne() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tappable(app.buttons.matching(identifier: "start.realWorld"), name: "start.realWorld").tap()

        let taipei = tappable(app.buttons.matching(identifier: "place.tra-taipei"), name: "place.tra-taipei")
        XCTAssertEqual(taipei.label, "Taipei", "The references' places are listed")
        taipei.tap()
        capture(app, name: "real-world-01-picker")

        tappable(app.buttons.matching(identifier: "realWorld.start"), name: "realWorld.start").tap()

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "The game starts")
        let style = app.buttons["map.style"]
        XCTAssertTrue(style.waitForExistence(timeout: 10), "Only a real-world map has a map style menu")
        XCTAssertTrue(app.buttons["Zoom in"].exists)
        capture(app, name: "real-world-02-game")

        // Keep the live clock from rebuilding the native menus (the map
        // style's and the game's) while XCTest targets their actions, as in
        // the start and save flow: pause before opening either.
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        tappable(app.buttons.matching(identifier: "map.style"), name: "map.style").tap()
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Satellite")), name: "Satellite").tap()
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        capture(app, name: "real-world-03-satellite")

        tappable(app.buttons.matching(identifier: "hud.menu"), name: "hud.menu").tap()
        tappable(app.buttons.matching(identifier: "menu.backToStart"), name: "menu.backToStart").tap()

        let continueButton = tappable(app.buttons.matching(identifier: "start.continue"), name: "start.continue")
        XCTAssertTrue(continueButton.label.contains("Real-world map"), "The autosave is a real-world map's: \(continueButton.label)")
        continueButton.tap()
        XCTAssertTrue(app.buttons["map.style"].waitForExistence(timeout: 15), "Continuing keeps the real-world map")
    }

    /// Stage V4e: the real-world demo runs under traffic control, and the
    /// map's traffic key appears and reads out the movement authority its
    /// trains take. Full lane only (not in the pull request gate).
    func testTheRealWorldDemoShowsMovementAuthorityOnTheMap() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        // The demo's button is the start screen's last: scroll to it.
        let demo = app.buttons["start.realWorldDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "Missing button: start.realWorldDemo")
        for _ in 0..<4 where !demo.isHittable { app.swipeUp() }
        tappable(app.buttons.matching(identifier: "start.realWorldDemo"), name: "start.realWorldDemo").tap()

        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 60), "The demo starts")
        let authority = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "map.traffic", "Movement authority")).firstMatch
        XCTAssertTrue(authority.waitForExistence(timeout: 60), "The demo's trains take their routes under traffic control")
        capture(app, name: "real-world-04-traffic")
    }

    /// A blank new game has no Apple map and no style menu.
    func testABlankGameHasNoMapStyle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["map.style"].exists)
    }

    /// The copy of a button the player can touch. Existence can come before
    /// a menu or screen transition ends, and `ViewThatFits` can also expose
    /// an unplaced copy of a menu action, so `firstMatch` alone may not be
    /// hittable (the start and save flow's rule, `StartSaveFlowSmokeTests`).
    private func tappable(_ query: XCUIElementQuery, name: String) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "Missing button: \(name)")
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let button = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                XCTAssertTrue(button.isEnabled, "Button is disabled: \(name)")
                return button
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("Button cannot be tapped: \(name)")
        return query.firstMatch
    }

    private func capture(_ app: XCUIApplication, name: String) {
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
