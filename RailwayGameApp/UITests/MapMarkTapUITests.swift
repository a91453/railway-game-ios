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
    /// 184), as every bubble of this scene is. Decision 501: and again
    /// after the panel is closed. The station stays selected, and its tag,
    /// drawn over the bubbles, lay on the middle station's bubble under its
    /// name: every later tap opened the tag (97.1 on an iPad).
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
        let first = alerts.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(first, "A bubble is on screen")
        guard let first else { return }
        let middle = CGPoint(x: first.frame.midX, y: first.frame.midY)
        // Decision 477: at the freight group, whose first row says what
        // the town is short of (it was last in the panel, a long scroll
        // down). The panel scrolls again once it has slid in, which a slow
        // runner takes seconds to do (``StationPanel/settleJump``).
        let materials = app.descendants(matching: .any).matching(identifier: "station.materials").firstMatch
        let done = app.buttons["station.done"]
        for tap in ["first", "second"] {
            // The bubble nearest where the first one was, by its middle,
            // as a finger goes back to it.
            let bubble = alerts.allElementsBoundByIndex.min { a, b in
                hypot(a.frame.midX - middle.x, a.frame.midY - middle.y) < hypot(b.frame.midX - middle.x, b.frame.midY - middle.y)
            }
            XCTAssertNotNil(bubble, "The bubble is still on the map for the \(tap) tap")
            guard let bubble else { return }
            XCTAssertTrue(bubble.becomesHittable(within: 5), "The bubble takes the \(tap) tap")
            // Where the finger lands, not the element: a tag over the
            // bubble takes a coordinate's tap, as it took the player's.
            bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(materials.appears(within: 10), "The \(tap) tap on the bubble's middle opens its station at its materials")
            XCTAssertTrue(materials.becomesHittable(within: 15), "The materials row is scrolled into view after the \(tap) tap")
            XCTAssertTrue(done.appears(within: 5))
            done.tap()
            XCTAssertTrue(materials.disappears(within: 10), "The station's panel closes")
        }
    }
}
