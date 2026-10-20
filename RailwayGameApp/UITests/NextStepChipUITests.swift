import XCTest

/// Decision 293: a new free game shows its next step on the map, beside
/// the quick layers, and a tap opens the goals with every step. Full lane
/// only (decision 199): the steps and when they are met are
/// `NextStepsTests` on Linux; this checks that it shows and a finger
/// reaches it. Run by hand with only_testing=RailwayGameUITests/NextStepChipUITests.
@MainActor
final class NextStepChipUITests: XCTestCase {
    func testANewGamesNextStepOpensTheGoals() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 15), "Missing the New Game button")
        newGame.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 30), "The new game opens")

        let chip = app.buttons["map.nextStep"]
        XCTAssertTrue(chip.appears(within: 15), "The next step is on the map")
        XCTAssertTrue(chip.label.contains("Open your first line"), chip.label)
        XCTAssertTrue(chip.becomesHittable(within: 10), "The next step is covered")
        chip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["goals.nextSteps"].firstMatch.appears(within: 10), "The goals list the next steps")
    }
}
