import XCTest

@MainActor
final class MapInteractionTests: XCTestCase {
    func testDemoMapOpensOnItsNetwork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let demoMap = app.buttons["start.demoMap"]
        XCTAssertTrue(demoMap.waitForExistence(timeout: 10))
        demoMap.tap()
        let select = app.buttons["tool.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((map.value as? String)?.contains("Central") == true,
                      "The opening camera must put Central at the map view's center; value: \(String(describing: map.value))")
    }

    func testZoomingOutShowsTheWholeLargeMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let demoMap = app.buttons["start.demoMap"]
        XCTAssertTrue(demoMap.waitForExistence(timeout: 10))
        demoMap.tap()
        let select = app.buttons["tool.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let zoomOut = app.buttons["Zoom out"]
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 10))
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))

        for _ in 0..<12 {
            if !zoomOut.isEnabled { break }
            zoomOut.tap()
        }
        XCTAssertFalse(zoomOut.isEnabled, "The whole 1024 × 1024 map must fit within 12 zoom-out taps")
        XCTAssertTrue(zoomIn.isEnabled)
        XCTAssertTrue(zoomIn.isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "en-large-map-whole"
        attachment.lifetime = .keepAlways
        add(attachment)

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((map.value as? String)?.contains("Central") == true,
                      "Tapping the whole map's center must still select Central; value: \(String(describing: map.value))")
    }

    /// A drag or pinch must not become the first/second tap of a new
    /// construction. After navigation, ordinary taps must still build.
    func testNavigationDoesNotChooseConstructionPoints() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        network.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(clear.isEnabled)

        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertFalse(clear.isEnabled, "Dragging must not pick a track anchor")
        map.pinch(withScale: 3, velocity: 1)
        XCTAssertFalse(clear.isEnabled, "Pinching must not pick a track anchor")
        XCTAssertFalse(app.buttons["Zoom in"].isEnabled, "A pinch past 2× must reach the camera's maximum zoom")
        XCTAssertTrue(app.buttons["Zoom out"].isEnabled)

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35)).tap()
        XCTAssertTrue(clear.isEnabled, "Taps after navigating must still reach the network tool")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35)).tap()
        let build = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        XCTAssertTrue(build.isEnabled, "Two taps after a pinch must make a buildable preview")
        build.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Built '")).firstMatch.waitForExistence(timeout: 5))
    }

    func testZoomButtonsRemainUsableWithoutPinching() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        // A step doubles the size (Stage E1): 32 points per 16 m to 64, the
        // maximum zoom.
        zoomIn.tap()
        XCTAssertFalse(zoomIn.isEnabled, "64 points per 16 m is the maximum zoom")
        XCTAssertTrue(zoomOut.isEnabled)
        zoomOut.tap()
        XCTAssertTrue(zoomIn.isEnabled)
    }

    func testRotationKeepsTheCameraZoom() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        zoomIn.tap()
        XCTAssertFalse(zoomIn.isEnabled)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertFalse(zoomIn.isEnabled, "Changing the layout must keep the camera's maximum zoom")
        app.buttons["Zoom out"].tap()
        XCTAssertTrue(zoomIn.isEnabled)
    }
}
