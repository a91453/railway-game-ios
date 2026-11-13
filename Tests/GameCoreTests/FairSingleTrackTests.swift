import Foundation
@testable import GameCore
import XCTest

/// A single track between two stations with several berths each (decision
/// 718): A's berths fan out west of the single track, B's east of it.
///
///     A2 ─╮                    ╭─ B2
///     A0 ──┴─ A1' ── single ───┴── B0      (a ladder: one turnout a berth)
///
/// Every berth is a dead end, so a train stands at A facing east or at B
/// facing west, and the only way between the stations is the single track.
enum SingleTrackFan {
    static let y: Int64 = 8_192
    static let single: Int64 = 16_384
    static let pitch: Int64 = 12_288

    /// A berth: its own station, so that no train waits for another's
    /// platform, only for the track between.
    struct Berth {
        let station: StationID
        let edge: TrackEdgeID
    }

    /// The world and each end's berths, nearest the single track first:
    /// `berths` of them an end.
    static func world(berths: Int) throws -> (world: GameWorld, west: [Berth], east: [Berth]) {
        let reach = Int64(berths) * pitch
        var world = try GameWorld(bounds: WorldBounds(width: 2 * reach + single + 4_096, height: 2 * y), economy: GameEconomy(balance: 100_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        let west = try world.buildTrackNode(at: WorldCoordinate(x: reach + 2_048, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: reach + 2_048 + single, y: y))
        _ = try world.buildTrackEdge(from: west, to: east)
        var ends: [[Berth]] = []
        for (name, start, d) in [("A", west, Int64(-1)), ("B", east, Int64(1))] {
            var found: [Berth] = []
            var turnout = start
            var x = world.trackNode(start)!.position.x
            func berth(on edge: TrackEdgeID, from: Int64, at point: PlanPoint) throws {
                let station = try world.buildStation(named: "\(name)\(found.count)", at: point).id
                try world.addTrackPlatform(station, on: edge, from: from, to: from + 4_096)
                found.append(Berth(station: station, edge: edge))
            }
            for index in 1..<berths {
                // A branch to one side, then the other.
                let up = index % 2 == 1
                let side = y + (up ? 2_048 : -2_048)
                let p = try world.buildTrackNode(at: WorldCoordinate(x: x + d * 4_096, y: side))
                let q = try world.buildTrackNode(at: WorldCoordinate(x: x + d * 10_240, y: side))
                _ = try world.buildTrackEdge(from: turnout, to: p, curve: .cubic(.init(x: x + d * 2_048, y: y), .init(x: x + d * 2_048, y: side)))
                try berth(on: try world.buildTrackEdge(from: p, to: q), from: 1_024, at: PlanPoint(x: x + d * 7_168, y: y + (up ? 6_144 : -6_144)))
                // The main goes on to the next turnout, or its own berth.
                let last = index == berths - 1
                x += d * (last ? 10_240 : pitch)
                let next = try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
                let main = try world.buildTrackEdge(from: turnout, to: next)
                turnout = next
                if last { try berth(on: main, from: 5_120, at: PlanPoint(x: x - d * 4_096, y: y - (up ? 6_144 : -6_144))) }
            }
            ends.append(found)
        }
        return (world, ends[0], ends[1])
    }

    /// A two-car train standing at `berth` facing the single track, with a
    /// service from there to `destination` that leaves at `departure`.
    static func train(_ world: inout GameWorld, at berth: Berth, to destination: Berth, departure: Int64, run: Int64 = 600) throws -> TrainID {
        let length = world.trackEdge(berth.edge)!.length
        let platform = world.network.platforms.first { $0.edge == berth.edge }!
        let id = try SingleTrackMeet.stand(&world, edge: TrackTraversal(edge: berth.edge, direction: .backward), offset: length - platform.start)
        try world.setTrainTimetable(id, to: [
            .init(station: berth.station, arrival: .init(seconds: 0), departure: .init(seconds: departure)),
            .init(station: destination.station, arrival: .init(seconds: departure + run), departure: .init(seconds: departure + run + 60)),
        ])
        try world.startTrainService(id)
        return id
    }

    /// The second each train set off from its first call, stepping `world`
    /// `seconds` one second at a time.
    static func departures(_ world: inout GameWorld, seconds: Int) throws -> [TrainID: Int64] {
        var left: [TrainID: Int64] = [:]
        world.setSpeed(.x1)
        while world.clock.now.seconds < Int64(seconds) {
            try world.advance(ticks: 1)
            for train in world.trains where left[train.id] == nil {
                if case .waitingAtStop(0, _)? = train.execution { continue }
                left[train.id] = world.clock.now.seconds
            }
        }
        return left
    }
}

/// Decision 718: trains waiting at both ends of a single track go in the
/// order they came to wait.
final class FairSingleTrackTests: XCTestCase {
    /// Three trains at the west end due at `east`, one at the east end due
    /// at `west`, traffic control on. IDs 1 to 3 eastbound, 4 westbound.
    static func stream(east: [Int64], west: Int64?) throws -> GameWorld {
        var (world, a, b) = try SingleTrackFan.world(berths: 4)
        for (index, departure) in east.enumerated() {
            _ = try SingleTrackFan.train(&world, at: a[index], to: b[index], departure: departure)
        }
        if let west { _ = try SingleTrackFan.train(&world, at: b[3], to: a[3], departure: west) }
        try world.setTrafficControl(true)
        return world
    }

    static func id(_ raw: Int) -> TrainID { TrainID(rawValue: raw) }

    /// The gap this closes: train 1 is on the single track when the
    /// westbound train comes due at 120, then two more eastbound at 180
    /// and 240. They used to go in behind train 1 and after it (the
    /// westbound left last, at 1146); now the westbound goes as soon as
    /// train 1 is clear, and they after it.
    func testATrainThatHasWaitedLongerGoesBeforeLaterOnesTheOtherWay() throws {
        var world = try Self.stream(east: [60, 180, 240], west: 120)
        let left = try SingleTrackFan.departures(&world, seconds: 1_800)
        let (e1, e2, e3, w) = (left[Self.id(1)], left[Self.id(2)], left[Self.id(3)], left[Self.id(4)])
        XCTAssertEqual(e1, 61)
        let west = try XCTUnwrap(w)
        XCTAssertLessThan(west, try XCTUnwrap(e2))
        XCTAssertLessThan(west, try XCTUnwrap(e3))
        XCTAssertLessThan(try XCTUnwrap(e2), try XCTUnwrap(e3), "and they in the order they came")
        XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil }, "every service ran to its end")
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// While it gives its turn, the train says for whom, and is listed as
    /// waiting for that train with no track contested: train 3, which
    /// could follow train 1 onto the single track.
    func testTheTrainGivingItsTurnNamesTheTrainThatGoesFirst() throws {
        var world = try Self.stream(east: [60, 180, 240], west: 120)
        world.setSpeed(.x1)
        try world.advance(ticks: 3_000) // second 300: train 1 still on the single track
        XCTAssertEqual(world.trainGoingFirst(before: Self.id(3)), Self.id(4))
        XCTAssertEqual(world.trainHoldingRoute(of: Self.id(3)), Self.id(4))
        XCTAssertEqual(world.contestedResources(of: Self.id(3)), [])
        XCTAssertNil(world.trainGoingFirst(before: Self.id(2)), "train 2 cannot go yet: it waits for track")
        XCTAssertNil(world.trainGoingFirst(before: Self.id(4)), "the westbound waits for track, not for a turn")
        XCTAssertEqual(world.trainHoldingRoute(of: Self.id(4)), Self.id(1))
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// Trains that came to wait before the one at the other end still go
    /// before it: the rule moves nobody ahead of a train that waited longer.
    func testTrainsThatCameFirstStillGoFirst() throws {
        var world = try Self.stream(east: [60, 61, 62], west: 63)
        let left = try SingleTrackFan.departures(&world, seconds: 1_800)
        let west = try XCTUnwrap(left[Self.id(4)])
        XCTAssertGreaterThan(west, try XCTUnwrap(left[Self.id(2)]))
        XCTAssertGreaterThan(west, try XCTUnwrap(left[Self.id(3)]))
        XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil })
    }

