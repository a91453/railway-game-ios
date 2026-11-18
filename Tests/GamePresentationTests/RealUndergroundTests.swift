import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 867 (REAL-UNDERGROUND): every line on sale on Hong Kong's and
/// Fukuoka's maps bought, the stations of the real lines' tunnels stand
/// in tunnels; decision 871, Taiwan's too (Qizhang, Huanbei). ``testReport()`` writes each platform as laid (its
/// section's kind and how far over the ground) beside the real line there
/// (within 30 m of a tunnel of `rail_structures.json` or not) and each
/// line's price, only when asked (`REAL_UNDERGROUND_REPORT=<file to write>`).
@MainActor
final class RealUndergroundTests: XCTestCase {
    private static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A platform as laid and as the real line is there.
    struct Row {
        let station: String
        let line: String
        let kind: TrackSectionKind
        /// Metres over the ground (negative under it).
        let over: Double
        let realTunnel: Bool
    }

    /// Whether `point` is within 30 m of a real tunnel of `system`.
    static func realTunnels(_ structures: RealRailStructures, system: String, frame: RealWorldFrame) -> (WorldVector) -> Bool {
        var segments: [(a: WorldVector, b: WorldVector)] = []
        for structure in structures.structures where structure.system == system && structure.kind == .tunnel {
            let points = structure.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            for index in points.indices.dropLast() { segments.append((points[index], points[index + 1])) }
        }
        return { point in
            segments.contains { segment in
                let d = segment.b - segment.a
                let lengthSquared = d.dot(d)
                let t = lengthSquared > 0 ? max(0, min(1, (point - segment.a).dot(d) / lengthSquared)) : 0
                return (point - (segment.a + d * t)).length < 30 * metre
            }
        }
    }

    static func rows(of world: GameWorld, laidBy: [TrackPlatform: String], structures: RealRailStructures, system: String) throws -> [Row] {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let inTunnel = realTunnels(structures, system: system, frame: frame)
        return world.network.platforms.compactMap { platform -> Row? in
            guard let station = world.station(id: platform.station), !station.isDepot,
                  let geometry = world.trackGeometry(of: platform.edge), let edge = world.network.edge(platform.edge) else { return nil }
            let middle = (platform.start + platform.end) / 2
            let position = geometry.location(at: middle).position
            let kind = edge.sectionSpans.first { $0.start <= middle && middle < $0.end }?.kind ?? .surface
            let ground = Double(world.groundHeight(at: position.plan) ?? 0)
            return Row(
                station: station.name, line: laidBy[platform] ?? "?", kind: kind, over: (Double(position.z) - ground) / metre,
                realTunnel: inTunnel(WorldVector(x: Double(position.x), y: Double(position.y)))
            )
        }
    }

    /// Buys `ids` in order, noting each line's price as offered.
    static func buy(_ ids: [String], on session: GameSession) throws -> (laidBy: [TrackPlatform: String], prices: [String]) {
        var laidBy: [TrackPlatform: String] = [:], prices: [String] = []
        for id in ids {
            let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
            let offer = session.realLineOffer(for: real)
            prices.append("UG_PRICE \(id) total=\(offer.price?.total.amount ?? 0) building=\(offer.price?.building.amount ?? 0)")
            laidBy.merge(try SharedStationLayoutTests.buy([id], on: session)) { old, _ in old }
        }
        return (laidBy, prices)
    }

    static func hongKongRows() throws -> (rows: [Row], prices: [String]) {
        let session = try HongKongMapTests.hongKong()
        let bought = try buy(session.buyableRealLines.map(\.id), on: session)
        let rows = try rows(of: session.world, laidBy: bought.laidBy, structures: try XCTUnwrap(session.railways?.structures), system: OverseasMap.hongKong.system)
        return (rows, bought.prices)
    }

    /// In the order the three are sold together (decision 862), unless
    /// another is asked for.
    static func fukuokaRows(_ order: [String] = ["fksubway:K", "fksubway:H", "fksubway:N"]) throws -> (rows: [Row], prices: [String]) {
        let session = try FukuokaRailwaysTests.fukuoka()
        let bought = try buy(order, on: session)
        let rows = try rows(of: session.world, laidBy: bought.laidBy, structures: try XCTUnwrap(session.railways?.structures), system: OverseasMap.fukuoka.system)
        return (rows, bought.prices)
    }

    /// The stations of `rows` with a platform in a tunnel, and those with
    /// one that is not.
    static func stations(_ rows: [Row]) -> (under: Set<String>, open: Set<String>) {
        (Set(rows.filter { $0.kind == .tunnel }.map(\.station)), Set(rows.filter { $0.kind != .tunnel }.map(\.station)))
    }

    /// Hong Kong's lines all bought: the stations of the real lines'
    /// tunnels are laid in tunnels, every platform of them, both lines' at
    /// Hong Kong and Kowloon; the others are not. Before decision 867 only
    /// Lei Tung was.
    func testHongKongsUndergroundStationsAreLaidInTunnels() throws {
        let found = Self.stations(try Self.hongKongRows().rows)
        XCTAssertEqual(found.under, ["香港", "九龍", "金鐘", "利東", "海怡半島", "東涌", "將軍澳"])
        XCTAssertEqual(found.under.intersection(found.open), [], "a station partly in a tunnel")
    }

