import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 695: what the airports add to a real line bought, printed as
/// Markdown. It asserts nothing and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     AIRPORT_REPORT=3 swift test -c release --skip-build --filter AirportReportTests
///
/// `AIRPORT_REPORT` is the days to play (1 to 60); `AIRPORT_ONLY` picks one
/// line (`tymc:A`, `trtc:BR`). Each line is bought in a real-world game
/// round it, as `AcquisitionReportTests` does, and played minute by minute
/// twice from the same minute: with the map's airports and without.
@MainActor
final class AirportReportTests: XCTestCase {
    static let networks = ["tymc:A", "trtc:BR"]

    func testWhatTheAirportsAddToARealLine() throws {
        guard let value = ProcessInfo.processInfo.environment["AIRPORT_REPORT"] else {
            throw XCTSkip("set AIRPORT_REPORT=<days> to print the airport report")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (1...60).contains($0) ? $0 : nil }, "AIRPORT_REPORT is 1 to 60 days")
        let only = ProcessInfo.processInfo.environment["AIRPORT_ONLY"]
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        // HEALTH-126: and how full the trains ran: the fullest a train left
        // a stop (of its rated capacity), the times a train left people
        // behind for want of room, those who found a station full or gave
        // up, and those still waiting at midnight; all stations, and of
        // them the airports' own.
        var rows = ["| Line | Airports | Day | Trips | Fares | Operating profit | Fullest train | Left behind (times): all / airport stations | Station full or gave up | Waiting at midnight: all / airport stations | Airport: flights / air passengers / riders (station) |",
                    "| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |"]
        var tourists: [String] = []
        for network in Self.networks where only == nil || only == network {
            let start = try Self.bought(network, data: data)
            for airports in [false, true] {
                var world = start
                // The airports' stations, as the game with them has them.
                let served = Set(world.airportDays().compactMap(\.station))
                if !airports { world.setAirports([]) }
                world.setLineAccounts(true)
                var before = (refused: Int64(0), served: Int64(0), lost: Int64(0))
                // The tick that starts at midnight counts the day that ended.
                try world.advance(ticks: 1)
                for day in 1...days {
                    for _ in 0..<1_440 { try world.advance(ticks: 1) }
                    let account = world.accounts.days.last
                    let counted = world.airports.map { airport in
                        "\(airport.englishName): \(airport.yesterdayFlights) / \(airport.yesterdayPassengers) / \(airport.yesterdayRiders)"
                            + " (\(world.airportDays().first { $0.airport.id == airport.id }?.station.flatMap { world.station(id: $0)?.name } ?? "none"))"
                    }.joined(separator: "; ")
                    let peak = world.lines.compactMap { world.lineYesterday($0.id)?.peakLoad }.max() ?? 0
                    let ledgers = world.stations.map { (station: $0.id, ledger: world.passengerLedger(of: $0.id)) }
                    let now = (
                        refused: ledgers.map(\.ledger.refused).reduce(0, +),
                        served: ledgers.filter { served.contains($0.station) }.map(\.ledger.refused).reduce(0, +),
                        lost: ledgers.map { $0.ledger.overflowed + $0.ledger.abandoned }.reduce(0, +)
                    )
                    let waiting = ledgers.map(\.ledger.waiting).reduce(0, +)
                    let waitingServed = ledgers.filter { served.contains($0.station) }.map(\.ledger.waiting).reduce(0, +)
                    rows.append("| \(network) | \(airports ? "with" : "without") | \(day) | \(world.lastDayTrips()) | \(account?.fareRevenue.moneyText ?? "") | "
                        + "\(Money(account.map(airportReportProfit) ?? 0).moneyText) | \(peak / 10)% | \(now.refused - before.refused) / \(now.served - before.served) | "
                        + "\(now.lost - before.lost) | \(waiting) / \(waitingServed) | \(counted) |")
                    before = now
                    // Review L18-3: the tourists of each sight, which the
                    // airports' stations now also set out from.
                    let sights = (world.tourism?.attractions ?? []).filter { $0.yesterday > 0 }
                    tourists.append("- \(network), \(airports ? "with" : "without"), day \(day): \(sights.map(\.yesterday).reduce(0, +)) tourists at \(sights.count) of "
                        + "\(world.tourism?.attractions.count ?? 0) sights; " + sights.map { "\($0.englishName) \($0.yesterday)" }.joined(separator: ", "))
                    FileHandle.standardError.write(Data("\(rows.last!)\n".utf8))
                }
            }
        }
        print("### What the airports add to a real line (\(days) days)\n\n" + rows.joined(separator: "\n")
            + "\n\nTourists of the day, by sight:\n\n" + tourists.joined(separator: "\n"))
    }

    /// Decision 712: what a line to an airport that flies to Hong Kong
    /// carries of its passengers in a day (``Airport/yesterdayRiders``),
    /// beside the 500 that open Hong Kong's map
    /// (``OverseasMap/ridersToOpen``): the Taoyuan Airport MRT bought, and
    /// lines of the player's own of two to six stations from Kaohsiung's
    /// and Taichung's terminals into their cities, three trains each.
    ///
    ///     AIR_ROUTE_REPORT=3 swift test --skip-build --filter AirportReportTests/testWhatALineToAnAirportCarries
    func testWhatALineToAnAirportCarries() throws {
        guard let value = ProcessInfo.processInfo.environment["AIR_ROUTE_REPORT"] else {
            throw XCTSkip("set AIR_ROUTE_REPORT=<days> to print what a line to an airport carries")
        }
        let days = try XCTUnwrap(Int(value).flatMap { (1...30).contains($0) ? $0 : nil }, "AIR_ROUTE_REPORT is 1 to 30 days")
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var rows = ["| Line | Stations | Day | Riders of the airports that fly to Hong Kong (yesterday) | Trips | Fares |", "| --- | --: | --: | --- | --: | --: |"]
        func play(_ name: String, stations: Int, _ start: GameWorld) throws {
            var world = start
            world.setLineAccounts(true)
            try world.advance(ticks: 1)
            for day in 1...days {
                for _ in 0..<1_440 { try world.advance(ticks: 1) }
                let riders = world.airports.filter { $0.flies(to: .hongKong) }.map { "\($0.englishName) \($0.yesterdayRiders)" }.joined(separator: "; ")
                rows.append("| \(name) | \(stations) | \(day) | \(riders) | \(world.lastDayTrips()) | \(world.accounts.days.last?.fareRevenue.moneyText ?? "") |")
                FileHandle.standardError.write(Data("\(rows.last!)\n".utf8))
            }
        }
        // `AIR_ROUTE_ONLY=own` leaves the bought line out (a quarter of an
        // hour in a debug build).
        if ProcessInfo.processInfo.environment["AIR_ROUTE_ONLY"] != "own" {
            let bought = try Self.bought("tymc:A", data: data)
            try play("Taoyuan Airport MRT (bought)", stations: bought.stations.count, bought)
        }
        // A line of one's own is not played (its track would have to be
        // laid by hand): the riders its airport's day gives it are read
        // instead (``AirportDay/ridersFrom`` and ``AirportDay/ridersTo``,
        // which the residents its stations reach cap), beside the most
        // the airport's passengers would give any line.
        var own = ["| Line | Stations | Riders today, both ways | The most the airport gives, both ways |", "| --- | --: | --: | --: |"]
        // The terminal first, then stops into the city: Kaohsiung's along
        // Zhongshan Road (where the Red Line's R4 to R8 are), Taichung's
        // by Daya and Shuinan to Taichung Station.
        let lines: [(name: String, stops: [(Double, Double)])] = [
            ("Own line from Kaohsiung Airport", [(22.5702, 120.3421), (22.5805, 120.3287), (22.5886, 120.3215), (22.5969, 120.3152), (22.6064, 120.3083), (22.6138, 120.3046)]),
            ("Own line from Taichung Airport", [(24.2539, 120.5996), (24.2290, 120.6480), (24.1890, 120.6540), (24.1716, 120.6845), (24.1500, 120.6850), (24.1368, 120.6850)]),
        ]
        for line in lines {
            for count in [2, 3, 4, 6] {
                let stops = Array(line.stops.prefix(count))
                let latitude = stops.map(\.0).reduce(0, +) / Double(count), longitude = stops.map(\.1).reduce(0, +) / Double(count)
                let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
                var world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(200_000_000_000), land: [], rules: .simple)
                world.setLandOnDemand()
                let frame = try XCTUnwrap(RealWorldFrame(world: world))
                var ids: [StationID] = []
                for (index, stop) in stops.enumerated() {
                    let position = frame.worldPosition(latitude: stop.0, longitude: stop.1)
                    ids.append(try world.buildStation(named: "S\(index + 1)", at: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))).id)
                }
                let route = try world.createLine(named: line.name, stops: ids).id
                for train in 1...3 { try world.assignTrain(try world.purchaseTrain(named: "T\(train)").id, to: route) }
                let session = GameSession(world: world, language: .english)
                session.population = data.population
                session.places = data.places
                session.water = data.water
                session.readLandRoundStations()
                let day = try XCTUnwrap(session.world.airportDays().first { $0.airport.flies(to: .hongKong) })
                XCTAssertNotNil(day.station, "\(line.name): the terminal's station serves it")
                own.append("| \(line.name) | \(count) | \(day.ridersFrom + day.ridersTo) | \(2 * day.ridersAtMost) |")
            }
        }
        print("### What a line to an airport carries (\(days) days; \(OverseasMap.hongKong.ridersToOpen) open Hong Kong)\n\n" + rows.joined(separator: "\n")
            + "\n\n" + own.joined(separator: "\n"))
    }

    /// A real-world game round `network` with the line bought, as
    /// `AcquisitionReportTests.play` begins it.
    static func bought(_ network: String, data: RealWorldData, rules: NewGameRules = .simple) throws -> GameWorld {
        let railways = try XCTUnwrap(data.railways)
        let runs = try XCTUnwrap(railways.branchRuns[network] ?? railways.metroRuns[network])
        let prefix = String(network.prefix { $0 != ":" })
        let system = prefix == "trtc" ? "mrt" : prefix
        let stations = try runs.stops.map { try BundledRealData.station($0, in: system) }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        let side: Int64 = network == "tymc:A" ? 1 << 22 : 1 << 21
        var world = GameWorld.newGame(
            anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: Money(200_000_000_000), land: [], rules: rules
        )
        world.setLandOnDemand()
        world.setRealTransfers(true)
        try world.mapGround()
        let session = GameSession(world: world, language: .english)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network || $0.id == network }, network)
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, "\(network): \(offer.problem ?? "")")
        _ = try session.build(acquisition, in: &world, recording: true)
        let built = GameSession(world: world, language: .english)
        built.railways = railways
        built.refreshTransfers()
        return built.world
    }
}

func airportReportProfit(_ day: DayAccount) -> Int64 {
    (day.fareRevenue + day.freightRevenue + day.propertyRevenue - day.totalCost - day.propertyCost).amount
}
