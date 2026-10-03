import Foundation
import GameCore
import XCTest

/// Stage S5 (ARCHITECTURE decision 31): stops, timetables, repeats, lines,
/// dispatch and patterns on the continuous track network. Expected values
/// are worked out by hand from the rules and written out, never taken from
/// a previous run; curve lengths follow decision 29's integer sampling.
/// Since Stage W2c a service's train follows a running curve between calls
/// (``ServiceRun``): its position mid-run is where that curve has taken it
/// (`runDistance`), and a line plans each leg with the least seconds its
/// performance needs (standard here: √(2 × length × 0.06) when the train
/// never reaches its top speed, rounded up).
final class NetworkServiceTests: XCTestCase {
    // MARK: - The straight line
    //
    // Four nodes on the surface, 8192 apart eastward at y = 1024, joined by
    // three straight edges; dead ends at a and d:
    //
    //   a ──e1── b ──e2── c ──e3── d
    //
    // - West on e1 from 1024 to 5120 (4096 long): berths e1 forward at 5120
    //   and e1 backward at 8192 − 1024 = 7168.
    // - Mid on e2 from 3000 to 5048 (2048: a train of three cars exactly):
    //   e2 forward at 5048, backward at 8192 − 3000 = 5192.
    // - East on e3 from 4096 to 5120 (1024: two cars exactly): e3 forward
    //   at 5120, backward at 4096.
    // - Terminus on e3 from 6144 to 8192 (2048): e3 forward at 8192, which
    //   is d (the end of e3, so a path there has no `end`), backward at 2048.
    private let e1 = TrackEdgeID.edge(1)
    private let e2 = TrackEdgeID.edge(2)
    private let e3 = TrackEdgeID.edge(3)
    private let e4 = TrackEdgeID.edge(4)
    private let west = StationID(rawValue: 1)
    private let mid = StationID(rawValue: 2)
    private let east = StationID(rawValue: 3)
    private let terminus = StationID(rawValue: 4)
    private let main = LineID(rawValue: 1)

