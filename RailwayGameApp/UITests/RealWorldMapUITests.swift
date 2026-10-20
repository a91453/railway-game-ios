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

        // Decision 262 put Taiwan's places under a group heading, so on a
        // landscape iPhone Taipei's row starts below the screen (and the
        // list makes rows only as they come near): scroll to it first.
        let taipei = app.buttons.matching(identifier: "place.tra-taipei").firstMatch
        XCTAssertTrue(app.scrollUntilShown(taipei, in: app.collectionViews.firstMatch), "Missing button: place.tra-taipei")
        taipei.waitUntilSettled()
        XCTAssertEqual(taipei.label, "Taipei", "The references' places are listed")
        app.tapMiddle(of: taipei)

        let start = tappable(app.buttons.matching(identifier: "realWorld.start"), name: "realWorld.start")
        start.waitUntilSettled()
        let startedAt = Date()
        start.tap()
        let tapReturnedAfter = Date().timeIntervalSince(startedAt)

        let map = app.descendants(matching: .any)["map"].firstMatch
        let mapAppeared = map.appears(within: 15)
        let mapAppearedAfter = Date().timeIntervalSince(startedAt)
        print("Real-world start timing: tap returned in \(tapReturnedAfter)s; map appeared=\(mapAppeared) in \(mapAppearedAfter)s from Build Here tap")
        XCTAssertTrue(mapAppeared, "The game starts after Build Here")
        XCTAssertTrue(start.disappears(within: 5), "The place picker closes after Build Here")
        XCTAssertTrue(app.buttons["Zoom in"].appears(within: 10))

        // Keep the live clock from rebuilding the native menus (the map
        // style's and the game's) while XCTest targets their actions, as in
        // the start and save flow: pause before opening either.
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        // Decision 226, step 3: the map style is the layer list's first
        // section, only for a real-world map.
        chooseSatellite(in: app)
        XCTAssertTrue(map.appears(within: 10))

        tappable(app.buttons.matching(identifier: "hud.menu"), name: "hud.menu").tap()
        tappable(app.buttons.matching(identifier: "menu.backToStart"), name: "menu.backToStart").tap()

        let continueButton = tappable(app.buttons.matching(identifier: "start.continue"), name: "start.continue")
        XCTAssertTrue(continueButton.label.contains("Real-world map"), "The autosave is a real-world map's: \(continueButton.label)")
        continueButton.tap()
        // Apple's map under the game's, as satellite was chosen.
        XCTAssertTrue(app.descendants(matching: .any)["map.base"].firstMatch.appears(within: 15), "Continuing keeps the real-world map")
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

        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The demo starts")
        let authority = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "map.traffic", "cleared to run")).firstMatch
        XCTAssertTrue(authority.appears(within: 60), "The demo's trains take their routes under traffic control")
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

        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 600), "The demo is built and opens")
        // It runs at once, like the other demos: a pause button, not a play one.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")).firstMatch.appears(within: 30))
    }

    /// Decision 191: the short credit in the real-world map's corner is
    /// always there and opens the data sources page. Full lane only (not
    /// in the pull request gate).
    func testTheMapCreditOpensTheDataSources() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        app.openDemo("demo.realWorld")

        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The demo starts")
        let credit = app.descendants(matching: .any)["map.credit"].firstMatch
        XCTAssertTrue(credit.appears(within: 30), "The map's corner credits its sources")
        XCTAssertTrue(credit.label.contains("© OpenMapTiles © OpenStreetMap"), credit.label)
        credit.tap()
        XCTAssertTrue(app.navigationBars["Data Sources"].appears(within: 10), "Tapping the credit opens the data sources")
    }

    /// TestFlight 56.1: changing from OpenStreetMap to satellite imagery,
    /// the player's route no longer lay on the map. After the change, and
    /// zoomed in as far as the map goes, Apple's map shows what the game's
    /// camera shows, straight down and north up (decision 50); the map
    /// reads this out under UI tests (`map.base`). Full lane only (not in
    /// the pull request gate): it needs Apple's tiles over the network.
    func testAppleMapLinesUpAfterChangingToSatellite() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        app.openDemo("demo.realWorld")
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The demo starts")
        // Paused, so the live clock does not rebuild the style menu.
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        chooseSatellite(in: app)

        let base = app.descendants(matching: .any)["map.base"].firstMatch
        XCTAssertTrue(base.appears(within: 30), "Apple's map is under the game's")
        assertLinesUp(base, "after changing to satellite")

        let zoomIn = app.buttons["Zoom in"]
        for _ in 0..<12 where zoomIn.isEnabled {
            zoomIn.tap()
        }
        assertLinesUp(base, "zoomed in as far as it goes")
    }

    /// Waits for Apple's map to show what the game's camera shows: MapKit
    /// settles a few seconds after it loads.
    private func assertLinesUp(_ base: XCUIElement, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        let follows = NSPredicate(format: "value == %@", "follows")
        let found = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: follows, object: base)], timeout: 30)
        // Still so a few seconds on: MapKit did not move it again.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(found == .completed && (base.value as? String) == "follows",
                      "Apple's map does not line up \(when): \(String(describing: base.value))", file: file, line: line)
    }

    /// A blank new game has no Apple map and no style menu.
    func testABlankGameHasNoMapStyle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 10))
        XCTAssertTrue(app.buttons["Zoom in"].appears(within: 10))
        // Decision 226, step 3: the style is in the layer list, and not
        // there for a blank map.
        let more = app.buttons["map.quickLayer.more"]
        XCTAssertTrue(more.appears(within: 10))
        more.tap()
        XCTAssertTrue(app.switches["layer.stationNames"].appears(within: 10), "The layer list opens")
        XCTAssertFalse(app.buttons["map.style"].exists)
    }

    /// Opens the layer list (the strip's More), chooses Satellite as the
    /// map style, its first section on a real-world map (decision 226,
    /// step 3), and closes the list.
    private func chooseSatellite(in app: XCUIApplication) {
        tappable(app.buttons.matching(identifier: "map.quickLayer.more"), name: "map.quickLayer.more").tap()
        tappable(app.buttons.matching(identifier: "map.style"), name: "map.style").tap()
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Satellite")), name: "Satellite").tap()
        tappable(app.buttons.matching(identifier: "layer.done"), name: "layer.done").tap()
        XCTAssertTrue(app.buttons["layer.done"].disappears(within: 5), "The layer list closes")
    }

    /// The start screen scrolls (decision 106), so with any text size,
    /// up to the largest accessibility size, each of its buttons can be
    /// reached; the real-world map's (runs 38281750910 and 38285956099
    /// could not bring it into sight, but they dragged down the middle of
    /// the screen, on a phone on its side the edge between the title and
    /// the buttons, and wanted the button wholly inside a band shorter
    /// than it). With the largest text a real-world game is started from
    /// the start screen and the place list (a phone is held on its side
    /// only). Full lane only (not in the pull request gate).
    func testTheRealWorldMapIsReachedWithTheLargestText() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        defer { app.terminate() }
        startARealWorldGameFromTaipei(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 15), "The game starts")
    }

    /// Decision 190's report (TestFlight 54.1): on a real-world map, a
    /// phone on its side, a tall banner under the top controls (here the
    /// largest accessibility text, which makes the banner tall) left no
    /// room between it and the dock, and the platform's ✓ went half under
    /// the dock. Here a platform is put on a stretch, then asked for again
    /// on the same place: GameCore refuses it (the platforms would
    /// overlap), the refusal stays in the banner for some seconds, and the
    /// ✓ and ✕ stay whole and above the dock meanwhile. Full lane only
    /// (not in the pull request gate).
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

        startARealWorldGameFromTaipei(in: app)
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 15), "The game starts")
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        // The map opens on the whole place, some 48 m a point: the stretch
        // below would run 10 km, onto land not owned (run 38289886049).
        // Five steps, each halving it, make it some 330 m. Before a tool is
        // chosen, while the zoom buttons show beside the map.
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        for _ in 0..<5 where zoomIn.isEnabled {
            zoomIn.tap()
        }

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
        // From 0.25 to 0.6, its middle at 0.425 where the platform goes.
        // Decision 226 put the tools in a column on a phone on its side,
        // and the middle line moved with them; the stretch from 0.3 to 0.55
        // then crossed a cutting, its middle climbing 11‰, and its platform
        // was not built (main bf12187's full lane, run 38641908091). The
        // longer stretch spreads that climb.
        point(0.25).tap()
        point(0.6).tap()
        let confirm = app.buttons["map.build.confirm"]
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        let builder = confirm.appears(within: 10) ? confirm : card
        XCTAssertTrue(builder.appears(within: 10), "No way to build the stretch")
        XCTAssertTrue(builder.becomesHittable(), "The ✓ cannot be tapped: \(builder.frame), dock top \(dockTop)")
        builder.tap()
        let banner = { (text: String) in
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        // "Built Track #N: …" since decision 201 named a stretch a track.
        if !banner("Built Track").appears(within: 10) {
            let problem = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Problem'")).firstMatch
            XCTFail("The stretch was not built: \(problem.exists ? problem.label : "no banner")")
            return
        }

        // The platform mode, from the details card (opened if folded).
        let platform = app.buttons["Platform"]
        if !platform.appears(within: 3) || !platform.becomesHittable(within: 1) {
            let controls = app.buttons["controls.toggle"]
            if controls.exists { controls.tap() }
        }
        XCTAssertTrue(platform.appears(within: 10), "No Platform mode")
        platform.waitUntilSettled()
        platform.tap()
        // Beside the open details card the 3D map and zoom buttons stand in
        // the middle of the map, on the stretch's line since the game menu
        // moved into the top row (#697): a tap there zoomed out, and the
        // next one fell on a climb (main 84a792e's full lane, run
        // 38861445072). The taps below keep off them. The station coverage
        // shortcut (#839) stands left of the 3D map button, and the step
        // left of that button landed on it (main 614375c's full lane, run
        // 39438209091); a real station's pin (#844) can stand on the line too.
        let mapButtons = ["map.coverageShortcut", "map.open3D", "Zoom out", "Zoom in"].map { app.buttons[$0] }
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.realStation.'"))
        func mapButton(at x: CGFloat) -> CGRect? {
            (mapButtons.filter(\.exists) + pins.allElementsBoundByIndex).lazy
                .map { $0.frame.insetBy(dx: -4, dy: -4) }
                .first { $0.contains(CGPoint(x: x, y: middle)) }
        }
        // A platform on the track, levelled first where it climbs; on the
        // near side of the buttons there.
        var siteX = frame.minX + frame.width * 0.425
        while let covering = mapButton(at: siteX) { siteX = covering.minX - 1 }
        let site = origin.withOffset(CGVector(dx: siteX, dy: middle))
        site.tap()
        XCTAssertTrue(confirm.appears(within: 10), "No ✓ for the platform")
        confirm.waitUntilSettled()
        confirm.tap()
        XCTAssertTrue(banner("Built station").appears(within: 10), "The platform was not built")
        // Asked for again on the same level stretch: refused, the refusal in
        // the banner, the pill still there. The new station's tag stands
        // over the site (run 38291939056), so the tap moves along the
        // platform, 16 cars and some 170 points long, until it reaches the
        // track.
        for offset: CGFloat in [60, -60, 90, -90] where !confirm.exists && mapButton(at: siteX + offset) == nil {
            site.withOffset(CGVector(dx: offset, dy: 0)).tap()
            _ = confirm.appears(within: 3)
        }
        XCTAssertTrue(confirm.appears(within: 5), "No ✓ for the second platform")
        confirm.waitUntilSettled()
        confirm.tap()
        XCTAssertTrue(banner("overlap").appears(within: 5), "No refusal in the banner")
        XCTAssertTrue(confirm.appears(within: 5), "The pill went with the refusal")
        // Decision 226: on a phone held sideways the tools are a column
        // down the leading edge, and while building it holds the building
        // tools, not Build; with no dock along the bottom there is none to
        // go under.
        let buildEntry = app.buttons["dock.build"]
        let dock = buildEntry.exists ? buildEntry.frame : CGRect(x: 0, y: app.frame.maxY, width: app.frame.width, height: 0)
        for (name, button) in [("✓", confirm), ("✕", app.buttons["map.build.cancel"])] {
            XCTAssertTrue(button.becomesHittable(), "The platform's \(name) cannot be tapped: \(button.frame)")
            XCTAssertLessThanOrEqual(button.frame.maxY, dock.minY, "The platform's \(name) goes under the dock: \(button.frame), dock \(dock)")
        }
    }

    /// TestFlight 67.1's report ("字會一直被面板擋住"): a phone on its side,
    /// the track card open, and the map's pill for the track's upgrade
    /// with a long line of words, which ran from the tools to under the
    /// card and was cut off there. Here a stretch is built, picked, and
    /// made double from its card, at a large text size so the pill's words
    /// are long: the pill stays left of the card, its words wrap, and its
    /// ✓ and ✕ can be tapped. Full lane only (not in the pull request
    /// gate).
    func testTheUpgradePillStaysBesideTheTrackCard() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
        ]
        app.launch()
        defer { app.terminate() }

        startARealWorldGameFromTaipei(in: app)
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 15), "The game starts")
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        // Some 330 m a point, as in the platform test above, so the stretch
        // stays on land the game owns.
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        for _ in 0..<5 where zoomIn.isEnabled {
            zoomIn.tap()
        }

        let build = app.buttons["dock.build"]
        tappable(app.buttons.matching(identifier: "dock.build"), name: "dock.build").tap()
        let network = app.buttons["tool.network"]
        network.waitUntilSettled()
        network.tap()

        // The platform test's stretch, built with the map's ✓ (or the
        // details card's Build Track).
        let hudBottom = app.buttons["hud.menu"].frame.maxY
        let dockTop = build.frame.minY
        let middle = (hudBottom + dockTop) / 2
        let frame = map.frame.intersection(app.frame)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.minX + frame.width * fraction, dy: middle))
        }
        point(0.25).tap()
        point(0.6).tap()
        let confirm = app.buttons["map.build.confirm"]
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        let builder = confirm.appears(within: 10) ? confirm : card
        XCTAssertTrue(builder.appears(within: 10), "No way to build the stretch")
        XCTAssertTrue(builder.becomesHittable(), "The ✓ cannot be tapped: \(builder.frame)")
        builder.tap()
        let built = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Built Track")).firstMatch
        if !built.appears(within: 10) {
            let problem = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Problem'")).firstMatch
            XCTFail("The stretch was not built: \(problem.exists ? problem.label : "no banner")")
            return
        }

        // The tools put away, the stretch picked: its card opens beside
        // the map. Off the map's own buttons in the middle, as above.
        let done = app.buttons["tool.select"]
        XCTAssertTrue(done.appears(within: 5), "No way to put the tools away")
        done.waitUntilSettled()
        done.tap()
        let mapButtons = ["map.open3D", "Zoom out", "Zoom in"].map { app.buttons[$0] }
        var trackX = frame.minX + frame.width * 0.425
        if let covering = mapButtons.lazy.filter(\.exists).map({ $0.frame.insetBy(dx: -4, dy: -4) })
            .first(where: { $0.contains(CGPoint(x: trackX, y: middle)) }) {
            trackX = covering.minX - 1
        }
        origin.withOffset(CGVector(dx: trackX, dy: middle)).tap()
        let double = app.buttons["inspector.track.double"]
        if !double.appears(within: 5) {
            let controls = app.buttons["controls.toggle"]
            if controls.exists { controls.tap() }
        }
        XCTAssertTrue(double.appears(within: 10), "No Make double track on the track card")
        double.waitUntilSettled()
        double.tap()

        let words = app.staticTexts["map.build.catchment"]
        XCTAssertTrue(words.appears(within: 10), "No words on the upgrade's pill")
        let details = app.descendants(matching: .any)["details.card"].firstMatch
        XCTAssertTrue(details.appears(within: 5), "The track card closed")
        let cardEdge = details.frame.minX
        let cancel = app.buttons["map.build.cancel"]
        for (name, element) in [("words", words), ("✓", confirm), ("✕", cancel)] {
            XCTAssertTrue(element.appears(within: 5), "No \(name) on the pill")
            XCTAssertLessThanOrEqual(
                element.frame.maxX, cardEdge,
                "The pill's \(name) runs under the track card: \(element.frame), card \(details.frame)"
            )
        }
        for (name, button) in [("✓", confirm), ("✕", cancel)] {
            XCTAssertTrue(button.becomesHittable(), "The pill's \(name) cannot be tapped: \(button.frame)")
        }
    }

    /// A player's report (a phone held sideways, a real-world map, in
    /// Chinese): the track tool's buttons, with "沿真實鐵路" (decision 213)
    /// added, did not fit the side panel, and "進階選項" and "沿真實鐵路"
    /// stood one character to a line, as tall as a column; the population
    /// grid's tooltip covered the map's ✓, and the layer and map buttons
    /// stood under the ✕ and ✓. Here each button keeps its words on one
    /// line, and the ✓ of a stretch is whole, uncovered, and clear of the
    /// round buttons. Full lane only (not in the pull request gate).
    func testTheTrackButtonsKeepTheirWordsOnALineAndTheConfirmIsClear() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-map-layer", "population",
        ]
        app.launch()
        defer { app.terminate() }

        startARealWorldGameFromTaipei(in: app)
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 15), "The game starts")
        tappable(app.buttons.matching(NSPredicate(format: "label == %@", "暫停")), name: "暫停").tap()
        // Some 330 m a point, as in the platform test above, so the stretch
        // stays on land the game owns.
        let zoomIn = app.buttons["放大"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        for _ in 0..<5 where zoomIn.isEnabled {
            zoomIn.tap()
        }

        let build = app.buttons["dock.build"]
        tappable(app.buttons.matching(identifier: "dock.build"), name: "dock.build").tap()
        let network = app.buttons["tool.network"]
        network.waitUntilSettled()
        network.tap()

        // One line of footnote text in a bordered button: "複線"'s height.
        let double = app.descendants(matching: .any)["network.double"].firstMatch
        XCTAssertTrue(double.appears(within: 10), "No 複線 button")
        for name in ["network.advanced", "network.trace"] {
            let button = app.descendants(matching: .any)[name].firstMatch
            XCTAssertTrue(button.appears(within: 5), "No \(name) button")
            XCTAssertLessThanOrEqual(
                button.frame.height, double.frame.height * 1.5,
                "\(name)'s words do not stand on one line: \(button.frame), 複線 \(double.frame)"
            )
            XCTAssertGreaterThan(button.frame.width, button.frame.height, "\(name) is a column: \(button.frame)")
        }

        // A stretch across the middle of the map, as in the platform test.
        let hudBottom = app.buttons["hud.menu"].frame.maxY
        let dockTop = build.frame.minY
        let middle = (hudBottom + dockTop) / 2
        let frame = map.frame.intersection(app.frame)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.3, dy: middle)).tap()
        origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.55, dy: middle)).tap()
        let confirm = app.buttons["map.build.confirm"]
        XCTAssertTrue(confirm.appears(within: 10), "No ✓ for the stretch")
        confirm.waitUntilSettled()
        XCTAssertTrue(confirm.becomesHittable(), "The ✓ cannot be tapped: \(confirm.frame)")
        XCTAssertFalse(
            app.descendants(matching: .any)["map.populationTooltip"].exists,
            "The population grid's tooltip stays over the ✕ and ✓"
        )
        // The map's own buttons: the layer strip's (decision 226, #644)
        // or, where it does not show, the round layers button. Map style
        // moved into the layer list (#645). At least one is there, so the
        // check is never empty (the PR #627–#646 review).
        let rounds = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.quickLayer.' OR identifier == 'map.layers'"))
            .allElementsBoundByIndex.filter(\.exists)
        XCTAssertFalse(rounds.isEmpty, "No layer buttons on the map")
        for (name, button) in [("✓", confirm), ("✕", app.buttons["map.build.cancel"])] {
            for other in rounds {
                XCTAssertFalse(
                    button.frame.intersects(other.frame),
                    "The \(name) is over \(other.identifier): \(button.frame), \(other.frame)"
                )
            }
        }
    }

    /// Start screen, Real-World Map, Taipei, Build Here: each scrolled
    /// to first, as the largest text needs.
    private func startARealWorldGameFromTaipei(in app: XCUIApplication) {
        // The place list (the sheet's only collection view) makes its rows
        // as they come near: with this text Taipei's is not made at first.
        for (identifier, holder) in [
            ("start.realWorld", nil), ("place.tra-taipei", app.collectionViews.firstMatch), ("realWorld.start", nil),
        ] as [(String, XCUIElement?)] {
            let button = app.buttons.matching(identifier: identifier).firstMatch
            XCTAssertTrue(
                app.scrollUntilShown(button, in: holder),
                "\(identifier) cannot be scrolled to: \(button.exists ? "\(button.frame)" : "missing"), app \(app.frame)"
            )
            app.tapMiddle(of: button)
        }
    }

    /// The copy of a button the player can touch. Existence can come before
    /// a menu or screen transition ends, and `ViewThatFits` can also expose
    /// an unplaced copy of a menu action, so `firstMatch` alone may not be
    /// hittable (the start and save flow's rule, `StartSaveFlowSmokeTests`).
    /// It is waited for until enabled too: the start screen's real-world
    /// buttons are disabled until the real-world data, read in the
    /// background at launch, is there.
    private func tappable(_ query: XCUIElementQuery, name: String) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.appears(within: 10), "Missing button: \(name)")
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
