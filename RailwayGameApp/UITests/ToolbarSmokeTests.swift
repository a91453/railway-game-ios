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
        app.chooseBlankMap()

        // Decision 114: Build opens the tools at the map's edge, and Done
        // closes them; so each is tapped in this order.
        for query in queries {
            let button = app.buttons[query]
            guard button.appears(within: 10) else {
                XCTFail("Missing toolbar button: \(query)")
                return
            }
            XCTAssertTrue(button.becomesHittable(), "Toolbar button cannot be tapped: \(query)")
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
        openLinesPanel(in: app)
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
        // Scrolled to, not only waited for: a list builds no row off screen,
        // and the summary sits under the switch, which can be the screen's
        // last row (main a2374a0's full lane, run 39722267769).
        let summary = app.staticTexts["lines.advanced.summary"]
        if !summary.appears(within: 10) { bringIntoView(summary, in: app) }
        XCTAssertTrue(summary.exists)
        XCTAssertFalse(app.buttons["line.route.-1.0.1"].exists)
        XCTAssertFalse(app.buttons["Split the Longest Band"].exists)
        setAdvanced(true, in: app)
        XCTAssertFalse(app.staticTexts["lines.advanced.summary"].exists)
        bringIntoView(app.buttons["line.route.-1.0.1"], in: app)
    }

    /// Pauses the game and opens the Lines panel, tapping again while it
    /// has not. On main 308c019's full lane (run 39676381575) the Pause tap
    /// found no hit point ({-1, -1}), the Simulator brought up Settings
    /// during the Lines tap, and the panel never opened: the test then
    /// dragged the map for the switch until its 8 minutes ran out. The
    /// runs before and after on the same code passed.
    private func openLinesPanel(in app: XCUIApplication) {
        let pause = app.buttons["Pause"].firstMatch
        let resume = app.buttons["Resume"].firstMatch
        XCTAssertTrue(pause.appears(within: 15))
        pause.waitUntilSettled()
        pause.tap()
        if !resume.appears(within: 5), pause.exists {
            pause.waitUntilSettled()
            pause.tap()
        }
        XCTAssertTrue(resume.appears(within: 5), "Pause must pause the game")
        let lines = app.buttons["Lines"].firstMatch
        let bar = app.navigationBars["Lines"].firstMatch
        XCTAssertTrue(lines.appears(within: 10))
        lines.waitUntilSettled()
        lines.tap()
        if !bar.appears(within: 10), lines.exists {
            lines.waitUntilSettled()
            lines.tap()
        }
        XCTAssertTrue(bar.appears(within: 10), "Lines must open the lines panel")
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
        let wanted = shown ? "1" : "0"
        // Up to three presses, each only while the switch still reads the
        // old value: main e6e8f5a's full lane (run 39781136910) pressed the
        // right point of the drawn switch, (759, 245) in {709, 231, 63, 28},
        // and the app's trace shows the touch begin and then be cancelled
        // 181 ms later, the main thread busy 186 ms meanwhile, so the switch
        // never turned; the same press in the test before ended in 58 ms
        // and turned it. A cancelled touch is no press at all, so it is
        // pressed again, as a finger would; the value is read first each
        // time, so a press that did turn it is never undone.
        for attempt in 1...3 {
            // Once the list has stopped: a tap on a list still moving after
            // the drags only stops it, and the switch, under the finger
            // 350 ms, did not turn (PR #659's run 38729482700 and run
            // 38863791023, the app's trace: both a second after a short
            // last drag; the five launches without one each turned it at
            // once).
            (control.exists ? control : toggle).waitUntilSettled()
            if control.exists {
                // A center tap landed on the iOS 26 switch's glass thumb but
                // left its value at 0 in full lane run 39094300227. Press
                // the destination side of the track, as a finger turning it
                // would.
                control.coordinate(withNormalizedOffset: CGVector(dx: shown ? 0.8 : 0.2, dy: 0.5)).tap()
            } else {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -42, dy: 0)).tap()
            }
            // Twenty seconds for the last press: as a job's first test, on
            // a cold Simulator with the real-world demo, one lookup took 10
            // to 20 seconds, and the switch's value was first read 17
            // seconds after the tap (run 38441429093); the same steps in
            // the next test took a second. A slow lookup only delays the
            // read below, which still sees a press that turned it.
            let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: toggle)
            if XCTWaiter.wait(for: [flipped], timeout: attempt < 3 ? 8 : 20) == .completed { return }
            if toggle.value as? String == wanted { return }
            recordRouteUI("Advanced switch still \(shown ? "off" : "on") after press \(attempt)", in: app)
        }
        XCTFail("The Advanced switch did not turn \(shown ? "on" : "off")")
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
        XCTAssertTrue(button.becomesHittable())
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

    /// Waits until the element's frame is the same twice in a row, a
    /// quarter of a second apart, for an element that is not itself a
    /// control (a card, a panel): what a fixed second's sleep used to wait
    /// for after something slid in.
    func waitUntilStill(timeout: TimeInterval = 5) {
        var last = frame
        for _ in 0..<Int(timeout * 4) {
            Thread.sleep(forTimeInterval: 0.25)
            let now = frame
            if now == last { return }
            last = now
        }
        XCTFail("\(self) did not stop moving")
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
    /// `drags`: how many drags before giving up, for a list longer than
    /// the default reaches.
    /// `clearOf`: a kind of control a drag must not start on, as the
    /// settings' volume sliders: a drag begun on one moved its slider, not
    /// the list, and every drag after began on it again (main fcf0697's
    /// full lane, run 40176501060: 24 drags at (437, 301) on the chimes
    /// slider). `at`: the x the drags run down instead, where a list's
    /// left edge is not its content (a sheet centred on a phone on its
    /// side, whose edge is the safe area: run 40208393295).
    func dragUntilWhollyOnScreen(_ element: XCUIElement, in list: XCUIElement? = nil, below: CGFloat? = nil, drags: Int? = nil,
                                 at column: CGFloat? = nil, clearOf controls: XCUIElement.ElementType? = nil) -> Bool {
        let area = list.map(\.frame) ?? frame
        let top = max(list == nil ? frame.minY + 140 : area.minY + 8, (below ?? -.infinity) + 8)
        let bottom = list == nil ? frame.maxY - 120 : area.maxY - 8
        // A form's rows are inset 16 pt from the list's sides.
        let x = column ?? (list == nil ? area.midX : area.minX + 8)
        // A panel beside the map on a phone on its side is short, and a
        // line's list there runs to some 23 screens (main's e48285f): long
        // drags until the row exists, then short ones that cannot carry it
        // past the band. The settings reached the report's attach switch
        // after 15 of 16 drags (main c4134e8's full lane), and a later run
        // lost 5 of its 16 to the list's bottom edge, where the touch fell
        // on the scroll edge's own view and nothing moved (main 27b1dde,
        // run 38773737363): 24 leaves room for both.
        for _ in 0..<(drags ?? (list == nil ? 24 : 40)) {
            if element.exists {
                let place = element.frame
                if place.minY >= top, place.maxY <= bottom, element.isHittable { return true }
                // Above the band: move the list down. Each drag is shorter
                // than the band less a row, so a row cannot jump over it.
                if place.minY < top {
                    drag(in: area, at: x, from: 0.45, to: 0.65, clearOf: controls)
                    continue
                }
                drag(in: area, at: x, from: 0.75, to: 0.5, clearOf: controls)
            } else {
                drag(in: area, at: x, from: list == nil ? 0.75 : 0.9, to: list == nil ? 0.5 : 0.15, clearOf: controls)
            }
        }
        return false
    }

    /// Drags vertically down `area` at `x` between two heights given as
    /// fractions of it, and holds before lifting, so a list does not fling.
    /// Both heights move together, a tenth of `area` at a time, until the
    /// drag starts clear of every control of the kind `controls`, read
    /// from one snapshot (a row the list drops between two reads would
    /// fail the second).
    private func drag(in area: CGRect, at x: CGFloat, from: CGFloat, to: CGFloat, clearOf controls: XCUIElement.ElementType? = nil) {
        var (from, to) = (from, to)
        if let controls, let tree = try? snapshot() {
            func controlFrames(in element: any XCUIElementSnapshot) -> [CGRect] {
                (element.elementType == controls ? [element.frame] : []) + element.children.flatMap(controlFrames(in:))
            }
            let frames = controlFrames(in: tree)
            let shifts: [CGFloat] = [0, 0.1, -0.1, 0.2, -0.2]
            let within: ClosedRange<CGFloat> = 0.05...0.95
            let shift = shifts.first { shift in
                let start = CGPoint(x: x, y: area.minY + area.height * (from + shift))
                return within.contains(min(from, to) + shift) && within.contains(max(from, to) + shift)
                    && !frames.contains { $0.insetBy(dx: -8, dy: -8).contains(start) }
            } ?? 0
            (from, to) = (from + shift, to + shift)
        }
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

    /// Decision 316: the start screen's New Game opens the new game's
    /// page; taps its blank map, which starts the game, once the page has
    /// slid up.
    func chooseBlankMap(file: StaticString = #filePath, line: UInt = #line) {
        let blank = buttons["newGame.blank"]
        XCTAssertTrue(blank.appears(within: 10), "Missing the new game's blank map", file: file, line: line)
        XCTAssertTrue(blank.becomesHittable(within: 5), "The new game's blank map cannot be tapped", file: file, line: line)
        blank.tap()
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
        // A `where !shown()` keeps querying for every remaining iteration
        // after the row is visible (about 63 s in run 38996792440).
        for _ in 0..<drags {
            if shown() { return true }
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

    /// Decision 303: under simple rules a new line's ✓ (or Create Line)
    /// raises the line's card, and its Open Line makes the line. Taps Open
    /// Line once the card is up; with `required` false, a game whose ✓
    /// makes the line at once (realistic rules) shows no card and nothing
    /// is tapped.
    func openNewLineFromItsCard(required: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let open = buttons["line.confirm.done"]
        guard open.appears(within: required ? 10 : 5) else {
            if required {
                let up = buttons["line.confirm.back"].exists
                XCTFail(up ? "The new line's card rose without Open Line" : "The new line's card did not rise", file: file, line: line)
            }
            return
        }
        XCTAssertTrue(open.becomesHittable(within: 10), "Open Line on the new line's card is covered", file: file, line: line)
        open.waitUntilSettled()
        open.tap()
        XCTAssertTrue(open.disappears(within: 10), "The new line's card stayed up", file: file, line: line)
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

/// TestFlight, 2026-10-16: the phone's tools column and the station card on
/// a phone held sideways, at the largest text the app takes
/// (`dynamicTypeSize(...xxxLarge)`), where they were squeezed. In the full
/// lane (decision 199).
@MainActor
final class ShellLayoutUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            // Straight into the demo: at this size the start screen's Demo
            // Map button has no activation point XCTest can ask about (the
            // first run, 38844484023).
            "-ui-testing", "-demo-layout", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
        ] + extra
        app.launch()
        return app
    }

    /// Every button of the column one size, chosen or not, looking at the
    /// map and while building; and the column a gap below the layer strip.
    func testTheToolsColumnsButtonsAreOneSize() {
        continueAfterFailure = false
        let app = launch()
        defer { app.terminate() }
        let toggle = app.buttons["controls.toggle"]
        toggle.waitUntilSettled(timeout: 15)
        let more = app.buttons["map.quickLayer.more"]
        XCTAssertTrue(more.appears(within: 10))
        assertOneSize(["controls.toggle", "entry.economy", "entry.lines", "dock.build"], in: app, while: "looking at the map")
        // The strip's glass ends 3 points under its buttons, the column's 4
        // above its first; between them the screen's gap of 10, as from the
        // board to the strip.
        XCTAssertGreaterThanOrEqual(toggle.frame.minY - more.frame.maxY, 3 + 10 + 4 - 0.5,
                                    "The column stops a gap below the layer strip: toggle \(toggle.frame), strip \(more.frame)")

        let build = app.buttons["dock.build"]
        build.tap()
        app.buttons["tool.select"].waitUntilSettled(timeout: 10)
        assertOneSize(["controls.toggle", "tool.network", "tool.train", "tool.building", "tool.select", "dock.build"],
                      in: app, while: "building")
    }

    private func assertOneSize(_ identifiers: [String], in app: XCUIApplication, while state: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let frames = identifiers.map { id -> (String, CGRect) in
            let button = app.buttons[id]
            XCTAssertTrue(button.appears(within: 10), "Missing \(id) \(state)", file: file, line: line)
            return (id, button.frame)
        }
        guard let first = frames.first?.1 else { return }
        // 66.1's width (TestFlight 67.1 beside 66.1, ``ToolColumn``).
        XCTAssertEqual(first.width, 48, accuracy: 0.5, "The column's buttons are 48 points wide \(state): \(frames)", file: file, line: line)
        for (id, frame) in frames {
            XCTAssertEqual(frame.width, first.width, accuracy: 0.5, "\(id) is as wide as the toggle \(state): \(frames)", file: file, line: line)
            XCTAssertEqual(frame.height, first.height, accuracy: 0.5, "\(id) is as tall as the toggle \(state): \(frames)", file: file, line: line)
            XCTAssertEqual(frame.midX, first.midX, accuracy: 0.5, "\(id) lines up with the toggle \(state): \(frames)", file: file, line: line)
        }
    }

    /// Decision 251: the status bar keeps one width while the days go by
    /// and the game is paused and resumed, at the largest text: the menu
    /// button and the date stay where they are (on main the date's width
    /// changed from day to day, a holiday added its name and pausing added
    /// a dot, and near a layout's edge the bar changed its layout).
    func testTheStatusBarKeepsItsWidthAsTheDaysGoBy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            // Two minutes before midnight, so the first day goes by at once.
            "-ui-testing", "-demo-layout", "-demo-at", "23:58", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
        ]
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["hud.menu"]
        let time = app.buttons["hud.time"]
        // The demo runs on to 23:58 before the map opens.
        menu.waitUntilSettled(timeout: 60)
        XCTAssertTrue(time.appears(within: 10))
        // The fastest speed: a day in about 15 seconds where the device
        // keeps up.
        let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed")).firstMatch
        XCTAssertTrue(speed.appears(within: 10))
        speed.tap()
        let fast = app.buttons["6000 times real time, fast forward"]
        // The menu's rows exist before the menu has opened: tapped then,
        // the row had no hit point ({inf, inf}; main 96c39095's nightly
        // full lane, run 40232525406).
        XCTAssertTrue(fast.becomesHittable(within: 10))
        fast.tap()
        XCTAssertTrue(fast.disappears(within: 10))
        menu.waitUntilSettled()
        let start = (menu: menu.frame, time: time.frame, label: time.label)
        func same(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
        }
        var labels: Set<String> = []
        // Opened at 23:58, the next date comes at once; then watched for 20
        // seconds of the new day (the Simulator keeps up with about a day
        // and a half in 50: run 38866488755 saw two dates, the by-hand run
        // 38888496446 at 23:58 never a third).
        let watched = Date().addingTimeInterval(20)
        let deadline = Date().addingTimeInterval(50)
        while Date() < deadline, labels.count < 2 || Date() < watched {
            Thread.sleep(forTimeInterval: 0.5)
            guard let menuNow = try? menu.snapshot().frame, let timeNow = try? time.snapshot() else { continue }
            labels.insert(String(timeNow.label.prefix(while: { $0 != ")" })))
            XCTAssertTrue(same(menuNow, start.menu), "The menu button moved as the days went by: \(start.menu) then \(menuNow), \(timeNow.label)")
            XCTAssertEqual(timeNow.frame.width, start.time.width, accuracy: 0.5, "The date changed its width: \(start.label) then \(timeNow.label)")
        }
        // The Simulator keeps up with about a day and a half of it (run
        // 38866488755: Jan 1 to Jan 2).
        XCTAssertGreaterThanOrEqual(labels.count, 2, "No day went by: \(labels.sorted())")
        // Pausing and resuming move nothing either.
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.appears(within: 5))
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].appears(within: 5))
        XCTAssertTrue(same(menu.frame, start.menu), "Pausing moved the menu button: \(menu.frame)")
        app.buttons["Resume"].tap()
        XCTAssertTrue(pause.appears(within: 5))
        XCTAssertTrue(same(menu.frame, start.menu), "Resuming moved the menu button: \(menu.frame)")
    }

    /// The station's board in the panel beside the map: each train in two
    /// lines, its time and minutes never broken a character a line (the
    /// TestFlight report: "1／2:／5／5", "17／分").
    func testTheStationBoardsTimesKeepToOneLine() {
        continueAfterFailure = false
        // The demo opens at midnight; its trains set off at 06:00 and only
        // then come on the board. Waiting for the clock found none due at
        // 05:19, 07:20 and 16:07 (runs 38866705071, 38873835534,
        // 38861445072): the demo opens run on to 07:00 instead, paused, when
        // every station's board lists trains (DemoAtTests).
        let app = launch(["-demo-at", "07:00", "-ui-testing-paused"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        // The demo runs on to 07:00 before the map opens.
        XCTAssertTrue(map.appears(within: 60))
        // As MapInteractionTests' hold: the station nearest the middle once
        // the stations stand still.
        let stations = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(stations.appears(within: 10))
        func places() -> [CGPoint] {
            ((stations.value as? String) ?? "").split(separator: ";").compactMap { pair in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
        }
        var last = places()
        let settle = Date().addingTimeInterval(10)
        while Date() < settle {
            Thread.sleep(forTimeInterval: 0.5)
            let now = places()
            if !now.isEmpty, now == last { break }
            last = now
        }
        let middle = CGPoint(x: map.frame.width / 2, y: map.frame.height / 2)
        guard let central = last.min(by: { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }) else {
            XCTFail("The demo has stations")
            return
        }
        let clock = app.descendants(matching: .any)["hud.time"].firstMatch
        XCTAssertTrue(clock.appears(within: 10))
        XCTAssertTrue((try? clock.snapshot().label)?.contains("07:00") ?? false, "Paused at 07:00: \(String(describing: try? clock.snapshot().label))")
        // The board's own identifier is carried by every row under it, so
        // each train is found by its time and its minutes, which keep theirs
        // (the fifth run's hierarchy: rows read "station.board").
        let time = app.staticTexts.matching(identifier: "station.board.row.time").firstMatch
        // The panel's list, beside the map on the trailing side, once it has
        // slid in (the first run looked at once and found none). With the
        // clock running, a hold was once taken for a tap: it picked the
        // station and showed its tag, and no panel came (run 38848806364).
        // So it holds again, up to three times (the clock is paused now).
        var list: XCUIElement?
        for _ in 0..<3 where list == nil {
            map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: central.x, dy: central.y)).press(forDuration: 1.2)
            let opened = Date().addingTimeInterval(5)
            repeat {
                list = app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.frame.minX > app.frame.midX }
                if list == nil { Thread.sleep(forTimeInterval: 0.25) }
            } while list == nil && Date() < opened
        }
        func attach(_ name: String) {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        if list == nil { attach("No station panel after the hold") }
        XCTAssertNotNil(list, "The hold opens the station's panel")
        let board = app.buttons["station.board"].firstMatch
        let boardShown = app.dragUntilWhollyOnScreen(board, in: list)
        if !boardShown { attach("No board in the station's panel") }
        XCTAssertTrue(boardShown, "The station's panel has its board")
        // Its trains lie under its head and the way they go, which can be
        // all the panel shows of it (the eighth run: the head and "往 西站"
        // at the panel's foot, the trains below not yet made). One slow drag
        // brings the head up to the panel's top, the trains under it.
        if let list, boardShown, board.frame.minY > list.frame.minY + 80 {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = list.frame.minX + 8 - app.frame.minX
            let from = origin.withOffset(CGVector(dx: x, dy: board.frame.minY - app.frame.minY))
            let to = origin.withOffset(CGVector(dx: x, dy: list.frame.minY + 40 - app.frame.minY))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        // The clock is paused at 07:00, when every station's board lists
        // trains (DemoAtTests): the rows only have to be drawn. A row once
        // showed for a moment and was gone at the next look (#712), so one
        // sighting counts.
        var listed = false
        let due = Date().addingTimeInterval(5)
        repeat {
            if time.exists {
                listed = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < due
        // Not dragged into view: a label inside a row read as one is never
        // hittable, and the drag would hunt for it (the sixth run). The
        // board's head is in view, and its first trains under it.
        if !listed { attach("No train on the station's board") }
        XCTAssertTrue(listed, "The board lists a train")
        // A time or a count of minutes on one line is wider than tall and a
        // line high (some 22 and 25 points at this size); broken a character
        // a line, "1／2:／5／5" stood four lines high.
        let times = app.staticTexts.matching(identifier: "station.board.row.time").allElementsBoundByIndex
        let aways = app.staticTexts.matching(identifier: "station.board.row.away").allElementsBoundByIndex
        // Their frames are laid out whether or not the list shows them yet.
        XCTAssertFalse(times.isEmpty)
        for label in times + aways where label.exists && label.frame.height > 0 {
            XCTAssertLessThan(label.frame.height, 40, "\(label.label) keeps to one line: \(label.frame)")
            XCTAssertGreaterThan(label.frame.width, label.frame.height, "\(label.label) keeps to one line: \(label.frame)")
        }
    }
}
