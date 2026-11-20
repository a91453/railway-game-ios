import XCTest

/// Decision 350 (the owner, 2026-10-22): the map's coverage, 3D and zoom
/// buttons stand the same way however the device is held. Where they stand
/// for each way is `MapFocusTests` on Linux; this checks that they show and
/// a finger reaches them. Full lane only (decision 199). Run by hand with
/// only_testing=RailwayGameUITests/MapButtonsUITests (and
/// only_testing_ipad for the iPad's).
@MainActor
final class MapButtonsUITests: XCTestCase {
    /// On a phone on its side, beside the building card (the first level)
    /// they stand under it at the screen's edge, as under a panel (the
    /// second), the coverage button beside the 3D one.
    func testThePhonesButtonsStandUnderTheBuildingCard() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "a phone held on its side")
        let app = launch(orientation: .landscapeLeft)
        defer { app.terminate() }

        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 5))
        network.waitUntilSettled()
        if !network.isSelected { network.tap() }
        let card = app.descendants(matching: .any)["details.card"].firstMatch
        if !card.appears(within: 5) {
            let controls = app.buttons["controls.toggle"]
            if controls.exists { controls.tap() }
        }
        XCTAssertTrue(card.appears(within: 10), "The building card opens")
        card.waitUntilSettled()

        let buttons = checkTheButtonsShow(in: app)
        for button in buttons {
            XCTAssertGreaterThanOrEqual(button.frame.minY, card.frame.maxY, "Under the card: \(button.frame) and \(card.frame)")
        }
    }

    /// Decision 892: on a phone on its side, with the card folded too, the
    /// zoom buttons stand in their row at the screen's foot, beside the
    /// tools column at the trailing side, and a finger reaches them.
    func testThePhonesZoomButtonsStandInTheRowBesideTheColumn() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "a phone held on its side")
        let app = launch(orientation: .landscapeLeft)
        defer { app.terminate() }

        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        if app.descendants(matching: .any)["details.card"].firstMatch.exists {
            app.buttons["controls.toggle"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["details.card"].firstMatch.disappears(within: 10), "The card folds")
        }
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(zoomIn.appears(within: 10))
        XCTAssertTrue(zoomIn.becomesHittable(within: 10), "\(zoomIn) is covered: \(zoomIn.frame)")
        build.waitUntilSettled()
        XCTAssertLessThanOrEqual(zoomIn.frame.maxX, build.frame.minX, "Beside the column: \(zoomIn.frame) and \(build.frame)")
        XCTAssertGreaterThan(zoomIn.frame.midY, build.frame.minY, "In the bottom row: \(zoomIn.frame) and \(build.frame)")
    }

    /// Decision 382, later (TestFlight 85.1): while building, Build stood
    /// half cut at the column's foot, scrolled past its height. It stands
    /// whole there now, a finger reaches it and it closes the tools. Where
    /// the column is cut is `ToolColumnTests` on Linux.
    func testThePhonesBuildStandsWholeWhileBuilding() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "a phone held on its side")
        let app = launch(orientation: .landscapeLeft)
        defer { app.terminate() }

        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        XCTAssertTrue(app.buttons["tool.network"].appears(within: 10), "The building tools open")
        build.waitUntilSettled()
        XCTAssertTrue(build.becomesHittable(within: 10), "Build is covered: \(build.frame)")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(build.frame.maxY, window.maxY - 10, "Whole above the screen's foot: \(build.frame)")
        // The card's toggle on Build's row, not over the tools (98.1); in
        // the bottom leading corner since decision 892.
        let toggle = app.buttons["controls.toggle"]
        if toggle.exists {
            XCTAssertLessThanOrEqual(toggle.frame.maxX, build.frame.minX, "Beside Build: \(toggle.frame) and \(build.frame)")
            XCTAssertLessThanOrEqual(abs(toggle.frame.midY - build.frame.midY), build.frame.height / 2, "Beside Build: \(toggle.frame) and \(build.frame)")
        }
        build.tap()
        XCTAssertTrue(app.buttons["tool.network"].disappears(within: 10), "Build closes the tools")
    }

    /// 98.1 (the owner: "不是要固定在工具欄最上面嗎"): while building, the
    /// tools stood low over Done, scrolled, cut short, the room above them
    /// empty. Now a finger reaches the first tool as the tools open; where
    /// they all fit they stand close over Done, else the column runs up to
    /// a margin under the status bar, the first tool at its top. Done and
    /// the card's toggle stand beside Build (100.1, decision 509). Which of
    /// the two, and how tall the part that scrolls is, is `ToolColumnTests`.
    func testThePhonesBuildingToolsStartAtTheColumnsTop() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "a phone held on its side")
        let app = launch(orientation: .landscapeLeft)
        defer { app.terminate() }

        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 10), "The building tools open")
        XCTAssertTrue(network.becomesHittable(within: 10), "The first tool is covered or scrolled away: \(network.frame)")
        network.waitUntilSettled()
        let status = app.descendants(matching: .any)["hud.bar"].firstMatch
        XCTAssertTrue(status.appears(within: 5))
        let done = app.buttons["tool.select"]
        XCTAssertTrue(done.appears(within: 5))
        // Decision 892: on Build's row, in the bottom leading corner.
        XCTAssertLessThanOrEqual(done.frame.maxX, build.frame.minX, "Done on Build's row: \(done.frame) and \(build.frame)")
        XCTAssertEqual(done.frame.midY, build.frame.midY, accuracy: 0.5, "Done beside Build: \(done.frame) and \(build.frame)")
        XCTAssertLessThan(network.frame.maxY, build.frame.minY, "The tools over Build: \(network.frame) and \(build.frame)")
        // Each button is touched 2 past what it draws, above and below
        // (decision 509). Up the column: the margin of 10 and the glass, 4
        // (2 where the column is short), over the first tool. Close over
        // Build: the tools' glass, the gap of 6 and Build's glass between.
        let atTop = abs(network.frame.minY + 2 - (status.frame.maxY + 10 + 4)) <= 3
        let bus = app.buttons["tool.bus"]
        let overBuild = bus.exists && bus.isHittable && abs((build.frame.minY + 2) - (bus.frame.maxY - 2) - (4 + 6 + 4)) <= 3
        XCTAssertTrue(atTop || overBuild,
                      "Neither at the column's top nor close over Build: \(network.frame), \(bus.frame), Build \(build.frame), the status bar \(status.frame)")
    }

    /// On an iPad held upright they stand in the map's corner beside the
    /// lines panel, not gone.
    func testTheIPadsButtonsStayBesideThePanelHeldUpright() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "an iPad held upright")
        let app = launch(orientation: .portrait)
        defer { app.terminate() }

        let lines = app.buttons["entry.lines"]
        XCTAssertTrue(lines.appears(within: 10))
        lines.tap()
        XCTAssertTrue(app.navigationBars["Lines"].appears(within: 10), "The lines panel opens")
        checkTheButtonsShow(in: app)
    }

    /// Decision 469 (UI review 2-3): on a phone on its side with the
    /// details card open, the row under the status pill ran under the card
    /// where it had no room (at night, the skip beside the strip). The
    /// strip folds to one button there now; either way it stays clear of
    /// the card and a finger reaches its list. When it folds is
    /// `MapTopRowTests` on Linux.
    func testThePhonesLayerStripKeepsClearOfTheCard() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "a phone held on its side")
        let app = launch(orientation: .landscapeLeft)
        defer { app.terminate() }

        let card = app.descendants(matching: .any)["details.card"].firstMatch
        if !card.appears(within: 5) {
            let controls = app.buttons["controls.toggle"]
            XCTAssertTrue(controls.appears(within: 10))
            controls.tap()
        }
        XCTAssertTrue(card.appears(within: 10), "The details card opens")
        card.waitUntilSettled()
        let strip = app.descendants(matching: .any)["map.quickLayer.strip"].firstMatch
        XCTAssertTrue(strip.appears(within: 10), "The layer strip shows")
        // The strip's mark is no control and takes no touch: since the
        // mark is ordered behind what it marks (``hudFrameMark``, pull
        // request #2453), XCTest finds the strip's buttons, not the mark,
        // at its hit point, so it is waited for until it stands still, not
        // until it is hittable.
        strip.waitUntilStill()
        XCTAssertLessThanOrEqual(strip.frame.maxX, card.frame.minX, "Clear of the card: \(strip.frame) and \(card.frame)")
        let more = app.buttons["map.quickLayer.more"]
        XCTAssertTrue(more.becomesHittable(within: 10), "\(more) is covered: \(more.frame)")
    }

    private func launch(orientation: UIDeviceOrientation) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The demo map opens")
        return app
    }

    /// The coverage, 3D and zoom buttons show, a finger reaches them, and
    /// they stand in one row.
    @discardableResult
    private func checkTheButtonsShow(in app: XCUIApplication) -> [XCUIElement] {
        let buttons = ["map.coverageShortcut", "map.open3D", "Zoom out", "Zoom in"].map { app.buttons[$0] }
        for button in buttons {
            XCTAssertTrue(button.appears(within: 10), "\(button) shows")
            XCTAssertTrue(button.becomesHittable(within: 10), "\(button) is covered: \(button.frame)")
        }
        let coverage = buttons[0].frame, threeD = buttons[1].frame
        XCTAssertLessThan(abs(coverage.midY - threeD.midY), 2, "The coverage button beside the 3D one: \(coverage) and \(threeD)")
        XCTAssertLessThan(coverage.maxX, threeD.minX + 1, "The coverage button left of the 3D one")
        XCTAssertLessThan(abs(threeD.midY - buttons[3].frame.midY), 2, "In a row with the zoom buttons")
        return buttons
    }
}
