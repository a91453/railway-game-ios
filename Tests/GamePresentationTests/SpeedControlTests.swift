import GameCore
import GamePresentation
import XCTest

final class SpeedControlTests: XCTestCase {
    func testSpeedIsReadFromAndWrittenToTheWorldClock() async throws {
        let world = try makeWorld(speed: .paused)
        await MainActor.run {
            let session = GameSession(world: world)

            session.setSpeed(.double)
            XCTAssertEqual(session.world.clock.speed, .double)

            session.setSpeed(.paused)
            XCTAssertTrue(session.world.clock.isPaused)

            session.setSpeed(.normal)
            XCTAssertEqual(session.world.clock.speed, .normal)
            XCTAssertEqual(session.world.clock.now, .zero, "changing speed does not move time")
        }
    }

    func testCommandsUpdateTheCashSeenByTheHUDImmediately() async throws {
        let world = try makeWorld(balance: 10_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(GridPosition(x: 0, y: 0))
            session.selectTool(.buildTrack)
            session.applyTool()
            XCTAssertEqual(session.world.economy.balance.displayText, "9,900")

            session.select(GridPosition(x: 1, y: 0))
            session.selectTool(.buildStation)
            session.applyTool()
            XCTAssertEqual(session.world.economy.balance.displayText, "8,900")
        }
    }
}
