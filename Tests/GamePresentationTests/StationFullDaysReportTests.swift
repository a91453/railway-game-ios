@testable import GameCore
@testable import GamePresentation
import Foundation
import XCTest

/// Decision 534's measure, on request only (`STATION_FULL_DAYS=<days>`):
/// which stations turn passengers away for want of room, on which days,
/// with their people a day, so the rule "full on K of the last W days" can
/// be set against how often stations really fill. Prints one row a station
/// that was ever full, one column a day (the passengers turned away that
/// day, `·` for none), and, for each candidate rule, the days on which it
/// would have let the station expand.
///
///     STATION_FULL_DAYS=30 swift test -c release --skip-build \
///       --filter StationFullDaysReportTests
///
/// `STATION_FULL_DAYS_SAVE=<file>` reports a save instead of the new games
/// (the player's file stays out of the repository).
@MainActor
final class StationFullDaysReportTests: XCTestCase {
    private struct SharedFile: Decodable {
        let game: SavedGame
    }

    /// Decision 137's line between the first two towns of seed 1.
    func testALineBetweenTwoTowns() throws {
        guard ProcessInfo.processInfo.environment["STATION_FULL_DAYS_SAVE"] == nil else { throw XCTSkip("a save is reported") }
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        try report(try newGameLine(through: [towns[0], towns[1]]), title: "A line between two towns (seed 1)")
    }

    /// The demo map: several lines through the towns of seed 1.
    func testTheDemoMap() throws {
        guard ProcessInfo.processInfo.environment["STATION_FULL_DAYS_SAVE"] == nil else { throw XCTSkip("a save is reported") }
        try report(DemoWorld.make(in: .english), title: "The demo map")
    }

    /// A player's save, from its next midnight.
    func testASave() throws {
        guard let path = ProcessInfo.processInfo.environment["STATION_FULL_DAYS_SAVE"] else {
            throw XCTSkip("set STATION_FULL_DAYS_SAVE=<file> to report a save")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game)
            ?? JSONDecoder().decode(SavedGame.self, from: data)
        var world = saved.world
        world.setSpeed(.normal)
        let toMidnight = 86_400 - world.clock.now.seconds % 86_400
        try world.advance(ticks: Int(toMidnight / 60))
        try report(world, title: "Save \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    private func report(_ start: GameWorld, title: String) throws {
        guard let value = ProcessInfo.processInfo.environment["STATION_FULL_DAYS"] else {
            throw XCTSkip("set STATION_FULL_DAYS=<days> to print the full-days report")
        }
        let days = try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil })
        var world = start
        let firstDay = world.clock.now.seconds / 86_400
        var turnedAway: [StationID: [Int64]] = [:]
        var people: [StationID: [Int64]] = [:]
        for _ in 0..<days {
            let before = Dictionary(uniqueKeysWithValues: world.passengers.map { ($0.station, $0.overflowed) })
            try world.advance(ticks: 1_440)
            let day = world.clock.now.seconds / 86_400 - 1
            for station in world.stations where !station.isDepot {
                let after = world.passengers.first { $0.station == station.id }?.overflowed ?? 0
                turnedAway[station.id, default: []].append(after - (before[station.id] ?? 0))
                people[station.id, default: []].append(world.stationCommercePeople(of: station.id, onDay: day))
            }
        }
        var rows = ["### \(title), days \(firstDay)–\(firstDay + Int64(days) - 1)", ""]
        let full = world.stations.filter { (turnedAway[$0.id] ?? []).contains { $0 > 0 } }
        rows.append("stations \(world.stations.filter { !$0.isDepot }.count), ever full \(full.count)")
        rows.append("")
        rows.append("| station | max people/day | full days | turned away by day |")
        rows.append("| --- | --: | --: | --- |")
        for station in full {
            let away = turnedAway[station.id]!
            rows.append("| \(station.id.rawValue) \(station.name) | \(people[station.id]!.max() ?? 0) | \(away.filter { $0 > 0 }.count) | \(away.map { $0 > 0 ? String($0) : "·" }.joined(separator: " ")) |")
        }
        rows.append("")
        // Each candidate: the days (1-based) on which the station had been
        // full on at least `count` of the `window` days ending yesterday.
        let candidates = [(1, 2), (2, 3), (2, 5), (3, 5), (3, 7), (4, 7), (5, 7)]
        rows.append("| rule (full on K of the last W days) | stations ever open | station-days open | open stations: first day open |")
        rows.append("| --- | --: | --: | --- |")
        for (count, window) in candidates {
            var opened: [String] = []
            var stationDays = 0
            for station in full {
                let away = turnedAway[station.id]!
                var openDays: [Int] = []
                for day in 1..<days {
                    let recent = away[max(0, day - window)..<day].filter { $0 > 0 }.count
                    if recent >= count { openDays.append(day + 1) }
                }
                stationDays += openDays.count
                if let first = openDays.first { opened.append("\(station.name) \(first) (\(openDays.count)d)") }
            }
            rows.append("| \(count) of \(window) | \(opened.count) | \(stationDays) | \(opened.joined(separator: ", ")) |")
        }
        print(rows.joined(separator: "\n"))
    }
}
