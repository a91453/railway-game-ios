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

    /// Decision 898: the Nanakuma Line is bought with the Hashimoto depot,
    /// past Hashimoto, its end, alone or with the other two: the trains
    /// Hashimoto's own tracks have no room for overnight start in it, as
    /// many as it has sidings. The line has the 23 trains its peak needs
    /// at the game's dwell, with three minutes at Hashimoto to make a
    /// delay good (20 before, and some 127 runs a day late), and every
    /// run goes the whole way, so its ends take the home signal
    /// (decisions 849 and 890).
    func testTheNanakumaLineIsBoughtWithTheHashimotoDepot() throws {
        let id = "fksubway:N"
        let runs = try XCTUnwrap(try Self.railways().metroRuns[id])
        let ends = [try XCTUnwrap(runs.stops.first), try XCTUnwrap(runs.stops.last)]
        // The whole day is laid out from the depot's end: no train stands
        // at Hakata overnight, 13.5 km from the depot, where the game would
        // take it in for the night and send it back empty at dawn, in the
        // first trains' way.
        XCTAssertEqual(runs.overnight, [ends[0]: 23])
        let inDepot = 23 - (try XCTUnwrap(runs.tracks[ends[0]]) - 1)
        XCTAssertEqual(inDepot, RealLineDepotSite.hashimoto.sidings)
        XCTAssertEqual(RealLineDepotSite.hashimoto.beyond, ends[0])
        XCTAssertTrue(runs.runs.allSatisfy { !($0.positioning || $0.train == "回送") })
        let real = runs.runs
        XCTAssertEqual(real.count, 514)
        XCTAssertTrue(real.allSatisfy { $0.calls.count == runs.stops.count }, "every run goes the whole way")

        for together in [false, true] {
            let session = try Self.fukuoka()
            if together {
                try TimetableCheckupAllBoughtTests.buyTogether(["fksubway:K", "fksubway:H", "fksubway:N"], in: session)
            } else {
                let offer = session.realLineOffer(for: try XCTUnwrap(session.buyableRealLines.first { $0.id == id }))
                let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
                let depot = try XCTUnwrap(acquisition.depot, "bought with its depot")
                XCTAssertEqual(depot.name, "橋本車輛基地")
                XCTAssertEqual(depot.platforms.count, RealLineDepotSite.hashimoto.sidings)
                XCTAssertNil(acquisition.moreDepots)
                XCTAssertEqual(acquisition.trains.count, 23)
                XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
            }
            let world = session.world
            let line = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: id)?.line)))
            XCTAssertEqual(line.runs.count, real.count, "together: \(together)")
            XCTAssertEqual(line.trains.count, 23, "together: \(together)")
            let station = try XCTUnwrap(line.depots.first.flatMap { world.station(id: $0) })
            XCTAssertEqual(line.depots.count, 1, "together: \(together)")
            XCTAssertEqual(station.name, "橋本車輛基地")
            XCTAssertTrue(station.isDepot)
            XCTAssertEqual(world.trains.count { world.stationsStoppedAt(by: $0.id).contains(station.id) }, inDepot)
            // Past the line's end, north-west of Hashimoto, on its side
            // of the Muromi River.
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let middle = frame.worldPosition(latitude: 33.5572, longitude: 130.3174)
            let (dx, dy) = (Double(station.location.x) - middle.x, Double(station.location.y) - middle.y)
            XCTAssertLessThan((dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre), 300)
            // The other two lines have no depot.
            if together {
                for other in ["fksubway:K", "fksubway:H"] {
                    XCTAssertEqual(try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: other)?.line))).depots, [], other)
                }
            }
        }
    }
}

/// Decision 898: run only with `HASHIMOTO_DEPOT_DUMP=<file.json>`: the
/// three lines bought together, the track round the Hashimoto depot, for
/// `tools/rail-depots/plot_depots.py` (`PLOT_SITES=hashimoto`), drawn over
/// OpenStreetMap's real yard.
@MainActor
final class HashimotoDepotDumpTests: XCTestCase {
    func testDumpTheDepotTrack() throws {
        guard let path = ProcessInfo.processInfo.environment["HASHIMOTO_DEPOT_DUMP"] else {
            throw XCTSkip("HASHIMOTO_DEPOT_DUMP=<file.json> writes the depot's track")
        }
        let session = try TimetableCheckupAllBoughtTests.fukuoka(rules: .simple)
        try TimetableCheckupAllBoughtTests.buyTogether(["fksubway:K", "fksubway:H", "fksubway:N"], in: session)
        let world = session.world
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let perMetre = frame.mapPointsPerMetre, units = Double(WorldCoordinate.unitsPerMetre)
        func geo(_ point: WorldCoordinate) -> [Double] {
            let east = (Double(point.x) - frame.middleX) / units, south = (Double(point.y) - frame.middleY) / units
            let longitude = (RealWorldFrame.mercatorX(frame.anchor.longitudeDegrees) + east * perMetre) / RealWorldFrame.worldPoints * 360 - 180
            let y = RealWorldFrame.mercatorY(frame.anchor.latitudeDegrees) + south * perMetre
            let latitude = atan(sinh(Double.pi * (1 - 2 * y / RealWorldFrame.worldPoints))) * 180 / .pi
            return [latitude, longitude, Double(point.z) / units]
        }
        let middle = frame.worldPosition(latitude: 33.5560, longitude: 130.3195)
        var edges: [[[Double]]] = []
        for edge in world.network.edges {
            guard let geometry = world.network.geometry(of: edge.id) else { continue }
            let close = geometry.points.contains { point in
                let (dx, dy) = (Double(point.x) - middle.x, Double(point.y) - middle.y)
                return (dx * dx + dy * dy).squareRoot() / units < 900
            }
            if close { edges.append(geometry.points.map(geo)) }
        }
        let station = world.stations.first(where: \.isDepot)
        let data = try JSONSerialization.data(withJSONObject: ["sites": [[
            "name": RealLineDepotSite.hashimoto.english, "edges": edges,
            "station": station.map { geo(WorldCoordinate(x: $0.location.x, y: $0.location.y, z: 0)) } ?? [],
        ] as [String: Any]]])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
