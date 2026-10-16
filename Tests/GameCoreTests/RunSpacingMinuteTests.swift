import Foundation
@testable import GameCore
import XCTest

/// ARCHITECTURE decision 248: with traffic control off, how far a train of
/// a line with real runs may go is decided once a minute (and as it sets
/// off), so a minute in one step is sixty one-second steps (decision 37),
/// and two trains never both go onto a single track towards each other.
///
/// A straight single track of thirteen columns: West beside column 1,
/// Alpha beside 3, Gamma beside 10; a link (1024 units) at the crawl takes
/// about a minute.
final class RunSpacingMinuteTests: XCTestCase {
    private let track = TestLine(tiles: 13)
    private let west = StationID(rawValue: 1)
    private let alpha = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let slow = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)
    private let fast = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 3)

    private func run(_ from: Int, _ to: Int, at minute: Int64, taking minutes: Int64) -> LineRun {
        LineRun(from: from, to: to, times: [
            LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + minutes) * 60, departure: (minute + minutes) * 60),
        ])
    }

    /// The track and its stations at 05:55, traffic control off, and the
    /// lines `lines` (stops, performance, runs), each with a train placed
    /// at its column and facing.
    private func makeWorld(_ lines: [(stops: [StationID], performance: TrainPerformance, runs: [LineRun], trains: [(x: Int, facingEast: Bool)])]) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 14_336, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 355), speed: .normal)
        )
        try track.build(in: &world)
        try track.buildStation(named: "West", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Alpha", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 10, at: 0, in: &world)
        try world.setTrafficControl(false)
        for (number, line) in lines.enumerated() {
            let id = try world.createLine(named: "L\(number + 1)", stops: line.stops).id
            try world.setLinePerformance(id, to: line.performance)
            try world.setLineRuns(id, to: line.runs)
            for (x, facingEast) in line.trains {
                let train = try world.purchaseTrain(named: "T\(x)")
                try world.placeTrain(train.id, at: track.at(x, facingEast: facingEast))
                try world.setTrainMovementRate(train.id, to: 1024)
                try world.assignTrain(train.id, to: id)
            }
        }
        return world
    }

    /// Pairs of trains whose bodies lie on one edge at once, and whether
    /// they face each other there.
    private func meetings(in world: GameWorld) -> [(TrainID, TrainID, opposite: Bool)] {
        var on: [TrackEdgeID: [(TrainID, TrackEdgeDirection, Int64, Int64)]] = [:]
        for train in world.trains {
            for stretch in world.bodyStretches(of: train) where stretch.to > stretch.from {
                guard let length = world.network.edge(stretch.traversal.edge)?.length else { continue }
                let (low, high) = stretch.traversal.direction == .forward ? (stretch.from, stretch.to) : (length - stretch.to, length - stretch.from)
                on[stretch.traversal.edge, default: []].append((train.id, stretch.traversal.direction, low, high))
            }
        }
        var found: [(TrainID, TrainID, opposite: Bool)] = []
        for trains in on.values {
            for i in trains.indices {
                for j in trains.indices where j > i && trains[i].0 != trains[j].0 {
                    let opposite = trains[i].1 != trains[j].1
                    if opposite || min(trains[i].3, trains[j].3) > max(trains[i].2, trains[j].2) { found.append((trains[i].0, trains[j].0, opposite)) }
                }
            }
        }
        return found
    }

    /// Runs `minutes` minutes both in one step a minute and sixty one-second
    /// steps, checking every second that no two trains overlap or face each
    /// other on an edge, and every minute that the two worlds agree.
    private func check(_ start: GameWorld, minutes: Int, file: StaticString = #filePath, line: UInt = #line) throws -> GameWorld {
        var whole = start
        var seconds = start
        seconds.setSpeed(.x10)
        for minute in 1...minutes {
            try whole.advance(ticks: 1)
            for second in 1...60 {
                try seconds.advance(ticks: 1)
                let met = meetings(in: seconds)
                XCTAssertEqual(met.map { "\($0.0.rawValue)-\($0.1.rawValue) \($0.opposite ? "facing" : "overlapping")" }, [],
                               "minute \(minute), second \(second)", file: file, line: line)
                if !met.isEmpty { return seconds }
            }
            XCTAssertEqual(whole.trains, seconds.trains, "minute \(minute)", file: file, line: line)
            if whole.trains != seconds.trains { return seconds }
        }
        XCTAssertEqual(whole, seconds, file: file, line: line)
        return whole
    }

    /// Two trains leaving the two ends of the single track in the same
    /// minute: one goes on, the other waits.
    func testOnASingleTrackOnlyOneGoesOn() throws {
        let world = try makeWorld([
            ([alpha, gamma], slow, [run(0, 1, at: 360, taking: 12), run(1, 0, at: 360, taking: 12)], [(3, true), (10, false)]),
        ])
        let after = try check(world, minutes: 25)
        let travelled = after.trains.map { $0.position.map { position -> Int64 in
            guard case .onEdge(let traversal, _) = position else { return 0 }
            return Int64(traversal.edge.rawValue)
        } ?? 0 }
        XCTAssertNotEqual(travelled, [4, 10], "one of them has gone onto the track between: \(travelled)")
    }

    /// A faster train behind a slower one on the same way stops short of
    /// it, and a minute in one step leaves them where seconds do.
    func testAFasterTrainBehindStopsShort() throws {
        let world = try makeWorld([
            ([alpha, gamma], slow, [run(0, 1, at: 360, taking: 12)], [(3, true)]),
            ([west, gamma], fast, [run(0, 1, at: 361, taking: 4)], [(1, true)]),
        ])
        let after = try check(world, minutes: 20)
        XCTAssertEqual(WorldInvariants.violations(in: after), [])
    }

    /// Save version 63: saved within a minute, the allowances come back,
    /// and the loaded world goes on as the saved one does.
    func testVersionSixtyThreeKeepsTheAllowances() throws {
        var world = try makeWorld([
            ([alpha, gamma], slow, [run(0, 1, at: 360, taking: 12)], [(3, true)]),
            ([west, gamma], fast, [run(0, 1, at: 361, taking: 4)], [(1, true)]),
        ])
        world.setSpeed(.x10)
        for _ in 0..<(8 * 60 + 25) { try world.advance(ticks: 1) }
        XCTAssertFalse(world.spacingAllowances.isEmpty)
        let url = SavedGameTests.fixtures.appendingPathComponent("v63-spacing-allowances.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SPACING_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 63)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 63,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        for _ in 0..<120 {
            try world.advance(ticks: 1)
            try loaded.advance(ticks: 1)
        }
        XCTAssertEqual(loaded, world)
    }

    /// A saved allowance that is not well formed is refused.
    func testABadAllowanceIsRefused() throws {
        let world = try makeWorld([([alpha, gamma], slow, [run(0, 1, at: 360, taking: 12)], [(3, true)])])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        object["spacingAllowances"] = [["train": 1, "left": -1, "stop": 1, "cycle": 0]]
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object)))
        object["spacingAllowances"] = [["train": 1, "stop": 1, "cycle": 0], ["train": 1, "stop": 1, "cycle": 0]]
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
