import XCTest

@MainActor
final class ToolbarSmokeTests: XCTestCase {
    func testEnglishToolbar() {
        checkToolbar(language: "en", locale: "en_US", queries: [
            "Select tool", "Track network tool", "Train tool", "Building tool",
        ])
    }

    func testTraditionalChineseToolbar() {
        // Identifiers, not translated text: the wording is the localization
        // check's (localization.yml), not this test's.
        checkToolbar(language: "zh-Hant", locale: "zh_TW", queries: [
            "tool.select", "tool.network", "tool.train", "tool.building",
        ])
    }

    /// The app has no Japanese interface: someone who reads Japanese first
    /// and Traditional Chinese second gets the Chinese one, not English.
    func testJapaneseThenTraditionalChineseGetsChinese() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(ja, zh-Hant)", "-AppleLocale", "ja_JP"]
        app.launch()
        defer { app.terminate() }
        let brand = app.staticTexts["start.brand"]
        XCTAssertTrue(brand.waitForExistence(timeout: 10))
        XCTAssertEqual(brand.label, "沿線")
        XCTAssertTrue(app.buttons["start.newGame"].exists)
    }

    private func checkToolbar(language: String, locale: String, queries: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        let brand = app.staticTexts["start.brand"]
        XCTAssertTrue(brand.waitForExistence(timeout: 10))
        XCTAssertEqual(brand.label, language == "en" ? "Along the Line" : "沿線")

        // The app opens on the start screen; start a new game from it.
        let newGame = app.buttons["start.newGame"]
        guard newGame.waitForExistence(timeout: 10) else {
            XCTFail("Missing start screen button: New Game")
            return
        }
        newGame.tap()

        for query in queries {
            let button = app.buttons[query]
            guard button.waitForExistence(timeout: 10) else {
                XCTFail("Missing toolbar button: \(query)")
                return
            }
            XCTAssertTrue(button.isHittable, "Toolbar button cannot be tapped: \(query)")
            button.tap()
        }
    }
}