    private func forward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .forward)
    }

    private func backward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .backward)
    }

    private func minutes(_ minute: Int64) -> GameTime {
        GameTime(minutes: minute)
    }

    private func makeStraightWorld(minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            width: 32, height: 8, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        let nodes = try [1_024, 9_216, 17_408, 25_600].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 1_024)) }
        for index in 0..<3 {
            try world.buildTrackEdge(from: nodes[index], to: nodes[index + 1])
        }
        for (index, name) in ["West", "Mid", "East", "Terminus"].enumerated() {
            try world.buildStation(named: name, at: TestLine.centre(index + 1, 6))
        }
        try world.addTrackPlatform(west, on: e1, from: 1_024, to: 5_120)
        try world.addTrackPlatform(mid, on: e2, from: 3_000, to: 5_048)
        try world.addTrackPlatform(east, on: e3, from: 4_096, to: 5_120)
        try world.addTrackPlatform(terminus, on: e3, from: 6_144, to: 8_192)
        return world
    }

    /// Buys a train of `cars` cars, places it at `position` and stops it
    /// there with a path that ends where it stands (none needed at the end
    /// of an edge), moving at `rate`.
    private func stoppedTrain(_ cars: Int, at position: TrainPosition, rate: Int64 = 1_024, in world: inout GameWorld) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T\(world.trains.count + 1)").id
        try world.setTrainCars(id, to: cars)
        try world.placeTrain(id, at: position)
        guard case .onEdge(let traversal, let offset) = position, let length = world.trackEdge(traversal.edge)?.length else {
            throw XCTSkip("a train on the network")
        }
        try world.setTrainContinuation(id, along: [], stoppingAt: offset < length ? offset : nil)
        try world.setTrainMovementRate(id, to: rate)
        return id
    }

    private func train(_ world: GameWorld, _ id: TrainID) throws -> Train {
        try XCTUnwrap(world.train(id: id))
    }

    // MARK: - Berths and paths

    /// A path to a station ends with the head at the far end of one of its
    /// platforms the way the train travels: `end` going forward,
    /// `L − start` along the edge going backward.
    func testAPathEndsAtTheFarEndOfAPlatformTheWayTheTrainTravels() throws {
        let world = try makeStraightWorld()
        let fromA = TrainPosition.onEdge(forward(e1), offset: 0)
        // West's berth is ahead on the train's own edge: 5120 along it.
        XCTAssertEqual(world.path(from: fromA, toStation: west), TrainPath(traversals: [], end: 5_120, distance: 5_120))
        // Mid: the rest of e1 (8192), then 5048 into e2.
        XCTAssertEqual(world.path(from: fromA, toStation: mid), TrainPath(traversals: [forward(e2)], end: 5_048, distance: 13_240))
        // East: two whole edges (8192 each) and 5120 into e3.
        XCTAssertEqual(world.path(from: fromA, toStation: east), TrainPath(traversals: [forward(e2), forward(e3)], end: 5_120, distance: 21_504))
        // Terminus: its far end is d, the end of e3, so the path has no end.
        XCTAssertEqual(world.path(from: fromA, toStation: terminus), TrainPath(traversals: [forward(e2), forward(e3)], end: nil, distance: 24_576))

        // Going west from d: each platform's start is its far end.
        let fromD = TrainPosition.onEdge(backward(e3), offset: 0)
        XCTAssertEqual(world.path(from: fromD, toStation: terminus), TrainPath(traversals: [], end: 2_048, distance: 2_048))
        XCTAssertEqual(world.path(from: fromD, toStation: east), TrainPath(traversals: [], end: 4_096, distance: 4_096))
        XCTAssertEqual(world.path(from: fromD, toStation: mid), TrainPath(traversals: [backward(e2)], end: 5_192, distance: 13_384))
        XCTAssertEqual(world.path(from: fromD, toStation: west), TrainPath(traversals: [backward(e2), backward(e1)], end: 7_168, distance: 23_552))
    }

    /// Distances are exact: the rest of the current edge, every edge
    /// between in full and the stretch into the last; never the edges
    /// counted as links.
    func testAPathIsItsExactDistance() throws {
        let world = try makeStraightWorld()
        // 3000 along e1: 5192 to its end, then 5048 into e2.
        XCTAssertEqual(world.path(from: .onEdge(forward(e1), offset: 3_000), toStation: mid)?.distance, 10_240)
        // At the end of e1 (b): nothing left of e1, 5048 into e2.
        XCTAssertEqual(world.path(from: .onEdge(forward(e1), offset: 8_192), toStation: mid), TrainPath(traversals: [forward(e2)], end: 5_048, distance: 5_048))
        // At Mid's berth already: nothing to travel.
        XCTAssertEqual(world.path(from: .onEdge(forward(e2), offset: 5_048), toStation: mid), TrainPath(traversals: [], end: 5_048, distance: 0))
        // Past West going east: West is behind, and a path never turns back.
        XCTAssertNil(world.path(from: .onEdge(forward(e1), offset: 6_000), toStation: west))
        // No platform on the network, no station, off the network.
        var bare = world
        try bare.buildStation(named: "Bare", at: TestLine.centre(9, 6))
        XCTAssertNil(bare.path(from: .onEdge(forward(e1), offset: 0), toStation: StationID(rawValue: 5)))
        XCTAssertNil(world.path(from: .onEdge(forward(e1), offset: 0), toStation: StationID(rawValue: 9)))
        XCTAssertNil(world.path(from: .onEdge(forward(e1), offset: 8_193), toStation: mid))
        XCTAssertNil(world.path(from: .onEdge(forward(.edge(7)), offset: 0), toStation: mid))
    }

    /// A platform is a berth only for a train no longer than it: three cars
    /// (2048) fit Mid and Terminus exactly and West, not East; four (3072)
    /// fit only West.
    func testOnlyPlatformsATrainFitsAreBerthsForIt() throws {
        let world = try makeStraightWorld()
        let start = TrainPosition.onEdge(forward(e1), offset: 0)
        XCTAssertNil(world.path(from: start, toStation: east, length: 2_048))
        XCTAssertEqual(world.path(from: start, toStation: east, length: 1_024)?.end, 5_120, "two cars fit exactly")
        XCTAssertEqual(world.path(from: start, toStation: mid, length: 2_048)?.distance, 13_240)
        XCTAssertEqual(world.path(from: start, toStation: terminus, length: 2_048)?.distance, 24_576)
        XCTAssertNil(world.path(from: start, toStation: mid, length: 3_072))
        XCTAssertNil(world.path(from: start, toStation: terminus, length: 3_072))
        XCTAssertEqual(world.path(from: start, toStation: west, length: 3_072)?.end, 5_120)
    }

    /// Where two routes to a station are equally long, the one that turns
    /// into the lower numbered edge where they part is taken, whichever way
    /// that edge runs and in whatever order the platforms were added.
    ///
    /// x (1024, 4096) to y (9216, 4096) is 8192; from y two branches run to
    /// (17408, 4096 ± 400): √(8192² + 400²) = 8201.8, both 8202, each
    /// leaving y within 1 in 16 of straight. Fork has a platform from 4000
    /// to 6048 on each: 8192 + 6048 = 14240 either way.
    func testEqualRoutesAreDecidedByEdgeNumber() throws {
        for northFirst in [true, false] {
            var world = try GameWorld(width: 20, height: 8, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
            let x = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_096))
            let y = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 4_096))
            let north = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: 3_696))
            let south = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: 4_496))
            try world.buildTrackEdge(from: x, to: y)
            try world.buildTrackEdge(from: y, to: northFirst ? north : south)
            try world.buildTrackEdge(from: y, to: northFirst ? south : north)
            XCTAssertEqual(world.trackEdge(e2)?.length, 8_202)
            XCTAssertEqual(world.trackEdge(e3)?.length, 8_202)
            let fork = try world.buildStation(named: "Fork", at: TestLine.centre(1, 7)).id
            try world.addTrackPlatform(fork, on: e3, from: 4_000, to: 6_048)
            try world.addTrackPlatform(fork, on: e2, from: 4_000, to: 6_048)
            XCTAssertEqual(
                world.path(from: .onEdge(forward(e1), offset: 0), toStation: fork),
                TrainPath(traversals: [forward(e2)], end: 6_048, distance: 14_240), northFirst ? "north is e2" : "south is e2"
            )
        }
    }

    // MARK: - Stops

    /// A train on the network is stopped at a station when its path is
    /// spent and its head is on one of the station's platforms; with its
    /// whole length when its body lies on that platform too.
    func testATrainStopsWhereItsPathEndsOnAPlatform() throws {
        var world = try makeStraightWorld()
        let id = try world.purchaseTrain(named: "Long").id
        try world.setTrainCars(id, to: 3)
        try world.placeTrain(id, at: .onEdge(forward(e1), offset: 5_120))
        // On West's berth with no path: it would run on to the end of e1.
        XCTAssertEqual(world.stationsStoppedAt(by: id), [])
        // A path that ends where it stands: stopped, body 3072...5120 on
        // the platform 1024...5120.
        try world.setTrainContinuation(id, along: [], stoppingAt: 5_120)
        XCTAssertEqual(world.stationsStoppedAt(by: id), [west])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [west])
        try world.setTrainMovementRate(id, to: 1_024)
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e1), offset: 5_120), "a spent path holds the train")

        // By hand to East's berth, which no service would take three cars
        // to: 3072 + 8192 + 5120 = 16384, sixteen minutes.
        try world.setTrainContinuation(id, along: [forward(e2), forward(e3)], stoppingAt: 5_120)
        XCTAssertEqual(world.stationsStoppedAt(by: id), [], "a path left is not a stop")
        try world.advance(ticks: 7)
        // 7168 on: 3072 to b, 4096 into e2, on Mid's platform but passing.
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e2), offset: 4_096))
        XCTAssertEqual(try train(world, id).movement.remainingEdges, [e3])
        XCTAssertEqual(world.stationsStoppedAt(by: id), [])
        try world.advance(ticks: 9)
        let arrived = try train(world, id)
        XCTAssertEqual(arrived.position, .onEdge(forward(e3), offset: 5_120))
        XCTAssertEqual(arrived.movement.edges, [])
        XCTAssertEqual(arrived.movement.end, 5_120)
        XCTAssertEqual(arrived.trailEdges, [])
        // Head on East's platform (4096...5120), tail at 3072 off it.
        XCTAssertEqual(world.stationsStoppedAt(by: id), [east])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [])

        // Clearing the path runs the train on to d: Terminus, 6144...8192.
        try world.setTrainContinuation(id, along: [])
        XCTAssertNil(try train(world, id).movement.end)
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e3), offset: 8_192))
        XCTAssertEqual(world.stationsStoppedAt(by: id), [terminus])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [terminus])
        // Turned round by hand (Stage S3): the head goes to the tail, 2048
        // along e3 backward, and with no path the train runs on west.
        try world.reverseTrain(id)
        XCTAssertEqual(try train(world, id).position, .onEdge(backward(e3), offset: 2_048))
        XCTAssertEqual(world.stationsStoppedAt(by: id), [])
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).position, .onEdge(backward(e3), offset: 3_072))
    }

    /// A path to stop on the network is checked: the grid has no end, and
    /// on the network the end lies before the end of its last edge, after
    /// its start once an edge is entered, and not behind the train.
    func testAPathEndIsChecked() throws {
        var world = try makeStraightWorld()
        let id = try world.purchaseTrain(named: "One").id
        try world.placeTrain(id, at: .onEdge(forward(e2), offset: 2_000))
        let before = world
        for (traversals, end) in [([], 8_192), ([], 1_999), ([forward(e3)], 0), ([forward(e3)], 8_192), ([backward(e1)], 100)] as [([TrackTraversal], Int64)] {
            XCTAssertThrowsGameError(try world.setTrainContinuation(id, along: traversals, stoppingAt: end), .invalidContinuation)
            XCTAssertEqual(world, before)
        }
        try world.setTrainContinuation(id, along: [], stoppingAt: 2_000)
        XCTAssertEqual(try train(world, id).movement.end, 2_000)
        try world.setTrainContinuation(id, along: [forward(e3)], stoppingAt: 1)
        XCTAssertEqual(try train(world, id).movement.edges, [e3])
        XCTAssertEqual(try train(world, id).movement.end, 1)
        // A train of one car at the start of an edge may stand there.
        let other = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(other, at: .onEdge(backward(e3), offset: 0))
        try world.setTrainContinuation(other, along: [], stoppingAt: 0)
        XCTAssertEqual(try train(world, other).movement.end, 0)

        var grid = try GameWorld(width: 4, height: 4, economy: GameEconomy(balance: 10_000, costs: testCosts))
        try grid.buildTrack(at: GridPosition(x: 1, y: 1), connections: [.east, .west])
        try grid.buildTrack(at: GridPosition(x: 2, y: 1), connections: [.east, .west])
        let onGrid = try grid.purchaseTrain(named: "Grid").id
        try grid.placeTrain(onGrid, at: .atNode(GridPosition(x: 1, y: 1), heading: .east))
        XCTAssertThrowsGameError(try grid.setTrainContinuation(onGrid, along: [], stoppingAt: 0), .invalidContinuation)
    }

    // MARK: - Timetables

    /// A one-way timetable West to Mid for three cars: 3072 + 5048 = 8120,
    /// in the ten minutes from leaving at 10 to arriving at 20 (Stage W2c:
    /// a run of 600 s on the standard curve, cruising at about 13.5 units a
    /// second).
    func testATimetableRunsFromPlatformToPlatform() throws {
        var world = try makeStraightWorld()
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: west, arrival: minutes(0), departure: minutes(10)),
            ScheduledStop(station: mid, arrival: minutes(20), departure: minutes(25)),
        ])
        try world.startTrainService(id)
        try world.advance(ticks: 10)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e1), offset: 5_120))

        // Minute 10: it leaves, with e2 to enter and its path ending at 5048,
        // 809 units along its curve a minute later.
        try world.advance(ticks: 1)
        var running = try train(world, id)
        XCTAssertEqual(running.execution, .travellingToStop(1))
        XCTAssertEqual(running.times?.run, ServiceRun(start: minutes(10), length: 8_120, seconds: 600))
        XCTAssertEqual(running.position, .onEdge(forward(e1), offset: 5_120 + runDistance(8_120, in: 600, after: 60)))
        XCTAssertEqual(running.movement.edges, [e2])
        XCTAssertEqual(running.movement.end, 5_048)
        // At 17, 5684 along: past b (3072), into e2.
        try world.advance(ticks: 6)
        running = try train(world, id)
        XCTAssertEqual(running.position, .onEdge(forward(e2), offset: runDistance(8_120, in: 600, after: 420) - 3_072))
        XCTAssertEqual(running.execution, .travellingToStop(1))
        try world.advance(ticks: 2)
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e2), offset: runDistance(8_120, in: 600, after: 540) - 3_072))
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1))
        // At Mid's berth at 20, on time.
        try world.advance(ticks: 1)
        let arrived = try train(world, id)
        XCTAssertEqual(world.clock.now, minutes(20))
        XCTAssertEqual(arrived.times?.arrival, minutes(20))
        XCTAssertNil(arrived.times?.run)
        XCTAssertEqual(arrived.position, .onEdge(forward(e2), offset: 5_048))
        XCTAssertEqual(arrived.execution, .waitingAtStop(1))
        XCTAssertEqual(world.stationsStoppedAt(by: id), [mid])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [mid], "3000...5048 exactly")

        // It waits for its last departure at 25; then the service is over
        // and the train stays where its path ends.
        try world.advance(ticks: 5)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(1))
        try world.advance(ticks: 1)
        XCTAssertNil(try train(world, id).execution)
        try world.advance(ticks: 5)
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e2), offset: 5_048))
        XCTAssertEqual(world.stationsStoppedAt(by: id), [mid])
    }

    /// Late: due at Mid 20 s after leaving West at 10 and away at 10:30, the
    /// train needs 32 s for the 8120 units (Stage W2c: √(2 × 8120 × 0.06) =
    /// 31.2), so it gets there at 10:32, after its departure, and its
    /// service ends once it has dwelt the least a terminal needs, 42 s, at
    /// 11:14.
    func testALateTrainLeavesAsSoonAsItHasArrived() throws {
        var world = try makeStraightWorld()
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: west, arrival: minutes(0), departure: minutes(10)),
            ScheduledStop(station: mid, arrival: GameTime(seconds: 620), departure: GameTime(seconds: 630)),
        ])
        try world.startTrainService(id)
        try world.advance(ticks: 11)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(world, id).times?.arrival, GameTime(seconds: 632))
        XCTAssertEqual(try train(world, id).times?.departure, minutes(10))
        try world.advance(ticks: 1)
        XCTAssertNil(try train(world, id).execution)
    }

    /// Without a platform the train fits, a service waits at its stop, not
    /// turned and not moved, and tries again each step. A stop that turns
    /// the train round turns it only once there is a way on from there.
    func testAServiceWithoutAPathWaitsAndIsNotTurnedRound() throws {
        var world = try makeStraightWorld()
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: west, arrival: minutes(0), departure: minutes(0), reverses: true),
            ScheduledStop(station: east, arrival: minutes(30), departure: minutes(30)),
        ])
        try world.startTrainService(id)
        let waiting = try train(world, id)
        try world.advance(ticks: 5)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(world, id).position, waiting.position, "not turned round")
        XCTAssertEqual(try train(world, id).movement, waiting.movement)

        // Turned round first (the stop says so), the train would face a;
        // so it still has no way to East, and waits.
        try world.addTrackPlatform(east, on: e3, from: 1_024, to: 3_072)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(world, id).position, waiting.position)
    }

    /// Once East has a platform three cars fit (1024 to 3072), the waiting
    /// service leaves on its next try, at 5: 3072 + 8192 + 3072 = 14336 in
    /// the 30 minutes its timetable gives the run (Stage W2c), so it gets
    /// there at 35, as late as it left.
    func testAServiceGoesOnceItsPathIsMadeValid() throws {
        var world = try makeStraightWorld()
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: west, arrival: minutes(0), departure: minutes(0)),
            ScheduledStop(station: east, arrival: minutes(30), departure: minutes(30)),
        ])
        try world.startTrainService(id)
        try world.advance(ticks: 5)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(0))
        try world.addTrackPlatform(east, on: e3, from: 1_024, to: 3_072)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1))
        XCTAssertEqual(try train(world, id).movement.end, 3_072)
        XCTAssertEqual(try train(world, id).times?.run, ServiceRun(start: minutes(5), length: 14_336, seconds: 1_800))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e1), offset: 5_120 + runDistance(14_336, in: 1_800, after: 60)))
        try world.advance(ticks: 28)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(1))
        XCTAssertEqual(world.clock.now, minutes(35))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e3), offset: 3_072))
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [east])
    }

    // MARK: - Repeats

    /// West to Terminus and back, every 60 minutes, three cars, each run
    /// taking the time its timetable gives it (Stage W2c):
    ///
    /// - out: 3072 + 8192 + 8192 = 19456 in 20 minutes; it dwells 42 s at
    ///   West first (Stage W2b), so it leaves 42 s late and gets to d at
    ///   20:42, as late;
    /// - turned at Terminus its head goes to its tail, 2048 along e3
    ///   backward; back: 6144 + 8192 + 7168 = 21504 from 25 to 50;
    /// - at West its head is at 1024 (e1 backward at 7168), its body to
    ///   3072; turned again at 52 its head is at 3072 facing east, 2048
    ///   short of West's berth, which the next cycle's first call reaches
    ///   at 60: where the train stood at the start.
    func testARepeatingTimetableRunsBackAndForthAndComesBackToTheSamePlace() throws {
        var world = try makeStraightWorld()
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: west, arrival: minutes(0), departure: minutes(0)),
            ScheduledStop(station: terminus, arrival: minutes(20), departure: minutes(25), reverses: true),
            ScheduledStop(station: west, arrival: minutes(50), departure: minutes(52), reverses: true),
        ], repeatingEvery: periodSeconds(60))
        let start = try train(world, id)
        try world.startTrainService(id)

        // At 19, 1098 s into the run, 17804 along: 6540 into e3.
        try world.advance(ticks: 19)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1))
        XCTAssertEqual(try train(world, id).times?.run, ServiceRun(start: GameTime(seconds: 42), length: 19_456, seconds: 1_200))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e3), offset: 5_120 + runDistance(19_456, in: 1_200, after: 1_098) - 16_384))
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [])
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1), "due at 20, arriving at 20:42")
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(world, id).times?.arrival, GameTime(seconds: 1_242))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e3), offset: 8_192))
        XCTAssertNil(try train(world, id).movement.end)
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [terminus])

        try world.advance(ticks: 4)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(1))
        // Minute 25: turned, then off along e3 backward, on time.
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(2))
        XCTAssertEqual(try train(world, id).times?.run, ServiceRun(start: minutes(25), length: 21_504, seconds: 1_500))
        XCTAssertEqual(try train(world, id).position, .onEdge(backward(e3), offset: 2_048 + runDistance(21_504, in: 1_500, after: 60)))
        XCTAssertEqual(try train(world, id).movement.edges, [e2, e1])
        XCTAssertEqual(try train(world, id).movement.end, 7_168)
        try world.advance(ticks: 24)
        XCTAssertEqual(world.clock.now, minutes(50))
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(2))
        XCTAssertEqual(try train(world, id).position, .onEdge(backward(e1), offset: 7_168))
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [west])

        // Minute 52: turned (head at 3072 facing east, standing) and off to
        // the next cycle's first call, 2048 on, due at 60.
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(0, cycle: 1))
        XCTAssertEqual(try train(world, id).times?.run, ServiceRun(start: minutes(52), length: 2_048, seconds: 480))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e1), offset: 3_072 + runDistance(2_048, in: 480, after: 60)))
        try world.advance(ticks: 6)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(0, cycle: 1))
        try world.advance(ticks: 1)
        XCTAssertEqual(world.clock.now, minutes(60))
        var back = try train(world, id)
        XCTAssertEqual(back.execution, .waitingAtStop(0, cycle: 1))
        XCTAssertEqual(back.position, start.position)
        XCTAssertEqual(back.trailEdges, start.trailEdges)
        XCTAssertEqual(back.movement, start.movement)

        // The next cycle is the same, 60 minutes later.
        try world.advance(ticks: 60)
        back = try train(world, id)
        XCTAssertEqual(back.execution, .waitingAtStop(0, cycle: 2))
        XCTAssertEqual(back.position, start.position)
        XCTAssertEqual(back.movement, start.movement)
    }

    // MARK: - Three dimensions

    // Surface Harbour, a curve, a ramp down into a tunnel, and Deep, an
    // underground station on a curve:
    //
    // - e1: (4096, 4096, 0) to (12288, 4096, 0), straight, 8192; Harbour
    //   from 2048 to 6144.
    // - e2: on to (16384, 8192, 0), the quarter curve pulled by (14336,
    //   4096) and (16384, 6144): sampled at 128ths (its control polygon is
    //   2048 + 2896 + 2048 = 6992, and 64 × 128 ≥ 6992), 6346 long.
    // - e3: down to (16384, 40960, −1024) in a tunnel, straight, 32768 long,
    //   a grade of 1 in 32; the node between e2 and e3 is a tunnel portal.
    // - e4: in the tunnel at −1024, the quarter curve to (12288, 45056)
    //   pulled by (16384, 43008) and (14336, 45056), also 6346; Deep from
    //   1024 to 4096.
    private let harbour = StationID(rawValue: 1)
    private let deep = StationID(rawValue: 2)

    private func makeDeepWorld() throws -> GameWorld {
        var world = try GameWorld(
            width: 64, height: 64, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 4_096, y: 4_096))
        let n2 = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 4_096))
        let n3 = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let n4 = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 40_960, z: -1_024))
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 45_056, z: -1_024))
        try world.buildTrackEdge(from: n1, to: n2)
        try world.buildTrackEdge(from: n2, to: n3, curve: .cubic(PlanPoint(x: 14_336, y: 4_096), PlanPoint(x: 16_384, y: 6_144)))
        try world.buildTrackEdge(from: n3, to: n4, structure: .tunnel)
        try world.buildTrackEdge(from: n4, to: n5, curve: .cubic(PlanPoint(x: 16_384, y: 43_008), PlanPoint(x: 14_336, y: 45_056)), structure: .tunnel)
        try world.buildStation(named: "Harbour", at: TestLine.centre(1, 60))
        try world.buildStation(named: "Deep", at: TestLine.centre(2, 60))
        try world.addTrackPlatform(harbour, on: e1, from: 2_048, to: 6_144)
        try world.addTrackPlatform(deep, on: e4, from: 1_024, to: 4_096)
        return world
    }

    /// Three cars, Harbour to Deep and back:
    ///
    /// - out: 2048 + 6346 + 32768 + 4096 = 45258, in the 25 minutes its
    ///   timetable gives the run (Stage W2c), from 0:42 (it dwells at
    ///   Harbour first, Stage W2b) to 25:42; six minutes in, 318 s along
    ///   its curve, it has come 9583, so the head is 9583 − 8394 = 1189
    ///   into the tunnel and the tail still on the curve;
    /// - at Deep the body is 2048...4096 of 1024...4096; turned round, the
    ///   head is where the tail was (6346 − 4096 + 2048 = 4298 along e4
    ///   backward: 2048 from e4's start), still on the platform;
    /// - back: 2048 + 32768 + 6346 + 6144 = 47306; held up at Deep until 34,
    ///   it sets off again as fast as it can, in 76 s (√(2 × 47306 × 0.06)
    ///   = 75.3), and is home at 35:16;
    /// - at Harbour the head is at 2048 (e1 backward at 6144), and turned at
    ///   its last stop, at 4096 facing east, standing.
    func testALongTrainRunsIntoATunnelToAnUndergroundCurvedPlatformAndBack() throws {
        var world = try makeDeepWorld()
        XCTAssertEqual(world.trackEdge(e2)?.length, 6_346)
        XCTAssertEqual(world.trackEdge(e3)?.length, 32_768)
        XCTAssertEqual(world.trackEdge(e4)?.length, 6_346)
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 6_144), rate: 2_048, in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: harbour, arrival: minutes(0), departure: minutes(0)),
            ScheduledStop(station: deep, arrival: minutes(25), departure: minutes(30), reverses: true),
            ScheduledStop(station: harbour, arrival: minutes(60), departure: minutes(60), reverses: true),
        ])
        XCTAssertEqual(
            world.path(from: .onEdge(forward(e1), offset: 6_144), toStation: deep, length: 2_048),
            TrainPath(traversals: [forward(e2), forward(e3), forward(e4)], end: 4_096, distance: 45_258)
        )
        try world.startTrainService(id)

        try world.advance(ticks: 6)
        XCTAssertEqual(try train(world, id).times?.run, ServiceRun(start: GameTime(seconds: 42), length: 45_258, seconds: 1_500))
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e3), offset: runDistance(45_258, in: 1_500, after: 318) - 8_394))
        XCTAssertEqual(try train(world, id).trailEdges, [e2], "through the portal: the tail is still outside")
        try world.advance(ticks: 4)
        // 558 s along: 16829 on, 8435 into the ramp: −1024 × 8435 / 32768 =
        // −263.6, rounded to −264.
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e3), offset: runDistance(45_258, in: 1_500, after: 558) - 8_394))
        let inTunnel = try XCTUnwrap(world.location(of: try train(world, id).position!))
        XCTAssertEqual(inTunnel.position.z, -264)

        try world.advance(ticks: 15)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1), "due at 25, arriving at 25:42")
        try world.advance(ticks: 1)
        var there = try train(world, id)
        XCTAssertEqual(world.clock.now, minutes(26))
        XCTAssertEqual(there.times?.arrival, GameTime(seconds: 1_542))
        XCTAssertEqual(there.execution, .waitingAtStop(1))
        XCTAssertEqual(there.position, .onEdge(forward(e4), offset: 4_096))
        XCTAssertEqual(there.trailEdges, [])
        XCTAssertEqual(world.stationsStoppedAt(by: id), [deep])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [deep])

        // Hold it (rate 0) to see where it turns: at 30 it turns round and
        // gets its path home, and stays; held up, it has no run.
        try world.setTrainMovementRate(id, to: 0)
        try world.advance(ticks: 8)
        there = try train(world, id)
        XCTAssertEqual(there.execution, .travellingToStop(2))
        XCTAssertEqual(there.times?.departure, minutes(30))
        XCTAssertNil(there.times?.run)
        XCTAssertEqual(there.position, .onEdge(backward(e4), offset: 4_298))
        XCTAssertEqual(world.trackPlatformsAlongWholeTrain(id).map(\.station), [deep], "the tail became the head on the same platform")
        XCTAssertEqual(world.pathAhead(of: id), [backward(e3), backward(e2), backward(e1)])
        XCTAssertEqual(there.movement.end, 6_144)
        XCTAssertEqual(world.path(from: there.position!, toStation: harbour, length: 2_048)?.distance, 47_306)

        try world.setTrainMovementRate(id, to: 2_048)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).times?.run, ServiceRun(start: minutes(34), length: 47_306, seconds: 76))
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(2))
        try world.advance(ticks: 1)
        let home = try train(world, id)
        XCTAssertEqual(world.clock.now, minutes(36))
        XCTAssertEqual(home.times?.arrival, GameTime(seconds: 34 * 60 + 76))
        XCTAssertEqual(home.execution, .waitingAtStop(2))
        XCTAssertEqual(home.position, .onEdge(backward(e1), offset: 6_144))
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [harbour])

        // Its last stop turns it round when it leaves at 60: head at 4096
        // facing east, standing.
        try world.advance(ticks: 24)
        XCTAssertEqual(try train(world, id).execution, .waitingAtStop(2))
        try world.advance(ticks: 1)
        let done = try train(world, id)
        XCTAssertNil(done.execution)
        XCTAssertEqual(done.position, .onEdge(forward(e1), offset: 4_096))
        XCTAssertEqual(done.movement.end, 4_096)
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [harbour])
        try world.advance(ticks: 5)
        XCTAssertEqual(try train(world, id).position, done.position)
    }

    /// A platform on a viaduct at 512 is a platform like any other: a train
    /// of one car at 2048 a minute from the edge's start stops at its far
    /// end each way.
    func testAnElevatedPlatformServesTrainsBothWays() throws {
        var world = try GameWorld(width: 12, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024, z: 512))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 1_024, z: 512))
        try world.buildTrackEdge(from: a, to: b, structure: .elevated)
        let high = try world.buildStation(named: "High", at: TestLine.centre(1, 3)).id
        try world.addTrackPlatform(high, on: e1, from: 2_048, to: 6_144)
        XCTAssertEqual(world.railwaySnapshot().platforms.map(\.height), [512])

        let id = try world.purchaseTrain(named: "Up").id
        try world.placeTrain(id, at: .onEdge(forward(e1), offset: 0))
        let path = try XCTUnwrap(world.path(from: .onEdge(forward(e1), offset: 0), toStation: high))
        XCTAssertEqual(path, TrainPath(traversals: [], end: 6_144, distance: 6_144))
        try world.setTrainContinuation(id, along: path.traversals, stoppingAt: path.end)
        try world.setTrainMovementRate(id, to: 2_048)
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e1), offset: 6_144))
        XCTAssertEqual(world.stationsStoppedAt(by: id), [high])

        // The other way, from b: its berth is the platform's start, 8192 −
        // 2048 = 6144 along e1 backward.
        let other = try world.purchaseTrain(named: "Down").id
        try world.placeTrain(other, at: .onEdge(backward(e1), offset: 0))
        XCTAssertEqual(world.path(from: .onEdge(backward(e1), offset: 0), toStation: high), TrainPath(traversals: [], end: 6_144, distance: 6_144))
    }

    // MARK: - Lines

    /// Line Main, West to Terminus, as a train of one car drives it from
    /// West's berth going east (going west from there there is no way):
    /// out 19456, 49 s (√(2 × 19456 × 0.06) = 48.3); turned at d its head
    /// is at the start of e3 backward; back 8192 + 8192 + 7168 = 23552, 54 s
    /// (53.2); with two minutes at each end, 343 s, planned as 6 minutes.
    func testALineJourneyOnTheNetworkIsItsExactDistances() throws {
        var world = try makeStraightWorld()
        try world.createLine(named: "Main", stops: [west, terminus])
        let journey = try XCTUnwrap(world.lineJourney(main))
        XCTAssertEqual(journey.start, .onEdge(forward(e1), offset: 5_120))
        XCTAssertEqual(journey.legs, [
            LineLeg(from: 0, to: 1, path: TrainPath(traversals: [forward(e2), forward(e3)], end: nil, distance: 19_456), seconds: 49),
            LineLeg(from: 1, to: 0, path: TrainPath(traversals: [backward(e2), backward(e1)], end: 7_168, distance: 23_552), seconds: 54),
        ])
        XCTAssertEqual(journey.legs.map(\.route), [[], []], "no grid tiles")
        XCTAssertEqual(journey.roundTripSeconds, 343)
        XCTAssertEqual(journey.roundTripMinutes, 6)
        XCTAssertEqual(world.lineMaximumTrains(main), 3)

        try world.setLineTrainsInService(main, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        XCTAssertEqual(world.lineTrainsInService(main, at: .low), 2)
        XCTAssertEqual(world.lineHeadway(main, at: .low), 3)
        try world.setLineTargetHeadways(main, to: TargetHeadways(low: 60))
        XCTAssertEqual(world.lineTrainsInService(main, at: .low), 1)
        XCTAssertEqual(world.lineHeadway(main, at: .low), 60)

        // The metro game's trains (3.96 and 4.68 km/h a second: 1 ÷ a + 1 ÷
        // b = 0.026224 s² a unit) never reach 80 km/h (1422 units a
        // second) here: √(2 × 19456 × 0.026224) = 31.9 and √(2 × 23552 ×
        // 0.026224) = 35.1, so 32 and 36 s; 308 s in all, still 6 minutes.
        try world.setLinePerformance(main, to: .metro)
        XCTAssertEqual(world.lineJourney(main)?.legs.map(\.seconds), [32, 36])
        XCTAssertEqual(world.lineJourney(main)?.roundTripSeconds, 308)
        XCTAssertEqual(world.lineJourney(main)?.roundTripMinutes, 6)
    }

    /// Two trains of three cars on Main, two a level, all day: 3 minutes
    /// apart (the line's round trip, 6 minutes, over 2). Each trip's legs
    /// take the least seconds for the train's own distances (Stage W2c).
    ///
    /// - The first, at West's berth, goes at 0 and leaves at 0:42: out 19456
    ///   in 49 s, at Terminus 1:31–3:31; back from the turn at d (head 2048
    ///   along e3 backward) 6144 + 8192 + 7168 = 21504 in 51 s (50.8), at
    ///   West at 4:22, where its service ends at 5:04.
    /// - The second, standing at 4096 on West's platform, goes at 3: out
    ///   4096 + 8192 + 8192 = 20480 in 50 s (49.6); back 51 s.
    /// - Back at West the first turned round (head at 3072 facing east) and
    ///   is ready; it goes again when the headway has passed, at 6: out
    ///   5120 + 16384 = 21504 in 51 s, and 51 s back.
    func testALineDispatchesTrainsOnTheNetworkAndSendsThemAgain() throws {
        var world = try makeStraightWorld()
        try world.createLine(named: "Main", stops: [west, terminus])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        let first = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        let second = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 4_096), in: &world)
        try world.assignTrain(first, to: main)
        try world.assignTrain(second, to: main)

        // In seconds: sent out at T, a train leaves West 42 s later (Stage
        // W2b); the first trip then takes 49 s out, 2 minutes at Terminus and
        // 51 s back.
        func times(_ id: TrainID) throws -> [[Int64]] {
            try train(world, id).timetable.map { [$0.station.rawValue == 1 ? 1 : 4, $0.arrival.seconds, $0.departure.seconds] }
        }
        try world.advance(ticks: 1)
        XCTAssertEqual(try times(first), [[1, 0, 42], [4, 91, 211], [1, 262, 262]])
        XCTAssertEqual(try train(world, first).timetable.map(\.reverses), [false, true, true])
        XCTAssertEqual(world.line(id: main)?.lastDispatch, minutes(0))
        XCTAssertNil(try train(world, second).execution)

        try world.advance(ticks: 3)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, minutes(3))
        // From 1024 further back: 50 s out.
        XCTAssertEqual(try times(second), [[1, 180, 222], [4, 272, 392], [1, 443, 443]])

        try world.advance(ticks: 2)
        // Minute 6: the first is back (4:22), has dwelt there and turned
        // round (5:04), waiting.
        let back = try train(world, first)
        XCTAssertNil(back.execution)
        XCTAssertEqual(back.position, .onEdge(forward(e1), offset: 3_072))
        XCTAssertEqual(back.movement.end, 3_072)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [west])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, minutes(6))
        // From where it was turned round: 51 s each way.
        XCTAssertEqual(try times(first), [[1, 360, 402], [4, 453, 573], [1, 624, 624]])
    }

    /// From 06:40, low (one train, every 6 minutes) until 07:00, then peak
    /// (two, every 3): the first goes at 400, 406, 412 and 418, back each
    /// time within 6 minutes (a trip of 5:04 or, from where it turned round,
    /// 5:06), and the second when 3 minutes have passed at the peak, at 421.
    func testTheLevelDecidesHowManyNetworkTrainsGo() throws {
        var world = try makeStraightWorld(minute: 400)
        try world.createLine(named: "Main", stops: [west, terminus])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 2, offPeak: 1, low: 1))
        let first = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        let second = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 4_096), in: &world)
        try world.assignTrain(first, to: main)
        try world.assignTrain(second, to: main)
        try world.advance(ticks: 20)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, minutes(418))
        XCTAssertEqual(try train(world, first).timetable.first?.departure, GameTime(seconds: 418 * 60 + 42))
        XCTAssertNil(try train(world, second).execution)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, minutes(421))
        XCTAssertEqual(try train(world, second).timetable.first?.departure, GameTime(seconds: 421 * 60 + 42))
    }

    /// A line never sends a train out to a platform it does not fit: four
    /// cars do not fit Terminus (2048), so the train at West is never
    /// ready, though the line itself can be driven.
    func testALineDoesNotSendATrainToAPlatformTooShortForIt() throws {
        var world = try makeStraightWorld()
        try world.createLine(named: "Main", stops: [west, terminus])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let long = try stoppedTrain(4, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.assignTrain(long, to: main)
        XCTAssertNotNil(world.lineJourney(main))
        try world.advance(ticks: 30)
        XCTAssertNil(try train(world, long).execution)
        XCTAssertNil(world.line(id: main)?.lastDispatch)
        XCTAssertEqual(try train(world, long).position, .onEdge(forward(e1), offset: 5_120))
    }

    // MARK: - Patterns

    /// Line Main calls at West, Mid, East and Terminus. For a train of one
    /// car from West's berth, in the least seconds for each leg (Stage W2c,
    /// √(2 × length × 0.06) rounded up):
    ///
    /// - all stops: 8120 (32), 3144 + 5120 = 8264 (32), 3072 (20); turned
    ///   at d, 4096 to East's other berth (23), 4096 + 5192 = 9288 (34),
    ///   3000 + 7168 = 10168 (35): 176 s of travel, 2 minutes at each end
    ///   and 1 at each of four calls between: 656 s, planned as 11 minutes;
    /// - short working Mid–East: 8264 (32); turned at East (head at 3072
    ///   along e3 backward), 5120 + 5192 = 10312 (36); 308 s, 6 minutes;
    /// - express West–Terminus: as the two-stop line, 49 + 54 + 240 = 343
    ///   s, 6 minutes, passing Mid and East without calling.
    func testShortWorkingsAndExpressesRunOnTheNetwork() throws {
        var world = try makeStraightWorld()
        try world.createLine(named: "Main", stops: [west, mid, east, terminus])
        let short = try world.addLinePattern(main, calling: [1, 2])
        let express = try world.addLinePattern(main, calling: [0, 3])
        XCTAssertEqual(world.lineJourney(main)?.legs.map(\.seconds), [32, 32, 20, 23, 34, 35])
        XCTAssertEqual(world.lineJourney(main)?.roundTripSeconds, 656)
        XCTAssertEqual(world.lineJourney(main)?.roundTripMinutes, 11)
        let shortJourney = try XCTUnwrap(world.lineJourney(main, pattern: short))
        XCTAssertEqual(shortJourney.start, .onEdge(forward(e2), offset: 5_048))
        XCTAssertEqual(shortJourney.legs.map(\.path.distance), [8_264, 10_312])
        XCTAssertEqual(shortJourney.legs.map(\.seconds), [32, 36])
        XCTAssertEqual(shortJourney.roundTripMinutes, 6)
        let expressJourney = try XCTUnwrap(world.lineJourney(main, pattern: express))
        XCTAssertEqual(expressJourney.legs.map { [$0.from, $0.to] }, [[0, 3], [3, 0]])
        XCTAssertEqual(expressJourney.legs.map(\.seconds), [49, 54])
        XCTAssertEqual(expressJourney.roundTripMinutes, 6)

        // Each sends a train of one car out from its own first call.
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: short)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: express)
        let shuttle = try stoppedTrain(1, at: .onEdge(forward(e2), offset: 5_048), in: &world)
        let fast = try stoppedTrain(1, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.assignTrain(shuttle, to: main, pattern: short)
        try world.assignTrain(fast, to: main, pattern: express)
        // Each leaves its first call 42 s after it is sent out (Stage W2b).
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, shuttle).timetable.map(\.station), [mid, east, mid])
        XCTAssertEqual(try train(world, shuttle).timetable.map(\.arrival.seconds), [0, 42 + 32, 42 + 32 + 120 + 36] as [Int64])
        XCTAssertEqual(try train(world, fast).timetable.map(\.station), [west, terminus, west])
        XCTAssertEqual(try train(world, fast).timetable.map(\.arrival.seconds), [0, 42 + 49, 42 + 49 + 120 + 54] as [Int64])
        // 22 s after leaving, at 1:04, the express is on Mid's platform
        // (6453 along its 49 s curve from West's berth: 3072 to b, 3381 into
        // e2), not calling there: still travelling to Terminus.
        world.setSpeed(.x10)
        try world.advance(ticks: 4)
        XCTAssertEqual(world.clock.now, GameTime(seconds: 64))
        XCTAssertEqual(try train(world, fast).position, .onEdge(forward(e2), offset: runDistance(19_456, in: 49, after: 22) - 3_072))
        XCTAssertEqual(try train(world, fast).execution, .travellingToStop(1))
        XCTAssertEqual(world.stationsStoppedAt(by: fast), [])
    }

    // MARK: - Platforms a service needs

    /// A platform where a service waits, or on whose edge a service's path
    /// ends, cannot be removed until the service stops; others can.
    func testAPlatformAServiceNeedsCannotBeRemoved() throws {
        var world = try makeStraightWorld()
        let id = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 5_120), in: &world)
        try world.setTrainTimetable(id, to: [
            ScheduledStop(station: west, arrival: minutes(0), departure: minutes(5)),
            ScheduledStop(station: mid, arrival: minutes(20), departure: minutes(20)),
        ])
        try world.startTrainService(id)
        XCTAssertThrowsGameError(try world.removeTrackPlatform(west, on: e1, from: 1_024), .trainServiceActive(id))
        try world.removeTrackPlatform(east, on: e3, from: 4_096)
        try world.advance(ticks: 6)
        XCTAssertEqual(try train(world, id).execution, .travellingToStop(1))
        XCTAssertThrowsGameError(try world.removeTrackPlatform(mid, on: e2, from: 3_000), .trainServiceActive(id))
        try world.removeTrackPlatform(west, on: e1, from: 1_024)
        try world.stopTrainService(id)
        try world.removeTrackPlatform(mid, on: e2, from: 3_000)
        // The train carries on to where its path ends, a station no more.
        try world.advance(ticks: 10)
        XCTAssertEqual(try train(world, id).position, .onEdge(forward(e2), offset: 5_048))
        XCTAssertEqual(world.stationsStoppedAt(by: id), [])
    }

    // MARK: - Saves

    /// Network services save and load: a path's end is written only when
    /// there is one; a bad end, or a service that does not fit where its
    /// train is, is refused.
    func testNetworkServicesSaveAndLoad() throws {
        var world = try makeDeepWorld()
        let running = try stoppedTrain(3, at: .onEdge(forward(e1), offset: 6_144), rate: 2_048, in: &world)
        let waiting = try stoppedTrain(1, at: .onEdge(forward(e4), offset: 4_096), rate: 2_048, in: &world)
        try world.setTrainTimetable(running, to: [
            ScheduledStop(station: harbour, arrival: minutes(0), departure: minutes(0)),
            ScheduledStop(station: deep, arrival: minutes(25), departure: minutes(30)),
        ])
        try world.setTrainTimetable(waiting, to: [
            ScheduledStop(station: deep, arrival: minutes(0), departure: minutes(50)),
            ScheduledStop(station: harbour, arrival: minutes(80), departure: minutes(80), reverses: true),
        ])
        try world.startTrainService(running)
        try world.startTrainService(waiting)
        try world.advance(ticks: 7)
        XCTAssertEqual(try train(world, running).execution, .travellingToStop(1))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let saved = try XCTUnwrap(json["trains"] as? [[String: Any]])
        // Stage W2c: it left at 0:42 on a run of 45258 in 1500 s, and has
        // come 11394 along it by 7 (378 s): into e3 (e2 and e3 entered).
        let movement = try XCTUnwrap(saved[0]["movement"] as? [String: Any])
        XCTAssertEqual(movement["end"] as? Int, 4_096)
        XCTAssertEqual(movement["edges"] as? [Int], [2, 3, 4])
        XCTAssertEqual(movement["cursor"] as? Int, 2)
        XCTAssertEqual((saved[1]["movement"] as? [String: Any])?["end"] as? Int, 4_096)
        let times = try XCTUnwrap(saved[0]["times"] as? [String: Any])
        XCTAssertEqual(times["run"] as? [String: Int], ["start": 42, "length": 45_258, "seconds": 1_500])
        XCTAssertNil((saved[1]["times"] as? [String: Any])?["run"], "a waiting train has no run")
        func runChange(_ run: [String: Any]) -> (inout [String: Any]) -> Void {
            { train in
                var times = train["times"] as! [String: Any]
                times["run"] = run
                train["times"] = times
            }
        }

        func mutated(_ index: Int, _ change: (inout [String: Any]) -> Void) throws -> Data {
            var copy = json
            var trains = saved
            change(&trains[index])
            copy["trains"] = trains
            return try JSONSerialization.data(withJSONObject: copy)
        }
        func movementChange(_ key: String, _ value: Any) -> (inout [String: Any]) -> Void {
            { train in
                var movement = train["movement"] as! [String: Any]
                movement[key] = value
                train["movement"] = movement
            }
        }
        let refused: [(String, Data)] = try [
            ("null end", mutated(0, movementChange("end", NSNull()))),
            ("negative end", mutated(1, movementChange("end", -1))),
            ("end 0 with edges left", mutated(0, movementChange("end", 0))),
            ("end at the end of the last edge", mutated(0, movementChange("end", 6_346))),
            ("end behind the head", mutated(1, movementChange("end", 4_000))),
            ("waiting short of its path's end", mutated(1, movementChange("end", 5_000))),
            ("travelling to no berth", mutated(0, movementChange("end", 4_000))),
            ("travelling on a spent path", mutated(1, { train in
                train["execution"] = ["phase": "travelling", "stop": 1]
                train["times"] = ["arrival": 0, "departure": 0]
            })),
            // Stage W2c: a run its train's performance builds no curve for,
            // one set off before the train left, and one while it waits.
            ("a run too fast for the train", mutated(0, runChange(["start": 42, "length": 45_258, "seconds": 1]))),
            ("a run before leaving", mutated(0, runChange(["start": 41, "length": 45_258, "seconds": 1_500]))),
            ("a run of no length", mutated(0, runChange(["start": 42, "length": 0, "seconds": 1_500]))),
            ("a run while waiting", mutated(1, runChange(["start": 0, "length": 1_024, "seconds": 60]))),
        ]
        for (name, bytes) in refused {
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: bytes), name)
        }
        // A save without "end" (as every save before Stage S5) runs the
        // path to the end of its last edge.
        let old = try mutated(0, { train in
            var movement = train["movement"] as! [String: Any]
            movement["end"] = nil
            train["movement"] = movement
            train["execution"] = nil
            train["times"] = nil
        })
        let loaded = try JSONDecoder().decode(GameWorld.self, from: old)
        XCTAssertNil(loaded.train(id: running)?.movement.end)
    }
}
