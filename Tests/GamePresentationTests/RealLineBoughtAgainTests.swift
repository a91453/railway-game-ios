import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 528 on every map (REBUY-EVERY-MAP): each line of each group
/// of lines sold together (decision 862) removed in its panel and bought
/// again. Hong Kong's Airport Express and Tung Chung Line have a class of
/// their own (`HongKongBoughtAgainTests`), which looks at what counts as
/// in use there.
@MainActor
final class RealLineBoughtAgainTests: XCTestCase {
    /// Where the platforms of `world` stand: each its station and its
    /// middle. By name: a depot taken up with its track is built again.
    private static func standing(in world: GameWorld) -> [(station: String, middle: WorldCoordinate)] {
        world.network.platforms.compactMap { platform in
            guard let geometry = world.trackGeometry(of: platform.edge), let station = world.station(id: platform.station) else { return nil }
            return (station.name, geometry.location(at: (platform.start + platform.end) / 2).position)
        }
    }

    /// The platforms of `after` further than a track's spacing (4 m), in
    /// plan or in height, from every platform their station had in
    /// `before`: each its station, where it stands and how far (plan,
    /// height) from the nearest it had, in metres.
    private static func moved(
        _ after: [(station: String, middle: WorldCoordinate)], from before: [(station: String, middle: WorldCoordinate)]
    ) -> [String] {
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 4 * metre
        return after.compactMap { platform -> String? in
            let apart = before.filter { $0.station == platform.station }.map { other -> (plan: Double, height: Double) in
                let dx = Double(other.middle.x - platform.middle.x), dy = Double(other.middle.y - platform.middle.y)
                return ((dx * dx + dy * dy).squareRoot(), abs(Double(other.middle.z - platform.middle.z)))
            }
            guard !apart.contains(where: { $0.plan <= reach && $0.height <= reach }) else { return nil }
            let nearest = apart.min { max($0.plan, $0.height) < max($1.plan, $1.height) }
            return "\(platform.station): " + (nearest.map { String(format: "%.0f m, %.0f m", $0.plan / metre, $0.height / metre) } ?? "new")
        }.sorted()
    }