/// This class is absent from ios-build.yml's PR gate selection.
@MainActor
final class LineRoutePreferenceUITests: XCTestCase {
    /// Decision 61: a new UI test stays in the full lane. The menu binds a
    /// platform to a real-world demo leg and can restore automatic routing.
    func testALineLegCanSelectAPhysicalPlatform() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let demo = app.buttons["start.realWorldDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        app.bringStartButtonIntoView(demo)
        // Disabled until the real-world data, read in the background at
        // launch, is there.
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: demo)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 15), .completed, "The real-world demo button never became enabled")
        demo.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15)); pause.tap()
        let lines = app.buttons["Lines"]
        XCTAssertTrue(lines.waitForExistence(timeout: 10)); lines.tap()
        let route = app.buttons["line.route.-1.0.1"]
        bringIntoView(route, in: app)
        recordRouteUI("before opening route menu", in: app)
        route.tap()
        recordRouteUI("after opening route menu", in: app)
        let platform = app.buttons["line.route.choice.-1.0.1.0"]
        tapMenuAction(platform, in: app)
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Platform track #"), object: route)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        // Choosing a path posts a status message, pinned to the bottom of
        // the sheet over the row at the bottom of the screen: the next tap
        // landed on it and the menu never opened (main, 56dae15). Dismiss
        // it, then bring the row clear before opening the menu again.
        dismissMessage(in: app)
        bringIntoView(route, in: app)
        route.tap()
        let automatic = app.buttons["Automatic physical path"]
        tapMenuAction(automatic, in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Automatic physical path"), object: route)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }

    /// Dismisses the status message the sheet shows at its bottom, if
    /// any: the lowest "Dismiss message" button, the sheet's own (the map's
    /// lies under the sheet), and waits for it to go. A success clears
    /// itself 4 s after it appears (#182), so it is waited out rather than
    /// tapped: on a slow runner the banner went between finding the button
    /// and tapping it, and the tap failed on an element that no longer
    /// existed. Only a message still there after that wait is tapped.
    private func dismissMessage(in app: XCUIApplication) {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "Dismiss message")).allElementsBoundByIndex
        guard let lowest = buttons.filter({ $0.exists }).max(by: { $0.frame.minY < $1.frame.minY }) else { return }
        if lowest.waitForNonExistence(timeout: 8) { return }
        lowest.tap()
        XCTAssertTrue(lowest.waitForNonExistence(timeout: 5), "The status message stayed over the list")
    }

    /// Scrolls the Lines panel until `row` lies wholly on screen
    /// (``XCUIApplication/dragUntilWhollyOnScreen(_:in:)``). A fixed number
    /// of `swipeUp()` calls did not: one run stopped with the row's top
    /// 1 pt above the bottom of the screen (main a383f27: "hittable", but
    /// the tap at its centre opened no menu) and a slow one never brought
    /// it into existence (main 11c511f). Since decision 106 the panel is
    /// beside the map, not a sheet: a drag down the middle of the screen
    /// began on the dock or the map and never moved the list (main
    /// e48285f), so the drag is made on the panel's own list.
    private func bringIntoView(_ row: XCUIElement, in app: XCUIApplication) {
        let bar = app.navigationBars["Lines"].firstMatch
        let list = bar.exists
            ? app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
            : nil
        guard app.dragUntilWhollyOnScreen(row, in: list) else {
            recordRouteUI("row never came into view", in: app)
            XCTFail("\(row) never lay wholly on screen")
            return
        }
    }

    private func tapMenuAction(_ button: XCUIElement, in app: XCUIApplication) {
        guard button.waitForExistence(timeout: 10) else {
            recordRouteUI("missing menu action", in: app)
            XCTFail("Missing route menu action; see the attached accessibility hierarchy")
            return
        }
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        let frame = button.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(app.frame.contains(center))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: center.x - app.frame.minX, dy: center.y - app.frame.minY)).tap()
    }

    private func recordRouteUI(_ phase: String, in app: XCUIApplication) {
        // Keep the actual AX frames in the full-lane log, including when a
        // native menu fails to expose the expected SwiftUI identifier.
        let hierarchy = app.debugDescription
        print("Route menu diagnostics (\(phase)):\n\(hierarchy)")
        let attachment = XCTAttachment(string: hierarchy)
        attachment.name = "Route menu — \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
extension XCUIApplication {
    /// Drags a list until `element` lies wholly on screen; whether it does
    /// within 16 drags. A sheet's list (`list` `nil`): clear of the
    /// navigation bar at the top and the home indicator and a status
    /// banner at the bottom, dragged down the middle of the screen; a sheet
    /// at its middle height grows first, as a swipe would grow it. A panel
    /// beside the map (decision 106): within `list`, dragged down its
    /// middle, so the drag starts on the list and not on the map or the
    /// dock beside it. How far a `swipeUp()` flings a list depends on the
    /// synthesized event's timing; each drag here holds before lifting, so
    /// the list moves by the drag's length and does not fling.
    func dragUntilWhollyOnScreen(_ element: XCUIElement, in list: XCUIElement? = nil) -> Bool {
        let area = list.map(\.frame) ?? frame
        let top = list == nil ? frame.minY + 140 : area.minY + 8
        let bottom = list == nil ? frame.maxY - 120 : area.maxY - 8
        for _ in 0..<16 {
            if element.exists {
                let place = element.frame
                if place.minY >= top, place.maxY <= bottom, element.isHittable { return true }
                // Above the band: move the list down. Each drag is shorter
                // than the band less a row, so a row cannot jump over it.
                if place.minY < top {
                    drag(in: area, from: 0.45, to: 0.65)
                    continue
                }
            }
            drag(in: area, from: 0.75, to: 0.5)
        }
        return false
    }

    /// Drags vertically down the middle of `area` between two heights
    /// given as fractions of it, and holds before lifting, so a list does
    /// not fling.
    private func drag(in area: CGRect, from: CGFloat, to: CGFloat) {
        let origin = coordinate(withNormalizedOffset: .zero)
        let x = area.midX - frame.minX
        let start = origin.withOffset(CGVector(dx: x, dy: area.minY - frame.minY + area.height * from))
        let end = origin.withOffset(CGVector(dx: x, dy: area.minY - frame.minY + area.height * to))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Scrolls the start screen's buttons until `button` can be tapped. A
    /// phone on its side shows them in a column of their own beside the
    /// title (decision 106): a `swipeUp()` at the middle of the screen
    /// lands on the edge between the two and may scroll the title instead.
    func bringStartButtonIntoView(_ button: XCUIElement) {
        guard button.waitForExistence(timeout: 10), !button.isHittable else { return }
        let column = scrollViews.containing(.button, identifier: button.identifier).firstMatch
        for _ in 0..<6 where column.exists && !button.isHittable {
            // Slowly, so the column does not fling past the button.
            if button.frame.midY < column.frame.midY {
                column.swipeDown(velocity: .slow)
            } else {
                column.swipeUp(velocity: .slow)
            }
        }
    }
}
