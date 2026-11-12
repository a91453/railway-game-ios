import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// COACH-HEALTH (decision 706 §2, `docs/research/COACH_HEALTH_2026-11-12.md`):
/// what the intercity coaches take and bring on the maps and networks the
/// whole-Taiwan report (`CoachReportTests`) did not reach, printed as
/// Markdown. It asserts nothing and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     COACH_HEALTH=1 COACH_HEALTH_ONLY=south swift test -c release --skip-build --filter CoachHealthReportTests
///
/// `COACH_HEALTH` is the days to play (0 to 5; 0 reads only the day's
/// demand); `COACH_HEALTH_ONLY` picks one scenario of ``scenarios`` by its
/// name. Each world is the one a real-world game has where the player
/// points (the whole island, `RealWorldExpansion`), in the demo mode so the
/// land is read as stations come and nothing needs buying first. Its
/// network is the real lines of some systems with a station in a box, laid
/// as the demo mode lays them (decision 351: every station, a train every
/// few minutes calling at all of them), and the real lines on sale bought
/// as the player buys them. The coach stops are the map's, as a game gets
/// them (`CoachCatalog.stops`).
@MainActor
final class CoachHealthReportTests: XCTestCase {
    struct Scenario {
        let name: String
        /// Where the player points.
        let pick: (latitude: Double, longitude: Double)
        /// The box whose real lines are laid: south, west, north, east.
        var box: (south: Double, west: Double, north: Double, east: Double)?
        /// The systems laid in the box; empty for every one but the Taiwan
        /// Railway, the High Speed Rail and the Alishan Forest Railway.
        var systems: Set<String> = []
        /// The lines on sale bought, in this order.
        var buys: [String] = []
    }

    static let taiwan = (south: WholeTaiwan.south, west: WholeTaiwan.west, north: WholeTaiwan.north, east: WholeTaiwan.east)
    static let scenarios: [Scenario] = [
        // Central Taiwan: Miaoli to Chiayi, the Taiwan Railway and the Taichung Metro.
        Scenario(name: "central", pick: (24.137066, 120.686867), box: (23.40, 120.20, 24.75, 121.10), systems: ["tra_sched", "tmrt"]),
        // The south: Tainan, Kaohsiung and Pingtung, the Taiwan Railway and the Kaohsiung Metro.
        Scenario(name: "south", pick: (22.639532, 120.302559), box: (22.30, 120.00, 23.40, 120.80), systems: ["tra_sched", "krtc"]),
        // The east: Hualien and Taitung.
        Scenario(name: "east", pick: (23.992700, 121.601200), box: (22.30, 120.85, 24.40, 121.75), systems: ["tra_sched"]),
        // The whole island with the Taiwan Railway alone.
        Scenario(name: "tra", pick: (25.047882, 121.517219), box: taiwan, systems: ["tra_sched"]),
        // A metropolis with its metro alone.
        Scenario(name: "metro-taipei", pick: (25.047882, 121.517219), box: (24.90, 121.30, 25.22, 121.70)),
        Scenario(name: "metro-taichung", pick: (24.137066, 120.686867), box: (23.95, 120.45, 24.35, 120.85), systems: ["tmrt"]),
        Scenario(name: "metro-kaohsiung", pick: (22.639532, 120.302559), box: (22.45, 120.15, 22.90, 120.50), systems: ["krtc"]),
        // An early save: one or two of the lines on sale, nothing else.
        Scenario(name: "early-jiji", pick: (23.83, 120.78), buys: ["JIJI"]),
        Scenario(name: "early-shalun", pick: (22.95, 120.25), buys: ["SHALUN"]),
        Scenario(name: "early-hsinchu", pick: (24.80, 121.03), buys: ["LIUJIA", "NEIWAN"]),
        Scenario(name: "early-ruifang", pick: (25.08, 121.80), buys: ["PINGXI", "SHENAO"]),
        Scenario(name: "early-kaohsiung-lrt", pick: (22.639532, 120.302559), buys: ["krtc:C"]),
        Scenario(name: "early-sanying", pick: (24.95, 121.38), buys: ["sanying:LB"]),
        Scenario(name: "early-airport-mrt", pick: (25.02, 121.30), buys: ["tymc:A"]),
        Scenario(name: "early-wenhu", pick: (25.047882, 121.517219), buys: ["trtc:BR"]),
    ]

