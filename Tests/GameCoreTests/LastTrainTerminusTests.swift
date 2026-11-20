@testable import GameCore
import XCTest

/// LAST-TRAIN-TERMINUS (decision 571, continued again, later): a line's
/// last service bound for a terminus whose nearest berth a train of the
/// same line stands on for the night takes a free berth of the terminus,
/// as it does past a spare of a line without runs. On the Sanying Line
/// under a new game's rules, the depot full, the trains that had ended
/// their day stood on the berths each night's last services were bound
/// for, and those services stood at the station before from 00:26 to
/// 06:01, though each terminus had two berths free.
///
///   A  W1 ════ n6 ══════════════════════════════ n7 ════ E1
///               ╲ x7                          x12 ╲
///   B  W2 ════════ n5 ════════════════════════════ n8 ══ E2
///
/// ``CounterflowDeadlockTests``' track. Y, the line's train, stands at
/// E2 without a service, its next run (E → W) hours away. X, a service at
/// W1 due out at 00:01, is bound for E, whose nearest berth for it is E2;
/// E1 is free, but the way to it runs against the planned way. Simple
/// rules (no block sections), traffic control on, as a new game starts.
final class LastTrainTerminusTests: XCTestCase {
    /// `yLeavesAt`: when the line's run E → W, Y's next, leaves (seconds
    /// after midnight). `late`: the minutes that pass before X's service
    /// starts, X then that much less a minute behind its timetable.
    private func makeWorld(yLeavesAt: Int64, late: Int = 0) throws -> (world: GameWorld, x: TrainID, y: TrainID, w: StationID, e: StationID, aEast: TrackEdgeID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 229_376, height: 65_536), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let w1 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000, y: 40_000))
        let n6 = try world.buildTrackNode(at: WorldCoordinate(x: 26_528, y: 40_000))
        let n7 = try world.buildTrackNode(at: WorldCoordinate(x: 202_272, y: 40_000))
        let e1 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000, y: 40_000))
        let w2 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000, y: 39_680))
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 29_728, y: 39_680))
        let n8 = try world.buildTrackNode(at: WorldCoordinate(x: 205_472, y: 39_680))
        let e2 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000, y: 39_680))
        let aWest = try world.buildTrackEdge(from: w1, to: n6)
        let aEast = try world.buildTrackEdge(from: n7, to: e1)
        let bWest = try world.buildTrackEdge(from: w2, to: n5)
        let bEast = try world.buildTrackEdge(from: n8, to: e2)
        _ = try world.buildTrackEdge(from: n5, to: n6, curve: .cubic(PlanPoint(x: 28_128, y: 39_680), PlanPoint(x: 28_128, y: 40_000)))
        _ = try world.buildTrackEdge(from: n7, to: n8, curve: .cubic(PlanPoint(x: 203_872, y: 40_000), PlanPoint(x: 203_872, y: 39_680)))
        _ = try world.buildTrackEdge(from: n6, to: n7)
        _ = try world.buildTrackEdge(from: n5, to: n8)

        let w = try world.buildStation(named: "W", at: PlanPoint(x: 22_560, y: 42_048)).id
        try world.addTrackPlatform(w, on: aWest, from: 700, to: 5_120)
        try world.addTrackPlatform(w, on: bWest, from: 1, to: 5_120)
        let e = try world.buildStation(named: "E", at: PlanPoint(x: 209_440, y: 42_048)).id
        try world.addTrackPlatform(e, on: bEast, from: 1_408, to: 5_828)
        try world.addTrackPlatform(e, on: aEast, from: 4_608, to: 9_727)

        let line = try world.createLine(named: "L", stops: [w, e]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 1, to: 0, times: [LineRunTime(arrival: yLeavesAt, departure: yLeavesAt),
                                            LineRunTime(arrival: yLeavesAt + 1_140, departure: yLeavesAt + 1_140)]),
        ])
        let x = try stand(&world, at: TrackTraversal(edge: aWest, direction: .forward), offset: 5_120)
        let y = try stand(&world, at: TrackTraversal(edge: bEast, direction: .backward), offset: 6_528 - 1_408)
        try world.assignTrain(y, to: line)
        try world.setTrainTimetable(x, to: [
            ScheduledStop(station: w, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: e, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
        ])
        try world.setTrafficControl(true)
        try world.advance(ticks: late)
        try world.startTrainService(x)
        return (world, x, y, w, e, aEast)
    }

    private func stand(_ world: inout GameWorld, at traversal: TrackTraversal, offset: Int64) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(id, to: 4_096)
        return id
    }

    /// Y's next run is at 05:00: X comes in to E1 within the half hour,
    /// and no train stands deadlocked.
    func testTheLastServiceTakesAFreeBerthPastATrainStandingForTheNight() throws {
        var (world, x, y, _, e, aEast) = try makeWorld(yLeavesAt: 5 * 3_600)
        XCTAssertFalse(world.blockSections)
        var arrived = false
        for _ in 0..<30 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.deadlockedTrains(), [], "at \(world.clock.now.minuteOfDay)")
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
            if world.stationsStoppedAt(by: x) == [e] { arrived = true }
        }
        XCTAssertTrue(arrived, "X reached E; it waits for \(String(describing: world.trainHoldingRoute(of: x)))")
        guard case .onEdge(let standing, _)? = world.train(id: x)?.position else { return XCTFail("X placed") }
        XCTAssertEqual(standing.edge, aEast, "X stands at E1")
        XCTAssertEqual(world.stationsStoppedAt(by: y), [e], "Y still stands at E2")
    }

    /// Y's next run leaves at 00:15, before X is due at E (00:20): Y may
    /// take it first, so until then X waits for E2 as before and does
    /// not go for E1. (Once Y is due too, the two wait for each other's
    /// berths, which decision 571 continued again already resolves.)
    func testAServiceWaitsForATrainWhoseRunLeavesBeforeItIsDue() throws {
        var (world, x, _, w, _, aEast) = try makeWorld(yLeavesAt: 15 * 60)
        while world.clock.now < GameTime(minutes: 14) {
            try world.advance(ticks: 1)
            XCTAssertFalse(world.train(id: x)?.movement.edges.contains(aEast) ?? false, "X does not go for E1 at \(world.clock.now.minuteOfDay)")
            XCTAssertEqual(world.stationsStoppedAt(by: x), [w], "X waits at W at \(world.clock.now.minuteOfDay)")
        }
    }

    /// EAL-LMC-PEAK-GAP: X leaves W five minutes late, so it is due at
    /// E at 00:25, not at the 00:20 of its timetable, and Y's next run
    /// leaves at 00:23: Y is not standing there for the night, it will
    /// have gone when X comes. X waits for E2 and does not go for E1
    /// against the planned way. (On the East Rail Line's Lok Ma Chau
    /// branch, which has no depot, a train five minutes late went round
    /// one four minutes from its run each morning, and the evening peak's
    /// longest gap went from 19 to 21 minutes.)
    func testALateServiceWaitsForATrainWhoseRunLeavesBeforeItCanCome() throws {
        var (world, x, _, w, _, aEast) = try makeWorld(yLeavesAt: 23 * 60, late: 5)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 5))
        while world.clock.now < GameTime(minutes: 22) {
            try world.advance(ticks: 1)
            XCTAssertFalse(world.train(id: x)?.movement.edges.contains(aEast) ?? false, "X does not go for E1 at \(world.clock.now.minuteOfDay)")
            XCTAssertEqual(world.stationsStoppedAt(by: x), [w], "X waits at W at \(world.clock.now.minuteOfDay)")
        }
    }

    /// As late, past a train whose run leaves after that (00:40), X takes
    /// the free berth as it does on time.
    func testALateServiceTakesAFreeBerthPastATrainWhoseRunLeavesAfterItComes() throws {
        var (world, x, _, _, e, aEast) = try makeWorld(yLeavesAt: 40 * 60, late: 5)
        var arrived = false
        for _ in 0..<30 {
            try world.advance(ticks: 1)
            if world.stationsStoppedAt(by: x) == [e] { arrived = true }
        }
        XCTAssertTrue(arrived, "X reached E; it waits for \(String(describing: world.trainHoldingRoute(of: x)))")
        guard case .onEdge(let standing, _)? = world.train(id: x)?.position else { return XCTFail("X placed") }
        XCTAssertEqual(standing.edge, aEast, "X stands at E1")
    }

    /// The rule for any terminus without a depot, whatever the map: for
    /// X leaving 0 to 12 minutes late, a train whose run leaves before X
    /// can come is never taken for one standing for the night (X waits
    /// for its berth), and one whose run leaves well after is passed.
    func testHoweverLateATrainAboutToLeaveIsNotTakenForOneStandingForTheNight() throws {
        for late in [0, 1, 2, 3, 5, 8, 12] {
            // X is `late` - 1 minutes behind when its service starts, so
            // it is due at E at 00:19 + late or later.
            let soon = Int64(18 + late)
            var (world, x, _, w, _, aEast) = try makeWorld(yLeavesAt: soon * 60, late: late)
            while world.clock.now < GameTime(minutes: soon - 1) {
                try world.advance(ticks: 1)
                XCTAssertFalse(world.train(id: x)?.movement.edges.contains(aEast) ?? false, "\(late) min late: X does not go for E1 at \(world.clock.now.minuteOfDay)")
                XCTAssertEqual(world.stationsStoppedAt(by: x), [w], "\(late) min late: X waits at W at \(world.clock.now.minuteOfDay)")
            }

            var (later, x2, _, _, e, _) = try makeWorld(yLeavesAt: Int64(60 + late) * 60, late: late)
            var arrived = false
            for _ in 0..<30 {
                try later.advance(ticks: 1)
                if later.stationsStoppedAt(by: x2) == [e] { arrived = true }
            }
            XCTAssertTrue(arrived, "\(late) min late: X takes the free berth past a train whose run is an hour off")
        }
    }
}
