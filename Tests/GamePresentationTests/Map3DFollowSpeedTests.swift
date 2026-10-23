import GameCore
import GamePresentation
import XCTest

/// Decision 360: following a train on the 3D map runs at 10× at most, so
/// the ground ahead is built in time (decision 358); the 2D map's speeds
/// stay as they are, and leaving the 3D map, or following, gives the 2D
/// speed back.
final class Map3DFollowSpeedTests: XCTestCase {
    private static let line = TestLine(tiles: 6, row: 2)
    private static let train = TrainID(rawValue: 1)

    private func makeFollowWorld(speed: GameSpeed) throws -> GameWorld {
        var world = try makeWorld(speed: speed)
        try Self.line.build(in: &world)
        try world.purchaseTrain(named: "Train 1")
        try world.placeTrain(Self.train, at: Self.line.at(1, facingEast: true))
        return world
    }

    func testTheMenuGoesUpToTenTimesOnlyWhileFollowingIn3D() {
        XCTAssertEqual(Map3DFollowSpeed.fastest, .x10)
        XCTAssertEqual(Map3DFollowSpeed.choices(capped: false), [.x1, .x10, .x60, .normal, .double, .fast], "the 2D menu is unchanged")
        XCTAssertEqual(Map3DFollowSpeed.choices(capped: true), [.x1, .x10])
        XCTAssertEqual(Map3DFollowSpeed.capped(.normal), .x10)
        XCTAssertEqual(Map3DFollowSpeed.capped(.x1), .x1)
        XCTAssertEqual(Map3DFollowSpeed.capped(.paused), .paused)
        XCTAssertEqual(Map3DFollowSpeed.limitText(in: .english), "Up to 10× while following in 3D")
        XCTAssertEqual(Map3DFollowSpeed.limitText(in: .traditionalChinese), "3D 跟車時最高 10×")
    }

    func testFollowingIn3DAtSixHundredRunsAtTenAndLeavingGivesSixHundredBack() async throws {
        let world = try makeFollowWorld(speed: .normal)
        await MainActor.run {
            let session = GameSession(world: world)
            session.followTrain(Self.train)
            XCTAssertEqual(session.speedChoices, Map3DFollowSpeed.choices(capped: false), "following on the 2D map keeps every speed")
            XCTAssertEqual(session.world.clock.speed, .normal)

            session.setMap3DOpen(true)
            XCTAssertTrue(session.isSpeedCappedIn3D)
            XCTAssertEqual(session.world.clock.speed, .x10)
            XCTAssertEqual(session.speedChoices, [.x1, .x10])

            // Nothing faster is taken while capped, whatever asks for it.
            session.setSpeed(.fast)
            XCTAssertEqual(session.world.clock.speed, .x10)

            session.setMap3DOpen(false)
            XCTAssertFalse(session.isSpeedCappedIn3D)
            XCTAssertEqual(session.world.clock.speed, .normal, "the 2D map runs at the speed it had")
            XCTAssertEqual(session.speedChoices, Map3DFollowSpeed.choices(capped: false))
        }
    }

    func testTheCapStartsAndEndsWithFollowingInside3D() async throws {
        let world = try makeFollowWorld(speed: .double)
        await MainActor.run {
            let session = GameSession(world: world)
            session.setMap3DOpen(true)
            XCTAssertFalse(session.isSpeedCappedIn3D, "looking around the 3D map is not following")
            XCTAssertEqual(session.world.clock.speed, .double)

            session.followTrain(Self.train)
            XCTAssertEqual(session.world.clock.speed, .x10)
            // The player picks real time while following in 3D.
            session.setSpeed(.x1)
            XCTAssertEqual(session.world.clock.speed, .x1)

            session.stopFollowingTrain()
            XCTAssertEqual(session.world.clock.speed, .double)
        }
    }

    func testASpeedAlreadyWithinTheCapIsKept() async throws {
        let world = try makeFollowWorld(speed: .x1)
        await MainActor.run {
            let session = GameSession(world: world)
            session.followTrain(Self.train)
            session.setMap3DOpen(true)
            XCTAssertEqual(session.world.clock.speed, .x1)
            session.setSpeed(.x10)
            session.setMap3DOpen(false)
            XCTAssertEqual(session.world.clock.speed, .x10, "a speed the player chose within the cap stays")
        }
    }

    func testAPausedGameStaysPausedAndResumesWithinTheCap() async throws {
        var world = try makeFollowWorld(speed: .normal)
        world.pause()
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.followTrain(Self.train)
            session.setMap3DOpen(true)
            XCTAssertTrue(session.world.clock.isPaused)
            XCTAssertEqual(session.world.clock.runningSpeed, .x10)
            XCTAssertEqual(session.worldToSave.clock.runningSpeed, .normal, "a save keeps the 2D speed")
            XCTAssertTrue(session.worldToSave.clock.isPaused)

            session.togglePause()
            XCTAssertEqual(session.world.clock.speed, .x10)
            XCTAssertEqual(session.worldToSave.clock.speed, .normal)
            session.togglePause()

            session.setMap3DOpen(false)
            XCTAssertTrue(session.world.clock.isPaused, "leaving does not start the game")
            XCTAssertEqual(session.world.clock.runningSpeed, .normal)
        }
    }
}
