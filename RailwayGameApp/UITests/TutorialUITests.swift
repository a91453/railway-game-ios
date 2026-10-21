import XCTest

/// Exercises the CX-5 card against the tutorial's steps (C5, redone by
/// decision 188: Build, the map, a stretch of track; the line
/// steps from `-tutorial-step`). Gameplay goals are tested in
/// TutorialSessionTests; these checks prove the overlay passes touches
/// through to the tool, observes completion and exposes its navigation.
@MainActor
final class TutorialUITests: XCTestCase {
    func testEnglishTutorialNavigation() {
        checkNavigation(language: "en", locale: "en_US", tutorialLabel: "Tutorial", lessonsLabel: "Lessons", nextLabel: "Next", backLabel: "Back", skipLabel: "Skip")
    }

    func testTraditionalChineseTutorialNavigation() {
        checkNavigation(language: "zh-Hant", locale: "zh_TW", tutorialLabel: "教學", lessonsLabel: "入門", nextLabel: "下一步", backLabel: "上一步", skipLabel: "略過")
    }

    func testLargeTextTutorialNavigation() {
        checkNavigation(language: "en", locale: "en_US", tutorialLabel: "Tutorial", lessonsLabel: "Lessons", nextLabel: "Next", backLabel: "Back", skipLabel: "Skip", largeText: true)
    }

    /// The tutorial's track chapter (decision 188; the name is kept for
    /// ios-build.yml's gate list): the network tool, zooming out, the two
    /// ends of a stretch and the map's ✓, each step moving on by itself,
    /// then the platform step, whose control the card leaves free, and Skip.
    func testBuildingTrackEnablesNextAndSkipEnds() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        startFirstLesson(app)
        openCard(app)
        let next = app.buttons["tutorial.next"]
        XCTAssertTrue(next.appears(within: 10))
        // Decision 226, later: Build, as in the game, opens the tools with
        // Network chosen.
        checkToolIsUncovered(app, identifier: "dock.build")
        selectTool(app, "dock.build")
        XCTAssertTrue(app.buttons["tool.network"].isSelected)

