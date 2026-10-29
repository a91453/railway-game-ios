@testable import GamePresentation
import XCTest

/// Decision 476's sequel: the player's own roads in the bus roads' graph.
/// Two streets 200 m apart that no road joins; a road of the player's
/// between them joins them where it crosses them, and where it ends within a
/// cell of them, and not farther.
final class BusOwnRoadsTests: XCTestCase {
    private typealias Point = BusRoadNetwork.Point
    private typealias Road = BusRoadNetwork.Road

    private let streets = [
        Road(points: [Point(x: 0, y: 0), Point(x: 400, y: 0)]),
        Road(points: [Point(x: 0, y: 200), Point(x: 400, y: 200)]),
    ]

    private func network(own: [Point]) -> BusRoadNetwork {
        BusRoadNetwork(roads: streets + BusRoadNetwork.joining(own: [own], ends: [own[0], own[own.count - 1]], to: streets))
    }

    private func way(_ network: BusRoadNetwork) -> [Point]? {
        guard let north = network.nearest(to: Point(x: 50, y: 0), within: BusRoadNetwork.snapReach),
              let south = network.nearest(to: Point(x: 50, y: 200), within: BusRoadNetwork.snapReach) else { return nil }
        return network.way(from: north, to: south)
    }

    private func length(_ points: [Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    func testWithoutTheirRoadTheStreetsDoNotJoin() {
        XCTAssertNil(way(BusRoadNetwork(roads: streets)))
    }

    func testARoadAcrossBothStreetsMakesJunctionsTheBusTurnsAt() throws {
        let network = network(own: [Point(x: 200, y: -30), Point(x: 200, y: 230)])
        let way = try XCTUnwrap(way(network))
        // East 150 m, south 200 m along their road, west 150 m.
        XCTAssertEqual(length(way), 500, accuracy: 2)
        XCTAssertTrue(way.contains { $0.distance(to: Point(x: 200, y: 0)) < 1 })
        XCTAssertTrue(way.contains { $0.distance(to: Point(x: 200, y: 200)) < 1 })
    }

    func testARoadEndingWithinACellOfAStreetIsJoinedToIt() throws {
        let network = network(own: [Point(x: 200, y: 40), Point(x: 200, y: 160)])
        let way = try XCTUnwrap(way(network))
        // East 150, 40 m to their road, 120 along it, 40 to the street, west 150.
        XCTAssertEqual(length(way), 500, accuracy: 2)
    }

    func testARoadEndingFartherThanACellIsNotJoined() {
        XCTAssertNil(way(network(own: [Point(x: 200, y: 100), Point(x: 200, y: 160)])))
    }

    func testAnEndOnAStreetAlreadyNeedsNoPiece() {
        let own = [Point(x: 200, y: 0), Point(x: 200, y: 200)]
        let roads = BusRoadNetwork.joining(own: [own], ends: own, to: streets)
        XCTAssertEqual(roads.count, 1, "the road itself, and no piece to the streets")
    }

    func testATunnelIsNotCrossed() {
        let tunnel = [Road(points: [Point(x: 0, y: 0), Point(x: 400, y: 0)], tunnel: true)]
        let roads = BusRoadNetwork.joining(own: [[Point(x: 200, y: -30), Point(x: 200, y: 30)]], ends: [], to: tunnel)
        XCTAssertEqual(roads.map(\.points.count), [2], "no junction with a road under the ground")
    }

    func testCrossingIsInsideBothPiecesOnly() {
        XCTAssertEqual(BusRoadNetwork.crossing(Point(x: 0, y: -1), Point(x: 0, y: 1), Point(x: -1, y: 0), Point(x: 1, y: 0)) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertNil(BusRoadNetwork.crossing(Point(x: 0, y: 0), Point(x: 0, y: 1), Point(x: -1, y: 0), Point(x: 1, y: 0)), "meeting at an end")
        XCTAssertNil(BusRoadNetwork.crossing(Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)), "parallel")
    }
}
