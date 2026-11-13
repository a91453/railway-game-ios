import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 697: Hong Kong's MTR, bundled beside Taiwan's railways in the
/// same formats and read only when its map is open, which it is not yet.
@MainActor
final class HongKongRailwaysTests: XCTestCase {
    /// The bundled files read with Hong Kong open.
    nonisolated static let open: RealRailways.Loaded = RealRailways.load(overseas: [.hongKong], pack: pack) { name, ext in
        try BundledRealData.file(name, ext)
    }

    /// The app's map pack of a city, in the repository.
    nonisolated static func pack(_ city: OverseasMap) -> MapPack? {
        MapPack(root: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("MapPacks").appendingPathComponent(city.packFolder))
    }

    /// Taiwan's railways alone, as the game read them before Hong Kong
    /// was open (and reads them where no city is).
    nonisolated static let closed: RealRailways.Loaded = RealRailways.load(overseas: []) { name, ext in
        try BundledRealData.file(name, ext)
    }

    static func taiwanOnly() throws -> RealRailways {
        try XCTUnwrap(closed.railways)
    }

    static func railways() throws -> RealRailways {
        try XCTUnwrap(open.railways)
    }

    /// MTR's ten lines and two branches, with their stations end to end.
    static let lines: [(id: String, stations: Int, first: String, last: String)] = [
        ("AEL", 5, "香港", "博覽館"), ("TCL", 8, "香港", "東涌"), ("TML", 27, "烏溪沙", "屯門"),
        ("EAL", 14, "金鐘", "羅湖"), ("EAL_LMC", 2, "上水", "落馬洲"), ("TWL", 16, "中環", "荃灣"),
        ("ISL", 17, "堅尼地城", "柴灣"), ("KTL", 17, "黃埔", "調景嶺"), ("TKL", 7, "北角", "寶琳"),
        ("TKL_LHP", 2, "將軍澳", "康城"), ("SIL", 5, "金鐘", "海怡半島"), ("DRL", 2, "迪士尼", "欣澳"),
    ]

