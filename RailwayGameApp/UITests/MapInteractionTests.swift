import UIKit
import XCTest

@MainActor
final class MapInteractionTests: XCTestCase {
    /// Assert what is under the camera, rather than only the session's target
    /// ID: this fails if MapView stops reacting to target changes while paused.
    func testSwitchingFollowTargetWhilePausedCentersTheCamera() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        XCTAssertTrue(app.buttons["Resume"].exists, "The demo must stay paused throughout this test")

        for name in ["Train 1", "Train 2"] {
            // Decision 114: the tools show once Build is pressed; Select
            // (Done) below closes them again.
            app.buttons["dock.build"].tap()
            // The tools slide in from the side: a tap found while they
            // moved landed 5 pt left of Train on the map, which, with the
            // network tool chosen, picked a track start and folded the
            // card (PR #326's run on 6d23fab).
            let trainTool = app.buttons["tool.train"]
            trainTool.waitUntilSettled()
            trainTool.tap()
            let fleet = app.buttons["train.fleetOverview"]
            XCTAssertTrue(fleet.appears(within: 5))
            if !fleet.becomesHittable(within: 1) { app.swipeUp() }
            fleet.tap()
            let follow = app.buttons["fleet.follow.\(name)"]
            // The overview's list makes a row only once it scrolls into
            // view, and since the summary card's roster button (#615) Train
            // 2's row starts below the screen of a phone on its side, where
            // `swipeUp()` left the list where it was (this branch's run
            // 38619859987): drag it until the row is made and wholly shown.
            XCTAssertTrue(app.dragUntilWhollyOnScreen(follow), "The overview's \(name) row never came into reach")
            follow.tap()
            XCTAssertTrue(app.buttons["train.unfollow"].appears(within: 5))
            let speed = app.descendants(matching: .any)["train.speed"].firstMatch
            XCTAssertTrue(speed.appears(within: 5))
            XCTAssertTrue(speed.label.contains("km/h"), "Train controls must show physical speed")
            XCTAssertFalse(app.steppers.containing(NSPredicate(format: "label BEGINSWITH 'Rate '")).firstMatch.exists,
                           "The obsolete per-minute rate must not remain a second speed control")
            app.buttons["tool.select"].tap()
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue((map.value as? String)?.hasPrefix("Train · \(name) ·") == true,
                          "The actual camera center must pick \(name); value: \(String(describing: map.value))")
            XCTAssertTrue(app.buttons["Resume"].exists)
        }
    }

    /// Decision 246 (a player's report: no guide to where a city's request
    /// is): the status bar's button opens the requests, and "Show on map"
    /// takes the camera to where one points, flagged, with its card.
    func testARequestShownOnTheMapIsFlaggedThere() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-city-requests", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let requests = app.buttons["hud.requests"]
        XCTAssertTrue(requests.appears(within: 5), "the status bar's requests button")
        requests.tap()
        let show = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'requests.show.'")).firstMatch
        XCTAssertTrue(app.buttons["goals.done"].appears(within: 5), "the requests open")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(show), "a request's Show on map never came into reach")
        show.tap()
        let flag = app.buttons["map.request.focus"]
        XCTAssertTrue(flag.appears(within: 5), "the request is flagged on the map")
        XCTAssertTrue(flag.becomesHittable(within: 5))
        // The camera went there: the flag stands near the map's middle.
        let middle = CGPoint(x: map.frame.midX, y: map.frame.midY)
        XCTAssertLessThan(abs(flag.frame.midX - middle.x), map.frame.width * 0.3, "flag at \(flag.frame), map \(map.frame)")
        XCTAssertLessThan(abs(flag.frame.midY - middle.y), map.frame.height * 0.3, "flag at \(flag.frame), map \(map.frame)")
        let card = app.descendants(matching: .any)["map.request.card"].firstMatch
        XCTAssertTrue(card.appears(within: 5), "its card says how far it has come")
        app.buttons["map.request.card.close"].tap()
        XCTAssertTrue(card.disappears(within: 5))
    }

    /// TestFlight 56.1: a train tapped with no tool chosen can be followed
    /// from the details card, as from the train tool.
    func testTheDetailsCardFollowsATappedTrain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        XCTAssertTrue(app.buttons["Resume"].exists, "The demo must stay paused throughout this test")

        // Bring Train 1 under the camera: follow it from the fleet list,
        // then let go; paused, it stays in the middle of the map.
        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        XCTAssertTrue(fleet.appears(within: 5))
        if !fleet.becomesHittable(within: 1) { app.swipeUp() }
        fleet.tap()
        let fleetFollow = app.buttons["fleet.follow.Train 1"]
        XCTAssertTrue(fleetFollow.appears(within: 5))
        for _ in 0..<3 where !fleetFollow.becomesHittable(within: 1) { app.swipeUp() }
        fleetFollow.tap()
        let unfollow = app.buttons["train.unfollow"]
        XCTAssertTrue(unfollow.appears(within: 5))
        unfollow.tap()
        XCTAssertTrue(unfollow.disappears(within: 5))
        app.buttons["tool.select"].tap()

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((map.value as? String)?.hasPrefix("Train · Train 1 ·") == true,
                      "The tap must pick Train 1; value: \(String(describing: map.value))")
        let follow = app.buttons["inspector.train.follow"]
        XCTAssertTrue(follow.appears(within: 5))
        XCTAssertTrue(follow.becomesHittable(), "The follow button shows without scrolling the card")
        follow.tap()
        XCTAssertTrue(unfollow.appears(within: 5), "Following shows the follow bar")
        XCTAssertTrue(follow.label.contains("Following"), "label: \(follow.label)")
        follow.tap()
        XCTAssertTrue(unfollow.disappears(within: 5), "A second tap stops following")
        XCTAssertTrue(app.buttons["Resume"].exists)
    }

    func testDemoMapOpensOnItsNetwork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        // A new game starts with no tool chosen: a tap selects (decision
        // 114: there is no Select button outside building).
        XCTAssertTrue(app.buttons["dock.build"].appears(within: 10))
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((map.value as? String)?.contains("Central") == true,
                      "The opening camera must put Central at the map view's center; value: \(String(describing: map.value))")
    }

    /// #593 (a player's report, an iPhone on its side): the demo opened
    /// with a station under the zoom buttons. The opening camera keeps
    /// every station clear of the buttons in the map's corners.
    func testTheOpeningKeepsTheStationsClearOfTheCornerButtons() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let stations = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(stations.appears(within: 10))
        // The layer strip's More, where the round layers button was until
        // decision 226 (2026-10-15) left the list one way in.
        let buttons = [app.buttons["Zoom in"], app.buttons["Zoom out"], app.buttons["map.quickLayer.more"]]
        for button in buttons { XCTAssertTrue(button.appears(within: 10), "\(button)") }
        // The buttons are measured after the first layout, and the camera
        // opens again clear of them: give it the time.
        func covered() -> [String] {
            let origin = map.frame.origin
            let points = ((stations.value as? String) ?? "").split(separator: ";").compactMap { pair -> CGPoint? in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: origin.x + xy[0], y: origin.y + xy[1]) : nil
            }
            XCTAssertFalse(points.isEmpty, "The demo has stations")
            return points.flatMap { point in
                buttons.filter { $0.frame.insetBy(dx: -4, dy: -4).contains(point) }.map { "\(point) under \($0.label)" }
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while !covered().isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertEqual(covered(), [], "No station opens under a corner button")
    }

    /// Decision 220: holding a station opens its panel (decision 119) and
    /// the map traces its busiest trips, which the map's value reads out
    /// (the arcs are drawn, not elements).
    func testHoldingAStationTracesItsBusiestTrips() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        // The camera opens again clear of the corner buttons once they are
        // measured (#593): a hold at the map's middle three seconds in found
        // no station under it, and the map does not start a hold off a
        // station (main a0acef1's full lane, run 38798340562: held 756 ms
        // at (437, 201), no panel). The stations' places, once they stand
        // still half a second, give the one nearest the middle: Central.
        let stations = app.descendants(matching: .any)["map.stations"].firstMatch
        XCTAssertTrue(stations.appears(within: 10))
        func places() -> [CGPoint] {
            ((stations.value as? String) ?? "").split(separator: ";").compactMap { pair in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
        }
        // The opening camera may still move clear of the corner buttons
        // for two seconds after the map opens (`MapView.openingSettles`):
        // places that stood still for half a second inside that time could
        // still move (main 878adaf's full lane and its run 38888973282:
        // held at (437, 201) two seconds in, no panel). So they are read
        // once that time is over, and once they stand still for a second.
        let opened = Date()
        var last = places()
        let settle = opened.addingTimeInterval(12)
        while Date() < settle {
            Thread.sleep(forTimeInterval: 1)
            let now = places()
            if !now.isEmpty, now == last, Date().timeIntervalSince(opened) > 3 { break }
            last = now
        }
        let middle = CGPoint(x: map.frame.width / 2, y: map.frame.height / 2)
        guard let central = last.min(by: { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }) else {
            XCTFail("The demo has stations")
            return
        }
        map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: central.x, dy: central.y)).press(forDuration: 0.8)
        XCTAssertTrue(app.navigationBars["Central"].appears(within: 5), "The hold opens Central's panel")
        func traces() -> Bool { (map.value as? String)?.contains("Busiest trips:") == true }
        let deadline = Date().addingTimeInterval(10)
        while !traces() && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(traces(), "The map traces Central's trips; value: \(String(describing: map.value))")
    }

    /// TestFlight 60.1: renaming a station took three taps before a letter
    /// could be typed. The station tag's pencil puts up the rename alert
    /// with its field ready, while the clock runs and redraws the panel.
    func testTheStationTagsPencilRenamesAtOnce() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pencil = app.buttons["map.stationTag.edit"]
        XCTAssertTrue(pencil.appears(within: 5), "A tap on Central picks it and shows its tag")
        XCTAssertTrue(pencil.becomesHittable())
        pencil.tap()

        let alert = app.alerts["Rename Station"]
        XCTAssertTrue(alert.appears(within: 5), "The pencil puts up the rename alert")
        // The alert's UIKit field does not carry SwiftUI's identifier
        // (`rename.field`): run 38525633704 found it only by its kind.
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.appears(within: 5))
        // No tap on the field: the keyboard is already its. It comes to the
        // field a moment after the alert does: typed at once, the letters
        // went nowhere and the name stayed "Central" (main 3b45ba3's full
        // lane, run 38831761775). So the test waits, still without a tap,
        // until the field has the keyboard; a field that never gets it is
        // the regression this test is for.
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, "The rename field takes the keyboard by itself")
        app.typeText(" Plaza")
        XCTAssertEqual(field.value as? String, "Central Plaza")
        alert.buttons["Rename"].tap()
        XCTAssertTrue(alert.disappears(within: 5))
        XCTAssertTrue(app.navigationBars["Central Plaza"].appears(within: 5),
                      "The station panel shows the new name")
    }

    func testZoomingOutShowsTheWholeLargeMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        // A new game starts with no tool chosen: a tap selects (decision
        // 114: there is no Select button outside building).
        XCTAssertTrue(app.buttons["dock.build"].appears(within: 10))
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let zoomOut = app.buttons["Zoom out"]
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomOut.appears(within: 10))
        XCTAssertTrue(zoomIn.appears(within: 10))

        for _ in 0..<12 {
            if !zoomOut.isEnabled { break }
            zoomOut.tap()
        }
        XCTAssertFalse(zoomOut.isEnabled, "The whole 1024 × 1024 map must fit within 12 zoom-out taps")
        XCTAssertTrue(zoomIn.isEnabled)
        XCTAssertTrue(zoomIn.becomesHittable())

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((map.value as? String)?.contains("Central") == true,
                      "Tapping the whole map's center must still select Central; value: \(String(describing: map.value))")
    }

    /// A drag or pinch must not become the first/second tap of a new
    /// construction. After navigation, ordinary taps must still build.
    func testNavigationDoesNotChooseConstructionPoints() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        // Decision 114: Build opens the tools, starting with the network.
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10))
        // The tools slide in from the side: a point read mid-slide falls on
        // the map, which under the network tool chooses a track start (as
        // #326 found for the train tool).
        network.waitUntilSettled()
        network.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(clear.isEnabled)

        // In the map's leading half: the details card floats over its
        // trailing side while a tool is chosen (decision 106).
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertFalse(clear.isEnabled, "Dragging must not pick a track anchor")
        map.pinch(withScale: 3, velocity: 1)
        XCTAssertFalse(clear.isEnabled, "Pinching must not pick a track anchor")
        // Decision 123: on a phone the zoom buttons give way beside the
        // details card, which a chosen tool keeps open. Fold the card to
        // read them, then open it again for the tool's buttons. Each tap is
        // tried twice, like the anchor's below: a touch can be lost after
        // the pinch to the closest zoom.
        let zoomIn = app.buttons["Zoom in"]
        let zoomHidden = !zoomIn.exists
        // Decision 136: a phone on its side (a compact height) folds the
        // card when a track starts. Not read from the zoom buttons: beside
        // the narrower card of decision 106's later fix they stay. A phone on
        // its side is under 500 points tall, an iPad never.
        let cardFolds = app.frame.height < 500
        let controls = app.buttons["controls.toggle"]
        func toggleControls(to label: String) {
            func labelled() -> Bool {
                XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: controls)],
                                 timeout: 10) == .completed
            }
            controls.tap()
            if !labelled() { controls.tap() }
            XCTAssertTrue(labelled(), "The details card did not change to \(label)")
        }
        if zoomHidden { toggleControls(to: "Show Controls") }
        XCTAssertTrue(zoomIn.appears(within: 10))
        XCTAssertFalse(zoomIn.isEnabled, "A pinch past 2× must reach the camera's maximum zoom")
        XCTAssertTrue(app.buttons["Zoom out"].isEnabled)
        if zoomHidden {
            toggleControls(to: "Hide Controls")
            XCTAssertTrue(clear.appears(within: 10))
            XCTAssertFalse(clear.isEnabled)
        }

        // After a pinch to the closest zoom an accessibility query can hold
        // the app's main thread for seconds (run 37161734560's recording),
        // and a touch held across that is failed by the tap recognizer: wait
        // for the anchor, and tap once more if the first touch was lost.
        // Decision 136: on a phone (where the card folded above) the
        // start folds the card, so the map's track gives the room to draw
        // in, and the map's ✓ builds; elsewhere the card's Clear and Build
        // Track stay.
        let anchor = map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
        func anchored() -> Bool {
            let signal = cardFolds
                ? XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Show Controls"), object: controls)
                : XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: clear)
            return XCTWaiter().wait(for: [signal], timeout: 10) == .completed
        }
        anchor.tap()
        if !anchored() { anchor.tap() }
        XCTAssertTrue(anchored(), "Taps after navigating must still reach the network tool")
        // The far end, tried twice like the anchor: the same lost touch.
        let far = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let build = cardFolds
            ? app.buttons["map.build.confirm"]
            : app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        func previewed() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: build)],
                             timeout: 10) == .completed
        }
        far.tap()
        if !previewed() { far.tap() }
        XCTAssertTrue(previewed(), "Two taps after a pinch must make a buildable preview")
        build.tap()
        // Built track disables the card's button for good (its end starts
        // the next stretch), and takes the map's ✓ away with the preview;
        // the "Built …" banner clears itself after 4 s (#182), within one
        // slow accessibility query.
        let built = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: cardFolds ? "exists == false" : "isEnabled == false"), object: build
        )
        XCTAssertEqual(XCTWaiter().wait(for: [built], timeout: 10), .completed, "Build Track did not build")
    }

    func testZoomButtonsRemainUsableWithoutPinching() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        // A step doubles the size (Stage E1): 32 points per 16 m to 64, the
        // maximum zoom. On a slow Simulator a touch was lost and the map
        // never moved (full lane run 38458089903, its screen recording):
        // the tap is tried again only when the camera's zoom (`map.camera`)
        // has not changed, so a step that grows less than double is not
        // made up by a second one (the PR #526–#626 review, C6).
        func atMaximum() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: zoomIn)],
                             timeout: 10) == .completed
        }
        let zoom = app.descendants(matching: .any)["map.camera"].firstMatch
        XCTAssertTrue(zoom.appears(within: 10))
        // The opening camera may frame the game again as its layout
        // settles: read the zoom once it has kept still for two seconds.
        var settled = zoom.value as? String
        for _ in 0..<10 {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", settled ?? ""), object: zoom)
            guard XCTWaiter().wait(for: [changed], timeout: 2) == .completed else { break }
            settled = zoom.value as? String
        }
        let before = try XCTUnwrap(settled.flatMap(Double.init))
        func moved() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", settled ?? ""), object: zoom)],
                             timeout: 10) == .completed
        }
        zoomIn.tap()
        if !moved() { zoomIn.tap() }
        XCTAssertTrue(moved(), "Zoom in did not move the camera")
        let after = try XCTUnwrap((zoom.value as? String).flatMap(Double.init))
        XCTAssertEqual(after / before, 2, accuracy: 0.001, "A step doubles the size: \(before) to \(after)")
        XCTAssertTrue(atMaximum(), "64 points per 16 m is the maximum zoom")
        XCTAssertTrue(zoomOut.isEnabled)
        zoomOut.tap()
        XCTAssertTrue(zoomIn.isEnabled)
    }

    /// TestFlight 56.1: the button to expand the map was tapped by mistake
    /// beside the building tools' Done, and buying a tile then looked like
    /// building. It is not shown while the tools are out; choosing a tile
    /// says so on the button; the pill buys in words, not with a build's ✓.
    func testTheMapExpansionIsNotMistakenForBuilding() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        let expansion = app.buttons["map.expansion"]
        XCTAssertTrue(expansion.appears(within: 30), "A blank map can be expanded")

        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10))
        network.waitUntilSettled()
        XCTAssertTrue(expansion.disappears(within: 5), "No Expand the Map beside the building tools")
        let done = app.buttons["tool.select"]
        XCTAssertTrue(done.appears(within: 5))
        done.tap()
        XCTAssertTrue(expansion.appears(within: 5), "Back once the tools are put away")

        expansion.tap()
        XCTAssertEqual(expansion.label, "Stop expanding the map")
        // The tile below the one owned: on a phone
        // on its side the expansion's pill (with its Done) stood over it
        // since the tools became a column (#626; main bf12187's full lane,
        // run 38641908091, tapped Done at (437, 301)). The camera now
        // shows the tiles for sale above the pill (the PR #627–#646
        // review), so a tap there chooses the tile.
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let tiles = app.descendants(matching: .any)["map.expansion.tiles"].firstMatch
        XCTAssertTrue(tiles.appears(within: 10))
        let centres = ((tiles.value as? String) ?? "").split(separator: ";").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
        XCTAssertFalse(centres.isEmpty, "Tiles for sale: \(String(describing: tiles.value))")
        // The lowest; in a row of several, the middle one (the land's
        // column). Run 38672710744: one tile below, at (437, 281).
        let bottom = try XCTUnwrap(centres.map(\.y).max())
        let row = centres.filter { abs($0.y - bottom) < 1 }.sorted { $0.x < $1.x }
        let below = row[row.count / 2]
        let origin = map.frame.origin
        let target = CGPoint(x: origin.x + below.x, y: origin.y + below.y)
        XCTAssertFalse(expansion.frame.contains(target), "The tile below the land is under the pill: \(target), \(expansion.frame)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.x, dy: target.y)).tap()
        let buy = app.buttons["map.expansion.buy"]
        XCTAssertTrue(buy.appears(within: 5), "A pill to buy the tile chosen")
        XCTAssertTrue(buy.label.hasPrefix("Buy tile, $"), "The pill says what it buys: \(buy.label)")
        XCTAssertFalse(app.buttons["map.build.confirm"].exists, "Not a build's ✓")

        expansion.tap()
        XCTAssertTrue(buy.disappears(within: 5), "Done leaves the expansion")
        XCTAssertEqual(expansion.label, "Expand the map")
    }

    func testRotationKeepsTheCameraZoom() {
        continueAfterFailure = false
        // Decision 106: a phone plays on its side, so it turns from one
        // side to the other.
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.terminate()
        }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        zoomIn.tap()
        XCTAssertFalse(zoomIn.isEnabled)

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertFalse(zoomIn.isEnabled, "Changing the layout must keep the camera's maximum zoom")
        // Waiting for the app to idle does not wait for the turn: a tap
        // found 0.5 s after it took the button's place in the turning
        // window, landed on the map beside the overview, which moved the
        // camera and left the zoom alone (the branch run of PR #326; the
        // passing runs tapped a second after the turn). Tap once the
        // button stays put.
        let zoomOut = app.buttons["Zoom out"]
        zoomOut.waitUntilSettled()
        zoomOut.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: zoomIn)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, "Zoom out did not leave room to zoom in")
    }

    /// TestFlight 59.1: building on a phone on its side opens and folds the
    /// details card again and again (the tool, a start tapped, Clear, done);
    /// each change zoomed the map out to the whole selected line. Building
    /// leaves the camera where the player zoomed it.
    func testBuildingKeepsTheCameraZoom() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        // A slow Simulator can lose the tap (main 81f3d4f's full lane):
        // tap once more if the camera has not reached its closest zoom.
        func closest() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: zoomIn)],
                             timeout: 10) == .completed
        }
        zoomIn.tap()
        if !closest() { zoomIn.tap() }
        XCTAssertTrue(closest(), "Zoom in must reach the camera's closest zoom")
        let zoom = app.descendants(matching: .any)["map.camera"].firstMatch
        XCTAssertTrue(zoom.appears(within: 5))
        let zoomed = zoom.value as? String
        XCTAssertNotNil(zoomed)
        // The card moves in and out with a transition: read the zoom once
        // it has had time to move the camera, as the bug did at once.
        func keepsZoom(_ step: String) {
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", zoomed ?? ""), object: zoom)
            XCTAssertNotEqual(XCTWaiter().wait(for: [moved], timeout: 2), .completed,
                              "\(step) must keep the camera's zoom; was \(zoomed ?? "nil"), now \(String(describing: zoom.value))")
        }

        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10))
        network.waitUntilSettled()
        keepsZoom("Opening the network tool")

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let hud = app.otherElements["map.constructionHUD"]
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35)).tap()
        keepsZoom("Tapping a track start")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(hud.appears(within: 5), "Two taps must preview a stretch")
        keepsZoom("Previewing a stretch")

        let cancel = app.buttons["map.build.cancel"]
        XCTAssertTrue(cancel.appears(within: 5))
        cancel.tap()
        XCTAssertTrue(hud.disappears(within: 5))
        keepsZoom("Clearing the stretch")

        buildEntry.waitUntilSettled()
        buildEntry.tap()
        XCTAssertTrue(network.disappears(within: 5), "Build pressed again must close the tools")
        keepsZoom("Closing the tools")
    }

    func testMapLayersSheetTogglesAndDismisses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")

        // The status pill lays itself out again just after the demo opens,
        // and a tap found before then lands where the pause button was: on
        // the map, leaving the clock running (main 7eb3892's full lane, run
        // 38599636375: found at (555, 35), drawn at (425, 44)). Wait until
        // it stays put, and tap again while the game has not paused.
        let pause = app.buttons["Pause"].firstMatch
        let resume = app.buttons["Resume"].firstMatch
        XCTAssertTrue(pause.appears(within: 10))
        pause.waitUntilSettled()
        pause.tap()
        if !resume.appears(within: 5) {
            pause.waitUntilSettled()
            pause.tap()
        }
        XCTAssertTrue(resume.appears(within: 5), "Pause must pause the game")

        // The layer strip's More opens the list (decision 226, 2026-10-15:
        // the round layers button only while the strip does not show).
        let layersButton = app.buttons["map.quickLayer.more"]
        XCTAssertTrue(layersButton.appears(within: 10), "The layer strip's More must be visible over the map")
        layersButton.tap()

        let stationNamesToggle = app.switches["layer.stationNames"]
        XCTAssertTrue(stationNamesToggle.appears(within: 5), "Station names toggle must exist in MapLayerSheet")

        let waitingCountsToggle = app.switches["layer.waitingCounts"]
        XCTAssertTrue(waitingCountsToggle.appears(within: 5), "Waiting counts toggle must exist in MapLayerSheet")

        let catchmentRingsToggle = app.switches["layer.catchmentRings"]
        XCTAssertTrue(catchmentRingsToggle.appears(within: 5), "Catchment rings toggle must exist in MapLayerSheet")

        let heatmapRow = app.switches["layer.populationHeatmap"]
        XCTAssertTrue(heatmapRow.appears(within: 5), "Population heatmap row must exist")
        // SwiftUI exposes a labelled wrapper and its actual UISwitch as
        // separate switches. Use the control's activation point; tapping
        // the wrapper or coordinates in its frame can leave it unchanged.
        let heatmapToggle = heatmapRow.switches.firstMatch
        XCTAssertTrue(heatmapToggle.appears(within: 5), "Population heatmap control must exist")
        XCTAssertTrue(heatmapToggle.isEnabled, "The implemented population overlay must be available")
        // The sheet may still be presenting when the switch first exists,
        // and a tap then can be lost (the value stays "0"): wait until it
        // can be hit, and tap again while it is still off.
        for _ in 0..<3 where heatmapToggle.value as? String != "1" {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: heatmapToggle)
            _ = XCTWaiter.wait(for: [hittable], timeout: 5)
            heatmapToggle.tap()
            let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: heatmapToggle)
            _ = XCTWaiter.wait(for: [switched], timeout: 3)
        }
        XCTAssertEqual(heatmapToggle.value as? String, "1", "Population heatmap must be on before dismissing")

        let doneButton = app.buttons["layer.done"]
        XCTAssertTrue(doneButton.appears(within: 5))
        doneButton.tap()

        // The layers button exists under the sheet too: what shows the
        // sheet closed is its Done button gone. With the heatmap just
        // drawn the app can be slow: one query took 30 s there and the
        // sheet was still up 5 s after Done (PR run 38064937060 on
        // 1ee3676, which touched no map or layer code). Allow it longer,
        // and tap Done again only if it is still there to tap.
        if !doneButton.disappears(within: 15), doneButton.isHittable {
            doneButton.tap()
        }
        XCTAssertTrue(doneButton.disappears(within: 15), "Map must be restored after dismissing sheet")
        let legend = app.descendants(matching: .any)["map.populationLegend"].firstMatch
        XCTAssertTrue(legend.appears(within: 5))
        let value = legend.value as? String ?? ""
        // The reference's 1 km grid legend: a gradient from 0 to 10000+.
        for end in ["0", "10000+"] {
            XCTAssertTrue(value.contains(end), "Legend must expose the gradient's end \(end); value: \(value)")
        }
        app.buttons["Close population legend"].tap()
        // The legend leaves with a transition (glass on iOS 26), which the
        // idle wait does not always cover: wait for it to go.
        XCTAssertTrue(legend.disappears(within: 5), "Closing the legend must remove it")
    }

    /// Phase 6d (ARCHITECTURE decision 76): the land value layer shows its
    /// legend, and a tapped cell its tooltip. Full lane only.
    func testLandValueLayerShowsItsLegendAndATappedCellsTooltip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()

        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.appears(within: 10))
        pause.tap()

        let layersButton = app.buttons["map.quickLayer.more"]
        XCTAssertTrue(layersButton.appears(within: 10))
        layersButton.tap()

        let row = app.switches["layer.landValue"]
        // The city's section is below the others: grow the sheet and
        // scroll until the row lies wholly on screen. A `swipeUp()` could
        // fling it to the screen's bottom edge, "hittable" but not tapped
        // (as LineRoutePreferenceUITests' row on main a383f27).
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row), "The land value row must come into view")
        let toggle = row.switches.firstMatch
        XCTAssertTrue(toggle.appears(within: 5))
        for _ in 0..<3 where toggle.value as? String != "1" {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: toggle)
            _ = XCTWaiter.wait(for: [hittable], timeout: 5)
            toggle.tap()
            let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
            _ = XCTWaiter.wait(for: [switched], timeout: 3)
        }
        XCTAssertEqual(toggle.value as? String, "1", "The land value layer must be on before dismissing")
        app.buttons["layer.done"].tap()

        let legend = app.descendants(matching: .any)["map.landValueLegend"].firstMatch
        XCTAssertTrue(legend.appears(within: 5), "The land value legend must show")

        // The new game opens on its first town, in the middle of the map.
        // On a phone the legend covers much of the map's trailing half,
        // and takes a tap there: tap the map halfway to the legend.
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let panel = app.descendants(matching: .any)["map.populationLegend"].firstMatch
        let clear = max(24, ((panel.exists ? panel : legend).frame.minX - map.frame.minX) / 2)
        map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: clear, dy: map.frame.height * 0.45)).tap()
        let tooltip = app.descendants(matching: .any)["map.cityTooltip"].firstMatch
        XCTAssertTrue(tooltip.appears(within: 5), "A tapped cell must show its tooltip")
        XCTAssertTrue((tooltip.label).contains("Land value"), "The tooltip must say the land value; label: \(tooltip.label)")
    }

    func testConstructionHUDAppearsDuringTrackPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()

        // Decision 114: Build opens the tools, starting with the network.
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10))
        // The tools slide in from the side: a point read mid-slide falls on
        // the map, which under the network tool chooses a track start (as
        // #326 found for the train tool).
        network.waitUntilSettled()
        network.tap()

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))

        let hud = app.otherElements["map.constructionHUD"]
        XCTAssertFalse(hud.exists, "HUD must not exist before track is previewed")

        // Tap start anchor and end anchor to trigger track preview, in the
        // map's leading half: the details card floats over its trailing
        // side while a tool is chosen (decision 106).
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35)).tap()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()

        XCTAssertTrue(hud.appears(within: 5), "MapConstructionHUD must appear when preview is active")

        // Cancelling construction removes preview and HUD: the map's ✕
        // beside the track, which a phone shows with the details card
        // folded (decision 136), as the card's Clear does.
        let cancel = app.buttons["map.build.cancel"]
        XCTAssertTrue(cancel.appears(within: 5))
        cancel.tap()

        // It leaves with a transition (move and fade, 0.2 s), which the
        // idle wait does not always cover, as the legend's (#198).
        XCTAssertTrue(hud.disappears(within: 5), "MapConstructionHUD must disappear when preview is cleared")
    }

    /// TestFlight 54.1: the track options are switches that say whether
    /// they are on (decision 107, later). Snapping starts on, and a tap
    /// turns it off.
    func testTheTrackOptionsShowWhetherTheyAreOn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10))
        network.waitUntilSettled()
        network.tap()

        let advanced = app.buttons["network.advanced"]
        XCTAssertTrue(advanced.appears(within: 10))
        for _ in 0..<3 where !advanced.becomesHittable(within: 1) { app.swipeUp() }
        advanced.tap()
        // A toggle with its own style: a toggle (value 1 or 0) or a
        // selected button, as the system reads it.
        let snap = app.descendants(matching: .any)["network.snap"].firstMatch
        XCTAssertTrue(snap.appears(within: 5))
        // The options open below the fold of the details card, which
        // scrolls on its own: a swipe up from the middle of the screen
        // began on the zoom buttons, never moved the card, and twice opened
        // the weather forecast instead (main 1678c8a's full lane, run
        // 38812528962: the switch stayed out of reach). The drag is made
        // on the card itself, down its leading margin beside the rows: its
        // scroll view is not exposed as one (a lookup of details.scroll.*
        // found nothing in PR #686's run 38820870840), the card is.
        let card = app.descendants(matching: .any)["details.card"].firstMatch
        XCTAssertTrue(card.appears(within: 5), "No details card")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(snap, in: card), "Snap to track never came into reach")
        func isOn() -> Bool { snap.isSelected || (snap.value as? String) == "1" }
        XCTAssertTrue(isOn(), "Snapping starts on, and says so; value: \(String(describing: snap.value))")
        snap.tap()
        for _ in 0..<10 where isOn() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        XCTAssertFalse(isOn(), "A tap turns snapping off, and says so; value: \(String(describing: snap.value))")
    }

    /// TestFlight 54.1: the news log is the bell's alone (decision 175,
    /// later). Tapping the station master, talking or not, never opens it.
    func testTheStationMasterDoesNotOpenTheNewsLog() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 10))
        let stationMaster = app.buttons["stationMaster"]
        XCTAssertTrue(stationMaster.appears(within: 10))
        let news = app.navigationBars["News"].firstMatch
        for _ in 0..<3 {
            stationMaster.tap()
            XCTAssertFalse(news.appears(within: 2), "Only the bell opens the news log")
        }
    }

    /// A panel beside the map (Lines) takes the details card's place: the
    /// dock's toggle for the card has nothing to change then, and on a
    /// phone the panel's edge lay over the station master beside the dock
    /// (bug hunt 3, domain D).
    func testASidePanelLeavesNoDeadToggleAndCoversNoStationMaster() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 10))
        let toggle = app.buttons["controls.toggle"]
        let stationMaster = app.buttons["stationMaster"]
        XCTAssertTrue(toggle.appears(within: 10))
        XCTAssertTrue(stationMaster.appears(within: 10))
        XCTAssertTrue(toggle.isEnabled)
        let cardBefore = toggle.label

        let lines = app.buttons["entry.lines"]
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["Lines"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        bar.waitUntilSettled()
        XCTAssertFalse(toggle.isEnabled, "With a panel beside the map the details card's toggle has nothing to change")
        // A tap then used to change only what showed after the panel closed.
        toggle.tap()
        if stationMaster.exists {
            XCTAssertTrue(stationMaster.becomesHittable(),
                          "The station master \(stationMaster.frame) shows only where the panel \(bar.frame) leaves it room")
            XCTAssertLessThanOrEqual(stationMaster.frame.maxX, bar.frame.minX,
                                     "The station master \(stationMaster.frame) must not lie under the panel \(bar.frame)")
        }

        bar.buttons["Done"].tap()
        XCTAssertTrue(bar.disappears(within: 10), "The lines panel closes")
        XCTAssertTrue(stationMaster.appears(within: 10))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.label, cardBefore, "Closing the panel must leave the details card as it was")
    }

    /// The details card keeps its status at its head and its action
    /// button at its foot, and scrolls only the options between: in a
    /// phone's card held on its side, the platform mode's options pushed
    /// Add Platform below the card's edge, and scrolling to it took the
    /// status, with its grade warning, away (TestFlight 54.1).
    func testPlatformModeKeepsItsStatusAndActionInTheCard() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        newGame.tap()
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        network.waitUntilSettled()
        network.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))

        // A stretch of track in the map's leading half, clear of the card
        // (decision 106); a phone folds the card while drawing and builds
        // with the map's ✓ (decision 136).
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4)).tap()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let confirm = app.buttons["map.build.confirm"]
        let buildTrack = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        let build = confirm.appears(within: 5) ? confirm : buildTrack
        XCTAssertTrue(build.appears(within: 5))
        build.tap()

        let platform = app.buttons["Platform"]
        if !platform.appears(within: 3) || !platform.becomesHittable(within: 1) {
            let controls = app.buttons["controls.toggle"]
            XCTAssertTrue(controls.appears(within: 5))
            controls.tap()
        }
        platform.waitUntilSettled()
        platform.tap()

        let status = app.descendants(matching: .any)["inspector.status"].firstMatch
        XCTAssertTrue(status.appears(within: 5))
        // An expectation is waited on once: a new one for each wait.
        func placed() -> Bool {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "m platform here"), object: status)
            return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
        }
        let mid = map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
        mid.tap()
        // Asked once after each tap: a second wait on a status already
        // seen placed failed when one lookup of it took four seconds of
        // its five (full lane run 38362099969, the status then reading
        // "… units along").
        var isPlaced = placed()
        if !isPlaced {
            mid.tap()
            isPlaced = placed()
        }
        XCTAssertTrue(isPlaced, "A tap on the track must place a platform; status: \(status.label)")

        let card = app.descendants(matching: .any)["details.card"].firstMatch
        XCTAssertTrue(card.appears(within: 5))
        card.waitUntilStill()
        let action = app.buttons["panel.action"]
        XCTAssertTrue(action.appears(within: 5))
        XCTAssertTrue(action.becomesHittable(), "Add Platform \(action.frame) must be in reach without scrolling the card \(card.frame)")
        assertWhollyInside(status, card, "before scrolling")
        assertWhollyInside(action, card, "before scrolling")

        // Scrolling the options leaves the status and the button in place.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            .press(forDuration: 0.1, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        assertWhollyInside(status, card, "after scrolling the options")
        XCTAssertTrue(action.becomesHittable(), "Add Platform must stay in reach after scrolling the options")
    }

    /// The train tool's card keeps its head (the selection) whole while
    /// its options scroll: an iPad's train tool card showed only the lower
    /// half of its head (TestFlight 54.1).
    func testTrainToolCardKeepsItsHead() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 10))
        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()

        let card = app.descendants(matching: .any)["details.card"].firstMatch
        XCTAssertTrue(card.appears(within: 5))
        card.waitUntilStill()
        let status = app.descendants(matching: .any)["inspector.status"].firstMatch
        XCTAssertTrue(status.appears(within: 5))
        assertWhollyInside(status, card, "when the train tool opens")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.1, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        assertWhollyInside(status, card, "after scrolling the options")
    }

    /// The status pill's pause button, news bell and game menu are drawn
    /// 32 to 40 points tall but touched over 44 by 44 (PR #440, found and
    /// not fixed): each is tapped beyond its drawn edge, between it and the
    /// pill's edge, where a tap used to miss it. From the touched element's
    /// centre, so the test does not depend on the frame XCTest reports.
    /// Full lane only (not in the pull request gate).
    /// TestFlight 59.1: on a phone held sideways the layer's legend starts
    /// folded to its title and colour bar; the title opens it with its
    /// opacity and timeline, and it stays as the player left it.
    func testTheLegendFoldsOnAPhoneOnItsSide() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "a phone's short screen")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-map-layer", "travel", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let legend = app.descendants(matching: .any)["map.populationLegend"].firstMatch
        XCTAssertTrue(legend.appears(within: 15), "The travel layer's legend must show")
        let fold = app.buttons["map.legend.fold"]
        let opacity = app.descendants(matching: .any)["map.popTravel.opacity"].firstMatch
        XCTAssertTrue(fold.appears(within: 5))
        XCTAssertFalse(opacity.exists, "Folded, the legend hides its opacity")
        XCTAssertTrue(fold.becomesHittable(within: 5))
        fold.tap()
        XCTAssertTrue(opacity.appears(within: 5), "Opened, the legend shows its opacity")
        XCTAssertTrue(app.descendants(matching: .any)["map.popTravel.hour"].firstMatch.exists, "and its timeline")
        fold.tap()
        XCTAssertTrue(opacity.disappears(within: 5), "Folded again")
    }

    func testTheStatusPillsButtonsAreTouchedBeyondTheirIcons() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 10))
        func tap(_ element: XCUIElement, below dy: CGFloat) {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: dy))
                .tap()
        }

        // The pause button, 40 points tall with its padding: 21 from its
        // centre, below and then above it.
        let resume = app.buttons["Resume"].firstMatch
        XCTAssertTrue(resume.appears(within: 10), "The demo opens paused")
        resume.waitUntilSettled()
        tap(resume, below: 21)
        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.appears(within: 5), "A tap 1 point below the drawn pause button resumes the game")
        // Tried twice, like the network tool's taps: this one, about a
        // second after the game resumed and some 12 points from the top of
        // a phone on its side, left the game running twice in the full
        // lane (runs 38430642081 and 38479608720; that run's recording shows
        // the button in place at the tap). A second tap comes only after
        // five seconds without a pause, so it cannot undo a slow first one.
        pause.waitUntilSettled()
        tap(pause, below: -21)
        if !resume.appears(within: 5) { tap(pause, below: -21) }
        XCTAssertTrue(resume.appears(within: 5), "A tap 1 point above the drawn pause button pauses the game")

        // The bell, 32 points tall: 20 below its centre.
        let bell = app.buttons["hud.news"]
        XCTAssertTrue(bell.appears(within: 5))
        tap(bell, below: 20)
        let news = app.navigationBars["News"]
        XCTAssertTrue(news.appears(within: 5), "A tap 4 points below the drawn bell opens the news")
        let done = app.buttons["news.done"]
        XCTAssertTrue(done.appears(within: 5))
        done.tap()
        XCTAssertTrue(news.disappears(within: 5))

        // The menu, 32 points tall: 20 above its centre.
        let menu = app.buttons["hud.menu"]
        XCTAssertTrue(menu.appears(within: 5))
        menu.waitUntilSettled()
        tap(menu, below: -20)
        XCTAssertTrue(app.buttons["menu.backToStart"].appears(within: 5), "A tap 4 points above the drawn menu button opens the game menu")
    }

    /// The details card keeps one layout for one subject while the clock
    /// runs. A train's summary at the card's head takes a line more when it
    /// stops ("Stopped at …") than when it runs; near the card's height that
    /// switched the card between its two layouts (the head and foot pinned,
    /// or the whole card scrolling), which put its options back at their
    /// top and closed an open menu (TestFlight 56.1). On a phone on its
    /// side at the demo's 600 times real time the demo's trains stop and
    /// start several times a minute.
    func testTheTrainToolCardKeepsItsLayoutWhileTheTrainStopsAndStarts() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // At 06:30, its trains running: opened at midnight, Train 1 set off
        // only some 36 seconds into the test, of the 60 it watches for.
        app.launchArguments = ["-ui-testing", "-demo-layout", "-demo-at", "06:30", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        // The demo runs on to 06:30 before the map opens.
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60))
        XCTAssertTrue(app.buttons["Pause"].appears(within: 10), "The clock must run")
        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        // Follow Train 1, so that it stays under the map's middle, and tap
        // it there: the card's head shows its summary.
        let fleet = app.buttons["train.fleetOverview"]
        XCTAssertTrue(fleet.appears(within: 15))
        if !fleet.becomesHittable(within: 1) { app.swipeUp() }
        fleet.tap()
        // The demo's tree is large and its clock runs: the list can take
        // longer than a paused demo's (run 38332921819).
        let fleetFollow = app.buttons["fleet.follow.Train 1"]
        XCTAssertTrue(fleetFollow.appears(within: 20), "The fleet list must offer to follow Train 1")
        for _ in 0..<3 where !fleetFollow.becomesHittable(within: 1) { app.swipeUp() }
        fleetFollow.tap()
        XCTAssertTrue(app.buttons["train.unfollow"].appears(within: 15))
        let map = app.descendants(matching: .any)["map"].firstMatch
        let status = app.descendants(matching: .any)["inspector.status"].firstMatch
        XCTAssertTrue(status.appears(within: 5))
        for _ in 0..<5 where !status.label.contains("Train 1") {
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(status.label.contains("Train 1"), "The tap must pick Train 1: \(status.label)")
        let card = app.descendants(matching: .any)["details.card"].firstMatch
        XCTAssertTrue(card.appears(within: 5))

        // The layout and the head's summary, a few times a second.
        // A snapshot that finds neither layout's mark keeps the marks it did
        // find, for the failure message.
        var layouts: [String: Int] = [:]
        var summaries = Set<String>()
        var samples: [String] = []
        // Until the train has been seen stopped and running three times
        // each: a snapshot of the demo's card takes a second or two, and in
        // one run 20 seconds held no stop (run 38332921819, the demo opened
        // at midnight then).
        var stopped = 0, running = 0
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, stopped < 3 || running < 3 {
            guard let snapshot = try? card.snapshot() else {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            var layout = "none", summary = "", marks: [String] = []
            var queue = [snapshot]
            while let next = queue.popLast() {
                if next.identifier.hasPrefix("details.scroll.") { layout = next.identifier }
                if next.identifier == "inspector.status" { summary = next.label }
                if !next.identifier.isEmpty { marks.append(next.identifier) }
                queue.append(contentsOf: next.children)
            }
            // In the whole layout the card's only child is its ScrollView,
            // and the card's own identifier ("details.card") takes the place
            // of "details.scroll.whole": the element found is the scroll view
            // itself (main 45fcde4's full lane, run 38933058668: all 24
            // snapshots of type 46, scrollView). The layout is then the
            // card's type; what it holds (the "On time" capsule's checkmark,
            // the stop button) comes and goes with the train, and is kept
            // for the failure message only.
            if layout == "none" {
                layout = snapshot.elementType == .scrollView ? "details.card(scrollView)" : "none(\(snapshot.elementType.rawValue))"
            }
            layouts[layout, default: 0] += 1
            let kind = summary.contains("Stopped at") ? "stopped" : summary.contains("running") ? "running" : "other"
            if kind == "stopped" { stopped += 1 }
            if kind == "running" { running += 1 }
            samples.append("\(layout.prefix(24))/\(kind)/\(Int(snapshot.frame.height))/\(marks.prefix(4).joined(separator: ","))")
            summaries.insert(summary.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression))
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(app.buttons["Pause"].exists, "The clock must keep running")
        XCTAssertTrue(summaries.contains { $0.contains("Stopped at") } && summaries.contains { !$0.contains("Stopped at") },
                      "The train must both stop and run while watched: \(summaries)")
        XCTAssertEqual(layouts.count, 1, "The card switched layouts while its train stopped and started: \(layouts); summaries: \(summaries); samples: \(samples)")
    }

    /// Waits until `element` is in the same place twice in a row, a
    /// quarter of a second apart: the card slides in, and grows as its
    /// content arrives. Unlike ``XCUIElement/waitUntilSettled(timeout:)``
    /// it asks nothing of hit testing, which a card is not made for.

    private func assertWhollyInside(_ element: XCUIElement, _ card: XCUIElement, _ when: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        // Half a point either way for rounding.
        XCTAssertTrue(card.frame.insetBy(dx: -0.5, dy: -0.5).contains(element.frame),
                      "\(element.identifier) \(element.frame) must lie wholly in the details card \(card.frame) \(when)",
                      file: file, line: line)
    }

    /// Decision 221: the line panel lists a line's depots with a tick
    /// each, within reach of a finger, and a tap ticks or unticks one. The
    /// depots scene (`ScreenshotScene.depots`) is the demo map with two
    /// depots, Line 1 at the west one. Full lane only (decision 199): what
    /// the list holds and what a tap does is `DepotToolsTests` on Linux.
    func testTheLinePanelTicksALinesDepot() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-scene", "depots", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The scene opens")

        let lines = app.buttons["entry.lines"]
        XCTAssertTrue(lines.appears(within: 10))
        lines.waitUntilSettled()
        lines.tap()
        let bar = app.navigationBars["Lines"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The lines panel opens")
        bar.waitUntilSettled()
        // Drags on the panel's own list, beside the map (`ToolbarSmokeTests`).
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }
        let line = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.trainsRow.1")).firstMatch
        // The list runs on under the bar (#659): a row counts as in reach only below it.
        XCTAssertTrue(app.dragUntilWhollyOnScreen(line, in: list, below: bar.frame.maxY), "Line 1's row must come into reach")
        line.tap()

        let depots = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "line.depot."))
        let depot = depots.firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(depot, in: list, below: bar.frame.maxY), "The line's depots must come into reach")
        XCTAssertTrue(depot.becomesHittable(within: 10))
        XCTAssertEqual(depots.count, 2, "Both depots are listed")
        let ticked = depot.isSelected
        depot.tap()
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: !ticked)), object: depot)
        XCTAssertEqual(XCTWaiter.wait(for: [flipped], timeout: 10), .completed, "A tap must \(ticked ? "untick" : "tick") the depot")
    }

    /// Decision 214: the network tool's fifth mode, Depot, shows how many
    /// sidings to lay, within reach of a finger on a phone. Full lane only
    /// (decision 199): the tool's logic is `DepotToolsTests` on Linux.
    func testTheDepotModeOffersItsSidings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.appears(within: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10))
        network.waitUntilSettled()
        network.tap()
        let depot = app.buttons["Depot"]
        XCTAssertTrue(depot.appears(within: 10))
        XCTAssertTrue(depot.becomesHittable(within: 10))
        depot.tap()
        let sidings = app.descendants(matching: .any)["network.depotSidings"].firstMatch
        XCTAssertTrue(sidings.appears(within: 10), "The number of sidings")
        XCTAssertTrue(sidings.becomesHittable(within: 10))
    }

    /// Decision 250 (a player's report): a sight tapped on the map opens the
    /// sights panel at its row, not at the top. Full lane only (decision
    /// 199): which row it opens at is `SightFocus` on Linux; this asks only
    /// whether the row is there to reach.
    func testASightTappedOnTheMapOpensItsRow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        // A new blank map has three to five sights in each tile, anywhere
        // in it: the opening, framed on the towns, may show none (main
        // 878adaf's full lane, run 38878787559), so the map is drawn back
        // until one is marked.
        let marks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.sight.'"))
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomOut.appears(within: 30))
        for _ in 0..<5 where !marks.firstMatch.appears(within: 3) && zoomOut.isEnabled {
            zoomOut.tap()
        }
        XCTAssertTrue(marks.firstMatch.appears(within: 10), "No sight is marked on the map")
        let mark = marks.element(boundBy: marks.count - 1)
        let id = mark.identifier.replacingOccurrences(of: "map.sight.", with: "")
        XCTAssertTrue(mark.becomesHittable(within: 10))
        mark.tap()
        XCTAssertTrue(app.buttons["tourism.done"].appears(within: 10), "The sights did not open")
        // The row's name: its star, which carries the row's identifier too,
        // is hidden from VoiceOver and never hittable (PR #713's run).
        let row = app.staticTexts.matching(identifier: "tourism.row.\(id)").firstMatch
        XCTAssertTrue(row.appears(within: 10), "The sight's row is not in the panel")
        XCTAssertTrue(row.becomesHittable(within: 10), "The panel did not open at the sight's row")
    }

    /// Decision 269: the map tilts as it comes closer. Pinched close, the
    /// 2D map hands over to the 3D map; pinched back out, the 3D map hands
    /// it back. In the full lane's second job (the class is in
    /// `FULL_LANE_SECOND_JOB`), not the pull request gate.
    func testPinchingCloseOpensTheThreeDMapAndPinchingOutComesBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        let close = app.buttons["map3D.close"]
        // Two pinches: the first may only bring the demo near the line.
        map.pinch(withScale: 6, velocity: 3)
        if !close.appears(within: 5) { map.pinch(withScale: 6, velocity: 3) }
        XCTAssertTrue(close.appears(within: 20), "A pinch close hands the 2D map over to the 3D map")
        let view = app.descendants(matching: .any)["map3D.view"].firstMatch
        XCTAssertTrue(view.appears(within: 10))
        view.pinch(withScale: 0.1, velocity: -3)
        if !close.disappears(within: 5) { view.pinch(withScale: 0.1, velocity: -3) }
        XCTAssertTrue(close.disappears(within: 10), "A pinch out hands the 3D map back")
        XCTAssertTrue(map.appears(within: 10))
    }

    /// Decision 269, later fix (71.1, the owner: "3D 一放大就跳回 2D"): a
    /// 3D map the button opened stays 3D as it is pinched closer; only one
    /// a pinch handed over goes back to the 2D map, and only pinched out.
    func testTheButtonsThreeDMapStaysThreeDWhenPinchedCloser() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        let open3D = app.buttons["map.open3D"]
        XCTAssertTrue(open3D.appears(within: 10))
        XCTAssertTrue(open3D.becomesHittable(within: 10))
        open3D.tap()
        let close = app.buttons["map3D.close"]
        XCTAssertTrue(close.appears(within: 20), "The 3D button opens the 3D map")
        let view = app.descendants(matching: .any)["map3D.view"].firstMatch
        XCTAssertTrue(view.appears(within: 10))
        view.pinch(withScale: 3, velocity: 2)
        view.pinch(withScale: 3, velocity: 2)
        XCTAssertFalse(close.disappears(within: 3), "Pinching closer must not go back to the 2D map")
        close.tap()
        XCTAssertTrue(close.disappears(within: 10))
    }
}
