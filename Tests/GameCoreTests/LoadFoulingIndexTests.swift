@testable import GameCore
import XCTest

/// ``RailwayNetwork/workOutFouling()``, which a loaded save makes
/// (`NEXT_PRIORITIES_2026-10-12.md` §2 item 3, a speed-up only): it tries
/// only the pairs of edges ``PlanBox/pairsInReach(_:margin:)`` finds, each
/// edge's checkpoints and pieces worked out once
/// (``TrackSpacing/Prepared``), and answers exactly as the pair-by-pair way
/// it replaced, kept here as the reference. The fouling kept up change by
/// change as the networks are built (``RailwayNetwork/foulingSpans``, still
/// worked out pair by pair) is compared too.
///
/// On random networks (tracks close side by side, crossing, at several
/// heights, sharing nodes, with platforms cutting edges into spans), on
/// long curving double track like the high-speed demo's, and on networks
/// made by hand where an edge is one unit from the spacing or the fouling
/// length either way.
final class LoadFoulingIndexTests: XCTestCase {
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

    // MARK: - The reference: every pair

    /// The fouling as it was worked out: every pair of edges, each with
    /// ``TrackSpacing/besidePoints(_:_:within:distance:)`` on its own.
    private static func everyPairFouling(of network: RailwayNetwork) -> [TrackSpan: Set<TrackSpan>] {
        var fouling: [TrackSpan: Set<TrackSpan>] = [:]
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        let edges = network.edges
        for i in edges.indices {
            for j in edges.indices where j > i {
                guard let a = network.clearanceShape(of: edges[i].id), let b = network.clearanceShape(of: edges[j].id) else { continue }
                let pairs = TrackSpacing.besidePoints(a, b, within: RailwayNetwork.foulingLength) { x, y in
                    if reach[x] == nil { reach[x] = network.trackDistances(from: x, within: RailwayNetwork.foulingLength) }
                    return reach[x]?[y]
                }
                let spansA = network.spans(of: edges[i].id, length: edges[i].length)
                let spansB = network.spans(of: edges[j].id, length: edges[j].length)
                for (s, t) in pairs {
                    for x in spansA where x.start <= s && s <= x.end {
                        for y in spansB where y.start <= t && t <= y.end {
                            fouling[x, default: []].insert(y)
                            fouling[y, default: []].insert(x)
                        }
                    }
                }
            }
        }
        return fouling
    }

    /// The fouling worked out with the index, the reference's, and the one
    /// kept up as the network was built, and how many spans foul.
    @discardableResult
    private func assertSameFouling(_ network: RailwayNetwork, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) -> Int {
        let indexed = network.workOutFouling()
        let reference = Self.everyPairFouling(of: network)
        XCTAssertEqual(indexed, reference, message, file: file, line: line)
        XCTAssertEqual(network.foulingSpans, reference, message, file: file, line: line)
        return reference.count
    }

    // MARK: - Building networks

    private func node(_ x: Int64, _ y: Int64, _ z: Int64 = 0, in network: inout RailwayNetwork) -> TrackNodeID {
        network.addNode(at: WorldCoordinate(x: x, y: y, z: z), next: network.nextNodeNumber + 1)
    }

    /// Adds an edge however it lies: these networks are not built by
    /// commands, so they may cross and run close, which is what the tests
    /// need. `nil`, and nothing added, where the shape has no geometry.
    @discardableResult
    private func edge(_ from: TrackNodeID, _ to: TrackNodeID, curve: TrackCurve = .straight, in network: inout RailwayNetwork) -> TrackEdgeID? {
        let a = network.node(from)!.position, b = network.node(to)!.position
        guard let geometry = TrackGeometry(from: a, to: b, curve: curve) else { return nil }
        return network.addEdge(from: from, to: to, curve: curve, profile: .uniform, structure: .surface, geometry: geometry, next: network.nextEdgeNumber + 1)
    }

    /// A straight edge between two new nodes.
    @discardableResult
    private func edge(_ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64, z: Int64 = 0, in network: inout RailwayNetwork) -> TrackEdgeID? {
        let from = node(x0, y0, z, in: &network), to = node(x1, y1, z, in: &network)
        return edge(from, to, in: &network)
    }

    /// A platform from `start` to `end` along `edge`, where it fits.
    private func platform(on edge: TrackEdgeID, _ start: Int64, _ end: Int64, in network: inout RailwayNetwork) {
        guard let length = network.edge(edge)?.length, end < length else { return }
        network.addPlatform(TrackPlatform(station: StationID(rawValue: 1), edge: edge, start: start, end: end))
    }

    // MARK: - Random networks

    func testRandomNetworksFoulAsEveryPair() {
        var random = Generator(state: 53)
        var fouled = 0, clear = 0
        for round in 0..<30 {
            var network = RailwayNetwork()
            var nodes: [TrackNodeID] = []
            // Most rounds in a narrow band, where many run close beside one
            // another; some spread out and few, where most are clear.
            let sparse = round % 5 == 4
            let (width, height): (Int64, Int64) = sparse ? (65_536, 65_536) : round % 2 == 0 ? (6_144, 512) : (6_144, 2_048)
            var built: [TrackEdgeID] = []
            for _ in 0..<(sparse ? 6 : 14 + Int(random.value(below: 14))) {
                let from: TrackNodeID
                if !nodes.isEmpty && random.value(below: 3) == 0 {
                    // From a node already there: edges sharing a node.
                    from = nodes[Int(random.value(below: Int64(nodes.count)))]
                } else {
                    from = node(random.value(below: width), random.value(below: height), [0, 0, 0, 256, 512][Int(random.value(below: 5))], in: &network)
                    nodes.append(from)
                }
                let a = network.node(from)!.position
                let to = node(a.x + 600 + random.value(below: 3_000), a.y + random.value(below: 513) - 256, a.z, in: &network)
                nodes.append(to)
                let b = network.node(to)!.position.plan
                let curve: TrackCurve = random.value(below: 2) == 0 ? .straight : .cubic(
                    PlanPoint(x: a.x + (b.x - a.x) / 3, y: a.y + random.value(below: 769) - 384),
                    PlanPoint(x: a.x + 2 * (b.x - a.x) / 3, y: b.y + random.value(below: 769) - 384)
                )
                if let id = edge(from, to, curve: curve, in: &network) { built.append(id) }
            }
            // Platforms cut some edges into spans.
            for id in built.prefix(4) {
                platform(on: id, 100 + random.value(below: 200), 500 + random.value(below: 400), in: &network)
            }
            let count = assertSameFouling(network, "round \(round)")
            if count > 0 { fouled += 1 } else { clear += 1 }
        }
        XCTAssertGreaterThan(fouled, 15)
        XCTAssertGreaterThan(clear, 2)
    }