        // Stage E1: zooming out moves the map; the card leaves the zoom
        // buttons free.
        waitForStep(app, title: "Zoom out to see the town")
        // Folded from the second step: open it, for the rest of the chapter.
        openCard(app)
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomOut.appears(within: 10))
        XCTAssertTrue(zoomOut.becomesHittable())
        if card.exists {
            XCTAssertFalse(card.frame.intersects(zoomOut.frame), "The tutorial card covers the zoom buttons")
        }
        zoomOut.tap()
        waitForStep(app, title: "Tap the start, then the end")

        // Tap the map where the card leaves it free: the card may sit on
        // the map (it may cover part of it, never a control).
        let map = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Map,")).firstMatch
        XCTAssertTrue(map.appears(within: 10))
        XCTAssertTrue(card.appears(within: 10))
        // The map runs up under the status pill, which floats over its
        // top: only the map below the pill can be tapped.
        let gameTime = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Game time")).firstMatch
        let hudBottom = max(app.buttons["hud.menu"].frame.maxY, gameTime.frame.maxY) + 12
        // The dock floats over the map's bottom (decision 106; on a phone
        // Build is the foot of the tools column): only the map above it can
        // be tapped too. The building tools run down the map's leading edge
        // (decision 114): only the map beside them.
        let dockTop = app.buttons["dock.build"].frame.minY - 12
        let railEnd = app.buttons["tool.select"].frame.maxX + 12
        let wholeMap = map.frame.intersection(app.frame)
        let visibleMap = wholeMap
            .divided(atDistance: max(0, hudBottom - wholeMap.minY), from: .minYEdge).remainder
            .divided(atDistance: max(0, wholeMap.maxY - dockTop), from: .maxYEdge).remainder
            .divided(atDistance: max(0, railEnd - wholeMap.minX), from: .minXEdge).remainder
        // Two points far enough apart for 160 m of track once zoomed out
        // (about 1 m a point on a phone, 220 points), clear of the card (which grows by
        // a line of hint after the first tap), the Map Layers button, the
        // zoom buttons and, on an iPad, the details card at the trailing
        // side, where the Build Track button is (decision 106).
        let layers = app.buttons["map.layers"]
        let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Build Track")).firstMatch
        var covered = [card.frame.insetBy(dx: 0, dy: -50), zoomOut.frame, app.buttons["Zoom in"].frame]
        if layers.exists { covered.append(layers.frame) }
        let free = action.exists
            ? visibleMap.divided(atDistance: max(0, visibleMap.maxX - (action.frame.minX - 20)), from: .maxXEdge).remainder
            : visibleMap
        // The widest gap that fits: the map may open closer on an iPad.
        let gaps: [CGFloat] = [400, 300, 220]
        guard let points = gaps.lazy.compactMap({ self.freePoints(in: free, avoiding: covered, gap: $0) }).first else {
            return XCTFail("No free place on the map: map \(visibleMap), free \(free), card \(card.frame), layers \(layers.frame), action \(action.frame)")
        }
        let (first, second) = points
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: first.x, dy: first.y)).tap()
        origin.withOffset(CGVector(dx: second.x, dy: second.y)).tap()

        // The map's ✓ builds it: the card leaves it free.
        waitForStep(app, title: "Tap ✓ to build the track", "taps \(first), \(second); card \(card.frame), free \(free)")
        let confirm = app.buttons["map.build.confirm"]
        XCTAssertTrue(confirm.appears(within: 10))
        XCTAssertTrue(confirm.becomesHittable(), "The ✓ cannot be tapped")
        if card.exists {
            XCTAssertFalse(card.frame.intersects(confirm.frame), "The tutorial card covers the ✓: card \(card.frame), ✓ \(confirm.frame)")
        }
        confirm.tap()
        // A press can be dropped on a loaded runner (run 37554617441: the
        // button highlighted, its action never ran): tap once more only
        // while it is still there, as nothing was built.
        if !confirm.disappears(within: 10), confirm.isEnabled {
            confirm.tap()
        }

        // The station chapter: the details card opens for the modes.
        waitForStep(app, title: "Tap Platform", "The ✓ did not build the track")
        let platform = app.buttons["Platform"]
        XCTAssertTrue(platform.appears(within: 10))
        XCTAssertTrue(platform.becomesHittable(), "The Platform mode cannot be tapped")
        if card.exists {
            XCTAssertFalse(card.frame.intersects(platform.frame), "The tutorial card covers the Platform mode")
        }
        // A new chapter: the card is folded again.
        openCard(app)
        waitForEnabled(app, false, "The platform step waits for the mode")
        XCTAssertTrue(app.buttons["tutorial.back"].exists)
        app.buttons["tutorial.skip"].tap()
        // The card may still be closing right after Skip: wait for it to go.
        XCTAssertTrue(next.disappears(within: 10), "Skip did not close the tutorial")
        XCTAssertTrue(app.buttons["tool.network"].becomesHittable())
    }

    /// The line step on a phone on its side (the owner's device, 2026-10-12):
    /// the card stood over the lines panel and Pick on Map could not be
    /// tapped. Started at the line chapter over the track and stations the
    /// steps before it build (`-tutorial-step`), opening Lines starts
    /// picking by itself and the step moves on; the card, open or folded by
    /// itself, leaves Pick on Map uncovered, and folds and opens again.
    func testTheLineStepLeavesTheLinesPanelUsable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-tutorial-step", "line.open"]
        app.launch()
        defer { app.terminate() }
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        let folded = app.buttons["tutorial.unfold"]
        XCTAssertTrue(waitForCard(card, or: folded), "No tutorial card at the line step")

        let lines = app.buttons["entry.lines"]
        XCTAssertTrue(lines.appears(within: 10))
        XCTAssertTrue(lines.becomesHittable(), "The Lines button is covered")
        lines.tap()
        let pick = app.buttons["line.draft.pick"]
        XCTAssertTrue(pick.appears(within: 10), "The lines panel did not open")
        // Picking starts by itself; Pick on Map is not tapped.
        let stop = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "line.draft.pick", "Stop Picking")).firstMatch
        XCTAssertTrue(stop.appears(within: 10), "Picking did not start by itself")
        waitForStep(app, title: "Tap one station, then the other")
        XCTAssertFalse(app.buttons["map.build.confirm"].exists, "A ✓ is left over")

        // The card settles after the panel slides in.
        pick.waitUntilSettled()
        if card.exists { card.waitUntilStill() }
        if folded.exists { folded.waitUntilStill() }
        if card.exists {
            XCTAssertFalse(card.frame.intersects(pick.frame), "The tutorial card covers Pick on Map: card \(card.frame), button \(pick.frame)")
        }
        if folded.exists {
            XCTAssertFalse(folded.frame.intersects(pick.frame), "The folded card covers Pick on Map: \(folded.frame), button \(pick.frame)")
        }
        XCTAssertTrue(pick.isHittable, "Pick on Map cannot be tapped")

        // The player can always fold the card out of the way, and open it.
        if card.exists {
            app.buttons["tutorial.fold"].tap()
            XCTAssertTrue(folded.appears(within: 10), "The card did not fold")
        }
        XCTAssertTrue(folded.becomesHittable())
        folded.tap()
        XCTAssertTrue(card.appears(within: 10), "The folded card did not open")
        XCTAssertTrue(app.buttons["tutorial.skip"].becomesHittable())
        XCTAssertFalse(app.buttons["tutorial.next"].isEnabled, "The stations are still to pick")
    }

    /// Decision 188 (full lane and iPad, not the gate): the ✓ on the map
    /// creates the line (decision 100, later); lesson 1's line opens with
    /// its trains (decisions 264 and 266, the name kept from when the lines
    /// panel's Buy … and Start Service came next), so the panel closes and
    /// the fares are waited for.
    func testCreateLineAndBuyAreInReach() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-tutorial-step", "line.create"]
        app.launch()
        defer { app.terminate() }
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        let folded = app.buttons["tutorial.unfold"]
        XCTAssertTrue(waitForCard(card, or: folded), "No tutorial card at the line step")

        // The step opens the lines panel itself; the ✓ beside the last
        // station picked creates the line.
        XCTAssertTrue(app.buttons["line.draft.pick"].appears(within: 10), "The lines panel did not open")
        let create = app.buttons["map.build.confirm"]
        XCTAssertTrue(create.appears(within: 10), "No ✓ on the map")
        XCTAssertTrue(waitForHittable(create), "The ✓ on the map cannot be tapped")
        create.waitUntilSettled()
        if card.exists { card.waitUntilStill() }
        if card.exists {
            XCTAssertFalse(card.frame.intersects(create.frame), "The tutorial card covers the ✓")
        }
        create.tap()
        app.openNewLineFromItsCard()

        // Decision 226, later: Done came before the line, and set time
        // running, so the time step is passed over and the panel closes.
        waitForStep(app, title: "Wait for your first fares")
        XCTAssertTrue(app.buttons["line.draft.pick"].disappears(within: 10), "The lines panel stayed open")
    }

    /// TestFlight 55.1: a data layer left on from the last game (the
    /// demand change, its legend at the trailing side) stood where the
    /// tutorial's steps are. The game opens with the layer on, and starting
    /// the tutorial from the game menu takes it away.
    func testTheTutorialStartsWithoutADataLayer() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-demo-layout", "-map-layer", "movement", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        defer { app.terminate() }
        let legend = app.descendants(matching: .any).matching(identifier: "map.populationLegend").firstMatch
        XCTAssertTrue(legend.appears(within: 15), "The demand change layer was not on before the tutorial")

        // Pause through the real HUD, as checkNavigation, so a running clock
        // does not rebuild the menu while XCTest targets it.
        hittableButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause"))).tap()
        app.buttons["Game menu"].tap()
        hittableButton(app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "menu.tutorial", "Tutorial"))).tap()
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        XCTAssertTrue(waitForCard(card, or: app.buttons["tutorial.unfold"]), "The tutorial did not start")
        XCTAssertTrue(legend.disappears(within: 10), "The data layer is still on in the tutorial")
    }

    /// Waits up to 10 seconds for `element` to be hittable.
    private func waitForHittable(_ element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if element.exists, element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return element.exists && element.isHittable
    }

    /// Waits up to 10 seconds for the step titled `title`, on the card or
    /// its folded pill ("Show Tutorial: <title>").
    private func waitForStep(
        _ app: XCUIApplication, title: String, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let heading = app.staticTexts["tutorial.title"].firstMatch
        let folded = app.buttons["tutorial.unfold"].firstMatch
        // Each is read from a snapshot, nil when it is gone: the second step
        // folds the first step's card, and one that folded between `exists`
        // and `label` failed the label's lookup.
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if (try? heading.snapshot())?.label == title { return }
            if (try? folded.snapshot())?.label.hasSuffix(title) == true { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        let shown = (try? heading.snapshot())?.label ?? (try? folded.snapshot())?.label ?? "no card"
        XCTFail("Timed out waiting for the step “\(title)”; showing “\(shown)”. \(message)", file: file, line: line)
    }

    /// Opens the tutorial's card, folded from the second step (decision
    /// 188, later fix), as the player does to read the step and reach Back,
    /// Next and Skip; an open card is left as it is.
    /// Decision 266: the start screen's Lessons, then lesson 1, whose
    /// guide is the tutorial's first part.
    private func startFirstLesson(_ app: XCUIApplication, label: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let lessons = app.buttons["start.lessons"]
        XCTAssertTrue(lessons.appears(within: 10), "No Lessons on the start screen", file: file, line: line)
        if let label {
            XCTAssertTrue(lessons.label.contains(label), "Lessons reads \(lessons.label)", file: file, line: line)
        }
        lessons.tap()
        let first = app.buttons["lesson.1.start"]
        XCTAssertTrue(first.appears(within: 10), "No lesson 1 in the list", file: file, line: line)
        XCTAssertTrue(first.becomesHittable(), "Lesson 1's Start cannot be tapped", file: file, line: line)
        first.tap()
    }

    private func openCard(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        let folded = app.buttons["tutorial.unfold"]
        XCTAssertTrue(waitForCard(card, or: folded), "No tutorial card", file: file, line: line)
        if !card.exists {
            // One tap: the pill opens the card as the finger comes down, so
            // a touch on it as a done step moves on still opens it
            // (``testATouchHeldOnTheFoldedCardAsTheStepMovesOnOpensIt``).
            folded.waitUntilSettled()
            folded.tap()
            XCTAssertTrue(card.appears(within: 10), "The folded card did not open", file: file, line: line)
        }
    }

    /// A touch on the folded card as a done step moves on opens the card.
    /// The card is made anew for each step, and the next step's pill
    /// stands elsewhere: a touch that began on the pill was cancelled as the
    /// step moved on, and the card did not open (main 6e86506's full lane,
    /// run 38709237236, the app's trace: cancelled 170 ms after it began).
    /// Here the step waits eight seconds before it moves on
    /// (`-tutorial-advance-ms`), and a press of twelve seconds, begun
    /// before, is held across it; the next step's card is open. Four and
    /// six were too short: the press began 4.4 s after Zoom out, when the
    /// pill had already moved, and fell on the map (main 01e3c9a's full
    /// lane, run 39546432319, the app's trace).
    func testATouchHeldOnTheFoldedCardAsTheStepMovesOnOpensIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-tutorial-step", "map.move", "-tutorial-advance-ms", "8000",
        ]
        app.launch()
        defer { app.terminate() }
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        let folded = app.buttons["tutorial.unfold"]
        XCTAssertTrue(folded.appears(within: 20), "No folded card at the map step")
        folded.waitUntilSettled()
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomOut.becomesHittable())
        let before = folded.frame
        // Done: the step moves on eight seconds from now.
        zoomOut.tap()
        XCTAssertTrue(folded.label.contains("Zoom out to see the town"), "The step moved on before the touch: \(folded.label)")
        // Near the pill's leading end, by the station master, which stays
        // where it is whatever the next step's title.
        folded.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 12)
        let progress = app.staticTexts.matching(identifier: "tutorial.progress").firstMatch
        XCTAssertTrue(
            card.appears(within: 5),
            "The touch held across the step moving on did not open the card (pill \(before) then \(folded.exists ? "\(folded.frame) \(folded.label)" : "gone"))"
        )
        XCTAssertTrue(progress.label.hasPrefix("Step 3 of"), "Not the next step: \(progress.label)")
    }

    /// Waits up to 15 seconds for the tutorial's card, open or folded.
    private func waitForCard(_ card: XCUIElement, or folded: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if card.exists || folded.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return card.exists || folded.exists
    }

    private func checkNavigation(
        language: String, locale: String, tutorialLabel: String, lessonsLabel: String, nextLabel: String, backLabel: String, skipLabel: String, largeText: Bool = false
    ) {
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

        startFirstLesson(app, label: lessonsLabel)
        openCard(app)

        let next = app.buttons["tutorial.next"]
        let back = app.buttons["tutorial.back"]
        let skip = app.buttons["tutorial.skip"]
        XCTAssertTrue(next.appears(within: 10))
        XCTAssertEqual(next.label, nextLabel)
        XCTAssertEqual(skip.label, skipLabel)
        waitForEnabled(app, false, "The first step waits for the network tool")
        XCTAssertFalse(back.exists, "The first step has no Back button")
        // Decision 226, later: the game's own tools; the building tools
        // show only once Build is tapped.
        XCTAssertFalse(app.buttons["tool.network"].exists, "The building tools are out before Build")

        // The outlined button must receive the touch underneath the overlay.
        checkToolIsUncovered(app, identifier: "dock.build")
        // Through selectTool, as the later taps: a single synthesized touch
        // can be lost (run 37797595561 left Next disabled after one tap on
        // an uncovered network tool, in Traditional Chinese on the iPad).
        selectTool(app, "dock.build")
        // Decision 188: the done step moves on by itself, and the map step
        // waits for the map to move. From the second step the card starts
        // folded (decision 188, later fix): open it for Back.
        XCTAssertTrue(app.buttons["tutorial.unfold"].appears(within: 10), "The done step did not move on by itself")
        openCard(app)
        XCTAssertTrue(back.appears(within: 10))
        XCTAssertEqual(back.label, backLabel)
        waitForEnabled(app, false)
        back.tap()
        XCTAssertTrue(back.disappears(within: 10))
        waitForEnabled(app, true)
        XCTAssertTrue(app.buttons["tool.network"].isSelected)
        // Reached by Back, the done step waits for Next. A slow runner can
        // only miss a step that moves on, not fail here wrongly.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(back.exists, "A step reached by Back moved on by itself")
        checkToolIsUncovered(app, identifier: "tool.select")
        putToolsAway(app)
        waitForEnabled(app, false)
        selectTool(app, "dock.build")
        waitForEnabled(app, true)
        XCTAssertFalse(back.exists, "A step reached by Back moved on by itself")

        // Reflowing the card must preserve navigation and usable controls.
        // A phone turns from one side to the other (decision 106: it
        // plays only on its side); an iPad from upright to its side.
        XCUIDevice.shared.orientation = .landscapeRight
        // The card turns with the screen: Skip is there before it comes to
        // rest (PR #493's run 38360304931 asked at once and found it out of
        // reach), so wait until it stands still and can be touched.
        skip.waitUntilSettled(timeout: 10)
        checkToolIsUncovered(app, identifier: "tool.network")
        checkToolIsUncovered(app, identifier: "tool.select")
        putToolsAway(app)
        waitForEnabled(app, false)
        checkToolIsUncovered(app, identifier: "dock.build")
        selectTool(app, "dock.build")
        waitForEnabled(app, true)
        skip.tap()
        // The card may still be closing right after Skip: wait for it to go.
        XCTAssertTrue(next.disappears(within: 10), "Skip did not close the tutorial")
        // The restarted tutorial's first step waits for Network again.
        // Decision 114: the tools show only while one is chosen, so Done
        // closes them rather than staying selected.
        putToolsAway(app)

        // The game menu starts the tutorial again without leaving this game:
        // the skipped tutorial is offered at its step, or from the start
        // (decision 188, later fix).
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
        let resume = app.buttons["menu.tutorial.resume"]
        XCTAssertTrue(resume.appears(within: 10), "The skipped tutorial is not offered to continue")
        XCTAssertTrue(resume.label.contains(language == "en" ? "Step 1" : "第 1 步"), resume.label)
        hittableButton(app.buttons.matching(identifier: "menu.tutorial.restart")).tap()
        openCard(app)
        XCTAssertTrue(next.appears(within: 10))
        XCTAssertFalse(back.exists)
        waitForEnabled(app, false)
        skip.tap()
        // The card may still be closing right after Skip: wait for it to go.
        XCTAssertTrue(next.disappears(within: 10), "Skip did not close the tutorial")
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

    /// Two points of `map` `gap` points apart in a row, each at least 12
    /// points inside it and clear of every frame in `covered` by 12: the
    /// first such pair, top row first, leading first.
    private func freePoints(in map: CGRect, avoiding covered: [CGRect], gap: CGFloat) -> (CGPoint, CGPoint)? {
        let blocked = covered.map { $0.insetBy(dx: -12, dy: -12) }
        func isFree(_ point: CGPoint) -> Bool {
            map.insetBy(dx: 12, dy: 12).contains(point) && !blocked.contains { $0.contains(point) }
        }
        var y = map.minY + 12
        while y <= map.maxY - 12 {
            var x = map.minX + 12
            while x + gap <= map.maxX - 12 {
                let first = CGPoint(x: x, y: y), second = CGPoint(x: x + gap, y: y)
                if isFree(first), isFree(second) { return (first, second) }
                x += 4
            }
            y += 8
        }
        return nil
    }

    /// Taps Done until the building tools are put away, at most twice (a
    /// touch can be lost, as in ``selectTool(_:_:file:line:)``): they show
    /// only while a tool is chosen (decision 114), the tutorial too since
    /// decision 226's later change, so Done is not left selected.
    private func putToolsAway(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let done = app.buttons["tool.select"]
        for _ in 0..<2 where done.exists {
            done.tap()
            if done.disappears(within: 5) { return }
        }
        XCTAssertFalse(done.exists, "Done did not put the tools away", file: file, line: line)
    }

    private func checkToolIsUncovered(_ app: XCUIApplication, identifier: String) {
        let tool = app.buttons[identifier]
        let card = app.descendants(matching: .any).matching(identifier: "tutorial.card").firstMatch
        XCTAssertTrue(tool.appears(within: 10))
        XCTAssertTrue(card.appears(within: 10))
        XCTAssertTrue(tool.becomesHittable())
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
        let deadline = Date().addingTimeInterval(10)
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
        let diagnostics = "Timed out after 10 seconds waiting for \(buttonDescription) isEnabled=\(enabled); found \(buttons.count) matching buttons: [\(states)]. \(message)"
        let hierarchy = XCTAttachment(string: "\(diagnostics)\n\n\(app.debugDescription)")
        hierarchy.name = "waitForEnabled-\(buttonDescription)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(diagnostics, file: file, line: line)
    }
}