    /// The group of `ids` bought together on a game from `open`, then
    /// each of `removed` (all of them by default) in turn, on a game of
    /// its own: removed, it is on sale again alone and is bought again,
    /// taking up all it left; its stations and trains are those it had,
    /// the other lines' track and platforms stay, no platform stands
    /// over another, and every platform stands where the first purchase
    /// stood it (to a track's spacing).
    static func boughtAgain(
        _ ids: [String], _ open: () throws -> GameSession, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for id in ids {
            let session = try open()
            let group = try XCTUnwrap(session.realLineBundles.first { $0.lines.contains { $0.id == id } }, id, file: file, line: line)
            XCTAssertEqual(Set(group.lines.map(\.id)), Set(ids), id, file: file, line: line)
            let first = session.realLineBundleOffer(for: group)
            XCTAssertTrue(session.acquireRealLines(first), "\(id): \(first.problemText(in: .traditionalChinese) ?? session.message?.text ?? "")", file: file, line: line)

            let theirs = Set(ids.filter { $0 != id }.flatMap { session.world.acquisition(of: $0)?.track ?? [] })
            func theirPlatforms() -> [String] {
                session.world.network.platforms.filter { theirs.contains($0.edge) }.map { "\($0.station) \($0.edge) \($0.start)" }
            }
            let platforms = theirPlatforms()
            let stood = standing(in: session.world)
            let stations = session.world.stations.count
            let trains = session.world.trains.count

            let its = try XCTUnwrap(session.world.acquisition(of: id)?.line, id, file: file, line: line)
            session.selectLine(its)
            session.removeSelectedLine()
            XCTAssertNil(session.world.line(id: its), "\(id): \(session.message?.text ?? "")", file: file, line: line)
            let left = Set(session.world.trackLeft(by: id))
            XCTAssertFalse(left.isEmpty, "\(id): its track stays", file: file, line: line)

            let listed = try XCTUnwrap(session.realLineBundles.first { $0.lines.contains { $0.id == id } }, "\(id) on sale again", file: file, line: line)
            XCTAssertEqual(listed.lines.map(\.id), [id], "\(id): alone, the others are the company's", file: file, line: line)
            let offer = session.realLineBundleOffer(for: listed)
            XCTAssertNil(offer.problemText(in: .traditionalChinese), "\(id): \(offer.problemText(in: .traditionalChinese) ?? "")", file: file, line: line)
            let clearing = try XCTUnwrap(offer.acquisitions?.first?.clearing, "\(id): what it left is taken up", file: file, line: line)
            XCTAssertEqual(Set(clearing.edges.map(TrackEdgeID.edge)), left, "\(id): all it left, and only that", file: file, line: line)
            let old = Set(session.world.network.platforms)
            XCTAssertTrue(session.acquireRealLines(offer), "\(id): \(session.message?.text ?? "")", file: file, line: line)

            let world = session.world
            XCTAssertEqual(world.trackLeft(by: id), [], "\(id): bought again, nothing is left", file: file, line: line)
            XCTAssertEqual(world.stations.count, stations, "\(id): its stations are the ones it left", file: file, line: line)
            XCTAssertEqual(world.trains.count, trains, "\(id): with its trains", file: file, line: line)
            XCTAssertTrue(theirs.allSatisfy { world.network.edge($0) != nil }, "\(id): the other lines' track stays", file: file, line: line)
            XCTAssertEqual(theirPlatforms(), platforms, "\(id): and their platforms", file: file, line: line)
            XCTAssertEqual(world.network.platforms.count, stood.count, "\(id): as many platforms", file: file, line: line)
            XCTAssertEqual(Self.moved(Self.standing(in: world), from: stood), [], "\(id): every platform where the first purchase stood it", file: file, line: line)
            var laidBy: [TrackPlatform: String] = [:]
            for platform in world.network.platforms { laidBy[platform] = old.contains(platform) ? "theirs" : id }
            XCTAssertEqual(
                SharedStationLayoutTests.stacked(SharedStationLayoutTests.platforms(of: world, laidBy: laidBy), in: world), [], id, file: file, line: line
            )
            for other in ids {
                let bought = try XCTUnwrap(world.acquisition(of: other)?.line, "\(id) \(other)", file: file, line: line)
                XCTAssertFalse(try XCTUnwrap(world.line(id: bought)).assignedTrains.isEmpty, "\(id) \(other)", file: file, line: line)
            }
        }
    }

    /// LIUJIA-REBUY: the Liujia and Neiwan Lines bought together, the
    /// Liujia Line removed was refused (「這段軌道會與另一段軌道交叉…」):
    /// laid again beside the Neiwan Line's track at Zhuzhong, which was
    /// itself laid beside the Liujia Line's, its hooked way crossed
    /// itself. It is laid where it stood.
    func testZhuzhongsLinesAreBoughtAgain() throws {
        try Self.boughtAgain(["tra:LIUJIA", "tra:NEIWAN"]) {
            try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple)
        }
    }

    /// DANHAI-REBUY-PLACE: the Green Mountain Line bought again stood
    /// elsewhere, nine of its stations some 30 m aside and 10 to 17 m
    /// lower, off their viaduct: laid beside the Blue Coast Line as
    /// decision 493 lays it after that line bought whole, though bought
    /// with it the Blue Coast Line starts at Binhai Shalun.
    func testDanhaisLinesAreBoughtAgain() throws {
        try Self.boughtAgain(["ntdlrt:V", "ntdlrt:VB"]) {
            try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple)
        }
    }

    func testRovaniemisLinesAreBoughtAgain() throws {
        try Self.boughtAgain(["vr:KJA", "vr:MUL"]) { try RovaniemiRailwaysTests.rovaniemi() }
    }

    func testFukuokasLinesAreBoughtAgain() throws {
        try Self.boughtAgain(["fksubway:K", "fksubway:H", "fksubway:N"]) { try FukuokaRailwaysTests.fukuoka() }
    }

    func testHongKongsAirportThreeAreBoughtAgain() throws {
        try Self.boughtAgain(["hkmtr:AEL", "hkmtr:TCL", "hkmtr:DRL"]) { try HongKongMapTests.hongKong() }
    }

    /// A new map's groups are added above: every map has its own here.
    func testEveryOverseasMapHasItsLinesBoughtAgain() {
        XCTAssertEqual(Set(OverseasMap.allCases), [.hongKong, .rovaniemi, .fukuoka], "add the new map's groups of lines to RealLineBoughtAgainTests")
    }
}
