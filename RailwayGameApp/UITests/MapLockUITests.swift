import XCTest

/// Decision 167, later: a blank new game owns one tile of its map, and
/// the tiles beside it carry a lock; tapping one opens that tile's card.
/// In the full lane (decision 199): which tiles, where and what a tap does
/// are GamePresentation's, tested on Linux (`MapLockTests`); this asks only
/// whether a lock shows and a finger reaches it.
@MainActor
final class MapLockUITests: XCTestCase {
    func testALockOpensItsTilesCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let newGame = app.buttons["start.newGame"]
        XCTAssertTrue(newGame.appears(within: 10))
        app.bringStartButtonIntoView(newGame)
        newGame.tap()
        app.chooseBlankMap()
        let expansion = app.buttons["map.expansion"]
        XCTAssertTrue(expansion.appears(within: 30), "A blank map can be expanded")

        // Zoomed out until a tile beside the land owned is in view: a
        // blank map opens on its town, some 2⁵ times closer than the
        // farthest zoom, and its tile is far wider than the town (run
        // 39545597750 stopped after four taps, the tile's edge still off
        // the screen; on Linux the seventh shows the first locks).
        let lock = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.lock.'")).firstMatch
        let zoomOut = app.buttons["Zoom out"]
        XCTAssertTrue(zoomOut.appears(within: 10))
        for _ in 0..<12 where !lock.exists && zoomOut.isEnabled {
            zoomOut.tap()
            _ = lock.appears(within: 1)
        }
        XCTAssertTrue(lock.appears(within: 5), "No lock on the tiles for sale")
        XCTAssertEqual(lock.label, "Locked land")
        XCTAssertTrue(lock.becomesHittable(within: 5), "The lock is not reachable")
        lock.tap()

        let buy = app.buttons["map.expansion.buy"]
        XCTAssertTrue(buy.appears(within: 5), "The lock opens the tile's card")
        XCTAssertEqual(expansion.label, "Stop expanding the map")
        XCTAssertFalse(lock.exists, "The tiles show their prices while choosing, not locks")
        expansion.tap()
        XCTAssertTrue(buy.disappears(within: 5))
        XCTAssertTrue(lock.appears(within: 5), "The locks come back")
    }
}
