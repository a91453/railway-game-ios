@testable import GameCore
import XCTest

/// Two shortcuts in building track (decision 170's follow-up of 2026-10-12,
/// speed-ups only), each shown to answer exactly as the long way:
///
/// - `RailwayNetwork.firstConflict` passes over an existing edge whose box
///   does not meet the new edge's before working out its geometry: it
///   answers as asking ``TrackClearance/isClear(_:_:)`` of every edge does,
///   on dense random networks where boxes meet and the edges cross, meet
///   and are clear, or do not meet; and where two boxes only touch, which
///   counts as meeting for both (`<=`, edges included).
/// - The fouling worked out again after a change visits only the pairs of
///   edges with a changed edge in them, not every pair: after every change
///   it is the fouling worked out from scratch.
final class TrackCheckShortcutTests: XCTestCase {
    /// SplitMix64: the same networks on every run.
    private struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func value(below bound: Int64) -> Int64 {
            Int64(next() % UInt64(bound))
        }
    }

    /// The answer without the box test: the first edge, in order, that
    /// `isClear` finds the new edge meets without clearance.
    private func everyEdgeSampled(
        in network: RailwayNetwork, from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, geometry: TrackGeometry
    ) -> TrackEdgeID? {
        let shape = ClearanceShape(from: from, to: to, curve: curve, geometry: geometry)
        return network.edges.first { edge in
            guard let other = network.clearanceShape(of: edge.id) else { return false }
            return !TrackClearance.isClear(shape, other)
        }?.id
    }

    private func node(_ x: Int64, _ y: Int64, _ z: Int64 = 0, in network: inout RailwayNetwork) -> TrackNodeID {
        network.addNode(at: WorldCoordinate(x: x, y: y, z: z), next: network.nextNodeNumber + 1)
    }

    /// Adds an edge however it lies: these networks are not built by
    /// commands, so they may cross, which is what the tests need.
    /// `nil`, and nothing added, where the shape has no geometry (too steep).
    @discardableResult
    private func edge(_ from: TrackNodeID, _ to: TrackNodeID, curve: TrackCurve = .straight, in network: inout RailwayNetwork) throws -> TrackEdgeID? {
        let a = try XCTUnwrap(network.node(from)).position, b = try XCTUnwrap(network.node(to)).position
        guard let geometry = TrackGeometry(from: a, to: b, curve: curve) else { return nil }
        return network.addEdge(from: from, to: to, curve: curve, profile: .uniform, structure: .surface, geometry: geometry, next: network.nextEdgeNumber + 1)
    }

    /// Whether the box of the new edge and the network's first edge whose
    /// box it meets, and the answers with and without the box test.
    private func compare(
        _ network: RailwayNetwork, from: TrackNodeID, to: TrackNodeID, curve: TrackCurve
    ) throws -> (boxed: TrackEdgeID?, sampled: TrackEdgeID?, boxesMeet: Int)? {
        let a = try XCTUnwrap(network.node(from)).position, b = try XCTUnwrap(network.node(to)).position
        guard let geometry = TrackGeometry(from: a, to: b, curve: curve) else { return nil }
        let box = PlanBox(ClearanceShape(from: from, to: to, curve: curve, geometry: geometry))
        let meeting = network.edges.count { network.planBox(of: $0)?.meets(box) == true }
        return (
            network.firstConflict(from: from, to: to, curve: curve, geometry: geometry),
            everyEdgeSampled(in: network, from: from, to: to, curve: curve, geometry: geometry),
            meeting
        )
    }

    func testRandomDenseNetworksAnswerAsWhenEveryEdgeIsSampled() throws {
        var random = Generator(state: 170)
        var conflicts = 0, clearWithBoxesMeeting = 0, noBoxMeets = 0
        for _ in 0..<40 {
            var network = RailwayNetwork()
            func point() -> (Int64, Int64, Int64) {
                (random.value(below: 8_192), random.value(below: 8_192), [0, 0, 256, 640][Int(random.value(below: 4))])
            }
            func curve(between a: (Int64, Int64, Int64), _ b: (Int64, Int64, Int64)) -> TrackCurve {
                guard random.value(below: 2) == 0 else { return .straight }
                return .cubic(
                    PlanPoint(x: a.0 + random.value(below: 2_049) - 1_024, y: a.1 + random.value(below: 2_049) - 1_024),
                    PlanPoint(x: b.0 + random.value(below: 2_049) - 1_024, y: b.1 + random.value(below: 2_049) - 1_024)
                )
            }
            for _ in 0..<12 {
                let (a, b) = (point(), point())
                let (from, to) = (node(a.0, a.1, a.2, in: &network), node(b.0, b.1, b.2, in: &network))
                try edge(from, to, curve: curve(between: a, b), in: &network)
            }
            for _ in 0..<12 {
                let (a, b) = (point(), point())
                var probe = network
                let (from, to) = (node(a.0, a.1, a.2, in: &probe), node(b.0, b.1, b.2, in: &probe))
                let shape = curve(between: a, b)
                guard let result = try compare(probe, from: from, to: to, curve: shape) else { continue }
                XCTAssertEqual(result.boxed, result.sampled)
                if result.sampled != nil {
                    conflicts += 1
                } else if result.boxesMeet > 0 {
                    clearWithBoxesMeeting += 1
                } else {
                    noBoxMeets += 1
                }
            }
        }
        // Every case came up, many times over.
        XCTAssertGreaterThan(conflicts, 20)
        XCTAssertGreaterThan(clearWithBoxesMeeting, 20)
        XCTAssertGreaterThan(noBoxMeets, 5)
    }

    /// Boxes that only touch, along an edge or at a corner, meet for the box
    /// test as for `isClear`'s own first test: the track there is still
    /// sampled, and a meeting on the touching line is found.
    func testBoxesThatOnlyTouchAreStillSampled() throws {
        var network = RailwayNetwork()
        // A wall at x = 1000, from y = 0 to 1000.
        let (top, bottom) = (node(1_000, 0, in: &network), node(1_000, 1_000, in: &network))
        XCTAssertNotNil(try edge(top, bottom, in: &network))

        // Its box touches along x = 1000, and the new edge ends on the
        // wall: they meet there.
        func probe(_ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64) throws -> (boxed: TrackEdgeID?, sampled: TrackEdgeID?, boxesMeet: Int) {
            var probe = network
            let (from, to) = (node(x0, y0, in: &probe), node(x1, y1, in: &probe))
            return try XCTUnwrap(compare(probe, from: from, to: to, curve: .straight))
        }
        var result = try probe(0, 500, 1_000, 500)
        XCTAssertEqual(result.boxesMeet, 1)
        XCTAssertEqual(result.boxed, .edge(1))
        XCTAssertEqual(result.sampled, .edge(1))

        // Touching at a corner only, at the wall's end.
        result = try probe(0, 2_000, 1_000, 1_000)
        XCTAssertEqual(result.boxesMeet, 1)
        XCTAssertEqual(result.boxed, .edge(1))
        XCTAssertEqual(result.sampled, .edge(1))

        // Boxes touching at x = 1000 but apart in y: clear, with or without.
        result = try probe(0, 1_500, 1_000, 1_500)
        XCTAssertEqual(result.boxesMeet, 0)
        XCTAssertNil(result.boxed)
        XCTAssertNil(result.sampled)

        // One unit short of touching: the boxes do not meet, nor the edges.
        result = try probe(0, 500, 999, 500)
        XCTAssertEqual(result.boxesMeet, 0)
        XCTAssertNil(result.boxed)
        XCTAssertNil(result.sampled)
    }

    /// Random networks of short edges laid close beside one another (so
    /// that many foul), built, given platforms and taken apart one change
    /// at a time: after every change the fouling kept up change by change
    /// is the fouling of the whole network worked out again.
    func testFoulingKeptUpChangeByChangeIsTheWholeNetworksFouling() throws {
        var random = Generator(state: 53)
        var fouled = 0
        for _ in 0..<12 {
            var network = RailwayNetwork()
            var built: [TrackEdgeID] = []
            for _ in 0..<16 {
                // Within a 6 m wide band, so neighbours are under 4 m apart.
                let x = random.value(below: 4_096), y = random.value(below: 384)
                let (from, to) = (node(x, y, in: &network), node(x + 1_024 + random.value(below: 2_048), y + random.value(below: 384) - 192, in: &network))
                if let edge = try edge(from, to, in: &network) { built.append(edge) }
                XCTAssertEqual(network.foulingSpans, network.workOutFouling())
            }
            for edge in built.prefix(4) {
                guard let length = network.edge(edge)?.length, length > 600 else { continue }
                network.addPlatform(TrackPlatform(station: StationID(rawValue: 1), edge: edge, start: 100, end: 500))
                XCTAssertEqual(network.foulingSpans, network.workOutFouling())
            }
            fouled += network.foulingSpans.count
            for edge in built.suffix(5) {
                network.removeEdge(edge)
                XCTAssertEqual(network.foulingSpans, network.workOutFouling())
            }
        }
        XCTAssertGreaterThan(fouled, 100, "spans fouled each other")
    }
}
