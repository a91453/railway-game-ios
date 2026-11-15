import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// BALANCE-RECENT (2026-11-15): the rules merged since 0.6.0 (131) whose
/// balance had not been measured, each played on and off in the same world
/// (`economy-balance`, §3): passengers who give up waiting (decision 731),
/// the annual taxes (decisions 734, 736), the event venues (768) and the
/// night markets' hours (769). It asserts nothing and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     RECENT_RULES_REPORT=720 swift test -c release --skip-build \
///       --filter 'RecentRulesBalanceReportTests/testBlankMap'
///     RECENT_RULES_REPORT=30 RECENT_RULES_LINE=trtc:BR swift test -c release --skip-build \
///       --filter 'RecentRulesBalanceReportTests/testARealLine'
///
/// `RECENT_RULES_REPORT` is the days to play. The blank map's lines are the
/// balance report's (decision 137's line between two towns, and one across
/// the first town); a real line is bought as `AirportReportTests` buys it,
/// with the map's people, under realistic rules.
@MainActor
final class RecentRulesBalanceReportTests: XCTestCase {
    private static let shownDays: Set<Int> = [1, 7, 30, 60, 90, 150, 180, 360, 450, 540, 720]

    /// The blank map, under the report's rules (every switch of a new game
    /// but the two of `NewGameOptions`): neither rule, each alone, and both.
    func testBlankMap() throws {
        let days = try requestedDays()
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let across = PlanPoint(x: towns[0].x + 6_144, y: towns[0].y)
        let worlds: [(String, GameWorld)] = [
            ("A line between two towns", try newGameLine(through: [towns[0], towns[1]])),
            ("A line across the first town", try newGameLine(through: [PlanPoint(x: towns[0].x - 6_144, y: towns[0].y), across])),
        ]
        for (title, opened) in worlds {
            var lines = ["### \(title), \(days) days", ""]
            lines.append("| Rules | Day | Balance | Fares so far | Fare trips so far | Tax paid so far | Gave up so far | Released so far | Recovered |")
            lines.append("| --- | --: | --: | --: | --: | --: | --: | --: | --: |")
            var summary = ["", "| Rules | Paid back on day | Balance on the last day | Fares | Tax paid | Gave up / released | Income tax assessed by year |", "| --- | --: | --: | --: | --: | --: | --- |"]
            for (label, patience, taxes) in [("neither", false, false), ("patience", true, false), ("annual taxes", false, true), ("both", true, true)] {
                var world = opened
                world.setPassengerPatience(patience)
                world.setAnnualTaxes(taxes)
                let cost = GameWorld.startingBalance - world.economy.balance
                var player = try reportPlayer(world)
                try player.advance(ticks: 1)
                var fares: Int64 = 0, trips: Int64 = 0, tax: Int64 = 0
                var paidBack: Int?
                for day in 1...days {
                    try player.playDay()
                    let report = player.world.financeReport(.day).previous
                    fares += report.fareRevenue.amount
                    tax += report.taxCost.amount
                    trips += player.world.accounts.days.last?.fareTrips ?? 0
                    let recovered = (player.world.economy.balance.amount - (GameWorld.startingBalance - cost).amount) * 100 / max(1, cost.amount)
                    if paidBack == nil, recovered >= 100 { paidBack = day }
                    guard Self.shownDays.contains(day) || day == days else { continue }
                    let ledger = Self.ledger(player.world)
                    lines.append("| \(label) | \(day) | \(dollars(player.world.economy.balance.amount)) | \(dollars(fares)) | \(trips) | \(dollars(tax)) | \(ledger.gaveUp) | \(ledger.released) | \(recovered)% |")
                }
                let ledger = Self.ledger(player.world)
                let assessed = player.world.accounts.years.map { "y\($0.year): \($0.incomeTaxAssessed.map { dollars($0.amount) } ?? "—")" }.joined(separator: ", ")
                summary.append("| \(label) | \(paidBack.map(String.init) ?? "—") | \(dollars(player.world.economy.balance.amount)) | \(dollars(fares)) | \(dollars(tax)) | \(ledger.gaveUp) / \(ledger.released) | \(assessed.isEmpty ? "—" : assessed) |")
            }
            print((lines + summary).joined(separator: "\n"))
        }
    }

