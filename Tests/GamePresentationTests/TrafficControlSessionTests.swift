import GameCore
import GamePresentation
import XCTest

/// Stage T in the app: traffic control is turned on and off through one
/// `GameWorld` command, a refused route is reported in the player's words,
/// and a train waiting for its route says which train it waits for, read
/// from `GameWorld.trainHoldingRoute(of:)` and never stored.
///
/// Each test compares the session's world with the same commands applied to
/// GameCore directly.
final class TrafficControlSessionTests: XCTestCase {
    // A dead-end line on row 1 with a station at each end:
    //
    //       West            East
    //   a - b - c - d - e - f - g
    //
    // West's platform is b (1, 1), East's f (5, 1). Express (1) stands at c
    // facing east; Local (2) stands at East's platform facing west, due to
    // leave for West at minute 1.
    private static let express = TrainID(rawValue: 1)
    private static let local = TrainID(rawValue: 2)

    private static func tile(_ x: Int) -> GridPosition {
        GridPosition(x: x, y: 1)
    }

    private func makeLineWorld() throws -> GameWorld {
        var world = try makeWorld(width: 8, height: 3, balance: 100_000, speed: .normal)
        try world.buildTrack(at: Self.tile(0), connections: .east)
        for x in 1...5 {
            try world.buildTrack(at: Self.tile(x), connections: [.east, .west])
        }
        try world.buildTrack(at: Self.tile(6), connections: .west)
        let west = try world.buildStation(named: "West", at: GridPosition(x: 1, y: 0)).id
        let east = try world.buildStation(named: "East", at: GridPosition(x: 5, y: 0)).id
        try world.purchaseTrain(named: "Express")
        try world.placeTrain(Self.express, at: .atNode(Self.tile(2), heading: .east))
        try world.purchaseTrain(named: "Local")
        try world.placeTrain(Self.local, at: .atNode(Self.tile(5), heading: .west))
        try world.setTrainMovementRate(Self.local, to: 1_024)
        try world.setTrainTimetable(Self.local, to: [
            ScheduledStop(station: east, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: west, arrival: GameTime(minutes: 10), departure: GameTime(minutes: 10)),
        ])
        try world.startTrainService(Self.local)
        return world
    }

    func testTrafficControlIsTurnedOnAndOffThroughGameCore() async throws {
        let world = try makeLineWorld()
        var on = world
        try on.setTrafficControl(true)
        var off = on
        try off.setTrafficControl(false)
        await MainActor.run { [on, off] in
            let session = GameSession(world: world)
            XCTAssertFalse(session.world.isTrafficControlEnabled)
            session.setTrafficControl(true)
            XCTAssertEqual(session.world, on)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Traffic control is on. Trains take their whole route before they leave."))
            session.setTrafficControl(false)
            XCTAssertEqual(session.world, off)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Traffic control is off. Trains no longer wait for each other."))
        }
    }

    func testTrafficControlIsRefusedOverSharedTrackAndNothingChanges() async throws {
        var world = try makeLineWorld()
        // Sent on to East without traffic control, Express needs the
        // platform Local stands on.
        try world.setTrainContinuation(Self.express, to: [Self.tile(3), Self.tile(4), Self.tile(5)])
        var expected = world
        do throws(GameError) {
            try expected.setTrafficControl(true)
            XCTFail("traffic control was turned on over shared track")
        } catch {
            XCTAssertEqual(error, .trainsShareTrack(Self.express, Self.local))
        }
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.setTrafficControl(true)
            XCTAssertEqual(session.world, world)
            XCTAssertFalse(session.world.isTrafficControlEnabled)
            XCTAssertEqual(session.message, StatusMessage(
                kind: .failure,
                text: "Trains #1 and #2 need the same track, so traffic control can't be turned on. Move one of them first."
            ))
        }
    }

    func testAWaitingTrainSaysWhichTrainHoldsItsRoute() async throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        try world.setTrainContinuation(Self.express, to: [Self.tile(3), Self.tile(4)])
        // Before its departure is due, Local does not wait for anything.
        XCTAssertNil(world.routeWaitText(of: Self.local, in: .english))
        var expected = world
        try expected.advance(ticks: 1)
        XCTAssertEqual(expected.trainHoldingRoute(of: Self.local), Self.express)
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.advance(realElapsed: GameSession.tickInterval)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.world.train(id: Self.local)?.execution, .waitingAtStop(0, cycle: 0))
            XCTAssertEqual(session.world.routeWaitText(of: Self.local, in: .english), "Waiting for Express to clear the route")
            XCTAssertNil(session.world.routeWaitText(of: Self.express, in: .english), "Express is not waiting for a route")
            XCTAssertNil(session.world.routeWaitText(of: TrainID(rawValue: 9), in: .english))
            // Without traffic control nothing waits.
            session.setTrafficControl(false)
            XCTAssertNil(session.world.routeWaitText(of: Self.local, in: .english))
        }
    }

    func testARouteAnotherTrainHoldsIsRefusedInThePlayersWords() async throws {
        var world = try makeLineWorld()
        try world.stopTrainService(Self.local)
        try world.setTrafficControl(true)
        try world.setTrainContinuation(Self.local, to: [Self.tile(4), Self.tile(3)])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTrain(Self.express)
            session.select(Self.tile(4))
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(
                kind: .failure, text: "Train #2 holds that track under traffic control. Wait for it to clear the route."
            ))
        }
    }
}
