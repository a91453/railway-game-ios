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
        // DIAGNOSTIC (claude/ipad-uitests-red), removed before review.
        print("DIAG lock \(lock.identifier) frame \(lock.frame) enabled \(lock.isEnabled) app \(app.frame) expansion \(expansion.frame) zoomOut \(zoomOut.frame) dockBuild \(app.buttons["dock.build"].frame)")
        let buy = app.buttons["map.expansion.buy"]
        func probe(_ dx: CGFloat, _ dy: CGFloat, _ name: String) {
            guard lock.appears(within: 5) else { print("DIAG no lock before \(name)"); return }
            let frame = lock.frame
            let at = CGPoint(x: frame.midX + dx, y: frame.midY + dy)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: at.x, dy: at.y)).tap()
            let opened = buy.appears(within: 4)
            print("DIAG \(name) lock \(frame) at \(at) opened: \(opened)")
            if opened {
                expansion.tap()
                _ = buy.disappears(within: 5)
                sleep(1)
            }
        }
        // Offsets from the lock's middle, in points.
        probe(0, 10, "A whole below")
        probe(0, -10, "B whole above")
        probe(0, 0.3, "C centre +0.3")
        probe(0, -0.3, "D centre -0.3")
        probe(0, 0, "E centre")
        probe(0.3, 2, "F +0.3, 2 below")
        probe(0, 2, "G whole 2 below")
        probe(0, 5.1, "H 5.1 below")
        if lock.appears(within: 5) { lock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap() }
        XCTAssertTrue(buy.appears(within: 5), "The lock opens the tile's card")
        XCTAssertEqual(expansion.label, "Stop expanding the map")
        XCTAssertFalse(lock.exists, "The tiles show their prices while choosing, not locks")
        expansion.tap()
        XCTAssertTrue(buy.disappears(within: 5))
        XCTAssertTrue(lock.appears(within: 5), "The locks come back")
    }
}
