import XCTest

/// ROSTERCRASH-2: the fleet's train roster opens its Arrange page from the
/// short rows. A player's report on 144 and again on 145: with many trains
/// and the phone on its side the roster shows its short rows, and Arrange
/// closed the app. The scene (`ScreenshotScene.rosterFleet`) has 24 trains
/// on sixteen lines and four on none; what the roster reads of it is
/// `TrainRosterTests` (Linux). This opens the roster as the player did,
/// from the fleet, and goes to Arrange and back.
@MainActor
final class TrainRosterArrangeUITests: XCTestCase {
    func testArrangeOpensFromShortRowsOnItsSide() {
        arrange(.landscapeLeft)
    }

    func testArrangeOpensFromShortRowsUpright() {
        arrange(.portrait)
    }

    private func arrange(_ orientation: UIDeviceOrientation) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-screenshot-scene", "rosterFleet"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")

        // The fleet, from Build → Train, then its roster.
        let build = app.buttons["dock.build"]
        build.waitUntilSettled()
        build.tap()
        let trainTool = app.buttons["tool.train"]
        XCTAssertTrue(trainTool.appears(within: 10), "The train tool shows")
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        XCTAssertTrue(fleet.appears(within: 5), "The fleet's button shows")
        fleet.tap()
        let open = app.buttons["fleet.roster"]
        XCTAssertTrue(open.appears(within: 10), "The fleet opens")
        open.waitUntilSettled()
        open.tap()
        let summary = app.staticTexts["trainRoster.summary"]
        XCTAssertTrue(summary.appears(within: 10), "The roster opens")
        XCTAssertTrue(summary.label.contains("24 列"), "Every train has a row: \(summary.label)")

        let pages = app.segmentedControls["trainRoster.page"]
        let arrange = pages.buttons["編排"]
        let roster = pages.buttons["運用表"]
        let hint = app.staticTexts["trainRoster.arrangeHint"]
        let waiting = app.descendants(matching: .any)["trainRoster.waiting"].firstMatch
        XCTAssertTrue(arrange.appears(within: 5), "The roster's pages show")
        // To Arrange and back, three times: the rows grow to their full
        // height and the waiting trains come in beside them, while the
        // roster is built again every second.
        for round in 1...3 {
            arrange.tap()
            XCTAssertTrue(hint.appears(within: 10), "Arrange says how (round \(round)); the app is \(app.state.rawValue)")
            XCTAssertTrue(waiting.appears(within: 5), "The waiting trains show (round \(round))")
            Thread.sleep(forTimeInterval: 2.5)
            XCTAssertEqual(app.state, .runningForeground, "The app closed on Arrange (round \(round))")
            roster.tap()
            XCTAssertTrue(hint.disappears(within: 10), "Back to the roster (round \(round)); the app is \(app.state.rawValue)")
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertEqual(app.state, .runningForeground, "The app closed back on the roster (round \(round))")
        }

        // On Arrange: the rows scrolled, then a waiting train held and
        // dragged onto a line's row.
        arrange.tap()
        XCTAssertTrue(hint.appears(within: 10), "Arrange says how; the app is \(app.state.rawValue)")
        let table = app.descendants(matching: .any)["trainRoster"].firstMatch
        let middle = table.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        middle.press(forDuration: 0.05, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(app.state, .runningForeground, "The app closed as the rows scrolled")
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "trainRoster.waiting.")).firstMatch
        XCTAssertTrue(card.appears(within: 5), "A waiting train shows")
        card.press(forDuration: 1.2, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(app.state, .runningForeground, "The app closed as a waiting train was dropped on a row")
        XCTAssertTrue(arrange.exists, "The roster is still up")
    }
}
