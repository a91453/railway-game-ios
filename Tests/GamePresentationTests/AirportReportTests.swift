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
        var rows = ["| Line | Airports | Day | Trips | Fares | Operating profit | Airport: flights / air passengers / riders (station) |",
                    "| --- | --- | --: | --: | --: | --: | --- |"]
        for network in Self.networks where only == nil || only == network {
            let start = try bought(network, data: data)
            for airports in [false, true] {
                var world = start
                if !airports { world.setAirports([]) }
                // The tick that starts at midnight counts the day that ended.
                try world.advance(ticks: 1)
                for day in 1...days {
                    for _ in 0..<1_440 { try world.advance(ticks: 1) }
                    let account = world.accounts.days.last
                    let counted = world.airports.map { airport in
                        "\(airport.englishName): \(airport.yesterdayFlights) / \(airport.yesterdayPassengers) / \(airport.yesterdayRiders)"
                            + " (\(world.airportDays().first { $0.airport.id == airport.id }?.station.flatMap { world.station(id: $0)?.name } ?? "none"))"
                    }.joined(separator: "; ")
                    rows.append("| \(network) | \(airports ? "with" : "without") | \(day) | \(world.lastDayTrips()) | \(account?.fareRevenue.moneyText ?? "") | "
                        + "\(Money(account.map(airportReportProfit) ?? 0).moneyText) | \(counted) |")
                    FileHandle.standardError.write(Data("\(rows.last!)\n".utf8))
                }
            }
        }
        print("### What the airports add to a real line (\(days) days)\n\n" + rows.joined(separator: "\n"))
    }

    /// A real-world game round `network` with the line bought, as
    /// `AcquisitionReportTests.play` begins it.
    private func bought(_ network: String, data: RealWorldData) throws -> GameWorld {
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
            anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: Money(200_000_000_000), land: [], rules: .simple
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

private func airportReportProfit(_ day: DayAccount) -> Int64 {
    (day.fareRevenue + day.freightRevenue + day.propertyRevenue - day.totalCost - day.propertyCost).amount
}
