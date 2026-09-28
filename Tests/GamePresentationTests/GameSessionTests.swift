import GameCore
import GamePresentation
import XCTest

// GameSession is main-actor isolated. Test methods hop onto the main actor
// with `MainActor.run` instead of isolating the XCTestCase subclass, which
// Swift 6.0 on Linux rejects under -warnings-as-errors.
final class GameSessionTests: XCTestCase {
    func testSessionOwnsTheWorldItWasGiven() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            XCTAssertEqual(session.world, world)
        }
    }
}
