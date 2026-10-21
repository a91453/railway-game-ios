import XCTest

/// Decisions 292 and 311: with the network tool, where people are shows
/// at once over the map, the switch beside the zoom buttons puts it away
/// and brings it back, its legend switches to coverage and its share of
/// residents and jobs, and leaving the tool puts the map back. Full lane
/// only (decision 199): the rules and the numbers are
/// `StationPotentialMapTests` and `CoverageSummaryTests` on Linux; this
/// checks that it shows and a finger reaches it.
/// Run by hand with only_testing=RailwayGameUITests/CoverageShortcutUITests.
@MainActor
final class CoverageShortcutUITests: XCTestCase {
    func testTheBuildingLayerShowsWhileBuildingAndGoesWithTheTool() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-ui-testing-paused", "-show-building-layer", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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

        let potential = app.descendants(matching: .any)["map.potentialLegend"].firstMatch
        XCTAssertTrue(potential.appears(within: 30), "Where people are shows as building begins")
        XCTAssertTrue(shortcut.appears(within: 10), "Offered with the network tool")
        XCTAssertTrue(shortcut.becomesHittable(within: 10), "The switch is covered")
        shortcut.tap()
        XCTAssertTrue(potential.disappears(within: 10), "The switch puts it away")
        shortcut.tap()
        XCTAssertTrue(potential.appears(within: 10), "And brings it back")

        let choice = app.descendants(matching: .any)["map.buildingLayer.choice"].firstMatch
        XCTAssertTrue(choice.appears(within: 10))
        choice.buttons["Coverage"].tap()
        let share = app.descendants(matching: .any)["map.coverageShare"].firstMatch
        XCTAssertTrue(share.appears(within: 30), "The legend says how many the stations reach")
        XCTAssertTrue(share.label.contains("straight-line estimate"), share.label)

        app.buttons["tool.select"].tap()
        XCTAssertTrue(shortcut.disappears(within: 10), "Gone with the tool")
        XCTAssertTrue(share.disappears(within: 10), "The map's layer is put back")
    }
}
