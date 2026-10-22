import XCTest

/// The marks over the map take a tap on their middle. On an iPad the
/// lock's circular hit shape let a tap on its middle row fall through to
/// the map (#1040, only_testing run 39826506139); these ask the same of
/// the other marks drawn as a circle or a capsule: a request's flag, a
/// sight's star and an alert's bubble. Before the flag took its square
/// (run 39841822269), its test alone was red, on the iPad alone: the
/// capsules' middle rows take the tap. In the full lane (decision 199):
/// what a tap does is GamePresentation's; this asks only whether the
/// finger reaches the mark, which only a Simulator can answer.
@MainActor
final class MapMarkTapUITests: XCTestCase {
    /// A request's flag (decision 246), tapped on its middle, points the
    /// request out and opens its card.
    func testARequestsFlagTakesATapOnItsMiddle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-layout", "-city-requests", "-ui-testing-paused",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.appears(within: 10))
        // Taken on, the request keeps its flag; "Show on map" brings the
        // camera to it, and with its card closed the flag stays there, no
        // longer pointed out (one only on offer goes with its card).
        let requests = app.buttons["hud.requests"]
        XCTAssertTrue(requests.appears(within: 5), "the status bar's requests button")
        requests.tap()
        let show = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'requests.show.'")).firstMatch
        XCTAssertTrue(app.buttons["goals.done"].appears(within: 5), "the requests open")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(show), "a request's Show on map never came into reach")
        let id = show.identifier.replacingOccurrences(of: "requests.show.", with: "")
        let accept = app.buttons["requests.accept.\(id)"]
        XCTAssertTrue(accept.appears(within: 5), "the demo's request is on offer")
        accept.tap()
        XCTAssertTrue(accept.disappears(within: 5), "the request is taken on")
        XCTAssertTrue(app.dragUntilWhollyOnScreen(show), "Show on map went out of reach")
        show.tap()
        let card = app.descendants(matching: .any)["map.request.card"].firstMatch
        XCTAssertTrue(card.appears(within: 5), "the request is pointed out")
        app.buttons["map.request.card.close"].tap()
        XCTAssertTrue(card.disappears(within: 5))

        let flag = app.buttons["map.request.\(id)"]
        XCTAssertTrue(flag.appears(within: 5), "the request's flag stays on the map")
        XCTAssertTrue(flag.becomesHittable(within: 5))
        flag.tap()
        XCTAssertTrue(card.appears(within: 5), "A tap on the flag's middle points its request out")
    }

    /// A sight's star (decision 174), tapped on its middle, opens the
    /// sights. Seed 1 has one in the middle of the screen by the third
    /// step out (`MapInteractionTests.testASightTappedOnTheMapOpensItsRow`).
    func testASightsMarkTakesATapOnItsMiddle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-seed", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        app.chooseBlankMap()
        let marks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.sight.'"))
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomOut.appears(within: 30))
        for _ in 0..<5 where !marks.firstMatch.appears(within: 3) && zoomOut.isEnabled {
            zoomOut.tap()
        }
        XCTAssertTrue(marks.firstMatch.appears(within: 10), "No sight is marked on the map")
        let mark = marks.element(boundBy: marks.count - 1)
        XCTAssertTrue(mark.becomesHittable(within: 10))
        mark.tap()
        XCTAssertTrue(app.buttons["tourism.done"].appears(within: 10), "A tap on the star's middle opens the sights")
    }

    /// An alert's bubble (decision 121), tapped on its middle: a station
    /// short of building materials opens its station's panel (decision
    /// 184), as every bubble of this scene is.
    func testAnAlertsBubbleTakesATapOnItsMiddle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-scene", "freight",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        // The bubbles, not the map: a query of every element timed out on
        // an iPhone while the scene was being built (run 39841822269).
        let alerts = app.buttons.matching(identifier: "map.alert")
        XCTAssertTrue(alerts.firstMatch.appears(within: 150), "The stations short of materials show")
        let alert = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(alert, "A bubble is on screen")
        alert?.tap()
        // Any of the panel's rows: which ones are on screen first depends
        // on the screen's size.
        let panel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'station.'")).firstMatch
        XCTAssertTrue(panel.appears(within: 5), "A tap on the bubble's middle opens its station")
    }
}
