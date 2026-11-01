import XCTest

/// Screenshots for the game's website (decision 165), in Traditional
/// Chinese on a phone on its side. Run only by `website-screenshots.yml`,
/// never by the gate or the full lane: each test opens a screen and keeps
/// what it shows as an attachment the workflow exports. They check only
/// that the screen they photograph is there.
@MainActor
final class WebsiteScreenshotTests: XCTestCase {
    /// Decision 535: a train of a real line bought, the Neiwan Line's and
    /// the Danhai light rail's, followed: its card says what it is, the
    /// lines list what the line runs, and the 3D map draws the real line's
    /// own train (the DR1000, the Danhai light rail's), not a generic one.
    /// For the screenshot review of the pull request that drew them so.
    func testBoughtLineStock() {
        for (real, name) in [("tra:NEIWAN", "neiwan"), ("ntdlrt:V", "danhai")] {
            let app = launch(extra: ["-screenshot-scene", "acquired", "-screenshot-follow-bought", real, "-map3D.quality", "saving"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            let stock = app.descendants(matching: .any)["train.stock"].firstMatch
            XCTAssertTrue(stock.appears(within: 30), "\(real): the train's card says what it is")
            settle(seconds: 3)
            keep("bought-\(name)-train-card", app)

            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 10))
            XCTAssertTrue(open3D.becomesHittable(within: 10))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            settle(seconds: 20)
            keep("bought-\(name)-3d", app)
            app.terminate()
        }

        let app = launch(extra: ["-screenshot-scene", "acquired"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()
        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        XCTAssertTrue(app.navigationBars["路線"].firstMatch.appears(within: 10), "The lines panel opens")
        settle(seconds: 3)
        keep("bought-lines-list", app)
    }

    /// Decision 517 續: the station picked on the 2D map keeps its tag on
    /// the 3D map, under the station there; a tap on the tag opens its
    /// details back on the 2D map.
    func testThreeDStationTag() {
        let app = launch(extra: ["-screenshot-scene", "freight", "-screenshot-select-station", "1", "-map3D.quality", "saving"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 120), "The scene opens")
        XCTAssertTrue(app.buttons["map.stationTag"].appears(within: 30), "A station is picked")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        let close = app.buttons["map3D.close"]
        XCTAssertTrue(close.appears(within: 60), "The 3D map opens")
        let tag = app.buttons["map3D.stationTag"]
        XCTAssertTrue(tag.appears(within: 120), "The picked station's tag stands on the 3D map")
        settle(seconds: 4)
        keep("map3d-station-tag", app)
        XCTAssertTrue(tag.becomesHittable(within: 10))
        tag.tap()
        XCTAssertTrue(close.disappears(within: 20), "The tag opens its details on the 2D map")
        settle()
        keep("map3d-station-tag-details", app)
    }

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
        // Decision 477: the panel opens at its freight group, scrolled past
        // the operations at its top (a form leaves out the rows off
        // screen), as `MapMarkTapUITests` waits for it.
        let materials = app.descendants(matching: .any)["station.materials"].firstMatch
        XCTAssertTrue(materials.appears(within: 10), "A tap on a bubble opens its station's panel")
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

    /// Decision 519: a bubble's station panel says the next step for its
    /// materials, and its platforms how a track of the player's own calls
    /// there. For the screenshot review of the pull request that made
    /// them, not the website.
    func testMaterialsNextStepAndOwnTrack() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 120), "The scene opens")
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.appears(within: 30), "The stations short of materials show")
        zoomInOnce(app)
        settle()
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        let materials = app.descendants(matching: .any)["station.materials"].firstMatch
        XCTAssertTrue(materials.appears(within: 10), "A tap on a bubble opens its station's panel")
        settle()
        // The panel's own list, so the row comes clear of the panel's
        // bottom edge, not only of the screen's.
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.frame.minX > app.frame.midX }
        XCTAssertTrue(app.dragUntilWhollyOnScreen(materials, in: list), "The materials row with its next step comes into view")
        settle()
        keep("materials-next-step", app)
        // The platforms are in the operations group at the top, which never
        // folds and so is not in the toolbar's jump menu: drag back up
        // until the list has loaded their footer again (`swipeDown()`
        // did not move the list in 20 swipes, run 41169918330), starting
        // below the panel's toolbar, which covers the list's top (drags
        // begun there moved nothing, run 41171191571).
        let footer = app.descendants(matching: .any)["station.platforms.footer"].firstMatch
        let toolbar = app.buttons["station.jump"].firstMatch
        let top = toolbar.exists ? toolbar.frame.maxY + 8 : (list?.frame.minY ?? 0) + 80
        dragBack(to: footer, in: list, below: top, in: app)
        XCTAssertTrue(app.dragUntilWhollyOnScreen(footer, in: list, below: top), "The platforms' footer comes into view")
        settle()
        keep("station-own-track", app)
    }

    /// Decision 506: a station panel's size section, how many can wait
    /// and the next expansion with what it needs. For the screenshot
    /// review of the pull request that made it, not the website.
    func testStationExpansionSection() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 120), "The scene opens")
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.appears(within: 30), "The stations' bubbles show")
        zoomInOnce(app)
        settle()
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        let jump = app.buttons["station.jump"].firstMatch
        XCTAssertTrue(jump.appears(within: 10), "A tap on a bubble opens its station's panel")
        jump.tap()
        let riders = app.buttons["station.jump.riders"].firstMatch
        XCTAssertTrue(riders.appears(within: 5), "The jump menu opens")
        riders.tap()
        settle()
        let section = app.descendants(matching: .any)["station.expansion.current"].firstMatch
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.frame.minX > app.frame.midX }
        XCTAssertTrue(app.dragUntilWhollyOnScreen(section, in: list), "The station size section comes into view")
        settle()
        keep("station-expansion", app)
    }

    /// Decision 533: the station panel's row of the riders a school and a
    /// hospital beside the station bring, under its trips by hour, at
    /// half past seven on a school day (`ScreenshotScene.commute`). For
    /// the screenshot review of the pull request that made it, not the
    /// website.
    func testCivicRidersRow() {
        let app = launch(extra: ["-screenshot-scene", "commute", "-screenshot-select-station", "1"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 120), "The scene opens")
        // A hold on the first station (the school's and the hospital's)
        // opens its panel, as `ToolbarSmokeTests`' board test does: the
        // tag's tap opens only the details card.
        let stations = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(stations.appears(within: 30), "The stations are drawn")
        func first() -> CGPoint? {
            ((stations.value as? String) ?? "").split(separator: ";").first.flatMap { pair in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
        }
        var last = first()
        let still = Date().addingTimeInterval(10)
        while Date() < still {
            Thread.sleep(forTimeInterval: 0.5)
            let now = first()
            if now != nil, now == last { break }
            last = now
        }
        guard let point = last else { return XCTFail("The scene has stations") }
        var list: XCUIElement?
        for _ in 0..<3 where list == nil {
            map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).press(forDuration: 1.2)
            let opened = Date().addingTimeInterval(5)
            repeat {
                list = app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.frame.minX > app.frame.midX }
                if list == nil { Thread.sleep(forTimeInterval: 0.25) }
            } while list == nil && Date() < opened
        }
        XCTAssertNotNil(list, "The hold opens the station's panel")
        let jump = app.buttons["station.jump"].firstMatch
        XCTAssertTrue(jump.appears(within: 10), "The panel has its jump menu")
        jump.tap()
        let riders = app.buttons["station.jump.riders"].firstMatch
        XCTAssertTrue(riders.appears(within: 5), "The jump menu opens")
        riders.tap()
        settle()
        // By its words too: in the list the row's identifier was not found
        // though it showed (run 41281919190's recording).
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "station.civicRiders.school", "學校 ·")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row, in: list), "The riders row comes into view")
        settle()
        keep("station-civic-riders", app)
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
        // The freight scene's simple rules fold the reports under the last
        // row: open them there and drag back up to the donut, rather than
        // look for it down the folded list first (`revealFinanceComposition`
        // spent some 220 of the test's 480 seconds so, run 41032530255).
        let income = app.descendants(matching: .any)["economy.composition.income"].firstMatch
        let reports = app.buttons["economy.reports"]
        if !income.exists, app.dragUntilWhollyOnScreen(reports, in: list, below: bar.frame.maxY), reports.label == "更多報表與設定" {
            reports.tap()
        }
        dragBack(to: income, in: list, below: bar.frame.maxY, in: app)
        XCTAssertTrue(app.dragUntilWhollyOnScreen(income, in: list, below: bar.frame.maxY), "The income donut comes into reach")
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
        // The picker is above the statement, scrolled away by now, and a
        // row the form has let go is otherwise looked for further down.
        let week = app.buttons["週"].firstMatch
        dragBack(to: week, in: list, below: bar.frame.maxY, in: app)
        XCTAssertTrue(app.dragUntilWhollyOnScreen(week, in: list, below: bar.frame.maxY), "The period picker comes into reach")
        week.tap()
        XCTAssertTrue(app.dragUntilWhollyOnScreen(costs, in: list, below: bar.frame.maxY), "The week's cost donut comes into reach")
        settle()
        keep("finance-composition-week-costs", app)
    }

    /// HANG2 P2-5 (decision 497): the confirmation before switching to free
    /// play, which says the cash stays where it is. For the screenshot
    /// review of the pull request that changed it, not the website.
    func testFreePlaySwitchConfirmation() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        app.chooseBlankMap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The game opens")
        tapButton("entry.economy", in: app)
        let bar = app.navigationBars["經濟明細"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The economy panel opens")
        bar.waitUntilSettled()
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let reports = app.buttons["economy.reports"]
        let free = app.buttons["切換到自由模式"].firstMatch
        if !free.exists, app.dragUntilWhollyOnScreen(reports, in: list, below: bar.frame.maxY), reports.label == "更多報表與設定" {
            reports.tap()
        }
        XCTAssertTrue(app.dragUntilWhollyOnScreen(free, in: list, below: bar.frame.maxY), "The free play switch comes into reach")
        free.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "蓋東西、買車都不用錢")).firstMatch.appears(within: 10), "The confirmation says building costs nothing")
        settle(seconds: 1)
        keep("free-play-switch-confirmation", app)
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

    /// Decision 523: amounts in NT$, and in English a rough US$ figure
    /// under the balance, beside a stretch's cost and after the starting
    /// cash. For the screenshot review of the pull request that added it,
    /// not the website.
    func testUSDollarReferenceEnglish() {
        currencyShots(english: true)
    }

    /// Decision 523: the same screens in Chinese, NT$ with no US$ figure.
    func testUSDollarReferenceChinese() {
        currencyShots(english: false)
    }

    private func currencyShots(english: Bool) {
        let suffix = english ? "en" : "zh"
        let app = launch(english: english)
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        XCTAssertTrue(app.buttons["newGame.blank"].appears(within: 10), "The new game's options open")
        settle(seconds: 1)
        keep("currency-new-game-\(suffix)", app)
        app.chooseBlankMap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 60), "The game opens")
        settle()
        keep("currency-hud-\(suffix)", app)

        tapButton("entry.economy", in: app)
        // The press on Data can be cancelled while the station master's
        // bubble goes (`FinanceCompositionUITests`): tap once more if the
        // panel did not open.
        let bar = app.navigationBars[english ? "Economy" : "經濟明細"].firstMatch
        if !bar.appears(within: 10) {
            tapButton("entry.economy", in: app)
        }
        XCTAssertTrue(bar.appears(within: 10), "The economy panel opens")
        bar.waitUntilSettled()
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        // Once the first hour has closed, the balance is among the reports
        // folded under today's figures; before it, every report shows and
        // there is no toggle. Go down the list until one or the other
        // comes, open the reports if folded, then go on to the balance.
        let balance = english ? app.staticTexts["economy.balance.usd"].firstMatch : app.staticTexts["目前餘額"].firstMatch
        let reports = app.buttons["economy.reports"].firstMatch
        // The panel beside the map is short and its rows are mostly fare
        // controls: swipe the list (a press and drag there changed the
        // fare, run 41236322793), and drag only clear of buttons.
        for _ in 0..<30 where !balance.exists && !reports.exists {
            list?.swipeUp(velocity: .slow)
        }
        if !balance.exists, app.dragUntilWhollyOnScreen(reports, in: list, below: bar.frame.maxY, clearOf: .button),
           reports.label == (english ? "More reports and settings" : "更多報表與設定") {
            reports.tap()
        }
        // The reports open below the fleet, above the toggle: the balance
        // follows the trends, further down.
        XCTAssertTrue(app.dragUntilWhollyOnScreen(balance, in: list, below: bar.frame.maxY, clearOf: .button),
                      "The balance is in the panel")
        settle()
        keep("currency-economy-\(suffix)", app)
        app.terminate()

        // A stretch drawn but not built: the cost above the map.
        let again = launch(english: english)
        defer { again.terminate() }
        let start = again.buttons["start.newGame"]
        XCTAssertTrue(start.appears(within: 10))
        again.bringStartButtonIntoView(start)
        start.tap()
        again.chooseBlankMap()
        let field = again.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(field.appears(within: 60), "The game opens")
        let build = again.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let network = again.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 5))
        network.waitUntilSettled()
        if !network.isSelected { network.tap() }
        let frame = field.frame.intersection(again.frame)
        let middle = (again.buttons["hud.menu"].frame.maxY + build.frame.minY) / 2
        let origin = again.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.3, dy: middle)).tap()
        origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.6, dy: middle)).tap()
        settle()
        keep("currency-build-cost-\(suffix)", again)
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

    /// 98.1 (decision 382, later): Build open on a phone on its side, the
    /// building tools from the column's top, on a map without credits and
    /// on the real-world demo with its credits under the column. For the
    /// screenshot review of the pull request that moved them, not the
    /// website. 100.1 (decision 509): with zoning's own button too.
    func testBuildingToolsColumn() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        app.buttons["dock.build"].tap()
        app.buttons["tool.network"].waitUntilSettled()
        settle()
        assertBuildingToolsWhole(app)
        keep("build-tools-column", app)
        // Decision 509: zoning's own button, its card open.
        app.buttons["tool.zoning"].tap()
        XCTAssertTrue(app.staticTexts["building.zoneCount"].appears(within: 10), "The zoning tool opens")
        settle()
        keep("build-tools-zoning", app)
        app.terminate()

        let real = launch()
        defer { real.terminate() }
        real.openDemo("demo.realWorld", timeout: 60)
        XCTAssertTrue(real.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The demo starts")
        settle(seconds: 4)
        // The credits' row starts past the column, which runs down beside
        // it (98.1, the planner's (a)).
        let credit = real.buttons["map.credit"]
        if credit.appears(within: 10) {
            XCTAssertGreaterThanOrEqual(credit.frame.minX, real.buttons["dock.build"].frame.maxX, "Past the column: \(credit.frame)")
        }
        keep("real-world-credits-row", real)
        real.buttons["dock.build"].tap()
        real.buttons["tool.network"].waitUntilSettled()
        settle()
        assertBuildingToolsWhole(real)
        keep("build-tools-column-real-world", real)
        real.terminate()

        // Lesson 1's tools, which fit: where they stand when nothing scrolls.
        let lesson = launch()
        defer { lesson.terminate() }
        let lessons = lesson.buttons["start.lessons"]
        XCTAssertTrue(lessons.appears(within: 15), "The start screen shows Lessons")
        lessons.waitUntilSettled()
        lessons.tap()
        let first = lesson.buttons["lesson.1.start"]
        if !first.appears(within: 5), lessons.exists {
            lessons.waitUntilSettled()
            lessons.tap()
        }
        XCTAssertTrue(first.appears(within: 10), "Lesson 1 is listed")
        XCTAssertTrue(first.becomesHittable(), "Lesson 1's Start can be tapped")
        first.tap()
        XCTAssertTrue(lesson.descendants(matching: .any)["tutorial.card"].firstMatch.appears(within: 60), "The lesson's card shows")
        lesson.buttons["dock.build"].tap()
        lesson.buttons["tool.select"].waitUntilSettled()
        settle()
        keep("build-tools-column-lesson", lesson)
    }

    /// The planner's condition for 100.1 (decision 509), on the smallest
    /// iPhone the workflow can choose as on the 17 Pro: the five tools,
    /// Done and Build whole on the screen, apart, and nothing scrolling
    /// (the bus tool's foot the tools' glass and the gap above Build; a
    /// part that scrolls would stand lower).
    private func assertBuildingToolsWhole(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let tools = ["tool.network", "tool.train", "tool.building", "tool.zoning", "tool.bus"]
        for name in tools + ["tool.select", "dock.build"] {
            let button = app.buttons[name]
            XCTAssertTrue(button.isHittable, "\(name) can be tapped", file: file, line: line)
            XCTAssertTrue(window.contains(button.frame), "\(name) whole on the screen: \(button.frame)", file: file, line: line)
            // Touched over 44 (2 past the 40 drawn, above and below).
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.5, "\(name) touched over 44: \(button.frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, "\(name) touched over 44: \(button.frame)", file: file, line: line)
        }
        // The touch areas meet in the 4 between two tools and never cross.
        let frames = tools.map { app.buttons[$0].frame }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(lower.minY - upper.maxY, -0.5, "apart: \(upper) \(lower)", file: file, line: line)
        }
        // Drawn: the bus tool's foot, the tools' glass (4, or 2 where the
        // column is short) and the gap of 6, then Build's glass of 4; a part
        // that scrolls stands lower, its foot only the gap above Build's glass.
        let build = app.buttons["dock.build"].frame
        XCTAssertLessThanOrEqual(frames[4].maxY - 2, build.minY + 2 - 11.5, "nothing scrolls: bus \(frames[4]), Build \(build)", file: file, line: line)
    }

    /// Building on the real-world demo, the panel open at the trailing
    /// side: where people are, its legend down by the credits rather than
    /// over the track being laid (TestFlight 98.1).
    func testBuildingLegendUnderPanel() {
        // UI tests leave where people are off unless asked (RailwayGameApp).
        let app = launch(extra: ["-show-building-layer"])
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The demo starts")
        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 5))
        network.waitUntilSettled()
        if !network.isSelected { network.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["map.potentialLegend"].firstMatch.appears(within: 30), "Where people are shows")
        settle(seconds: 4)
        keep("build-legend-under-panel", app)
    }

    /// Decision 514: the zoning layer's four outlooks on the zoning scene
    /// (`ScreenshotScene.zoning`) and its legend: by the demo's town the
    /// edge it can still build on, round the new station that waits for
    /// trains, and the grey beyond any station's reach. For the screenshot
    /// review of the pull request that marked them, not the website.
    func testZoningOutlooks() {
        let app = launch(extra: ["-screenshot-scene", "zoning"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let layers = app.buttons["map.quickLayer.more"]
        layers.waitUntilSettled()
        layers.tap()
        XCTAssertTrue(app.switches["layer.stationNames"].appears(within: 10), "The layers sheet opens")
        let row = app.switches["layer.zoning"]
        XCTAssertTrue(scrollScreen(to: row, in: app), "The zoning row comes into view")
        let zoning = row.switches.firstMatch
        XCTAssertTrue(zoning.appears(within: 5))
        for _ in 0..<3 where zoning.value as? String != "1" {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: zoning)
            _ = XCTWaiter.wait(for: [hittable], timeout: 5)
            zoning.tap()
            let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: zoning)
            _ = XCTWaiter.wait(for: [switched], timeout: 3)
        }
        XCTAssertEqual(zoning.value as? String, "1", "The zoning layer is on")
        app.buttons["layer.done"].tap()
        // The legend starts folded on a phone (decision 510): open it.
        XCTAssertTrue(app.descendants(matching: .any)["map.populationLegend"].firstMatch.appears(within: 10), "The zoning legend shows")
        let fold = app.buttons["map.legend.fold"]
        if fold.appears(within: 5), fold.label == "展開圖例", fold.becomesHittable(within: 5) { fold.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["map.zoneOutlookLegend"].firstMatch.appears(within: 10), "The outlooks' key shows")
        settle(seconds: 3)
        keep("zoning-outlooks", app)
        // One step out: the new station 1.5 km east and the far zones too.
        let zoomOut = app.buttons["縮小"]
        if zoomOut.appears(within: 5), zoomOut.becomesHittable(within: 3) {
            zoomOut.tap()
            settle(seconds: 3)
            keep("zoning-outlooks-wide", app)
        }
    }

    /// Decision 522: the zoning scene with the zoning tool open and a drag
    /// held down round the new station (`-screenshot-zone-drag`): the cells
    /// no station reaches grey inside the dashed box, and the tool opened
    /// on the use the city wants most; then the panel hidden and one step
    /// closer, the whole box in view. For the screenshot review of the
    /// pull request that added them, not the website.
    func testZoningDragPreview() {
        let app = launch(extra: ["-screenshot-scene", "zoning", "-screenshot-zone-drag"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        XCTAssertTrue(app.staticTexts["building.zoneCount"].appears(within: 30), "The zoning tool opens")
        settle(seconds: 4)
        keep("zoning-drag-preview", app)
        // The panel covers the box's east side on a phone: hidden, the
        // whole box shows, then one step closer.
        let toggle = app.buttons["controls.toggle"]
        if toggle.appears(within: 5), toggle.becomesHittable(within: 5) {
            toggle.tap()
            settle(seconds: 3)
            keep("zoning-drag-preview-map", app)
            let zoomIn = app.buttons["放大"]
            if zoomIn.appears(within: 5), zoomIn.becomesHittable(within: 3) {
                zoomIn.tap()
                settle(seconds: 3)
                keep("zoning-drag-preview-close", app)
            }
        }
    }

    /// Decision 510 (the author's iPhone held sideways, 99.1): a platform
    /// on the real-world demo where the track climbs, with where people
    /// are shown: the ✓ pill, the banner after ✓ and the layer's key each
    /// in a place of its own, the key folded while the pill shows. The
    /// longest platform, so its stretch is the likeliest not to level; a
    /// stretch that levels still shows the pill, banner and key together.
    func testPlatformLevellingWithTheLayer() {
        let app = launch(extra: ["-show-building-layer"])
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 60), "The demo starts")
        pauseTheClock(in: app)
        // Five steps in, as RealWorldMapUITests does: at the opening zoom
        // the stretch below would run onto land not owned, with no ✓.
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10) {
            for _ in 0..<5 where zoomIn.isEnabled { zoomIn.tap() }
        }
        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 5))
        network.waitUntilSettled()
        if !network.isSelected { network.tap() }
        // A stretch across the middle of the map, built with the ✓ (or,
        // where the details card stays open, its Build Track button).
        let frame = map.frame.intersection(app.frame)
        let middle = (app.buttons["hud.menu"].frame.maxY + build.frame.minY) / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.minX + frame.width * fraction, dy: middle))
        }
        point(0.25).tap()
        point(0.6).tap()
        let confirm = app.buttons["map.build.confirm"]
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '鋪設軌道'")).firstMatch
        let builder = confirm.appears(within: 10) ? confirm : card
        XCTAssertTrue(builder.appears(within: 10), "No way to build the stretch")
        XCTAssertTrue(builder.becomesHittable(), "The ✓ cannot be tapped")
        builder.tap()
        settle()
        let platform = app.segmentedControls.buttons["車站"].firstMatch
        if !platform.appears(within: 3) || !platform.becomesHittable(within: 1) {
            let controls = app.buttons["controls.toggle"]
            if controls.exists { controls.tap() }
        }
        XCTAssertTrue(platform.appears(within: 10), "No Station mode")
        platform.waitUntilSettled()
        platform.tap()
        let cars = app.steppers["network.platformCars"]
        if cars.appears(within: 5) {
            let more = cars.buttons.element(boundBy: 1)
            for _ in 0..<20 where more.exists && more.isEnabled && more.isHittable {
                more.tap()
            }
        }
        // The platform's site on the stretch, off the map's own buttons.
        let mapButtons = ["map.coverageShortcut", "map.open3D", "縮小", "放大"].map { app.buttons[$0] }
        var siteX = frame.minX + frame.width * 0.425
        while let covering = mapButtons.filter(\.exists).map({ $0.frame.insetBy(dx: -4, dy: -4) })
            .first(where: { $0.contains(CGPoint(x: siteX, y: middle)) }) {
            siteX = covering.minX - 40
        }
        origin.withOffset(CGVector(dx: siteX, dy: middle)).tap()
        XCTAssertTrue(confirm.appears(within: 10), "No ✓ for the platform")
        settle()
        keep("platform-levelling-pill", app)
        confirm.waitUntilSettled()
        confirm.tap()
        settle()
        keep("platform-levelling-layer", app)
    }

    /// Decision 507: the platform mode's layout menu on a double track,
    /// with a place picked, then the menu open (the single-track layouts
    /// greyed with why).
    func testStationLayoutMenu() {
        let app = launch(extra: ["-ui-test-world", "double-platform"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 30), "The world opens")
        map.waitUntilSettled()
        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let platformMode = app.segmentedControls.buttons["車站"].firstMatch
        if !platformMode.appears(within: 10) {
            let controls = app.buttons["controls.toggle"]
            if controls.appears(within: 5), controls.label == "展開控制項" { controls.tap() }
        }
        XCTAssertTrue(platformMode.becomesHittable(within: 10))
        settle()
        keep("station-mode-bar", app)
        platformMode.tap()
        // The station's place, as the map reports it.
        let readout = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(readout.appears(within: 10))
        settle(seconds: 3)
        let xy = (readout.value as? String ?? "").split(separator: ";").first?.split(separator: ",").compactMap { Double($0) } ?? []
        XCTAssertEqual(xy.count, 2)
        guard xy.count == 2 else { return }
        let frame = map.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + xy[0] - app.frame.minX, dy: frame.minY + xy[1] - app.frame.minY)).tap()
        let layout = app.buttons["network.stationLayout"].firstMatch
        XCTAssertTrue(layout.appears(within: 10), "The layout menu shows")
        settle()
        keep("station-layout-card", app)
        XCTAssertTrue(layout.becomesHittable(within: 5))
        layout.tap()
        settle()
        keep("station-layout-menu", app)
    }

    /// Decision 507: the tutorial's step that names the network tool's
    /// Station mode, its card beside the modes.
    func testTutorialStationStep() {
        let app = launch(extra: ["-tutorial-step", "station.mode"])
        defer { app.terminate() }
        let card = app.descendants(matching: .any)["tutorial.card"].firstMatch
        let folded = app.buttons["tutorial.unfold"]
        if !card.appears(within: 60), folded.exists { folded.tap() }
        XCTAssertTrue(card.appears(within: 10), "The tutorial's card shows")
        let mode = app.segmentedControls.buttons["車站"].firstMatch
        if !mode.appears(within: 10), app.buttons["dock.build"].exists { app.buttons["dock.build"].tap() }
        XCTAssertTrue(mode.appears(within: 10), "The Station mode shows")
        settle(seconds: 3)
        keep("tutorial-station-step", app)
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

    /// Decision 468, later: a trace along the Liujia Line on Hsinchu's
    /// real-world map says the line can be bought as it is, for how much,
    /// and its button opens the purchase card. The trace is drawn by the
    /// Debug app's `-ui-test-trace-for-sale` through the tool's own taps.
    func testTracedLineForSale() {
        let app = launch(extra: ["-ui-test-trace-for-sale"])
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        tapButton("newGame.realWorld", in: app, timeout: 60)
        let hsinchu = app.buttons.matching(identifier: "place.tra-hsinchu").firstMatch
        XCTAssertTrue(app.scrollUntilShown(hsinchu, in: app.collectionViews.firstMatch), "Hsinchu is listed")
        hsinchu.waitUntilSettled()
        app.tapMiddle(of: hsinchu)
        tapButton("realWorld.start", in: app, timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The game starts")
        // The trace's hint, its price once laid out, and the pill's button.
        let buy = app.buttons["map.build.buyLine"]
        XCTAssertTrue(buy.appears(within: 60), "The trace runs along a line for sale")
        settle(seconds: 8)
        keep("traced-line-for-sale", app)

        XCTAssertTrue(buy.becomesHittable(within: 5))
        buy.tap()
        settle(seconds: 6)
        keep("traced-line-for-sale-card", app)
    }

    /// Decision 513: a trace along the North-Link Line south of Nan'ao
    /// that no grade reaches says why, with the real line's length and its
    /// ends' heights. For the screenshot review of its pull request. The
    /// trace is drawn by the Debug app's `-ui-test-trace-refused` through
    /// the tool's own taps.
    func testTraceNoGradeReaches() {
        let app = launch(extra: ["-ui-test-trace-refused"])
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        tapButton("newGame.realWorld", in: app, timeout: 60)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 30), "The picker opens")
        search.tap()
        search.typeText("南澳")
        let nanao = app.buttons["station.tra_sched|南澳"]
        XCTAssertTrue(nanao.appears(within: 30), "Nan'ao is found")
        nanao.waitUntilSettled()
        app.tapMiddle(of: nanao)
        // While the search is on, the toolbar with Build Here is hidden:
        // the search's own cancel ends it, the map staying on Nan'ao.
        if !app.buttons["realWorld.start"].appears(within: 3) {
            // The one on the search field's row, not the picker's own Cancel.
            let ends = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "關閉", "Cancel", "Close"]))
            let row = search.frame
            let end = ends.allElementsBoundByIndex.first { abs($0.frame.midY - row.midY) < row.height }
            XCTAssertNotNil(end, "The search can be ended")
            end?.tap()
        }
        tapButton("realWorld.start", in: app, timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The game starts")
        let refusal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "坡度上限 40‰")).firstMatch
        XCTAssertTrue(refusal.appears(within: 120), "The trace is refused, and says why")
        settle(seconds: 8)
        keep("trace-no-grade-reaches", app)
    }

    /// Decision 521's third sequel: a double trace from Luodong to
    /// Dongshan, and the same trace joining track laid on its middle third,
    /// each previewed as one way (no second line beside it, no darker band
    /// where the glows meet). For the screenshot review of its pull
    /// request; drawn by the Debug app through the tool's own taps.
    func testTracePreviewDouble() {
        tracePreviewShot(argument: "-ui-test-trace-double", station: "羅東", search: "羅東", name: "trace-preview-double")
    }

    func testTracePreviewJoined() {
        tracePreviewShot(argument: "-ui-test-trace-joined", station: "羅東", search: "羅東", name: "trace-preview-joined")
    }

    private func tracePreviewShot(argument: String, station: String, search text: String, name: String) {
        let app = launch(extra: [argument])
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        tapButton("newGame.realWorld", in: app, timeout: 60)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.appears(within: 30), "The picker opens")
        search.tap()
        search.typeText(text)
        let place = app.buttons["station.tra_sched|\(station)"]
        XCTAssertTrue(place.appears(within: 30), "\(station) is found")
        place.waitUntilSettled()
        app.tapMiddle(of: place)
        if !app.buttons["realWorld.start"].appears(within: 3) {
            let ends = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "關閉", "Cancel", "Close"]))
            let row = search.frame
            let end = ends.allElementsBoundByIndex.first { abs($0.frame.midY - row.midY) < row.height }
            XCTAssertNotNil(end, "The search can be ended")
            end?.tap()
        }
        tapButton("realWorld.start", in: app, timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The game starts")
        XCTAssertTrue(app.buttons["map.build.confirm"].appears(within: 120), "The trace is previewed")
        // Close enough to see the glow: the Debug app keeps the place in
        // the middle every 4 s for a minute.
        // By its label, which the app shows in Chinese here.
        let zoomIn = app.buttons.matching(NSPredicate(format: "label IN %@", ["Zoom in", "放大"])).firstMatch
        XCTAssertTrue(zoomIn.becomesHittable(within: 10), "The zoom-in button")
        for _ in 0..<4 {
            zoomIn.tap()
            settle(seconds: 1)
        }
        settle(seconds: 10)
        keep(name, app)
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

    /// The selection card of a station on a phone on its side (a player's
    /// report: its summary was cut short with "…"): a station of the
    /// high-speed demo picked from its tag, the card in the side panel with
    /// the platforms and who waits on lines of their own. For the
    /// screenshot review of the pull request that fixed it, not the website.
    func testStationCard() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.highSpeed", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 600), "The demo is built and opens")
        settle(seconds: 8)
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 1) {
            for _ in 0..<2 {
                zoomIn.tap()
                settle(seconds: 1)
            }
        }
        // Yunlin's mark, two steps in on the demo's opening view (run
        // 41163857917 showed it at about 39 % across and 36 % down; the
        // station tags are not stations' marks).
        let map = app.descendants(matching: .any)["map"].firstMatch
        let status = app.descendants(matching: .any)["inspector.status"].firstMatch
        for offset in [CGVector(dx: 0.3875, dy: 0.36), CGVector(dx: 0.385, dy: 0.35), CGVector(dx: 0.39, dy: 0.37)] {
            map.coordinate(withNormalizedOffset: offset).tap()
            settle(seconds: 2)
            if status.exists, status.label.hasPrefix("車站") { break }
        }
        // The card is in the side panel, which a tap on a station leaves
        // closed (run 41165522130): open it.
        let controls = app.buttons["controls.toggle"]
        if controls.appears(within: 5), controls.becomesHittable(within: 2) {
            controls.tap()
        }
        settle(seconds: 3)
        keep("station-card", app)
        XCTAssertTrue(status.appears(within: 5), "The selection card shows")
    }

    /// Decision 532: a real-world station's card with Taiwan Railway's
    /// real next trains ("臺鐵 下一班：…"), a station of the real-world
    /// demo by day, its "Real Station" section under the surroundings.
    /// For the screenshot review of the pull request that made them, not
    /// the website.
    func testRealStationNextTrains() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 60), "The demo starts")
        waitForClock(from: 7, before: 20, in: app)
        pauseTheClock(in: app)
        settle(seconds: 3)
        // Where the stations are (`map.stations`, "x,y;x,y" in the map's
        // points), one clear of the map's buttons.
        let readout = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(readout.appears(within: 10), "The stations' places")
        let clear = map.frame.insetBy(dx: map.frame.width * 0.2, dy: map.frame.height * 0.2)
        let points = (readout.value as? String ?? "").split(separator: ";").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return nil }
            return CGPoint(x: map.frame.minX + xy[0], y: map.frame.minY + xy[1])
        }.filter { clear.contains($0) }
        XCTAssertFalse(points.isEmpty, "A station clear of the map's buttons")
        // A hold selects the station even when a train is over it.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: points[0].x - app.frame.minX, dy: points[0].y - app.frame.minY))
            .press(forDuration: 1)
        tapButton("station.jump", in: app)
        tapButton("station.jump.area", in: app)
        settle()
        let next = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "臺鐵 下一班")).firstMatch
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.frame.minX > app.frame.midX }
        let shown = app.dragUntilWhollyOnScreen(next, in: list)
        settle()
        keep("real-station-next-trains", app)
        XCTAssertTrue(shown, "Taiwan Railway's next trains come into view")
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
    /// second morning: the short list, its lines first on a phone on its
    /// side (decision 498), a line's own page, and the whole network's page.
    func testLinesListAndLinePage() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        settle(seconds: 2)
        keep("lines-list", app)

        // The form makes a row only once it scrolls in. The list runs
        // under the bar (decision 498: no heading over the first line), and
        // a tap on a row there lands on the bar (run 41081046632).
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.trainsRow.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row, in: list, below: bar.frame.maxY), "A line's row shows")
        // A tap on a list still moving after the drag only stops it.
        row.waitUntilSettled()
        row.tap()
        XCTAssertTrue(app.collectionViews["line.detail"].appears(within: 10), "The line's page opens")
        settle(seconds: 2)
        keep("line-page", app)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.collectionViews["line.detail"].disappears(within: 10), "Back to the list")
        // Decision 498: on a phone on its side the network's row is under
        // the lines, where `dragUntilWhollyOnScreen` looks for it.
        let network = app.buttons["lines.network"]
        let back = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let top = app.linesListTop(under: bar)
        XCTAssertTrue(app.dragUntilWhollyOnScreen(network, in: back, below: top), "The whole network's row shows")
        network.tap()
        settle(seconds: 2)
        keep("lines-network", app)
    }

    /// Decision 524: a line's page with realistic operation shows its last
    /// seven days' punctuality, Taiwan Railway's past year beside it.
    func testLineWeeklyPunctuality() {
        let app = launch(extra: ["-screenshot-scene", "punctuality"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        settle(seconds: 2)
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.trainsRow.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row, in: list, below: bar.frame.maxY), "A line's row shows")
        row.waitUntilSettled()
        row.tap()
        let page = app.collectionViews["line.detail"]
        XCTAssertTrue(page.appears(within: 10), "The line's page opens")
        let weekly = app.descendants(matching: .any)["line.weeklyPunctuality"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(weekly, in: page, below: app.navigationBars.firstMatch.frame.maxY), "The week's punctuality shows")
        weekly.waitUntilSettled()
        settle(seconds: 1)
        keep("line-weekly-punctuality", app)
    }

    /// Decision 524, later: the economy panel shows every passenger line's
    /// last seven days' punctuality, Taiwan Railway's past year beside it.
    func testCompanyWeeklyPunctuality() {
        let app = launch(extra: ["-screenshot-scene", "punctuality"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()
        tapButton("entry.economy", in: app)
        let bar = app.navigationBars["經濟明細"].firstMatch
        if !bar.appears(within: 10) {
            tapButton("entry.economy", in: app)
        }
        XCTAssertTrue(bar.appears(within: 10), "The economy panel opens")
        bar.waitUntilSettled()
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let weekly = app.descendants(matching: .any)["economy.weeklyPunctuality"].firstMatch
        // Swipe, not drag: the rows above it are mostly fare controls
        // (`currencyShots`).
        for _ in 0..<30 where !weekly.exists {
            list?.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.dragUntilWhollyOnScreen(weekly, in: list, below: bar.frame.maxY, clearOf: .button),
                      "The company's week of punctuality shows")
        weekly.waitUntilSettled()
        settle(seconds: 1)
        keep("company-weekly-punctuality", app)
    }

    /// Decision 512: a line's page opens its train roster, which lets the
    /// trains be arranged: the roster of one line, then Arrange.
    func testTrainRosterOfALine() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        settle(seconds: 2)
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.trainsRow.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row, in: list, below: bar.frame.maxY), "A line's row shows")
        row.waitUntilSettled()
        row.tap()
        let page = app.collectionViews["line.detail"]
        XCTAssertTrue(page.appears(within: 10), "The line's page opens")
        // The line's trains, where trains are sent out, as before the
        // roster's row was added below them (compare with `line-page`).
        settle(seconds: 2)
        keep("roster-line-page-trains", app)
        let open = app.buttons["line.trainRoster"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(open, in: page, below: app.navigationBars.firstMatch.frame.maxY), "The roster's button shows")
        open.waitUntilSettled()
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trainRoster"].firstMatch.appears(within: 10), "The roster opens")
        settle(seconds: 3)
        keep("roster-line", app)

        app.buttons["trainRoster.arrange"].tap()
        XCTAssertTrue(app.staticTexts["trainRoster.arrangeHint"].appears(within: 5), "Arrange says how")
        settle(seconds: 2)
        keep("roster-arrange", app)
        // Every line's trains, to drag one onto another line's row.
        let all = app.segmentedControls["trainRoster.lines"].buttons["全部路線"]
        if all.appears(within: 3) {
            all.tap()
            settle(seconds: 3)
            keep("roster-arrange-all", app)
        }
    }

    /// Decision 512: sending trains out is as it was. The same test runs on
    /// `main` and on the pull request, for the two side by side: a line's
    /// page at its trains and their dispatch, then a train's card.
    func testDispatchFlowAsBefore() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 120), "The scene opens")
        settle()

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        settle(seconds: 2)
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.trainsRow.")).firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row, in: list, below: bar.frame.maxY), "A line's row shows")
        row.waitUntilSettled()
        row.tap()
        let page = app.collectionViews["line.detail"]
        XCTAssertTrue(page.appears(within: 10), "The line's page opens")
        settle(seconds: 2)
        // A line with trains sends more out under "Now"; the catalog
        // button is only on a line without trains.
        let now = app.staticTexts["line.headway.now"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(now, in: page, below: app.navigationBars.firstMatch.frame.maxY), "The line's dispatch shows")
        now.waitUntilSettled()
        settle(seconds: 2)
        keep("dispatch-line-page", app)
        let done = app.navigationBars.firstMatch.buttons["完成"]
        if done.exists, done.isHittable {
            done.tap()
            settle()
        }

        // A train brought under the camera from the fleet, then tapped.
        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        XCTAssertTrue(fleet.appears(within: 5))
        fleet.tap()
        let follow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fleet.follow.")).firstMatch
        XCTAssertTrue(follow.appears(within: 5), "A train to follow")
        follow.tap()
        let unfollow = app.buttons["train.unfollow"]
        XCTAssertTrue(unfollow.appears(within: 5))
        unfollow.tap()
        _ = unfollow.disappears(within: 5)
        app.buttons["tool.select"].tap()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let card = app.buttons["inspector.train.timetable"]
        guard card.appears(within: 5) else {
            keep("debug-dispatch-card", app)
            return
        }
        settle(seconds: 2)
        keep("dispatch-train-card", app)
        // The card's buttons are under its trip on a phone on its side:
        // drag the card, not the map beside it, until they show.
        let column = card.frame.midX
        _ = app.dragUntilWhollyOnScreen(app.buttons["inspector.train.fleet"], drags: 4, at: column)
        settle(seconds: 2)
        keep("dispatch-train-buttons", app)
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
        // By the light of day, the stars over the island. Decision 510
        // hides the sights from as far out as the whole island, so in a
        // step or two until they show.
        waitForClock(from: 9, before: 17, in: app)
        let zoomIn = app.buttons["放大"]
        let sight = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.sight.'")).firstMatch
        for _ in 0..<4 where !sight.exists && zoomIn.exists && zoomIn.isEnabled {
            zoomIn.tap()
            settle(seconds: 2)
        }
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

        // A bubble opens its station's panel at the freight group (decisions
        // 184 and 477; the map's tag, and its pencil, show only with no
        // panel open); the toolbar's menu goes up to the riders.
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.appears(within: 30), "The stations short of materials show")
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        let materials = app.descendants(matching: .any)["station.materials"].firstMatch
        XCTAssertTrue(materials.appears(within: 10), "A tap on a bubble opens its station's panel")
        settle()
        keep("chart-station-panel", app)
        tapButton("station.jump", in: app)
        tapButton("station.jump.riders", in: app)
        settle()
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

    /// Drags `list` back towards its top until `element` exists below
    /// `top`, for `dragUntilWhollyOnScreen`, which looks further down for
    /// an element that does not exist. A panel beside the map on a phone
    /// on its side: `swipeDown()` on the list begins at its middle, on the
    /// economy's donut or on a line's row, and moved neither list in 12
    /// swipes (run 41026860196); held drags down the leading margin below
    /// `top`, as `dragUntilWhollyOnScreen` makes, do.
    private func dragBack(to element: XCUIElement, in list: XCUIElement?, below top: CGFloat, in app: XCUIApplication) {
        guard let list, list.exists else { return }
        let area = list.frame
        let rows = CGRect(x: area.minX, y: max(area.minY, top) + 8, width: area.width, height: area.maxY - 16 - max(area.minY, top))
        guard rows.height > 40 else { return }
        let x = (area.minX + 8 - app.frame.minX) / app.frame.width
        func point(_ y: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: (rows.minY + rows.height * y - app.frame.minY) / app.frame.height))
        }
        for _ in 0..<30 where !(element.exists && element.frame.minY >= top) {
            point(0.15).press(forDuration: 0.1, thenDragTo: point(0.85), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// One tap on the zoom-in button, when the map has it.
    /// Decision 502: the saves list with one row per game, choosing saves
    /// to delete and the warning before they go, and a save's earlier
    /// versions. For the screenshot review of the pull request that made
    /// them, not the website.
    func testSavesListOneRowPerGame() {
        let app = launch(extra: ["-sample-saves"])
        defer { app.terminate() }
        let saves = app.buttons["start.saves"]
        XCTAssertTrue(saves.appears(within: 30), "The start screen shows Saves")
        // On a phone on its side Saves lies below the fold of the start
        // screen's column: drag that column at the button's own x
        // (`StartSaveFlowSmokeTests.testAnUnreadableSaveCanBeDeleted`).
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<6 where !saves.isHittable {
            let x = saves.frame.midX - app.frame.minX
            origin.withOffset(CGVector(dx: x, dy: app.frame.height * 0.75))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: app.frame.height * 0.35)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        saves.tap()
        let select = app.buttons["saves.select"]
        XCTAssertTrue(select.appears(within: 10), "The list offers Select")
        settle()
        keep("saves-list", app)

        // A row's earlier versions, from its "⋯" menu.
        let menus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saves.menu.save-"))
        let versionsChoice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saves.versions.")).firstMatch
        for index in 0..<menus.count where !versionsChoice.exists {
            let menu = menus.element(boundBy: index)
            guard menu.isHittable else { continue }
            menu.tap()
            if !versionsChoice.appears(within: 2) { app.tap() }
        }
        if versionsChoice.exists {
            settle(seconds: 1)
            keep("saves-row-menu", app)
            versionsChoice.tap()
            let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saves.version.")).firstMatch
            XCTAssertTrue(version.appears(within: 10), "The earlier versions are offered")
            settle(seconds: 1)
            keep("saves-earlier-versions", app)
            let cancel = app.buttons["取消"].firstMatch
            if cancel.exists { cancel.tap() } else { app.tap() }
            XCTAssertTrue(version.disappears(within: 10))
        }

        select.tap()
        let selectAll = app.buttons["saves.selectAll"]
        XCTAssertTrue(selectAll.appears(within: 10), "Choosing offers Select All")
        settle(seconds: 1)
        keep("saves-select", app)
        selectAll.tap()
        settle(seconds: 1)
        keep("saves-select-all", app)
        tapButton("saves.deleteSelected", in: app)
        let confirm = app.buttons["saves.deleteSelected.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(within: 10), "Deleting warns first")
        settle(seconds: 1)
        keep("saves-delete-warning", app)
        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.exists)
        cancel.tap()
        XCTAssertTrue(confirm.disappears(within: 10), "Cancel keeps the saves")
    }

    private func zoomInOnce(_ app: XCUIApplication) {
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 5), zoomIn.becomesHittable(within: 3) {
            zoomIn.tap()
            settle(seconds: 1)
        }
    }

    /// Lesson 1's first card on a phone on its side (decision 498): its
    /// explanation ends on a whole line, the goal not cut in half.
    func testLessonCard() {
        let app = launch()
        defer { app.terminate() }
        let lessons = app.buttons["start.lessons"]
        XCTAssertTrue(lessons.appears(within: 15), "The start screen shows Lessons")
        lessons.waitUntilSettled()
        lessons.tap()
        let first = app.buttons["lesson.1.start"]
        if !first.appears(within: 5), lessons.exists {
            lessons.waitUntilSettled()
            lessons.tap()
        }
        XCTAssertTrue(first.appears(within: 10), "Lesson 1 is listed")
        XCTAssertTrue(first.becomesHittable(), "Lesson 1's Start can be tapped")
        first.tap()
        let card = app.descendants(matching: .any)["tutorial.card"].firstMatch
        XCTAssertTrue(card.appears(within: 60), "The lesson's card shows")
        settle(seconds: 3)
        keep("lesson-card", app)
    }

    /// Decision 508, for its screenshot review: a new blank-map game with
    /// no line, the station master's offer of the tutorial, the lines
    /// panel saying what is missing, and after "I'll do it myself" the
    /// station master naming Build with its ring.
    func testFirstLineGuide() {
        let app = launch(extra: ["-show-first-line-offer"])
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 15), "The start screen shows New Game")
        newGame.tap()
        app.chooseBlankMap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The new game opens")
        let offer = app.descendants(matching: .any)["stationMaster.offer"].firstMatch
        XCTAssertTrue(offer.appears(within: 15), "The station master offers the tutorial")
        settle()
        keep("first-line-offer", app)

        app.buttons["entry.lines"].tap()
        let need = app.descendants(matching: .any)["lines.firstLine"].firstMatch
        XCTAssertTrue(need.appears(within: 10), "The lines panel says what is missing")
        settle()
        keep("first-line-lines-empty", app)
        let go = app.buttons["lines.firstLine.go"]
        XCTAssertTrue(go.becomesHittable(), "Its button can be tapped")
        go.tap()
        XCTAssertTrue(app.buttons["tool.network"].appears(within: 10), "It opens Build")
        app.buttons["dock.build"].tap()

        let myself = app.buttons["stationMaster.offer.self"]
        XCTAssertTrue(myself.becomesHittable(), "I'll do it myself can be tapped")
        myself.tap()
        XCTAssertTrue(app.descendants(matching: .any)["stationMaster.bubble"].firstMatch.appears(within: 10), "The first step is said")
        settle()
        keep("first-line-guide-build", app)
    }

    /// The game menu on a phone on its side, its rows side by side icons
    /// alone (decision 498), and the settings' Rules row, which says
    /// where the rules are chosen.
    func testGameMenuAndRules() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()
        let menu = app.buttons["hud.menu"]
        menu.waitUntilSettled()
        menu.tap()
        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.appears(within: 30), "The menu opens")
        settings.waitUntilSettled()
        settle(seconds: 1)
        keep("game-menu", app)

        // Touched at its frame's middle, as SettingsUITests does: the
        // menu's items have no activation point of their own.
        let frame = settings.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.switches["settings.music"].appears(within: 10), "The settings open")
        let rules = app.descendants(matching: .any)["settings.rules"].firstMatch
        XCTAssertTrue(scrollScreen(to: rules, in: app), "The Rules row shows")
        settle(seconds: 1)
        keep("settings-rules", app)
    }

    /// Decision 497 (P2-6): Back to Start when the autosave cannot be
    /// written asks whether to leave without saving, and leaving reaches
    /// the start screen.
    func testLeavingWithoutSaving() {
        let app = launch(extra: ["-screenshot-scene", "freight", "-unwritable-saves"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()
        let menu = app.buttons["hud.menu"]
        menu.waitUntilSettled()
        menu.tap()
        let backToStart = app.buttons["menu.backToStart"]
        XCTAssertTrue(backToStart.appears(within: 30), "The menu opens")
        backToStart.waitUntilSettled()
        // Touched at its frame's middle, as in testGameMenuAndRules.
        let frame = backToStart.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        // An alert's button is in the tree twice.
        let leave = app.buttons["menu.leaveWithoutSaving"].firstMatch
        XCTAssertTrue(leave.appears(within: 60), "The question to leave without saving")
        settle(seconds: 1)
        keep("leave-without-saving", app)
        leave.tap()
        XCTAssertTrue(app.descendants(matching: .any)["start.brand"].firstMatch.appears(within: 30), "The start screen")
    }

    private func launch(extra: [String] = [], english: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        let language = english ? ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] : ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launchArguments = ["-ui-testing"] + language + extra
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
