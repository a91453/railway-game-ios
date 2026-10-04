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
    // A dead-end line of the track network on row 1 (nodes at columns
    // 0–6, edges 1–6 eastward, see `TestLine`) with a station at each end:
    //
    //   row 0:        West            East
    //   row 1:   o - o - o - o - o - o - o
    //
    // West's platforms are either side of column 1, East's of column 5.
    // Express (1) stands at column 2 facing east; Local (2) stands at
    // East facing west, due to leave for West at minute 1.
    private static let line = TestLine(tiles: 7, row: 1)
    private static let express = TrainID(rawValue: 1)
    private static let local = TrainID(rawValue: 2)
    private static let east = StationID(rawValue: 2)

    private func makeLineWorld() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 3_072, balance: 100_000, speed: .normal)
        try Self.line.build(in: &world)
        let west = try Self.line.buildStation(named: "West", beside: 1, at: 0, in: &world)
        let east = try Self.line.buildStation(named: "East", beside: 5, at: 0, in: &world)
        try world.purchaseTrain(named: "Express")
        try world.placeTrain(Self.express, at: Self.line.at(2, facingEast: true))
        try world.purchaseTrain(named: "Local")
        try world.placeTrain(Self.local, at: Self.line.at(5, facingEast: false))
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
        try world.setTrainContinuation(Self.express, along: Self.line.path(from: 2, through: [3, 4, 5]))
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
        try world.setTrainContinuation(Self.express, along: Self.line.path(from: 2, through: [3, 4]))
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

    /// Stage U2: a service following another between calls says which
    /// train it follows while it is on its way, not that it waits.
    func testAFollowingTrainSaysWhichTrainItFollows() throws {
        // Four edges of 32768 east along y = 1024; A's platform on e1, M's
        // on e2. Leader stands at M and runs on to e4 slowly; Follower
        // stands at A and runs past M, so it sets off behind Leader.
        var world = try makeWorld(width: 133_120, height: 4_096, balance: 100_000_000, speed: .normal)
        let nodes = try (0..<5).map { try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Int64($0) * 32_768, y: 1_024)) }
        for (from, to) in zip(nodes, nodes.dropFirst()) {
            try world.buildTrackEdge(from: from, to: to)
        }
        var stations: [StationID] = []
        for (name, edge, start) in [("A", 1, Int64(1_024)), ("M", 2, 14_336), ("N", 3, 14_336), ("B", 4, 28_672)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: 1_024 + Int64(edge - 1) * 32_768 + start + 1_024, y: 2_048)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: start + 2_048)
            stations.append(station)
        }
        try world.setTrafficControl(true)
        for (name, edge, offset, stops) in [
            ("Leader", 2, Int64(16_384), [(stations[1], Int64(0), Int64(1)), (stations[3], 21, 21)]),
            ("Follower", 1, 3_072, [(stations[0], 0, 0), (stations[2], 7, 7)]),
        ] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 1_024)
            try world.setTrainTimetable(id, to: stops.map {
                ScheduledStop(station: $0.0, arrival: GameTime(minutes: $0.1), departure: GameTime(minutes: $0.2))
            })
            try world.startTrainService(id)
        }
        let (leader, follower) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        // At 1:00 Leader still stands at M: Follower waits for it.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.routeWaitText(of: follower, in: .english), "Waiting for Leader to clear the route")
        // A minute later both are on their way, Follower behind Leader.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: follower)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: follower), leader)
        XCTAssertEqual(world.routeWaitText(of: follower, in: .english), "Following Leader")
        XCTAssertEqual(world.routeWaitText(of: follower, in: .traditionalChinese), "跟在 Leader 後面")
        XCTAssertNil(world.routeWaitText(of: leader, in: .english))
    }

    /// Stage V2: two expresses face each other across a single track with
    /// a passing loop at M. Each waits for the other (a deadlock) until the
    /// dispatcher sends Eastbound to stand aside at M.
    func testADeadlockAndAPassingPlaceAreToldInThePlayersWords() throws {
        var world = try makeWorld(width: 36_864, height: 12_288, balance: 100_000_000, speed: .normal)
        for (x, y) in [(1_024, 4_096), (9_216, 4_096), (25_600, 4_096), (33_792, 4_096), (13_312, 6_144), (21_504, 6_144)] as [(Int64, Int64)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        for edge in 1...3 { try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        try world.buildTrackEdge(from: .node(2), to: .node(5), curve: .cubic(PlanPoint(x: 11_264, y: 4_096), PlanPoint(x: 11_264, y: 6_144)))
        try world.buildTrackEdge(from: .node(5), to: .node(6))
        try world.buildTrackEdge(from: .node(6), to: .node(3), curve: .cubic(PlanPoint(x: 23_552, y: 6_144), PlanPoint(x: 23_552, y: 4_096)))
        var stations: [StationID] = []
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            stations.append(try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192)).id)
        }
        for (station, edge, start) in [(0, 1, Int64(1_024)), (1, 2, 7_168), (1, 5, 3_072), (2, 3, 5_120)] {
            try world.addTrackPlatform(stations[station], on: .edge(edge), from: start, to: start + 2_048)
        }
        for (name, traversal, stops) in [
            ("Eastbound", TrackTraversal(edge: .edge(1), direction: .forward), [stations[0], stations[2]]),
            ("Westbound", TrackTraversal(edge: .edge(3), direction: .backward), [stations[2], stations[0]]),
        ] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(traversal, offset: 3_072))
            try world.setTrainContinuation(id, along: [], stoppingAt: 3_072)
            try world.setTrainMovementRate(id, to: 1_024)
            try world.setTrainTimetable(id, to: stops.enumerated().map {
                ScheduledStop(station: $0.element, arrival: GameTime(minutes: Int64($0.offset) * 4), departure: GameTime(minutes: Int64($0.offset) * 4))
            })
            try world.startTrainService(id)
        }
        try world.setTrafficControl(true)
        let (east, west) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        try world.advance(ticks: 1)
        XCTAssertEqual(world.routeWaitText(of: east, in: .english), "Deadlocked with Westbound")
        XCTAssertEqual(world.routeWaitText(of: west, in: .traditionalChinese), "與 Eastbound 互相卡住（死結）")
        try world.advance(ticks: 1)
        XCTAssertEqual(world.passingPlace(of: east), stations[1])
        XCTAssertEqual(world.routeWaitText(of: east, in: .english), "Standing aside at M until Westbound clears the route")
        XCTAssertEqual(world.routeWaitText(of: east, in: .traditionalChinese), "在 M 待避，等待 Westbound 讓出進路")
    }

    func testARouteAnotherTrainHoldsIsRefusedInThePlayersWords() async throws {
        var world = try makeLineWorld()
        try world.stopTrainService(Self.local)
        try world.setTrafficControl(true)
        try world.setTrainContinuation(Self.local, along: Self.line.path(from: 5, through: [4, 3]))
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTrain(Self.express)
            session.selectStation(Self.east)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(
                kind: .failure, text: "Train #2 holds that track under traffic control. Wait for it to clear the route."
            ))
        }
    }
}
