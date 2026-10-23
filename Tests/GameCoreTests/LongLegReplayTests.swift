import Foundation
@testable import GameCore
import XCTest

/// The world of `ReplayFixtures/long-leg-traffic.json` (NEXT_PRIORITIES
/// 2026-10-12 §2 item 6): long legs under traffic control, where a route
/// holds thousands of spans, recorded before route reservation was made
/// faster so that the faster version must replay it to the same states.
///
/// A ring of single track run one way round: two straights of 40 km, the
/// upper run east and the lower west, joined by a turn at each end, laid as
/// edges of at most 4 km. Four stations, A and B on the upper straight and
/// C and D on the lower, each with a passing loop beside its platform, so
/// the legs are 20 to 23 km. A local ring line calls at all four and an
/// express ring line at A, C and D, so trains follow each other (Stage U2) and
/// take the loop's platform when the main one is held (decision 57). The
/// commands are mostly advances, with a save and load, a changed headway
/// and a train taken off its line and put back.
final class LongLegReplayTests: XCTestCase {
    static let metre = WorldCoordinate.unitsPerMetre
    static let west: Int64 = 131_072
    static let length = 40_000 * metre
    static let lower: Int64 = 20_480
    static let upper: Int64 = lower + 128_000

    /// The world the fixture starts from, at 06:00 with traffic control on.
    static func world() throws -> GameWorld {
        let east = west + length
        var world = try GameWorld(
            bounds: WorldBounds(width: east + 131_072, height: upper + 20_480),
            economy: GameEconomy(balance: 1_000_000_000, costs: SingleTrackMeet.costs), clock: GameClock(now: GameTime(minutes: 6 * 60), speed: .normal)
        )
        func node(_ x: Int64, _ y: Int64) throws -> TrackNodeID {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        // A straight from `from` to `to` along `y`, the way it is run, with a
        // station at each of `centres`: its main track 8192 either side of
        // its centre and a loop beside it, `side` off, as in
        // `SingleTrackMeet`. Edges of at most 4 km between.
        var platforms: [(main: TrackEdgeID, loop: TrackEdgeID)] = []
        func straight(from: Int64, to: Int64, y: Int64, side: Int64, centres: [Int64]) throws -> (first: TrackNodeID, last: TrackNodeID) {
            let way: Int64 = to > from ? 1 : -1
            let first = try node(from, y)
            var previous = first, at = from
            func run(to x: Int64) throws {
                let count = (abs(x - at) + 4_000 * metre - 1) / (4_000 * metre)
                for k in 1...count {
                    let next = k == count ? try node(x, y) : try node(at + (x - at) * k / count, y)
                    _ = try world.buildTrackEdge(from: previous, to: next)
                    previous = next
                }
                at = x
            }
            for centre in centres {
                try run(to: centre - way * 8_192)
                let entry = previous
                let exit = try node(centre + way * 8_192, y)
                let loopIn = try node(centre - way * 4_096, y + side), loopOut = try node(centre + way * 4_096, y + side)
                let main = try world.buildTrackEdge(from: entry, to: exit)
                _ = try world.buildTrackEdge(from: entry, to: loopIn, curve: .cubic(PlanPoint(x: centre - way * 6_144, y: y), PlanPoint(x: centre - way * 6_144, y: y + side)))
                let loop = try world.buildTrackEdge(from: loopIn, to: loopOut)
                _ = try world.buildTrackEdge(from: loopOut, to: exit, curve: .cubic(PlanPoint(x: centre + way * 6_144, y: y + side), PlanPoint(x: centre + way * 6_144, y: y)))
                platforms.append((main, loop))
                previous = exit
                at = centre + way * 8_192
            }
            try run(to: to)
            return (first, previous)
        }
        let quarter = length / 4
        let top = try straight(from: west, to: east, y: upper, side: 2_048, centres: [west + quarter, west + 3 * quarter])
        let bottom = try straight(from: east, to: west, y: lower, side: -2_048, centres: [west + 3 * quarter, west + quarter])
        _ = try world.buildTrackEdge(from: top.last, to: bottom.first, curve: .cubic(PlanPoint(x: east + 96_000, y: upper), PlanPoint(x: east + 96_000, y: lower)))
        _ = try world.buildTrackEdge(from: bottom.last, to: top.first, curve: .cubic(PlanPoint(x: west - 96_000, y: lower), PlanPoint(x: west - 96_000, y: upper)))
        var stations: [StationID] = []
        for (index, name) in ["A", "B", "C", "D"].enumerated() {
            let main = platforms[index].main
            let centre = try XCTUnwrap(world.trackEdge(main)?.length) / 2
            let point = try XCTUnwrap(world.network.node(try XCTUnwrap(world.trackEdge(main)).from)).position
            let station = try world.buildStation(named: name, at: PlanPoint(x: point.x + (index < 2 ? 8_192 : -8_192), y: point.y + (index < 2 ? 6_144 : -6_144))).id
            try world.addTrackPlatform(station, on: main, from: centre - 3_072, to: centre + 3_072)
            try world.addTrackPlatform(station, on: platforms[index].loop, from: 1_024, to: 7_168)
            stations.append(station)
        }
        let local = try world.createLine(named: "Local", stops: stations).id
        let express = try world.createLine(named: "Express", stops: [stations[0], stations[2], stations[3]]).id
        for line in [local, express] { try world.setLineRing(line, to: true) }
        try world.setLinePerformance(express, to: .express)
        try world.setLineTargetHeadways(local, to: TargetHeadways(peak: 15, offPeak: 15, low: 15))
        try world.setLineTargetHeadways(express, to: TargetHeadways(peak: 30, offPeak: 30, low: 30))
        // Four-car trains standing at the platforms, facing the way round.
        func stand(_ line: LineID, at station: Int, loop: Bool) throws {
            let id = try world.purchaseTrain(named: "T\(world.trains.count + 1)").id
            try world.setTrainCars(id, to: 4)
            let edge = loop ? platforms[station].loop : platforms[station].main
            let platform = try XCTUnwrap(world.trackPlatforms(of: stations[station]).first { $0.edge == edge })
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: platform.end))
            try world.setTrainContinuation(id, along: [], stoppingAt: platform.end)
            try world.useTrainPerformanceForMovement(id)
            try world.assignTrain(id, to: line)
        }
        try stand(local, at: 0, loop: false)
        try stand(local, at: 2, loop: false)
        try stand(express, at: 0, loop: true)
        try stand(express, at: 2, loop: true)
        // Decision 172: a ring line sends its trains out from the stops they
        // stand at.
        world.setFlexDispatch(true)
        try world.setTrafficControl(true)
        return world
    }

    /// The commands: advances of five minutes, three hours in all, with a
    /// save and load, a changed headway and a train taken off its line and
    /// put back.
    static func operations() -> [KernelDifferentialTests.Operation] {
        var operations: [KernelDifferentialTests.Operation] = []
        for index in 0..<40 {
            switch index {
            case 12: operations.append(.saveAndLoad)
            case 20: operations.append(.setLineTargets(LineID(rawValue: 1), TargetHeadways(peak: 10, offPeak: 10, low: 10)))
            case 26: operations.append(.unassign(TrainID(rawValue: 3)))
            case 30: operations.append(.assign(TrainID(rawValue: 3), LineID(rawValue: 1)))
            default: break
            }
            operations.append(.advance(5))
        }
        return operations
    }

    /// Decision 364: no train is ever deadlocked over the fixture's three
    /// hours. Its ring trains stood at C send out round to A and on for a
    /// whole lap; a first try that ended their trip at A left them standing
    /// there, and all four deadlocked at 06:58.
    func testNoTrainDeadlocksOverTheThreeHours() throws {
        var world = try Self.world()
        for _ in 0..<36 {
            try world.advance(ticks: 5)
            XCTAssertEqual(world.deadlockedTrains(), [], "at \(world.clock.now.minutes / 60):\(world.clock.now.minutes % 60)")
        }
    }

    /// Records the fixture, only on request, as `ReplayFixtureTests` records
    /// the campaign's: `REPLAY_RECORD=<directory>`. Recorded once, with the
    /// route reservation that came before it was made faster; recording
    /// again is a behaviour change to justify, never a way to make the
    /// replay pass.
    func testRecordingTheFixture() throws {
        guard let directory = ProcessInfo.processInfo.environment["REPLAY_RECORD"] else {
            throw XCTSkip("set REPLAY_RECORD=<directory> to record the replay fixtures")
        }
        let start = try Self.world()
        let operations = Self.operations()
        let checksums = ReplayFixture.checksums(from: start, applying: operations, every: ReplayFixture.interval) { index, problem in
            XCTFail("long-leg-traffic: command \(index): \(problem)")
        }
        let fixture = try ReplayFixture(
            schemaVersion: ReplayFixture.schemaVersion,
            description: "Long legs under traffic control: a local and an express ring line on a ring of 80 km of single track with passing loops, routes of thousands of spans.",
            source: "LongLegReplayTests.world()", start: start, interval: ReplayFixture.interval,
            commands: operations.map(ReplayCommand.init), checksums: checksums
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(fixture).write(to: URL(fileURLWithPath: directory).appendingPathComponent("long-leg-traffic.json"))
    }
}
