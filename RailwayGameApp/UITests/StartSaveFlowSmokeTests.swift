import XCTest

@MainActor
final class StartSaveFlowSmokeTests: XCTestCase {
    func testEnglishStartSaveFlow() {
        checkFlow(language: "en", locale: "en_US")
    }

    func testTraditionalChineseStartSaveFlow() {
        checkFlow(language: "zh-Hant", locale: "zh_TW")
    }

    /// Decision 257: Language opens the game's own menu of languages, each
    /// named in itself; since decision 381 it is the first row of
    /// Settings. Nothing is chosen, so the Simulator's app settings stay as
    /// they were. Full lane only.
    func testLanguageOpensTheGamesLanguageMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        requiredButton(StartID.settings, in: app).tap()
        let language = app.buttons["settings.language"].firstMatch
        XCTAssertTrue(language.appears(within: 10), "Settings has no Language. \(screenText(in: app))")
        XCTAssertTrue(language.becomesHittable(within: 5), "Language cannot be tapped")
        language.tap()
        for name in ["Same as iPhone", "English", "繁體中文"] {
            let item = app.buttons[name].firstMatch
            XCTAssertTrue(item.appears(within: 5), "The language menu has no \(name). \(screenText(in: app))")
            XCTAssertTrue(item.becomesHittable(within: 5), "\(name) cannot be tapped")
        }
    }

    /// Decision 381: the data sources and licences are two taps from the
    /// start screen (Help, then its first row), and Saves on a clean launch
    /// offers to import a save. Full lane only.
    func testHelpReachesTheDataSourcesAndSavesOffersAnImport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        requiredButton(StartID.help, in: app).tap()
        let sources = app.buttons["help.dataSources"].firstMatch
        XCTAssertTrue(sources.appears(within: 10), "Help has no data sources row. \(screenText(in: app))")
        XCTAssertTrue(sources.becomesHittable(within: 5), "The data sources row cannot be tapped")
        sources.tap()
        XCTAssertTrue(app.navigationBars["Data Sources"].appears(within: 10), "The data sources did not open")
        app.terminate()

        app.launch()
        requiredButton(StartID.saves, in: app).tap()
        let importButton = app.buttons["saves.import"].firstMatch
        XCTAssertTrue(importButton.appears(within: 10), "The empty saves list offers no import. \(screenText(in: app))")
        XCTAssertTrue(importButton.becomesHittable(within: 5), "Import from Files cannot be tapped")
    }

    /// Decision 415: an updated app shows its news once on the start
    /// screen, and Help opens them again. Full lane only.
    func testAnUpdateShowsWhatsNewAndHelpOpensItAgain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-updated", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let done = app.buttons["whatsNew.done"].firstMatch
        XCTAssertTrue(done.appears(within: 10), "An update shows no news. \(screenText(in: app))")
        XCTAssertTrue(done.becomesHittable(within: 5), "The news cannot be closed")
        done.tap()
        XCTAssertTrue(done.disappears(within: 10), "The news did not close")

        requiredButton(StartID.help, in: app).tap()
        let row = app.buttons["help.whatsNew"].firstMatch
        XCTAssertTrue(row.appears(within: 10), "Help has no What's New row. \(screenText(in: app))")
        XCTAssertTrue(row.becomesHittable(within: 5), "The What's New row cannot be tapped")
        row.tap()
        XCTAssertTrue(app.navigationBars["What's New"].appears(within: 10), "Help did not open the news")
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
        app.chooseBlankMap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        // Decision 114: the tools show once Build is pressed.
        requiredButton("dock.build", in: app).tap()
        requiredButton("tool.building", in: app).tap()
        requiredButton("building.kind.house", in: app).tap()
        let count = app.staticTexts["building.count"]
        XCTAssertTrue(count.appears(within: 10), "Missing the building count")
        XCTAssertEqual(count.label, "0 buildings placed")

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        // Decision 95: a tap chooses the site, which enables the action
        // button; the button builds. A touch held across a slow
        // accessibility query is failed by the tap recognizer
        // (MapInteractionTests), so a lost tap is tried once more. The
        // count says whether it was built, not the "Built house #1 …"
        // banner: a success clears itself after 4 s, within one slow
        // accessibility query. The tap is at the middle of the map, clear
        // of the banner, legend and controls along its edges: at (0.5,
        // 0.3) no full run since P0-A (main's 37828454679, the manual runs
        // 37837094185 and 37838371614) ever built the house. A failure
        // says what the screen showed.
        let ground = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let build = app.buttons["panel.action"]
        func sited() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: build)],
                             timeout: 10) == .completed
        }
        ground.tap()
        if !sited() { ground.tap() }
        XCTAssertTrue(sited(), "A tap did not choose a site the house can stand on. \(screenText(in: app))")
        XCTAssertEqual(count.label, "0 buildings placed", "A tap only chooses where it goes")
        build.tap()
        let built = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1 building placed"), object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [built], timeout: 10), .completed, "The house was not built. \(screenText(in: app))")

        openGameMenu(in: app)
        tapMenuAction("menu.saveGame", in: app)
        openGameMenu(in: app)
        tapMenuAction("menu.backToStart", in: app)
        requiredButton("start.continue", in: app).tap()

        // Decision 114: the tools show once Build is pressed.
        requiredButton("dock.build", in: app).tap()
        requiredButton("tool.building", in: app).tap()
        XCTAssertTrue(count.appears(within: 10), "Missing the building count after continuing")
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
        app.chooseBlankMap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause").tap()
        // Decision 114: the tools show once Build is pressed.
        requiredButton("dock.build", in: app).tap()
        requiredButton("tool.building", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Zone")), name: "Zone").tap()
        requiredButton("building.zone.commercial", in: app).tap()
        let count = app.staticTexts["building.zoneCount"]
        XCTAssertTrue(count.appears(within: 10), "Missing the zoned cell count")
        XCTAssertEqual(count.label, "0 cells zoned")

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        // In the map's leading half: the details card floats over its
        // trailing side while a tool is chosen (decision 106).
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        let zoned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0 cells zoned"), object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [zoned], timeout: 10), .completed, "The drag zoned nothing: \(count.label)")
        let label = count.label

        openGameMenu(in: app)
        tapMenuAction("menu.saveGame", in: app)
        openGameMenu(in: app)
        tapMenuAction("menu.backToStart", in: app)
        requiredButton("start.continue", in: app).tap()

        // Decision 114: the tools show once Build is pressed.
        requiredButton("dock.build", in: app).tap()
        requiredButton("tool.building", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Zone")), name: "Zone").tap()
        XCTAssertTrue(count.appears(within: 10), "Missing the zoned cell count after continuing")
        XCTAssertEqual(count.label, label, "The zones did not survive saving and continuing")
    }

    private func checkFlow(language: String, locale: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        defer { app.terminate() }

        assertEmptyStart(in: app)

        // Decision 135: the simple demo is in the Demo Map's sheet.
        requiredButton("start.demoMap", in: app).tap()
        requiredButton("demo.simple", in: app).tap()
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
        // Back to Start creates only an autosave. Saves counting one save
        // also proves that Save Game wrote a manual save rather than doing
        // nothing (decision 381: the button always shows; with no save it
        // offers an import and has no number). On a phone on its side
        // (decision 106) it is further down the start screen's column.
        let saves = app.buttons[StartID.saves]
        XCTAssertTrue(saves.appears(within: 10), "Missing UI flow button: \(StartID.saves)")
        XCTAssertTrue(saves.label.contains("1"), "Saves does not count the manual save: \(saves.label)")
        XCTAssertTrue(app.buttons["start.demoMap"].exists, "Missing UI flow button: start.demoMap")

        requiredButton("start.continue", in: app).tap()
        assertGame(in: app)
        XCTAssertFalse(app.buttons["start.newGame"].exists, "Continue did not leave the start screen")

        // Prove that the same installation starts clean again after both a
        // manual save and an autosave, in each language.
        app.terminate()
        app.launch()
        assertEmptyStart(in: app)
    }

    /// A save that cannot be read is listed so that it can be deleted
    /// (``GameLauncher/otherSaves``): its row cannot load, but its swipe
    /// must still offer Delete (bug hunt 3, domain D).
    func testAnUnreadableSaveCanBeDeleted() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-broken-save", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        // On a phone on its side Saves lies below the screen, in the
        // start screen's column beside the title, which the shared helper
        // did not find (run 38260619251): drag that column at the button's
        // own x until it can be tapped.
        let saves = app.buttons[StartID.saves]
        XCTAssertTrue(saves.appears(within: 10), "An unreadable save is still listed")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<6 where !saves.isHittable {
            let x = saves.frame.midX - app.frame.minX
            origin.withOffset(CGVector(dx: x, dy: app.frame.height * 0.75))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: app.frame.height * 0.35)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(saves.isHittable, "Saves can be brought into view: \(saves.frame)")
        saves.tap()
        let row = app.buttons["saves.row.save-broken.json"]
        XCTAssertTrue(row.appears(within: 10), "The unreadable save is listed")
        // Decision 381: the row's "⋯" button shows what its swipe does.
        let menu = app.buttons["saves.menu.save-broken.json"]
        XCTAssertTrue(menu.appears(within: 5), "The unreadable save's row has no ⋯ button")
        XCTAssertTrue(menu.becomesHittable(within: 5), "The ⋯ button cannot be tapped")
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        if !delete.appears(within: 5) { row.swipeLeft() }
        XCTAssertTrue(delete.appears(within: 5), "Swiping the unreadable save must offer Delete")
        delete.tap()
        let confirm = app.buttons["saves.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(within: 5), "Deleting asks first")
        confirm.tap()
        XCTAssertTrue(row.disappears(within: 10), "The unreadable save is gone from the list")
    }

    /// TestFlight 54.1: Back to Start could not be touched, so leaving a
    /// game meant killing the app. The game loop replaced the world every
    /// tick and the open menu was rebuilt each time, and Back to Start was
    /// its last row. Here the clock runs (the demo's 600 times real time,
    /// its trains moving) while the menu is open.
    func testBackToStartWorksWhileTheClockRuns() {
        checkBackToStartWhileTheClockRuns(arguments: [], demo: true)
    }

    /// The same with the largest text short of the accessibility sizes,
    /// where the menu's rows are tallest. A blank new game, whose clock runs
    /// too: with this text the Demo Map button is below the start screen's
    /// fold, where XCTest could not tell whether it can be touched.
    func testBackToStartWorksWithLargeTextWhileTheClockRuns() {
        checkBackToStartWhileTheClockRuns(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"], demo: false)
    }

    /// The train menu and the train type menu with the clock running, in one
    /// launch: each relaunch of the app costs 10 to 15 s of the full lane
    /// (#545). Every check is the one its own test made before.
    ///
    /// TestFlight 54.1: with many trains and the clock running, the train
    /// menu could not be scrolled (each tick took it back to its top) and
    /// showed two layers of text. Fifteen trains, more than the menu shows
    /// at once on a phone on its side: with the clock running the open
    /// menu stays as it opened, and a row other than the selected train's
    /// can be chosen. XCTest cannot scroll a native menu (a press and drag
    /// chooses the row under the finger, a swipe closes the menu, paused or
    /// not: runs 38285634450 and 38287892415), so scrolling to the last row
    /// is left to a device.
    ///
    /// The author's report (decision 184, later): with the clock running,
    /// the train type menu could not be scrolled until the game was paused.
    /// With the clock running the open menu stays as it opened for thirty
    /// ticks, and a type other than the train's can be chosen. The chosen
    /// train is still one not yet placed, whose panel shows the menu.
    func testTheTrainAndTypeMenusStayStillAndChooseWhileTheClockRuns() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        // A blank new game: $3,000,000, enough for fifteen trains.
        requiredButton("start.newGame", in: app).tap()
        app.chooseBlankMap()
        _ = requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause")
        requiredButton("dock.build", in: app).tap()
        requiredButton("tool.train", in: app).tap()
        let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Buy a train"))
        for _ in 0..<15 {
            requiredButton(buy, name: "Buy").tap()
        }
        let picker = app.buttons.matching(identifier: "train.picker")
        XCTAssertTrue(picker.firstMatch.appears(within: 10), "Missing the train menu")
        waitForLabel("Train: Train 15", of: picker.firstMatch)
        XCTAssertTrue(app.buttons["Pause"].exists, "The clock must keep running")

        requiredButton("train.picker", in: app).tap()
        // The menu's rows ("Train 3"), not the picker ("Train: …") or the
        // train tool.
        let menuRows = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Train [0-9]+"))
        XCTAssertTrue(menuRows.firstMatch.appears(within: 10), "The train menu did not open")
        // The menu grows open: read its rows once two reads agree.
        func visibleRows() -> [String] {
            menuRows.allElementsBoundByIndex.filter(touchable).map { "\($0.label) \($0.frame)" }
        }
        let opened = settledRows(visibleRows, menu: "train.picker")
        XCTAssertGreaterThan(opened.count, 1, "The train menu shows its rows")
        // Thirty ticks: the menu must not move, close or change.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(visibleRows(), opened, "The open train menu changed by itself while the clock ran")
        // Choose a row in the middle of those it shows, which is not the
        // selected train (the lowest, at the menu's faded edge, took no tap
        // in run 38289773400).
        let rows = menuRows.allElementsBoundByIndex.filter(touchable)
        let row = rows[rows.count / 2]
        let name = row.label
        XCTAssertNotEqual(name, "Train 15")
        touchMenuRow(row, closing: app.buttons.matching(NSPredicate(format: "label == %@", name)), in: app, name: name)
        waitForLabel("Train: \(name)", of: picker.firstMatch)

        // Every type's name says what a car carries ("… · 140 a car · 4
        // doors"); the menu's own button is left out.
        checkMenuStaysStillAndChooses(
            "train.type",
            rows: app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND identifier != %@", " a car · ", "train.type")),
            in: app
        )
    }

    /// The menu in the author's screenshot (decision 184, later): how a
    /// train runs, 25 rows (Standard, Metro, Local EMU … and the design
    /// speeds). The same with the clock running.
    func testThePerformanceMenuStaysStillAndChoosesWhileTheClockRuns() {
        let app = launchWithAnUnplacedTrain()
        defer { app.terminate() }
        let presets = [
            "Standard", "Metro", "Local EMU", "Ordinary", "Chu-Kuang / Fu-Hsing", "Tze-Chiang", "EMU3000",
            "Push-pull Tze-Chiang", "Taroko", "Puyuma", "Diesel Tze-Chiang", "DR1000 railcar",
            "Alishan Forest Railway", "High-speed rail", "Steam train",
        ]
        checkMenuStaysStillAndChooses(
            "train.performance",
            rows: app.buttons.matching(NSPredicate(format: "label IN %@", presets)),
            in: app
        )
    }

    /// A blank new game, its clock running, with one train bought and not
    /// yet placed: the train panel shows its type and performance menus.
    private func launchWithAnUnplacedTrain() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        requiredButton("start.newGame", in: app).tap()
        app.chooseBlankMap()
        _ = requiredButton(app.buttons.matching(NSPredicate(format: "label == %@", "Pause")), name: "Pause")
        requiredButton("dock.build", in: app).tap()
        requiredButton("tool.train", in: app).tap()
        requiredButton(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Buy a train")), name: "Buy").tap()
        return app
    }

    /// Opens the menu `identifier` with the clock running: its `rows` must
    /// stay as they opened for thirty ticks, and one other than the chosen
    /// one (which the menu's label begins with) must be chosen when touched.
    private func checkMenuStaysStillAndChooses(_ identifier: String, rows menuRows: XCUIElementQuery, in app: XCUIApplication) {
        // On a phone on its side the train panel shows its first rows only
        // (run 38323867205: train.type 476 pt down a 402 pt screen): drag
        // the panel until the menu can be touched.
        let target = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(target.appears(within: 10), "Missing the menu \(identifier)")
        // The panel is dragged down its leading margin, beside the rows,
        // in drags shorter than its visible rows: drags of 40% of the
        // screen at the menu's own x carried train.performance past them
        // to y 81 once the train card grew a line (full lane run
        // 38362099969), and shorter ones begun on the menus above were
        // taken by those menus and moved nothing (run 38369790160).
        if !touchable(target) {
            let panel = app.scrollViews.containing(.button, identifier: identifier).firstMatch
            XCTAssertTrue(panel.exists, "No panel holds the menu \(identifier)")
            _ = app.dragUntilWhollyOnScreen(target, in: panel)
        }
        let menu = requiredButton(identifier, in: app)
        let chosen = menu.label
        XCTAssertTrue(app.buttons["Pause"].exists, "The clock must keep running")

        menu.tap()
        XCTAssertTrue(menuRows.firstMatch.appears(within: 10), "The menu \(identifier) did not open")
        // The menu grows open: read its rows once two reads agree.
        func visibleRows() -> [String] {
            menuRows.allElementsBoundByIndex.filter(touchable).map { "\($0.label) \($0.frame)" }
        }
        let opened = settledRows(visibleRows, menu: identifier)
        XCTAssertGreaterThan(opened.count, 1, "The menu \(identifier) shows its rows")
        // Thirty ticks: the menu must not move, close or change.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(visibleRows(), opened, "The open menu \(identifier) changed by itself while the clock ran")
        // Choose a row in the middle of those it shows that is not the
        // chosen one (the lowest, at the menu's faded edge, can miss). The
        // menu's label names the chosen row ("Performance: Standard · …"),
        // or the row begins with it (a type's row adds its card).
        let others = menuRows.allElementsBoundByIndex.filter(touchable).filter { !chosen.contains($0.label) && !$0.label.hasPrefix(chosen) }
        guard !others.isEmpty else { return XCTFail("The menu \(identifier) offers nothing else: \(opened)") }
        let row = others[(others.count - 1) / 2]
        let label = row.label
        touchMenuRow(row, closing: app.buttons.matching(NSPredicate(format: "label == %@", label)), in: app, name: label)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", chosen), object: menu)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed, "Choosing \(label) changed nothing in \(identifier)")
        XCTAssertTrue(label.hasPrefix(menu.label) || menu.label.contains(label), "\(identifier) shows \(menu.label), not the row chosen: \(label)")
    }

    private func checkBackToStartWhileTheClockRuns(arguments: [String], demo: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        defer { app.terminate() }

        if demo {
            requiredButton("start.demoMap", in: app).tap()
            requiredButton("demo.simple", in: app).tap()
        } else {
            requiredButton("start.newGame", in: app).tap()
            app.chooseBlankMap()
        }
        assertGame(in: app)
        // Not paused: the point is the running clock.
        XCTAssertTrue(app.buttons["Pause"].exists, "The game's clock must be running")

        openGameMenu(in: app)
        tapMenuAction("menu.backToStart", in: app)
        _ = requiredButton("start.newGame", in: app)
        _ = requiredButton("start.continue", in: app)
    }

    /// Waits until `element` reads `label`, looking every tenth of a second,
    /// and judges every look, the last one too. With fifteen trains and the
    /// clock running one look at the app took 5 to 21 s (main abb306a's
    /// full lane, run 39053855189): an `XCTWaiter` of 10 s timed out while
    /// its first look was still out, and the look after it read the label
    /// it waited for ("Expected Train: Train 5, found Train: Train 5",
    /// main 98d1f15's full lane, run 39070554849).
    private func waitForLabel(_ label: String, of element: XCUIElement, within timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        var seen = element.exists ? element.label : "nothing"
        while seen != label, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            seen = element.exists ? element.label : "nothing"
        }
        XCTAssertEqual(seen, label, "Expected \(label), found \(seen)")
    }

    private func assertEmptyStart(in app: XCUIApplication) {
        _ = requiredButton("start.newGame", in: app)
        _ = requiredButton("start.demoMap", in: app)
        XCTAssertFalse(app.buttons["start.continue"].exists, "A clean launch must not offer Continue")
        // Decision 381: Saves always shows; with no save it offers an
        // import, with no number of saves. The count is written in digits
        // ("2 個存檔"); \.isNumber alone also counts the 一 of 另一台.
        let saves = app.buttons[StartID.saves]
        XCTAssertTrue(saves.appears(within: 10), "Missing UI flow button: \(StartID.saves)")
        XCTAssertFalse(saves.label.contains(where: { $0.isASCII && $0.isNumber }), "A clean launch must not count saves: \(saves.label)")
    }

    private func assertGame(in app: XCUIApplication) {
        // The demo map's accessibility tree is large: on a slow runner one
        // query of it took 9 s, so its waits allow longer than a button's.
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 30), "Missing game map")
        assertHittable(map, timeout: 30, message: "Game map is not visible")
        for identifier in ["dock.build", "entry.lines", "hud.menu"] {
            _ = requiredButton(identifier, in: app)
        }
    }

    private func openGameMenu(in app: XCUIApplication) {
        // A touch can go by without the menu opening (run 40450049689: the
        // touch was sent, the app went idle, and `menu.saveGame` was in none
        // of ten reads over ten seconds): the button is touched again then.
        let opened = requiredButton("hud.menu", in: app).openMenu(showing: app.buttons.matching(identifier: "menu.saveGame").firstMatch)
        XCTAssertTrue(opened, "The game menu did not open: no menu.saveGame row after 3 touches of hud.menu")
        _ = menuRow("menu.saveGame", in: app)
        // Let the menu finish opening: tapMenuAction touches an action's
        // frame as it reads it. The screenshot taken here used to pause so.
        menuRow("menu.backToStart", in: app).waitUntilStill()
    }

    private func tapMenuAction(_ identifier: String, in app: XCUIApplication) {
        touchMenuRow(menuRow(identifier, in: app), closing: app.buttons.matching(identifier: identifier), in: app, name: identifier)
    }

    /// The game menu's row `identifier`, once a copy of it lies on the
    /// screen and stays in the same place a quarter of a second later, and
    /// is enabled. Not asked `isHittable`: just after the menu opened, with
    /// the row's frame on the screen, XCTest failed the test outright
    /// asking it ("Failed to determine hittability of menu.saveGame:
    /// Activation point invalid", the pull request gate's run 38471573204
    /// and #532's). `touchMenuRow` touches the frame's centre for the same
    /// reason, and checks that the menu closes.
    ///
    /// With the demo map's clock running, the Simulator takes 2 to 4 s to
    /// find an element once, so ten seconds held only two or three reads,
    /// too few to see one frame twice in a row (main c005788's full lane,
    /// run 40279577850, `testBackToStartWorksWhileTheClockRuns`: "Menu row
    /// never came to rest on the screen: menu.saveGame", line 569; it
    /// passed on a re-run). So it reads up to 12 times within 40 s,
    /// whichever comes first, and still wants two reads of one frame.
    private func menuRow(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(query.firstMatch.appears(within: 10), "Missing menu row: \(identifier)")
        let bounds = app.frame
        var last: CGRect?
        let deadline = Date().addingTimeInterval(40)
        var reads = 0
        repeat {
            reads += 1
            let row = query.allElementsBoundByIndex.first { copy in
                let frame = copy.frame
                return !frame.isEmpty && bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
            }
            if let row {
                let frame = row.frame
                if frame == last {
                    XCTAssertTrue(row.isEnabled, "Menu row is disabled: \(identifier)")
                    return row
                }
                last = frame
            } else {
                last = nil
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while reads < 12 && Date() < deadline
        XCTFail("Menu row never came to rest on the screen: \(identifier)")
        return query.firstMatch
    }

    /// Touches the menu row `button`; `query` finds its copies, whose
    /// staying on screen means the action did not run.
    private func touchMenuRow(_ button: XCUIElement, closing query: XCUIElementQuery, in app: XCUIApplication, name identifier: String) {
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
        if !menuCloses(query, timeout: 10) {
            point.tap()
        }
    }

    /// Whether no copy of the menu action is left that the player can
    /// touch within `timeout` seconds.
    private func menuCloses(_ query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !query.allElementsBoundByIndex.contains(where: touchable) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// What the screen shows, for a failure message: the building tool's
    /// preview (why a site is refused), its count, the action button, the
    /// map's selection and every other text on screen.
    private func screenText(in app: XCUIApplication) -> String {
        func label(_ element: XCUIElement) -> String { element.exists ? element.label : "(none)" }
        let action = app.buttons["panel.action"]
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).filter { !$0.isEmpty }
        return """
            Preview: \(label(app.staticTexts["building.preview"])); count: \(label(app.staticTexts["building.count"])); \
            action: \(label(action)) enabled \(action.exists && action.isEnabled); \
            map value: \(String(describing: app.descendants(matching: .any)["map"].firstMatch.value)); \
            texts: \(texts.joined(separator: " | "))
            """
    }

    private func requiredButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        // A phone on its side (decision 106) shows fewer of the start
        // screen's buttons at once: scroll their column to the one wanted.
        // Scroll until its middle shows, which is what `touchable` asks: a
        // button partly on screen is hittable to XCTest, so asking that left
        // the Demo Map, pushed down by the Lessons button (decision 266),
        // with its middle under the screen's edge (full lanes 39020766185
        // and 39026081385: frame y 357-456 on a 402-point-high screen).
        let button = app.buttons[identifier]
        if identifier.hasPrefix("start."), button.appears(within: 10) {
            XCTAssertTrue(app.scrollUntilShown(button), "The start screen's column never showed \(identifier)")
        }
        // The tools slide in once Build is pressed: tap one once it stays put.
        if identifier.hasPrefix("tool.") { button.waitUntilSettled() }
        return requiredButton(app.buttons.matching(identifier: identifier), name: identifier)
    }

    /// The rows of the menu `menu` (as `read` lists them), once two reads
    /// half a second apart agree and list a row. A native menu grows open
    /// from its lower edge: when the Simulator is slow its first row is
    /// still while the rows above it lie under the opening animation, so
    /// one row standing still does not say the menu is open (run
    /// 40257225657, attempt 2, `testThePerformanceMenuStaysStillAndChoosesWhileTheClockRuns`:
    /// 2 rows read as it opened, 7 three seconds later, every frame the
    /// same). Each read asks every row for its frame, which takes seconds
    /// with the clock running (see `menuRow`), so like `menuRow` it reads up
    /// to 12 times within 40 s, whichever comes first, and fails if no two
    /// reads in a row agree.
    private func settledRows(_ read: () -> [String], menu identifier: String) -> [String] {
        var last = read()
        let deadline = Date().addingTimeInterval(40)
        var reads = 1
        repeat {
            Thread.sleep(forTimeInterval: 0.5)
            let now = read()
            reads += 1
            if now == last && !now.isEmpty { return now }
            last = now
        } while reads < 12 && Date() < deadline
        XCTFail("The menu \(identifier) did not settle")
        return last
    }

    /// Whether `element` can be touched. Only a copy with a frame on the
    /// screen is asked: asking one without (an unplaced copy that
    /// ViewThatFits exposes, or a menu row still being laid out) whether it
    /// is hittable fails the test outright ("Failed to determine
    /// hittability … Activation point invalid", full lane run 38296188423,
    /// whose recording shows the menu drawn and still). The frame comes
    /// from a snapshot, which a gone copy fails without failing the test: a
    /// menu row can close between the query listing it and this read (main
    /// 584bddd's full lane, run 40051175469: Train 5 was chosen, the menu
    /// closed, and its row, listed 2 s before, was read as an element).
    private func touchable(_ element: XCUIElement) -> Bool {
        guard let frame = try? element.snapshot().frame, !frame.isEmpty,
              XCUIApplication().frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return element.exists && element.isHittable
    }

    private func requiredButton(_ query: XCUIElementQuery, name: String) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.appears(within: 10), "Missing UI flow button: \(name)")
        // ViewThatFits can also expose an unplaced copy of a menu action.
        // Find the button the player can touch, allowing the transition to
        // finish, and still fail if it is disabled or no copy is tappable.
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let button = query.allElementsBoundByIndex.first(where: touchable) {
                XCTAssertTrue(button.isEnabled, "UI flow button is disabled: \(name)")
                return button
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        let button = query.firstMatch
        XCTFail("UI flow button cannot be tapped: \(name) (exists \(button.exists), frame \(button.frame))")
        return query.firstMatch
    }

    private func assertHittable(_ element: XCUIElement, timeout: TimeInterval, message: String) {
        // Existence can precede the end of a menu or screen transition.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, message)
    }
}

/// Decision 381: the start screen's identifiers these tests reach
/// (``StartMenuEntry/identifier``, ``StartMenuChip/identifier``).
enum StartID {
    static let help = "start.help"
    static let saves = "start.saves"
    static let settings = "start.settings"
}
