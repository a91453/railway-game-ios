import XCTest

/// Screenshots for the game's website (decision 165), in Traditional
/// Chinese on a phone on its side. Run only by `website-screenshots.yml`,
/// never by the gate or the full lane: each test opens a screen and keeps
/// what it shows as an attachment the workflow exports. They check only
/// that the screen they photograph is there.
@MainActor
final class WebsiteScreenshotTests: XCTestCase {
    /// Decision 536: a train of a real line bought, the Neiwan Line's and
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
            waitForPicture(timeout: 150)
            settle(seconds: 5)
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

    /// Decision 564: the Wenhu Line bought on a real map of Taipei and run
    /// on to 07:40, a train near its middle followed: on the 2D map and in
    /// 3D, each way's trains on the track to their right, as the real
    /// Taipei Metro's run. For the screenshot review of the pull request
    /// that put them there.
    func testWenhuRunsOnTheRight() {
        // The buying and the morning take most of it (the workflow allows
        // up to 30 minutes a test).
        executionTimeAllowance = 1_500
        let app = launch(extra: ["-screenshot-scene", "wenhu", "-screenshot-buy-real", "trtc:BR", "-screenshot-follow-bought", "trtc:BR",
                                 "-map3D.quality", "saving"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        // The Debug app on a Simulator buys the line and runs the morning
        // on to 07:40 for minutes, its main thread busy for a minute at a
        // time, longer than a UI query waits: the test asks nothing of it
        // for six minutes first.
        Thread.sleep(forTimeInterval: 360)
        XCTAssertTrue(app.descendants(matching: .any)["train.stock"].firstMatch.appears(within: 900), "The line is bought and its train followed")
        // The bought card first.
        let done = app.buttons["acquired.done"]
        if done.appears(within: 10), done.becomesHittable(within: 10) {
            done.tap()
            XCTAssertTrue(done.disappears(within: 60), "The bought card closes")
        }
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 5) {
            for _ in 0..<6 {
                zoomIn.tap()
                settle(seconds: 1)
            }
        }
        settle(seconds: 3)
        keep("wenhu-right-2d", app)

        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        waitForPicture(timeout: 150)
        settle(seconds: 5)
        keep("wenhu-right-3d", app)
    }

    /// Decision 602: the Wenhu Line bought on a real map of Taipei at
    /// 05:30, its trains in its two depots, on the 3D map over Muzha
    /// Depot past Taipei Zoo and over Neihu Depot past Nangang Exhibition
    /// Center, from the side and from higher up. For the screenshot review
    /// of the pull request that laid the depots as the real yards.
    func testWenhuDepotMuzha() { shootRealDepot("wenhu-depot-muzha", at: "25.000776,121.586414") }
    func testWenhuDepotNeihu() { shootRealDepot("wenhu-depot-neihu", at: "25.059900,121.619920") }

    /// Decision 621: the Kaohsiung Circular Light Rail bought on a real map
    /// of Kaohsiung, its trains in its depot, laid as a strip beside the
    /// line as the real one, on the 3D map from the side and from higher
    /// up. For the screenshot review of the pull request that laid it.
    func testKaohsiungLightRailDepot() {
        shootRealDepot("klrt-depot", at: "22.609000,120.325500", scene: "klrt", line: "krtc:C")
    }

    private func shootRealDepot(_ name: String, at place: String, scene: String = "wenhu", line: String = "trtc:BR") {
        // The buying takes minutes in the Debug app (the workflow allows up
        // to 30 minutes a test).
        executionTimeAllowance = 1_500
        for (shot, view) in [("side", "450,200,55"), ("high", "900,200,20")] {
            let app = launch(extra: ["-screenshot-scene", scene, "-screenshot-buy-real", line, "-screenshot-3d-view", view,
                                     "-screenshot-3d-at", place, "-map3D.quality", "high"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            // The Debug app's main thread is busy buying for a minute at a
            // time, longer than a UI query waits.
            Thread.sleep(forTimeInterval: 180)
            let done = app.buttons["acquired.done"]
            XCTAssertTrue(done.appears(within: 600), "The line is bought")
            if done.becomesHittable(within: 10) {
                done.tap()
                XCTAssertTrue(done.disappears(within: 60), "The bought card closes")
            }
            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 10))
            XCTAssertTrue(open3D.becomesHittable(within: 10))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
            settle(seconds: 12)
            keep("\(name)-\(shot)", app)
            app.terminate()
        }
    }

    /// Decision 625: the real stations' exterior studies on the 3D map,
    /// in the demo's real lines laid round TRA Taichung (the old station
    /// beside the new: one building each), TRA Hsinchu, TRA Banqiao, HSR
    /// Taoyuan with the Airport MRT's A18, HSR Taichung with TRA
    /// Xinwuri, and HSR Zuoying with TRA Xinzuoying, by day (09:30) and
    /// by night (19:30), close over the platforms and trains. For the screenshot review of the pull request that stood
    /// them there.
    func testStationExteriorTaichung() { shootStationExterior("exteriorTaichung", lay: "24.115,120.660,24.160,120.715") }
    func testStationExteriorHsinchu() { shootStationExterior("exteriorHsinchu", lay: "24.775,120.945,24.828,121.000") }
    func testStationExteriorBanqiao() { shootStationExterior("exteriorBanqiao", lay: "24.990,121.440,25.040,121.490") }
    func testStationExteriorTaoyuanHSR() { shootStationExterior("exteriorTaoyuanHSR", lay: "24.990,121.190,25.040,121.240") }
    func testStationExteriorTaichungHSR() { shootStationExterior("exteriorTaichungHSR", lay: "23.870,120.570,24.130,120.640") }
    func testStationExteriorZuoying() { shootStationExterior("exteriorZuoying", lay: "22.670,120.270,22.940,120.330") }

    private func shootStationExterior(_ scene: String, lay view: String) {
        // Laying the lines and running half an hour take minutes in the
        // Debug app (the workflow allows up to 30 minutes a test).
        executionTimeAllowance = 1_500
        // Each study's OSM origin, but the HSR Taichung one: its platforms'
        // middle, 180 m north-east (the origin is by the high-rises).
        let places = ["exteriorTaichung": "24.13732601,120.68671829", "exteriorHsinchu": "24.80160443,120.97165154", "exteriorBanqiao": "25.0144511,121.4640451",
                      "exteriorTaoyuanHSR": "25.01347985,121.214539", "exteriorTaichungHSR": "24.11248,120.61598", "exteriorZuoying": "22.68726485,120.3074864"]
        for (hour, suffix) in [("day", ""), ("night", "Night")] {
            let app = launch(extra: ["-screenshot-scene", scene + suffix, "-screenshot-lay-demo", view, "-screenshot-3d-view", "380,215,40",
                                     "-screenshot-3d-at", places[scene] ?? "", "-map3D.quality", "high",
                                     // Decision 625 續: no frame rate or gesture hint over the stations.
                                     "-screenshot-3d-clean"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            // The Debug app's main thread is busy laying the lines for a
            // minute at a time, longer than a UI query waits.
            Thread.sleep(forTimeInterval: 240)
            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 600))
            XCTAssertTrue(open3D.becomesHittable(within: 300))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
            settle(seconds: 12)
            keep("station-exterior-\(scene.dropFirst("exterior".count).lowercased())-\(hour)", app)
            app.terminate()
        }
    }

    /// Decision 603: the Xiaobitan Branch Line bought on a real map of
    /// New Taipei and run on to 07:40, its one train followed: on the 2D
    /// map and in 3D, a single track with one platform track at each
    /// station, as the real line's. For the screenshot review of the pull
    /// request that laid it so.
    func testXiaobitanSingleTrack() {
        executionTimeAllowance = 1_500
        let app = launch(extra: ["-screenshot-scene", "xiaobitan", "-screenshot-buy-real", "trtc:G_XBT", "-screenshot-follow-bought", "trtc:G_XBT",
                                 "-map3D.quality", "saving"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        // As the Wenhu Line's: the Debug app buys the line and runs the
        // morning with its main thread busy for a minute at a time.
        Thread.sleep(forTimeInterval: 240)
        XCTAssertTrue(app.descendants(matching: .any)["train.stock"].firstMatch.appears(within: 900), "The line is bought and its train followed")
        let done = app.buttons["acquired.done"]
        if done.appears(within: 10), done.becomesHittable(within: 10) {
            done.tap()
            XCTAssertTrue(done.disappears(within: 60), "The bought card closes")
        }
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 5) {
            for _ in 0..<5 {
                zoomIn.tap()
                settle(seconds: 1)
            }
        }
        settle(seconds: 3)
        keep("xiaobitan-single-2d", app)

        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        waitForPicture(timeout: 150)
        settle(seconds: 5)
        keep("xiaobitan-single-3d", app)
    }

    /// Decision 605 (continued): the Taoyuan Airport MRT bought as it was
    /// before its expresses came, at 02:00 with its last trains in: its
    /// panel's 「照真實改建」, the card saying what it lays and what it
    /// costs, and Chang Gung Memorial Hospital station after it with four
    /// tracks, a loop outside each platform. For the screenshot review of
    /// the pull request that made the rebuild work.
    func testTaoyuanAirportRebuild() {
        executionTimeAllowance = 1_500
        let app = launch(extra: ["-screenshot-scene", "tymcRebuild", "-screenshot-buy-real-before", "tymc:A"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let done = app.buttons["acquired.done"]
        XCTAssertTrue(done.appears(within: 600), "The line is bought")
        settle(seconds: 3)
        keep("tymc-rebuild-before-2d", app)
        if done.becomesHittable(within: 10) {
            done.tap()
            XCTAssertTrue(done.disappears(within: 60), "The bought card closes")
        }

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        XCTAssertTrue(app.navigationBars["路線"].firstMatch.appears(within: 10), "The lines panel opens")
        let rebuild = app.buttons["line.rebuildAsReal"]
        if !rebuild.appears(within: 5) {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'line.row.'")).firstMatch
            XCTAssertTrue(row.appears(within: 10), "The bought line is listed")
            row.tap()
        }
        for _ in 0..<6 where !(rebuild.exists && rebuild.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(rebuild.becomesHittable(within: 10), "The line's panel offers the rebuild")
        settle(seconds: 2)
        keep("tymc-rebuild-panel", app)
        rebuild.tap()
        let confirm = app.buttons["line.rebuildAsReal.confirm"]
        XCTAssertTrue(confirm.appears(within: 30), "The card offers to rebuild")
        settle(seconds: 2)
        keep("tymc-rebuild-card", app)
        confirm.tap()
        XCTAssertTrue(rebuild.disappears(within: 60), "Nothing is left to rebuild")
        settle(seconds: 2)
        keep("tymc-rebuild-panel-after", app)

        let close = app.navigationBars.buttons["完成"].firstMatch
        XCTAssertTrue(close.becomesHittable(within: 10), "The panel can be closed")
        close.tap()
        XCTAssertTrue(close.disappears(within: 10), "The panel closes")
        settle(seconds: 5)
        keep("tymc-rebuild-after-2d", app)
    }

    /// Decision 535 (continued, KLRT): the Kaohsiung Circular Light Rail
    /// on a real map of Kaohsiung: its purchase card (round the ring, no
    /// terminal named), the card once bought, then run on to 07:40 with a
    /// train followed, on the 2D map and in 3D, its CAF and Citadis trains
    /// going round each way. For the screenshot review of the pull request
    /// that put it on sale.
    func testKaohsiungLightRailRing() {
        executionTimeAllowance = 1_700
        do {
            let app = launch(extra: ["-screenshot-scene", "klrt", "-screenshot-offer-real", "krtc:C"])
            defer { app.terminate() }
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            let buy = app.buttons["acquire.buy"]
            XCTAssertTrue(buy.appears(within: 300), "The purchase card opens")
            // The card shows the price only once the ring is laid out and
            // priced, when its buy button is enabled.
            let priced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: buy)
            XCTAssertEqual(XCTWaiter().wait(for: [priced], timeout: 300), .completed, "The ring is priced")
            settle(seconds: 3)
            keep("klrt-offer", app)
        }
        let app = launch(extra: ["-screenshot-scene", "klrt", "-screenshot-buy-real", "krtc:C", "-screenshot-follow-bought", "krtc:C",
                                 "-map3D.quality", "saving"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        // As the Wenhu Line's: the Debug app buys the line and runs the
        // morning with its main thread busy for a minute at a time.
        Thread.sleep(forTimeInterval: 300)
        XCTAssertTrue(app.descendants(matching: .any)["train.stock"].firstMatch.appears(within: 900), "The line is bought and its train followed")
        let done = app.buttons["acquired.done"]
        if done.appears(within: 10), done.becomesHittable(within: 10) {
            keep("klrt-acquired", app)
            done.tap()
            XCTAssertTrue(done.disappears(within: 60), "The bought card closes")
        }
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 5) {
            for _ in 0..<5 {
                zoomIn.tap()
                settle(seconds: 1)
            }
        }
        settle(seconds: 3)
        keep("klrt-ring-2d", app)

        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        waitForPicture(timeout: 150)
        settle(seconds: 5)
        keep("klrt-ring-3d", app)
    }

    /// Decision 606 (IDLEREAL): the idle mode on a real map with nothing
    /// of the player's follows a real timetable's train on the 3D map, its
    /// name and where it goes faint in the top corner, gone a few seconds
    /// later. For the screenshot review of the pull request that added it,
    /// not the website. The train is the director's random pick: one in a
    /// tunnel is passed over, so it may take a few tries.
    func testIdleModeFollowsARealTrain() {
        executionTimeAllowance = 1_500
        let app = launch(extra: ["-screenshot-scene", "xiaobitan", "-map3D.quality", "saving"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle()
        let menu = app.buttons["hud.menu"]
        menu.waitUntilSettled()
        menu.tap()
        let ambient = app.buttons["menu.ambient"]
        XCTAssertTrue(ambient.appears(within: 30), "The menu opens")
        ambient.waitUntilSettled()
        settle(seconds: 1)
        // Touched at its frame's middle, as testGameMenuAndRules does.
        let frame = ambient.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["ambient.curtain"].firstMatch.appears(within: 10), "The idle mode starts")
        let corner = app.staticTexts["ambient.realTrain"]
        XCTAssertTrue(corner.appears(within: 1_200), "A real train is followed and named")
        settle(seconds: 1)
        keep("idle-real-train", app)
        XCTAssertTrue(corner.disappears(within: 30), "Its name fades")
        settle(seconds: 2)
        keep("idle-real-train-later", app)
    }

    /// Decision 566: the new-train card, the Puyuma's with another
    /// waiting ("Skip all"), then the EMU3000's, and in English the 700T's.
    /// For the screenshot review of the pull request that added it.
    func testNewTrainArrivalCard() {
        let app = launch(extra: ["-screenshot-scene", "acquired", "-screenshot-new-train", "puyuma,emu3000"])
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let welcome = app.buttons["newTrain.welcome"]
        XCTAssertTrue(welcome.appears(within: 30), "The card shows")
        XCTAssertTrue(welcome.becomesHittable(within: 10))
        settle()
        keep("new-train-puyuma", app)
        welcome.tap()
        XCTAssertTrue(app.staticTexts["newTrain.title"].firstMatch.appears(within: 10))
        settle()
        keep("new-train-emu3000", app)
        app.buttons["newTrain.skip"].tap()
        XCTAssertTrue(app.buttons["newTrain.welcome"].disappears(within: 10), "Skip closes it")
        app.terminate()

        let english = launch(extra: ["-screenshot-scene", "acquired", "-screenshot-new-train", "highSpeed"], english: true)
        defer { english.terminate() }
        XCTAssertTrue(english.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        XCTAssertTrue(english.buttons["newTrain.welcome"].appears(within: 30), "The card shows")
        settle()
        keep("new-train-700t-english", english)
    }

    /// Decision 538 (continued): a train of a bought real line followed on
    /// the 2D map, close up: its cars along the curves of the Danhai light
    /// rail and the Neiwan Line, not swung straight off them. For the
    /// screenshot review of the pull request that laid them so.
    func testTrainCarsOnCurves2D() {
        for (real, name) in [("ntdlrt:V", "danhai"), ("tra:NEIWAN", "neiwan")] {
            let app = launch(extra: ["-screenshot-scene", "acquired", "-screenshot-follow-bought", real])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            XCTAssertTrue(app.descendants(matching: .any)["train.stock"].firstMatch.appears(within: 30), "\(real): the train is followed")
            let zoomIn = app.buttons["放大"]
            if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 5) {
                for _ in 0..<6 {
                    zoomIn.tap()
                    settle(seconds: 1)
                }
            }
            settle(seconds: 3)
            keep("curve2d-\(name)", app)
            app.terminate()
        }
    }

    /// Decision 574: the Maokong Gondola on a real map of Muzha, its rope
    /// and stations on the 2D map, then the network tool's cable car mode
    /// with the gondola's card, in Chinese and in English (six modes in
    /// the row). For the screenshot review of the pull request that added
    /// the mode.
    func testCablewayMode() {
        for english in [false, true] {
            let app = launch(extra: ["-screenshot-scene", "maokong"], english: english)
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            settle(seconds: 5)
            if !english { keep("cableway-map", app) }
            let build = app.buttons["dock.build"]
            if build.appears(within: 10) { build.tap() }
            let network = app.buttons["tool.network"]
            XCTAssertTrue(network.appears(within: 10))
            network.waitUntilSettled()
            if !network.isSelected { network.tap() }
            // The row slides sideways when the modes do not fit.
            let mode = app.networkMode(english ? "Cable car" : "纜車")
            XCTAssertTrue(mode.exists, "The mode is in the row, not under More")
            XCTAssertTrue(mode.becomesHittable(within: 10))
            mode.tap()
            let card = app.descendants(matching: .any)["network.cablewayCard"].firstMatch
            XCTAssertTrue(card.appears(within: 10), "The gondola's card")
            // The card is below the mode's options, under the panel's edge:
            // the options (in view) drag it up, rows and all.
            let angle = app.descendants(matching: .any)["network.cablewayAngle"].firstMatch
            // Decision 588: on a phone the instruction at the head scrolls
            // away with the options (a drag on the options' last row began
            // on the pinned button under it, run 41915148091); the drag
            // on the head moves both (a second one on the options took
            // them past the card's top, run 41921574255).
            let head = app.descendants(matching: .any)["inspector.status"].firstMatch
            XCTAssertTrue(angle.appears(within: 5), "The cable car's options")
            if head.appears(within: 5) { head.swipeUp() }
            settle()
            keep(english ? "cableway-mode-english" : "cableway-mode", app)
            // Decision 574's next step: the panel closed and opened again
            // shows the chosen mode in view, the row not slid by hand.
            let done = app.buttons["tool.select"]
            if done.becomesHittable(within: 10) {
                done.tap()
                if build.appears(within: 10) { build.tap() }
                XCTAssertTrue(network.appears(within: 10))
                network.waitUntilSettled()
                if !network.isSelected { network.tap() }
                XCTAssertTrue(app.networkModeElement(english ? "Cable car" : "纜車").appears(within: 10))
                settle()
                keep(english ? "cableway-mode-reopened-english" : "cableway-mode-reopened", app)
            }
            app.terminate()
        }
    }

    /// Decision 585: the Tamsui–Bali ferry on a real map of the river
    /// mouth, its crossing and piers on the 2D map, then the transit
    /// tool's ferry mode with the route's card, in Chinese and in English;
    /// and the collection's ferry page in Settings. For the screenshot
    /// review of the pull request that added the mode.
    func testFerryMode() {
        for english in [false, true] {
            let app = launch(extra: ["-screenshot-scene", "tamsuiFerry"], english: english)
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 180), "The scene opens")
            settle(seconds: 5)
            // The scene opens close on the river: one step out shows both piers.
            let zoomOut = app.buttons[english ? "Zoom out" : "縮小"]
            if zoomOut.appears(within: 5), zoomOut.isEnabled { zoomOut.tap() }
            settle()
            if !english { keep("ferry-map", app) }
            let build = app.buttons["dock.build"]
            if build.appears(within: 10) { build.tap() }
            let transit = app.buttons["tool.bus"]
            XCTAssertTrue(transit.appears(within: 10))
            transit.waitUntilSettled()
            if !transit.isSelected { transit.tap() }
            let mode = app.segmentedControls.buttons[english ? "Ferries" : "渡輪"].firstMatch
            XCTAssertTrue(mode.becomesHittable(within: 10), "The ferry mode is in the transit tool's row")
            // The panel may still be settling after the tool opens: tap
            // until the segment reads selected.
            for _ in 0..<3 where !mode.isSelected {
                mode.tap()
                settle(seconds: 1)
            }
            XCTAssertTrue(mode.isSelected, "The ferry mode is chosen")
            let card = app.descendants(matching: .any)["ferry.card"].firstMatch
            XCTAssertTrue(card.appears(within: 10), "The ferry's card")
            // The mode's instruction is the card at the top, and the
            // route's card comes first under the modes, so the panel opens
            // on it without scrolling.
            XCTAssertTrue(app.descendants(matching: .any)["ferry.hint"].firstMatch.appears(within: 5), "The ferry mode's instruction")
            settle()
            keep(english ? "ferry-mode-english" : "ferry-mode", app)
            app.terminate()
        }
        let app = launch()
        defer { app.terminate() }
        let settings = app.buttons["start.settings"]
        XCTAssertTrue(settings.appears(within: 60), "Missing start.settings")
        settings.tap()
        // Neither the picker's identifier nor its segment under
        // `segmentedControls` reached the drag inside the settings list
        // (runs 41849781799 and 41856636503). Bring the garage row up as
        // the train garage tests do; the picker is the row above it, and
        // its ferry segment is found by its label whatever its type.
        let garage = app.buttons["settings.trainGarage"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(garage, clearOf: .slider), "Missing the collection's train page")
        let ferries = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "渡輪")).firstMatch
        XCTAssertTrue(ferries.becomesHittable(within: 10), "Missing the collection's ferry page")
        ferries.tap()
        let boat = app.descendants(matching: .any)["settings.ferry.shunfeng166"].firstMatch
        XCTAssertTrue(boat.appears(within: 10), "The ferry page")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(app.descendants(matching: .any)["settings.ferry.gushanCijin"].firstMatch, clearOf: .slider))
        settle()
        keep("collection-ferries", app)
    }

    /// Decision 575 續 (CABLEMAP): the Maokong Gondola on the 3D map: its
    /// cabins, towers and ropes close up over a span, from just over the
    /// ground up at the cabins' floors (the crystal cabins' glass), and
    /// from far, the near cabins whole and the rest far. For the
    /// screenshot review of the pull request that drew them.
    func testCablewayIn3D() {
        for (name, view, span) in [("cableway-3d-near", "110,40,55", "1,500"), ("cableway-3d-below", "60,70,88", "1,450"),
                                   ("cableway-3d-far", "1400,20,45", "1,500")] {
            let app = launch(extra: ["-screenshot-scene", "maokong", "-screenshot-3d-view", view, "-screenshot-3d-cableway", span,
                                     "-map3D.quality", "high"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            settle(seconds: 3)
            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 10))
            XCTAssertTrue(open3D.becomesHittable(within: 10))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
            settle(seconds: 12)
            keep(name, app)
            app.terminate()
        }
    }

    /// Decision 615 (CABLE-SUNMOON): the Sun Moon Lake Ropeway on the 3D
    /// map running Sun Moon Lake's cabins (red, yellow, blue and the green
    /// crystal one), close up over its span and from below, the glass
    /// see-through. For the pull request's screenshot review, beside
    /// ``testCablewayIn3D()``'s Maokong cabins.
    func testSunMoonLakeCablewayIn3D() {
        for (name, view, span) in [("cableway-sunmoon-3d-near", "110,40,55", "0,500"), ("cableway-sunmoon-3d-below", "60,70,88", "0,450"),
                                   ("cableway-sunmoon-3d-close", "40,25,30", "0,520")] {
            let app = launch(extra: ["-screenshot-scene", "sunMoonLake", "-screenshot-3d-view", view, "-screenshot-3d-cableway", span,
                                     "-map3D.quality", "high"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            settle(seconds: 3)
            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 10))
            XCTAssertTrue(open3D.becomesHittable(within: 10))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
            settle(seconds: 12)
            keep(name, app)
            app.terminate()
        }
    }

    /// Decision 585 續 (FERRY-QIJIN): the ferry mode's pale blue shore
    /// round Kaohsiung harbour's mouth on a map whose land round Cijin is
    /// not read in yet (the author's, on 115.1). For the pull request's
    /// screenshot review.
    /// Decision 629 (TRACKHEIGHT): a stretch drawn across a river on the
    /// ground, refused, its card offering a bridge and a tunnel; then the
    /// bridge tapped, and the end raised a metre by hand. In Chinese and
    /// in English. For the screenshot review of the pull request that
    /// added them.
    func testTrackHeightFixes() {
        for english in [false, true] {
            let app = launch(extra: ["-screenshot-scene", "trackHeight"], english: english)
            let suffix = english ? "-en" : ""
            let fixUp = app.buttons["map.build.fixUp"]
            XCTAssertTrue(fixUp.appears(within: 180), "The card offers a bridge")
            XCTAssertTrue(app.buttons["map.build.fixDown"].exists, "and a tunnel")
            settle(seconds: 3)
            keep("track-height-refused\(suffix)", app)
            fixUp.tap()
            XCTAssertTrue(fixUp.disappears(within: 20), "Built as offered, nothing left to fix")
            settle(seconds: 2)
            keep("track-height-bridge\(suffix)", app)
            // Decision 646: a tap on the HUD's height cell opens − and +.
            let cell = app.descendants(matching: .any)["map.constructionHUD.height"].firstMatch
            XCTAssertTrue(cell.becomesHittable(within: 10))
            cell.tap()
            let raise = app.buttons["map.build.raise"]
            XCTAssertTrue(raise.becomesHittable(within: 10))
            raise.tap()
            settle(seconds: 2)
            keep("track-height-raised\(suffix)", app)
            app.terminate()
        }
    }

    func testFerryShoreCijin() {
        let app = launch(extra: ["-screenshot-scene", "cijinShore"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 180), "The scene opens")
        settle(seconds: 5)
        // The whole island opens in view, and a camera request only zooms
        // out to its region: pinched in towards Cijin (the scene centres
        // the map on it each second), some 125 times, short of the closest
        // zoom that hands over to the 3D map; its next request zooms out
        // to the harbour.
        for _ in 0..<3 {
            map.pinch(withScale: 5, velocity: 3)
            settle(seconds: 2)
        }
        let build = app.buttons["dock.build"]
        if build.appears(within: 10) { build.tap() }
        let transit = app.buttons["tool.bus"]
        XCTAssertTrue(transit.appears(within: 10))
        transit.waitUntilSettled()
        if !transit.isSelected { transit.tap() }
        let mode = app.segmentedControls.buttons["渡輪"].firstMatch
        XCTAssertTrue(mode.becomesHittable(within: 10), "The ferry mode is in the transit tool's row")
        for _ in 0..<3 where !mode.isSelected {
            mode.tap()
            settle(seconds: 1)
        }
        XCTAssertTrue(mode.isSelected, "The ferry mode is chosen")
        settle(seconds: 3)
        keep("ferry-shore-cijin", app)
    }

    /// Decision 585 PR-3 (FERRY3): the ferries on the 3D map: Tamsui–Bali's
    /// passenger boat and Gushan–Cijin's double-ended ferry close up at
    /// their piers (near models), each from 600 m (far models, past the
    /// near models' 350 m; from 1,100 m over Tamsui the app's main thread
    /// was busy past the UI query's limit, run 41900993132), and
    /// Gushan–Cijin at dusk with its lamps lit; every shot looks at the
    /// first boat. Two tests, each within the 8 minutes a test may take
    /// (run 41906144682 took five shots past it). For the screenshot
    /// review of the pull request that drew them.
    func testFerriesIn3DTamsui() {
        shootFerries([("ferry-3d-tamsui-near", "tamsuiFerry", "75,35,62"),
                      ("ferry-3d-tamsui-far", "tamsuiFerry", "600,20,50")])
    }

    func testFerriesIn3DGushan() {
        shootFerries([("ferry-3d-gushan-near", "gushanFerry", "85,35,62"),
                      ("ferry-3d-gushan-far", "gushanFerry", "600,20,50"),
                      ("ferry-3d-gushan-evening", "gushanFerryEvening", "110,215,64")])
    }

    private func shootFerries(_ shots: [(name: String, scene: String, view: String)]) {
        for shot in shots {
            let app = launch(extra: ["-screenshot-scene", shot.scene, "-screenshot-3d-view", shot.view, "-map3D.quality", "high",
                                     "-screenshot-3d-ferry"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 180), "The scene opens")
            settle(seconds: 3)
            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 10))
            XCTAssertTrue(open3D.becomesHittable(within: 10))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
            settle(seconds: 12)
            keep(shot.name, app)
            app.terminate()
        }
    }

    /// Decision 578: the 3D follow views: the window of a car, the platform
    /// of the next stop (a short gap), and the station view greyed out
    /// while the next stop is a high-speed gap away.
    func testFollowWindowAndStation() {
        func open3DFollowing(_ scene: String) -> XCUIApplication {
            let app = launch(extra: ["-screenshot-scene", scene, "-screenshot-follow-train", "-map3D.quality", "high"])
            XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
            settle(seconds: 5)
            let open3D = app.buttons["map.open3D"]
            XCTAssertTrue(open3D.appears(within: 10))
            XCTAssertTrue(open3D.becomesHittable(within: 10))
            open3D.tap()
            XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
            XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
            return app
        }
        do {
            let app = open3DFollowing("platformStop")
            defer { app.terminate() }
            let window = app.buttons["map3D.follow.window"]
            XCTAssertTrue(window.becomesHittable(within: 10))
            window.tap()
            // Decision 578 (FOLLOWVIEW-2): one run of three shot the view
            // from behind, 後方 still chosen after this tap (run
            // 41800375321); the shot is taken only of the window view.
            if !window.isSelectedWithin(5) {
                XCTContext.runActivity(named: "車窗 not chosen after the tap; tapping it again") { _ in }
                XCTAssertTrue(window.becomesHittable(within: 10))
                window.tap()
            }
            XCTAssertTrue(window.isSelectedWithin(5), "The window view is chosen")
            settle(seconds: 8)
            keep("follow-window", app)
            let station = app.buttons["map3D.follow.station"]
            XCTAssertTrue(station.becomesHittable(within: 10))
            station.tap()
            settle(seconds: 12)
            keep("follow-station-near", app)
        }
        do {
            let app = open3DFollowing("farStops")
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["map3D.follow.station"].appears(within: 10))
            settle(seconds: 3)
            keep("follow-station-too-far", app)
        }
    }

    /// Decision 565: a train of four 20 m cars standing at a platform four
    /// cars long on a real map, close up on the 2D map and on the 3D one:
    /// every car inside the platform, its nose at the platform's end. For
    /// the screenshot review of the pull request that stopped it so.
    func testPlatformStop() {
        let app = launch(extra: ["-screenshot-scene", "platformStop", "-screenshot-follow-train",
                                 "-screenshot-3d-view", "160,0,55", "-map3D.quality", "high"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        // The train's card has no stock row (no real line's stock): let the
        // follow settle instead.
        settle(seconds: 5)
        let zoomIn = app.buttons["放大"]
        if zoomIn.appears(within: 10), zoomIn.becomesHittable(within: 5) {
            for _ in 0..<6 {
                zoomIn.tap()
                settle(seconds: 1)
            }
        }
        settle(seconds: 3)
        keep("platform-stop-2d", app)

        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
        settle(seconds: 12)
        keep("platform-stop-3d", app)
    }

    /// Decision 539: a freight line's train, followed on the 3D map, is
    /// the R200 hauling container wagons (not grey boxes). For the
    /// screenshot review of the pull request that drew it so.
    func testFreightTrainIn3D() {
        let app = launch(extra: ["-screenshot-scene", "freight", "-screenshot-follow-freight", "-map3D.quality", "saving"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        XCTAssertTrue(app.buttons["train.unfollow"].appears(within: 30), "The freight train is followed")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        // The size check of waitForPicture passed the spinner here; wait
        // for the spinner itself to go.
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 240), "The 3D map is drawn")
        // Decision 546: and its trains' models, not the boxes before them.
        XCTAssertTrue(app.descendants(matching: .any)["map3D.trainsLoading"].firstMatch.disappears(within: 240), "The trains are drawn")
        settle(seconds: 8)
        keep("freight-3d", app)
    }

    /// Decision 580 (FOLLOWBUS): a feeder bus followed on the 3D map, from
    /// above and behind and from the driver's seat, with the follow bar.
    /// For the screenshot review of the pull request that let the camera
    /// follow a bus. One shot a test, as the leaned views.
    func testFollowBusAboveBehind() { shootFollowBus("aboveBack", "follow-bus-above") }
    func testFollowBusCab() { shootFollowBus("cab", "follow-bus-cab") }
    func testFollowBusSide() { shootFollowBus("side", "follow-bus-side") }
    func testFollowBusBack() { shootFollowBus("back", "follow-bus-back") }
    func testFollowBusWindow() { shootFollowBus("window", "follow-bus-window") }

    /// Decision 342 (FOLLOWXRAY): the same on Taipei's real city, buildings
    /// beside and behind the bus, seen through.
    func testFollowBusCityBack() { shootFollowBus("back", "follow-bus-city-back", scene: "followBusCity") }
    func testFollowBusCitySide() { shootFollowBus("side", "follow-bus-city-side", scene: "followBusCity") }
    func testFollowBusCityWindow() { shootFollowBus("window", "follow-bus-city-window", scene: "followBusCity") }

    private func shootFollowBus(_ view: String, _ name: String, scene: String = "followBus") {
        let app = launch(extra: ["-screenshot-scene", scene, "-screenshot-follow-bus", "-map3DFollowView", view,
                                 "-map3D.quality", "high"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
        XCTAssertTrue(app.buttons["map3D.follow.stop"].appears(within: 30), "The bus is followed")
        settle(seconds: 12)
        keep(name, app)
    }

    /// Decision 583 (CABLEFOLLOW): a Maokong Gondola cabin followed on the
    /// 3D map, from its window, from above and behind, and from beside it,
    /// with the follow bar. For the screenshot review of the pull request
    /// that let the camera follow a cabin. One shot a test.
    func testFollowCabinWindow() { shootFollowCabin("window", "follow-cabin-window") }
    func testFollowCabinAboveBehind() { shootFollowCabin("aboveBack", "follow-cabin-above") }
    func testFollowCabinSide() { shootFollowCabin("side", "follow-cabin-side") }

    private func shootFollowCabin(_ view: String, _ name: String) {
        let app = launch(extra: ["-screenshot-scene", "maokong", "-screenshot-follow-cabin", "-map3DFollowView", view,
                                 "-map3D.quality", "high"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
        XCTAssertTrue(app.buttons["map3D.follow.stop"].appears(within: 30), "The cabin is followed")
        settle(seconds: 12)
        keep(name, app)
    }

    /// Decision 585 PR-4 (FERRYFOLLOW): a ferry boat followed on the 3D
    /// map: Tamsui–Bali's from its bridge and its cabin's window,
    /// Gushan–Cijin's from above and behind and, at 18:30, from beside it,
    /// with the follow bar. For the screenshot review of the pull request
    /// that let the camera follow a boat. One shot a test.
    func testFollowFerryTamsuiBridge() { shootFollowFerry("tamsuiFerryCrossing", "cab", "follow-ferry-tamsui-bridge") }
    func testFollowFerryTamsuiWindow() { shootFollowFerry("tamsuiFerryCrossing", "window", "follow-ferry-tamsui-window") }
    func testFollowFerryGushanAbove() { shootFollowFerry("gushanFerry", "aboveBack", "follow-ferry-gushan-above") }
    func testFollowFerryGushanWindow() { shootFollowFerry("gushanFerry", "window", "follow-ferry-gushan-window") }
    func testFollowFerryGushanEveningSide() { shootFollowFerry("gushanFerryEvening", "side", "follow-ferry-gushan-evening-side") }

    private func shootFollowFerry(_ scene: String, _ view: String, _ name: String) {
        let app = launch(extra: ["-screenshot-scene", scene, "-screenshot-follow-ferry", "-map3DFollowView", view,
                                 "-map3D.quality", "high"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
        XCTAssertTrue(app.buttons["map3D.follow.stop"].appears(within: 30), "The boat is followed")
        settle(seconds: 12)
        keep(name, app)
    }

    /// Decision 555: the 3D map at its own tilt and leaned by two fingers
    /// to 60°, round Taipei Main Station (the Shin Kong Life Tower to the
    /// south-west) and round Taipei 101. For the screenshot review of the
    /// pull request that let it lean. One shot a test: each takes some two
    /// minutes on the Simulator, past XCTest's eight minutes a test for six.
    func testLeanedStation140() { shootLean("taipeiMain", "140,225,0", "lean-station-own") }
    func testLeanedStation140At60() { shootLean("taipeiMain", "140,225,60", "lean-station-60") }
    func testLeanedStation200() { shootLean("taipeiMain", "200,225,0", "lean-station-200-own") }
    func testLeanedStation200At60() { shootLean("taipeiMain", "200,225,60", "lean-station-200-60") }
    /// Decision 600: the real trains on Taichung's viaduct on the tracks
    /// they are assigned, the double track on one deck, close and leaned.
    func testTaichungViaduct() { shootLean("taichungViaduct", "200,225,45", "taichung-viaduct") }
    func testTaichungViaductClose() { shootLean("taichungViaduct", "120,135,30", "taichung-viaduct-close") }

    /// Decision 581, later (ROUNDHOUSE-STOCK): the Changhua Roundhouse's
    /// parked locomotives, their noses out of the doorways towards the
    /// turntable, from the turntable's side close by and higher up. For the
    /// pull request's screenshot review.
    func testChanghuaRoundhouseStock() {
        for (view, name) in [("90,0,60", "roundhouse-stock-close"), ("80,320,55", "roundhouse-stock-west"),
                             ("220,10,40", "roundhouse-stock-high")] {
            shootLean("changhuaRoundhouse", view, name)
        }
    }
    /// Decision 607: the interchange west of Taichung over the high-speed
    /// line, beside the Fazi River: its link roads meeting the decks at
    /// one height, from above and leaned low.
    func testInterchange() { shootLean("interchange", "320,200,40", "interchange") }
    func testInterchangeClose() { shootLean("interchange", "160,240,25", "interchange-close") }
    func testLeaned101() { shootLean("taipei101", "260,20,0", "lean-101-own") }
    func testLeaned101At60() { shootLean("taipei101", "260,20,60", "lean-101-60") }

    /// Decision 611 (ROADTUNNEL): the real roads' tunnel portals, close up
    /// and from above: the Hsuehshan Tunnel's two bores at Toucheng (the
    /// freeway, west into the hill), Provincial Highway 9's (蘇花改) tunnels
    /// north of Nanao, and its gallery south of Su'ao. For the screenshot
    /// review of the pull request that drew them, not the website.
    func testRoadTunnelHsuehshan() {
        shootLean("hsuehshanTunnel", "160,0,60", "road-tunnel-hsuehshan-near")
        shootLean("hsuehshanTunnel", "500,270,0", "road-tunnel-hsuehshan-high")
    }
    func testRoadTunnelSuhua() {
        shootLean("suhuaTunnel", "160,180,60", "road-tunnel-suhua-near-south")
        shootLean("suhuaTunnel", "160,0,60", "road-tunnel-suhua-near-north")
        shootLean("suhuaTunnel", "500,0,0", "road-tunnel-suhua-high")
    }
    func testRoadTunnelGallery() {
        shootLean("suhuaGallery", "140,180,60", "road-tunnel-gallery-near-south")
        shootLean("suhuaGallery", "140,0,60", "road-tunnel-gallery-near-north")
    }

    private func shootLean(_ scene: String, _ view: String, _ name: String, extra: [String] = []) {
        let app = launch(extra: ["-screenshot-scene", scene, "-screenshot-3d-view", view, "-map3D.quality", "high"] + extra)
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
        settle(seconds: 12)
        keep(name, app)
    }

    /// Decision 596: the big junction east of Taipei Main Station from
    /// above, by day and by night: the traffic waiting at the stop lines
    /// of the roads its signals show red, the people at the crossings. The
    /// Simulator's GPU has no tier and draws nothing on the streets, so
    /// the standard tier is asked for.
    func testStreetStopDay() { shootLean("streetStop", "150,200,40", "street-stop-day", extra: ["-screenshot-device-tier", "1"]) }
    func testStreetStopNight() { shootLean("streetStopNight", "150,200,40", "street-stop-night", extra: ["-screenshot-device-tier", "1"]) }

    /// Decision 617 (NIGHT-GLOW): the same junction at 20:00 closer and
    /// lower, its street lights, signals, signs and windows, and the
    /// scene's train followed from behind and from beside it, its lamps:
    /// the before and after of the glows round the lights.
    func testNightGlowStreet() { shootLean("streetStopNight", "70,200,22", "night-glow-street", extra: ["-screenshot-device-tier", "1"]) }
    func testNightGlowFollowBack() { shootNightGlowFollow("back", "night-glow-follow-back") }
    func testNightGlowFollowSide() { shootNightGlowFollow("side", "night-glow-follow-side") }

    private func shootNightGlowFollow(_ view: String, _ name: String) {
        let app = launch(extra: ["-screenshot-scene", "streetStopNight", "-screenshot-follow-train", "-map3DFollowView", view,
                                 "-map3D.quality", "high", "-screenshot-device-tier", "1"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        settle(seconds: 5)
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 300), "The 3D map is drawn")
        XCTAssertTrue(app.buttons["map3D.follow.stop"].appears(within: 30), "The train is followed")
        settle(seconds: 12)
        keep(name, app)
    }

    /// Decision 610: Banqiao's low-rise blocks north of Fuzhong close up
    /// and leaned, over their roofs (decision 610 續: not against a
    /// tower's wall), the real buildings' street fronts (arcade pillars, grilles,
    /// air conditioners, blade signs, rooftop rooms). The standard tier is
    /// asked for: the Simulator's GPU has none, and the lowest leaves the
    /// fronts out.
    func testRealStreetFronts() { shootLean("streetFronts", "70,240,55", "street-fronts", extra: ["-screenshot-device-tier", "1"]) }
    func testRealStreetFrontsAbove() { shootLean("streetFronts", "140,60,35", "street-fronts-above", extra: ["-screenshot-device-tier", "1"]) }

    /// Decision 357 續 (SUNPCF): the 3D map with the sun's shadows drawn
    /// (quality High), for the before/after of the tent filter.
    func testSunShadowsIn3D() {
        let app = launch(extra: ["-screenshot-scene", "freight", "-screenshot-select-station", "1", "-map3D.quality", "high"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        XCTAssertTrue(app.buttons["map3D.close"].appears(within: 60), "The 3D map opens")
        XCTAssertTrue(app.descendants(matching: .any)["map3D.loading"].firstMatch.disappears(within: 240), "The 3D map is drawn")
        // Close in and tilted, where a shadow's edge is wide enough to see.
        for _ in 0..<3 { app.pinch(withScale: 3, velocity: 2) }
        settle(seconds: 8)
        keep("sun-shadows-3d", app)
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

    /// Decision 506 續二 (BADGE): the expansion scene
    /// (`ScreenshotScene.expansion`), West's concourse mark beside its name,
    /// close up (the overview's names carry no squares). For the
    /// screenshot review of the pull request that drew the mark, not the
    /// website; in both languages.
    func testStationTierMark() {
        tierMarkShot(english: false)
    }

    func testStationTierMarkInEnglish() {
        tierMarkShot(english: true)
    }

    /// The same scene's Central: past the people a day its first expansion
    /// needs, full on too few of the last seven days.
    func testStationExpansionFullDays() {
        fullDaysShot(english: false)
    }

    func testStationExpansionFullDaysInEnglish() {
        fullDaysShot(english: true)
    }

    private func tierMarkShot(english: Bool) {
        let app = launch(extra: ["-screenshot-scene", "expansion"], english: english)
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 180), "The scene opens")
        let stations = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(stations.appears(within: 30), "The stations are drawn")
        func west() -> CGPoint? {
            ((stations.value as? String) ?? "").split(separator: ";").first.flatMap { pair in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
        }
        settle()
        // Zoom in first (the badges are drawn only at full detail), then
        // drag West to the middle; the zoom does not keep a point in place,
        // so the drag comes after it and reads West again. The drag starts
        // between the side rail and the stations (a hold on a station opens
        // its panel) and is slow, so the map does not coast past.
        let zoomIn = app.buttons[english ? "Zoom in" : "放大"]
        XCTAssertTrue(zoomIn.appears(within: 5), "The zoom buttons show")
        for _ in 0..<3 where zoomIn.isEnabled {
            XCTAssertTrue(zoomIn.becomesHittable(within: 3))
            zoomIn.tap()
            settle(seconds: 1)
        }
        settle()
        guard let point = west() else { return XCTFail("The scene has stations") }
        let middle = CGPoint(x: map.frame.width / 2, y: map.frame.height / 2)
        let shift = CGVector(dx: middle.x - point.x, dy: middle.y - point.y)
        let from = CGVector(dx: middle.x - shift.dx / 2, dy: middle.y + 120 - shift.dy / 2)
        let origin = map.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(from).press(
            forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: from.dx + shift.dx, dy: from.dy + shift.dy)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3)
        settle()
        keep("station-tier-mark-\(english ? "en" : "zh")", app)
        if let moved = west() {
            XCTAssertLessThan(abs(moved.x - middle.x), map.frame.width / 4, "West is near the middle (\(moved))")
        }
    }

    private func fullDaysShot(english: Bool) {
        let app = launch(extra: ["-screenshot-scene", "expansion"], english: english)
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 180), "The scene opens")
        let stations = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(stations.appears(within: 30), "The stations are drawn")
        func central() -> CGPoint? {
            let pairs = ((stations.value as? String) ?? "").split(separator: ";")
            guard pairs.count > 1 else { return nil }
            let xy = pairs[1].split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
        var last = central()
        let still = Date().addingTimeInterval(10)
        while Date() < still {
            Thread.sleep(forTimeInterval: 0.5)
            let now = central()
            if now != nil, now == last { break }
            last = now
        }
        // A hold on Central opens its panel, as `testCivicRidersRow` does.
        guard let point = last else { return XCTFail("The scene has a second station") }
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
        let offer = app.descendants(matching: .any)["station.expansion.build"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(offer, in: list), "The station size card's offer comes into view")
        settle()
        keep("station-expansion-full-days-\(english ? "en" : "zh")", app)
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

    /// The real-world demo with a stretch of track built across the
    /// middle of the map and a platform's site picked on it (the platform
    /// mode open, at its longest), for a test to shoot; its ✓.
    private func pickPlatformSiteOnTheRealWorldDemo(_ app: XCUIApplication) -> XCUIElement {
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
        let platform = app.networkModeInTheCard("車站", folded: "展開控制項")
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
        return confirm
    }

    /// Decision 569: the names offered under a new station's name on a
    /// real-world map, then one of them picked.
    func testStationNameChoices() {
        let app = launch()
        defer { app.terminate() }
        _ = pickPlatformSiteOnTheRealWorldDemo(app)
        let first = app.buttons["network.stationNameChoice.0"]
        XCTAssertTrue(first.appears(within: 10), "The names show under the name")
        // The name sits below the card's short middle (on an iPhone held
        // sideways it shows some 70 points): drag inside it, slowly, until
        // the whole first name shows, not only its top edge.
        // Decision 588: or the head scrolling with the options over the
        // pinned foot.
        let pinnedMiddle = app.scrollViews["details.scroll.middle"]
        let middle = pinnedMiddle.exists ? pinnedMiddle : app.scrollViews["details.scroll.foot"]
        func shown() -> Bool {
            first.isHittable && (!middle.exists || first.frame.maxY <= middle.frame.maxY + 1)
        }
        for _ in 0..<12 where !shown() && middle.exists {
            let box = middle.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: box.midX, dy: box.maxY - 6))
            let to = origin.withOffset(CGVector(dx: box.midX, dy: box.minY + 6))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            settle(seconds: 0.5)
        }
        XCTAssertTrue(shown(), "The names can be reached")
        settle()
        keep("station-name-choices", app)
        let second = app.buttons["network.stationNameChoice.1"]
        if second.exists, second.isHittable {
            second.tap()
            settle()
            keep("station-name-choice-picked", app)
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
        let confirm = pickPlatformSiteOnTheRealWorldDemo(app)
        XCTAssertTrue(confirm.appears(within: 10), "No ✓ for the platform")
        settle()
        keep("platform-levelling-pill", app)
        confirm.waitUntilSettled()
        confirm.tap()
        settle()
        keep("platform-levelling-layer", app)
    }

    /// Decision 572: a station on both tracks of a double track with no
    /// crossover between them (built before decision 571): the station
    /// panel's button that lays one, then what it says once laid.
    func testOldStationCrossovers() {
        let app = launch(extra: ["-ui-test-world", "old-crossovers"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 30), "The world opens")
        map.waitUntilSettled()
        let select = app.buttons["tool.select"]
        if select.appears(within: 5), select.becomesHittable(within: 5) { select.tap() }
        let readout = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(readout.appears(within: 10))
        settle(seconds: 3)
        let xy = (readout.value as? String ?? "").split(separator: ";").first?.split(separator: ",").compactMap { Double($0) } ?? []
        XCTAssertEqual(xy.count, 2)
        guard xy.count == 2 else { return }
        let frame = map.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + xy[0] - app.frame.minX, dy: frame.minY + xy[1] - app.frame.minY)).press(forDuration: 1)
        XCTAssertTrue(app.descendants(matching: .any)["station.operations"].firstMatch.appears(within: 10), "The station panel opens")
        let button = app.buttons["station.crossovers"].firstMatch
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.appears(within: 10))
        list.waitUntilStill()
        // Clear of the bar's scroll edge too, which hides a row's top
        // line just under the bar (the first round's shot).
        XCTAssertTrue(app.dragUntilWhollyOnScreen(button, in: list, below: app.navigationBars.firstMatch.frame.maxY + 32), "The button shows")
        button.waitUntilSettled()
        settle()
        keep("station-crossovers-button", app)
        button.tap()
        XCTAssertTrue(button.disappears(within: 10), "Laid, it goes")
        settle()
        keep("station-crossovers-laid", app)
    }

    /// Decision 584: a line with no trains, and 列車 4 standing with no
    /// line where its trips start: the line page offers it to the line,
    /// and buying trains instead says it is in the way, with "Go" to it.
    func testIdleTrainAtALinesFirstStop() {
        let app = launch(extra: ["-ui-test-world", "idle-blocker"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 30), "The world opens")
        map.waitUntilSettled()
        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let page = app.openLinePage()
        let idle = app.buttons["line.staff.idleTrain"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(idle, in: page), "The idle train's row shows")
        idle.waitUntilSettled()
        settle()
        keep("idle-train-row", app)
        let start = app.buttons["line.staff.start"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(start, in: page), "The buy button shows")
        start.tap()
        XCTAssertTrue(app.buttons["banner.goToTrain"].firstMatch.appears(within: 10), "The banner names the train in the way")
        settle()
        keep("idle-train-banner", app)
    }

    /// Decision 584, PR-2: the train tool at 海岸, a station of two
    /// platforms on two tracks that do not meet, with 列車 3 off the track
    /// and given 海岸線: the platforms listed, the one on 海岸線's track
    /// picked, then the other picked by hand.
    func testPlacementPlatformChoice() {
        shootPlacementPlatformChoice(english: false, name: "platform-choice")
    }

    /// The same in English, the first only.
    func testPlacementPlatformChoiceEnglish() {
        shootPlacementPlatformChoice(english: true, name: "platform-choice-en")
    }

    private func shootPlacementPlatformChoice(english: Bool, name: String) {
        let app = launch(extra: ["-ui-test-world", "platform-choice"], english: english)
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 30), "The world opens")
        map.waitUntilSettled()
        let build = app.buttons["dock.build"]
        if build.appears(within: 5), build.becomesHittable(within: 5) { build.tap() }
        let trainTool = app.buttons["tool.train"]
        XCTAssertTrue(trainTool.appears(within: 10), "The train tool shows")
        trainTool.waitUntilSettled()
        trainTool.tap()
        let readout = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(readout.appears(within: 10))
        settle(seconds: 3)
        let xy = (readout.value as? String ?? "").split(separator: ";").first?.split(separator: ",").compactMap { Double($0) } ?? []
        XCTAssertEqual(xy.count, 2)
        guard xy.count == 2 else { return }
        let frame = map.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + xy[0] - app.frame.minX, dy: frame.minY + xy[1] - app.frame.minY)).tap()
        let card = app.descendants(matching: .any)["details.card"].firstMatch
        XCTAssertTrue(card.appears(within: 10), "The train tool's card shows")
        let first = app.buttons["train.platform.1"].firstMatch
        let second = app.buttons["train.platform.2"].firstMatch
        XCTAssertTrue(first.appears(within: 10), "The station's platforms are listed")
        // Decision 588: the cars and the platforms stand over the Place
        // button, in the card's foot, which stays in view: nothing to
        // scroll, in either language or on the smallest iPhone.
        let place = app.descendants(matching: .any)["panel.action"].firstMatch
        XCTAssertTrue(place.appears(within: 10), "The Place button shows")
        settle()
        keep(name, app)
        let cars = app.descendants(matching: .any)["train.cars"].firstMatch
        for (element, what) in [(first, "Platform 1"), (second, "Platform 2"), (place, "The Place button"), (cars, "The cars")] {
            XCTAssertTrue(element.exists && card.frame.insetBy(dx: -0.5, dy: -0.5).contains(element.frame),
                          "\(what) shows whole in the card without scrolling: \(element.frame) in \(card.frame)")
            XCTAssertTrue(app.frame.contains(element.frame), "\(what) is on the screen: \(element.frame)")
        }
        XCTAssertTrue(first.isHittable && second.isHittable && place.isHittable, "Both platforms and the button show at once")
        guard !english else { return }
        let other = second.isSelected ? first : second
        other.tap()
        settle()
        XCTAssertTrue(other.isSelected, "The tapped platform is picked")
        keep("platform-choice-picked", app)
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
        let platformMode = app.networkModeInTheCard("車站", folded: "展開控制項", within: 10)
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
        let mode = app.networkMode("車站")
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

    /// Decision 535 (continued, ANKENG): the Ankeng LRT's purchase card on
    /// a real-world game at Banqiao, opened from the lines panel's lines
    /// for sale. For the screenshot review of its pull request.
    func testAnkengLRTForSale() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        tapButton("newGame.realWorld", in: app, timeout: 60)
        let banqiao = app.buttons.matching(identifier: "place.tra-banqiao").firstMatch
        XCTAssertTrue(app.scrollUntilShown(banqiao, in: app.collectionViews.firstMatch), "Banqiao is listed")
        banqiao.waitUntilSettled()
        app.tapMiddle(of: banqiao)
        tapButton("realWorld.start", in: app, timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The game starts")
        settle(seconds: 4)

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["路線"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let ankeng = app.buttons["line.acquire.K"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(ankeng, in: list), "The Ankeng LRT is for sale")
        settle(seconds: 1)
        keep("ankeng-for-sale", app)
        ankeng.tap()
        XCTAssertTrue(app.buttons["acquire.buy"].appears(within: 120), "Its card is laid out")
        settle(seconds: 2)
        keep("ankeng-for-sale-card", app)
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

    /// Decision 632: the collection's ferry and cable car pages, and each
    /// one's 3D stage (the phone on its side, as every screenshot here):
    /// the close view and the side by day, the close view at night and the
    /// view from above. For the screenshot review of the pull request that
    /// added them.
    func testCollectionFerriesAndCableCarsIn3D() {
        for (page, exhibit, entry) in [("渡輪", "ferries", "settings.ferry.chigu2"), ("纜車", "cableways", "settings.cableway.sunMoonLake")] {
            let app = launch()
            let settings = app.buttons["start.settings"]
            XCTAssertTrue(settings.appears(within: 60), "Missing start.settings")
            settings.tap()
            // As testFerryMode: bring the garage row up, then the page's
            // segment above it.
            let garage = app.buttons["settings.trainGarage"]
            XCTAssertTrue(app.dragUntilWhollyOnScreen(garage, clearOf: .slider), "Missing the collection's train page")
            let segment = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", page)).firstMatch
            XCTAssertTrue(segment.becomesHittable(within: 10), "Missing the collection's \(exhibit) page")
            segment.tap()
            let open = app.buttons["settings.collection.\(exhibit)"]
            XCTAssertTrue(open.appears(within: 10), "The \(exhibit) page")
            XCTAssertTrue(app.dragUntilWhollyOnScreen(app.descendants(matching: .any)[entry].firstMatch, clearOf: .slider))
            settle()
            keep("collection-\(exhibit)-page", app)
            XCTAssertTrue(app.dragUntilWhollyOnScreen(open, clearOf: .slider), "The \(exhibit) button")
            open.tap()
            let closeUp = app.buttons["trainShowcase.camera.closeUp"]
            XCTAssertTrue(closeUp.appears(within: 120), "The \(exhibit) stage did not open")
            // The picture shows once the models are made (the first run's
            // day shots caught the spinner).
            XCTAssertTrue(app.activityIndicators.firstMatch.disappears(within: 180), "The \(exhibit) models")
            closeUp.tap()
            settle(seconds: 6)
            keep("collection-\(exhibit)-day-close", app)
            app.buttons["trainShowcase.camera.side"].tap()
            settle(seconds: 4)
            keep("collection-\(exhibit)-day-side", app)
            let light = app.segmentedControls["trainShowcase.light"]
            light.buttons.element(boundBy: 2).tap()
            closeUp.tap()
            settle(seconds: 4)
            keep("collection-\(exhibit)-night-close", app)
            app.buttons["trainShowcase.camera.overhead"].tap()
            settle(seconds: 4)
            keep("collection-\(exhibit)-night-above", app)
            app.terminate()
        }
    }

    /// Decision 560: the EMU700 local train in the garage (the 3D map's
    /// own models, eight cars), by day: the front close up and the side,
    /// near models, then the far models from the side and the front. For
    /// the screenshot review of the pull request that put it in service.
    func testEMU700Train() {
        // The garage opened on the EMU700 alone (`-screenshot-showcase`, as
        // decision 558's test): scrolling the picker's sheet on a phone on
        // its side ran past the 8 minutes (run 41620016563).
        let app = launch(extra: ["-screenshot-showcase", "emu700"])
        defer { app.terminate() }
        let settings = app.buttons["start.settings"]
        XCTAssertTrue(settings.appears(within: 60), "Missing start.settings")
        settings.tap()
        let garage = app.buttons["settings.trainGarage"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(garage, clearOf: .slider), "Missing the garage row")
        garage.tap()
        let closeUp = app.buttons["trainShowcase.camera.closeUp"]
        XCTAssertTrue(closeUp.appears(within: 120), "The garage did not open")
        let far = app.segmentedControls["trainShowcase.far"]
        far.buttons.element(boundBy: 0).tap()
        closeUp.tap()
        settle(seconds: 6)
        keep("emu700-near-front", app)
        app.buttons["trainShowcase.camera.side"].tap()
        settle(seconds: 4)
        keep("emu700-near-side", app)
        far.buttons.element(boundBy: 1).tap()
        settle(seconds: 6)
        keep("emu700-far-side", app)
        closeUp.tap()
        settle(seconds: 4)
        keep("emu700-far-front", app)
    }

    /// Decision 558: the Wenhu line's two fleets in the garage (the 3D
    /// map's own models), one at a time, by day: the front close up and
    /// the side, near models, then the far models from the side.
    func testWenhuTrains() {
        // The garage opened on one train at a time (`-screenshot-showcase`):
        // scrolling the picker's half-height sheet on a phone on its side
        // ran past the 8 minutes (run 41613797939).
        for (key, name) in [("wenhuVAL256", "val256"), ("wenhu370", "370")] {
            let app = launch(extra: ["-screenshot-showcase", key])
            defer { app.terminate() }
            let settings = app.buttons["start.settings"]
            XCTAssertTrue(settings.appears(within: 60), "Missing start.settings")
            settings.tap()
            let garage = app.buttons["settings.trainGarage"]
            XCTAssertTrue(app.dragUntilWhollyOnScreen(garage, clearOf: .slider), "Missing the garage row")
            garage.tap()
            let closeUp = app.buttons["trainShowcase.camera.closeUp"]
            XCTAssertTrue(closeUp.appears(within: 120), "The garage did not open")
            let far = app.segmentedControls["trainShowcase.far"]
            far.buttons.element(boundBy: 0).tap()
            closeUp.tap()
            settle(seconds: 6)
            keep("wenhu-\(name)-near-front", app)
            app.buttons["trainShowcase.camera.side"].tap()
            settle(seconds: 4)
            keep("wenhu-\(name)-near-side", app)
            far.buttons.element(boundBy: 1).tap()
            settle(seconds: 6)
            keep("wenhu-\(name)-far-side", app)
            closeUp.tap()
            settle(seconds: 4)
            keep("wenhu-\(name)-far-front", app)
        }
    }

    /// Decision 561: the Taoyuan Airport MRT's two fleets in the garage
    /// (the 3D map's own models), one at a time, as decision 558's test:
    /// the front close up and the side, near models, then the far models.
    func testTaoyuanAirportTrains() {
        for (key, name) in [("taoyuanAirport1000", "1000"), ("taoyuanAirport2000", "2000")] {
            let app = launch(extra: ["-screenshot-showcase", key])
            defer { app.terminate() }
            let settings = app.buttons["start.settings"]
            XCTAssertTrue(settings.appears(within: 60), "Missing start.settings")
            settings.tap()
            let garage = app.buttons["settings.trainGarage"]
            XCTAssertTrue(app.dragUntilWhollyOnScreen(garage, clearOf: .slider), "Missing the garage row")
            garage.tap()
            let closeUp = app.buttons["trainShowcase.camera.closeUp"]
            XCTAssertTrue(closeUp.appears(within: 120), "The garage did not open")
            let far = app.segmentedControls["trainShowcase.far"]
            far.buttons.element(boundBy: 0).tap()
            closeUp.tap()
            settle(seconds: 6)
            keep("tymc-\(name)-near-front", app)
            app.buttons["trainShowcase.camera.side"].tap()
            settle(seconds: 4)
            keep("tymc-\(name)-near-side", app)
            far.buttons.element(boundBy: 1).tap()
            settle(seconds: 6)
            keep("tymc-\(name)-far-side", app)
            closeUp.tap()
            settle(seconds: 4)
            keep("tymc-\(name)-far-front", app)
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

    /// Decisions 631 and 642: the freight scene's yards and stations
    /// zoomed in one and two steps, where every track shows its number;
    /// a number keeps off the switches, the points where tracks cross,
    /// the stations' badges, waiting counts and names. Then the layer
    /// strip folded into its one round button, and the layers sheet with
    /// its track numbers switch. For the screenshot review of the pull
    /// request that made the numbers keep clear.
    func testTrackNumbersAndFoldedLayerStrip() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        XCTAssertTrue(app.buttons.matching(identifier: "map.alert").firstMatch.appears(within: 30), "The scene has run on")
        zoomInOnce(app)
        settle(seconds: 2)
        keep("track-numbers-zoom1", app)
        zoomInOnce(app)
        settle(seconds: 2)
        keep("track-numbers-zoom2", app)

        let collapse = app.buttons["map.quickLayer.collapse"]
        XCTAssertTrue(collapse.appears(within: 10), "The layer strip has its fold button")
        XCTAssertTrue(collapse.becomesHittable(within: 5))
        collapse.tap()
        let expand = app.buttons["map.quickLayer.expand"]
        XCTAssertTrue(expand.appears(within: 10), "The strip folds into one button")
        settle(seconds: 2)
        keep("layer-strip-folded", app)
        expand.tap()
        XCTAssertTrue(collapse.appears(within: 10), "The strip opens again")

        let more = app.buttons["map.quickLayer.more"]
        guard more.appears(within: 5), more.becomesHittable(within: 5) else { return }
        more.tap()
        let numbers = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '軌道編號'")).firstMatch
        if numbers.appears(within: 10) {
            _ = app.dragUntilWhollyOnScreen(numbers, drags: 8)
        }
        settle(seconds: 2)
        keep("layers-sheet-track-numbers", app)
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

    /// Decision 573: a depot laid near two lines with none offers each on
    /// the banner, and the game menu's Report a Problem says where to
    /// send it. For the screenshot review of the pull request that added
    /// them, not the website.
    func testDepotOfferAndWhereToReport() {
        let app = launch(extra: ["-screenshot-scene", "depotOffer"])
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        // The offer stays 10 s: shot as soon as it shows.
        let offer = app.buttons["banner.depotLine"].firstMatch
        XCTAssertTrue(offer.appears(within: 10), "The banner offers the lines")
        settle(seconds: 1)
        keep("depot-offer", app)

        app.buttons["banner.depotLine"].firstMatch.tap()
        settle(seconds: 1)
        keep("depot-offer-chosen", app)
        // Decision 619: the yard's fan with the banner and the building
        // tools closed, pinched in (the scene centres the map on the yard
        // each second for a minute).
        let dismiss = app.buttons["banner.dismiss"].firstMatch
        if dismiss.appears(within: 2) { dismiss.tap() }
        XCTAssertTrue(dismiss.disappears(within: 5), "The banner goes")
        let done = app.buttons["tool.select"]
        if done.becomesHittable(within: 10) { done.tap() }
        let fold = app.buttons["map.minimap.fold"].firstMatch
        if fold.becomesHittable(within: 5) { fold.tap() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        for _ in 0..<2 {
            map.pinch(withScale: 2.5, velocity: 2)
            settle(seconds: 2)
        }
        keep("depot-yard", app)

        let menu = app.buttons["hud.menu"]
        menu.waitUntilSettled()
        menu.tap()
        // The menu's rows side by side (a ControlGroup) drop their
        // identifiers: found by the label too, in either language.
        let report = app.buttons.matching(NSPredicate(format: "identifier == 'menu.report' OR label == 'Report a Problem' OR label == '回報問題'")).firstMatch
        XCTAssertTrue(report.appears(within: 30), "The menu opens")
        report.waitUntilSettled()
        let frame = report.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["report.whereToSend"].firstMatch.appears(within: 10), "The report says where to send it")
        settle(seconds: 1)
        keep("report-where-to-send", app)
    }

    /// Decision 568: a new line picked on the map (five stations, the
    /// potential layer on, as in the owner's report), on the map alone and
    /// beside the lines panel; on an iPad upright too. The shots upright
    /// end in `-portrait` and are not turned (website-screenshots.yml).
    func testRouteDrawing() {
        shootRouteDrawing(extra: [], name: "route-draw")
    }

    /// Decision 568: the same at the largest accessibility text size.
    func testRouteDrawingLargeText() {
        shootRouteDrawing(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"], name: "route-draw-large-text")
    }

    private func shootRouteDrawing(extra: [String], name: String) {
        let app = launch(extra: ["-screenshot-scene", "freight", "-screenshot-line-draft"] + extra)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 120), "The scene opens")
        XCTAssertTrue(app.buttons["map.build.confirm"].appears(within: 30), "The new line's pill shows")
        // Where people are (decision 311), its legend over the map, as the
        // owner had it.
        let coverage = app.buttons["map.coverageShortcut"]
        if coverage.appears(within: 10) {
            coverage.waitUntilSettled()
            coverage.tap()
        }
        settle(seconds: 3)
        keep(name + upright(app), app)

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        XCTAssertTrue(app.navigationBars["路線"].firstMatch.appears(within: 10), "The lines panel opens")
        settle(seconds: 3)
        keep("\(name)-panel" + upright(app), app)
    }

    /// "-portrait" when the app shows upright: an iPhone is held on its
    /// side only (project.yml), but the runner's iPad Simulator turns or
    /// not whatever the test asks, and the workflow turns every other
    /// shot a quarter back (decision 568).
    private func upright(_ app: XCUIApplication) -> String {
        let frame = app.windows.firstMatch.frame
        return frame.width < frame.height ? "-portrait" : ""
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

    /// Waits until the 3D map is drawn, not its spinner: the Simulator
    /// draws it in software and can take over a minute; a screenshot of
    /// the spinner is about 240 KB, one of the map far more.
    private func waitForPicture(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        // Decision 546: and its trains' models, not the boxes before them.
        _ = XCUIApplication().descendants(matching: .any)["map3D.trainsLoading"].firstMatch.disappears(within: timeout)
        while Date() < deadline {
            if XCUIScreen.main.screenshot().pngRepresentation.count > 600_000 { return }
            Thread.sleep(forTimeInterval: 2)
        }
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

private extension XCUIElement {
    /// Whether the element is selected within `timeout` seconds, at once
    /// when it already is.
    func isSelectedWithin(_ timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(exists && isSelected) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return true
    }
}