    /// Fukuoka's three lines bought as they are sold: every station in a
    /// tunnel but Meinohama (on its viaduct) and Kaizuka (on the ground),
    /// as the real ones. Before decision 867 none was.
    func testFukuokasUndergroundStationsAreLaidInTunnels() throws {
        let found = Self.stations(try Self.fukuokaRows().rows)
        XCTAssertEqual(found.open, ["姪濱", "貝塚"])
        XCTAssertEqual(found.under.count, 34)
        XCTAssertEqual(found.under.intersection(found.open), [])
    }

    /// A Taiwan line bought on its city's real opening (which reads the
    /// water and the heights, as a player's game does), built on a pricing
    /// copy as ``LineHeightReportTests`` builds it: the world and the main
    /// track's path.
    static func taiwanLaid(_ id: String, opening: String) throws -> (world: GameWorld, path: WorldPath) {
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let city = try XCTUnwrap(AcquisitionReportTests.cities.first { $0.name == opening })
        let start = try XCTUnwrap(GeoAnchor(latitudeDegrees: city.latitude, longitudeDegrees: city.longitude))
        let world = GameLauncher.newWorld(at: start, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.coverage = data.coverage
        session.railways = data.railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(id) on sale")
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        var built = session.world.pricingCopy()
        _ = try session.buildStepByStep(acquisition, in: &built, recording: false)
        return (built, WorldPath(acquisition.pieces[0].nodes.map { WorldVector(x: Double($0.x), y: Double($0.y)) }))
    }

    /// The kinds of the sections under the platforms of the station named `name`.
    static func platformKinds(of name: String, in world: GameWorld) throws -> [TrackSectionKind] {
        let station = try XCTUnwrap(world.stations.first { $0.name == name && !$0.isDepot }, name)
        return world.network.platforms(of: station.id).compactMap { platform in
            let middle = (platform.start + platform.end) / 2
            return world.network.edge(platform.edge)?.sectionSpans.first { $0.start <= middle && middle < $0.end }?.kind
        }
    }

    /// Decision 871: the Xiaobitan Branch Line's Qizhang, in the real
    /// line's tunnel, is laid in one (it stood on the ground), and
    /// Xiaobitan stays on its viaduct.
    func testQizhangOnTheXiaobitanBranchIsLaidInATunnel() throws {
        let laid = try Self.taiwanLaid("trtc:G_XBT", opening: "Taipei")
        let qizhang = try Self.platformKinds(of: "七張", in: laid.world)
        XCTAssertFalse(qizhang.isEmpty)
        XCTAssertEqual(Set(qizhang), [.tunnel])
        XCTAssertEqual(Set(try Self.platformKinds(of: "小碧潭", in: laid.world)), [.viaduct])
    }

    /// Decision 871: the Taoyuan Airport MRT's Huanbei, in the real
    /// line's tunnel, is laid in one (it stood in a cutting), and the
    /// line passes under the Tamsui River in its real tunnel from Taipei
    /// Main Station (it crossed on a bridge 5 m over the water): no
    /// bridge in the first 2.4 km.
    func testTheAirportLineIsLaidUnderTheTamsuiRiverAndAtHuanbei() throws {
        let laid = try Self.taiwanLaid("tymc:A", opening: "Taoyuan")
        XCTAssertEqual(Set(try Self.platformKinds(of: "環北站", in: laid.world)), [.tunnel])
        XCTAssertEqual(Set(try Self.platformKinds(of: "台北車站", in: laid.world)), [.tunnel])
        XCTAssertEqual(Set(try Self.platformKinds(of: "三重站", in: laid.world)), [.viaduct])
        var bridged = 0
        for edge in laid.world.network.edges {
            let geometry = try XCTUnwrap(laid.world.trackGeometry(of: edge.id))
            for span in edge.sectionSpans where span.kind == .bridge && span.end > span.start {
                for point in geometry.points(from: span.start, to: span.end) {
                    let near = laid.path.nearest(WorldVector(x: Double(point.x), y: Double(point.y)))
                    if near.away < 30 * Self.metre, near.along < 2400 * Self.metre { bridged += 1 }
                }
            }
        }
        XCTAssertEqual(bridged, 0, "points on a bridge over the Tamsui River")
    }

    func testReport() throws {
        guard let path = ProcessInfo.processInfo.environment["REAL_UNDERGROUND_REPORT"] else {
            throw XCTSkip("Set REAL_UNDERGROUND_REPORT=<file> to write where the bought lines' platforms stand.")
        }
        var out: [String] = []
        for (name, found) in [("HongKong", try Self.hongKongRows()), ("Fukuoka", try Self.fukuokaRows())] {
            out += found.prices
            let rows = found.rows
            for row in rows.sorted(by: { ($0.line, $0.station) < ($1.line, $1.station) }) {
                out.append("UG_PLATFORM \(name) \(row.line) \(row.station) \(row.kind) \(String(format: "%.1f", row.over)) real=\(row.realTunnel ? "tunnel" : "open")")
            }
            let real = rows.filter(\.realTunnel)
            out.append("UG_SUMMARY \(name): \(rows.count) platforms, \(rows.filter { $0.kind == .tunnel }.count) in tunnels; real tunnel \(real.count), of them laid in tunnels \(real.filter { $0.kind == .tunnel }.count); laid in a tunnel where the real line is open \(rows.filter { !$0.realTunnel && $0.kind == .tunnel }.count)")
        }
        try out.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
