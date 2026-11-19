import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 854: Fukuoka's map pack, Japan's first map: the Fukuoka City
/// Subway's three lines (stations from the MLIT's National Land Numerical
/// Information N02, track and tunnels from OpenStreetMap, headways
/// estimated), read since its map opened (FUKUOKA-OPEN).
@MainActor
final class FukuokaRailwaysTests: XCTestCase {
    /// The bundled files read with Fukuoka open.
    nonisolated static let open: RealRailways.Loaded = RealRailways.load(overseas: [.fukuoka], pack: HongKongRailwaysTests.pack) { name, ext in
        try BundledRealData.file(name, ext)
    }

    static func railways() throws -> RealRailways {
        try XCTUnwrap(open.railways)
    }

    nonisolated static func ground() throws -> OverseasGround {
        try OverseasGround(city: .fukuoka, pack: try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)))
    }

    /// A game on Fukuoka's map with its railways, its people and its
    /// ground (FUKUOKA-GROUND), as the launcher would start it.
    static func fukuoka() throws -> GameSession {
        let ground = try Self.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        try world.mapGround()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        return session
    }

    /// The three lines, end to end, as the operator numbers their stations.
    static let lines: [(id: String, stations: Int, first: String, last: String, km: ClosedRange<Double>)] = [
        ("K", 13, "姪濱", "福岡機場", 12.5...13.5),
        ("H", 7, "中洲川端", "貝塚", 4.5...5.0),
        ("N", 18, "橋本", "博多", 13.2...14.0),
    ]

    // MARK: - The switch

    /// FUKUOKA-OPEN: open, reached by flights as Hong Kong is; the game
    /// reads and credits it, and a release uploads its pack (its asset
    /// pack manifest, `MapPackDownloadsTests`).
    func testFukuokaIsOpen() throws {
        XCTAssertTrue(OverseasMaps.open.contains(.fukuoka))
        XCTAssertTrue(OverseasMap.fukuoka.opensByFlights)
        let all = RealRailways.load(pack: HongKongRailwaysTests.pack) { try BundledRealData.file($0, $1) }
        XCTAssertTrue(try XCTUnwrap(all.railways).lines.contains { $0.system.id == "fksubway" })
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertTrue(DataSourceCredits.sections(in: language).contains { $0.id == "fukuokaRailways" })
            XCTAssertTrue(DataSourceCredits.sections(in: language, overseas: [.fukuoka]).contains { $0.id == "fukuokaRailways" })
        }
    }

    // MARK: - The railways

    /// The three lines with their stations in order, read without an issue,
    /// each as long as the real line.
    func testTheLinesAndTheirStations() throws {
        XCTAssertEqual(Self.open.issues, [])
        let railways = try Self.railways()
        let lines = railways.lines.filter { $0.system.id == "fksubway" }
        XCTAssertEqual(Set(lines.map(\.lineKey)), ["fksubway|K", "fksubway|H", "fksubway|N"])
        for line in Self.lines {
            let runs = try XCTUnwrap(railways.metroRuns["fksubway:\(line.id)"], line.id)
            XCTAssertEqual(runs.stops.count, line.stations, line.id)
            XCTAssertEqual(runs.stops.first, line.first, line.id)
            XCTAssertEqual(runs.stops.last, line.last, line.id)
        }
        let network = try JSONSerialization.jsonObject(with: try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)).file("fksubway", "json")) as? [String: Any]
        let listed = try XCTUnwrap(network?["lines"] as? [[String: Any]])
        for line in Self.lines {
            let stations = try XCTUnwrap(listed.first { $0["id"] as? String == line.id }?["stations"] as? [[String: Any]])
            let km = try XCTUnwrap(stations.last?["d"] as? Double)
            XCTAssertTrue(line.km.contains(km), "\(line.id): \(km) km")
        }
    }

    /// Every station has its English name beside its Chinese one, and the
    /// two stations the lines share are one station each: Hakata (Kuko and
    /// Nanakuma lines) and Nakasu-Kawabata (Kuko and Hakozaki lines).
    func testStationsHaveTheirEnglishNamesAndShareInterchanges() throws {
        let railways = try Self.railways()
        let stations = railways.stations.filter { $0.system.id == "fksubway" }
        // 38 stops on the three lines, the two shared ones counted once.
        XCTAssertEqual(stations.count, 36)
        for station in stations {
            XCTAssertNotNil(station.english, station.chinese)
        }
        XCTAssertEqual(stations.first { $0.chinese == "福岡機場" }?.english, "Fukuoka Airport")
        XCTAssertEqual(stations.first { $0.chinese == "姪濱" }?.english, "Meinohama")
        for (name, lines) in [("博多", ["K", "N"]), ("中洲川端", ["K", "H"])] {
            let calling = Self.lines.map(\.id).filter { railways.metroRuns["fksubway:\($0)"]?.stops.contains(name) == true }
            XCTAssertEqual(calling, lines, name)
        }
    }

    /// A subway: most of each line is in tunnels, from OpenStreetMap.
    func testTheLinesAreMostlyInTunnels() throws {
        let data = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)).file("rail_structures", "json")
        let structures = try RealRailStructures(data: data).structures
        XCTAssertGreaterThan(structures.filter { $0.kind == .tunnel }.count, 30)
    }

    /// The airport's station, where the flights will land, is the Kuko
    /// Line's last.
    func testTheArrivalIsTheAirportsStation() throws {
        let airport = try XCTUnwrap(try Self.railways().stations.first { $0.chinese == "福岡機場" })
        XCTAssertEqual(airport.coordinate.latitude, OverseasMap.fukuoka.arrival.latitude, accuracy: 0.001)
        XCTAssertEqual(airport.coordinate.longitude, OverseasMap.fukuoka.arrival.longitude, accuracy: 0.001)
        let extent = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)).extent()
        XCTAssertEqual(extent, MapPack.Extent(north: 33.72, south: 33.52, west: 130.29, east: 130.48))
    }

    /// Each line is on sale on the map, bought with its trains, and runs a
    /// whole day with no train in a deadlock.
    func testEachLineIsBoughtAndRunsADay() throws {
        XCTAssertEqual(try Self.fukuoka().buyableRealLines.map(\.id).sorted(), ["fksubway:H", "fksubway:K", "fksubway:N"])
        for line in Self.lines {
            let id = "fksubway:\(line.id)"
            let session = try Self.fukuoka()
            let buyable = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            let offer = session.realLineOffer(for: buyable)
            XCTAssertNil(offer.problem, id)
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
            let bought = try XCTUnwrap(session.world.acquisition(of: id))
            let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)))
            XCTAssertGreaterThan(ran.assignedTrains.count, 0, id)
            var played = session.world
            var stuck = 0
            for _ in 0..<(24 * 60) {
                try played.advance(ticks: 1)
                if !played.deadlockedTrains().isEmpty { stuck += 1 }
            }
            XCTAssertEqual(stuck, 0, "\(id): minutes of the day with a deadlock")
            let after = try XCTUnwrap(played.line(id: ran.id))
            XCTAssertGreaterThan(zip(after.runs, after.runDays).filter { $0.1 != nil }.count, 0, id)
        }
    }
}
