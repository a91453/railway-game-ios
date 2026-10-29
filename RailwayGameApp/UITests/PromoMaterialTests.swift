import XCTest

/// Pictures and moving pictures for a promotional video (decision 475), in
/// Traditional Chinese on a device on its side. Run only by
/// `website-screenshots.yml` with its `promo` kind, one test at a time with
/// the Simulator's screen recorded around it; never by the gate or the full
/// lane (`ios-build.yml` skips this class). Each test opens one scene, keeps
/// screenshots of it as attachments the workflow exports, then moves the
/// camera (zoom, pan, the 3D map's turn and pinch) while the recording runs.
/// They test nothing: a step whose screen is not there is skipped, so one
/// scene that changes does not lose the others' pictures.
@MainActor
final class PromoMaterialTests: XCTestCase {
    private var marked = false

    // MARK: - The demo maps, by day, at dusk and at night

    func testSimpleDemoDay() { demo(at: "10:00", name: "simple-day") }
    func testSimpleDemoDusk() { demo(at: "17:40", name: "simple-dusk") }
    func testSimpleDemoNight() { demo(at: "21:30", name: "simple-night") }

    /// The game's menus over the simple demo by day: the layers, the lines,
    /// the goals, the forecast, the building mode.
    func testPanelsAndBuildMode() {
        let app = launch(extra: ["-demo-layout", "-demo-at", "10:00"])
        defer { app.terminate() }
        guard mapAppears(in: app, timeout: 240) else { return }
        settle(seconds: 4)
        keep("panels-map", app)

        pauseTheClock(in: app)
        openAndKeep("entry.lines", as: "panels-lines", in: app, close: "完成")
        let layers = app.buttons["map.quickLayer.more"]
        if layers.appears(within: 5), layers.becomesHittable(within: 3) {
            layers.tap()
            settle()
            keep("panels-layers", app)
            let done = app.buttons["layer.done"]
            if done.appears(within: 5) { done.tap() }
            settle()
        }
        openFromGameMenu("menu.goals", as: "panels-goals", in: app)
        closeSheetIfAny(in: app)
        tapIfThere("hud.time", in: app)
        if app.descendants(matching: .any)["hud.forecast"].firstMatch.appears(within: 5) {
            settle()
            keep("panels-forecast", app)
        }
        closeSheetIfAny(in: app)

        let build = app.buttons["dock.build"]
        if build.appears(within: 10), build.becomesHittable(within: 5) {
            build.tap()
            settle(seconds: 3)
            keep("panels-build", app)
            for tool in ["tool.track", "tool.station", "tool.train"] {
                let button = app.buttons[tool]
                if button.appears(within: 3), button.isHittable {
                    button.tap()
                    settle(seconds: 2)
                    keep("panels-build-\(tool.replacingOccurrences(of: "tool.", with: ""))", app)
                }
            }
        }
    }

    // MARK: - The scenes with freight and depots

