import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The TRA demo's weekday (decision 240), from 07:00 to half past seven
/// the next morning, minute by minute, as the high-speed demo's day is
/// checked (``HighSpeedDemoDayTests``): its sets keep to the real day,
/// never two on one track at once and never against their way's track, and
/// stand in the depots at night. A day takes minutes in a debug build: CI
/// runs it in the high-speed demo's day's shard (`campaigns-16`,
/// `.github/scripts/swift-shards.sh`).
final class TRADemoDayTests: XCTestCase {
    struct Day {
        var overlaps: [String] = []
        var against: [String] = []
        var late: [String: Int64] = [:]
        var night: [String] = []
        var world: GameWorld
    }

    private static let day: Result<Day, Error> = Result {
        var world = try TRADemoTests.opened.get()
        let tracks = try TRADemoTests.built.get().tracks
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
                for overlap in HighSpeedDemoDayTests.overlaps(in: world) {
                    let names = [overlap.trains.0, overlap.trains.1].map { world.train(id: $0)?.name ?? "?" }
                    day.overlaps.append("\(minute / 60 % 24):\(minute % 60) \(names[0]) and \(names[1]) on \(overlap.edge)")
                }
            }
            for train in world.trains where train.execution != nil {
                day.late[train.name] = max(day.late[train.name] ?? 0, world.lateness(of: train.id) ?? 0)
                guard case .onEdge(let traversal, _)? = train.position else { continue }
                if tracks.isAgainst(traversal) { day.against.append("\(train.name) at \(minute / 60 % 24):\(minute % 60)") }
            }
        }
        day.world = world
        return day
    }

    /// No set runs against its way's track, none is more than half an
    /// hour late, no run is dropped, and the next morning's runs leave
    /// again.
    func testItsSetsKeepToTheRealDay() throws {
        let day = try Self.day.get()
        XCTAssertEqual(day.against, [], "against its way's track")
        let latest = day.late.values.max() ?? 0
        XCTAssertLessThan(latest, HighSpeedDemoDayTests.latestAllowed, "\(day.late.filter { $0.value >= HighSpeedDemoDayTests.latestAllowed })")
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

    /// From 07:00 to 03:00 no two sets' bodies are ever on the same edge
    /// at once, and at 03:00 every set stands in a depot on a siding of
    /// its own.
    func testNoTwoSetsOverlapAllDay() throws {
        let day = try Self.day.get()
        XCTAssertEqual(day.overlaps, [], "two sets on one edge")
        XCTAssertEqual(day.night, [], "at night")
    }
}
