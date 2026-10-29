import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 424: the player's bus routes follow the base map's roads. A
/// network made of a few streets laid in vector tiles by hand: a bus takes
/// `primary` to `minor` roads (not service roads or freeways), a
/// stop is put on the nearest road within 25 m, the way between two stops
/// runs along the streets, a road cut at a tile's edge still joins, and two
/// streets no road joins give no way, not a straight line. Decision 474: a
/// one-way road is taken its way only, and a tunnel is taken but holds no
/// stop.
final class BusRoadNetworkTests: XCTestCase {
    private typealias Point = BusRoadNetwork.Point

    private let frame = RealWorldFrame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!, bounds: .standard)
    private var projection: RealRoadCells.Projection { RealRoadCells.Projection(frame: frame) }

    /// A tile in the middle of the map.
    private var tile: (column: Int, row: Int) { (projection.column(8_192), projection.row(8_192)) }

    /// A line of `kind` through `points` (metres of the world) as tile
    /// `column`, `row` holds it.
    private func feature(
        _ kind: String, _ points: [(x: Double, y: Double)], column: Int, row: Int, brunnel: String? = nil, oneway: Double? = nil
    ) -> VectorTile.Feature {
        let (west, north, scale) = projection.place(column: column, row: row, extent: 4096)
        var properties: [String: VectorTile.Value] = ["class": .string(kind)]
        if let brunnel { properties["brunnel"] = .string(brunnel) }
        if let oneway { properties["oneway"] = .number(oneway) }
        let part = points.map { VectorTile.Point(x: Int32((($0.x - west) / scale).rounded()), y: Int32((($0.y - north) / scale).rounded())) }
        return VectorTile.Feature(kind: .line, properties: properties, parts: [part])
    }

    private func layer(_ features: [VectorTile.Feature]) -> VectorTile.Layer {
        VectorTile.Layer(name: "transportation", extent: 4096, features: features)
    }

    private func roads(_ layer: VectorTile.Layer, column: Int, row: Int) -> [BusRoadNetwork.Road] {
        BusRoadNetwork.roads(in: layer, column: column, row: row, projection: projection)
    }

    /// Two parallel streets 200 m apart, 400 m long, and a cross street at
    /// their east ends, in the middle of a tile; `x0`, `y0` is the west end
    /// of the north street.
    private func streets(extra: [VectorTile.Feature] = [], cross: String = "minor") -> (network: BusRoadNetwork, x0: Double, y0: Double) {
        let (column, row) = tile
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        let network = BusRoadNetwork(roads: roads(layer([
            feature("secondary", [(x0, y0), (x0 + 400, y0)], column: column, row: row),
            feature("tertiary", [(x0, y0 + 200), (x0 + 400, y0 + 200)], column: column, row: row),
            feature(cross, [(x0 + 400, y0), (x0 + 400, y0 + 200)], column: column, row: row),
        ] + extra), column: column, row: row))
        return (network, x0, y0)
    }

    private func place(_ network: BusRoadNetwork, _ x: Double, _ y: Double, within reach: Double = BusRoadNetwork.snapReach) -> BusRoadNetwork.Place? {
        network.nearest(to: Point(x: x, y: y), within: reach)
    }

    /// The length of `points` in metres.
    private func length(_ points: [Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// How far `point` is from the nearest of `lines`' pieces, in metres.
    private func away(_ point: Point, from lines: [[(x: Double, y: Double)]]) -> Double {
        var least = Double.infinity
        for line in lines {
            for (a, b) in zip(line, line.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy), 0), 1)
                least = min(least, hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t)))
            }
        }
        return least
    }

    // MARK: - Ways

    func testATurningRouteRunsAlongTheStreetsAndNeverAcrossTheBlock() throws {
        let (network, x0, y0) = streets()
        let north = try XCTUnwrap(place(network, x0 + 50, y0 + 5))
        let south = try XCTUnwrap(place(network, x0 + 60, y0 + 195))
        let way = try XCTUnwrap(network.way(from: north, to: south))
        // East along the north street, south along the cross street, west
        // along the south street: 350 + 200 + 340 m.
        XCTAssertEqual(length(way), 890, accuracy: 4)
        let streets: [[(x: Double, y: Double)]] = [
            [(x0, y0), (x0 + 400, y0)], [(x0, y0 + 200), (x0 + 400, y0 + 200)], [(x0 + 400, y0), (x0 + 400, y0 + 200)],
        ]
        for point in way { XCTAssertLessThan(away(point, from: streets), 1.5, "\(point) is not on a street") }
        // Every stretch between two points lies on one street too: the
        // middle of it is no farther from the streets.
        for (a, b) in zip(way, way.dropFirst()) {
            XCTAssertLessThan(away(Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), from: streets), 1.5)
        }
        XCTAssertEqual(way.first?.distance(to: north.point), 0)
        XCTAssertEqual(way.last?.distance(to: south.point), 0)
    }

    func testTheSameRoadsGiveTheSameWay() throws {
        let (first, x0, y0) = streets()
        let (second, _, _) = streets()
        func run(_ network: BusRoadNetwork) throws -> [Point] {
            try XCTUnwrap(network.way(from: try XCTUnwrap(place(network, x0 + 10, y0)), to: try XCTUnwrap(place(network, x0 + 10, y0 + 200))))
        }
        XCTAssertEqual(try run(first), try run(second))
        XCTAssertEqual(first.nodes, second.nodes)
    }

    func testTheWayBetweenTwoPointsOfOneStreetIsTheStreet() throws {
        let (network, x0, y0) = streets()
        let a = try XCTUnwrap(place(network, x0 + 20, y0)), b = try XCTUnwrap(place(network, x0 + 120, y0))
        let way = try XCTUnwrap(network.way(from: a, to: b))
        XCTAssertEqual(length(way), 100, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(network.way(from: a, to: a)).count, 1)
    }

    // MARK: - Stops on roads

    func testAStopIsPutOnTheRoadWithin25MetresAndRefusedBeyond() throws {
        let (network, x0, y0) = streets()
        // Mid-block, 100 m from both streets: refused.
        XCTAssertNil(place(network, x0 + 200, y0 + 100))
        XCTAssertNil(place(network, x0 + 200, y0 + 40), "40 m from the street")
        XCTAssertNil(place(network, x0 + 200, y0 + 26))
        // 24 m off the north street: on it, straight below the tap.
        let near = try XCTUnwrap(place(network, x0 + 200, y0 + 24))
        XCTAssertEqual(near.point.x, x0 + 200, accuracy: 1.5)
        XCTAssertEqual(near.point.y, y0, accuracy: 1.5)
        XCTAssertEqual(near.distance, 24, accuracy: 1.5)
        // A station is put on a road from farther.
        XCTAssertNotNil(place(network, x0 + 200, y0 + 100, within: BusRoadNetwork.stationReach))
    }

    func testAPointIsOnlyPutWhereGameCoreKnowsARoad() throws {
        let (network, x0, y0) = streets()
        // Only the west half of the north street counts as a road.
        let found = try XCTUnwrap(network.nearest(to: Point(x: x0 + 160, y: y0 + 3), within: 25, accepting: { $0.x <= x0 + 150 }))
        XCTAssertLessThanOrEqual(found.point.x, x0 + 150 + 0.001)
        XCTAssertEqual(found.point.y, y0, accuracy: 1.5)
        XCTAssertNil(network.nearest(to: Point(x: x0 + 300, y: y0 + 3), within: 25, accepting: { $0.x <= x0 + 150 }), "150 m off")
        XCTAssertNil(network.nearest(to: Point(x: x0 + 160, y: y0 + 3), within: 25, accepting: { _ in false }))
    }

    // MARK: - Tiles

    func testARoadCutAtATilesEdgeStillJoins() throws {
        let (column, row) = tile
        let (_, north, _) = projection.place(column: column, row: row, extent: 4096)
        let (east, _, _) = projection.place(column: column + 1, row: row, extent: 4096)
        let y = north + 800
        // The road runs 300 m either side of the edge; each tile also holds
        // some of the other's side (its buffer).
        let left = layer([feature("minor", [(east - 300, y), (east + 60, y)], column: column, row: row)])
        let right = layer([feature("minor", [(east - 60, y), (east + 300, y)], column: column + 1, row: row)])
        let network = BusRoadNetwork(roads: roads(left, column: column, row: row) + roads(right, column: column + 1, row: row))
        let a = try XCTUnwrap(place(network, east - 250, y)), b = try XCTUnwrap(place(network, east + 250, y))
        let way = try XCTUnwrap(network.way(from: a, to: b), "the two tiles' pieces do not join")
        XCTAssertEqual(length(way), 500, accuracy: 3)
    }

    func testASideStreetJoinsTheMiddleOfARoadThatHasNoPointThere() throws {
        // The tiles drop a straight road's points where a side street meets
        // it: the side street's end lies on the inside of the road's piece.
        let roads = BusRoadNetwork(roads: [
            .init(points: [Point(x: 0, y: 0), Point(x: 400, y: 0)]),
            .init(points: [Point(x: 200, y: 150), Point(x: 200, y: 0.5)]),
        ])
        let side = try XCTUnwrap(roads.nearest(to: Point(x: 200, y: 100), within: 5))
        let west = try XCTUnwrap(roads.nearest(to: Point(x: 20, y: 0), within: 5))
        let way = try XCTUnwrap(roads.way(from: side, to: west))
        XCTAssertEqual(length(way), 100 + 180, accuracy: 2)
        // A side street ending farther than a metre from the road does not join it.
        let apart = BusRoadNetwork(roads: [
            .init(points: [Point(x: 0, y: 0), Point(x: 400, y: 0)]),
            .init(points: [Point(x: 200, y: 150), Point(x: 200, y: 1.5)]),
        ])
        XCTAssertNil(apart.way(from: try XCTUnwrap(apart.nearest(to: Point(x: 200, y: 100), within: 5)),
                               to: try XCTUnwrap(apart.nearest(to: Point(x: 20, y: 0), within: 5))))
    }

    func testTwoEndsWithinAMetreJoinAndFartherApartDoNot() throws {
        func network(gap: Double) -> BusRoadNetwork {
            BusRoadNetwork(roads: [
                .init(points: [Point(x: 0, y: 0), Point(x: 100, y: 0)]),
                .init(points: [Point(x: 100 + gap, y: 0), Point(x: 200 + gap, y: 0)]),
            ])
        }
        for (gap, joined) in [(0.6, true), (1.5, false)] {
            let roads = network(gap: gap)
            let a = try XCTUnwrap(roads.nearest(to: Point(x: 10, y: 0), within: 5)), b = try XCTUnwrap(roads.nearest(to: Point(x: 190, y: 0), within: 5))
            XCTAssertEqual(roads.way(from: a, to: b) != nil, joined, "a gap of \(gap) m")
        }
    }

    // MARK: - What a bus takes

    func testServiceRoadsAndFreewaysAreNotTaken() throws {
        let (column, row) = tile
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        let everything = layer([
            feature("service", [(x0, y0), (x0 + 100, y0)], column: column, row: row),
            feature("motorway", [(x0, y0 + 20), (x0 + 100, y0 + 20)], column: column, row: row),
            feature("trunk", [(x0, y0 + 40), (x0 + 100, y0 + 40)], column: column, row: row),
            feature("rail", [(x0, y0 + 80), (x0 + 100, y0 + 80)], column: column, row: row),
            feature("path", [(x0, y0 + 100), (x0 + 100, y0 + 100)], column: column, row: row),
        ])
        XCTAssertTrue(roads(everything, column: column, row: row).isEmpty)
        // A bridge is a road a bus takes, and decision 474, a tunnel too;
        // each class from primary to minor.
        let taken = layer(["primary", "secondary", "tertiary", "minor"].enumerated().map { index, kind in
            feature(kind, [(x0, y0 + Double(index) * 30), (x0 + 100, y0 + Double(index) * 30)], column: column, row: row,
                    brunnel: kind == "primary" ? "bridge" : kind == "secondary" ? "tunnel" : nil)
        })
        let read = roads(taken, column: column, row: row)
        XCTAssertEqual(read.count, 4)
        XCTAssertEqual(read.map(\.tunnel), [false, true, false, false])
    }

    // MARK: - One-way roads and tunnels (decision 474)

    /// The two streets of ``streets()``, the north one one way: east, or
    /// with `against` drawn west to east but taken west (`oneway` -1).
    private func oneWayStreets(against: Bool = false) -> (network: BusRoadNetwork, x0: Double, y0: Double) {
        let (column, row) = tile
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        let network = BusRoadNetwork(roads: roads(layer([
            feature("secondary", [(x0, y0), (x0 + 400, y0)], column: column, row: row, oneway: against ? -1 : 1),
            feature("tertiary", [(x0, y0 + 200), (x0 + 400, y0 + 200)], column: column, row: row),
            feature("minor", [(x0 + 400, y0), (x0 + 400, y0 + 200)], column: column, row: row),
            feature("minor", [(x0, y0), (x0, y0 + 200)], column: column, row: row),
        ]), column: column, row: row))
        return (network, x0, y0)
    }

    func testAOneWayStreetIsTakenItsWayOnly() throws {
        let (network, x0, y0) = oneWayStreets()
        let west = try XCTUnwrap(place(network, x0 + 100, y0)), east = try XCTUnwrap(place(network, x0 + 300, y0))
        XCTAssertTrue(network.isOneway(west))
        // East, its way: straight along it.
        XCTAssertEqual(length(try XCTUnwrap(network.way(from: west, to: east))), 200, accuracy: 2)
        // West, against it: round the block, 100 + 200 + 400 + 200 + 100 m.
        let back = try XCTUnwrap(network.way(from: east, to: west))
        XCTAssertEqual(length(back), 1_000, accuracy: 4)
        XCTAssertTrue(back.contains { $0.y > y0 + 150 }, "by the south street")
        // Drawn the other way round, taken west: the other way about.
        let (turned, _, _) = oneWayStreets(against: true)
        let a = try XCTUnwrap(place(turned, x0 + 100, y0)), b = try XCTUnwrap(place(turned, x0 + 300, y0))
        XCTAssertEqual(length(try XCTUnwrap(turned.way(from: b, to: a))), 200, accuracy: 2)
        XCTAssertEqual(length(try XCTUnwrap(turned.way(from: a, to: b))), 1_000, accuracy: 4)
    }

    func testOnADividedRoadTheOtherCarriagewayIsFoundFacingTheOtherWay() throws {
        let (column, row) = tile
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        // Two carriageways 12 m apart, the north one east, the south one west.
        let network = BusRoadNetwork(roads: roads(layer([
            feature("primary", [(x0, y0), (x0 + 400, y0)], column: column, row: row, oneway: 1),
            feature("primary", [(x0 + 400, y0 + 12), (x0, y0 + 12)], column: column, row: row, oneway: 1),
        ]), column: column, row: row))
        let nearer = try XCTUnwrap(place(network, x0 + 200, y0 + 4))
        XCTAssertEqual(nearer.point.y, y0, accuracy: 1)
        let other = try XCTUnwrap(network.nearest(to: Point(x: x0 + 200, y: y0 + 4), within: 25, facing: network.direction(of: nearer.segment)))
        XCTAssertEqual(other.point.y, y0 + 12, accuracy: 1)
        let back = try XCTUnwrap(network.nearest(to: Point(x: x0 + 200, y: y0 + 4), within: 25, facing: network.direction(of: other.segment)))
        XCTAssertEqual(back.point.y, y0, accuracy: 1, "facing the south one's way: the north one")
    }

    func testATunnelIsTakenButHoldsNoStop() throws {
        let (column, row) = tile
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = west + 500, y0 = north + 500
        // A road, 300 m of it in a tunnel through a hill, and the long way
        // round the hill.
        let network = BusRoadNetwork(roads: roads(layer([
            feature("secondary", [(x0, y0), (x0 + 100, y0)], column: column, row: row),
            feature("secondary", [(x0 + 100, y0), (x0 + 400, y0)], column: column, row: row, brunnel: "tunnel"),
            feature("secondary", [(x0 + 400, y0), (x0 + 500, y0)], column: column, row: row),
            feature("minor", [(x0 + 100, y0), (x0 + 100, y0 + 300), (x0 + 400, y0 + 300), (x0 + 400, y0)], column: column, row: row),
        ]), column: column, row: row))
        let a = try XCTUnwrap(place(network, x0 + 50, y0)), b = try XCTUnwrap(place(network, x0 + 450, y0))
        let route = try XCTUnwrap(network.route(from: a, to: b))
        XCTAssertEqual(length(route.points), 400, accuracy: 2, "through the tunnel, not round the hill")
        XCTAssertEqual(route.tunnels.count, route.points.count - 1)
        let inside = zip(zip(route.points, route.points.dropFirst()), route.tunnels).filter(\.1).reduce(0.0) { $0 + $1.0.0.distance(to: $1.0.1) }
        XCTAssertEqual(inside, 300, accuracy: 2)
        // A tap over the tunnel puts no stop in it.
        XCTAssertNil(place(network, x0 + 250, y0 + 5))
        // The way drawn keeps which pieces are in the tunnel.
        let way = BusWay(legs: [(route.points.map(\.plan), route.tunnels)], stops: nil)
        XCTAssertEqual(way.tunnels.count, way.points.count - 1)
        XCTAssertTrue(way.tunnels.contains(true))
    }

    func testTwoStreetsOnlyAServiceRoadJoinsGiveNoWayAndNoStraightLine() throws {
        let (network, x0, y0) = streets(cross: "service")
        // The cross street is a service road: it is left out.
        XCTAssertEqual(network.nodes.count, 4)
        let north = try XCTUnwrap(place(network, x0 + 50, y0)), south = try XCTUnwrap(place(network, x0 + 50, y0 + 200))
        XCTAssertNil(network.way(from: north, to: south), "no road joins the streets")
        // A leg no road joins is broken: no line, no metres, and the route
        // does not open with them.
        let way = BusWay(lines: [[Point(x: 0, y: 0).plan, Point(x: 10, y: 0).plan], nil])
        XCTAssertEqual(way.firstBroken, 1)
        XCTAssertNil(way.legMetres)
        XCTAssertEqual(way.legs[1].line, [])
        XCTAssertEqual(way.points, [], "only the legs after the last broken one are drawn, and there are none")
    }

    // MARK: - Metres and corners

    func testALegsMetresAreItsDrawnLinesLengthToTheMetre() throws {
        let (network, x0, y0) = streets()
        let stops = [try XCTUnwrap(place(network, x0 + 50, y0)), try XCTUnwrap(place(network, x0 + 400, y0 + 100)),
                     try XCTUnwrap(place(network, x0 + 100, y0 + 200))]
        var lines: [[PlanPoint]?] = []
        var exact: [Double] = []
        for (from, to) in zip(stops, stops.dropFirst()) {
            let way = try XCTUnwrap(network.way(from: from, to: to))
            lines.append(way.map(\.plan))
            exact.append(length(way))
        }
        let way = BusWay(lines: lines)
        let metres = try XCTUnwrap(way.legMetres)
        XCTAssertEqual(metres.count, 2)
        for (given, drawn) in zip(metres, exact) { XCTAssertLessThan(abs(Double(given) - drawn), 1, "\(given) m given, \(drawn) m drawn") }
    }

    func testCornersAreRoundedAndTheStopsStayOnTheLine() throws {
        let (network, x0, y0) = streets()
        let a = try XCTUnwrap(place(network, x0 + 50, y0)), b = try XCTUnwrap(place(network, x0 + 50, y0 + 200))
        let way = BusWay(lines: [try XCTUnwrap(network.way(from: a, to: b)).map(\.plan)])
        // The two corners are cut: more points than the road has.
        XCTAssertGreaterThan(way.points.count, 4)
        XCTAssertEqual(way.marks.count, 2)
        XCTAssertEqual(way.points[way.marks[0]], a.point.plan)
        XCTAssertEqual(way.points[way.marks[1]], b.point.plan)
        // The curve stays within the corner's cut of the road.
        let streets: [[(x: Double, y: Double)]] = [
            [(x0, y0), (x0 + 400, y0)], [(x0, y0 + 200), (x0 + 400, y0 + 200)], [(x0 + 400, y0), (x0 + 400, y0 + 200)],
        ]
        for point in way.points { XCTAssertLessThan(away(Point(point), from: streets), BusWay.cornerRadius / 2 + 1.5) }
        // A straight road keeps its points.
        let straight = BusWay(lines: [[Point(x: 0, y: 0).plan, Point(x: 50, y: 0).plan, Point(x: 100, y: 0).plan]])
        XCTAssertEqual(straight.points.count, 3)
    }
}