    /// A real line with the map's people, bought under realistic rules (both
    /// rules above on, the venues and night markets of the map): as it
    /// opens, without patience, without venues, and with the night markets
    /// as the towns' sights they were before decision 769.
    func testARealLine() throws {
        let days = try requestedDays()
        let network = ProcessInfo.processInfo.environment["RECENT_RULES_LINE"] ?? "trtc:BR"
        let opened = try AirportReportTests.bought(network, data: RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file), rules: .realistic)
        let venues = opened.demandEvents?.venues ?? []
        let markets = opened.tourism?.attractions.filter { $0.kind == .nightMarket }.map(\.englishName) ?? []
        var lines = [
            "### \(network), \(days) days, realistic rules",
            "",
            "Venues on the map: \(venues.count) (\(venues.map(\.id).joined(separator: ", "))); night markets: \(markets.joined(separator: ", "))",
            "",
            "| Variant | Fares | Fare trips | Gave up / released | Events (kind, station, venue, boost, days) | Busiest event station's released |",
            "| --- | --: | --: | --- | --- | --- |",
        ]
        var hourLines: [String] = []
        let watched = Self.watchedStations(opened)
        var sights: [String] = []
        let variants: [(String, (inout GameWorld) -> Void)] = [
            ("as opened", { _ in }),
            ("no patience", { $0.setPassengerPatience(false) }),
            ("no venues", { $0.setEventVenues([]) }),
            ("night markets as towns", { world in
                guard var tourism = world.tourism else { return }
                for index in tourism.attractions.indices where tourism.attractions[index].kind == .nightMarket {
                    tourism.attractions[index].kind = .town
                }
                world.tourism = tourism
                world.passengerPlan = GameWorld.PassengerPlanCache()
            }),
            ("sight kinds as towns", { world in
                guard var tourism = world.tourism else { return }
                for index in tourism.attractions.indices where [.landmark, .museum, .temple].contains(tourism.attractions[index].kind) {
                    tourism.attractions[index].kind = .town
                }
                world.tourism = tourism
                world.passengerPlan = GameWorld.PassengerPlanCache()
            }),
        ]
        // `RECENT_RULES_VARIANTS=as opened,no venues` plays only those.
        let chosen = ProcessInfo.processInfo.environment["RECENT_RULES_VARIANTS"].map { Set($0.split(separator: ",").map(String.init)) }
        for (label, change) in variants where chosen?.contains(label) ?? true {
            var world = opened
            change(&world)
            try world.advance(ticks: 1)
            var fares: Int64 = 0, trips: Int64 = 0
            var seen: [DemandEvent] = []
            // The released passengers of each hour at the stations of the
            // night markets and the venues, summed over the days played.
            var hourly = Array(repeating: Int64(0), count: 24)
            var lastReleased = watched.reduce(Int64(0)) { $0 + world.passengerLedger(of: $1).released }
            for _ in 1...days {
                for hour in 0..<24 {
                    try world.advance(ticks: 60)
                    let now = watched.reduce(Int64(0)) { $0 + world.passengerLedger(of: $1).released }
                    hourly[hour] += now - lastReleased
                    lastReleased = now
                }
                let report = world.financeReport(.day).previous
                fares += report.fareRevenue.amount
                trips += world.accounts.days.last?.fareTrips ?? 0
                for event in world.demandEvents?.events ?? [] where !seen.contains(event) { seen.append(event) }
            }
            let ledger = Self.ledger(world)
            let names = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.id, $0.name) })
            let events = seen.filter { $0.festival == nil }.map {
                "\($0.kind.rawValue) @\(names[$0.station] ?? "?")\($0.venue.map { " [\($0)]" } ?? "") +\($0.boost / 10)% d\($0.start)–\($0.end - 1)"
            }.joined(separator: "; ")
            let busiest = seen.map(\.station).max { world.passengerLedger(of: $0).released < world.passengerLedger(of: $1).released }
            let busiestText = busiest.map { "\(names[$0] ?? "?"): \(world.passengerLedger(of: $0).released)" } ?? "—"
            lines.append("| \(label) | \(dollars(fares)) | \(trips) | \(ledger.gaveUp) / \(ledger.released) | \(events.isEmpty ? "none" : events) | \(busiestText) |")
            hourLines.append("| \(label) | " + hourly.map(String.init).joined(separator: " | ") + " |")
            do {
                // Each sight's tourists so far this year, by kind (decision
                // 772 changes the kinds' seasons and hours).
                let visited = (world.tourism?.attractions ?? []).filter { $0.thisYear > 0 }.sorted { $0.thisYear > $1.thisYear }
                sights += visited.map { "| \(label) | \($0.englishName) | \($0.kind.rawValue) | \($0.thisYear) | \($0.thisYear / Int64(days)) |" }
            }
        }
        print(lines.joined(separator: "\n"))
        print("\nReleased by hour at the stations by a night market or a venue (\(watched.compactMap { opened.station(id: $0)?.name }.joined(separator: ", "))):\n")
        print("| Variant | " + (0..<24).map { "\($0)" }.joined(separator: " | ") + " |")
        print("| --- |" + String(repeating: " --: |", count: 24))
        print(hourLines.joined(separator: "\n"))
        print("\nSights' tourists:\n\n| Variant | Sight | Kind | Tourists | A day |\n| --- | --- | --- | --: | --: |")
        print(sights.joined(separator: "\n"))
    }

    /// The stations a night market's or an event venue's crowd comes to.
    private static func watchedStations(_ world: GameWorld) -> [StationID] {
        var points = world.tourism?.attractions.filter { $0.kind == .nightMarket }.map(\.point) ?? []
        points += world.demandEvents?.venues.map(\.point) ?? []
        var stations: [StationID] = []
        for point in points {
            for station in world.festivalStations(near: point).prefix(1) where !stations.contains(station) { stations.append(station) }
        }
        return stations
    }

    private static func ledger(_ world: GameWorld) -> (released: Int64, gaveUp: Int64) {
        world.stations.reduce((Int64(0), Int64(0))) {
            let ledger = world.passengerLedger(of: $1.id)
            return ($0.0 + ledger.released, $0.1 + ledger.gaveUp)
        }
    }

    private func requestedDays() throws -> Int {
        guard let value = ProcessInfo.processInfo.environment["RECENT_RULES_REPORT"] else {
            throw XCTSkip("set RECENT_RULES_REPORT=<days> to print the recent rules' balance report")
        }
        return try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil }, "RECENT_RULES_REPORT is a whole number of days")
    }

    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
