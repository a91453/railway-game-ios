import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The high-speed demo's real day (decisions 197, 221 and 228), from 07:00
/// to half past seven the next morning, minute by minute: its sets keep to
/// the real day, never two on one track at once, and stand in the depots at
/// night. A class of its own, as a day takes minutes in a debug build: CI
/// runs it in a shard of its own (`campaigns-16`, `.github/scripts/swift-shards.sh`).
final class HighSpeedDemoDayTests: XCTestCase {
    /// The game as it runs, from 07:00 to half past seven the next morning,
    /// minute by minute (decision 228), as the tests of the real day read
    /// it. Run once for them: a day takes some minutes in a debug build.
    struct Day {
        /// Two sets on one edge at once, from 07:00 to 03:00: the minute,
        /// the sets, the edge and how far they overlap.
        var overlaps: [String] = []
        /// A set running against its way's track.
        var against: [String] = []
        var seen = (down: 0, up: 0)
        /// How late each set ran at most, in seconds, on a run.
        var late: [String: Int64] = [:]
        /// At 03:00, every set that is not in a depot, or shares its
        /// siding with another.
        var night: [String] = []
        var world: GameWorld
    }

    private static let day: Result<Day, Error> = Result {
        var world = try HighSpeedDemoTests.opened.get()
        let tracks = try HighSpeedDemoTests.built.get().tracks
        var day = Day(world: world)
        for _ in 0..<(24 * 60 + 30) {
            try world.advance(ticks: 1)
            let minute = world.clock.now.minute
            if minute == 1_440 + 3 * 60 {
                var sidings: Set<TrackEdgeID> = []
                for train in world.trains {
                    if !world.standsInADepot(train) { day.night.append("\(train.name) is not in a depot at 03:00") }
                    if case .onEdge(let traversal, _)? = train.position, !sidings.insert(traversal.edge).inserted {
                        day.night.append("\(train.name) shares a siding at 03:00")
                    }
                }
            }
            if minute <= 1_440 + 3 * 60 {
                for overlap in overlaps(in: world) {
                    let names = [overlap.trains.0, overlap.trains.1].map { world.train(id: $0)?.name ?? "?" }
                    day.overlaps.append("\(minute / 60 % 24):\(minute % 60) \(names[0]) and \(names[1]) on \(overlap.edge), \(overlap.length / Int64(HighSpeedDemoTests.metre)) m")
                }
            }
            for train in world.trains where train.execution != nil {
                day.late[train.name] = max(day.late[train.name] ?? 0, world.lateness(of: train.id) ?? 0)
                guard case .onEdge(let traversal, _)? = train.position else { continue }
                if tracks.isAgainst(traversal) { day.against.append("\(train.name) at minute \(minute)") }
                if tracks.southbound.contains(traversal.edge) { day.seen.down += 1 }
                if tracks.northbound.contains(traversal.edge) { day.seen.up += 1 }
            }
        }
        day.world = world
        return day
    }

    /// The game as it runs, from 07:00 to half past seven the next morning:
    /// no set runs against its way's track, so no two sets going opposite
    /// ways are ever on the same track (but where sets turn back); both
    /// tracks are used all day; no set is more than a few minutes late
    /// (decision 228: a set held up by the one ahead goes on at its pace);
    /// no run is dropped; and the next morning's runs leave again (decision
    /// 197).
    func testItsSetsKeepToTheRealDay() throws {
        let day = try Self.day.get()
        XCTAssertEqual(day.against, [], "against its way's track")
        XCTAssertGreaterThan(day.seen.down, 5_000)
        XCTAssertGreaterThan(day.seen.up, 5_000)
        let latest = day.late.values.max() ?? 0
        XCTAssertLessThan(latest, Self.latestAllowed, "\(day.late.filter { $0.value >= Self.latestAllowed })")
        let world = day.world
        XCTAssertEqual(world.clock.now.minute % 1_440, 7 * 60 + 30)
        let now = world.clock.now.seconds - GameTime.secondsPerDay
        for line in world.lines {
            for (index, run) in line.runs.enumerated() {
                let day: Int64 = run.times[0].departure + LineRun.latestDispatch < now ? 1 : 0
                XCTAssertGreaterThanOrEqual(line.runDays[index] ?? -1, day, "\(line.name): the run leaving at \(run.times[0].departure / 60) min")
            }
        }
    }

    /// How late a set may run at most over the day (decision 228): the
    /// spacing rules hold a set behind the one ahead for a few minutes where
    /// the game's runs close up on the real day's spacing.
    static let latestAllowed: Int64 = 30 * 60

