import XCTest

@MainActor
final class MapInteractionTests: XCTestCase {
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
        map.pinch(withScale: 1.5, velocity: 1)
        XCTAssertFalse(clear.isEnabled, "Pinching must not pick a track anchor")
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
        for _ in 0..<4 { zoomIn.tap() }
        XCTAssertFalse(zoomIn.isEnabled, "64 points per tile is the maximum zoom")
        XCTAssertTrue(zoomOut.isEnabled)
        zoomOut.tap()
        XCTAssertTrue(zoomIn.isEnabled)
    }
}
