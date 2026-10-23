import XCTest

/// Decision 305: a line open 06:00–20:00 at 01:00 ("quiet-night"), when
/// no train runs until the morning, shows "Skip to Morning" under the speed; tapping it runs the
/// game on and the chip goes once the morning is near. In the full lane
/// (decision 199): where it stops is GamePresentation's, tested on Linux
/// (`NightSkipTests`); this asks only whether it shows and a finger
/// reaches it.
@MainActor
final class NightSkipUITests: XCTestCase {
    func testTheNightsShortcutShowsAndRunsToTheMorning() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-world", "quiet-night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let skip = app.buttons["hud.nightSkip"]
        XCTAssertTrue(skip.appears(within: 60), "no shortcut over the quiet night")
        XCTAssertTrue(skip.becomesHittable(within: 5), "the shortcut is not reachable")
        XCTAssertTrue(skip.label.hasPrefix("Skip to Morning"), skip.label)
        skip.tap()
        // About four hours at ten minutes a tick: a few seconds.
        XCTAssertTrue(skip.disappears(within: 30), "the shortcut stayed")
        let stop = app.buttons["hud.nightSkip.stop"]
        XCTAssertTrue(stop.disappears(within: 60), "the skip did not reach the morning")
        XCTAssertFalse(app.buttons["hud.nightSkip"].exists, "offered again at its own stop")
    }
}

/// Decision 371: the flat map's frame readout on a map of 44 stations, by
/// day at 1× and at night at the opening speed, printed to the log for a
/// comparison between two commits on the same Simulator (the numbers are
/// not a phone's). By hand only (`ios-build.yml`'s `only_testing`); the
/// full lane skips it. It asserts nothing but that the readout shows.
@MainActor
final class MapFrameCostUITests: XCTestCase {
    func testTheFrameReadoutOnABigMapByDay() {
        readOut("big-grid")
    }

    func testTheFrameReadoutOnABigMapAtNight() {
        readOut("big-grid-night")
    }

    private func readOut(_ world: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-test-world", world, "-map.showsFrameRate", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        let readout = app.buttons["map.frameRate"]
        XCTAssertTrue(readout.appears(within: 60), "no frame readout")
        readout.tap()
        for second in 1...4 {
            Thread.sleep(forTimeInterval: 5)
            print("[frame-cost] \(world) at \(second * 5) s: \(readout.label)")
        }
    }
}
