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
        waitForEnabled(app, true)
        next.tap()
        waitForEnabled(app, false)

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
        // The row can be the map's bottom edge, where the Map Layers button
        // sits in the leading corner: start the track to its right.
        let layers = app.buttons["map.layers"]
        let left = layers.exists ? max(visibleMap.minX + 50, layers.frame.maxX + 24) : visibleMap.minX + 50
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: left, dy: row)).tap()
        origin.withOffset(CGVector(dx: left + 80, dy: row)).tap()
        waitForEnabled(app, false, "Choosing the ends only previews track")
        let build = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Build Track")).firstMatch
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        waitForEnabled(app, true, buttonDescription: "Build Track (label prefix)", query: {
            $0.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Build Track"))
        })
        // The step asks for this button: the card must leave it usable.
        XCTAssertTrue(build.isHittable)
        XCTAssertFalse(card.frame.intersects(build.frame), "The tutorial card covers Build Track")
        let label = build.label
        build.tap()
        // A press can be dropped on a loaded runner (run 37554617441: the
        // button highlighted, its action never ran): tap once more only
        // while nothing was built (a built track disables the button).
        let built = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Built ")).firstMatch
        if !built.waitForExistence(timeout: 10) {
            let again = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            if again.exists, again.isEnabled { again.tap() }
            XCTAssertTrue(built.waitForExistence(timeout: 10), "Build Track did not build")
        }
        waitForEnabled(app, true)
        next.tap()
        // Stage E1: the map step waits until the player moves the map. The
        // zoom buttons are among its controls, so the card leaves them free.
        waitForEnabled(app, false, "The map step waits for the map to move")
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 5))
        XCTAssertTrue(zoomIn.isHittable)
        XCTAssertFalse(card.frame.intersects(zoomIn.frame), "The tutorial card covers the zoom buttons")
        capture(app, name: "en-tutorial-map-step")
        zoomIn.tap()
        waitForEnabled(app, true)
        next.tap()
        // The next step asks for a station, so Next waits again; Done is the
        // last of eleven steps and is checked in TutorialSessionTests.
        XCTAssertEqual(next.label, "Next")
        waitForEnabled(app, false, "The station step waits for a station")
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
        waitForEnabled(app, false, "The first step waits for the network tool")
        XCTAssertFalse(back.exists, "The first step has no Back button")

        // The outlined button must receive the touch underneath the overlay.
        checkToolIsUncovered(app, identifier: "tool.network")
        app.buttons["tool.network"].tap()
        waitForEnabled(app, true)
        XCTAssertTrue(app.buttons["tool.network"].isSelected)
        checkToolIsUncovered(app, identifier: "tool.select")
        selectTool(app, "tool.select")
        waitForEnabled(app, false)
        selectTool(app, "tool.network")
        waitForEnabled(app, true)
        capture(app, name: "\(screenshotPrefix)-tutorial-tool")
        next.tap()

        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, backLabel)
        waitForEnabled(app, false)
        capture(app, name: "\(screenshotPrefix)-tutorial-map")
        back.tap()
        XCTAssertFalse(back.exists)
        waitForEnabled(app, true)

        // Reflowing the card must preserve navigation and usable controls.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable)
        checkToolIsUncovered(app, identifier: "tool.network")
        checkToolIsUncovered(app, identifier: "tool.select")
        selectTool(app, "tool.select")
        waitForEnabled(app, false)
        selectTool(app, "tool.network")
        waitForEnabled(app, true)
        capture(app, name: "\(screenshotPrefix)-tutorial-landscape")
        skip.tap()
        XCTAssertFalse(next.exists)
        // The restarted tutorial's first step waits for Network again.
        selectTool(app, "tool.select")

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
        waitForEnabled(app, false)
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

    /// Taps tool `identifier` until it is selected, at most twice. A touch
    /// synthesized while the Simulator settles a rotation, or while the
    /// app answers a slow accessibility query, can be lost (the recordings
    /// of runs 37196759420 and 37515199643 show the touch landing on the
    /// uncovered button with no effect); the step reads which tool is
    /// selected, so that is what must be true before going on.
    private func selectTool(
        _ app: XCUIApplication, _ identifier: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<2 {
            app.buttons[identifier].tap()
            let deadline = Date().addingTimeInterval(5)
            repeat {
                if app.buttons[identifier].isSelected { return }
                Thread.sleep(forTimeInterval: 0.25)
            } while Date() < deadline
        }
        XCTFail("\(identifier) is not selected after two taps", file: file, line: line)
    }

    private func waitForEnabled(
        _ app: XCUIApplication, _ enabled: Bool, _ message: String = "",
        buttonDescription: String = "tutorial.next",
        query: (XCUIApplication) -> XCUIElementQuery = { $0.buttons.matching(identifier: "tutorial.next") },
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            // The card is rebuilt for each step. Resolve the current buttons
            // on every poll, and never accept an absent or duplicate match.
            let buttons = query(app).allElementsBoundByIndex
            if buttons.count == 1, buttons[0].isEnabled == enabled {
                return
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            Thread.sleep(forTimeInterval: min(0.25, remaining))
        } while Date() < deadline

        // One slow query can use up the whole wait: the final state counts.
        let buttons = query(app).allElementsBoundByIndex
        if buttons.count == 1, buttons[0].isEnabled == enabled {
            return
        }
        let states = buttons.enumerated().map { index, button in
            "[\(index)] isEnabled=\(button.isEnabled)"
        }.joined(separator: ", ")
        let diagnostics = "Timed out after 5 seconds waiting for \(buttonDescription) isEnabled=\(enabled); found \(buttons.count) matching buttons: [\(states)]. \(message)"
        let hierarchy = XCTAttachment(string: "\(diagnostics)\n\n\(app.debugDescription)")
        hierarchy.name = "waitForEnabled-\(buttonDescription)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        capture(app, name: "waitForEnabled-\(buttonDescription)-timeout")
        XCTFail(diagnostics, file: file, line: line)
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
