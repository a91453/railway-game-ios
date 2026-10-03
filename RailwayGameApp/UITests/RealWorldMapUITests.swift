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

        let realWorld = app.buttons["start.realWorld"]
        XCTAssertTrue(realWorld.waitForExistence(timeout: 10))
        realWorld.tap()

        let taipei = app.buttons["place.tra-taipei"]
        XCTAssertTrue(taipei.waitForExistence(timeout: 10), "The references' places are listed")
        XCTAssertEqual(taipei.label, "Taipei")
        taipei.tap()
        capture(app, name: "real-world-01-picker")

        let build = app.buttons["realWorld.start"]
        XCTAssertTrue(build.waitForExistence(timeout: 10))
        build.tap()

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "The game starts")
        let style = app.buttons["map.style"]
        XCTAssertTrue(style.waitForExistence(timeout: 10), "Only a real-world map has a map style menu")
        XCTAssertTrue(app.buttons["Zoom in"].exists)
        capture(app, name: "real-world-02-game")

        style.tap()
        let satellite = app.buttons["Satellite"]
        XCTAssertTrue(satellite.waitForExistence(timeout: 10))
        satellite.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        capture(app, name: "real-world-03-satellite")

        // Keep the live clock from rebuilding the native menu while XCTest
        // targets its actions, as in the start and save flow.
        let pause = app.buttons.matching(NSPredicate(format: "label == %@", "Pause")).firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        app.buttons["hud.menu"].firstMatch.tap()
        let back = app.buttons["menu.backToStart"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()

        let continueButton = app.buttons["start.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        XCTAssertTrue(continueButton.label.contains("Real-world map"), "The autosave is a real-world map's: \(continueButton.label)")
        continueButton.tap()
        XCTAssertTrue(app.buttons["map.style"].waitForExistence(timeout: 15), "Continuing keeps the real-world map")
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

    private func capture(_ app: XCUIApplication, name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