    static func metres(_ a: RealRailways.Coordinate, _ b: RealRailways.Coordinate) -> Double {
        let dy = (a.latitude - b.latitude) * 111_320
        let dx = (a.longitude - b.longitude) * 111_320 * cos(a.latitude * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - The switch

    /// With no overseas city read the game reads what it did, no player
    /// can reach a Hong Kong line, and the credits list Taiwan's sources
    /// only. Hong Kong is read since decision 712's third pull request, and
    /// credited.
    func testNoOverseasMapIsReadUnlessOpen() throws {
        XCTAssertEqual(OverseasMaps.open, [.hongKong])
        let railways = try Self.taiwanOnly()
        XCTAssertFalse(railways.lines.contains { $0.system.id == "hkmtr" })
        XCTAssertFalse(railways.stations.contains { $0.system.id == "hkmtr" })
        XCTAssertNil(railways.operations?.system(id: "hkmtr"))
        XCTAssertFalse(railways.metroRuns.keys.contains { $0.hasPrefix("hkmtr:") })
        XCTAssertFalse(RealRailways.System.all.contains { $0.id == "hkmtr" })
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(DataSourceCredits.sections(in: language, overseas: []), DataSourceCredits.taiwanSections(in: language))
            XCTAssertEqual(DataSourceCredits.sections(in: language).count, DataSourceCredits.taiwanSections(in: language).count + 1)
        }
    }

    /// With Hong Kong open Taiwan's railways are the same, in the same
    /// places of the lists, and nothing fails to read.
    func testOpeningHongKongLeavesTaiwanAsItIs() throws {
        XCTAssertEqual(Self.open.issues, [])
        let closed = try Self.taiwanOnly()
        let open = try Self.railways()
        XCTAssertEqual(open.lines.prefix(closed.lines.count).map(\.lineKey), closed.lines.map(\.lineKey))
        XCTAssertEqual(open.lines.prefix(closed.lines.count).map(\.points), closed.lines.map(\.points))
        XCTAssertEqual(Array(open.stations.prefix(closed.stations.count)), closed.stations)
        XCTAssertTrue(open.lines.dropFirst(closed.lines.count).allSatisfy { $0.system.id == "hkmtr" })
        XCTAssertTrue(open.stations.dropFirst(closed.stations.count).allSatisfy { $0.system.id == "hkmtr" })
        for (id, runs) in closed.metroRuns {
            XCTAssertEqual(open.metroRuns[id], runs, id)
        }
        XCTAssertEqual(open.structures.map { Array($0.structures.prefix(closed.structures?.structures.count ?? 0)) }, closed.structures?.structures)
    }

    /// A city whose files are missing is left out and said so; Taiwan's
    /// railways still load.
    func testAMissingHongKongFileLeavesTaiwanLoaded() throws {
        let empty = MapPack(root: FileManager.default.temporaryDirectory.appendingPathComponent("no-such-map-pack"))
        for pack in [empty, nil] {
            let loaded = RealRailways.load(overseas: [.hongKong], pack: { _ in pack }) { name, ext in
                try BundledRealData.file(name, ext)
            }
            let railways = try XCTUnwrap(loaded.railways)
            XCTAssertEqual(railways.lines.map(\.lineKey), try Self.taiwanOnly().lines.map(\.lineKey))
            XCTAssertFalse(loaded.issues.isEmpty)
        }
    }

    /// The pack is one folder that holds all of Hong Kong and nothing of
    /// it is among Taiwan's files; `pack.json` lists every file in it with
    /// where its fields come from.
    func testThePackIsSelfContained() throws {
        let pack = try XCTUnwrap(Self.pack(.hongKong))
        let files = try FileManager.default.contentsOfDirectory(atPath: pack.root.path).sorted()
        struct Manifest: Decodable {
            struct File: Decodable {
                let bytes: Int
                let sources: [String: String]
            }

            let id: String
            let system: String
            let files: [String: File]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: pack.file("pack", "json"))
        XCTAssertEqual(manifest.id, "hongkong")
        XCTAssertEqual(manifest.system, OverseasMap.hongKong.system)
        XCTAssertEqual(files.filter { $0 != "pack.json" }, manifest.files.keys.sorted())
        for (name, file) in manifest.files {
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: pack.root.appendingPathComponent(name).path)[.size] as? Int)
            XCTAssertEqual(size, file.bytes, name)
            XCTAssertFalse(file.sources.isEmpty, name)
            XCTAssertTrue(file.sources.values.allSatisfy { ["OpenStreetMap", "MTR open data", "this project", "WorldPop", "Lands Department DTM"].contains($0) }, name)
        }
        let taiwan = try FileManager.default.contentsOfDirectory(atPath: BundledRealData.directory.path)
        XCTAssertFalse(taiwan.contains { $0.hasPrefix("hk") })
    }

    // MARK: - The map

    /// Every line is on the map in its colour, its stations in MTR's order
    /// with Chinese and English names, all inside Hong Kong.
    func testEveryLineIsOnTheMapWithItsStations() throws {
        let railways = try Self.railways()
        let operations = try XCTUnwrap(railways.operations?.system(id: "hkmtr"))
        XCTAssertEqual(operations.lines.map(\.id), Self.lines.map(\.id))
        let system = try XCTUnwrap(RealRailways.System.overseas[.hongKong])
        XCTAssertEqual(railways.lines.filter { $0.system.id == "hkmtr" }.count, Self.lines.count)
        for expected in Self.lines {
            let line = try XCTUnwrap(operations.lines.first { $0.id == expected.id }, expected.id)
            XCTAssertEqual(line.stations.count, expected.stations, expected.id)
            XCTAssertEqual(line.stations.first?.name, expected.first, expected.id)
            XCTAssertEqual(line.stations.last?.name, expected.last, expected.id)
            let drawn = try XCTUnwrap(railways.lines.first { $0.lineKey == "hkmtr|\(expected.id)" }, expected.id)
            XCTAssertEqual(drawn.palette.color, system.lineColors["hkmtr|\(expected.id)"], expected.id)
            XCTAssertEqual(line.color?.uppercased(), system.lineColors["hkmtr|\(expected.id)"].map { String(format: "#%02X%02X%02X", $0.red, $0.green, $0.blue) }, expected.id)
            for station in line.stations {
                let placed = try XCTUnwrap(railways.stations.first { $0.system.id == "hkmtr" && $0.chinese == station.name }, station.name)
                XCTAssertFalse((placed.english ?? "").isEmpty, station.name)
                XCTAssertTrue((22.15...22.56).contains(placed.coordinate.latitude) && (113.83...114.41).contains(placed.coordinate.longitude), station.name)
            }
        }
        XCTAssertEqual(Set(railways.stations.filter { $0.system.id == "hkmtr" }.map(\.chinese)).count, 97)
    }

    /// The network is connected: each line's drawn shape runs unbroken past
    /// every one of its stations in order, and from the airport every
    /// station is reached by changing where two lines share a station.
    func testTheNetworkIsConnected() throws {
        let railways = try Self.railways()
        let operations = try XCTUnwrap(railways.operations?.system(id: "hkmtr"))
        for line in operations.lines {
            XCTAssertGreaterThan(line.shape.count, 1, line.id)
            for (a, b) in zip(line.shape, line.shape.dropFirst()) {
                XCTAssertLessThan(Self.metres(a, b), 4_000, "\(line.id): a gap in its shape")
            }
            var at = 0
            var last = -1.0
            for station in line.stations {
                let here = RealRailways.Coordinate(latitude: station.latitude, longitude: station.longitude)
                let near = try XCTUnwrap(line.shape.indices.dropFirst(at).min { Self.metres(line.shape[$0], here) < Self.metres(line.shape[$1], here) })
                XCTAssertLessThan(Self.metres(line.shape[near], here), 150, "\(line.id) \(station.name): off its line")
                at = near
                let distance = try XCTUnwrap(station.distanceKm, station.name)
                XCTAssertGreaterThan(distance, last, "\(line.id) \(station.name)")
                last = distance
            }
            XCTAssertEqual(line.segmentRunSec?.count, line.stations.count - 1, line.id)
            // Running seconds, the stop taken off: the feed gives whole minutes, so a short hop
            // (Central to Admiralty, Airport to AsiaWorld-Expo) is a minute less its stop.
            XCTAssertTrue(line.segmentRunSec?.allSatisfy { ($0 ?? 0) >= 20 && ($0 ?? 0) <= 1_500 } ?? false, line.id)
        }
        var reached: Set<String> = ["機場"]
        var grew = true
        while grew {
            grew = false
            for line in operations.lines where line.stations.contains(where: { reached.contains($0.name) }) {
                let before = reached.count
                reached.formUnion(line.stations.map(\.name))
                grew = grew || reached.count > before
            }
        }
        XCTAssertEqual(reached.count, 97)
    }

    /// Hong Kong International Airport is in the data: Airport station on
    /// the Airport Express, where the map is opened.
    func testTheAirportAndTheAirportExpressAreThere() throws {
        let railways = try Self.railways()
        let express = try XCTUnwrap(railways.operations?.line(id: "AEL", inSystem: "hkmtr"))
        XCTAssertEqual(express.stations.map(\.name), ["香港", "九龍", "青衣", "機場", "博覽館"])
        let airport = try XCTUnwrap(railways.stations.first { $0.system.id == "hkmtr" && $0.chinese == "機場" })
        XCTAssertEqual(airport.english, "Airport")
        XCTAssertLessThan(Self.metres(airport.coordinate, OverseasMap.hongKong.arrival), 100)
    }

    // MARK: - The trains

    /// Every line has trains both ways on every day of the week, from
    /// early morning to past midnight, each calling at every station in
    /// order at the line's running times.
    func testEveryLineIsScheduledBothWays() throws {
        let railways = try Self.railways()
        let operations = try XCTUnwrap(railways.operations)
        let timetable = try XCTUnwrap(operations.timetable(forSystem: "hkmtr"))
        XCTAssertTrue(timetable.isEstimated)
        for expected in Self.lines {
            let line = try XCTUnwrap(timetable.lines[expected.id], expected.id)
            XCTAssertEqual(line.days.count, 7, expected.id)
            for day in Set(line.days) {
                let trips = try XCTUnwrap(line.sets[day], expected.id)
                for forward in [true, false] {
                    let way = trips.filter { ($0.calls.first?.stationIndex ?? 0 < $0.calls.last?.stationIndex ?? 0) == forward }
                    XCTAssertGreaterThan(way.count, 60, "\(expected.id) \(forward ? "down" : "up")")
                    XCTAssertLessThan(try XCTUnwrap(way.map { $0.calls[0].second }.min()), 7 * 3_600, expected.id)
                    XCTAssertGreaterThan(try XCTUnwrap(way.map { $0.calls[0].second }.max()), 23 * 3_600, expected.id)
                    for trip in way {
                        let order = forward ? Array(0..<expected.stations) : Array((0..<expected.stations).reversed())
                        XCTAssertEqual(trip.calls.map(\.stationIndex), order, expected.id)
                        XCTAssertTrue(zip(trip.calls, trip.calls.dropFirst()).allSatisfy { $0.second < $1.second }, expected.id)
                    }
                }
            }
        }
    }

    /// The lines whose day of runs was worked out are on sale on a map of
    /// Hong Kong once it is open, under MTR's names in both languages, and
    /// on no map while it is closed.
    func testTheLinesAreOnSaleOnlyWhenHongKongIsOpen() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 223_200_000, longitude: 1_141_200_000))
        let world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 23, height: 1 << 23), balance: Money(100_000_000_000), rules: .realistic)
        let closed = GameSession(world: world, language: .traditionalChinese)
        closed.railways = try Self.taiwanOnly()
        XCTAssertEqual(closed.buyableRealLines.map(\.id), [])
        let session = GameSession(world: world, language: .traditionalChinese)
        let railways = try Self.railways()
        session.railways = railways
        let withRuns = RealBranchLine.overseasLines.map { "hkmtr:\($0.network)" }.filter { railways.metroRuns[$0] != nil }
        XCTAssertEqual(session.buyableRealLines.map(\.id).sorted(), withRuns.sorted())
        XCTAssertTrue(withRuns.contains("hkmtr:AEL"), "the Airport Express has its day of runs")
        XCTAssertEqual(Set(RealBranchLine.overseasLines.map(\.network)), Set(Self.lines.map(\.id)))
        for line in session.buyableRealLines {
            let runs = try XCTUnwrap(railways.metroRuns[line.id])
            XCTAssertEqual(line.stops, runs.stops, line.id)
            XCTAssertFalse(runs.runs.isEmpty, line.id)
        }
    }

    /// The Airport Express bought as one command and run for two days:
    /// every run of the second day was sent out.
    func testTheAirportExpressIsBoughtAndRuns() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 223_100_000, longitude: 1_140_500_000))
        let world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 23, height: 1 << 23), balance: Money(100_000_000_000), rules: .realistic)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try Self.railways()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:AEL" })
        let offer = session.realLineOffer(for: line)
        XCTAssertNil(offer.problem, offer.problem ?? "")
        let acquisition = try XCTUnwrap(offer.acquisition)
        XCTAssertNotNil(acquisition.color)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        var played = session.world
        let bought = try XCTUnwrap(played.acquisition(of: "hkmtr:AEL"))
        for _ in 0..<51 { try played.advance(ticks: 60) }
        let ran = try XCTUnwrap(played.line(id: try XCTUnwrap(bought.line)))
        let today = played.clock.now.seconds / GameTime.secondsPerDay
        let missed = zip(ran.runs, ran.runDays).filter { run, day in
            run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
        }
        XCTAssertEqual(missed.count, 0, "runs not sent out yesterday: \(missed.count) of \(ran.runs.count)")
    }

    // MARK: - The credits

    /// Open, Hong Kong's railways are credited in both languages: MTR's
    /// open data and its terms, and OpenStreetMap.
    func testHongKongIsCreditedWhenOpen() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let sections = DataSourceCredits.sections(in: language, overseas: [.hongKong])
            XCTAssertEqual(Array(sections.dropLast()), DataSourceCredits.taiwanSections(in: language))
            let credit = try XCTUnwrap(sections.last?.credits.first)
            XCTAssertEqual(sections.last?.id, "hongKongRailways")
            XCTAssertTrue(credit.notice.contains("DATA.GOV.HK"))
            XCTAssertTrue(credit.notice.contains("OpenStreetMap"))
            XCTAssertTrue(credit.notice.contains("ODbL"))
            XCTAssertEqual(credit.links.count, 2)
        }
    }
}
