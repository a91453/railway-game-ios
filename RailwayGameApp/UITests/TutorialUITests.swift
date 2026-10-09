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
        XCUIDevice.shared.orientation = .landscapeLeft
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
        selectTool(app, "tool.network")
        waitForEnabled(app, true)
        next.tap()
        waitForEnabled(app, false)

        // Tap the map where the card leaves it free: the card may sit on
        // the map (it may cover part of it, never a control).
        // The underlying map and the outlined Build Track action stay usable.
        let map = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Map,")).firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // The map runs up under the status pill, which floats over its
        // top: only the map below the pill can be tapped.
        let gameTime = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Game time")).firstMatch
        let hudBottom = max(app.buttons["hud.menu"].frame.maxY, gameTime.frame.maxY) + 12
        // The dock floats over the map's bottom (decision 106): only the
        // map above it can be tapped too.
        let dockTop = app.buttons["tool.select"].frame.minY - 12
        let wholeMap = map.frame.intersection(app.frame)
        let visibleMap = wholeMap
            .divided(atDistance: max(0, hudBottom - wholeMap.minY), from: .minYEdge).remainder
            .divided(atDistance: max(0, wholeMap.maxY - dockTop), from: .maxYEdge).remainder
        // Two points 60 apart on the map that no control covers: not the
        // card (on a wide screen it can stand beside the map's middle,
        // so a free row alone is not enough), not the Map Layers button,
        // and not the details card at the trailing side, where the Build
        // Track button is (decision 106).
        let layers = app.buttons["map.layers"]
        let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Build Track")).firstMatch
        var covered = [card.frame]
        if layers.exists { covered.append(layers.frame) }
        let free = action.exists
            ? visibleMap.divided(atDistance: max(0, visibleMap.maxX - (action.frame.minX - 20)), from: .maxXEdge).remainder
            : visibleMap
        guard let points = freePoints(in: free, avoiding: covered) else {
            return XCTFail("No free place on the map: map \(visibleMap), free \(free), card \(card.frame), layers \(layers.frame), action \(action.frame)")
        }
        let (first, second) = points
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: first.x, dy: first.y)).tap()
        origin.withOffset(CGVector(dx: second.x, dy: second.y)).tap()
        let tapped = "taps \(first), \(second); card \(card.frame), free \(free)"
        waitForEnabled(app, false, "Choosing the ends only previews track (\(tapped))")
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
        // while nothing was built. A built track disables the button for
        // good (its end starts the next stretch); the "Built …" banner is
        // no sign, as it clears itself after 4 s (#182), within one slow
        // accessibility query.
        let built = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: build)
        if XCTWaiter().wait(for: [built], timeout: 10) != .completed {
            let again = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            if again.exists, again.isEnabled { again.tap() }
        }
        // The step's own check that track was built.
        waitForEnabled(app, true, "Build Track did not build")
        next.tap()
        // Stage E1: the map step waits until the player moves the map. The
        // zoom buttons are among its controls, so the card leaves them free.
        waitForEnabled(app, false, "The map step waits for the map to move")
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 5))
        XCTAssertTrue(zoomIn.isHittable)
        XCTAssertFalse(card.frame.intersects(zoomIn.frame), "The tutorial card covers the zoom buttons")
        zoomIn.tap()
        waitForEnabled(app, true)
        next.tap()
        // The next step asks for a station, so Next waits again; Done is the
        // last of eleven steps and is checked in TutorialSessionTests.
        XCTAssertEqual(next.label, "Next")
        waitForEnabled(app, false, "The station step waits for a station")
        XCTAssertTrue(app.buttons["tutorial.back"].exists)
        app.buttons["tutorial.skip"].tap()
        // The card may still be closing right after Skip: wait for it to go.
        XCTAssertTrue(next.waitForNonExistence(timeout: 5), "Skip did not close the tutorial")
        XCTAssertTrue(app.buttons["tool.network"].isHittable)
    }

    private func checkNavigation(language: String, locale: String, tutorialLabel: String, nextLabel: String, backLabel: String, skipLabel: String, largeText: Bool = false) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        }
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
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
        // Through selectTool, as the later taps: a single synthesized touch
        // can be lost (run 37797595561 left Next disabled after one tap on
        // an uncovered network tool, in Traditional Chinese on the iPad).
        selectTool(app, "tool.network")
        waitForEnabled(app, true)
        XCTAssertTrue(app.buttons["tool.network"].isSelected)
        checkToolIsUncovered(app, identifier: "tool.select")
        selectTool(app, "tool.select")
        waitForEnabled(app, false)
        selectTool(app, "tool.network")
        waitForEnabled(app, true)
        next.tap()

        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, backLabel)
        waitForEnabled(app, false)
        back.tap()
        XCTAssertFalse(back.exists)
        waitForEnabled(app, true)

        // Reflowing the card must preserve navigation and usable controls.
        // A phone turns from one side to the other (decision 106: it
        // plays only on its side); an iPad from upright to its side.
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable)
        checkToolIsUncovered(app, identifier: "tool.network")
        checkToolIsUncovered(app, identifier: "tool.select")
        selectTool(app, "tool.select")
        waitForEnabled(app, false)
        selectTool(app, "tool.network")
        waitForEnabled(app, true)
        skip.tap()
        // The card may still be closing right after Skip: wait for it to go.
        XCTAssertTrue(next.waitForNonExistence(timeout: 5), "Skip did not close the tutorial")
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
        // The card may still be closing right after Skip: wait for it to go.
        XCTAssertTrue(next.waitForNonExistence(timeout: 5), "Skip did not close the tutorial")
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

    /// Two points of `map` 60 points apart in a row, each at least 12
    /// points inside it and clear of every frame in `covered` by 12: the
    /// first such pair, top row first, leading first. They fit the band of
    /// the map the tutorial's card leaves free beside it (96 points).
    private func freePoints(in map: CGRect, avoiding covered: [CGRect]) -> (CGPoint, CGPoint)? {
        let blocked = covered.map { $0.insetBy(dx: -12, dy: -12) }
        func isFree(_ point: CGPoint) -> Bool {
            map.insetBy(dx: 12, dy: 12).contains(point) && !blocked.contains { $0.contains(point) }
        }
        var y = map.minY + 12
        while y <= map.maxY - 12 {
            var x = map.minX + 12
            while x + 60 <= map.maxX - 12 {
                let first = CGPoint(x: x, y: y), second = CGPoint(x: x + 60, y: y)
                if isFree(first), isFree(second) { return (first, second) }
                x += 4
            }
            y += 8
        }
        return nil
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
        XCTFail(diagnostics, file: file, line: line)
    }
}
