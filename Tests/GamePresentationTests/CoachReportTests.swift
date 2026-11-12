import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 706: what the intercity coaches take from a real line bought
/// and bring to it, printed as Markdown. It asserts nothing and runs only
/// on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     COACH_REPORT=3 swift test -c release --skip-build --filter CoachReportTests
///
/// `COACH_REPORT` is the days to play (1 to 60); `COACH_ONLY` picks one
/// line (`tymc:A`, `trtc:BR`). Each line is bought in a real-world game
/// round it, as `AirportReportTests` does, and played minute by minute
/// twice from the same minute: without the map's coach stops and with.
@MainActor
final class CoachReportTests: XCTestCase {
    func testWhatTheCoachesTakeAndBring() throws {
        guard let value = ProcessInfo.processInfo.environment["COACH_REPORT"] else {
            throw XCTSkip("set COACH_REPORT=<days> to print the coach report")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (1...60).contains($0) ? $0 : nil }, "COACH_REPORT is 1 to 60 days")
        let only = ProcessInfo.processInfo.environment["COACH_ONLY"]
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let network = try XCTUnwrap(data.coaches)
        var rows = ["| Line | Coaches | Day | Trips | Fares | Operating profit | Fullest train | Station full or gave up | Coach stops: on the map / with a station | Coach passengers at those | Riders on the trains | Pairs with a coach | Trips a day the coaches take |",
                    "| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |"]
        var stops: [String] = []
        for line in AirportReportTests.networks where only == nil || only == line {
            let start = try AirportReportTests.bought(line, data: data)
            for coaches in [false, true] {
                var world = coaches ? CoachCatalog.withCoachStops(start, network: network) : start
                world.setLineAccounts(true)
                var before: Int64 = 0
                // The tick that starts at midnight counts the day that ended.
                try world.advance(ticks: 1)
                for day in 1...days {
                    for _ in 0..<1_440 { try world.advance(ticks: 1) }
                    let account = world.accounts.days.last
                    let peak = world.lines.compactMap { world.lineYesterday($0.id)?.peakLoad }.max() ?? 0
                    let lost = world.stations.map { world.passengerLedger(of: $0.id) }.map { $0.overflowed + $0.abandoned }.reduce(0, +)
                    let served = world.coachDays().filter { $0.station != nil }
                    let taken = world.stations.map { world.tripsTakenByCoaches(from: $0.id) }.reduce(0, +)
                    let pairs = world.coachRivals().values.map(\.count).reduce(0, +)
                    rows.append("| \(line) | \(coaches ? "with" : "without") | \(day) | \(world.lastDayTrips()) | \(account?.fareRevenue.moneyText ?? "") | "
                        + "\(Money(account.map(airportReportProfit) ?? 0).moneyText) | \(peak / 10)% | \(lost - before) | "
                        + "\(world.coachStops.count) / \(served.count) | \(served.map(\.stop.yesterdayPassengers).reduce(0, +)) | "
                        + "\(world.coachStops.map(\.yesterdayRiders).reduce(0, +)) | \(pairs) | \(taken) |")
                    before = lost
                    FileHandle.standardError.write(Data("\(rows.last!)\n".utf8))
                    if coaches, day == days {
                        stops.append("- \(line): " + served.map {
                            "\($0.stop.name) (\($0.station.flatMap { world.station(id: $0)?.name } ?? "")) \($0.stop.yesterdayPassengers) / \($0.stop.yesterdayRiders)"
                        }.joined(separator: "; "))
                    }
                }
            }
        }
        print("### What the coaches take and bring (\(days) days)\n\n" + rows.joined(separator: "\n")
            + "\n\nThe coach stops a station serves, coach passengers / riders of the last day:\n\n" + stops.joined(separator: "\n"))
    }
}
