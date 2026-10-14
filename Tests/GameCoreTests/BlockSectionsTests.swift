import Foundation
@testable import GameCore
import XCTest

/// Block sections (ARCHITECTURE decision 212): with the world's
/// `blockSections` on, a following train's authority ends at a block's
/// boundary, a train following others leads another, and a following train
/// waits for nothing it has not taken. Off, as before.
///
/// Expected values are worked out by hand from the rules and written out.
final class BlockSectionsTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    // MARK: - The long line
    //
    //   n1 ──e1── n2 ──e2── n3 ──e3── n4     y = 1024
    //
    // Each edge is 200,000 long: blocks of 96,000 bound it at 0, 96,000,
    // 192,000 and 200,000 from its `from` node. A's platform is at the
    // start of e1, B's at the end of e3.

    private static let edgeLength: Int64 = 200_000

    private func makeWorld() throws -> (world: GameWorld, a: StationID, b: StationID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 3 * Self.edgeLength + 4_096, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let nodes = try (0..<4).map { try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Int64($0) * Self.edgeLength, y: 1_024)) }
        for (from, to) in zip(nodes, nodes.dropFirst()) {
            try world.buildTrackEdge(from: from, to: to)
        }
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 1_024 + 8_192, y: 2_048)).id
        try world.addTrackPlatform(a, on: .edge(1), from: 1_024, to: 20_480)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 1_024 + 3 * Self.edgeLength - 8_192, y: 2_048)).id
        try world.addTrackPlatform(b, on: .edge(3), from: Self.edgeLength - 20_480, to: Self.edgeLength - 1_024)
        return (world, a, b)
    }

    // MARK: - Boundaries

    /// The boundaries along a route are each edge's ends and every 96,000
    /// from its `from` node, whichever way the edge is travelled.
    func testBoundariesAreEachEdgesEndsAndEveryBlockFromItsStart() throws {
        var (world, _, _) = try makeWorld()
        world.setBlockSections(true)
        // Head at 50,000 along e1, running east to 150,000 along e3.
        let east = try world.purchaseTrain(named: "E").id
        try world.placeTrain(east, at: .onEdge(forward(1), offset: 50_000))
        try world.setTrainContinuation(east, along: [forward(2), forward(3)], stoppingAt: 150_000)
        let e = world.authorityEnvelopes(of: try XCTUnwrap(world.train(id: east)))
        XCTAssertEqual(e.length, 150_000 + 200_000 + 150_000)
        // From the head: e1's 96,000 and 192,000 are 46,000 and 142,000
        // on; e1 ends 150,000 on; e2's 96,000 and 192,000 are 246,000 and
        // 342,000 on; e2 ends 350,000 on; e3's 96,000 is 446,000 on; the
        // route ends 500,000 on.
        let boundaries: [Int64] = [46_000, 142_000, 150_000, 246_000, 342_000, 350_000, 446_000]
        XCTAssertEqual(world.blockBoundary(e, atOrBefore: 0), 0)
        XCTAssertEqual(world.blockBoundary(e, atOrBefore: 45_999), 0)
        for (boundary, next) in zip(boundaries, boundaries.dropFirst()) {
            XCTAssertEqual(world.blockBoundary(e, atOrBefore: boundary), boundary)
            XCTAssertEqual(world.blockBoundary(e, atOrBefore: next - 1), boundary)
            XCTAssertEqual(world.blockBoundary(e, after: boundary), next)
            XCTAssertEqual(world.blockBoundary(e, after: next - 1), next)
        }
        XCTAssertEqual(world.blockBoundary(e, after: 0), 46_000)
        XCTAssertEqual(world.blockBoundary(e, atOrBefore: 499_999), 446_000)
        XCTAssertEqual(world.blockBoundary(e, atOrBefore: 600_000), 446_000)
        XCTAssertNil(world.blockBoundary(e, after: 446_000), "none before the route ends")

        // Head at 150,000 along e3, running west to 50,000 along e1: the
        // same boundaries seen the other way. e3's 96,000 is 54,000 on; e3
        // ends 150,000 on; e2's 192,000 and 96,000 are 158,000 and 254,000
        // on; e2 ends 350,000 on; e1's 192,000 and 96,000 are 358,000 and
        // 454,000 on; the route ends 500,000 on.
        let west = try world.purchaseTrain(named: "W").id
        try world.placeTrain(west, at: .onEdge(backward(3), offset: 50_000))
        try world.setTrainContinuation(west, along: [backward(2), backward(1)], stoppingAt: 150_000)
        let w = world.authorityEnvelopes(of: try XCTUnwrap(world.train(id: west)))
        let back: [Int64] = [54_000, 150_000, 158_000, 254_000, 350_000, 358_000, 454_000]
        for (boundary, next) in zip(back, back.dropFirst()) {
            XCTAssertEqual(world.blockBoundary(w, atOrBefore: boundary), boundary)
            XCTAssertEqual(world.blockBoundary(w, atOrBefore: next - 1), boundary)
            XCTAssertEqual(world.blockBoundary(w, after: boundary), next)
        }
        XCTAssertEqual(world.blockBoundary(w, atOrBefore: 53_999), 0)
        XCTAssertNil(world.blockBoundary(w, after: 454_000))
    }

    // MARK: - Following

    /// Five more stations along the line, west to east: S1 on e1, S2 and
    /// S3 on e2, D and C on e3, before B; each a platform 20,000 long.
    private func makeChainWorld() throws -> (world: GameWorld, stations: [String: StationID]) {
        var (world, _, b) = try makeWorld()
        var stations: [String: StationID] = ["B": b]
        for (name, edge, from) in [("S1", 1, Int64(30_000)), ("S2", 2, 20_000), ("S3", 2, 150_000), ("D", 3, 20_000), ("C", 3, 100_000)] {
            let x = 1_024 + Int64(edge - 1) * Self.edgeLength + from + 10_000
            let station = try world.buildStation(named: name, at: PlanPoint(x: x, y: 2_048)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: from, to: from + 20_000)
            stations[name] = station
        }
        return (world, stations)
    }

    private func makeChain(blocks: Bool) throws -> (world: GameWorld, trains: [TrainID]) {
        var (world, stations) = try makeChainWorld()
        world.setBlockSections(blocks)
        var trains: [TrainID] = []
        for (from, edge, to) in [("S3", 2, "B"), ("S2", 2, "C"), ("S1", 1, "D")] {
            let id = try world.purchaseTrain(named: "T\(trains.count + 1)").id
            try world.setTrainCars(id, to: 2)
            let end: Int64 = ["S3": 170_000, "S2": 40_000, "S1": 50_000][from]!
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: end))
            try world.setTrainMovementRate(id, to: 4_096)
            try world.setTrainContinuation(id, along: [], stoppingAt: end)
            try world.setTrainTimetable(id, to: [
                ScheduledStop(station: stations[from]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
                ScheduledStop(station: stations[to]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
            ])
            trains.append(id)
        }
        try world.setTrafficControl(true)
        for id in trains {
            try world.startTrainService(id)
        }
        return (world, trains)
    }

    /// Three services leave at 1:00: T1 from S3 to B, T2 from S2 to C past
    /// S3, T3 from S1 to D past S2. T1 takes its route whole and T2 follows
    /// it. Without block sections T3 may not follow T2, which follows
    /// another itself: it waits. With them it follows T2 at once. No two
    /// ever hold the same track, and stepping by minutes gives the world
    /// stepping by seconds does.
    func testATrainFollowingAnotherLeadsAThirdWithBlockSections() throws {
        // Without block sections T3 waits for T2.
        var (old, oldTrains) = try makeChain(blocks: false)
        try old.advance(ticks: 2)
        XCTAssertEqual(old.train(id: oldTrains[0])?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(old.train(id: oldTrains[1])?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertTrue(old.isFollowing(try XCTUnwrap(old.train(id: oldTrains[1]))))
        XCTAssertEqual(old.train(id: oldTrains[2])?.execution, .waitingAtStop(0, cycle: 0), "a train following another leads nobody")

        // With them T3 follows T2.
        var (world, trains) = try makeChain(blocks: true)
        let start = world
        world.setSpeed(.x10)
        var seconds = 0
        var chained = 0
        var thirdLeft: GameTime?
        while seconds < 1_800 {
            try world.advance(ticks: 1)
            seconds += 1
            let held = trains.map { Set(world.heldResources(of: $0)) }
            XCTAssertTrue(held[0].isDisjoint(with: held[1]) && held[0].isDisjoint(with: held[2]) && held[1].isDisjoint(with: held[2]), "second \(seconds)")
            let following = trains.map { world.isFollowing(world.train(id: $0)!) }
            if following[1], following[2] { chained += 1 }
            if thirdLeft == nil, case .travellingToStop? = world.train(id: trains[2])?.execution { thirdLeft = world.train(id: trains[2])?.times?.departure }
            // A service's last call completes it.
            if trains.allSatisfy({ world.train(id: $0)?.execution == nil }) { break }
        }
        XCTAssertGreaterThan(chained, 0, "T3 followed T2 while T2 followed T1")
        XCTAssertEqual(thirdLeft, GameTime(seconds: 60), "T3 left at 1:00")
        for id in trains {
            XCTAssertNil(world.train(id: id)?.execution, "\(id) arrived")
        }

        // Stepping by minutes gives the same world.
        let minutesRun = seconds / 60 + 1
        var minutes = start
        try minutes.advance(ticks: minutesRun)
        var byTicks = start
        byTicks.setSpeed(.x10)
        try byTicks.advance(ticks: minutesRun * 60)
        byTicks.setSpeed(.normal)
        XCTAssertEqual(minutes, byTicks)
    }

    // MARK: - Saves

    /// Missing key is off; on, it is saved as `"blockSections": true` and
    /// read back.
    func testBlockSectionsAreSavedOnlyWhenOn() throws {
        var (world, _, _) = try makeWorld()
        XCTAssertFalse(world.blockSections)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertFalse(String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self).contains("blockSections"))
        world.setBlockSections(true)
        let data = try encoder.encode(SavedGame(world: world))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""blockSections":true"#))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    /// Save version 55: the three services of
    /// ``testATrainFollowingAnotherLeadsAThirdWithBlockSections()`` at 2:00,
    /// T2 following T1 and T3 following T2, a block at a time.
    func testVersionFiftyFiveKeepsBlockSections() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v55-block-sections.json")
        var (made, trains) = try makeChain(blocks: true)
        try made.advance(ticks: 2)
        XCTAssertTrue(made.isFollowing(try XCTUnwrap(made.train(id: trains[1]))))
        XCTAssertTrue(made.isFollowing(try XCTUnwrap(made.train(id: trains[2]))))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["BLOCK_SECTIONS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 55)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertTrue(loaded.blockSections)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 55,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
