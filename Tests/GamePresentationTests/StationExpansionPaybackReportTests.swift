@testable import GameCore
@testable import GamePresentation
import Foundation
import XCTest

/// Decision 506's payback in a new game, on request only
/// (`STATION_EXPANSION_PAYBACK=<days>`): a world played as it is beside the
/// same world where every station that may expand (busy and full lately)
/// does, each morning, with
/// the money given (so the price does not change what else runs). Prints
/// each day's fares and the people turned away by a full station in both,
/// and the days the extra fares take to repay what was spent.
@MainActor
final class StationExpansionPaybackReportTests: XCTestCase {
    /// Decision 137's line between the first two towns of seed 1.
    func testALineBetweenTwoTowns() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        try report(try newGameLine(through: [towns[0], towns[1]]), title: "A line between two towns (seed 1)")
    }

    /// The demo map: several lines through the towns of seed 1.
    func testTheDemoMap() throws {
        try report(DemoWorld.make(in: .english), title: "The demo map")
    }

    private func report(_ start: GameWorld, title: String) throws {
        guard let value = ProcessInfo.processInfo.environment["STATION_EXPANSION_PAYBACK"] else {
            throw XCTSkip("set STATION_EXPANSION_PAYBACK=<days> to print the payback report")
        }
        let days = try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil })
        var plain = start, expanded = start
        var spent = Money.zero
        var steps: [String] = []
        var rows = ["### \(title)", "", "| day | fares as is | fares expanded | turned away as is | turned away expanded |", "| --: | --: | --: | --: | --: |"]
        var extra: Int64 = 0
        var payback: Int?
        for day in 1...days {
            let overflowPlain = plain.passengers.reduce(0) { $0 + $1.overflowed }
            let overflowExpanded = expanded.passengers.reduce(0) { $0 + $1.overflowed }
            // Expand each morning wherever the game allows it: yesterday's
            // people, and full yesterday or today.
            if day > 1 {
                for station in expanded.stations {
                    while let next = expanded.nextStationExpansion(of: station.id),
                          expanded.stationExpansionPeople(of: station.id) >= next.threshold,
                          expanded.stationWasFullLately(station.id) {
                        expanded.economy.earn(next.price)
                        try expanded.expandStation(at: station.id)
                        spent = spent + next.price
                        steps.append("day \(day): \(station.name) → \(next.capacity)")
                    }
                }
            }
            try plain.advance(ticks: 1_440)
            try expanded.advance(ticks: 1_440)
            let today = plain.clock.now.seconds / 86_400 - 1
            let farePlain = plain.accounts.days.first { $0.day == today }?.fareRevenue.amount ?? 0
            let fareExpanded = expanded.accounts.days.first { $0.day == today }?.fareRevenue.amount ?? 0
            if spent > .zero {
                extra += fareExpanded - farePlain
                if payback == nil, extra >= spent.amount { payback = day }
            }
            rows.append("| \(day) | \(farePlain) | \(fareExpanded) | \(plain.passengers.reduce(0) { $0 + $1.overflowed } - overflowPlain) | \(expanded.passengers.reduce(0) { $0 + $1.overflowed } - overflowExpanded) |")
        }
        rows.append("")
        rows.append("expansions: \(steps.isEmpty ? "none" : steps.joined(separator: "; "))")
        rows.append("spent \(spent.amount) cents, extra fares since \(extra) cents, repaid on day \(payback.map(String.init) ?? "not within \(days) days")")
        print(rows.joined(separator: "\n"))
    }
}
