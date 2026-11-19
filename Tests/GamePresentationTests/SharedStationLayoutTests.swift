import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// SHARED-STATION-LEVEL (2026-11-18, the owner's screenshot of Rovaniemi on
/// 138): a second line bought through a station the company already has
/// keeps that station one station: its platforms beside the first line's,
/// never over them. On Rovaniemi's map the two lines' platforms stand at one
/// height, an island between them; on every map (Rovaniemi, Hong Kong,
/// Taiwan) no platform track of a station lies over another of it.
@MainActor
final class SharedStationLayoutTests: XCTestCase {
    private static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A platform as laid: its station, the line that laid it (by the
    /// purchase it came with), its centre line and its height.
    struct Laid {
        let station: StationID
        let line: String
        let points: [WorldCoordinate]
    }

    /// The platforms of `world`, each with the purchase it came with
    /// (`laidBy`, by the platform), sampled every 4 m along its track.
    static func platforms(of world: GameWorld, laidBy: [TrackPlatform: String]) -> [Laid] {
        world.network.platforms.compactMap { platform -> Laid? in
            guard let geometry = world.trackGeometry(of: platform.edge) else { return nil }
            let step: Int64 = 4 * WorldCoordinate.unitsPerMetre
            var points: [WorldCoordinate] = []
            var at: Int64 = platform.start
            while at < platform.end {
                points.append(geometry.location(at: at).position)
                at += step
            }
            points.append(geometry.location(at: platform.end).position)
            return Laid(station: platform.station, line: laidBy[platform] ?? "?", points: points)
        }
    }

    /// Where two platforms of one station lie over each other: within 4 m of
    /// each other in plan (GameCore's least spacing of two tracks side by
    /// side) and 2 m or more apart in height. Each as "station: line over
    /// line".
    static func stacked(_ laid: [Laid], in world: GameWorld) -> [String] {
        var found: [String] = []
        let near = 4 * metre, apart = 2 * metre
        for (i, a) in laid.enumerated() {
            for b in laid[(i + 1)...] where b.station == a.station {
                let over = a.points.contains { p in
                    b.points.contains { q in
                        let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
                        return (dx * dx + dy * dy).squareRoot() < near && abs(Double(p.z - q.z)) >= apart
                    }
                }
                if over { found.append("\(world.station(id: a.station)?.name ?? "?"): \(a.line) / \(b.line)") }
            }
        }
        return found
    }

    /// The least plan distance between a platform of line `a` and one of
    /// line `b` at `station`, in metres, and their heights' greatest
    /// difference.
    static func between(_ a: String, _ b: String, at station: StationID, in laid: [Laid]) -> (distance: Double, height: Double)? {
        let first = laid.filter { $0.station == station && $0.line == a }, second = laid.filter { $0.station == station && $0.line == b }
        guard !first.isEmpty, !second.isEmpty else { return nil }
        var distance = Double.infinity, height = 0.0
        for p in first.flatMap(\.points) {
            for q in second.flatMap(\.points) {
                let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
                distance = min(distance, (dx * dx + dy * dy).squareRoot())
                height = max(height, abs(Double(p.z - q.z)))
            }
        }
        return (distance / metre, height / metre)
    }

    /// The stations two purchases laid platforms at whose platforms stand
    /// more than half a metre apart in height, by name (decision 875: one
    /// station, one level).
    static func uneven(_ laid: [Laid], in world: GameWorld) -> [String] {
        Dictionary(grouping: laid, by: \.station).compactMap { station, platforms -> String? in
            let heights = platforms.flatMap(\.points).map(\.z)
            guard Set(platforms.map(\.line)).count > 1, let low = heights.min(), let high = heights.max(),
                  Double(high - low) > metre / 2 else { return nil }
            return world.station(id: station)?.name
        }.sorted()
    }

    /// How far over the ground each platform of `station` stands at its
    /// middle, in metres.
    static func overGround(_ station: StationID, in world: GameWorld) -> [Double] {
        world.network.platforms(of: station).compactMap { platform in
            guard let geometry = world.trackGeometry(of: platform.edge) else { return nil }
            let middle = geometry.location(at: (platform.start + platform.end) / 2).position
            return (Double(middle.z) - Double(world.groundHeight(at: middle.plan) ?? 0)) / metre
        }
    }

    /// Buys `ids` in order on `session`, recording which purchase laid each
    /// platform.
    static func buy(_ ids: [String], on session: GameSession, file: StaticString = #filePath, line: UInt = #line) throws -> [TrackPlatform: String] {
        var laidBy: [TrackPlatform: String] = [:]
        for id in ids {
            let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(ids): \(id) on sale", file: file, line: line)
            let offer = session.realLineOffer(for: real)
            XCTAssertNil(offer.problem, "\(ids): \(id)", file: file, line: line)
            XCTAssertTrue(session.acquireRealLine(offer), "\(ids): \(id): \(session.message?.text ?? "")", file: file, line: line)
            for platform in session.world.network.platforms where laidBy[platform] == nil {
                laidBy[platform] = id
            }
        }
        return laidBy
    }

    // MARK: - Rovaniemi

    /// The owner's screenshot: the Kemijärvi and Muurola lines both end at
    /// Rovaniemi. Bought in either order, the second's platforms there stand
    /// at the first's height (within 0.5 m), beside them (an island's width,
    /// 11 m, between the two lines' nearest tracks, so the 3D map draws one
    /// island between them), and none over another. Before, the second's
    /// four stood 16 m up, each within a metre of one of the first's.
    func testRovaniemisTwoLinesShareOneLevel() throws {
        for order in [["vr:KJA", "vr:MUL"], ["vr:MUL", "vr:KJA"]] {
            let session = try RovaniemiRailwaysTests.rovaniemi()
            let laidBy = try Self.buy(order, on: session)
            let world = session.world
            let laid = Self.platforms(of: world, laidBy: laidBy)
            XCTAssertEqual(Self.stacked(laid, in: world), [], "\(order)")
            XCTAssertEqual(Self.uneven(laid, in: world), [], "\(order)")
            let rovaniemi = try XCTUnwrap(world.stations.first { $0.name == "羅瓦涅米" }?.id)
            let lines = try order.map { id in try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: id)?.line))) }
            XCTAssertTrue(lines.allSatisfy { $0.stops.contains(rovaniemi) }, "\(order): one Rovaniemi of both lines")
            let pair = try XCTUnwrap(Self.between(order[0], order[1], at: rovaniemi, in: laid), "\(order)")
            XCTAssertLessThanOrEqual(pair.height, 0.5, "\(order): the two lines' platforms at one height")
            XCTAssertGreaterThanOrEqual(pair.distance, 8, "\(order): an island's width between the two lines")
            XCTAssertLessThanOrEqual(pair.distance, 15, "\(order): within the 3D map's island pairing")
        }
    }

    // MARK: - Hong Kong

    /// Every line on sale bought, one after another, on Hong Kong's map: no
    /// platform track of a station over another of it, the interchanges
    /// included.
    func testHongKongsInterchangesStackNoPlatforms() throws {
        let session = try HongKongMapTests.hongKong()
        let laidBy = try Self.buy(session.buyableRealLines.map(\.id).sorted(), on: session)
        let world = session.world
        let laid = Self.platforms(of: world, laidBy: laidBy)
        XCTAssertEqual(Self.stacked(laid, in: world), [])
        // Decision 863: at the stations the line bought second shares, at
        // one height (Kowloon was 4.9 m apart, Sunny Bay 5.8 m). Decision
        // 875: Tsing Yi's too, both lines' on the real viaduct (the
        // Airport Express's stood 11.6 m under the Tung Chung Line's).
        XCTAssertEqual(Self.uneven(laid, in: world), [])
        for (name, ids) in [
            ("香港", ["hkmtr:AEL", "hkmtr:TCL"]), ("九龍", ["hkmtr:AEL", "hkmtr:TCL"]), ("青衣", ["hkmtr:AEL", "hkmtr:TCL"]),
            ("欣澳", ["hkmtr:DRL", "hkmtr:TCL"]),
        ] {
            let station = try XCTUnwrap(world.stations.first { $0.name == name }?.id, name)
            let pair = try XCTUnwrap(Self.between(ids[0], ids[1], at: station, in: laid), name)
            XCTAssertLessThanOrEqual(pair.height, 0.5, "\(name): the two lines' platforms at one height")
        }
    }

    /// Decision 875 (TSING-YI-LEVEL): the Airport Express and the Tung
    /// Chung Line at Tsing Yi, in the order the three are sold together
    /// (decision 862) and the two others a game may have bought them in:
    /// both lines' platforms up on the station's real viaduct (decision
    /// 462), at one height, the Airport Express's in its lane beside the
    /// Tung Chung Line's. Before, the Airport Express's stood 4.4 m over
    /// the ground (6.5 m bought second) under the Tung Chung Line's 16 m:
    /// laid 25 m beside the drawing (decision 753), it found none of the
    /// viaduct, looked for within 20 m.
    func testTsingYisTwoLinesStandOnOneViaduct() throws {
        for order in [["hkmtr:AEL", "hkmtr:TCL", "hkmtr:DRL"], ["hkmtr:TCL", "hkmtr:AEL", "hkmtr:DRL"], ["hkmtr:DRL", "hkmtr:TCL", "hkmtr:AEL"]] {
            let session = try HongKongMapTests.hongKong()
            let laidBy = try Self.buy(order, on: session)
            let world = session.world
            let laid = Self.platforms(of: world, laidBy: laidBy)
            XCTAssertEqual(Self.stacked(laid, in: world), [], "\(order)")
            XCTAssertEqual(Self.uneven(laid, in: world), [], "\(order)")
            let tsingYi = try XCTUnwrap(world.stations.first { $0.name == "青衣" }?.id)
            let pair = try XCTUnwrap(Self.between("hkmtr:AEL", "hkmtr:TCL", at: tsingYi, in: laid), "\(order)")
            XCTAssertLessThanOrEqual(pair.height, 0.5, "\(order): the two lines' platforms at one height")
            XCTAssertGreaterThanOrEqual(pair.distance, 8, "\(order): an island's width or more between the two lines")
            let over = Self.overGround(tsingYi, in: world)
            XCTAssertEqual(over.count, 4, "\(order): two platforms of each line")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(over.min()), 10, "\(order): every platform up on the viaduct")
        }
    }

    // MARK: - Fukuoka

    /// Fukuoka's three subway lines (decision 854), all bought on one map,
    /// first from the Kuko Line and then from the other end: Hakata (Kuko,
    /// Nanakuma) and Nakasu-Kawabata (Kuko, Hakozaki) stay one station each,
    /// both lines stopping there, no platform of a station lies over
    /// another of it, and the two lines' platforms stand at one height
    /// (within 0.5 m), an island's width or more apart. Decision 863
    /// (SHARED-STATION-THROUGH): before, with the Kuko Line bought last its
    /// platforms at both stood 16 m up (the raise of decision 809:
    /// ``RealLineLaying/sharedEnds(of:points:through:shared:extent:)``
    /// moved only a line's ends, and the Kuko Line runs through both), and
    /// with it bought first the Hakozaki Line stood 5.9 m over it at
    /// Nakasu-Kawabata and the Nanakuma Line 3.1 m at Hakata (a platform
    /// a few metres down was not counted as one to stand level with).
    func testFukuokasInterchangesStackNoPlatforms() throws {
        let interchanges = [("博多", ["fksubway:K", "fksubway:N"]), ("中洲川端", ["fksubway:K", "fksubway:H"])]
        for order in [["fksubway:K", "fksubway:H", "fksubway:N"], ["fksubway:N", "fksubway:H", "fksubway:K"]] {
            let session = try FukuokaRailwaysTests.fukuoka()
            let laidBy = try Self.buy(order, on: session)
            let world = session.world
            let laid = Self.platforms(of: world, laidBy: laidBy)
            XCTAssertEqual(Self.stacked(laid, in: world), [], "\(order)")
            XCTAssertEqual(Self.uneven(laid, in: world), [], "\(order)")
            for (name, ids) in interchanges {
                let stations = world.stations.filter { $0.name == name }
                XCTAssertEqual(stations.count, 1, "\(order): one \(name)")
                let station = try XCTUnwrap(stations.first?.id)
                for id in ids {
                    let line = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: id)?.line)))
                    XCTAssertTrue(line.stops.contains(station), "\(order): \(id) stops at \(name)")
                }
                let pair = try XCTUnwrap(Self.between(ids[0], ids[1], at: station, in: laid), "\(order): \(name)")
                XCTAssertLessThanOrEqual(pair.height, 0.5, "\(order): \(name): the two lines' platforms at one height")
                XCTAssertGreaterThanOrEqual(pair.distance, 8, "\(order): \(name): an island's width or more between the two lines")
            }
        }
    }

    // MARK: - Every map

    /// The maps this file buys every shared station of. A new
    /// ``OverseasMap`` needs its own test above before it is added here
    /// (real-line-laying §2): decision 854 left Fukuoka's out at first.
    static let mapsChecked: Set<OverseasMap> = [.hongKong, .rovaniemi, .fukuoka]

    func testEveryOverseasMapHasItsSharedStationsChecked() {
        XCTAssertEqual(Set(OverseasMap.allCases), Self.mapsChecked,
                       "A new map's lines are bought together here, both orders where two share a station (real-line-laying §2)")
    }

    // MARK: - The report

    /// Every station two purchases laid platforms at, each line's
    /// platforms there: how far over the ground (metres, lowest to
    /// highest), their height, and from the first line's the least plan
    /// distance and the greatest difference in height.
    static func report(_ title: String, of world: GameWorld, laidBy: [TrackPlatform: String]) -> [String] {
        var lines = ["SHARED \(title)"]
        let byStation = Dictionary(grouping: world.network.platforms.filter { laidBy[$0] != nil }, by: \.station)
        let laid = platforms(of: world, laidBy: laidBy)
        for (station, platforms) in byStation.sorted(by: { $0.key < $1.key }) {
            let ids = Set(platforms.compactMap { laidBy[$0] }).sorted()
            guard ids.count > 1, let name = world.station(id: station)?.name else { continue }
            var row = "SHARED   \(name):"
            for id in ids {
                let overs = platforms.filter { laidBy[$0] == id }.compactMap { platform -> (over: Double, z: Double)? in
                    guard let geometry = world.trackGeometry(of: platform.edge) else { return nil }
                    let middle = geometry.location(at: (platform.start + platform.end) / 2).position
                    return ((Double(middle.z) - Double(world.groundHeight(at: middle.plan) ?? 0)) / metre, Double(middle.z) / metre)
                }
                let over = overs.map(\.over), z = overs.map(\.z)
                row += String(format: " %@ ×%d over %.1f…%.1f z %.1f…%.1f;", id, overs.count, over.min() ?? 0, over.max() ?? 0, z.min() ?? 0, z.max() ?? 0)
            }
            for id in ids.dropFirst() {
                if let pair = between(ids[0], id, at: station, in: laid) {
                    row += String(format: " %@/%@ %.1f m apart, %.1f m in height;", ids[0], id, pair.distance, pair.height)
                }
            }
            lines.append(row)
        }
        return lines
    }

    /// TSING-YI-LEVEL: the shared stations of every map, in the order the
    /// lines are sold together and the other way, written to the file
    /// `SHARED_STATION_REPORT` names; skipped without it.
    /// `SHARED_STATION_ONLY=zhuzhong` (or `hongkong`, `danhai`,
    /// `rovaniemi`, `fukuoka`) for one map's.
    func testReport() throws {
        guard let path = ProcessInfo.processInfo.environment["SHARED_STATION_REPORT"] else {
            throw XCTSkip("SHARED_STATION_REPORT=<file to write> prints every shared station's platforms")
        }
        var lines: [String] = []
        let only = ProcessInfo.processInfo.environment["SHARED_STATION_ONLY"]
        func buy(_ title: String, _ ids: [String], _ open: () throws -> GameSession) throws {
            guard only.map({ $0 == title }) ?? true else { return }
            let session = try open()
            var laidBy: [TrackPlatform: String] = [:]
            for id in ids {
                guard let real = session.buyableRealLines.first(where: { $0.id == id }) else {
                    lines.append("SHARED \(title): \(id) not on sale")
                    continue
                }
                let offer = session.realLineOffer(for: real)
                guard session.acquireRealLine(offer) else {
                    lines.append("SHARED \(title): \(id) refused: \(offer.problem ?? session.message?.text ?? "")")
                    continue
                }
                lines.append("SHARED_PRICE \(title) \(id) total=\(offer.price?.total.amount ?? 0) building=\(offer.price?.building.amount ?? 0)")
                for platform in session.world.network.platforms where laidBy[platform] == nil { laidBy[platform] = id }
                // `SHARED_STATION_PROFILE=<ids>`: the line's first track
                // too, node by node: how far along, its height and how
                // far over the ground (metres).
                if ProcessInfo.processInfo.environment["SHARED_STATION_PROFILE"]?.split(separator: ",").contains(Substring(id)) == true,
                   let nodes = offer.acquisition?.pieces.first?.nodes {
                    var along = 0.0
                    var row = "SHARED_PROFILE \(title) \(id):"
                    for (index, node) in nodes.enumerated() {
                        if index > 0 {
                            let dx = Double(node.x - nodes[index - 1].x), dy = Double(node.y - nodes[index - 1].y)
                            along += (dx * dx + dy * dy).squareRoot() / Self.metre
                        }
                        let over = (Double(node.z) - Double(session.world.groundHeight(at: node.plan) ?? 0)) / Self.metre
                        row += String(format: " %.0f:%.1f/%+.1f", along, Double(node.z) / Self.metre, over)
                    }
                    lines.append(row)
                }
            }
            lines += Self.report("\(title) \(ids)", of: session.world, laidBy: laidBy)
        }
        let hongKong = try HongKongMapTests.hongKong().buyableRealLines.map(\.id)
        let airport = ["hkmtr:AEL", "hkmtr:TCL", "hkmtr:DRL"]
        try buy("hongkong", hongKong) { try HongKongMapTests.hongKong() }
        try buy("hongkong", ["hkmtr:TCL", "hkmtr:AEL", "hkmtr:DRL"]) { try HongKongMapTests.hongKong() }
        try buy("hongkong", Array(airport.reversed())) { try HongKongMapTests.hongKong() }
        for order in [["tra:LIUJIA", "tra:NEIWAN"], ["tra:NEIWAN", "tra:LIUJIA"]] {
            try buy("zhuzhong", order) { try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple) }
        }
        for order in [["ntdlrt:V", "ntdlrt:VB"], ["ntdlrt:VB", "ntdlrt:V"]] {
            try buy("danhai", order) { try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple) }
        }
        for order in [["vr:KJA", "vr:MUL"], ["vr:MUL", "vr:KJA"]] {
            try buy("rovaniemi", order) { try RovaniemiRailwaysTests.rovaniemi() }
        }
        for order in [["fksubway:K", "fksubway:H", "fksubway:N"], ["fksubway:N", "fksubway:H", "fksubway:K"]] {
            try buy("fukuoka", order) { try FukuokaRailwaysTests.fukuoka() }
        }
        try lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Taiwan

    /// The Liujia and Neiwan Lines through Zhuzhong, in either order: the
    /// Liujia Line's platforms up on its real viaduct (decision 462), but
    /// beside the Neiwan Line's, not over them.
    /// ZHUZHONG-LEVEL (the owner on 140: 「竹中一個高架一個地面」): bought
    /// together, in the order they are sold (decision 862), the two lines
    /// stand on one viaduct at Zhuzhong, as the real station's three tracks
    /// on its second floor do: one level (within 0.5 m), well over the
    /// ground, and an island between them (their nearest tracks within the
    /// 15 m the 3D map draws one island across). Before, the Liujia Line's
    /// way doubled back at Zhuzhong, its platforms stood square to the
    /// Neiwan Line's across them, and the Neiwan Line's stayed on the
    /// ground 13.6 m under, 32 m off.
    func testZhuzhongsTwoLinesStandOnOneViaduct() throws {
        let session = try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple)
        let laidBy = try Self.buy(["tra:LIUJIA", "tra:NEIWAN"], on: session)
        let world = session.world
        let laid = Self.platforms(of: world, laidBy: laidBy)
        XCTAssertEqual(Self.stacked(laid, in: world), [])
        XCTAssertEqual(Self.uneven(laid, in: world), [])
        let zhuzhong = try XCTUnwrap(world.stations.first { $0.name == "竹中" }?.id)
        let pair = try XCTUnwrap(Self.between("tra:LIUJIA", "tra:NEIWAN", at: zhuzhong, in: laid))
        XCTAssertLessThan(pair.distance, 15, "an island between the two lines")
        XCTAssertGreaterThan(pair.distance, 9, "beside each other, not over")
        XCTAssertTrue(Self.overGround(zhuzhong, in: world).allSatisfy { $0 > 8 }, "both up on the viaduct")
    }

    func testZhuzhongStacksNoPlatforms() throws {
        for order in [["tra:LIUJIA", "tra:NEIWAN"], ["tra:NEIWAN", "tra:LIUJIA"]] {
            let session = try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple)
            let laidBy = try Self.buy(order, on: session)
            let world = session.world
            XCTAssertEqual(Self.stacked(Self.platforms(of: world, laidBy: laidBy), in: world), [], "\(order)")
        }
    }

    /// Decision 875: the Danhai light rail's two lines in the order they
    /// are sold together (decision 862): at Binhai Shalun the Blue Coast
    /// Line's platforms stand at the Green Mountain Line's, which are 5 m
    /// over ground that falls away there (they stood 3.2 m under them: a
    /// platform that far up was not counted as one to stand level with).
    func testBinhaiShalunsTwoLinesStandAtOneLevel() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple)
        let laidBy = try Self.buy(["ntdlrt:V", "ntdlrt:VB"], on: session)
        let world = session.world
        let laid = Self.platforms(of: world, laidBy: laidBy)
        XCTAssertEqual(Self.stacked(laid, in: world), [])
        XCTAssertEqual(Self.uneven(laid, in: world), [])
        let shalun = try XCTUnwrap(world.stations.first { $0.name == "濱海沙崙" }?.id)
        let pair = try XCTUnwrap(Self.between("ntdlrt:V", "ntdlrt:VB", at: shalun, in: laid))
        XCTAssertLessThanOrEqual(pair.height, 0.5, "the two lines' platforms at one height")
    }

    /// DANHAI-OLD-SAVE: a game saved before the two were sold together
    /// (decision 862) may hold the Blue Coast Line alone, bought whole
    /// from Hongshulin. The Green Mountain Line bought after it lies 30 m
    /// beside it to Binhai Shalun (decision 493), off the real viaduct
    /// the two share: its platforms stood on the ground, 10 to 17 m under
    /// the Blue Coast Line's at seven stations. They stand at one level,
    /// but at Hongshulin: its end there is longer than the Blue Coast
    /// Line's, and no grade reaches both that line's platforms there and
    /// the next station's (2.6 m apart, DANHAI-HONGSHULIN-LEVEL).
    func testTheGreenMountainLineAfterTheBlueCoastLineStandsAtItsLevel() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple)
        let laidBy = try Self.buy(["ntdlrt:VB", "ntdlrt:V"], on: session)
        let world = session.world
        let laid = Self.platforms(of: world, laidBy: laidBy)
        XCTAssertEqual(Self.stacked(laid, in: world), [])
        XCTAssertEqual(Self.uneven(laid, in: world).filter { $0 != "紅樹林" }, [])
        let hongshulin = try XCTUnwrap(world.stations.first { $0.name == "紅樹林" }?.id)
        let pair = try XCTUnwrap(Self.between("ntdlrt:V", "ntdlrt:VB", at: hongshulin, in: laid))
        XCTAssertLessThanOrEqual(pair.height, 3, "both on the viaduct there")
    }
}
