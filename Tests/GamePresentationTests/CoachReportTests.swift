import Foundation
@testable import GameCore
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
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
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
                    let pairs = world.coachPairCount()
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

    /// Decision 706 §2: what the coaches take on the whole of Taiwan, with
    /// the Taiwan Railway and the High Speed Rail the company's own:
    ///
    ///     COACH_TAIWAN=1 swift test -c release --skip-build --filter 'CoachReportTests/testWhatTheCoachesTakeAcrossTaiwan$'
    ///
    /// `COACH_TAIWAN` is the days to play (0 to 10; 0 reads only the day's
    /// demand); `COACH_TAIWAN_ONLY` picks a network (`hsr`, `tra+hsr`;
    /// `tra` alone has no game that gives its stations their trips). The High Speed Rail is the high-speed demo's
    /// (decision 170), on its real day's trains; the Taiwan Railway is laid
    /// as the demo mode lays real lines (decision 351), every station of
    /// every line, a train every 15 minutes calling at all of them. For
    /// each network it prints the trips and fares of a day's demand the
    /// coaches take (every pair of stations, each priced at its fare), the
    /// pairs they take most from, and the days played without the coach
    /// stops and with.
    func testWhatTheCoachesTakeAcrossTaiwan() async throws {
        guard let value = ProcessInfo.processInfo.environment["COACH_TAIWAN"] else {
            throw XCTSkip("set COACH_TAIWAN=<days> to print the whole-Taiwan coach report")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (0...10).contains($0) ? $0 : nil }, "COACH_TAIWAN is 0 to 10 days")
        let only = ProcessInfo.processInfo.environment["COACH_TAIWAN_ONLY"]
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let network = try XCTUnwrap(data.coaches)
        func note(_ text: String) { FileHandle.standardError.write(Data("\(text)\n".utf8)) }
        var out: [String] = []
        for variant in ["hsr", "tra+hsr"] where only == nil || only == variant {
            var world: GameWorld
            if variant.contains("hsr") {
                world = try HighSpeedDemo.make(
                    in: .english, railways: railways, population: data.population, places: data.places, water: data.water, heights: data.heights
                )
            } else {
                world = HighSpeedDemo.newWorld(paying: Money(0), eventSeed: 1)
                try world.mapGround()
            }
            world.setUnlimitedFunds(true)
            if variant.contains("tra") {
                let session = GameSession(world: world, language: .english)
                session.railways = railways
                session.population = data.population
                session.places = data.places
                session.water = data.water
                session.heights = data.heights
                session.news.isDemo = true
                let began = Date()
                let laid = await session.layDemoRealLines(in: WorldRegion(bounds: world.bounds), routes: .max, anyWidth: true) {
                    $0.system.id == "tra_sched"
                }
                note("\(variant): laid \(laid.map { "\($0.lines) lines, \($0.stations) stations, \($0.missed) missed" } ?? "nothing") in "
                    + "\(Int(Date().timeIntervalSince(began))) s: \(session.message?.text ?? "")")
                session.refreshTransfers()
                world = session.world
            }
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            var with = world
            with.setCoachStops(CoachCatalog.stops(of: network, in: frame, bounds: world.bounds))
            let stations = with.stations.filter { !$0.isDepot }
            let rivals = with.coachRivals()

            // The day's demand, pair by pair.
            struct Pair {
                let from: String, to: String
                let kept: Int64, taken: Int64, fare: Int64, minutes: Int64
                let rival: CoachLink
            }
            var pairs: [Pair] = []
            var trips: Int64 = 0, taken: Int64 = 0, fares: Int64 = 0, faresTaken: Int64 = 0
            for station in stations {
                for detail in with.dailyDemandDetails(from: station.id) {
                    // What the trip pays: the high-speed fare when its
                    // fastest way rides the High Speed Rail.
                    let fast = detail.route?.legs.contains { with.isHighSpeedLine($0.line) } ?? false
                    let fare = with.tripFare(from: station.id, to: detail.destination, highSpeed: fast)?.amount ?? 0
                    trips += detail.trips
                    taken += detail.byCoach
                    fares += detail.trips * fare
                    faresTaken += detail.byCoach * fare
                    if detail.byCoach > 0, let rival = rivals[station.id]?[detail.destination] {
                        pairs.append(Pair(from: station.name + (fast ? " (HSR)" : ""), to: with.station(id: detail.destination)?.name ?? "", kept: detail.trips,
                                          taken: detail.byCoach, fare: fare, minutes: detail.route?.totalMinutes ?? 0, rival: rival))
                    }
                }
            }
            func percent(_ part: Int64, of whole: Int64) -> String {
                whole == 0 ? "0.0%" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
            }
            out.append("### \(variant): \(with.lines.count) lines, \(stations.count) stations, \(with.trains.count) trains\n")
            out.append("Coach stops \(with.coachStops.count), with a station \(with.coachStations.compactMap { $0 }.count); "
                + "pairs with a coach \(with.coachPairCount()), of them losing trips \(pairs.count).\n")
            out.append("| A day's demand | Trips | Fares (each pair at its fare) |\n| --- | --: | --: |")
            out.append("| Without coaches | \(trips + taken) | \(Money(fares + faresTaken).moneyText) |")
            out.append("| With coaches | \(trips) | \(Money(fares).moneyText) |")
            out.append("| The coaches take | \(taken) (\(percent(taken, of: trips + taken))) | "
                + "\(Money(faresTaken).moneyText) (\(percent(faresTaken, of: fares + faresTaken))) |\n")
            out.append("| From | To | Rail: minutes / fare | Coach: minutes / a day / fare | Trips without | The coach takes | Share | Fares taken |")
            out.append("| --- | --- | --: | --: | --: | --: | --: | --: |")
            for pair in pairs.sorted(by: { $0.taken * $0.fare > $1.taken * $1.fare }).prefix(40) {
                out.append("| \(pair.from) | \(pair.to) | \(pair.minutes) / \(pair.fare / 100) | \(pair.rival.minutes) / \(pair.rival.dailyCoaches) / \(pair.rival.fare) | "
                    + "\(pair.kept + pair.taken) | \(pair.taken) | \(percent(pair.taken, of: pair.kept + pair.taken)) | \(Money(pair.taken * pair.fare).moneyText) |")
            }
            let shares = pairs.map { $0.taken * 1_000 / max(1, $0.kept + $0.taken) }
            out.append("\nPairs by the share the coach takes: up to 5%: \(shares.count { $0 <= 50 }); to 10%: \(shares.count { $0 > 50 && $0 <= 100 }); "
                + "to 20%: \(shares.count { $0 > 100 && $0 <= 200 }); over 20%: \(shares.count { $0 > 200 }); the most \(Double(shares.max() ?? 0) / 10)%.\n")
            note(out.joined(separator: "\n"))

            guard days > 0 else { continue }
            out.append("| Coaches | Day | Trips | Fares | Operating profit | Fullest train | Station full or gave up | Riders the coaches bring | Trips a day the coaches take | Seconds |")
            out.append("| --- | --: | --: | --: | --: | --: | --: | --: | --: | --: |")
            for coaches in [false, true] {
                var played = coaches ? with : world
                played.setLineAccounts(true)
                var before: Int64 = 0
                try played.advance(ticks: 1)
                // To the first midnight, so each day counted is a whole one.
                while played.clock.now.seconds % GameTime.secondsPerDay != 0 { try played.advance(ticks: 1) }
                try played.advance(ticks: 1)
                before = played.stations.map { played.passengerLedger(of: $0.id) }.map { $0.overflowed + $0.abandoned }.reduce(0, +)
                for day in 1...days {
                    let began = Date()
                    // Read at noon and not counted in the seconds: at
                    // midnight a timetabled network has no train to ride.
                    var robbed: Int64 = 0, reading: TimeInterval = 0
                    for minute in 0..<1_440 {
                        try played.advance(ticks: 1)
                        guard minute == 720 else { continue }
                        let read = Date()
                        robbed = played.stations.map { played.tripsTakenByCoaches(from: $0.id) }.reduce(0, +)
                        reading = Date().timeIntervalSince(read)
                    }
                    let account = played.accounts.days.last
                    let peak = played.lines.compactMap { played.lineYesterday($0.id)?.peakLoad }.max() ?? 0
                    let lost = played.stations.map { played.passengerLedger(of: $0.id) }.map { $0.overflowed + $0.abandoned }.reduce(0, +)
                    let row = "| \(coaches ? "with" : "without") | \(day) | \(played.lastDayTrips()) | \(account?.fareRevenue.moneyText ?? "") | "
                        + "\(Money(account.map(airportReportProfit) ?? 0).moneyText) | \(peak / 10)% | \(lost - before) | "
                        + "\(played.coachStops.map(\.yesterdayRiders).reduce(0, +)) | \(robbed) | \(Int(Date().timeIntervalSince(began) - reading)) |"
                    out.append(row)
                    note(row)
                    before = lost
                }
            }
            out.append("")
        }
        print("### What the coaches take across Taiwan (\(days) days)\n\n" + out.joined(separator: "\n"))
    }
}
