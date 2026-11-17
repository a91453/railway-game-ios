import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 818: what Rovaniemi's two lines cost to buy and what they earn,
/// and how many minutes a train waits in a deadlock, printed as Markdown
/// only when asked:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     ROVANIEMI_REPORT=30 swift test -c release --skip-build \
///       --filter RovaniemiReportTests
///
/// `ROVANIEMI_REPORT` is the days to play (1 to 360), minute by minute, as
/// the launcher starts the map (its rules as a new game's, realistic;
/// `ROVANIEMI_SIMPLE=1` for the simple ones). Each line is bought alone on
/// its own game, then both in one, with NT$1,000 million in the bank so the
/// cash never runs short; the price is set against what a standard opening
/// can reach (its cash and the most it may borrow).
///
/// Decision 828: `ROVANIEMI_ONLY=vr:MUL+vr:KJA` plays only those purchases,
/// in that order; `ROVANIEMI_CITY=hk` plays Hong Kong's map instead
/// (`hkmtr:SIL` and `hkmtr:TCL` without `ROVANIEMI_ONLY`), and
/// `ROVANIEMI_FAR_OFF=1` turns far demand off, as before decision 828.
@MainActor
final class RovaniemiReportTests: XCTestCase {
    private static let checkpoints: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 14, 30, 60, 90, 180, 360]

    func testWhatTheLinesCostAndEarn() throws {
        guard let value = ProcessInfo.processInfo.environment["ROVANIEMI_REPORT"] else {
            throw XCTSkip("set ROVANIEMI_REPORT=<days> to print Rovaniemi's line report")
        }
        let days = try XCTUnwrap(Int(value).flatMap { (1...360).contains($0) ? $0 : nil }, "ROVANIEMI_REPORT is 1 to 360 days")
        let simple = ProcessInfo.processInfo.environment["ROVANIEMI_SIMPLE"] != nil
        let reach = GameWorld.startingBalance + CompanyAccounts.maximumLoan
        var prices = [
            "| Line | Riders a day (paid for) | Land | Building | Trains | Riders' value | Price | ÷ opening reach (\(reach.moneyText)) |",
            "| --- | --: | --: | --: | --: | --: | --: | --: |",
        ]
        var summary = [
            "| Bought | Trips a day, days \(min(days, 30))–\(days) | Fares a day | Operating profit a day | Payback (price ÷ profit) | Cash change by day \(days) | Deadlock minutes |",
            "| --- | --: | --: | --: | --: | --: | --: |",
        ]
        var trace = [
            "| Bought | Day | Trips | Fares | Operating profit | Each line: boardings, departures | Each line's day | Deadlock minutes (first) |",
            "| --- | --: | --: | --: | --: | --- | --- | --- |",
        ]
        let environment = ProcessInfo.processInfo.environment
        let hongKong = environment["ROVANIEMI_CITY"] == "hk"
        let only = environment["ROVANIEMI_ONLY"].map { [$0.split(separator: "+").map(String.init)] }
        let all = hongKong ? [["hkmtr:SIL"], ["hkmtr:TCL"]] : [["vr:KJA"], ["vr:MUL"], ["vr:KJA", "vr:MUL"], ["vr:MUL", "vr:KJA"]]
        for ids in only ?? all {
            let started = Date()
            let session = try Self.rovaniemi(simple: simple, hongKong: hongKong, far: environment["ROVANIEMI_FAR_OFF"] == nil)
            var paid = Money.zero
            for id in ids {
                let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
                let offer = session.realLineOffer(for: line)
                let price = try XCTUnwrap(offer.price, "\(id): \(offer.problem ?? "")")
                let acquisition = try XCTUnwrap(offer.acquisition, id)
                if ids.count == 1 {
                    prices.append(
                        "| \(id) | \(acquisition.dailyRiders) | \(price.land.moneyText) | \(price.building.moneyText) | \(price.trains.moneyText) | "
                            + "\(price.riders.moneyText) | \(price.total.moneyText) | " + String(format: "%.2f", Double(price.total.amount) / Double(reach.amount)) + " |"
                    )
                }
                paid = paid + price.total
                XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
            }
            var played = session.world
            // Decision 179's accounts, for each line's own day.
            played.setLineAccounts(true)
            let lines = try ids.map { id in try XCTUnwrap(played.acquisition(of: id)?.line, id) }
            let before = played.economy.balance.amount
            var profits: [Int64] = [], fares: [Int64] = [], trips: [Int64] = []
            var stuck = 0
            for day in 1...days {
                var stuckToday: [String] = []
                for minute in 0..<(24 * 60) {
                    try played.advance(ticks: 1)
                    if !played.deadlockedTrains().isEmpty {
                        stuckToday.append(String(format: "%02d:%02d", (minute + 1) / 60, (minute + 1) % 60))
                    }
                }
                stuck += stuckToday.count
                let account = played.accounts.days.last
                profits.append(account.map(operatingProfit) ?? 0)
                fares.append(account?.fareRevenue.amount ?? 0)
                trips.append(played.lastDayTrips())
                if Self.checkpoints.contains(day) || !stuckToday.isEmpty {
                    trace.append(
                        "| \(ids.joined(separator: " + ")) | \(day) | \(trips.last!) | \(Money(fares.last!).moneyText) | \(Money(profits.last!).moneyText) | "
                            + lines.enumerated().map { "\(ids[$0.offset]) \(played.lineYesterday($0.element)?.boardings ?? 0), \(played.lineYesterday($0.element)?.departures ?? 0)" }
                            .joined(separator: "; ") + " | "
                            + lines.enumerated().map { entry in
                                let tally = played.lineYesterday(entry.element) ?? LineTally()
                                return "\(ids[entry.offset]) fares \(tally.fareRevenue.moneyText), operating \(tally.operatingCost.moneyText), "
                                    + "upkeep \(tally.maintenanceCost.moneyText), energy \(tally.energyCost.moneyText), staff \(tally.staffCost.moneyText), "
                                    + "\(tally.trainDistance / (1_000 * WorldCoordinate.unitsPerMetre)) train-km"
                            }.joined(separator: "; ") + " | "
                            + "\(stuckToday.count)\(stuckToday.isEmpty ? "" : " (" + stuckToday.prefix(4).joined(separator: ", ") + ")") |"
                    )
                }
            }
            let from = min(days, 30) - 1
            func average(_ values: [Int64]) -> Int64 {
                let slice = values.dropFirst(from)
                return slice.isEmpty ? 0 : slice.reduce(0, +) / Int64(slice.count)
            }
            let profit = average(profits)
            summary.append(
                "| \(ids.joined(separator: " + ")) | \(average(trips)) | \(Money(average(fares)).moneyText) | \(Money(profit).moneyText) | "
                    + "\(profit > 0 ? "\(paid.amount / profit) days" : "never") | \(Money(played.economy.balance.amount - before).moneyText) | \(stuck) |"
            )
            FileHandle.standardError.write(Data("\(summary.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print(
            "### \(hongKong ? "Hong Kong" : "Rovaniemi")'s lines (\(days) days, \(simple ? "simple" : "realistic") rules)\n\n" + prices.joined(separator: "\n")
                + "\n\n" + summary.joined(separator: "\n") + "\n\n" + trace.joined(separator: "\n")
        )
    }

    /// ``RovaniemiRailwaysTests/rovaniemi()``, or Hong Kong's map when
    /// `hongKong`, under the simple rules when `simple`, far demand off
    /// unless `far`.
    private static func rovaniemi(simple: Bool, hongKong: Bool = false, far: Bool = true) throws -> GameSession {
        let ground = try hongKong ? HongKongMapTests.ground() : RovaniemiRailwaysTests.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        if simple { NewGameRules.simple.apply(to: &world) }
        world.setFarDemand(far)
        try world.mapGround()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try hongKong ? HongKongRailwaysTests.railways() : RovaniemiRailwaysTests.railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        return session
    }
}

/// A day's fares and other income less its running costs (the finance
/// report's operating profit, as `AcquisitionReportTests` reads it).
private func operatingProfit(_ day: DayAccount) -> Int64 {
    (day.fareRevenue + day.freightRevenue + day.propertyRevenue - day.totalCost - day.propertyCost).amount
}
