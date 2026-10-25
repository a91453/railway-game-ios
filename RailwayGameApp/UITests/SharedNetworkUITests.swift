import XCTest

/// Decision 409: a network a friend sent offers a new game from it and a
/// look round it. In the full lane (decision 199): what each choice does
/// to the money and the saves is GamePresentation's, tested on Linux
/// (`SharedNetworkTests`); this asks only whether the sheet shows, a finger
/// reaches its choices, and Just Look opens the game.
@MainActor
final class SharedNetworkUITests: XCTestCase {
    func testAFriendsNetworkOffersBothChoicesAndJustLookOpensIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-shared-network", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let newGame = app.buttons["sharedNetwork.newGame"]
        XCTAssertTrue(newGame.appears(within: 30), "no sheet for the network sent")
        // On a phone on its side, as the tests before leave it, the
        // postcard fills the sheet and the choices are below it: the
        // player scrolls to them (the full lanes of main fcf0697 and
        // c4fc5b6 found Start a New Game there and not hittable). A slow
        // drag begun on a choice pressed it (run 40201864136: the seventh
        // drag began on Just Look and opened the game), so the drags start
        // clear of buttons.
        XCTAssertTrue(app.dragUntilWhollyOnScreen(newGame, clearOf: .button), "Start a New Game is not reachable")
        XCTAssertTrue(newGame.becomesHittable(within: 5), "Start a New Game is not reachable")
        let look = app.buttons["sharedNetwork.look"]
        XCTAssertTrue(app.dragUntilWhollyOnScreen(look, clearOf: .button), "Just Look is not reachable")
        XCTAssertTrue(look.becomesHittable(within: 5), "Just Look is not reachable")
        look.tap()
        XCTAssertTrue(look.disappears(within: 10), "the sheet stayed")
        XCTAssertTrue(app.buttons["Pause"].appears(within: 30), "the network did not open")
        XCTAssertFalse(app.buttons["start.newGame"].exists, "still on the start screen")
    }
}
