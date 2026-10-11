import XCTest

/// Screenshots for the game's website (decision 165), in Traditional
/// Chinese on a phone on its side. Run only by `website-screenshots.yml`,
/// never by the gate or the full lane: each test opens a screen and keeps
/// what it shows as an attachment the workflow exports. They check only
/// that the screen they photograph is there.
@MainActor
final class WebsiteScreenshotTests: XCTestCase {
    /// The freight scene (`ScreenshotScene.freight`): the map with the
    /// stations short of building materials, a yard's station picked (its
    /// tag says the goods waiting), and the freight train's card.
    func testFreight() {
        let app = launch(extra: ["-screenshot-scene", "freight"])
        defer { app.terminate() }
        let map = app.descendants(matching: .any)["map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 120), "The scene opens")
        let alert = app.buttons.matching(identifier: "map.alert").firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 30), "The stations short of materials show")
        settle()
        keep("freight-materials", app)

        alert.tap()
        settle()
        keep("freight-station", app)

        app.buttons["dock.build"].tap()
        let trainTool = app.buttons["tool.train"]
        trainTool.waitUntilSettled()
        trainTool.tap()
        let fleet = app.buttons["train.fleetOverview"]
        if !fleet.isHittable { app.swipeUp() }
        XCTAssertTrue(fleet.waitForExistence(timeout: 5))
        fleet.tap()
        let follow = app.buttons["fleet.follow.貨運列車 1"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        for _ in 0..<3 where !follow.isHittable { app.swipeUp() }
        follow.tap()
        XCTAssertTrue(app.buttons["train.unfollow"].waitForExistence(timeout: 5))
        settle()
        keep("freight-train", app)
    }

    /// A blank new game's map expansion: the tiles that can be bought,
    /// their prices, and the locked ones.
    func testMapExpansion() {
        let app = launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        let expansion = app.buttons["map.expansion"]
        XCTAssertTrue(expansion.waitForExistence(timeout: 30), "A blank map can be expanded")
        expansion.tap()
        settle(seconds: 3)
        keep("map-expansion", app)
    }

    /// The Liu Mingchuan challenge as it opens: its map from Keelung to
    /// Hsinchu, and the station master's first words.
    func testLiuMingchuanChallenge() {
        let app = launch()
        defer { app.terminate() }
        let challenges = app.buttons["start.challenges"]
        XCTAssertTrue(challenges.waitForExistence(timeout: 10))
        app.bringStartButtonIntoView(challenges)
        challenges.tap()
        let liu = app.buttons["challenge.history.liuMingchuan"]
        XCTAssertTrue(liu.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: liu)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "The real-world data loads")
        liu.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 60), "The challenge starts")
        settle(seconds: 8)
        keep("liu-mingchuan", app)
    }

    /// The real-world demo on the game's own base map (decision 151), the
    /// hills shaded from the game's heights.
    func testRealWorldDemoBaseMap() {
        let app = launch()
        defer { app.terminate() }
        app.openDemo("demo.realWorld", timeout: 60)
        XCTAssertTrue(app.descendants(matching: .any)["map"].firstMatch.waitForExistence(timeout: 60), "The demo starts")
        settle(seconds: 8)
        keep("real-world-demo", app)
    }

    // MARK: - Helpers

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"] + extra
        app.launch()
        return app
    }

    /// Lets the map draw and the animations end before a screenshot.
    private func settle(seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Keeps the screen as an attachment named `name`, which the workflow
    /// exports as `name.png`.
    private func keep(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
