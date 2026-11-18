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
        XCTAssertEqual(Self.stacked(Self.platforms(of: world, laidBy: laidBy), in: world), [])
    }

    // MARK: - Fukuoka

    /// Fukuoka's three subway lines (decision 854), all bought on one map,
    /// first from the Kuko Line and then from the other end: Hakata (Kuko,
    /// Nanakuma) and Nakasu-Kawabata (Kuko, Hakozaki) stay one station each,
    /// both lines stopping there, and no platform of a station lies over
    /// another of it. Not yet at one height: underground, and with the Kuko
    /// Line bought last, its platforms at both stand 16 m up (the raise
    /// of decision 809, since ``sharedEnds`` moves only a line's ends);
    /// FUKUOKA-INTERCHANGE-LEVEL, before the map opens.
    func testFukuokasInterchangesStackNoPlatforms() throws {
        let interchanges = [("博多", ["fksubway:K", "fksubway:N"]), ("中洲川端", ["fksubway:K", "fksubway:H"])]
        for order in [["fksubway:K", "fksubway:H", "fksubway:N"], ["fksubway:N", "fksubway:H", "fksubway:K"]] {
            let session = try FukuokaRailwaysTests.fukuoka()
            let laidBy = try Self.buy(order, on: session)
            let world = session.world
            let laid = Self.platforms(of: world, laidBy: laidBy)
            XCTAssertEqual(Self.stacked(laid, in: world), [], "\(order)")
            for (name, ids) in interchanges {
                let stations = world.stations.filter { $0.name == name }
                XCTAssertEqual(stations.count, 1, "\(order): one \(name)")
                let station = try XCTUnwrap(stations.first?.id)
                for id in ids {
                    let line = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: id)?.line)))
                    XCTAssertTrue(line.stops.contains(station), "\(order): \(id) stops at \(name)")
                }
                XCTAssertNotNil(Self.between(ids[0], ids[1], at: station, in: laid), "\(order): \(name)")
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

    // MARK: - Taiwan

    /// The Liujia and Neiwan Lines through Zhuzhong, in either order: the
    /// Liujia Line's platforms up on its real viaduct (decision 462), but
    /// beside the Neiwan Line's, not over them.
    func testZhuzhongStacksNoPlatforms() throws {
        for order in [["tra:LIUJIA", "tra:NEIWAN"], ["tra:NEIWAN", "tra:LIUJIA"]] {
            let session = try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple)
            let laidBy = try Self.buy(order, on: session)
            let world = session.world
            XCTAssertEqual(Self.stacked(Self.platforms(of: world, laidBy: laidBy), in: world), [], "\(order)")
        }
    }
}
