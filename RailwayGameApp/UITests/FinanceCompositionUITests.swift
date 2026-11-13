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
        // The press on Data can be cancelled while the app's main thread
        // stalls (the app's trace: "touch cancelled at (100, 240)" 150 ms
        // after it began, then an 885 ms gap between frames, as the station
        // master's bubble went; branch flane-full-lane, run 41195369563),
        // and the panel never opens. Tap once more if it did not, as
        // HUDAlignmentUITests does for Build.
        if !bar.appears(within: 10), economy.exists {
            economy.tap()
        }
        XCTAssertTrue(bar.appears(within: 10), "The economy panel opens")
        bar.waitUntilSettled()
        // Decision 717: the statement and its donuts are the reports
        // page's leading column.
        XCTAssertTrue(app.showEconomyPage("Reports"), "The reports page")
        let list = app.economyList()
        let column = app.economyDragColumn(list)

        let income = list.descendants(matching: .any)["economy.composition.income"].firstMatch
        XCTAssertTrue(app.dragUntilWhollyOnScreen(income, in: list, below: bar.frame.maxY, at: column, clearOf: .button), "The income donut comes into reach")
        XCTAssertTrue(list.descendants(matching: .any)["economy.composition.costs"].firstMatch.exists, "The cost donut shows")

        let detail = app.staticTexts["economy.composition.income.detail"]
        XCTAssertTrue(detail.label.hasPrefix("Income NT$"), "Before a tap the ring's total is summed up: \(detail.label)")
        let fares = app.buttons["economy.composition.income.fares"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(fares, in: list, below: bar.frame.maxY, at: column, clearOf: .button), "The fares row comes into reach")
        XCTAssertTrue(fares.becomesHittable(within: 5))
        fares.tap()
        XCTAssertTrue(detail.label.hasPrefix("Fares · NT$"), "The tapped slice is spelled out: \(detail.label)")
        fares.tap()
        XCTAssertTrue(detail.label.hasPrefix("Income NT$"), "A second tap lets it go: \(detail.label)")
    }
}

extension XCUIApplication {
    /// Decision 717: picks a page of the company's figures, which cover
    /// the whole screen, by its name on the control in their bar; whether
    /// it was there to pick.
    func showEconomyPage(_ title: String) -> Bool {
        let pages = segmentedControls["economy.pages"].firstMatch
        guard pages.appears(within: 10) else { return false }
        let page = pages.buttons[title].firstMatch
        guard page.appears(within: 5) else { return false }
        page.tap()
        return true
    }

    /// A column of the page shown: the leading one (the only one where
    /// the window is narrow or the text large), or the trailing one.
    func economyList(trailing: Bool = false) -> XCUIElement {
        let own = collectionViews[trailing ? "economy.trailing" : "economy.leading"].firstMatch
        return trailing && !own.exists ? collectionViews["economy.leading"].firstMatch : own
    }

    /// Where drags run down `list`: its rows' own leading edge. The lists
    /// run under the screen's edges, where a drag does not scroll them.
    func economyDragColumn(_ list: XCUIElement) -> CGFloat {
        let cell = list.cells.firstMatch
        return (cell.exists ? cell.frame.minX : list.frame.minX + 60) + 6
    }
}
