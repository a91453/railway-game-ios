import XCTest

@MainActor
final class StartSaveFlowSmokeTests: XCTestCase {
    func testEnglishStartSaveFlow() {
        checkFlow(language: "en", locale: "en_US")
    }

    func testTraditionalChineseStartSaveFlow() {
        checkFlow(language: "zh-Hant", locale: "zh_TW")
    }

    /// City building P0-A (decision 92): on a blank map, choose the house,
    /// tap the ground, see it built, save, go back to the start and
    /// continue: the house is still there.
    func testAHouseBuiltOnABlankMapIsKeptBySavingAndContinuing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        requiredButton("start.newGame", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        requiredButton("tool.building", in: app).tap()
        requiredButton("building.kind.house", in: app).tap()
        let count = app.staticTexts["building.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), "Missing the building count")
        XCTAssertEqual(count.label, "0 buildings placed")

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        // Decision 95: a tap chooses the site, which enables the action
        // button; the button builds. A touch held across a slow
        // accessibility query is failed by the tap recognizer
        // (MapInteractionTests), so a lost tap is tried once more. The
        // count says whether it was built, not the "Built house #1 …"
        // banner: a success clears itself after 4 s, within one slow
        // accessibility query, and main's run 37828454679 never found it.
        let ground = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let build = app.buttons["panel.action"]
        func sited() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: build)],
                             timeout: 10) == .completed
        }
        ground.tap()
        if !sited() { ground.tap() }
        XCTAssertTrue(sited(), "A tap did not choose a site the house can stand on")
        XCTAssertEqual(count.label, "0 buildings placed", "A tap only chooses where it goes")
        build.tap()
        let built = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1 building placed"), object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [built], timeout: 10), .completed, "The house was not built: \(count.label)")

        openGameMenu(in: app)
        tapMenuAction("menu.saveGame", in: app)
        openGameMenu(in: app)
        tapMenuAction("menu.backToStart", in: app)
        requiredButton("start.continue", in: app).tap()

        requiredButton("tool.building", in: app).tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10), "Missing the building count after continuing")
        XCTAssertEqual(count.label, "1 building placed", "The house did not survive saving and continuing")
    }

    /// City building P0-B (decision 98): the building tool's zoning mode
    /// zones the cells a one-finger drag crosses, and the zones survive
    /// saving and continuing. Not on the pull request gate: the drag is a
    /// gesture only a Simulator can make, but the zoning itself is pinned
    /// by GameCore's and GamePresentation's tests.
    func testCellsZonedByADragAreKeptBySavingAndContinuing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        requiredButton("start.newGame", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        requiredButton("tool.building", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Zone")), name: "Zone").tap()
        requiredButton("building.zone.commercial", in: app).tap()
        let count = app.staticTexts["building.zoneCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), "Missing the zoned cell count")
        XCTAssertEqual(count.label, "0 cells zoned")

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        let zoned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0 cells zoned"), object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [zoned], timeout: 10), .completed, "The drag zoned nothing: \(count.label)")
        let label = count.label

        openGameMenu(in: app)
        tapMenuAction("menu.saveGame", in: app)
        openGameMenu(in: app)
        tapMenuAction("menu.backToStart", in: app)
        requiredButton("start.continue", in: app).tap()

        requiredButton("tool.building", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Zone")), name: "Zone").tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10), "Missing the zoned cell count after continuing")
        XCTAssertEqual(count.label, label, "The zones did not survive saving and continuing")
    }

    private func checkFlow(language: String, locale: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        assertEmptyStart(in: app)

        requiredButton("start.demoMap", in: app).tap()
        assertGame(in: app)

        // Keep the live clock from rebuilding the native menu while XCTest
        // targets its actions, as in the tutorial UI tests. Use the real HUD.
        requiredButton(app.buttons.matching(NSPredicate(
            format: "label == %@", language == "en" ? "Pause" : "暫停"
        )), name: "Pause").tap()

        openGameMenu(in: app)

        tapMenuAction("menu.saveGame", in: app)
        assertGame(in: app)

        openGameMenu(in: app)

        tapMenuAction("menu.backToStart", in: app)
        _ = requiredButton("start.newGame", in: app)
        _ = requiredButton("start.continue", in: app)
        // Back to Start creates only an autosave. This separate button also
        // proves that Save Game wrote a manual save rather than doing nothing.
        _ = requiredButton("start.savedGames", in: app)
        _ = requiredButton("start.demoMap", in: app)

        requiredButton("start.continue", in: app).tap()
        assertGame(in: app)
        XCTAssertFalse(app.buttons["start.newGame"].exists, "Continue did not leave the start screen")

        // Prove that the same installation starts clean again after both a
        // manual save and an autosave, in each language.
        app.terminate()
        app.launch()
        assertEmptyStart(in: app)
    }

    private func assertEmptyStart(in app: XCUIApplication) {
        _ = requiredButton("start.newGame", in: app)
        _ = requiredButton("start.demoMap", in: app)
        XCTAssertFalse(app.buttons["start.continue"].exists, "A clean launch must not offer Continue")
        XCTAssertFalse(app.buttons["start.savedGames"].exists, "A clean launch must not list saved games")
    }

    private func assertGame(in app: XCUIApplication) {
        // The demo map's accessibility tree is large: on a slow runner one
        // query of it took 9 s, so its waits allow longer than a button's.
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 30), "Missing game map")
        assertHittable(map, timeout: 30, message: "Game map is not visible")
        for identifier in ["tool.select", "tool.network", "tool.train", "hud.menu"] {
            _ = requiredButton(identifier, in: app)
        }
    }

    private func openGameMenu(in app: XCUIApplication) {
        requiredButton("hud.menu", in: app).tap()
        _ = requiredButton("menu.saveGame", in: app)
        _ = requiredButton("menu.backToStart", in: app)
        // Let the menu finish opening: tapMenuAction touches an action's
        // frame as it reads it. The screenshot taken here used to pause so.
        Thread.sleep(forTimeInterval: 1)
    }

    private func tapMenuAction(_ identifier: String, in app: XCUIApplication) {
        let button = requiredButton(identifier, in: app)
        // XCTest can report a native SwiftUI Menu action as hittable yet
        // fail to compute its activation point when tap() refreshes the
        // tree. Touch the visible frame's center, keeping the hittable and
        // enabled checks and the subsequent real save/return assertions.
        let frame = button.frame, bounds = app.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(bounds.contains(center), "Menu action is outside the app: \(identifier)")
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: center.x - bounds.minX, dy: center.y - bounds.minY))
        point.tap()
        // A row can show its press highlight and still not run its action
        // (run 37196737286: the menu stayed open and the map behind it was
        // never hittable). The menu closes when the action runs, so touch
        // it once more only while it is still open.
        if !menuCloses(app.buttons.matching(identifier: identifier), timeout: 10) {
            point.tap()
        }
    }

    /// Whether no copy of the menu action is left that the player can
    /// touch within `timeout` seconds.
    private func menuCloses(_ query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !query.allElementsBoundByIndex.contains(where: { $0.isHittable }) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    private func requiredButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        requiredButton(app.buttons.matching(identifier: identifier), name: identifier)
    }

    private func requiredButton(_ query: XCUIElementQuery, name: String) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "Missing UI flow button: \(name)")
        // ViewThatFits can also expose an unplaced copy of a menu action.
        // Find the button the player can touch, allowing the transition to
        // finish, and still fail if it is disabled or no copy is tappable.
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let button = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                XCTAssertTrue(button.isEnabled, "UI flow button is disabled: \(name)")
                return button
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("UI flow button cannot be tapped: \(name)")
        return query.firstMatch
    }

    private func assertHittable(_ element: XCUIElement, timeout: TimeInterval, message: String) {
        // Existence can precede the end of a menu or screen transition.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, message)
    }
}