    /// Long curving double track 5 m apart, as the high-speed demo lays it,
    /// cut into edges with platforms, and a third track that runs closer
    /// than the spacing in places, at one level and on a viaduct just below
    /// and at the clearance.
    func testLongCurvingDoubleTrackFoulsAsEveryPair() {
        var random = Generator(state: 444)
        var fouled = 0
        for round in 0..<6 {
            var network = RailwayNetwork()
            var line: [(Int64, Int64)] = [(10_000, 10_000)]
            var heading: (Int64, Int64) = (3, 1)
            for _ in 0..<12 {
                heading = (heading.0 + random.value(below: 3) - 1, heading.1 + random.value(below: 3) - 1)
                if heading == (0, 0) { heading = (1, 0) }
                let step = 2_000 + random.value(below: 2_000)
                let length = max(abs(heading.0), abs(heading.1))
                line.append((line.last!.0 + heading.0 * step / length, line.last!.1 + heading.1 * step / length))
            }
            let thirdHeight = [0, TrackStructure.clearance - 1, TrackStructure.clearance][round % 3]
            for (offset, z): (Int64, Int64) in [(0, 0), (320, 0), (320 + 200 + random.value(below: 112), thirdHeight)] {
                var previous: TrackNodeID?
                for (k, point) in line.enumerated() {
                    let node = node(point.0, point.1 + offset, z, in: &network)
                    if let previous {
                        let a = network.node(previous)!.position.plan, b = network.node(node)!.position.plan
                        let bend = random.value(below: 401) - 200
                        let id = edge(previous, node, curve: k % 3 == 0 ? .straight : .cubic(
                            PlanPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3 + bend),
                            PlanPoint(x: a.x + 2 * (b.x - a.x) / 3, y: a.y + 2 * (b.y - a.y) / 3 + bend)
                        ), in: &network)
                        if let id, k % 4 == 1 { platform(on: id, 200, 900, in: &network) }
                    }
                    previous = node
                }
            }
            fouled += assertSameFouling(network, "round \(round)")
        }
        XCTAssertGreaterThan(fouled, 50)
    }

    // MARK: - Made by hand

    /// Edges whose boxes are apart by one unit less than the spacing, end to
    /// end, side by side and across a gap in y, foul; one more unit apart,
    /// they do not.
    func testEdgesTheSpacingApartFoulAcrossTheGap() {
        let w = RailwayNetwork.trackSpacing
        for gap in [w - 1, w] {
            for (a, b) in [
                ((0, 0, 1_000, 0), (1_000 + gap, 0, 2_000, 0)),
                ((0, 0, 0, 1_000), (0, 1_000 + gap, 0, 2_000)),
                ((1_000, 0, 2_000, 0), (1_000, gap, 1_500, gap)),
                ((0, 0, 0, 1_000), (gap, 0, gap, 1_000)),
            ] as [((Int64, Int64, Int64, Int64), (Int64, Int64, Int64, Int64))] {
                var network = RailwayNetwork()
                edge(a.0, a.1, a.2, a.3, in: &network)
                edge(b.0, b.1, b.2, b.3, in: &network)
                let count = assertSameFouling(network, "gap \(gap): \(a) \(b)")
                XCTAssertEqual(count, gap < w ? 2 : 0, "gap \(gap): \(a) \(b)")
            }
        }
    }

    /// Only an edge's end checkpoint comes close: a T one unit closer than
    /// the spacing to the side of another, whose checkpoints pass 24 from
    /// its end. Either way round.
    func testOnlyAnEdgesEndCheckpointFouls() {
        let w = RailwayNetwork.trackSpacing
        for reversed in [false, true] {
            var network = RailwayNetwork()
            if reversed {
                edge(1_000, 0, 0, 0, in: &network)
            } else {
                edge(0, 0, 1_000, 0, in: &network)
            }
            edge(1_000 + w - 1, -1_000, 1_000 + w - 1, 1_000, in: &network)
            XCTAssertGreaterThan(assertSameFouling(network, "reversed \(reversed)"), 0, "reversed \(reversed)")
        }
    }

    /// Two tracks parting at a shared node: beside each other within the
    /// fouling length of it along the track they do not foul; beyond it
    /// they do, and with a platform the span the point lies in fouls.
    func testTracksPartingFoulBeyondTheFoulingLength() {
        var network = RailwayNetwork()
        let start = node(0, 0, in: &network)
        let ahead = node(4_000, 0, in: &network)
        let beside = node(4_000, 200, in: &network)
        let straight = edge(start, ahead, in: &network)!
        edge(start, beside, in: &network)
        platform(on: straight, 2_000, 3_000, in: &network)
        XCTAssertGreaterThan(assertSameFouling(network), 0)
    }
}
