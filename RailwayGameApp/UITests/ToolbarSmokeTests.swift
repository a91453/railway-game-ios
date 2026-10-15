import XCTest

@MainActor
final class ToolbarSmokeTests: XCTestCase {
    func testEnglishToolbar() {
        checkToolbar(language: "en", locale: "en_US", queries: [
            "Construction", "Track network tool", "Train tool", "Building tool", "Done building",
        ])
    }

    func testTraditionalChineseToolbar() {
        // Identifiers, not translated text: the wording is the localization
        // check's (localization.yml), not this test's.
        checkToolbar(language: "zh-Hant", locale: "zh_TW", queries: [
            "dock.build", "tool.network", "tool.train", "tool.building", "tool.select",
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
        XCTAssertTrue(brand.appears(within: 10))
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
        XCTAssertTrue(brand.appears(within: 10))
        XCTAssertEqual(brand.label, language == "en" ? "Along the Line" : "沿線")

        // The app opens on the start screen; start a new game from it.
        let newGame = app.buttons["start.newGame"]
        guard newGame.appears(within: 10) else {
            XCTFail("Missing start screen button: New Game")
            return
        }
        newGame.tap()

        // Decision 114: Build opens the tools at the map's edge, and Done
        // closes them; so each is tapped in this order.
        for query in queries {
            let button = app.buttons[query]
            guard button.appears(within: 10) else {
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
        app.openDemo("demo.realWorld")
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.appears(within: 15)); pause.tap()
        let lines = app.buttons["Lines"]
        XCTAssertTrue(lines.appears(within: 10)); lines.tap()
        // Decision 196, later: the tracks a leg takes are an advanced detail.
        setAdvanced(true, in: app)
        let route = app.buttons["line.route.-1.0.1"]
        bringIntoView(route, in: app)
        recordRouteUI("before opening route menu", in: app)
        route.tap()
        recordRouteUI("after opening route menu", in: app)
        let platform = app.buttons["line.route.choice.-1.0.1.0"]
        tapMenuAction(platform, in: app)
        XCTAssertTrue(route.appears(within: 10))
        // "Platform on track #N · route chosen automatically" since decision
        // 201 (RoutePreview.choiceText).
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Platform on track #"), object: route)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        // Choosing a path posts a status message, pinned to the bottom of
        // the sheet over the row at the bottom of the screen: the next tap
        // landed on it and the menu never opened (main, 56dae15). Dismiss
        // it, then bring the row clear before opening the menu again.
        dismissMessage(in: app)
        bringIntoView(route, in: app)
        route.tap()
        let automatic = app.buttons["Automatic route"]
        tapMenuAction(automatic, in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Automatic route"), object: route)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }

    /// Decision 196, later: the lines panel's "Advanced" switch folds the
    /// tracks each leg takes and the service day on a phone, says what is
    /// folded in one line, and shows them again when turned on.
    func testTheAdvancedSwitchFoldsTheTracksAndTheServiceDay() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.realWorld")
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.appears(within: 15)); pause.tap()
        let lines = app.buttons["Lines"]
        XCTAssertTrue(lines.appears(within: 10)); lines.tap()
        setAdvanced(false, in: app)
        XCTAssertTrue(app.staticTexts["lines.advanced.summary"].appears(within: 10))
        XCTAssertFalse(app.buttons["line.route.-1.0.1"].exists)
        XCTAssertFalse(app.buttons["Split the Longest Band"].exists)
        setAdvanced(true, in: app)
        XCTAssertFalse(app.staticTexts["lines.advanced.summary"].exists)
        bringIntoView(app.buttons["line.route.-1.0.1"], in: app)
    }

    /// Turns the lines panel's "Advanced" switch on or off: the choice is
    /// kept between launches, so a test sets the one it needs.
    private func setAdvanced(_ shown: Bool, in app: XCUIApplication) {
        let toggle = app.switches["lines.advanced"]
        bringIntoView(toggle, in: app)
        guard (toggle.value as? String == "1") != shown else { return }
        // The switch itself sits at the row's trailing edge, some 51 points
        // wide inside a margin of about 16: a fixed 42 points in lands on
        // it whether the element's frame takes the margin in or not. At 95%
        // of the row the touch fell in the margin once the panel narrowed
        // to 270 points (#499; main's full lane, run 38404565525).
        // The switch control inside the row, where SwiftUI exposes it, at
        // its own activation point: since the tools became a column on a
        // phone on its side (#626), the row's frame no longer reached the
        // drawn switch, and 42 points in from it tapped the row three times
        // (main bf12187's full lane, run 38641908091: (540, 314), the switch
        // drawn at about 735).
        let control = toggle.switches.firstMatch
        if control.exists {
            control.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -42, dy: 0)).tap()
        }
        // Twenty seconds: as a job's first test, on a cold Simulator with
        // the real-world demo, one lookup took 10 to 20 seconds, and the
        // switch's value was first read 17 seconds after the tap (run
        // 38441429093); the same steps in the next test took a second.
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", shown ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [flipped], timeout: 20), .completed, "The Advanced switch did not turn \(shown ? "on" : "off")")
    }

    /// Dismisses the status message the sheet shows at its bottom, if
    /// any: the lowest "Dismiss message" button, the sheet's own (the map's
    /// lies under the sheet), and waits for it to go. A success clears
    /// itself 4 s after it appears (#182), so it is waited out rather than
    /// tapped: on a slow runner the banner went between finding the button
    /// and tapping it, and the tap failed on an element that no longer
    /// existed. Only a message still there after that wait is tapped. Each
    /// button's place is read from a snapshot, which a button that has gone
    /// meanwhile simply lacks: reading `frame` from one failed the test
    /// (main f833a6e, d46734a: the message cleared between the query and
    /// the read).
    private func dismissMessage(in app: XCUIApplication) {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "Dismiss message")).allElementsBoundByIndex
        let placed = buttons.compactMap { button in (try? button.snapshot()).map { (button: button, top: $0.frame.minY) } }
        guard let lowest = placed.max(by: { $0.top < $1.top })?.button else { return }
        if lowest.disappears(within: 8) { return }
        lowest.tap()
        XCTAssertTrue(lowest.disappears(within: 5), "The status message stayed over the list")
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
        guard app.dragUntilWhollyOnScreen(row, in: list, below: bar.exists ? bar.frame.maxY : nil) else {
            recordRouteUI("row never came into view", in: app)
            XCTFail("\(row) never lay wholly on screen")
            return
        }
    }

    private func tapMenuAction(_ button: XCUIElement, in app: XCUIApplication) {
        guard button.appears(within: 10) else {
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
extension XCUIElement {
    /// Whether the element exists within `timeout` seconds, as
    /// `waitForExistence(timeout:)` says, but at once when it is already
    /// there: XCTest's wait first looks a second after it starts. In the
    /// pull request runs of 2026-10-13 every one of a run's some 160 waits
    /// found its element at that first look: about 2.7 of the gate's 8.5
    /// minutes of tests (decision 199).
    func appears(within timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    /// Whether the element is gone within `timeout` seconds, at once when
    /// it already is: `waitForNonExistence(timeout:)` waits that first
    /// second too.
    func disappears(within timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }

    /// Whether the element can be touched within `timeout` seconds, looking
    /// every tenth of a second. An element that slides in, turns with the
    /// screen or is uncovered exists before it comes to rest, and
    /// `isHittable` asked at once answers for where it is on its way: the
    /// second `waitForExistence(timeout:)` waited before it looked used to
    /// hide that (PR #493's run 38360304931, the tutorial's Skip right after
    /// the phone turned).
    func becomesHittable(within timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(exists && isHittable) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    /// Waits until the element is hittable and in the same place twice in
    /// a row, a quarter of a second apart. Waiting for the app to idle does
    /// not wait for a turning layout or tools sliding in, and a tap found
    /// while they move lands where the element was (PR #326's runs: on the
    /// map beside the overview, and 5 pt left of the train tool).
    ///
    /// The frame must hold for half a second before `isHittable` is asked.
    /// A screen turned from one side to the other keeps every frame where
    /// it was in the app's own coordinates while the turn is still drawn:
    /// two frames a quarter of a second apart agreed, and `isHittable`
    /// asked mid-turn failed the test outright ("Activation point invalid";
    /// the tutorial's Skip on an iPad, main 2ec70b2's full lane, run
    /// 38720199489).
    func waitUntilSettled(timeout: TimeInterval = 5) {
        XCTAssertTrue(appears(within: timeout), "Missing \(self)")
        var last = frame
        var steady = 0
        for _ in 0..<Int(timeout * 4) {
            Thread.sleep(forTimeInterval: 0.25)
            let now = frame
            steady = now == last ? steady + 1 : 0
            if steady >= 2, isHittable { return }
            last = now
        }
        XCTFail("\(self) did not settle")
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
    /// leading margin beside the rows, so the drag starts on the list and
    /// not on the map or the dock beside it, nor on a row that is a
    /// control. A full-width Menu row (Add Stop Where It Fits) took the
    /// press of every drag begun on it and the list did not move: a branch
    /// run (38130205989) lost two drags to the app's stalls, so its fixed
    /// starting point fell on that row and the last 22 drags moved nothing.
    /// How far a `swipeUp()` flings a list depends on the synthesized
    /// event's timing; each drag here holds before lifting, so the list
    /// moves by the drag's length and does not fling.
    /// `below`: the bottom of a bar the list scrolls under, which the
    /// element must clear too. The Lines panel's list runs on under its
    /// navigation bar: a row "wholly on screen" there lay behind the bar,
    /// and the tap went to its one uncovered corner and opened no menu
    /// (main 2ec70b2's full lane, run 38720199489).
    func dragUntilWhollyOnScreen(_ element: XCUIElement, in list: XCUIElement? = nil, below: CGFloat? = nil) -> Bool {
        let area = list.map(\.frame) ?? frame
        let top = max(list == nil ? frame.minY + 140 : area.minY + 8, (below ?? -.infinity) + 8)
        let bottom = list == nil ? frame.maxY - 120 : area.maxY - 8
        // A form's rows are inset 16 pt from the list's sides.
        let x = list == nil ? area.midX : area.minX + 8
        // A panel beside the map on a phone on its side is short, and a
        // line's list there runs to some 23 screens (main's e48285f): long
        // drags until the row exists, then short ones that cannot carry it
        // past the band.
        for _ in 0..<(list == nil ? 16 : 40) {
            if element.exists {
                let place = element.frame
                if place.minY >= top, place.maxY <= bottom, element.isHittable { return true }
                // Above the band: move the list down. Each drag is shorter
                // than the band less a row, so a row cannot jump over it.
                if place.minY < top {
                    drag(in: area, at: x, from: 0.45, to: 0.65)
                    continue
                }
                drag(in: area, at: x, from: 0.75, to: 0.5)
            } else {
                drag(in: area, at: x, from: list == nil ? 0.75 : 0.9, to: list == nil ? 0.5 : 0.15)
            }
        }
        return false
    }

    /// Drags vertically down `area` at `x` between two heights given as
    /// fractions of it, and holds before lifting, so a list does not fling.
    private func drag(in area: CGRect, at x: CGFloat, from: CGFloat, to: CGFloat) {
        let origin = coordinate(withNormalizedOffset: .zero)
        let x = x - frame.minX
        let start = origin.withOffset(CGVector(dx: x, dy: area.minY - frame.minY + area.height * from))
        let end = origin.withOffset(CGVector(dx: x, dy: area.minY - frame.minY + area.height * to))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Scrolls the start screen's buttons until `button` can be tapped. A
    /// phone on its side shows them in a column of their own beside the
    /// title (decision 106): a `swipeUp()` at the middle of the screen
    /// lands on the edge between the two and may scroll the title instead.
    func bringStartButtonIntoView(_ button: XCUIElement) {
        guard button.appears(within: 10), !button.becomesHittable(within: 1) else { return }
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

    /// Scrolls `holder`, or whatever holds `button` (a scroll view, or a
    /// `List`'s collection view), until the middle of `button` shows in
    /// it; whether it does. Drags on the holder itself, not at the
    /// middle of the screen, which on a phone on its side is the edge
    /// between the start screen's title and its buttons, or the map beside
    /// a sheet's list. With the largest accessibility text one start
    /// screen button is taller than the band
    /// ``dragUntilWhollyOnScreen(_:in:)`` wants it wholly inside. A `List`
    /// makes its rows only as they come near, so a `holder` is dragged up
    /// with long drags until the row is there. Nothing here asks XCTest
    /// whether the button can be touched: of a start screen button
    /// scrolled partly into sight it failed the test, its middle on screen
    /// or not (runs 38335812150 and 38339333769), so ``tapMiddle(of:)``
    /// touches it. Slow swipes flung the start screen's column past the
    /// band every time, the button's middle below it and then above it
    /// for 20 swipes (main's full lane, run 38345123226): each drag here
    /// holds before lifting and is shorter than the band, so the middle
    /// cannot jump over it.
    func scrollUntilShown(_ button: XCUIElement, in holder: XCUIElement? = nil, drags: Int = 40) -> Bool {
        if holder == nil, !button.appears(within: 10) { return false }
        guard let holder = holder ?? [scrollViews, collectionViews, tables]
            .map({ $0.containing(.button, identifier: button.identifier).firstMatch })
            .first(where: \.exists) else {
            return button.exists && frame.contains(CGPoint(x: button.frame.midX, y: button.frame.midY))
        }
        _ = holder.appears(within: 10)
        let onScreen = holder.frame.intersection(frame)
        let area = onScreen.isEmpty ? holder.frame : onScreen
        // Clear of the holder's edges, where a navigation or home bar can
        // lie over it.
        let band = area.insetBy(dx: 0, dy: 24)
        func shown() -> Bool {
            button.exists && band.minY <= button.frame.midY && button.frame.midY <= band.maxY
        }
        for _ in 0..<drags where !shown() {
            if !button.exists {
                drag(in: area, at: area.midX, from: 0.85, to: 0.15)
            } else if button.frame.midY < band.minY {
                drag(in: area, at: area.midX, from: 0.35, to: 0.65)
            } else {
                drag(in: area, at: area.midX, from: 0.65, to: 0.35)
            }
        }
        return shown()
    }

    /// Touches the middle of `element`'s frame, once it is enabled.
    func tapMiddle(of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 15), .completed, "\(element) never became enabled", file: file, line: line)
        let place = element.frame
        coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: place.midX - frame.minX, dy: place.midY - frame.minY))
            .tap()
    }

    /// Opens one of the start screen's demos (decision 135): the Demo Map
    /// button, then `identifier`'s row in its sheet (`demo.realWorld`,
    /// `demo.highSpeed` or `demo.simple`) once it is enabled: the
    /// real-world demos wait for the real-world data, read in the
    /// background at launch.
    func openDemo(_ identifier: String, timeout: TimeInterval = 15) {
        let button = buttons["start.demoMap"]
        XCTAssertTrue(button.appears(within: 10), "Missing button: start.demoMap")
        bringStartButtonIntoView(button)
        button.tap()
        let demo = buttons[identifier]
        // A tap while the app is still busy after launch can be lost: one
        // accessibility query took 9 s, the tap was sent and the sheet never
        // opened (PR run 38208781302 on 8b08998, which changed no app code
        // and passed on its re-run). Tap again while the button is still
        // there to tap and the sheet is not.
        for _ in 0..<2 where !demo.appears(within: 10) && button.isHittable {
            button.tap()
        }
        XCTAssertTrue(demo.appears(within: 10), "Missing demo: \(identifier)")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: demo)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: timeout), .completed, "The demo never became enabled: \(identifier)")
        demo.tap()
    }
}
