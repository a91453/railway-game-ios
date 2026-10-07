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
        let demoMap = app.buttons["start.demoMap"]
        XCTAssertTrue(demoMap.waitForExistence(timeout: 10))
        demoMap.tap()
        let select = app.buttons["tool.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
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
        let demoMap = app.buttons["start.demoMap"]
        XCTAssertTrue(demoMap.waitForExistence(timeout: 10))
        demoMap.tap()
        let select = app.buttons["tool.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
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

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "en-large-map-whole"
        attachment.lifetime = .keepAlways
        add(attachment)

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
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        network.tap()
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(clear.isEnabled)

        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertFalse(clear.isEnabled, "Dragging must not pick a track anchor")
        map.pinch(withScale: 3, velocity: 1)
        XCTAssertFalse(clear.isEnabled, "Pinching must not pick a track anchor")
        XCTAssertFalse(app.buttons["Zoom in"].isEnabled, "A pinch past 2× must reach the camera's maximum zoom")
        XCTAssertTrue(app.buttons["Zoom out"].isEnabled)

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
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35)).tap()
        let build = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Build Track'")).firstMatch
        XCTAssertTrue(build.isEnabled, "Two taps after a pinch must make a buildable preview")
        build.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Built '")).firstMatch.waitForExistence(timeout: 5))
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
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        newGame.tap()
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        zoomIn.tap()
        XCTAssertFalse(zoomIn.isEnabled)

        XCUIDevice.shared.orientation = .landscapeLeft
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
        let demoMap = app.buttons["start.demoMap"]
        XCTAssertTrue(demoMap.waitForExistence(timeout: 10))
        demoMap.tap()

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

        XCTAssertTrue(layersButton.waitForExistence(timeout: 5), "Map must be restored after dismissing sheet")
        let legend = app.descendants(matching: .any)["map.populationLegend"].firstMatch
        XCTAssertTrue(legend.waitForExistence(timeout: 5))
        let value = legend.value as? String ?? ""
        // The reference's 1 km grid legend: a gradient from 0 to 10000+.
        for end in ["0", "10000+"] {
            XCTAssertTrue(value.contains(end), "Legend must expose the gradient's end \(end); value: \(value)")
        }
        app.buttons["Close population legend"].tap()
        XCTAssertFalse(legend.exists)
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

        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.waitForExistence(timeout: 10))
        network.tap()

        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        let hud = app.otherElements["map.constructionHUD"]
        XCTAssertFalse(hud.exists, "HUD must not exist before track is previewed")

        // Tap start anchor and end anchor to trigger track preview
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35)).tap()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35)).tap()

        XCTAssertTrue(hud.waitForExistence(timeout: 5), "MapConstructionHUD must appear when preview is active")

        // Clearing construction removes preview and HUD
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()

        XCTAssertFalse(hud.exists, "MapConstructionHUD must disappear when preview is cleared")
    }
}
