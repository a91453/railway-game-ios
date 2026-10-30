import Foundation
@testable import GameCore
import XCTest

/// Decision 504: who waits at the stations of a player's save over a few
/// days, and what the line carries and earns, to compare a build before and
/// after those still waiting go home at 04:00. The file is the player's and
/// stays out of the repository; run on request:
///
///     DAILY_WAIT_SAVE=<file> swift test --filter DailyWaitReportTests
///
/// `DAILY_WAIT_SAVE` is a save (`SavedGame`, or a shared `.alongtheline`
/// file holding one under `game`); `DAILY_WAIT_DAYS` how many days to run
/// (default 3). It prints a row every three hours: who waits, the longest
/// wait, and the running totals of arrivals, abandonments and refusals for
/// a full station; then each finished day's fares. Just before 04:00 it
/// adds who waits by how many stops their ride goes, and how long they
/// have waited (boarding takes the farthest first: decision 504's next
/// step).
final class DailyWaitReportTests: XCTestCase {
    private struct SharedFile: Decodable {
        let game: SavedGame
    }

    func testWhoWaitsOverTheDays() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["DAILY_WAIT_SAVE"] else {
            throw XCTSkip("set DAILY_WAIT_SAVE=<file> to report who waits in a save")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game)
            ?? JSONDecoder().decode(SavedGame.self, from: data)
        let days = Int64(environment["DAILY_WAIT_DAYS"] ?? "") ?? 3
        var world = saved.world
        world.setSpeed(.normal)
        let start = world.clock.now.seconds
        print("stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), from day \(start / 86_400) \(start % 86_400 / 60) min")
        print("| time | waiting | longest wait (min) | stations with a wait over 2 h | arrived | abandoned | overflowed |")
        print("| --- | --: | --: | --: | --: | --: | --: |")
        func row() {
            let now = world.clock.now
            var waiting: Int64 = 0, longest: Int64 = 0, long = 0
            for record in world.passengers {
                waiting += record.waitingCount
                if let first = record.waiting.first {
                    let wait = (now.seconds - first.since.seconds) / 60
                    longest = max(longest, wait)
                    if wait > 120 { long += 1 }
                }
            }
            let arrived = world.passengers.reduce(0) { $0 + $1.arrived }
            let abandoned = world.passengers.reduce(0) { $0 + $1.abandoned }
            let overflowed = world.passengers.reduce(0) { $0 + $1.overflowed }
            let day = now.seconds / 86_400, minute = now.seconds % 86_400 / 60
            print("| day \(day) \(minute / 60):\(String(format: "%02d", minute % 60)) | \(waiting) | \(longest) | \(long) | \(arrived) | \(abandoned) | \(overflowed) |")
        }
        func byStops() {
            let now = world.clock.now
            let buckets = ["1", "2", "3-5", "6+"]
            var count = [Int64](repeating: 0, count: 4), minutes = [Int64](repeating: 0, count: 4)
            for record in world.passengers {
                for group in record.waiting {
                    guard let stops = world.lines.first(where: { $0.id == group.line })?.stops,
                          let from = stops.firstIndex(of: record.station),
                          let to = stops.firstIndex(of: group.destination) else { continue }
                    let hops = abs(to - from)
                    let bucket = hops <= 1 ? 0 : hops == 2 ? 1 : hops <= 5 ? 2 : 3
                    count[bucket] += group.count
                    minutes[bucket] += group.count * (now.seconds - group.since.seconds) / 60
                }
            }
            print("| stops ridden | waiting | mean wait (min) |")
            print("| --- | --: | --: |")
            for index in buckets.indices {
                print("| \(buckets[index]) | \(count[index]) | \(count[index] > 0 ? minutes[index] / count[index] : 0) |")
            }
        }
        row()
        let end = start + days * 86_400
        // A row each time the clock passes a third hour, and just before
        // and after 04:00.
        func mark(_ seconds: Int64) -> Int64 {
            let day = seconds / 86_400, second = seconds % 86_400
            let window: Int64 = second >= 4 * 3_600 + 60 ? 2 : second >= 4 * 3_600 - 60 ? 1 : 0
            return day * 100 + second / (3 * 3_600) * 3 + window
        }
        while world.clock.now.seconds < end {
            let before = mark(world.clock.now.seconds)
            try world.advance(ticks: 1)
            let after = mark(world.clock.now.seconds)
            if after != before {
                row()
                if after % 100 == 4 { byStops() }  // 03:59, the minute before 04:00
            }
        }
        print("| day | fares |")
        print("| --- | --: |")
        for day in world.accounts.days where day.day >= start / 86_400 {
            print("| \(day.day) | \(day.fareRevenue.amount) |")
        }
    }
}
