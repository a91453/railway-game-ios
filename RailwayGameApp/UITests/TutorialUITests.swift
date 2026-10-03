import XCTest

/// Exercises the CX-5 card against the tutorial's first steps (C5: the network
/// tool, then a stretch of track). Gameplay goals are tested in
/// TutorialSessionTests; these checks prove the overlay passes touches
/// through to the tool, observes completion and exposes its navigation.
@MainActor
final class TutorialUITests: XCTestCase {
    func testEnglishTutorialNavigation() {
        checkNavigation(language: "en", locale: "en_US", tutorialLabel: "Tutorial", nextLabel: "Next", backLabel: "Back", skipLabel: "Skip")
    }

    func testTraditionalChineseTutorialNavigation() {
        checkNavigation(language: "zh-Hant", locale: "zh_TW", tutorialLabel: "教學", nextLabel: "下一步", backLabel: "上一步", skipLabel: "略過")
    }

    func testLargeTextTutorialNavigation() {
        checkNavigation(language: "en", locale: "en_US", tutorialLabel: "Tutorial", nextLabel: "Next", backLabel: "Back", skipLabel: "Skip", largeText: true)
    }

    func testBuildingTrackEnablesNextAndSkipEnds() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let start = app.buttons["start.tutorial"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let next = app.buttons["tutorial.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        checkToolIsUncovered(app, identifier: "tool.network")
        app.buttons["tool.network"].tap()
        waitForEnabled(next, true)
        next.tap()
        waitForEnabled(next, false)

        // Tap the map in a row the card leaves free: the card may sit on the
        // map (it may cover part of it, never a control), above or below.
        // The underlying map and the outlined Build Track action stay usable.
        let map = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Map,")).firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let visibleMap = map.frame.intersection(app.frame)
        let row = freeRow(in: visibleMap, avoiding: card.frame)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: visibleMap.minX + 50, dy: row)).tap()
        origin.withOffset(CGVector(dx: visibleMap.minX + 130, dy: row)).tap()
        waitForEnabled(next, false, "Choosing the ends only previews track")
        let build = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Build Track")).firstMatch
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        waitForEnabled(build, true)
        // The step asks for this button: the card must leave it usable.
        XCTAssertTrue(build.isHittable)
        XCTAssertFalse(card.frame.intersects(build.frame), "The tutorial card covers Build Track")
        build.tap()
        waitForEnabled(next, true)
        next.tap()
        // Stage E1: the map step waits until the player moves the map. The
        // zoom buttons are among its controls, so the card leaves them free.
        waitForEnabled(next, false, "The map step waits for the map to move")
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 5))
        XCTAssertTrue(zoomIn.isHittable)
        XCTAssertFalse(card.frame.intersects(zoomIn.frame), "The tutorial card covers the zoom buttons")
        capture(app, name: "en-tutorial-map-step")
        zoomIn.tap()
        waitForEnabled(next, true)
        next.tap()
        // The next step asks for a station, so Next waits again; Done is the
        // last of eleven steps and is checked in TutorialSessionTests.
        XCTAssertEqual(next.label, "Next")
        waitForEnabled(next, false, "The station step waits for a station")
        XCTAssertTrue(app.buttons["tutorial.back"].exists)
        capture(app, name: "en-tutorial-station-step")
        app.buttons["tutorial.skip"].tap()
        XCTAssertFalse(next.exists)
        XCTAssertTrue(app.buttons["tool.network"].isHittable)
    }

    private func checkNavigation(language: String, locale: String, tutorialLabel: String, nextLabel: String, backLabel: String, skipLabel: String, largeText: Bool = false) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        }
        let screenshotPrefix = largeText ? "en-large-text" : language
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let start = app.buttons["start.tutorial"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.label.contains(tutorialLabel))
        start.tap()

        let next = app.buttons["tutorial.next"]
        let back = app.buttons["tutorial.back"]
        let skip = app.buttons["tutorial.skip"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertEqual(next.label, nextLabel)
        XCTAssertEqual(skip.label, skipLabel)
        XCTAssertFalse(next.isEnabled, "The first step waits for the network tool")
        XCTAssertFalse(back.exists, "The first step has no Back button")

        // The outlined button must receive the touch underneath the overlay.
        checkToolIsUncovered(app, identifier: "tool.network")
        app.buttons["tool.network"].tap()
        waitForEnabled(next, true)
        XCTAssertTrue(app.buttons["tool.network"].isSelected)
        checkToolIsUncovered(app, identifier: "tool.select")
        app.buttons["tool.select"].tap()
        waitForEnabled(next, false)
        app.buttons["tool.network"].tap()
        waitForEnabled(next, true)
        capture(app, name: "\(screenshotPrefix)-tutorial-tool")
        next.tap()

        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, backLabel)
        waitForEnabled(next, false)
        capture(app, name: "\(screenshotPrefix)-tutorial-map")
        back.tap()
        XCTAssertFalse(back.exists)
        waitForEnabled(next, true)

        // Reflowing the card must preserve navigation and usable controls.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable)
        checkToolIsUncovered(app, identifier: "tool.network")
        checkToolIsUncovered(app, identifier: "tool.select")
        app.buttons["tool.select"].tap()
        waitForEnabled(next, false)
        app.buttons["tool.network"].tap()
        waitForEnabled(next, true)
        capture(app, name: "\(screenshotPrefix)-tutorial-landscape")
        skip.tap()
        XCTAssertFalse(next.exists)
        app.buttons["tool.select"].tap()

        // The game menu starts the tutorial again without leaving this game.
        // Pause through the real HUD so a rapidly changing game clock does
        // not continuously rebuild the native menu while XCTest targets it.
        hittableButton(app.buttons.matching(NSPredicate(
            format: "label == %@", language == "en" ? "Pause" : "暫停"
        ))).tap()
        app.buttons[language == "en" ? "Game menu" : "遊戲選單"].tap()
        // ViewThatFits can expose an unplaced menu action with an infinite
        // frame as well as the visible native menu item. Select the action
        // the player can actually touch, rather than the hidden duplicate.
        let restart = hittableButton(app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "menu.tutorial", tutorialLabel
        )))
        XCTAssertEqual(restart.label, tutorialLabel)
        restart.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
        waitForEnabled(next, false)
        skip.tap()
        XCTAssertFalse(next.exists)
    }

    private func hittableButton(_ query: XCUIElementQuery) -> XCUIElement {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let visible = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                return visible
            }
            // Only the test runner waits; the app can finish opening the menu.
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("No visible tutorial menu action")
        return query.firstMatch
    }

    /// A row of `map` 24 points from an edge of the part `card` does not
    /// cover: above the card when there is room, otherwise below it.
    private func freeRow(in map: CGRect, avoiding card: CGRect) -> CGFloat {
        guard card.intersects(map) else { return map.minY + 24 }
        if card.minY - map.minY >= 48 { return map.minY + 24 }
        return min(card.maxY + 24, map.maxY - 24)
    }

    private func checkToolIsUncovered(_ app: XCUIApplication, identifier: String) {
        let tool = app.buttons[identifier]
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(tool.isHittable)
        XCTAssertFalse(card.frame.intersects(tool.frame), "The tutorial card covers \(identifier)")
    }

    private func waitForEnabled(_ element: XCUIElement, _ enabled: Bool, _ message: String = "") {
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: enabled))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, message)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        // A window screenshot can use stale portrait bounds after rotating
        // on iOS 26, cropping the game and filling the rest with black.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
