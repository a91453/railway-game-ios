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
        XCTAssertTrue(map.appears(within: 120), "The scene opens")
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.appears(within: 30), "The stations short of materials show")
        settle()
        keep("freight-materials", app)

        // A bubble on screen picks its station, whose tag shows.
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        XCTAssertTrue(app.buttons["map.stationTag"].appears(within: 5), "A tap on a bubble picks its station")
        settle()
        keep("freight-station", app)

        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        XCTAssertTrue(fleet.appears(within: 5))
        fleet.tap()
        // The freight train is the last of five: the list loads its rows
        // as they scroll in.
        let follow = app.buttons["fleet.follow.貨運列車 1"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(follow), "The freight train is in the fleet")
        follow.tap()
        XCTAssertTrue(app.buttons["train.unfollow"].appears(within: 5))
        settle()
        keep("freight-train", app)
    }

    /// A blank new game's map expansion: the tiles that can be bought,
    /// their prices, and the locked ones.
    func testMapExpansion() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        app.chooseBlankMap()
        let expansion = app.buttons["map.expansion"]
        XCTAssertTrue(expansion.appears(within: 30), "A blank map can be expanded")
        expansion.tap()
        settle(seconds: 3)
        keep("map-expansion", app)
    }

    /// The Liu Mingchuan challenge as it opens: its map from Keelung to
    /// Hsinchu, and the station master's first words.
    func testLiuMingchuanChallenge() {
        let app = launch()
        defer { app.terminate() }
        // Decision 381: the challenges are on the new game's page.
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        let challenges = app.buttons["newGame.challenges"]
        XCTAssertTrue(challenges.appears(within: 10))
        XCTAssertTrue(challenges.becomesHittable(within: 5))
        challenges.tap()
        let liu = app.buttons["challenge.history.liuMingchuan"]
        XCTAssertTrue(liu.appears(within: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: liu)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "The real-world data loads")
        liu.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The challenge starts")
        // The game opens at midnight, when the map is tinted for the night
        // (decision 182), and its tiles are slow to come in: by the light of
        // day they have.
        waitForClock(from: 9, before: 17, in: app)
        settle(seconds: 2)
        keep("liu-mingchuan", app)
    }

    /// The real-world demo on the game's own base map (decision 151), the
    /// hills shaded from the game's heights.
    func testRealWorldDemoBaseMap() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The demo starts")
        settle(seconds: 8)
        keep("real-world-demo", app)

        // The same map by day: the demo opens at midnight, its stations lit.
        waitForClock(from: 9, before: 17, in: app)
        settle(seconds: 2)
        keep("real-world-demo-day", app)
    }

    // MARK: - What the game gained after those (decisions 167 to 186)

    /// The High Speed Rail demo (decision 170): Nangang to Zuoying on the
    /// real route, its sets already running. It is built off the main
    /// actor, which takes minutes in the Simulator's unoptimised build.
    func testHighSpeedDemo() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.highSpeed", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 600), "The demo is built and opens")
        settle(seconds: 8)
        keep("high-speed-demo", app)

        // It opens on what is built: the line from end to end, as far as
        // the island lets the map zoom out. A closer look at the middle of
        // it, three steps in.
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 1) {
            for _ in 0..<3 {
                zoomIn.tap()
                settle(seconds: 1)
            }
            settle(seconds: 3)
            keep("high-speed-demo-close", app)
        }
    }

    /// The company's goals on a blank new game (decisions 181 and 183): the
    /// requests the city offers with what each pays, above the company's
    /// rank and title.
    func testGoalsAndCityRequests() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        app.chooseBlankMap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The game starts")
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
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        // The lines open on a form for a new one: the panel is scrolled to
        // the lines' reports, which are in a list that builds a row as it
        // is scrolled to (the panel's own list: `ToolbarSmokeTests`).
        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let report = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.report.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(report, in: list), "A line's report comes into view")
        settle(seconds: 2)
        keep("line-report", app)

        // The panel closed, then the layer: the riders on each stretch of
        // track against what its trains carry.
        let done = bar.buttons["完成"]
        if done.exists, done.isHittable {
            done.tap()
            settle()
        }
        let layers = app.buttons["map.quickLayer.more"]
        layers.waitUntilSettled()
        layers.tap()
        // The layer is the last of the sheet's rows, below long notes: the
        // sheet is dragged up, slowly, until it is there. Not by an element
        // of it: a row that has scrolled away is not in the hierarchy.
        XCTAssertTrue(app.switches["layer.stationNames"].appears(within: 10), "The layers sheet opens")
        let row = app.switches["layer.sectionFlow"]
        XCTAssertTrue(scrollScreen(to: row, in: app), "The passenger load row comes into view")
        let load = row.switches.firstMatch
        XCTAssertTrue(load.appears(within: 5))
        for _ in 0..<3 where load.value as? String != "1" {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: load)
            _ = XCTWaiter.wait(for: [hittable], timeout: 5)
            load.tap()
            let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: load)
            _ = XCTWaiter.wait(for: [switched], timeout: 3)
        }
        XCTAssertEqual(load.value as? String, "1", "The passenger load layer is on")
        app.buttons["layer.done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["map.sectionFlowLegend"].firstMatch.appears(within: 10), "The layer's key shows")
        // The load is worked out in the background.
        settle(seconds: 5)
        keep("passenger-load", app)
    }

    /// The secretary's room (decision 175) on a blank new game: the
    /// forecast of the next seven days under the clock.
    func testForecast() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        app.chooseBlankMap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The game starts")
        settle(seconds: 5)
        pauseTheClock(in: app)

        tapButton("hud.time", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["hud.forecast"].firstMatch.appears(within: 10), "The forecast opens")
        settle()
        keep("forecast", app)
    }

    /// The sights of the whole of Taiwan (decision 174): their stars on the
    /// map, then their panel with the stars, the season and the shops.
    func testTourism() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        // Decision 316: the real-world map is on the new game's page.
        tapButton("newGame.realWorld", in: app, timeout: 60)
        // The whole of Taiwan is offered below Taiwan's places, in a list
        // that builds a row as it is scrolled to, and is enabled once the
        // population is read. The list is found by its first row, which it
        // drops once scrolled away from, so a second swipe found no list:
        // where the list lies is kept, and dragged there.
        let places = app.collectionViews.containing(.button, identifier: "place.tra-taipei").firstMatch
        XCTAssertTrue(places.appears(within: 30), "The places are listed")
        let listColumn = places.frame
        let wholeTaiwan = app.buttons["realWorld.wholeTaiwan"]
        XCTAssertTrue(scrollScreen(to: wholeTaiwan, in: app, over: listColumn), "The whole of Taiwan comes into view")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: wholeTaiwan)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 90), .completed, "The population is read")
        wholeTaiwan.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The game starts")
        // By the light of day, the stars over the island.
        waitForClock(from: 9, before: 17, in: app)
        settle(seconds: 3)
        keep("tourism-map", app)

        openFromGameMenu("menu.tourism", in: app)
        _ = app.buttons["tourism.done"].appears(within: 10)
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

    /// Drags up the middle of the screen, or of the `list` frame when one is
    /// given, slowly so that a list does not fling past, until `element` can
    /// be touched; whether it can. For a list that builds a row as it is
    /// scrolled to and is not found by what it holds, as a row that has
    /// scrolled away is not in the hierarchy.
    private func scrollScreen(to element: XCUIElement, in app: XCUIApplication, over list: CGRect? = nil, drags: Int = 30) -> Bool {
        let x = list.map { $0.midX / app.frame.width } ?? 0.5
        for _ in 0..<drags {
            if element.exists, element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.8))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.3))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            settle(seconds: 0.5)
        }
        return element.exists && element.isHittable
    }

    /// Waits until the game's clock reads from `start` o'clock to before
    /// `end`, for a screenshot by the light of day: the games open at
    /// midnight, when the map is tinted for the night (decision 182), and
    /// how fast the clock goes depends on the game and the runner.
    private func waitForClock(from start: Int, before end: Int, in app: XCUIApplication, timeout: TimeInterval = 400) {
        let clock = app.buttons["hud.time"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if clock.exists, let hour = Self.hour(in: clock.label), hour >= start, hour < end { return }
            Thread.sleep(forTimeInterval: 3)
        }
        XCTFail("The clock never read \(start) to \(end) o'clock")
    }

    /// The hour in a clock's label, "… 06:26".
    private static func hour(in label: String) -> Int? {
        guard let time = label.range(of: "[0-9]{1,2}:[0-9]{2}", options: .regularExpression) else { return nil }
        return Int(label[time].split(separator: ":")[0])
    }

    /// Opens `item` of the game menu: in its first level, or under "More"
    /// in a game with both goals and sights (decision 383). The clock is
    /// paused first: its ticks would rebuild the native menu while XCTest
    /// targets an action in it (the start and save flow's rule).
    private func openFromGameMenu(_ item: String, in app: XCUIApplication) {
        pauseTheClock(in: app)
        tapButton("hud.menu", in: app)
        if !app.buttons[item].appears(within: 3) {
            tapButton("menu.more", in: app)
        }
        tapButton(item, in: app)
    }

    /// Pauses the clock, when it runs.
    private func pauseTheClock(in app: XCUIApplication) {
        let pause = app.buttons.matching(NSPredicate(format: "label == %@", "暫停")).firstMatch
        if pause.appears(within: 10), pause.becomesHittable(within: 1) {
            pause.tap()
        }
    }

    /// Taps the copy of the button `identifier` that the player can touch,
    /// once it is enabled: a menu can hold an unplaced copy of an action
    /// (`RealWorldMapUITests.tappable`).
    private func tapButton(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let buttons = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(buttons.firstMatch.appears(within: timeout), "Missing button: \(identifier)")
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
