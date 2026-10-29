import XCTest

/// Decision 434: the train showcase (decision 492: the garage) opens from
/// the settings, and "Hide Buttons" leaves only the trains until the
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

        // Decision 492: the garage's row, for every player.
        let showcase = app.buttons["settings.trainGarage"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(showcase, clearOf: .slider), "Missing the garage row")
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
