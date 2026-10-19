import XCTest

/// Decision 292: with the network tool, the coverage switch is beside the
/// zoom buttons, shows the coverage layer and its share of residents and
/// jobs, and puts the map back once the tool is left. Full lane only
/// (decision 199): the switch's rules and the share are
/// `CoverageSummaryTests` on Linux; this checks that a finger reaches it.
/// Run by hand with only_testing=RailwayGameUITests/CoverageShortcutUITests.
@MainActor
final class CoverageShortcutUITests: XCTestCase {
    func testTheSwitchShowsCoverageWhileBuildingAndGoesWithTheTool() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The demo map opens")

        let shortcut = app.buttons["map.coverageShortcut"]
        XCTAssertFalse(shortcut.exists, "Not offered while only looking at the map")

        let build = app.buttons["dock.build"]
        XCTAssertTrue(build.appears(within: 10))
        build.tap()
        let network = app.buttons["tool.network"]
        XCTAssertTrue(network.appears(within: 5))
        network.waitUntilSettled()
        if !network.isSelected { network.tap() }

        XCTAssertTrue(shortcut.appears(within: 10), "Offered with the network tool")
        XCTAssertTrue(shortcut.becomesHittable(within: 10), "The switch is covered")
        shortcut.tap()
        let share = app.descendants(matching: .any)["map.coverageShare"].firstMatch
        XCTAssertTrue(share.appears(within: 30), "The legend says how many the stations reach")
        XCTAssertTrue(share.label.contains("straight-line estimate"), share.label)

        app.buttons["tool.select"].tap()
        XCTAssertTrue(shortcut.disappears(within: 10), "Gone with the tool")
        XCTAssertTrue(share.disappears(within: 10), "The map's layer is put back")
    }
}
