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
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Resume"].exists, "The demo must stay paused throughout this test")

        for name in ["Train 1", "Train 2"] {
            // Decision 114: the tools show once Build is pressed; Select
            // (Done) below closes them again.
            app.buttons["dock.build"].tap()
            app.buttons["tool.train"].tap()
            let fleet = app.buttons["train.fleetOverview"]
            if !fleet.isHittable { app.swipeUp() }
            XCTAssertTrue(fleet.waitForExistence(timeout: 5))
            fleet.tap()
            let follow = app.buttons["fleet.follow.\(name)"]
            XCTAssertTrue(follow.waitForExistence(timeout: 5))
            for _ in 0..<3 where !follow.isHittable { app.swipeUp() }
            XCTAssertTrue(follow.isHittable)
            follow.tap()
            XCTAssertTrue(app.buttons["train.unfollow"].waitForExistence(timeout: 5))
            let speed = app.descendants(matching: .any)["train.speed"].firstMatch
            XCTAssertTrue(speed.waitForExistence(timeout: 5))
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

    func testDemoMapOpensOnItsNetwork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")
        // A new game starts with no tool chosen: a tap selects (decision
        // 114: there is no Select button outside building).
        XCTAssertTrue(app.buttons["dock.build"].waitForExistence(timeout: 10))
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((map.value as? String)?.contains("Central") == true,
                      "The opening camera must put Central at the map view's center; value: \(String(describing: map.value))")
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
        XCTAssertTrue(app.buttons["dock.build"].waitForExistence(timeout: 10))
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let zoomOut = app.buttons["Zoom out"]
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 10))
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))

        for _ in 0..<12 {
            if !zoomOut.isEnabled { break }
            zoomOut.tap()
        }
        XCTAssertFalse(zoomOut.isEnabled, "The whole 1024 × 1024 map must fit within 12 zoom-out taps")
        XCTAssertTrue(zoomIn.isEnabled)
        XCTAssertTrue(zoomIn.isHittable)

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
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        // Decision 114: Build opens the tools, starting with the network.
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.waitForExistence(timeout: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        network.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
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
        let cardFolds = !zoomIn.exists
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
        if cardFolds { toggleControls(to: "Show Controls") }
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        XCTAssertFalse(zoomIn.isEnabled, "A pinch past 2× must reach the camera's maximum zoom")
        XCTAssertTrue(app.buttons["Zoom out"].isEnabled)
        if cardFolds {
            toggleControls(to: "Hide Controls")
            XCTAssertTrue(clear.waitForExistence(timeout: 10))
            XCTAssertFalse(clear.isEnabled)
        }

        // After a pinch to the closest zoom an accessibility query can hold
        // the app's main thread for seconds (run 37161734560's recording),
        // and a touch held across that is failed by the tap recognizer: wait
        // for the anchor, and tap once more if the first touch was lost.
        let anchor = map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
        func anchored() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: clear)],
                             timeout: 10) == .completed
        }
        anchor.tap()
        if !anchored() { anchor.tap() }
        XCTAssertTrue(anchored(), "Taps after navigating must still reach the network tool")
        // The far end, tried twice like the anchor: the same lost touch.
        let far = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let build = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        func previewed() -> Bool {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: build)],
                             timeout: 10) == .completed
        }
        far.tap()
        if !previewed() { far.tap() }
        XCTAssertTrue(previewed(), "Two taps after a pinch must make a buildable preview")
        build.tap()
        // Built track disables the button for good (its end starts the
        // next stretch); the "Built …" banner clears itself after 4 s
        // (#182), within one slow accessibility query.
        let built = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: build)
        XCTAssertEqual(XCTWaiter().wait(for: [built], timeout: 10), .completed, "Build Track did not build")
    }

    func testZoomButtonsRemainUsableWithoutPinching() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        // A step doubles the size (Stage E1): 32 points per 16 m to 64, the
        // maximum zoom.
        zoomIn.tap()
        XCTAssertFalse(zoomIn.isEnabled, "64 points per 16 m is the maximum zoom")
        XCTAssertTrue(zoomOut.isEnabled)
        zoomOut.tap()
        XCTAssertTrue(zoomIn.isEnabled)
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
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        zoomIn.tap()
        XCTAssertFalse(zoomIn.isEnabled)

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertFalse(zoomIn.isEnabled, "Changing the layout must keep the camera's maximum zoom")
        app.buttons["Zoom out"].tap()
        XCTAssertTrue(zoomIn.isEnabled)
    }

    func testMapLayersSheetTogglesAndDismisses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        app.openDemo("demo.simple")

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))

        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 10), "Map layers button must be visible on the map")
        layersButton.tap()

        let stationNamesToggle = app.switches["layer.stationNames"]
        XCTAssertTrue(stationNamesToggle.waitForExistence(timeout: 5), "Station names toggle must exist in MapLayerSheet")

        let waitingCountsToggle = app.switches["layer.waitingCounts"]
        XCTAssertTrue(waitingCountsToggle.waitForExistence(timeout: 5), "Waiting counts toggle must exist in MapLayerSheet")

        let catchmentRingsToggle = app.switches["layer.catchmentRings"]
        XCTAssertTrue(catchmentRingsToggle.waitForExistence(timeout: 5), "Catchment rings toggle must exist in MapLayerSheet")

        let heatmapRow = app.switches["layer.populationHeatmap"]
        XCTAssertTrue(heatmapRow.waitForExistence(timeout: 5), "Population heatmap row must exist")
        // SwiftUI exposes a labelled wrapper and its actual UISwitch as
        // separate switches. Use the control's activation point; tapping
        // the wrapper or coordinates in its frame can leave it unchanged.
        let heatmapToggle = heatmapRow.switches.firstMatch
        XCTAssertTrue(heatmapToggle.waitForExistence(timeout: 5), "Population heatmap control must exist")
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
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        // The layers button exists under the sheet too: what shows the
        // sheet closed is its Done button gone.
        XCTAssertTrue(doneButton.waitForNonExistence(timeout: 5), "Map must be restored after dismissing sheet")
        let legend = app.descendants(matching: .any)["map.populationLegend"].firstMatch
        XCTAssertTrue(legend.waitForExistence(timeout: 5))
        let value = legend.value as? String ?? ""
        // The reference's 1 km grid legend: a gradient from 0 to 10000+.
        for end in ["0", "10000+"] {
            XCTAssertTrue(value.contains(end), "Legend must expose the gradient's end \(end); value: \(value)")
        }
        app.buttons["Close population legend"].tap()
        // The legend leaves with a transition (glass on iOS 26), which the
        // idle wait does not always cover: wait for it to go.
        XCTAssertTrue(legend.waitForNonExistence(timeout: 5), "Closing the legend must remove it")
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
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()

        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 10))
        layersButton.tap()

        let row = app.switches["layer.landValue"]
        // The city's section is below the others: grow the sheet and
        // scroll until the row lies wholly on screen. A `swipeUp()` could
        // fling it to the screen's bottom edge, "hittable" but not tapped
        // (as LineRoutePreferenceUITests' row on main a383f27).
        XCTAssertTrue(app.dragUntilWhollyOnScreen(row), "The land value row must come into view")
        let toggle = row.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
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
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "The land value legend must show")

        // The new game opens on its first town, in the middle of the map.
        // On a phone the legend covers much of the map's trailing half,
        // and takes a tap there: tap the map halfway to the legend.
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let panel = app.descendants(matching: .any)["map.populationLegend"].firstMatch
        let clear = max(24, ((panel.exists ? panel : legend).frame.minX - map.frame.minX) / 2)
        map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: clear, dy: map.frame.height * 0.45)).tap()
        let tooltip = app.descendants(matching: .any)["map.cityTooltip"].firstMatch
        XCTAssertTrue(tooltip.waitForExistence(timeout: 5), "A tapped cell must show its tooltip")
        XCTAssertTrue((tooltip.label).contains("Land value"), "The tooltip must say the land value; label: \(tooltip.label)")
    }

    func testConstructionHUDAppearsDuringTrackPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()

        // Decision 114: Build opens the tools, starting with the network.
        let buildEntry = app.buttons["dock.build"]
        XCTAssertTrue(buildEntry.waitForExistence(timeout: 10))
        buildEntry.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        network.tap()

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        let hud = app.otherElements["map.constructionHUD"]
        XCTAssertFalse(hud.exists, "HUD must not exist before track is previewed")

        // Tap start anchor and end anchor to trigger track preview, in the
        // map's leading half: the details card floats over its trailing
        // side while a tool is chosen (decision 106).
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35)).tap()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()

        XCTAssertTrue(hud.waitForExistence(timeout: 5), "MapConstructionHUD must appear when preview is active")

        // Clearing construction removes preview and HUD
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()

        // It leaves with a transition (move and fade, 0.2 s), which the
        // idle wait does not always cover, as the legend's (#198).
        XCTAssertTrue(hud.waitForNonExistence(timeout: 5), "MapConstructionHUD must disappear when preview is cleared")
    }
}