    func testFreightScene() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        guard mapAppears(in: app, timeout: 120) else { return }
        settle(seconds: 4)
        keep("freight-map", app)
        // A station that is short of materials: its tag and, tapped, its card.
        let alert = app.buttons.matching(identifier: "map.alert").allElementsBoundByIndex.first(where: \.isHittable)
        if let alert {
            alert.tap()
            settle()
            keep("freight-station", app)
            let tag = app.buttons["map.stationTag"]
            if tag.appears(within: 3), tag.isHittable {
                tag.tap()
                settle(seconds: 2)
                keep("freight-station-card", app)
                closeSheetIfAny(in: app)
            }
        }
        followFirstTrain(prefix: "freight", in: app)
        showcase3D("freight", in: app)
    }

    func testDepotsScene() {
        let app = launch(extra: ["-screenshot-scene", "depots"])
        defer { app.terminate() }
        guard mapAppears(in: app, timeout: 120) else { return }
        settle(seconds: 4)
        showcase("depots", in: app)
    }

    // MARK: - The real-line demos

    func testHighSpeedDemo() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.highSpeed", timeout: 60)
        guard mapAppears(in: app, timeout: 600) else { return }
        settle(seconds: 6)
        showcase("highspeed", in: app)
    }

    func testTRADemo() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.tra", timeout: 60)
        guard mapAppears(in: app, timeout: 600) else { return }
        settle(seconds: 6)
        showcase("tra-yilan", in: app)
    }

    func testRealWorldDemo() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        guard mapAppears(in: app, timeout: 120) else { return }
        settle(seconds: 8)
        keep("realworld-demo-night", app)
        if waitForClock(from: 9, before: 17, in: app) {
            showcase("realworld-demo-day", in: app)
        }
    }

    // MARK: - Real-world maps: the cities of Taiwan

    func testCityTaipei() { city("tra-taipei", name: "taipei") }
    func testCityBanqiao() { city("tra-banqiao", name: "banqiao") }
    func testCityHsinchu() { city("tra-hsinchu", name: "hsinchu") }
    func testCityTaichung() { city("tra-taichung", name: "taichung") }
    func testCityTainan() { city("tra-tainan", name: "tainan") }
    func testCityKaohsiung() { city("tra-kaohsiung", name: "kaohsiung") }
    func testCityHualien() { city("tra-hualien", name: "hualien") }

    // MARK: - The new trains in the train showcase

    /// The new Puyuma, the Ming-Ri, Kaohsiung's and Taichung Green's trains
    /// side by side in the demo mode's train showcase (decision 434): its
    /// three camera views, then the turntable going round them by day, at
    /// dusk and at night with the buttons hidden. The 3D quality is the
    /// saving one, so the Simulator's software drawing keeps up.
    func testTrainShowcaseNewTrains() {
        let app = launch(extra: ["-\(Self.qualityKey)", "saving"])
        defer { app.terminate() }
        guard openTrainShowcase(in: app) else { return }
        pickShowcaseTrains(off: ["emu3000", "emu800", "highSpeed", "metroC341"],
                           on: ["MINGRI", "kaohsiung", "taichungGreen"], in: app)
        waitForPicture(in: app, timeout: 120)
        settle(seconds: 3)
        markAction()
        keep("showcase-front", app)
        for view in ["side", "overhead", "closeUp"] {
            tapIfThere("trainShowcase.camera.\(view)", in: app)
            settle(seconds: 5)
            keep("showcase-\(view)", app)
        }
        // A toggle in the button style: read as a button or a switch.
        let turntable = app.descendants(matching: .any)["trainShowcase.turntable"].firstMatch
        if turntable.appears(within: 5), turntable.isHittable { turntable.tap() }
        for (light, name) in [("白天", "day"), ("黃昏", "dusk"), ("夜晚", "night")] {
            let segment = app.segmentedControls["trainShowcase.light"].buttons[light]
            if !app.buttons["trainShowcase.hide"].exists {
                let reveal = app.descendants(matching: .any)["trainShowcase.reveal"].firstMatch
                if reveal.exists { reveal.tap() }
                _ = app.buttons["trainShowcase.hide"].appears(within: 5)
            }
            if segment.appears(within: 5), segment.isHittable { segment.tap() }
            settle(seconds: 2)
            tapIfThere("trainShowcase.hide", in: app)
            // The turntable goes round while the picture is held.
            settle(seconds: 6)
            keep("showcase-turn-\(name)", app)
            settle(seconds: 12)
            keep("showcase-turn-\(name)-later", app)
        }
    }

    // MARK: - Scenes

    /// The simple demo opened at `time`: the clock runs on from there.
    private func demo(at time: String, name: String) {
        let app = launch(extra: ["-demo-layout", "-demo-at", time])
        defer { app.terminate() }
        guard mapAppears(in: app, timeout: 300) else { return }
        settle(seconds: 5)
        showcase(name, in: app)
    }

    /// A real-world map on `placeID`: the first hours at night, then by
    /// the light of day, then at dusk if the clock gets there.
    private func city(_ placeID: String, name: String) {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        guard newGame.appears(within: 30) else { return XCTFail("No start screen") }
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        tapButton("newGame.realWorld", in: app, timeout: 60)
        let place = app.buttons.matching(identifier: "place.\(placeID)").firstMatch
        guard app.scrollUntilShown(place, in: app.collectionViews.firstMatch) else { return XCTFail("No place \(placeID)") }
        place.waitUntilSettled()
        app.tapMiddle(of: place)
        let start = app.buttons.matching(identifier: "realWorld.start").firstMatch
        guard start.appears(within: 30) else { return XCTFail("No Build Here button") }
        start.waitUntilSettled()
        start.tap()
        guard mapAppears(in: app, timeout: 120) else { return }
        settle(seconds: 8)
        keep("\(name)-night", app)
        if waitForClock(from: 9, before: 17, in: app) {
            settle(seconds: 2)
            showcase("\(name)-day", in: app)
        }
        if waitForClock(from: 17, before: 19, in: app, timeout: 240) {
            settle(seconds: 2)
            keep("\(name)-dusk", app)
            showcase3D("\(name)-dusk", in: app)
        }
    }

    /// The flat map's camera moves, then the 3D map. The recording's
    /// interesting part starts at the `[promo] action-start` line in the
    /// log (the workflow turns it into an offset).
    private func showcase(_ name: String, in app: XCUIApplication) {
        keep("\(name)-map", app)
        markAction()
        let zoomIn = app.buttons["放大"]
        let zoomOut = app.buttons["縮小"]
        if zoomIn.appears(within: 5) {
            for step in 1...2 where zoomIn.isHittable {
                zoomIn.tap()
                settle(seconds: 2)
                keep("\(name)-map-zoom\(step)", app)
            }
        }
        slowDrag(in: app, from: CGVector(dx: 0.7, dy: 0.55), to: CGVector(dx: 0.3, dy: 0.45))
        settle(seconds: 3)
        keep("\(name)-map-pan", app)
        slowDrag(in: app, from: CGVector(dx: 0.3, dy: 0.45), to: CGVector(dx: 0.7, dy: 0.6))
        settle(seconds: 3)
        if zoomOut.exists {
            for _ in 1...2 where zoomOut.isHittable {
                zoomOut.tap()
                settle(seconds: 1)
            }
        }
        settle(seconds: 3)
        showcase3D(name, in: app)
    }

    /// Opens the 3D map from the flat one, turns and pinches it, and closes
    /// it.
    private func showcase3D(_ name: String, in app: XCUIApplication) {
        let open3D = app.buttons["map.open3D"]
        guard open3D.appears(within: 10), open3D.becomesHittable(within: 10) else { return }
        open3D.tap()
        let close = app.buttons["map3D.close"]
        guard close.appears(within: 60) else { return }
        markAction()
        // The Simulator draws the 3D map in software and takes up to a
        // minute to show it: a picture of the spinner is 180 KB, one of the
        // map 1.9 MB or more.
        waitForPicture(in: app, timeout: 120)
        settle(seconds: 3)
        keep("\(name)-3d-far", app)
        let view = app.descendants(matching: .any)["map3D.view"].firstMatch
        let target = view.exists ? view : app
        // Pinching in tilts the map, two fingers turn it, a drag moves it.
        target.pinch(withScale: 1.8, velocity: 0.6)
        settle(seconds: 4)
        keep("\(name)-3d-tilt", app)
        target.rotate(CGFloat.pi / 3, withVelocity: 0.4)
        settle(seconds: 3)
        keep("\(name)-3d-turn", app)
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        settle(seconds: 3)
        keep("\(name)-3d-move", app)
        target.pinch(withScale: 2.0, velocity: 0.6)
        settle(seconds: 5)
        keep("\(name)-3d-near", app)
        target.pinch(withScale: 1.8, velocity: 0.6)
        settle(seconds: 8)
        keep("\(name)-3d-street", app)
        // The trains run past while the picture is held.
        settle(seconds: 10)
        keep("\(name)-3d-held", app)
        if close.exists, close.isHittable {
            close.tap()
            _ = close.disappears(within: 10)
        }
    }

    /// Follows the freight scene's first train in the fleet list and shows it
    /// from the 3D map when the follow bar offers that.
    private func followFirstTrain(prefix: String, in app: XCUIApplication) {
        markAction()
        let build = app.buttons["dock.build"]
        guard build.appears(within: 10), build.becomesHittable(within: 5) else { return }
        build.tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        guard fleet.appears(within: 5) else { return }
        fleet.tap()
        let follow = app.buttons["fleet.follow.貨運列車 1"]
        var reached = false
        for _ in 0..<12 {
            if follow.exists, follow.isHittable { reached = true; break }
            // Start in the margin beside the cards: a drag that starts on a card did not move the list.
            let margin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            margin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)))
        }
        guard reached else { return }
        follow.tap()
        guard app.buttons["train.unfollow"].appears(within: 5) else { return }
        settle(seconds: 4)
        keep("\(prefix)-train-follow", app)
        let in3D = app.buttons["follow.map3D"]
        if in3D.appears(within: 3), in3D.isHittable {
            in3D.tap()
            if app.buttons["map3D.close"].appears(within: 60) {
                settle(seconds: 10)
                keep("\(prefix)-train-3d", app)
                settle(seconds: 8)
                keep("\(prefix)-train-3d-later", app)
                app.buttons["map3D.close"].tap()
            }
        }
    }

    /// Opens the train showcase from the settings: the version row tapped
    /// five times shows the demo mode's rows (as `TrainShowcaseUITests`).
    private func openTrainShowcase(in app: XCUIApplication) -> Bool {
        let settings = app.buttons["start.settings"]
        guard settings.appears(within: 30) else { XCTFail("No start screen"); return false }
        settings.tap()
        guard app.switches["settings.music"].appears(within: 10) else { XCTFail("No settings"); return false }
        let version = app.descendants(matching: .any)["settings.version"].firstMatch
        guard app.dragUntilWhollyOnScreen(version, clearOf: .slider) else { XCTFail("No version row"); return false }
        let showcase = app.buttons["settings.trainShowcase"]
        let demoSwitch = app.switches["settings.demoMode"]
        for _ in 0..<4 where !showcase.exists && !demoSwitch.exists {
            for _ in 0..<5 { version.tap() }
            _ = showcase.appears(within: 3) || demoSwitch.appears(within: 1)
        }
        guard app.dragUntilWhollyOnScreen(showcase, clearOf: .slider) else { XCTFail("No train showcase row"); return false }
        showcase.tap()
        guard app.buttons["trainShowcase.pick"].appears(within: 60) else { XCTFail("The showcase did not open"); return false }
        return true
    }

    /// Takes the trains `off` the showcase and puts the ones `on` on it, in
    /// the picker's order.
    private func pickShowcaseTrains(off: [String], on: [String], in app: XCUIApplication) {
        let pick = app.buttons["trainShowcase.pick"]
        guard pick.becomesHittable(within: 10) else { return }
        pick.tap()
        let list = app.collectionViews.containing(.any, identifier: "trainShowcase.cars.puyuma").firstMatch
        guard list.appears(within: 10) else { return }
        for key in Self.pickerOrder where off.contains(key) || on.contains(key) {
            let row = app.buttons["trainShowcase.pick.\(key)"]
            if app.scrollUntilShown(row, in: list), row.isEnabled { row.tap() }
        }
        tapIfThere("trainShowcase.pick.done", in: app)
        _ = app.buttons["trainShowcase.pick.done"].disappears(within: 10)
    }

    /// The 3D quality setting's key (`Map3DQuality.key`).
    private static let qualityKey = "map3D.quality"
    /// The picker's rows that the showcase scene touches, in the picker's
    /// order (`Map3DShowcase.catalog`).
    private static let pickerOrder = ["emu3000", "emu800", "puyuma", "MINGRI", "highSpeed", "metroC341", "kaohsiung", "taichungGreen"]

    // MARK: - Helpers

    private func launch(extra: [String] = []) -> XCUIApplication {
        // Keep going after a failed step: the pictures already kept still
        // count, and a missing screen only costs its own pictures.
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"] + extra
        app.launch()
        return app
    }

    private func mapAppears(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let appeared = app.descendants(matching: .any)["map"].firstMatch.appears(within: timeout)
        if !appeared { XCTFail("The map never opened") }
        return appeared
    }

    /// Prints where the recording's camera work starts, once a test: the
    /// workflow turns it into an offset in MANIFEST.txt.
    private func markAction() {
        guard !marked else { return }
        marked = true
        print("[promo] action-start \(Date().timeIntervalSince1970)")
    }

    /// Waits until the screen holds a picture: a screenshot of the 3D
    /// map's spinner is small, one of the map large.
    private func waitForPicture(in app: XCUIApplication, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if XCUIScreen.main.screenshot().pngRepresentation.count > 600_000 { return }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func settle(seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Keeps the whole screen as an attachment named `name`, which the
    /// workflow exports as `name.png` (the app's own screenshot of a device
    /// on its side comes out turned; the workflow turns it back).
    private func keep(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func slowDrag(in app: XCUIApplication, from: CGVector, to: CGVector) {
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: to), withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Waits until the clock reads from `start` o'clock to before `end`;
    /// whether it did.
    @discardableResult
    private func waitForClock(from start: Int, before end: Int, in app: XCUIApplication, timeout: TimeInterval = 600) -> Bool {
        let clock = app.buttons["hud.time"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if clock.exists, let hour = Self.hour(in: clock.label), hour >= start, hour < end { return true }
            Thread.sleep(forTimeInterval: 3)
        }
        return false
    }

    private static func hour(in label: String) -> Int? {
        guard let time = label.range(of: "[0-9]{1,2}:[0-9]{2}", options: .regularExpression) else { return nil }
        return Int(label[time].split(separator: ":")[0])
    }

    private func pauseTheClock(in app: XCUIApplication) {
        let pause = app.buttons.matching(NSPredicate(format: "label == %@", "暫停")).firstMatch
        if pause.appears(within: 5), pause.becomesHittable(within: 1) {
            pause.tap()
        }
    }

    private func tapIfThere(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons.matching(identifier: identifier).allElementsBoundByIndex.first { $0.isHittable && $0.isEnabled }
        button?.tap()
    }

    /// Taps `identifier`, keeps the screen as `name`, and taps `close`.
    private func openAndKeep(_ identifier: String, as name: String, in app: XCUIApplication, close: String) {
        let button = app.buttons[identifier]
        guard button.appears(within: 5), button.becomesHittable(within: 3) else { return }
        button.tap()
        settle(seconds: 3)
        keep(name, app)
        let done = app.buttons[close]
        if done.exists, done.isHittable { done.tap() }
        settle()
    }

    private func openFromGameMenu(_ item: String, as name: String, in app: XCUIApplication) {
        pauseTheClock(in: app)
        tapIfThere("hud.menu", in: app)
        if !app.buttons[item].appears(within: 3) {
            tapIfThere("menu.more", in: app)
        }
        guard app.buttons[item].appears(within: 3) else { return }
        tapIfThere(item, in: app)
        settle(seconds: 3)
        keep(name, app)
    }

    private func closeSheetIfAny(in app: XCUIApplication) {
        for label in ["完成", "關閉", "Done"] {
            let button = app.buttons[label].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                settle()
                return
            }
        }
    }

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
