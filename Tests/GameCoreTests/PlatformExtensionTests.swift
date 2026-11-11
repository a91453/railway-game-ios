import Foundation
import GameCore
import XCTest

/// Decision 687: a platform lengthened where it stands
/// (`GameWorld.extendTrackPlatform(_:on:from:toStart:end:)`). Expected
/// values are worked out by hand from the layout below.
final class PlatformExtensionTests: XCTestCase {
    // Four nodes 8192 apart eastward, three straight edges:
    //
    //   a ──e1── b ──e2── c ──e3── d
    //
    // West on e1 1024...5120, Mid on e2 3000...5048, East on e3
    // 4096...5120, Terminus on e3 6144...8192.
    private let e1 = TrackEdgeID.edge(1)
    private let e2 = TrackEdgeID.edge(2)
    private let e3 = TrackEdgeID.edge(3)
    private let west = StationID(rawValue: 1)
    private let mid = StationID(rawValue: 2)
    private let east = StationID(rawValue: 3)
    private let terminus = StationID(rawValue: 4)

    private func forward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .forward)
    }

    private func makeWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 32_768, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
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

    /// A train of `cars` cars stopped with its head at `offset` of `edge`.
    private func standing(_ cars: Int, on edge: TrackEdgeID, at offset: Int64, in world: inout GameWorld) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T\(world.trains.count + 1)").id
        try world.setTrainCars(id, to: cars)
        try world.placeTrain(id, at: .onEdge(forward(edge), offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        return id
    }

    /// Both ends move out, the platform stays one platform of its station,
    /// nothing is paid, and trains now run to its new far end.
    func testAPlatformGrowsAtBothEndsForNothing() throws {
        var world = try makeWorld()
        let balance = world.economy.balance
        try world.extendTrackPlatform(mid, on: e2, from: 3_000, toStart: 2_000, end: 6_000)
        XCTAssertEqual(world.trackPlatforms(of: mid), [TrackPlatform(station: mid, edge: e2, start: 2_000, end: 6_000)])
        XCTAssertEqual(world.economy.balance, balance)
        XCTAssertEqual(world.network.platforms.count, 4)
        // The rest of e1 (8192), then 6000 into e2.
        XCTAssertEqual(world.path(from: .onEdge(forward(e1), offset: 0), toStation: mid), TrainPath(traversals: [forward(e2)], end: 6_000, distance: 14_192))
        // Its ends cut the edge's spans where they now are.
        let cuts = Set(world.trackSpans(of: e2).map(\.start))
        XCTAssertTrue(cuts.isSuperset(of: [2_000, 6_000]))
        XCTAssertTrue(cuts.isDisjoint(with: [3_000, 5_048]))
        // One end alone.
        try world.extendTrackPlatform(mid, on: e2, from: 2_000, toStart: 2_000, end: 8_192)
        XCTAssertEqual(world.trackPlatforms(of: mid), [TrackPlatform(station: mid, edge: e2, start: 2_000, end: 8_192)])
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, world)
    }

    /// Each refusal leaves the world as it was.
    func testRefusalsChangeNothing() throws {
        var world = try makeWorld()
        let before = world
        func refused(_ station: StationID, _ edge: TrackEdgeID, _ start: Int64, _ newStart: Int64, _ newEnd: Int64, _ error: GameError, line: UInt = #line) {
            XCTAssertThrowsError(try world.extendTrackPlatform(station, on: edge, from: start, toStart: newStart, end: newEnd), line: line) {
                XCTAssertEqual($0 as? GameError, error, line: line)
            }
            XCTAssertEqual(world, before, line: line)
        }
        refused(StationID(rawValue: 9), e2, 3_000, 2_000, 6_000, .unknownStation(StationID(rawValue: 9)))
        // No such platform: another station's, another start.
        refused(west, e2, 3_000, 2_000, 6_000, .invalidPlatform)
        refused(mid, e2, 3_001, 2_000, 6_000, .invalidPlatform)
        // No longer, shorter at an end, or moved.
        refused(mid, e2, 3_000, 3_000, 5_048, .invalidPlatform)
        refused(mid, e2, 3_000, 3_500, 6_000, .invalidPlatform)
        refused(mid, e2, 3_000, 2_000, 5_000, .invalidPlatform)
        // Off the edge.
        refused(mid, e2, 3_000, -1, 5_048, .invalidPlatform)
        refused(mid, e2, 3_000, 3_000, 8_193, .invalidPlatform)
        // Into Terminus's platform, which starts at 6144; up to it is fine.
        refused(east, e3, 4_096, 4_096, 6_145, .invalidPlatform)
        try world.extendTrackPlatform(east, on: e3, from: 4_096, toStart: 4_096, end: 6_144)
        XCTAssertEqual(world.trackPlatforms(of: east), [TrackPlatform(station: east, edge: e3, start: 4_096, end: 6_144)])
    }

    /// The room is the edge's ends or the next platform along.
    func testTheRoomReachesTheEdgesEndsAndTheNextPlatform() throws {
        let world = try makeWorld()
        func room(_ station: StationID) -> [Int64]? {
            world.trackPlatforms(of: station).first.flatMap { world.trackPlatformRoom(of: $0) }.map { [$0.before, $0.after] }
        }
        XCTAssertEqual(room(west), [1_024, 3_072])
        XCTAssertEqual(room(mid), [3_000, 3_144])
        // East: back to the edge's start, on to Terminus at 6144.
        XCTAssertEqual(room(east), [4_096, 1_024])
        // Terminus: back to East's end at 5120, and it ends the edge.
        XCTAssertEqual(room(terminus), [1_024, 0])
        XCTAssertNil(world.trackPlatformRoom(of: TrackPlatform(station: mid, edge: e2, start: 1, end: 2)))
    }

    /// A platform grows only over level track: an edge that rises 1 unit
    /// over 8192 is at height 0 up to 4095 and at 1 from 4096.
    func testAPlatformGrowsOnlyOverLevelTrack() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 32_768, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 1_024, z: 1))
        try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "Slope", at: TestLine.centre(1, 6)).id
        try world.addTrackPlatform(station, on: e1, from: 1_024, to: 3_072)
        let platform = try XCTUnwrap(world.trackPlatforms(of: station).first)
        let room = try XCTUnwrap(world.trackPlatformRoom(of: platform))
        XCTAssertEqual(room.before, 1_024)
        XCTAssertEqual(room.after, 1_023)
        let before = world
        XCTAssertThrowsError(try world.extendTrackPlatform(station, on: e1, from: 1_024, toStart: 1_024, end: 4_096)) {
            XCTAssertEqual($0 as? GameError, .invalidPlatform)
        }
        XCTAssertEqual(world, before)
        try world.extendTrackPlatform(station, on: e1, from: 1_024, toStart: 0, end: 4_095)
        XCTAssertEqual(world.trackPlatforms(of: station), [TrackPlatform(station: station, edge: e1, start: 0, end: 4_095)])
    }

    /// Without traffic control a train stopped at the platform stays
    /// stopped at its station, now beside all of a longer platform.
    func testATrainStoppedAtThePlatformStaysAtItsStation() throws {
        var world = try makeWorld()
        // Four cars, 3072 long, head at Mid's far end: its tail at 1976 is
        // off the 2048 platform.
        let id = try standing(4, on: e2, at: 5_048, in: &world)
        XCTAssertEqual(world.stationsStoppedAt(by: id), [mid])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [])
        try world.extendTrackPlatform(mid, on: e2, from: 3_000, toStart: 1_976, end: 5_048)
        XCTAssertEqual(world.stationsStoppedAt(by: id), [mid])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [mid])
        XCTAssertEqual(world.train(id: id)?.position, .onEdge(forward(e2), offset: 5_048))
    }

    /// Under traffic control the platform's ends cut the spans trains
    /// hold: while one holds a span of the edge the platform stays as it
    /// is, as adding or removing one there would be refused.
    func testATrainHoldingTheTrackRefusesItUnderTrafficControl() throws {
        var world = try makeWorld()
        let id = try standing(2, on: e2, at: 5_048, in: &world)
        try world.setTrafficControl(true)
        let before = world
        XCTAssertThrowsError(try world.extendTrackPlatform(mid, on: e2, from: 3_000, toStart: 2_000, end: 6_000)) {
            XCTAssertEqual($0 as? GameError, .trackReserved(id))
        }
        XCTAssertEqual(world, before)
        // Another edge's platform is free to grow.
        try world.extendTrackPlatform(west, on: e1, from: 1_024, toStart: 0, end: 5_120)
        XCTAssertEqual(world.trackPlatforms(of: west), [TrackPlatform(station: west, edge: e1, start: 0, end: 5_120)])
    }
}
