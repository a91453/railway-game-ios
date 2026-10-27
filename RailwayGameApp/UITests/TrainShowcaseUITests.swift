import XCTest

/// Decision 434: the demo mode's train showcase opens from the settings of
/// a test build, and "Hide Buttons" leaves only the trains until the
/// picture is tapped. In the full lane only (decision 199).
@MainActor
final class TrainShowcaseUITests: XCTestCase {
    func testTheShowcaseHidesItsButtonsUntilThePictureIsTapped() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let settings = app.buttons["start.settings"]
        XCTAssertTrue(settings.appears(within: 30), "Missing start.settings")
        settings.tap()
        XCTAssertTrue(app.switches["settings.music"].appears(within: 10), "Missing the settings")

        // The version row, at the foot of the list, tapped five times in a
        // row shows the demo mode's rows (decision 351); the switch itself
        // is left as it is. The taps count only when each follows the last
        // within DemoMode.tapGap (1.5 s), and on a loaded runner a tap can
        // take longer than that, so a batch is tried again (the count
        // starts over after the pause) until a row shows. The rows sit
        // below the version row, and a List holds no row that is off the
        // screen, so "shown" is read from the switch and the showcase row
        // alike, then the list is dragged to the showcase row.
        let version = app.descendants(matching: .any)["settings.version"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(version, clearOf: .slider), "Missing the version row")
        let showcase = app.buttons["settings.trainShowcase"]
        let demoSwitch = app.switches["settings.demoMode"]
        for _ in 0..<4 where !showcase.exists && !demoSwitch.exists {
            for _ in 0..<5 { version.tap() }
            _ = showcase.appears(within: 3) || demoSwitch.appears(within: 1)
        }
        XCTAssertTrue(demoSwitch.exists || showcase.exists, "The version row's taps did not show the demo mode's rows")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(showcase, clearOf: .slider), "Missing the train showcase row")
        showcase.tap()

        let hide = app.buttons["trainShowcase.hide"]
        XCTAssertTrue(hide.appears(within: 60), "The showcase did not open")
        XCTAssertTrue(app.descendants(matching: .any)["trainShowcase.controls"].firstMatch.appears(within: 10), "Missing the controls")
        XCTAssertTrue(hide.becomesHittable(within: 5))
        hide.tap()
        XCTAssertTrue(hide.disappears(within: 10), "Hide Buttons left the buttons")
        XCTAssertTrue(app.descendants(matching: .any)["trainShowcase.controls"].firstMatch.disappears(within: 10), "The controls stayed")
        XCTAssertFalse(app.buttons["trainShowcase.close"].exists)
        let reveal = app.descendants(matching: .any)["trainShowcase.reveal"].firstMatch
        XCTAssertTrue(reveal.appears(within: 10), "Nothing to tap to bring the buttons back")

        // A tap on the picture brings them back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(hide.appears(within: 10), "A tap did not bring the buttons back")
        let close = app.buttons["trainShowcase.close"]
        XCTAssertTrue(close.becomesHittable(within: 5))
        close.tap()
        XCTAssertTrue(close.disappears(within: 10), "Close did not close the showcase")
    }
}
