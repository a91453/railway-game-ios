import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 597: ``GameWorld/singleTrackLength(of:from:to:)`` works out
/// the edges every way between two stations' platforms runs over as their
/// dominators, once a leg, instead of searching the network again without
/// each edge of the leg (decision 264's way, kept here as the reference).
/// The two agree on every leg of the demos' lines.
final class SingleTrackLengthTests: XCTestCase {
    func testTheDominatorsAgreeWithASearchWithoutEachEdge() throws {
        for (name, world) in [
            ("high-speed demo", try HighSpeedDemoTests.opened.get()),
            ("Yilan Line demo", try TRADemoTests.opened.get()),
        ] {
            var legs = 0, single = 0
            for line in world.lines {
                guard let journey = world.lineJourney(line.id) else { continue }
                for (leg, edges) in GameWorld.legEdges(of: journey) where leg.to > leg.from && leg.to < line.stops.count {
                    let (a, b) = (line.stops[leg.from], line.stops[leg.to])
                    let expected = Self.searched(world, of: edges, from: a, to: b)
                    XCTAssertEqual(world.singleTrackLength(of: edges, from: a, to: b), expected, "\(name) \(line.name) leg \(leg.from)–\(leg.to)")
                    legs += 1
                    if expected > 0 { single += 1 }
                }
            }
            // Both answers come up: some legs have track every way runs
            // over (a turnout at least), some do not.
            XCTAssertGreaterThan(legs, 2, name)
            XCTAssertGreaterThan(single, 0, name)
        }
    }

    /// A station with no way to the other: every edge counts, as before.
    func testNoWayCountsEveryEdge() throws {
        var world = GameWorld.newGame(rules: .simple)
        let y = world.bounds.height / 2, x = world.bounds.width / 2
        let unit = 1_000 * WorldCoordinate.unitsPerMetre
        let nodes = try (0..<4).map { try world.buildTrackNode(at: WorldCoordinate(x: x + Int64($0) * unit, y: y)) }
        let west = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        let east = try world.buildTrackEdge(from: nodes[2], to: nodes[3])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x, y: y)).id
        try world.addTrackPlatform(a, on: west, from: 0, to: unit / 4)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: x + 3 * unit, y: y)).id
        try world.addTrackPlatform(b, on: east, from: 0, to: unit / 4)
        let both = try XCTUnwrap(world.trackEdge(west)?.length) + XCTUnwrap(world.trackEdge(east)?.length)
        XCTAssertEqual(world.singleTrackLength(of: [west, east], from: a, to: b), both)
        XCTAssertEqual(Self.searched(world, of: [west, east], from: a, to: b), both)
    }

    /// Decision 264's way: for each edge, whether a platform of `b` is
    /// still reached from one of `a` without it.
    static func searched(_ world: GameWorld, of edges: [TrackEdgeID], from a: StationID, to b: StationID) -> Int64 {
        let network = world.network
        let starts = Set(network.platforms.filter { $0.station == a }.map(\.edge))
        let goals = Set(network.platforms.filter { $0.station == b }.map(\.edge))
        func joined(without cut: TrackEdgeID) -> Bool {
            var seen = starts.subtracting([cut])
            var queue = Array(seen)
            while let edge = queue.popLast() {
                if edge != cut, goals.contains(edge) { return true }
                guard let track = network.edge(edge) else { continue }
                for node in [track.from, track.to] {
                    for next in network.node(node)?.end(of: edge)?.exits ?? [] where next != cut && seen.insert(next).inserted {
                        queue.append(next)
                    }
                }
            }
            return false
        }
        return Set(edges).reduce(0) { length, edge in
            guard let track = network.edge(edge), !joined(without: edge) else { return length }
            return length + track.length
        }
    }
}
