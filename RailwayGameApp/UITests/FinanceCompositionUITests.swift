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
        // Drags on the panel's own list, beside the map (`ToolbarSmokeTests`).
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.frame.midX >= bar.frame.minX && $0.frame.midX <= bar.frame.maxX }

        XCTAssertTrue(app.revealFinanceComposition(in: list, below: bar.frame.maxY), "The income donut comes into reach")
        XCTAssertTrue((list ?? app).descendants(matching: .any)["economy.composition.costs"].firstMatch.exists, "The cost donut shows")

        let detail = app.staticTexts["economy.composition.income.detail"]
        XCTAssertTrue(detail.label.hasPrefix("Income NT$"), "Before a tap the ring's total is summed up: \(detail.label)")
        let fares = app.buttons["economy.composition.income.fares"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(fares, in: list, below: bar.frame.maxY), "The fares row comes into reach")
        XCTAssertTrue(fares.becomesHittable(within: 5))
        fares.tap()
        XCTAssertTrue(detail.label.hasPrefix("Fares · NT$"), "The tapped slice is spelled out: \(detail.label)")
        fares.tap()
        XCTAssertTrue(detail.label.hasPrefix("Income NT$"), "A second tap lets it go: \(detail.label)")
    }
}

extension XCUIApplication {
    /// Brings the economy panel's income donut (decision 480) wholly into
    /// `list`, below `below`; whether it came. A game of simple rules keeps
    /// the reports folded away under a toggle at the list's foot, and the
    /// reports open above it, so the toggle goes first and the list then
    /// goes back up to the donut, as `WebsiteScreenshotTests` does.
    ///
    /// Looking down the folded list for the donut first cost 25 drags, each
    /// followed by a query of every element in the app: the test took
    /// 210–312 s in each full lane from deef5e3 to 5121f61, and in 0c6e5ce's
    /// (103.1, run 41287836096) one such query stalled 60 s, the time
    /// XCTest gives a query on the app's main thread, and XCTest's own code
    /// in the app then aborted it ("Illegal fault request … snapshot has no
    /// data source"). So the queries look in `list`, not the whole app.
    func revealFinanceComposition(in list: XCUIElement?, below: CGFloat) -> Bool {
        let scope = list ?? self
        let income = scope.descendants(matching: .any)["economy.composition.income"].firstMatch
        if !income.exists {
            let reports = scope.buttons["economy.reports"]
            if dragUntilWhollyOnScreen(reports, in: list, below: below), reports.label == "More reports and settings" {
                reports.tap()
            }
            for _ in 0..<12 where !income.exists {
                scope.swipeDown(velocity: .fast)
            }
        }
        return dragUntilWhollyOnScreen(income, in: list, below: below)
    }
}
