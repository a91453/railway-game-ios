import XCTest

/// This class is absent from ios-build.yml's PR gate selection.
@MainActor
final class FinanceCompositionUITests: XCTestCase {
    /// Decision 480: the economy panel's report shows the period's income
    /// and costs as donuts, and tapping a slice's row spells it out under
    /// its ring. The freight scene has a day of fares, freight and running
    /// costs behind it.
    func testTheIncomeAndCostDonutsShowAndTheirRowsAnswerATap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-scene", "freight", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.appears(within: 60), "The scene opens")

        let economy = app.buttons["entry.economy"]
        XCTAssertTrue(economy.appears(within: 10))
        economy.waitUntilSettled()
        economy.tap()
        let bar = app.navigationBars["Economy"].firstMatch
        XCTAssertTrue(bar.appears(within: 10), "The economy panel opens")
        bar.waitUntilSettled()
        // Drags on the panel's own list, beside the map (`ToolbarSmokeTests`).
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }

        // A game of simple rules keeps the reports folded away at first.
        let reports = app.buttons["economy.reports"]
        if reports.exists, reports.label.hasPrefix("More") {
            XCTAssertTrue(app.dragUntilWhollyOnScreen(reports, in: list, below: bar.frame.maxY), "The reports toggle comes into reach")
            reports.tap()
        }

        let income = app.descendants(matching: .any)["economy.composition.income"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(income, in: list, below: bar.frame.maxY), "The income donut comes into reach")
        XCTAssertTrue(app.descendants(matching: .any)["economy.composition.costs"].firstMatch.exists, "The cost donut shows")

        let detail = app.staticTexts["economy.composition.income.detail"]
        XCTAssertTrue(detail.label.hasPrefix("Income $"), "Before a tap the ring's total is summed up: \(detail.label)")
        let fares = app.buttons["economy.composition.income.fares"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(fares, in: list, below: bar.frame.maxY), "The fares row comes into reach")
        XCTAssertTrue(fares.becomesHittable(within: 5))
        fares.tap()
        XCTAssertTrue(detail.label.hasPrefix("Fares · $"), "The tapped slice is spelled out: \(detail.label)")
        fares.tap()
        XCTAssertTrue(detail.label.hasPrefix("Income $"), "A second tap lets it go: \(detail.label)")
    }
}
