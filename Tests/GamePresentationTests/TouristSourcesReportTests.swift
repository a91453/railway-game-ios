import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 601: the sights on a bought or a self-built branch line, with
/// and without bigger stations elsewhere on the map that do not join it,
/// printed as Markdown. It asserts nothing and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     TOURIST_REPORT=180 swift test -c release --skip-build \
///       --filter TouristSourcesReportTests
///
/// `TOURIST_REPORT` is the days to play (1 to 720); `TOURIST_ONLY` picks
/// one line (`PINGXI`, `JIJI`, `NEIWAN`).
///
/// The world is `AcquisitionReportTests`'s (simple rules, the app's
/// heights, land read round each station, real transfers on, $200 million
/// in the bank) with every catalogue sight on the map and no outside
/// connections, as on the whole-Taiwan map. "Towns" adds stations at the
/// main line's real towns nearby (on a map 2²² wide, about 65.5 km, so that they are on it), none of them joined to the branch, as a
/// player's network elsewhere (docs/research/TOURIST_SOURCES_2026-11-05.md §3).
@MainActor
final class TouristSourcesReportTests: XCTestCase {
    static let towns: [String: [String]] = [
        "JIJI": ["彰化", "花壇", "大村", "員林", "永靖", "社頭", "田中"],
        "PINGXI": ["基隆", "三坑", "八堵", "七堵", "百福", "五堵", "汐止", "汐科"],
        "NEIWAN": ["竹北", "新豐", "湖口", "富岡", "埔心", "楊梅"],
    ]

    func testSightsOnABranchLine() throws {
        guard let value = ProcessInfo.processInfo.environment["TOURIST_REPORT"] else {
            throw XCTSkip("set TOURIST_REPORT=<days> to print the tourist sources report")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (1...720).contains($0) ? $0 : nil }, "TOURIST_REPORT is 1 to 720 days")
        let only = ProcessInfo.processInfo.environment["TOURIST_ONLY"]
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var rows = [
            "| Line | Map | Way | Sights day 1 | Tourists by day 30 | Tourists by day \(days) | Op. profit a day, 1–30 | Op. profit a day, 1–\(days) | Op. profit a day, last 30 | Trips day 30 / \(days) | Cash change by day \(days) |",
            "| --- | --- | --- | --- | --: | --: | --: | --: | --: | --- | --: |",
        ]
        for network in ["JIJI", "PINGXI", "NEIWAN"] where only.map({ $0 == network }) ?? true {
            for withTowns in [false, true] {
                for recording in [true, false] {
                    let started = Date()
                    let played = try play(network, towns: withTowns, recording: recording, days: days, data: data)
                    func average(_ range: ClosedRange<Int64>) -> String {
                        let slice = played.profits[Int(range.lowerBound - 1)...Int(range.upperBound - 1)]
                        return Money(slice.reduce(0, +) / Int64(slice.count)).moneyText
                    }
                    rows.append(
                        "| \(network) | \(withTowns ? "towns" : "branch only") | \(recording ? "bought" : "own") | \(played.status) | "
                            + "\(played.tourists[min(30, days)] ?? 0) | \(played.tourists[days] ?? 0) | \(average(1...min(30, days))) | \(average(1...days)) | "
                            + "\(average(max(1, days - 29)...days)) | \(played.trips[min(30, days)] ?? 0) / \(played.trips[days] ?? 0) | \(Money(played.cash - played.before).moneyText) |"
                    )
                    FileHandle.standardError.write(Data("\(rows.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
                }
            }
        }
        print("### Tourists on a branch line (\(days) days, no outside connections)\n\n" + rows.joined(separator: "\n"))
    }

    private struct Played {
        var status = ""
        var before: Int64 = 0
        var cash: Int64 = 0
        var tourists: [Int64: Int64] = [:]
        var trips: [Int64: Int64] = [:]
        var profits: [Int64] = []
    }

    private func play(_ network: String, towns: Bool, recording: Bool, days: Int64, data: RealWorldData) throws -> Played {
        let railways = try XCTUnwrap(data.railways)
        let runs = try XCTUnwrap(railways.branchRuns[network])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: RealBranchLine.tra) }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        let side: Int64 = 1 << 22
        var world = GameWorld.newGame(
            anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: Money(20_000_000_000), land: [], rules: .simple
        )
        world.setLandOnDemand()
        world.setRealTransfers(true)
        world.setOutsideConnections(false)
        try world.mapGround()
        world.setTourism(RealWorldFrame(world: world).map { AttractionCatalog.attractions(in: $0, bounds: world.bounds) })
        let session = GameSession(world: world, language: .english)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network || $0.id == network }, network)
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, "\(network): \(offer.problem ?? "")")
        var played = Played()
        played.before = world.economy.balance.amount
        _ = try session.build(acquisition, in: &world, recording: recording)
        let built = GameSession(world: world, language: .english)
        built.railways = railways
        built.refreshTransfers()
        world = built.world
        if towns {
            var built: [StationID] = []
            for name in Self.towns[network] ?? [] {
                let point = try BundledRealData.point(BundledRealData.station(name, in: RealBranchLine.tra).coordinate, in: world)
                if let station = try? world.buildStation(named: name, at: point) { built.append(station.id) }
            }
            // Their land, as an edit in the app reads it round a new station.
            let reading = GameSession(world: world, language: .english)
            reading.railways = railways
            reading.population = data.population
            reading.places = data.places
            reading.water = data.water
            reading.heights = data.heights
            reading.readLandRoundStations()
            world = reading.world
            // The towns' own line with a train, as a player's network
            // elsewhere runs, joined to nothing on the branch.
            if built.count >= 2 {
                let line = try world.createLine(named: "Towns", stops: built).id
                let train = try world.purchaseTrain(named: "Towns").id
                try world.assignTrain(train, to: line)
            }
            let towns = built.map { "\(world.station(id: $0)?.name ?? "?") \(world.landCatchment(of: $0)?.residents ?? -1)\(world.stationDemand(of: $0) == nil ? " no demand" : "")" }
            let branch = world.stations.filter { !built.contains($0.id) }.map { "\($0.name) \(world.landCatchment(of: $0.id)?.residents ?? -1)" }
            FileHandle.standardError.write(Data("\(network) towns: \(towns.joined(separator: ", ")); branch: \(branch.joined(separator: ", "))\n".utf8))
        }
        // Each sight near the line: its status once the first day has run.
        let near = (world.tourism?.attractions ?? []).filter { sight in
            world.stations.contains { station in
                let dx = station.point.x - sight.point.x, dy = station.point.y - sight.point.y
                return dx * dx + dy * dy <= Tourism.reach * Tourism.reach
            }
        }
        for day in 1...days {
            try world.advance(ticks: 1_440)
            if day == 1 {
                played.status = near.map { "\($0.name) \(world.attractionStatus(of: $0.id))" }.joined(separator: ", ")
            }
            played.tourists[day] = near.compactMap { sight in world.tourism?.attractions.first { $0.id == sight.id }?.thisYear }.reduce(0, +)
            played.trips[day] = world.lastDayTrips()
            played.profits.append(world.accounts.days.last.map { ($0.fareRevenue + $0.freightRevenue + $0.propertyRevenue - $0.totalCost - $0.propertyCost).amount } ?? 0)
            played.cash = world.economy.balance.amount
        }
        return played
    }
}