    /// With nobody waiting the other way, nothing is held: the eastbound
    /// trains leave at the same seconds with a westbound train that is not
    /// due yet as with none at all.
    func testALoneDirectionIsNotHeld() throws {
        var alone = try Self.stream(east: [60, 180, 240], west: nil)
        var beside = try Self.stream(east: [60, 180, 240], west: 3_000)
        let expected = try SingleTrackFan.departures(&alone, seconds: 1_200)
        let left = try SingleTrackFan.departures(&beside, seconds: 1_200)
        XCTAssertEqual(expected.count, 3)
        for id in 1...3 { XCTAssertEqual(left[Self.id(id)], expected[Self.id(id)], "train \(id)") }
        XCTAssertNil(left[Self.id(4)])
    }

    /// Two each way, due in turn (east 60, west 120, east 180, west 240):
    /// they go east, west, east, west.
    func testTrainsQueuedAtBothEndsAlternate() throws {
        var (world, a, b) = try SingleTrackFan.world(berths: 4)
        let e1 = try SingleTrackFan.train(&world, at: a[0], to: b[0], departure: 60)
        let w1 = try SingleTrackFan.train(&world, at: b[2], to: a[2], departure: 120)
        let e2 = try SingleTrackFan.train(&world, at: a[1], to: b[1], departure: 180)
        let w2 = try SingleTrackFan.train(&world, at: b[3], to: a[3], departure: 240)
        try world.setTrafficControl(true)
        let left = try SingleTrackFan.departures(&world, seconds: 3_000)
        let order = [e1, w1, e2, w2].sorted { (left[$0] ?? .max) < (left[$1] ?? .max) }
        XCTAssertEqual(order, [e1, w1, e2, w2], "\(left)")
        XCTAssertEqual(left.count, 4)
        XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil })
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// A train kept by one that stands is given no turn: the eastbound
    /// trains would wait for it for good. A train with no service stands
    /// on the east end's main between the westbound's berth and the single
    /// track; the eastbound trains for the berths short of it go as with no
    /// westbound train at all.
    func testATrainKeptByAStandingTrainIsGivenNoTurn() throws {
        func world(westbound: Bool) throws -> GameWorld {
            var (world, a, b) = try SingleTrackFan.world(berths: 4)
            _ = try SingleTrackFan.train(&world, at: a[0], to: b[0], departure: 60)
            _ = try SingleTrackFan.train(&world, at: a[1], to: b[1], departure: 180)
            // The main between the east end's second and third turnouts,
            // on the way out of b[2] and b[3].
            let east = world.trackNode(.node(2))!.position
            let main = try XCTUnwrap(world.network.edges.first { edge in
                world.trackNode(edge.from)?.position == WorldCoordinate(x: east.x + SingleTrackFan.pitch, y: east.y)
                    && world.trackNode(edge.to)?.position == WorldCoordinate(x: east.x + 2 * SingleTrackFan.pitch, y: east.y)
            })
            _ = try SingleTrackMeet.stand(&world, edge: TrackTraversal(edge: main.id, direction: .forward), offset: 6_144)
            if westbound { _ = try SingleTrackFan.train(&world, at: b[3], to: a[3], departure: 120) }
            try world.setTrafficControl(true)
            return world
        }
        var without = try world(westbound: false)
        var with = try world(westbound: true)
        let expected = try SingleTrackFan.departures(&without, seconds: 1_500)
        let left = try SingleTrackFan.departures(&with, seconds: 1_500)
        XCTAssertNotNil(expected[Self.id(2)])
        XCTAssertEqual(left[Self.id(1)], expected[Self.id(1)])
        XCTAssertEqual(left[Self.id(2)], expected[Self.id(2)])
        XCTAssertNil(left[Self.id(4)], "the westbound train cannot leave past the standing one")
    }

    /// One long advance ends where minutes and tenths of a second do, and a
    /// save taken while a train gives its turn goes on the same.
    func testBatchesStepsAndASaveAgree() throws {
        var batch = try Self.stream(east: [60, 180, 240], west: 120)
        var minutes = batch
        var tenths = batch
        try batch.advance(ticks: 30)
        for _ in 0..<30 { try minutes.advance(ticks: 1) }
        tenths.setSpeed(.x1)
        for _ in 0..<3_000 { try tenths.advance(ticks: 1) }
        XCTAssertEqual(tenths.trainGoingFirst(before: Self.id(3)), Self.id(4))
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: tenths))).world
        for _ in 0..<1_500 {
            try tenths.advance(ticks: 10)
            try loaded.advance(ticks: 10)
        }
        XCTAssertEqual(loaded, tenths)
        tenths.setSpeed(.normal)
        XCTAssertEqual(minutes, batch)
        XCTAssertEqual(tenths, batch)
    }
}