    /// Decision 228 (the author's report of 62.1: two sets on one track at
    /// Zuoying): from 07:00 to 03:00, minute by minute, no two sets' bodies
    /// are ever on the same edge at once, at a platform or between
    /// stations; and at 03:00 every set stands in a depot, on a siding of
    /// its own, and none on a platform (decision 221, #627).
    func testNoTwoSetsOverlapAllDay() throws {
        let day = try Self.day.get()
        XCTAssertEqual(day.overlaps, [], "two sets on one edge")
        XCTAssertEqual(day.night, [], "at night")
    }

    /// Where two sets' bodies lie on the same edge at once: each pair of
    /// sets, the edge, and how far they overlap along it (world units).
    static func overlaps(in world: GameWorld) -> [(trains: (TrainID, TrainID), edge: TrackEdgeID, length: Int64)] {
        var bodies: [TrackEdgeID: [(TrainID, Int64, Int64)]] = [:]
        for train in world.trains {
            for stretch in world.bodyStretches(of: train) where stretch.to > stretch.from {
                guard let length = world.network.edge(stretch.traversal.edge)?.length else { continue }
                let (low, high) = stretch.traversal.direction == .forward ? (stretch.from, stretch.to) : (length - stretch.to, length - stretch.from)
                bodies[stretch.traversal.edge, default: []].append((train.id, low, high))
            }
        }
        var found: [(trains: (TrainID, TrainID), edge: TrackEdgeID, length: Int64)] = []
        for (edge, on) in bodies.sorted(by: { $0.key < $1.key }) where on.count > 1 {
            for i in on.indices {
                for j in on.indices where j > i && on[i].0 != on[j].0 {
                    let length = min(on[i].2, on[j].2) - max(on[i].1, on[j].1)
                    if length > 0 { found.append(((on[i].0, on[j].0), edge, length)) }
                }
            }
        }
        return found
    }

    /// The real day minute by minute, measured, and printed only on
    /// request (decision 228): by station (of a platform on the edge, or
    /// "-") and hour, how many minutes two sets overlapped, and the most
    /// sets standing at each station at once against its platforms; and
    /// how late each set ran at most:
    ///
    ///     HSR_OVERLAP_REPORT=1 swift test -c release -Xswiftc -enable-testing --filter HighSpeedDemoDayTests/testOverlapReport
    func testOverlapReport() throws {
        guard ProcessInfo.processInfo.environment["HSR_OVERLAP_REPORT"] != nil else { throw XCTSkip("Set HSR_OVERLAP_REPORT=1.") }
        var world = try HighSpeedDemoTests.opened.get()
        var stationOf: [TrackEdgeID: String] = [:]
        for platform in world.network.platforms {
            stationOf[platform.edge] = world.station(id: platform.station)?.name
        }
        var counts: [String: [Int: Int]] = [:]
        var occupancy: [String: [Int: Int]] = [:]
        var late: [String: Int64] = [:]
        for _ in 0..<(20 * 60) {
            try world.advance(ticks: 1)
            let hour = Int(world.clock.now.minute / 60 % 24)
            var here: [String: Int] = [:]
            for train in world.trains {
                for station in world.stationsStoppedAt(by: train.id) {
                    here[world.station(id: station)?.name ?? "?", default: 0] += 1
                }
                if train.execution != nil { late[train.name] = max(late[train.name] ?? 0, world.lateness(of: train.id) ?? 0) }
            }
            for (station, count) in here {
                occupancy[station, default: [:]][hour] = max(occupancy[station]?[hour] ?? 0, count)
            }
            for overlap in Self.overlaps(in: world) {
                counts[stationOf[overlap.edge] ?? "-", default: [:]][hour, default: 0] += 1
            }
        }
        var lines = ["most sets standing at once, by station and hour:"]
        for (station, hours) in occupancy.sorted(by: { $0.key < $1.key }) {
            let platforms = world.stations.first { $0.name == station }.map { world.network.platforms(of: $0.id).count } ?? 0
            lines.append("\(station): platforms \(platforms); " + hours.sorted { $0.key < $1.key }.map { "\($0.key)h \($0.value)" }.joined(separator: ", "))
        }
        lines.append("overlaps (pairs of sets, minutes) by station and hour:")
        for (station, hours) in counts.sorted(by: { $0.key < $1.key }) {
            lines.append("\(station): total \(hours.values.reduce(0, +)); " + hours.sorted { $0.key < $1.key }.map { "\($0.key)h \($0.value)" }.joined(separator: ", "))
        }
        lines.append("latest each set ran, minutes: " + late.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value / 60)" }.joined(separator: ", "))
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
