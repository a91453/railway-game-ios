import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 920 (ZEBRA-LOOK; the owner's screenshot of 2026-11-21, 「大概像
/// 這樣一坨 明明不用那麼多」): OSM draws a divided road as two one-way
/// carriageways, so one crossroads is four to nine points where roads
/// cross, and each point got its own crossings, stop lines, boxes and
/// signals. The points joined by short roads are one junction: clear
/// inside, its crossings round the outer edge, one way's paint and signal
/// per carriageway coming in, and all its signals in one group.
final class Map3DCrossroadsClusterTests: XCTestCase {
    private typealias Point = Map3DBaseMap.Point

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ kind: Map3DBaseMap.RoadKind, _ points: [(Double, Double)], oneway: Bool = false) -> Map3DBaseMap.Road {
        var road = Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Point(x: $0.0, z: $0.1) }, bounds: everywhere)
        road.oneway = oneway
        return road
    }

    /// Two divided primary roads crossing at the origin, their
    /// carriageways 24 m apart (centre to centre), traffic on the right
    /// (+z is south): four points where carriageways cross.
    private var dividedCrossroads: [Map3DBaseMap.Road] {
        [road(.primary, [(-12, -200), (-12, -12), (-12, 12), (-12, 200)], oneway: true),  // southbound, west side
         road(.primary, [(12, 200), (12, 12), (12, -12), (12, -200)], oneway: true),      // northbound, east side
         road(.primary, [(-200, 12), (-12, 12), (12, 12), (200, 12)], oneway: true),      // eastbound, south side
         road(.primary, [(200, -12), (12, -12), (-12, -12), (-200, -12)], oneway: true)]  // westbound, north side
    }

    private func isInside(_ p: Point, _ edge: Double) -> Bool { abs(p.x) < edge && abs(p.z) < edge }

    func testADividedCrossroadsIsOneJunction() {
        let markings = Map3DRoadMarkings(dividedCrossroads)
        XCTAssertEqual(markings.junctions.count, 4, "four points where the carriageways cross")
        let crosswalks = markings.marks.filter { $0.kind == .crosswalk }, stops = markings.marks.filter { $0.kind == .stopLine }
        // Before decision 920: 16 crossings (each point's four arms), 16
        // stop lines and 16 signals, eight of each inside the junction.
        // A crossing across each carriageway on the four ways out: two a
        // way, side by side.
        XCTAssertEqual(crosswalks.count, 8)
        // The carriageway coming in, one each way: a stop line and a signal.
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(markings.signals.count, 4)
        XCTAssertEqual(markings.stops.count, 4)
        // Nothing painted inside: the carriageways' outer kerbs are 16.5 m
        // out (12 + 4.5).
        for mark in markings.marks { XCTAssertFalse(isInside(mark.centre, 16.5), "\(mark.kind) at \(mark.centre)") }
        // The two crossings of a way in line, across the whole road.
        for way in [Point(x: 1, z: 0), Point(x: -1, z: 0), Point(x: 0, z: 1), Point(x: 0, z: -1)] {
            let pair = crosswalks.filter { Map3DRoadMarkings.dot($0.centre, way) > 16 }
            XCTAssertEqual(pair.count, 2, "\(way)")
            XCTAssertEqual(Map3DRoadMarkings.dot(pair[0].centre, way), Map3DRoadMarkings.dot(pair[1].centre, way), accuracy: 1e-9)
        }
        // Each stop line across its whole carriageway, before its crossing.
        for stop in stops {
            XCTAssertEqual(stop.width, 9 - 0.3, accuracy: 1e-9)
            let side = Point(x: -stop.along.z, z: stop.along.x)
            let carriageway = Map3DRoadMarkings.dot(stop.centre, side)
            // The carriageway on the right of its traffic: 12 m to the
            // right of the junction's middle.
            XCTAssertEqual(carriageway, 12, accuracy: 1e-6)
        }
        // One junction, one group of the clock's.
        XCTAssertEqual(Set(markings.signals.map(\.group)).count, 1)
        XCTAssertEqual(Set(markings.walks.map(\.group)), Set(markings.signals.map(\.group)))
        // Each signal on the kerb on the right of its traffic.
        for signal in markings.signals {
            let right = Point(x: -signal.along.z, z: signal.along.x)
            XCTAssertGreaterThan(Map3DRoadMarkings.dot(right, signal.foot), 12 + 4.5)
        }
        // The centre lines are left out inside the junction.
        for (number, road) in dividedCrossroads.enumerated() {
            let pieces = markings.centreLines(of: road, number: number)
            for piece in pieces { for p in piece { XCTAssertFalse(isInside(p, 13), "road \(number) centre line at \(p)") } }
        }
    }

    /// A divided road crossed by a two-way one: two points, one junction.
    func testADividedRoadCrossedByATwoWayRoad() {
        let roads = [road(.primary, [(-12, -200), (-12, 0), (-12, 200)], oneway: true),
                     road(.primary, [(12, 200), (12, 0), (12, -200)], oneway: true),
                     road(.secondary, [(-200, 0), (-12, 0), (12, 0), (200, 0)])]
        let markings = Map3DRoadMarkings(roads)
        XCTAssertEqual(markings.junctions.count, 2)
        let crosswalks = markings.marks.filter { $0.kind == .crosswalk }
        // Two across the divided road each way, one across the two-way
        // road each way; before, eight (four at each point).
        XCTAssertEqual(crosswalks.count, 6)
        XCTAssertEqual(markings.marks.filter { $0.kind == .stopLine }.count, 4)
        XCTAssertEqual(markings.signals.count, 4)
        XCTAssertEqual(Set(markings.signals.map(\.group)).count, 1)
        for mark in markings.marks where mark.kind == .crosswalk || mark.kind == .stopLine {
            XCTAssertFalse(abs(mark.centre.x) < 16 && abs(mark.centre.z) < 4, "\(mark.kind) at \(mark.centre)")
        }
    }

    /// Two-way crossroads 40 m apart stay two junctions, and a divided
    /// road's crossroads 200 m apart are not joined.
    func testJunctionsFurtherApartStayApart() {
        let grid = [road(.primary, [(-200, 0), (0, 0), (40, 0), (200, 0)]),
                    road(.secondary, [(0, -200), (0, 0), (0, 200)]),
                    road(.secondary, [(40, -200), (40, 0), (40, 200)])]
        let markings = Map3DRoadMarkings(grid)
        XCTAssertEqual(markings.marks.filter { $0.kind == .crosswalk }.count, 8)
        XCTAssertEqual(Set(markings.signals.map(\.group)).count, Set([Point(x: 0, z: 0), Point(x: 40, z: 0)].map { Map3DSignalTiming.group(at: $0) }).count)
        let divided = [road(.primary, [(-12, -400), (-12, 0), (-12, 200), (-12, 400)], oneway: true),
                       road(.primary, [(12, 400), (12, 200), (12, 0), (12, -400)], oneway: true),
                       road(.secondary, [(-200, 0), (-12, 0), (12, 0), (200, 0)]), road(.secondary, [(-200, 200), (-12, 200), (12, 200), (200, 200)])]
        let two = Map3DRoadMarkings(divided)
        XCTAssertEqual(two.junctions.count, 4)
        XCTAssertEqual(two.marks.filter { $0.kind == .crosswalk }.count, 12, "six at each crossroads")
    }

    // MARK: - Real crossroads

    /// The roads within `reach` metres of a place on the Taiwan map, in
    /// metres from it.
    static func taiwanRoads(latitude: Double, longitude: Double, reach: Double = 400) throws -> [Map3DBaseMap.Road] {
        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped))
        let frame = RealWorldFrame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)), bounds: .standard)
        return roads(tiles, frame: frame, latitude: latitude, longitude: longitude, reach: reach)
    }

    static func fukuokaRoads(latitude: Double, longitude: Double, reach: Double = 400) throws -> [Map3DBaseMap.Road] {
        let ground = try OverseasGround(city: .fukuoka, pack: XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)))
        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped),
                                     cities: [XCTUnwrap(ground.baseMap, "the pack's base map")])
        let frame = try XCTUnwrap(RealWorldFrame(world: GameWorld.newOverseasGame(ground)))
        return roads(tiles, frame: frame, latitude: latitude, longitude: longitude, reach: reach)
    }

    private static func roads(_ tiles: BaseMapTiles, frame: RealWorldFrame, latitude: Double, longitude: Double, reach: Double) -> [Map3DBaseMap.Road] {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: latitude, longitude: longitude)
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        return Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: place.x, originY: place.y).roads
    }

    private struct Count: Equatable, CustomStringConvertible {
        let points: Int, crosswalks: Int, stops: Int, signals: Int, groups: Int
        var description: String { "\(points) points, \(crosswalks) crossings, \(stops) stop lines, \(signals) signals in \(groups) groups" }
    }

    /// What is marked within `within` metres of `at`.
    private func count(_ roads: [Map3DBaseMap.Road], at: Point = Point(x: 0, z: 0), within: Double = 45, region: Map3DStreetRegion = .taiwan,
                       joining: Bool = true) -> Count {
        let markings = Map3DRoadMarkings(roads, region: region, joining: joining)
        func near(_ p: Point) -> Bool { Map3DRoadMarkings.distance(p, at) < within }
        let signals = markings.signals.filter { near($0.foot) }
        return Count(points: markings.junctions.filter(near).count,
                     crosswalks: markings.marks.filter { $0.kind == .crosswalk && near($0.centre) }.count,
                     stops: markings.marks.filter { $0.kind == .stopLine && near($0.centre) }.count,
                     signals: signals.count, groups: Set(signals.map(\.group)).count)
    }

    /// 忠孝東路 × 敦化南路 (Taipei), both divided: four points.
    func testZhongxiaoDunhuaIsOneJunction() throws {
        let roads = try Self.taiwanRoads(latitude: 25.04145, longitude: 121.54907)
        let before = count(roads, joining: false), after = count(roads)
        print("ZEBRA-LOOK 忠孝敦化 before", before, "after", after)
        XCTAssertEqual(before, Count(points: 4, crosswalks: 18, stops: 11, signals: 11, groups: 2), "main 53b6da1")
        XCTAssertEqual(after.points, 4)
        XCTAssertLessThanOrEqual(after.crosswalks, 8)
        XCTAssertLessThanOrEqual(after.stops, 4)
        XCTAssertLessThanOrEqual(after.signals, 4)
        XCTAssertEqual(after.groups, 1)
    }

    /// A divided crossroads in 天神 (Fukuoka), 190 m north of 渡辺通 ×
    /// 明治通り's point: four points.
    func testTenjinIsOneJunction() throws {
        let roads = try Self.fukuokaRoads(latitude: 33.59060, longitude: 130.39890)
        let at = Point(x: -46, z: -190)
        let before = count(roads, at: at, within: 30, region: .japan, joining: false), after = count(roads, at: at, within: 30, region: .japan)
        print("ZEBRA-LOOK 天神 before", before, "after", after)
        XCTAssertEqual(before.points, 4)
        XCTAssertGreaterThan(before.crosswalks, after.crosswalks)
        XCTAssertLessThanOrEqual(after.crosswalks, 8)
        XCTAssertLessThanOrEqual(after.signals, 4)
        XCTAssertEqual(after.groups, 1)
    }
}
