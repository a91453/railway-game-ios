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
        // One step closer, so that the bubbles stand clear of the stations'
        // names under them.
        zoomInOnce(app)
        settle()
        keep("freight-materials", app)

        // Decision 184: a bubble for a town short of materials opens its
        // station's panel, whose Freight section builds the yard.
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        let panel = app.descendants(matching: .any).matching(identifier: "station.operations").firstMatch
        XCTAssertTrue(panel.appears(within: 10), "A tap on a bubble opens its station's panel")
        // The materials line sits lower in the form; bring it into view
        // when the form has it, without failing the shot if it stays below.
        let materials = app.descendants(matching: .any)["station.materials"].firstMatch
        _ = app.dragUntilWhollyOnScreen(materials, drags: 8)
        settle()
        keep("freight-station", app)
        let done = app.buttons["完成"].firstMatch
        if done.appears(within: 3), done.isHittable {
            done.tap()
            XCTAssertTrue(done.disappears(within: 10), "The station's panel closes")
        }

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
        // The sheet's list makes a row only once it scrolls in.
        var reached = false
        for _ in 0..<12 {
            if follow.exists, follow.isHittable { reached = true; break }
            // Start in the margin beside the cards: a drag that starts on a card did not move the list.
            let margin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            margin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)))
        }
        // The fleet sheet did not scroll under XCUITest in three runs
        // (40819608742, 40820811745, 40822034774): keep what it shows and
        // go without the following shot rather than fail the other two.
        guard reached else {
            keep("debug-fleet", app)
            return
        }
        follow.tap()
        XCTAssertTrue(app.buttons["train.unfollow"].appears(within: 5))
        settle()
        keep("freight-train", app)
    }

    /// Decision 480: the economy panel's income and cost donuts in the
    /// freight scene, the day's and the week's (its tax and "Other"), and a
    /// slice picked. For the screenshot review of the pull request that
    /// made them, not the website.
    func testFinanceComposition() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        tapButton("entry.economy", in: app)
        let bar = app.navigationBars["經濟明細"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The economy panel opens")
        bar.waitUntilSettled()
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        XCTAssertTrue(app.revealFinanceComposition(in: list, below: bar.frame.maxY), "The income donut comes into reach")
        settle()
        keep("finance-composition-day-income", app)

        let costs = app.descendants(matching: .any)["economy.composition.costs"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(costs, in: list, below: bar.frame.maxY), "The cost donut comes into reach")
        settle()
        keep("finance-composition-day-costs", app)

        let fares = app.buttons["economy.composition.income.fares"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(fares, in: list, below: bar.frame.maxY), "The fares row comes into reach")
        fares.tap()
        settle(seconds: 1)
        keep("finance-composition-picked", app)

        // The week: the first midnight's tax, and the small costs as "Other".
        let week = app.buttons["週"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(week, in: list, below: bar.frame.maxY), "The period picker comes into reach")
        week.tap()
        XCTAssertTrue(app.dragUntilWhollyOnScreen(costs, in: list, below: bar.frame.maxY), "The week's cost donut comes into reach")
        settle()
        keep("finance-composition-week-costs", app)
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
        // One step closer, so that the sights' stars stand clear of the
        // prices.
        zoomInOnce(app)
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

    /// New game → real world (decision 477): the whole of Taiwan first,
    /// above the places.
    func testRealWorldPicker() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        tapButton("newGame.realWorld", in: app, timeout: 60)
        XCTAssertTrue(app.buttons["realWorld.wholeTaiwan"].appears(within: 15), "The places show")
        settle()
        keep("real-world-picker", app)
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

    /// The lines panel in two levels (decision 481) on the freight scene's
    /// second morning: the short list with its pinned controls, a line's
    /// own page, and the whole network's page.
    func testLinesListAndLinePage() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        XCTAssertTrue(app.navigationBars["路線"].firstMatch.appears(within: 10), "The lines panel opens")
        settle(seconds: 2)
        keep("lines-list", app)

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.trainsRow.")).firstMatch
        XCTAssertTrue(row.appears(within: 10), "A line's row shows")
        row.tap()
        XCTAssertTrue(app.collectionViews["line.detail"].appears(within: 10), "The line's page opens")
        settle(seconds: 2)
        keep("line-page", app)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.collectionViews["line.detail"].disappears(within: 10), "Back to the list")
        let network = app.buttons["lines.network"]
        XCTAssertTrue(network.appears(within: 10), "The whole network's row shows")
        network.tap()
        settle(seconds: 2)
        keep("lines-network", app)
    }

    /// Decision 478's load charts on the freight scene: a passenger line's
    /// fullest train by day and its riders between stops, then a section's
    /// riders hour by hour in the flow report.
    func testLoadCharts() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let report = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.report.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(report, in: list), "A passenger line's row comes into view")
        report.tap()
        // Decision 481: the charts are on the line's own page.
        let linePage = app.collectionViews["line.detail"].firstMatch
        XCTAssertTrue(linePage.appears(within: 10), "The line's page opens")
        let peak = app.descendants(matching: .any)["line.operations.peakLoad"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(peak, in: linePage), "The fullest train by day comes into view")
        settle()
        keep("line-peak-load", app)
        XCTAssertTrue(app.dragUntilWhollyOnScreen(app.descendants(matching: .any)["line.load.chart"].firstMatch, in: linePage),
                      "The riders between stops come into view")
        // Worked out in the background.
        settle(seconds: 3)
        keep("line-load-profile", app)

        // The flow report's button is on the list's bar.
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(linePage.disappears(within: 10), "Back to the list")
        let flow = app.buttons["lines.networkFlow"]
        XCTAssertTrue(flow.becomesHittable(within: 5), "The flow report's button is there")
        flow.tap()
        let page = app.segmentedControls["networkFlow.page"]
        XCTAssertTrue(page.appears(within: 10), "The flow report opens")
        page.buttons.element(boundBy: 1).tap()
        // Below decision 472's ranking: the list builds it as it scrolls
        // in. Its summary first, then a little further for the chart, which
        // is taller than the band dragUntilWhollyOnScreen keeps clear.
        let summary = app.descendants(matching: .any)["networkFlow.hourly.summary"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(summary), "A section's riders hour by hour show")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        settle()
        keep("section-hourly", app)
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
        // The whole of Taiwan is offered first (decision 477), in a list
        // that builds a row as it is scrolled to, and is enabled once the
        // population is read. The list is found by its first row, which it
        // drops once scrolled away from, so a second swipe found no list:
        // where the list lies is kept, and dragged there.
        // Decision 442: Taiwan's places are 22 rows, so Taipei's is not on
        // the first screen; the list is the page's first, found as
        // `RealWorldMapUITests` finds it.
        let places = app.collectionViews.firstMatch
        XCTAssertTrue(places.appears(within: 30), "The places are listed")
        let wholeTaiwan = app.buttons["realWorld.wholeTaiwan"]
        XCTAssertTrue(app.scrollUntilShown(wholeTaiwan, in: places), "The whole of Taiwan comes into view")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: wholeTaiwan)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 90), .completed, "The population is read")
        app.tapMiddle(of: wholeTaiwan)
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

    // MARK: - Screenshot review of decision 472's charts (ui-review skill)

    /// Decision 472's charts on the freight scene's second morning, for
    /// their screenshot review: a station's trips by hour with its rush,
    /// the lines' rows with their trend and fullest train, and the flow
    /// report's most crowded sections.
    func testStatisticsCharts() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        // A bubble picks its station; the tag's pencil opens the station's
        // panel with the rename alert over it, which is cancelled.
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.appears(within: 30), "The stations short of materials show")
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        let pencil = app.buttons["map.stationTag.edit"]
        XCTAssertTrue(pencil.appears(within: 5), "A tap on a bubble picks its station")
        XCTAssertTrue(pencil.becomesHittable(within: 5))
        pencil.tap()
        let rename = app.alerts.firstMatch
        XCTAssertTrue(rename.appears(within: 5), "The station's panel opens with the rename alert")
        rename.buttons["取消"].tap()
        XCTAssertTrue(rename.disappears(within: 5))
        settle()
        keep("chart-station-panel", app)
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.frame.minX > app.frame.midX }
        let entries = app.descendants(matching: .any)["station.flow.entries"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(entries, in: list), "The trips by hour come into view")
        settle()
        keep("chart-station-hourly", app)
        let done = app.navigationBars.buttons["完成"].firstMatch
        if done.exists, done.isHittable {
            done.tap()
            settle()
        }

        // The lines' rows, each with its trend (decision 481: the fullest
        // train is on the line's own page).
        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        let linesList = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let report = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.report.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(report, in: linesList), "A line's row comes into view")
        settle()
        keep("chart-line-rows", app)

        // The flow report's most crowded sections, ranked.
        let flow = app.buttons["lines.networkFlow"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(flow, in: linesList), "The flow report's button comes into view")
        flow.tap()
        let page = app.segmentedControls["networkFlow.page"]
        XCTAssertTrue(page.appears(within: 10), "The flow report opens")
        page.buttons.element(boundBy: 1).tap()
        let ranking = app.descendants(matching: .any)["networkFlow.ranking"].firstMatch
        XCTAssertTrue(ranking.appears(within: 30), "The ranking is worked out")
        settle()
        keep("chart-section-ranking", app)
    }

    /// Where trains show on the freight scene, for the ui-review skill's
    /// icon-or-model check (decision 482, later): the map from far and
    /// near, a line's details and its showroom, and the fleet. A screen it
    /// cannot reach is left out rather than failing the run.
    func testTrainLooks() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()
        keep("trains-map", app)
        let zoomOut = app.buttons["縮小"], zoomIn = app.buttons["放大"]
        if zoomOut.appears(within: 10), zoomOut.becomesHittable(within: 1) {
            for _ in 0..<2 {
                zoomOut.tap()
                settle(seconds: 1)
            }
            settle()
            keep("trains-map-far", app)
        }
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 1) {
            for _ in 0..<5 {
                zoomIn.tap()
                settle(seconds: 1)
            }
            settle()
            keep("trains-map-near", app)
        }

        // A line's details, then its showroom.
        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let report = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.report.")).firstMatch
        if app.dragUntilWhollyOnScreen(report, in: list) {
            // Decision 481: a row opens the line's own page.
            report.tap()
            let page = app.collectionViews["line.detail"]
            _ = page.appears(within: 10)
            settle()
            keep("trains-line-details", app)
            let catalog = app.buttons["line.staff.catalog"]
            if app.dragUntilWhollyOnScreen(catalog, in: page.exists ? page : list) {
                catalog.tap()
                let cancel = app.buttons["catalog.cancel"]
                if cancel.appears(within: 10) {
                    settle()
                    keep("trains-catalog", app)
                    cancel.tap()
                    _ = cancel.disappears(within: 10)
                }
            }
        }
        let done = bar.buttons["完成"]
        if done.exists, done.isHittable {
            done.tap()
            settle()
        }

        // The fleet, as the freight test opens it.
        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        if fleet.appears(within: 5) {
            fleet.tap()
            _ = app.buttons["fleet.done"].appears(within: 10)
            settle()
            keep("trains-fleet", app)
        }
    }

    // MARK: - Helpers

    /// One tap on the zoom-in button, when the map has it.
    private func zoomInOnce(_ app: XCUIApplication) {
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 5), zoomIn.becomesHittable(within: 3) {
            zoomIn.tap()
            settle(seconds: 1)
        }
    }

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