    func testWhatTheCoachesDoOnTheOtherMaps() async throws {
        guard let value = ProcessInfo.processInfo.environment["COACH_HEALTH"] else {
            throw XCTSkip("set COACH_HEALTH=<days> to print the coach health report")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (0...5).contains($0) ? $0 : nil }, "COACH_HEALTH is 0 to 5 days")
        let only = ProcessInfo.processInfo.environment["COACH_HEALTH_ONLY"]
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let network = try XCTUnwrap(data.coaches)
        func note(_ text: String) { FileHandle.standardError.write(Data("\(text)\n".utf8)) }
        func percent(_ part: Int64, of whole: Int64) -> String {
            whole == 0 ? "0.0%" : String(format: "%+.1f%%", Double(part) * 100 / Double(whole))
        }
        func share(_ part: Int64, of whole: Int64) -> String {
            whole == 0 ? "0.0%" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
        }
        var out: [String] = []
        for scenario in Self.scenarios where only == nil || only == scenario.name {
            let began = Date()
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: scenario.pick.latitude, longitudeDegrees: scenario.pick.longitude))
            var world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights,
                placeNames: data.placeNames
            ), demo: true)
            func session(of world: GameWorld) -> GameSession {
                let session = GameSession(world: world, language: .english)
                session.railways = railways
                session.population = data.population
                session.places = data.places
                session.water = data.water
                session.heights = data.heights
                session.coverage = data.coverage
                session.news.isDemo = true
                return session
            }
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            if let box = scenario.box {
                let playing = session(of: world)
                let a = frame.worldPosition(latitude: box.north, longitude: box.west), b = frame.worldPosition(latitude: box.south, longitude: box.east)
                let view = WorldRegion(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y))
                let systems = scenario.systems
                let laid = await playing.layDemoRealLines(in: view, routes: .max, anyWidth: true) {
                    systems.isEmpty ? !["tra_sched", "thsr_sched", "afr_sched"].contains($0.system.id) : systems.contains($0.system.id)
                }
                note("\(scenario.name): laid \(laid.map { "\($0.lines) lines, \($0.stations) stations, \($0.missed) missed" } ?? "nothing") in "
                    + "\(Int(Date().timeIntervalSince(began))) s: \(playing.message?.text ?? "")")
                playing.readLandRoundStations()
                playing.refreshTransfers()
                world = playing.world
            }
            for buy in scenario.buys {
                let playing = session(of: world)
                let line = try XCTUnwrap(playing.buyableRealLines.first { $0.network == buy || $0.id == buy }, "\(scenario.name): \(buy) is not on sale")
                XCTAssertTrue(playing.acquireRealLine(playing.realLineOffer(for: line)), "\(scenario.name): \(buy): \(playing.message?.text ?? "")")
                playing.refreshTransfers()
                world = playing.world
            }
            var with = world
            with.setCoachStops(CoachCatalog.stops(of: network, in: frame, bounds: world.bounds))
            let stations = with.stations.filter { !$0.isDepot }

            // The day's demand, pair by pair, as `with` stands: read at noon
            // of the first day played (a line just laid has no train out
            // yet, and so no way to ride), or at once with no day played.
            func table(_ with: GameWorld) {
                let rivals = with.coachRivals()
                struct Pair {
                    let from: String, to: String
                    let kept: Int64, taken: Int64, fare: Int64, minutes: Int64
                    let rival: CoachLink
                    var share: Int64 { taken * 1_000 / max(1, kept + taken) }
                }
                var pairs: [Pair] = []
                var trips: Int64 = 0, taken: Int64 = 0, fares: Int64 = 0, faresTaken: Int64 = 0
                for station in stations {
                    for detail in with.dailyDemandDetails(from: station.id) {
                        let fast = detail.route?.legs.contains { with.isHighSpeedLine($0.line) } ?? false
                        let fare = with.tripFare(from: station.id, to: detail.destination, highSpeed: fast)?.amount ?? 0
                        trips += detail.trips
                        taken += detail.byCoach
                        fares += detail.trips * fare
                        faresTaken += detail.byCoach * fare
                        if let rival = rivals[station.id]?[detail.destination] {
                            pairs.append(Pair(from: station.name, to: with.station(id: detail.destination)?.name ?? "", kept: detail.trips,
                                              taken: detail.byCoach, fare: fare, minutes: detail.route?.totalMinutes ?? 0, rival: rival))
                        }
                    }
                }
                let losing = pairs.filter { $0.taken > 0 }
                let served = with.coachDays().filter { $0.station != nil }
                let brought = served.map(\.riders).reduce(0, +)
                out.append("### \(scenario.name): \(with.lines.count) lines, \(stations.count) stations, \(with.trains.count) trains\n")
                out.append("Coach stops \(with.coachStops.count), with a station \(served.count) ("
                    + served.prefix(40).map { "\($0.stop.name) → \($0.station.flatMap { with.station(id: $0)?.name } ?? "")" }.joined(separator: "; ")
                    + "); pairs with a coach \(with.coachPairCount()), of them losing trips \(losing.count); the coaches bring \(brought) riders a day.\n")
                out.append("| A day's demand | Trips | Fares (each pair at its fare) |\n| --- | --: | --: |")
                out.append("| Without coaches | \(trips + taken) | \(Money(fares + faresTaken).moneyText) |")
                out.append("| The coaches take | \(taken) (\(share(taken, of: trips + taken))) | "
                    + "\(Money(faresTaken).moneyText) (\(share(faresTaken, of: fares + faresTaken))) |")
                out.append("| The coaches bring (riders, both ways) | \(brought) | |\n")
                if !pairs.isEmpty {
                    out.append("| From | To | Rail: minutes / fare | Coach: minutes / a day / fare | Trips without | The coach takes | Share |")
                    out.append("| --- | --- | --: | --: | --: | --: | --: |")
                    for pair in pairs.sorted(by: { $0.taken != $1.taken ? $0.taken > $1.taken : $0.kept > $1.kept }).prefix(25) {
                        out.append("| \(pair.from) | \(pair.to) | \(pair.minutes) / \(pair.fare / 100) | \(pair.rival.minutes) / \(pair.rival.dailyCoaches) / \(pair.rival.fare) | "
                            + "\(pair.kept + pair.taken) | \(pair.taken) | \(share(pair.taken, of: pair.kept + pair.taken)) |")
                    }
                    let busy = losing.filter { $0.kept + $0.taken >= 100 }.max { $0.share < $1.share }
                    let most = losing.max { $0.share < $1.share }
                    out.append("\nThe most taken of a pair: \(most.map { "\($0.from) → \($0.to) \(Double($0.share) / 10)% of \($0.kept + $0.taken)" } ?? "none"); "
                        + "of a pair with 100 trips a day or more: \(busy.map { "\($0.from) → \($0.to) \(Double($0.share) / 10)% of \($0.kept + $0.taken)" } ?? "none").\n")
                }
                note(out.joined(separator: "\n"))
            }

            guard days > 0 else {
                table(with)
                continue
            }
            // Each line's profit of a day: its fares less its costs.
            func profit(_ tally: LineTally) -> Int64 {
                (tally.fareRevenue - tally.operatingCost - tally.maintenanceCost - tally.energyCost - tally.staffCost).amount
            }
            struct Day {
                var trips: Int64 = 0, fares: Int64 = 0, profit: Int64 = 0, lost: Int64 = 0, riders: Int64 = 0, robbed: Int64 = 0
                var lines: [LineID: Int64] = [:]
            }
            var played: [Bool: [Day]] = [:]
            for coaches in [false, true] {
                var world = coaches ? with : world
                world.setLineAccounts(true)
                try world.advance(ticks: 1)
                // To the first midnight, so each day counted is a whole one.
                while world.clock.now.seconds % GameTime.secondsPerDay != 0 { try world.advance(ticks: 1) }
                try world.advance(ticks: 1)
                var before = world.stations.map { world.passengerLedger(of: $0.id) }.map { $0.overflowed + $0.abandoned }.reduce(0, +)
                for _ in 1...days {
                    var day = Day()
                    for minute in 0..<1_440 {
                        try world.advance(ticks: 1)
                        guard minute == 720 else { continue }
                        day.robbed = world.stations.map { world.tripsTakenByCoaches(from: $0.id) }.reduce(0, +)
                        if coaches, played[true] == nil { table(world) }
                    }
                    let account = world.accounts.days.last
                    let lost = world.stations.map { world.passengerLedger(of: $0.id) }.map { $0.overflowed + $0.abandoned }.reduce(0, +)
                    day.trips = world.lastDayTrips()
                    day.fares = account?.fareRevenue.amount ?? 0
                    day.profit = account.map(airportReportProfit) ?? 0
                    day.lost = lost - before
                    day.riders = world.coachStops.map(\.yesterdayRiders).reduce(0, +)
                    for line in world.lines { day.lines[line.id] = world.lineYesterday(line.id).map(profit) ?? 0 }
                    before = lost
                    played[coaches, default: []].append(day)
                    note("\(scenario.name), \(coaches ? "with" : "without"), day \(played[coaches]!.count): trips \(day.trips), fares \(Money(day.fares).moneyText), "
                        + "\(Int(Date().timeIntervalSince(began))) s")
                }
            }
            out.append("| Day | Trips: without / with | Fares: without / with | Operating profit: without / with | Station full or gave up: without / with "
                + "| Riders the coaches bring | Trips the coaches take (read at noon) | Lines in profit without and at a loss with |")
            out.append("| --: | --: | --: | --: | --: | --: | --: | --- |")
            for index in 0..<Int(days) {
                guard let off = played[false]?[index], let on = played[true]?[index] else { continue }
                let turned = with.lines.filter { (off.lines[$0.id] ?? 0) >= 0 && (on.lines[$0.id] ?? 0) < 0 }
                    .map { "\($0.name) (\(Money(off.lines[$0.id] ?? 0).moneyText) → \(Money(on.lines[$0.id] ?? 0).moneyText))" }
                let worst = with.lines.map { (line: $0, change: (on.lines[$0.id] ?? 0) - (off.lines[$0.id] ?? 0)) }.min { $0.change < $1.change }
                out.append("| \(index + 1) | \(off.trips) / \(on.trips) (\(percent(on.trips - off.trips, of: off.trips))) | "
                    + "\(Money(off.fares).moneyText) / \(Money(on.fares).moneyText) (\(percent(on.fares - off.fares, of: off.fares))) | "
                    + "\(Money(off.profit).moneyText) / \(Money(on.profit).moneyText) | \(off.lost) / \(on.lost) | \(on.riders) | \(on.robbed) | "
                    + "\(turned.isEmpty ? "none" : turned.joined(separator: "; ")); of \(with.lines.count) lines, in profit without \(off.lines.values.count { $0 >= 0 }), "
                    + "with \(on.lines.values.count { $0 >= 0 }); the line whose profit falls most: "
                    + "\(worst.map { "\($0.line.name) \(Money($0.change).moneyText)" } ?? "none") |")
            }
            out.append("")
            note(out.suffix(Int(days) + 3).joined(separator: "\n"))
        }
        print("### What the coaches do on the other maps (\(days) days)\n\n" + out.joined(separator: "\n"))
    }
}
