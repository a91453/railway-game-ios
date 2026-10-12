import XCTest

/// Stage E2: a real-world game starts from a place in the list and is
/// played over Apple's map. The map's tiles need the network, so nothing
/// here looks at them: only that the game starts on a real-world map,
/// that its style can be changed, and that its save says what it is.
@MainActor
final class RealWorldMapUITests: XCTestCase {
    func testARealWorldGameStartsFromAPlaceAndIsSavedAsOne() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        tappable(app.buttons.matching(identifier: "start.realWorld"), name: "start.realWorld").tap()

        let taipei = tappable(app.buttons.matching(identifier: "place.tra-taipei"), name: "place.tra-taipei")
        XCTAssertEqual(taipei.label, "Taipei", "The references' places are listed")
        taipei.tap()

        tappable(app.buttons.matching(identifier: "realWorld.start"), name: "realWorld.start").tap()

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "The game starts")
        let style = app.buttons["map.style"]
        XCTAssertTrue(style.waitForExistence(timeout: 10), "Only a real-world map has a map style menu")
        XCTAssertTrue(app.buttons["Zoom in"].exists)

        // Keep the live clock from rebuilding the native menus (the map
        // style's and the game's) while XCTest targets their actions, as in
        // the start and save flow: pause before opening either.
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        tappable(app.buttons.matching(identifier: "map.style"), name: "map.style").tap()
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Satellite")), name: "Satellite").tap()
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        tappable(app.buttons.matching(identifier: "hud.menu"), name: "hud.menu").tap()
        tappable(app.buttons.matching(identifier: "menu.backToStart"), name: "menu.backToStart").tap()

        let continueButton = tappable(app.buttons.matching(identifier: "start.continue"), name: "start.continue")
        XCTAssertTrue(continueButton.label.contains("Real-world map"), "The autosave is a real-world map's: \(continueButton.label)")
        continueButton.tap()
        XCTAssertTrue(app.buttons["map.style"].waitForExistence(timeout: 15), "Continuing keeps the real-world map")
    }

    /// Stage V4e: the real-world demo runs under traffic control, and the
    /// map's traffic key appears and reads out the movement authority its
    /// trains take. Full lane only (not in the pull request gate).
    func testTheRealWorldDemoShowsMovementAuthorityOnTheMap() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        app.openDemo("demo.realWorld")

        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 60), "The demo starts")
        let authority = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "map.traffic", "Movement authority")).firstMatch
        XCTAssertTrue(authority.waitForExistence(timeout: 60), "The demo's trains take their routes under traffic control")
    }

    /// Decision 170: the High Speed Rail demo is built off the main actor (a
    /// few seconds on a device, minutes in the Simulator's unoptimised
    /// build), the demo sheet saying so, and opens on the map with the
    /// clock running. Full lane only (not in the pull request gate).
    func testTheHighSpeedDemoOpensOnTheMapAndRuns() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        app.openDemo("demo.highSpeed")

        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 600), "The demo is built and opens")
        // It runs at once, like the other demos: a pause button, not a play one.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")).firstMatch.waitForExistence(timeout: 30))
    }

    /// A blank new game has no Apple map and no style menu.
    func testABlankGameHasNoMapStyle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["map.style"].exists)
    }

    /// Decision 190's report (TestFlight 54.1): on a real-world map, a
    /// phone on its side, a tall banner under the top controls (here the
    /// largest accessibility text, which makes every card and the pill
    /// tall) left no room between it and the dock, and the platform's ✓
    /// went half under the dock. The ✓ stays whole and above the dock.
    /// Full lane only (not in the pull request gate).
    func testThePlatformConfirmStaysAboveTheDockUnderATallBanner() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
        ]
        app.launch()
        defer { app.terminate() }

        tappable(app.buttons.matching(identifier: "start.realWorld"), name: "start.realWorld").tap()
        tappable(app.buttons.matching(identifier: "place.tra-taipei"), name: "place.tra-taipei").tap()
        tappable(app.buttons.matching(identifier: "realWorld.start"), name: "realWorld.start").tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "The game starts")
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()

        let build = app.buttons["dock.build"]
        tappable(app.buttons.matching(identifier: "dock.build"), name: "dock.build").tap()
        let network = app.buttons["tool.network"]
        network.waitUntilSettled()
        network.tap()

        // A stretch across the middle of the map between the top controls
        // and the dock, its ends tapped and built with the map's ✓ (or, where
        // the details card stays open, its Build Track button).
        let hudBottom = app.buttons["hud.menu"].frame.maxY
        let dockTop = build.frame.minY
        let middle = (hudBottom + dockTop) / 2
        let frame = map.frame.intersection(app.frame)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.minX + frame.width * fraction, dy: middle))
        }
        point(0.3).tap()
        point(0.55).tap()
        let confirm = app.buttons["map.build.confirm"]
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        let builder = confirm.waitForExistence(timeout: 10) ? confirm : card
        XCTAssertTrue(builder.waitForExistence(timeout: 10), "No way to build the stretch")
        XCTAssertTrue(builder.isHittable, "The ✓ cannot be tapped: \(builder.frame), dock top \(dockTop)")
        builder.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Built Edge'")).firstMatch
            .waitForExistence(timeout: 10), "The stretch was not built")

        // The platform mode, from the details card (opened if folded).
        let platform = app.buttons["Platform"]
        if !platform.waitForExistence(timeout: 3) || !platform.isHittable {
            let controls = app.buttons["controls.toggle"]
            if controls.exists { controls.tap() }
        }
        XCTAssertTrue(platform.waitForExistence(timeout: 10), "No Platform mode")
        platform.waitUntilSettled()
        platform.tap()
        // On the track: the platform's site, its pill and its ✓.
        let site = origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.425, dy: middle))
        site.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No ✓ for the platform")
        confirm.waitUntilSettled()
        XCTAssertTrue(confirm.isHittable, "The platform's ✓ cannot be tapped: \(confirm.frame)")
        XCTAssertLessThanOrEqual(confirm.frame.maxY, app.buttons["dock.build"].frame.minY,
                                 "The platform's ✓ goes under the dock: \(confirm.frame), dock \(app.buttons["dock.build"].frame)")
        let cancel = app.buttons["map.build.cancel"]
        XCTAssertTrue(cancel.isHittable, "The platform's ✕ cannot be tapped: \(cancel.frame)")
        XCTAssertLessThanOrEqual(cancel.frame.maxY, app.buttons["dock.build"].frame.minY)
    }

    /// The copy of a button the player can touch. Existence can come before
    /// a menu or screen transition ends, and `ViewThatFits` can also expose
    /// an unplaced copy of a menu action, so `firstMatch` alone may not be
    /// hittable (the start and save flow's rule, `StartSaveFlowSmokeTests`).
    /// It is waited for until enabled too: the start screen's real-world
    /// buttons are disabled until the real-world data, read in the
    /// background at launch, is there.
    private func tappable(_ query: XCUIElementQuery, name: String) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "Missing button: \(name)")
        let deadline = Date().addingTimeInterval(10)
        var disabled: XCUIElement?
        repeat {
            if let button = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                if button.isEnabled {
                    return button
                }
                disabled = button
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        if let disabled {
            XCTFail("Button is disabled: \(name)")
            return disabled
        }
        XCTFail("Button cannot be tapped: \(name)")
        return query.firstMatch
    }
}
