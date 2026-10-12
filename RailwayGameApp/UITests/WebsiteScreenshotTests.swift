import XCTest

/// Screenshots for the game's website (decision 165), in Traditional
/// Chinese on a phone on its side. Run only by `website-screenshots.yml`,
/// never by the gate or the full lane: each test opens a screen and keeps
/// what it shows as an attachment the workflow exports. They check only
/// that the screen they photograph is there.
@MainActor
final class WebsiteScreenshotTests: XCTestCase {
    /// The freight scene (`ScreenshotScene.freight`): the map with the
    /// stations short of building materials, a yard's station picked (its
    /// tag says the goods waiting), and the freight train's card.
    func testFreight() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 120), "The scene opens")
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.waitForExistence(timeout: 30), "The stations short of materials show")
        settle()
        keep("freight-materials", app)

        // A bubble on screen picks its station, whose tag shows.
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        XCTAssertTrue(app.buttons["map.stationTag"].waitForExistence(timeout: 5), "A tap on a bubble picks its station")
        settle()
        keep("freight-station", app)

        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        XCTAssertTrue(fleet.waitForExistence(timeout: 5))
        fleet.tap()
        // The freight train is the last of five: the list loads its rows
        // as they scroll in.
        let follow = app.buttons["fleet.follow.貨運列車 1"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(follow), "The freight train is in the fleet")
        follow.tap()
        XCTAssertTrue(app.buttons["train.unfollow"].waitForExistence(timeout: 5))
        settle()
        keep("freight-train", app)
    }

    /// A blank new game's map expansion: the tiles that can be bought,
    /// their prices, and the locked ones.
    func testMapExpansion() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        let expansion = app.buttons["map.expansion"]
        XCTAssertTrue(expansion.waitForExistence(timeout: 30), "A blank map can be expanded")
        expansion.tap()
        settle(seconds: 3)
        keep("map-expansion", app)
    }

    /// The Liu Mingchuan challenge as it opens: its map from Keelung to
    /// Hsinchu, and the station master's first words.
    func testLiuMingchuanChallenge() {
        let app = launch()
        defer { app.terminate() }
        let challenges = app.buttons["start.challenges"]
        XCTAssertTrue(challenges.waitForExistence(timeout: 10))
        app.bringStartButtonIntoView(challenges)
        challenges.tap()
        let liu = app.buttons["challenge.history.liuMingchuan"]
        XCTAssertTrue(liu.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: liu)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "The real-world data loads")
        liu.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 60), "The challenge starts")
        settle(seconds: 8)
        keep("liu-mingchuan", app)
    }

    /// The real-world demo on the game's own base map (decision 151), the
    /// hills shaded from the game's heights.
    func testRealWorldDemoBaseMap() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 60), "The demo starts")
        settle(seconds: 8)
        keep("real-world-demo", app)
    }

    // MARK: - What the game gained after those (decisions 167 to 186)

    /// The High Speed Rail demo (decision 170): Nangang to Zuoying on the
    /// real route, its sets already running. It is built off the main
    /// actor, which takes minutes in the Simulator's unoptimised build.
    func testHighSpeedDemo() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.highSpeed", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 600), "The demo is built and opens")
        settle(seconds: 8)
        keep("high-speed-demo", app)

        // The line from end to end, a few steps out.
        let zoomOut = app.buttons["縮小"]
        if zoomOut.waitForExistence(timeout: 10), zoomOut.isHittable {
            for _ in 0..<3 {
                zoomOut.tap()
                settle(seconds: 1)
            }
            settle(seconds: 3)
            keep("high-speed-demo-wide", app)
        }
    }

    /// The company's goals on a blank new game (decisions 181 and 183): the
    /// requests the city offers with what each pays, above the company's
    /// rank and title.
    func testGoalsAndCityRequests() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 30), "The game starts")
        openFromGameMenu("menu.goals", in: app)
        settle(seconds: 3)
        keep("goals-requests", app)
    }

    /// The lines' reports of the day before (decision 179) and the
    /// passenger load layer (decision 178) on the freight scene's second
    /// morning, when a day has been and the trains carry their loads.
    func testLineReportAndPassengerLoad() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        settle(seconds: 3)
        keep("line-report", app)

        // The panel out of the map's way, then the layer: the riders on
        // each stretch of track against what its trains carry.
        let toggle = app.buttons["controls.toggle"]
        if toggle.exists, toggle.isHittable {
            toggle.tap()
            settle()
        }
        let layers = app.buttons["map.layers"]
        layers.waitUntilSettled()
        layers.tap()
        let row = app.switches["layer.sectionFlow"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row), "The passenger load row comes into view")
        let load = row.switches.firstMatch
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        for _ in 0..<3 where load.value as? String != "1" {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: load)
            _ = XCTWaiter.wait(for: [hittable], timeout: 5)
            load.tap()
            let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: load)
            _ = XCTWaiter.wait(for: [switched], timeout: 3)
        }
        XCTAssertEqual(load.value as? String, "1", "The passenger load layer is on")
        app.buttons["layer.done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["map.sectionFlowLegend"].firstMatch.waitForExistence(timeout: 10), "The layer's key shows")
        // The load is worked out in the background.
        settle(seconds: 5)
        keep("passenger-load", app)
    }

    /// The sights of the whole of Taiwan (decision 174): their stars on the
    /// map, then their panel with the stars, the season and the shops.
    func testTourism() {
        let app = launch()
        defer { app.terminate() }
        tapButton("start.realWorld", in: app, timeout: 60)
        // Below Taiwan's places, and enabled once the population is read.
        let wholeTaiwan = app.buttons["realWorld.wholeTaiwan"]
        XCTAssertTrue(wholeTaiwan.waitForExistence(timeout: 30), "The whole of Taiwan is offered")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(wholeTaiwan), "The button comes into view")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: wholeTaiwan)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 90), .completed, "The population is read")
        wholeTaiwan.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 120), "The game starts")
        settle(seconds: 5)
        keep("tourism-map", app)

        openFromGameMenu("menu.tourism", in: app)
        _ = app.buttons["tourism.done"].waitForExistence(timeout: 10)
        settle(seconds: 2)
        keep("tourism-panel", app)
    }

    // MARK: - Helpers

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"] + extra
        app.launch()
        return app
    }

    /// Lets the map draw and the animations end before a screenshot.
    private func settle(seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Keeps the screen as an attachment named `name`, which the workflow
    /// exports as `name.png`. The whole screen: the app's own screenshot
    /// of a phone on its side came out turned and cut in half.
    private func keep(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Opens `item` of the game menu's "More" submenu. The clock is paused
    /// first: its ticks would rebuild the native menu while XCTest targets
    /// an action in it (the start and save flow's rule).
    private func openFromGameMenu(_ item: String, in app: XCUIApplication) {
        let pause = app.buttons.matching(NSPredicate(format: "label == %@", "暫停")).firstMatch
        if pause.waitForExistence(timeout: 10), pause.isHittable {
            pause.tap()
        }
        tapButton("hud.menu", in: app)
        tapButton("menu.more", in: app)
        tapButton(item, in: app)
    }

    /// Taps the copy of the button `identifier` that the player can touch,
    /// once it is enabled: a menu can hold an unplaced copy of an action
    /// (`RealWorldMapUITests.tappable`).
    private func tapButton(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let buttons = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: timeout), "Missing button: \(identifier)")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let button = buttons.allElementsBoundByIndex.first(where: { $0.isHittable && $0.isEnabled }) {
                button.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("Button cannot be tapped: \(identifier)")
    }
}
