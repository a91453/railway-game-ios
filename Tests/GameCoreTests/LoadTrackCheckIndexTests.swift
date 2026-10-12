@testable import GameCore
import XCTest

/// The track checks a loaded save makes (`NEXT_PRIORITIES_2026-10-12.md`
/// §2 item 3 (1), speed-ups only), each shown to answer exactly as the
/// pair-by-pair way they replaced, kept here as the reference:
///
/// - ``RailwayNetwork/firstConflictingPair(geometries:)`` tries only the
///   pairs ``PlanBox/pairsInReach(_:margin:)`` finds, and
///   ``TrackClearance/isClear(_:_:)`` only pieces in runs whose boxes meet:
///   the same first pair, or none.
/// - ``RailwayNetwork/tooClosePairs(geometries:)`` tries only the pairs in
///   reach, each with every edge's checkpoints and pieces worked out once:
///   the same pairs, in the same order.
///
/// On dense random networks (crossings at one level and over one another,
/// curves, edges sharing nodes, tracks laid close side by side), on long
/// curving double track like the high-speed demo's, and on networks made by
/// hand where a box is one unit from reach either way.
final class LoadTrackCheckIndexTests: XCTestCase {
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

    // MARK: - The reference: every pair, every piece

    /// ``TrackClearance/isClear(_:_:)`` as it was: every piece within the
    /// other edge's box against every such piece of the other.
    private static func everyPieceIsClear(_ a: ClearanceShape, _ b: ClearanceShape) -> Bool {
        guard a.minimum.x <= b.maximum.x, b.minimum.x <= a.maximum.x, a.minimum.y <= b.maximum.y, b.minimum.y <= a.maximum.y else {
            return true
        }
        if a.lowest - b.highest >= TrackStructure.clearance || b.lowest - a.highest >= TrackStructure.clearance {
            return true
        }
        let shared: Set<TrackNodeID> = Set([a.from, a.to]).intersection([b.from, b.to])
        func stretch(of shape: ClearanceShape) -> (points: [PlanPoint], distances: [Int64])? {
            let length = shape.geometry.length
            let start = shared.contains(shape.from) ? RailwayNetwork.junctionZone : 0
            let end = shared.contains(shape.to) ? length - RailwayNetwork.junctionZone : length
            guard start < end else { return nil }
            let stretch = shape.geometry.stretch(from: start, to: end)
            return (stretch.points.map(\.plan), stretch.distances)
        }
        func pieces(of points: [PlanPoint], within minimum: PlanPoint, _ maximum: PlanPoint) -> [Int] {
            points.indices.dropLast().filter { i in
                let (p, q) = (points[i], points[i + 1])
                return min(p.x, q.x) <= maximum.x && minimum.x <= max(p.x, q.x) && min(p.y, q.y) <= maximum.y && minimum.y <= max(p.y, q.y)
            }
        }
        guard let first = stretch(of: a), let second = stretch(of: b) else { return true }
        for i in pieces(of: first.points, within: b.minimum, b.maximum) {
            let (p, q) = (first.points[i], first.points[i + 1])
            for j in pieces(of: second.points, within: a.minimum, a.maximum) {
                let (r, s) = (second.points[j], second.points[j + 1])
                guard min(p.x, q.x) <= max(r.x, s.x), min(r.x, s.x) <= max(p.x, q.x),
                      min(p.y, q.y) <= max(r.y, s.y), min(r.y, s.y) <= max(p.y, q.y)
                else { continue }
                let meetings = TrackClearance.meetingPoints(
                    p, q, along: (first.distances[i], first.distances[i + 1]),
                    r, s, along: (second.distances[j], second.distances[j + 1])
                )
                guard !meetings.isEmpty else { continue }
                let heightsA = meetings.map { a.geometry.height(at: $0.a) }
                let heightsB = meetings.map { b.geometry.height(at: $0.b) }
                guard heightsA.min()! - heightsB.max()! >= TrackStructure.clearance
                    || heightsB.min()! - heightsA.max()! >= TrackStructure.clearance
                else { return false }
            }
        }
        return true
    }

    private static func shapes(of network: RailwayNetwork) -> [(TrackEdgeID, ClearanceShape)] {
        network.edges.map { ($0.id, network.clearanceShape(of: $0.id)!) }
    }

    /// The first conflicting pair as it was found: every pair in order.
    private static func everyPairFirstConflict(in network: RailwayNetwork) -> (TrackEdgeID, TrackEdgeID)? {
        let shapes = shapes(of: network)
        for i in shapes.indices {
            for j in shapes.indices where j > i {
                if !everyPieceIsClear(shapes[i].1, shapes[j].1) { return (shapes[i].0, shapes[j].0) }
            }
        }
        return nil
    }

    /// The pairs too close as they were found: every pair in order, each
    /// with ``TrackSpacing/isSpaced(_:_:distance:)`` on its own.
    private static func everyPairTooClose(in network: RailwayNetwork) -> [TrackEdgePair] {
        let shapes = shapes(of: network)
        var pairs: [TrackEdgePair] = []
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        for i in shapes.indices {
            for j in shapes.indices where j > i {
                let spaced = TrackSpacing.isSpaced(shapes[i].1, shapes[j].1) { a, b in
                    if reach[a] == nil { reach[a] = network.trackDistances(from: a, within: RailwayNetwork.partingReach) }
                    return reach[a]?[b]
                }
                if !spaced { pairs.append(TrackEdgePair(shapes[i].0, shapes[j].0)) }
            }
        }
        return pairs
    }

    private struct Answers: Equatable {
        let first: [TrackEdgeID]?
        let tooClose: [TrackEdgePair]
    }

    /// The answers of the checks a load makes, and of the reference.
    private static func answers(_ network: RailwayNetwork) -> (indexed: Answers, reference: Answers) {
        let geometries = network.edges.map { network.geometry(of: $0.id)! }
        let indexed = Answers(first: network.firstConflictingPair(geometries: geometries).map { [$0.0, $0.1] }, tooClose: network.tooClosePairs(geometries: geometries))
        let reference = Answers(first: everyPairFirstConflict(in: network).map { [$0.0, $0.1] }, tooClose: everyPairTooClose(in: network))
        return (indexed, reference)
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

    // MARK: - Random networks

    func testRandomDenseNetworksAnswerAsEveryPair() throws {
        var random = Generator(state: 191)
        var conflicts = 0, clear = 0, tooClose = 0, conflictNotFirstInSweep = 0
        for round in 0..<36 {
            var network = RailwayNetwork()
            var nodes: [TrackNodeID] = []
            // Some rounds in a narrow band, where many run close beside one
            // another; some spread out, where many cross; and some few and
            // far apart, where most networks are clear.
            let sparse = round % 3 == 2
            let (width, height): (Int64, Int64) = round % 3 == 0 ? (8_192, 768) : sparse ? (65_536, 65_536) : (8_192, 8_192)
            func newNode() -> TrackNodeID {
                let id = node(random.value(below: width), random.value(below: height), [0, 0, 0, 256, 512, 640][Int(random.value(below: 6))], in: &network)
                nodes.append(id)
                return id
            }
            for _ in 0..<(sparse ? 8 : 20 + Int(random.value(below: 20))) {
                // Now and then from a node already there: edges sharing a
                // node are not checked within the junction zone of it.
                let from = !nodes.isEmpty && random.value(below: 3) == 0 ? nodes[Int(random.value(below: Int64(nodes.count)))] : newNode()
                // Far apart, short edges: most networks are clear.
                let to = sparse ? node(
                    network.node(from)!.position.x + random.value(below: 4_096), network.node(from)!.position.y + random.value(below: 4_096), 0, in: &network
                ) : newNode()
                let (a, b) = (network.node(from)!.position.plan, network.node(to)!.position.plan)
                let curve: TrackCurve = random.value(below: 2) == 0 ? .straight : .cubic(
                    PlanPoint(x: a.x + random.value(below: 2_049) - 1_024, y: a.y + random.value(below: 2_049) - 1_024),
                    PlanPoint(x: b.x + random.value(below: 2_049) - 1_024, y: b.y + random.value(below: 2_049) - 1_024)
                )
                edge(from, to, curve: curve, in: &network)
            }
            let (indexed, reference) = Self.answers(network)
            XCTAssertEqual(indexed, reference, "round \(round)")
            if let first = reference.first {
                conflicts += 1
                // The sweep meets boxes in order of their left sides, not of
                // the edges: count networks where another conflicting pair
                // comes first that way, so the order is put to the test.
                let boxes = network.edges.map { network.planBox(of: $0)! }
                let sweepFirst = boxes.indices.min { (boxes[$0].minimum.x, $0) < (boxes[$1].minimum.x, $1) }!
                if network.edges[sweepFirst].id != first[0] { conflictNotFirstInSweep += 1 }
            } else {
                clear += 1
            }
            tooClose += reference.tooClose.count
        }
        XCTAssertGreaterThan(conflicts, 15)
        XCTAssertGreaterThan(clear, 5)
        XCTAssertGreaterThan(conflictNotFirstInSweep, 5)
        print("LoadTrackCheckIndexTests: \(conflicts) conflicting, \(clear) clear, \(conflictNotFirstInSweep) not first in the sweep, \(tooClose) pairs too close")
        XCTAssertGreaterThan(tooClose, 1_000)
    }

    /// Every pair of random shapes with many pieces: ``TrackClearance/isClear(_:_:)``
    /// with runs answers as with every piece, both ways round, when the
    /// shapes cross, run along each other, touch, or share an end.
    func testIsClearWithRunsAnswersAsEveryPiece() throws {
        var random = Generator(state: 16)
        var notClear = 0, clearWithBoxesMeeting = 0
        for _ in 0..<20 {
            var network = RailwayNetwork()
            for _ in 0..<10 {
                let from = node(random.value(below: 4_096), random.value(below: 4_096), [0, 0, 384, 512][Int(random.value(below: 4))], in: &network)
                let to = node(random.value(below: 4_096), random.value(below: 4_096), [0, 0, 384, 512][Int(random.value(below: 4))], in: &network)
                let (a, b) = (network.node(from)!.position.plan, network.node(to)!.position.plan)
                // Curves, so that there are many pieces and many runs.
                edge(from, to, curve: .cubic(
                    PlanPoint(x: a.x + random.value(below: 4_097) - 2_048, y: a.y + random.value(below: 4_097) - 2_048),
                    PlanPoint(x: b.x + random.value(below: 4_097) - 2_048, y: b.y + random.value(below: 4_097) - 2_048)
                ), in: &network)
            }
            let shapes = Self.shapes(of: network).map(\.1)
            for a in shapes {
                for b in shapes where a.from != b.from {
                    let expected = Self.everyPieceIsClear(a, b)
                    XCTAssertEqual(TrackClearance.isClear(a, b), expected)
                    if !expected {
                        notClear += 1
                    } else if PlanBox(a).meets(PlanBox(b)) {
                        clearWithBoxesMeeting += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(notClear, 50)
        XCTAssertGreaterThan(clearWithBoxesMeeting, 50)
    }

    /// Long curving double track 5 m apart, as the high-speed demo lays it,
    /// cut into edges, with a third track that runs closer than the spacing
    /// in places, and others that cross over it at and below the
    /// clearance.
    func testLongCurvingDoubleTrackAnswersAsEveryPair() throws {
        var random = Generator(state: 444)
        for round in 0..<6 {
            var network = RailwayNetwork()
            // A wandering line, as points 2,000 to 4,000 apart.
            var line: [(Int64, Int64)] = [(10_000, 10_000)]
            var heading: (Int64, Int64) = (3, 1)
            for _ in 0..<14 {
                heading = (heading.0 + random.value(below: 3) - 1, heading.1 + random.value(below: 3) - 1)
                if heading == (0, 0) { heading = (1, 0) }
                let step = 2_000 + random.value(below: 2_000)
                let length = max(abs(heading.0), abs(heading.1))
                line.append((line.last!.0 + heading.0 * step / length, line.last!.1 + heading.1 * step / length))
            }
            // Each track: the line offset sideways, its edges curving to
            // the next point, sharing nodes end to end.
            for offset: Int64 in [0, 320, 320 + 200 + random.value(below: 112)] {
                var previous: TrackNodeID?
                for (k, point) in line.enumerated() {
                    let node = node(point.0, point.1 + offset, in: &network)
                    if let previous {
                        let a = network.node(previous)!.position.plan, b = network.node(node)!.position.plan
                        let bend = random.value(below: 401) - 200
                        edge(previous, node, curve: k % 3 == 0 ? .straight : .cubic(
                            PlanPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3 + bend),
                            PlanPoint(x: a.x + 2 * (b.x - a.x) / 3, y: a.y + 2 * (b.y - a.y) / 3 + bend)
                        ), in: &network)
                    }
                    previous = node
                }
            }
            // Crossings over the tracks, at and just below the clearance,
            // and one at the tracks' level in the last round.
            for k in 0..<4 {
                let point = line[2 + 3 * k]
                let z = round == 5 && k == 3 ? 0 : TrackStructure.clearance - Int64(k % 2)
                edge(point.0 - 600, point.1 - 3_000, point.0 + 600, point.1 + 3_000, z: z, in: &network)
            }
            let (indexed, reference) = Self.answers(network)
            XCTAssertEqual(indexed, reference, "round \(round)")
            XCTAssertFalse(reference.tooClose.isEmpty, "round \(round): the third track runs too close")
            XCTAssertNotNil(reference.first, "round \(round): a crossing below the clearance")
        }
    }

    // MARK: - Made by hand

    /// Of several conflicting pairs, the first in edge order, whatever
    /// order the boxes lie in from left to right.
    func testTheFirstConflictIsTheFirstInEdgeOrder() {
        var network = RailwayNetwork()
        // Edge 1, far right, crosses edge 5; edges 2 and 3, far left, cross
        // each other; edge 4 is clear of all.
        edge(9_000, 0, 9_000, 2_000, in: &network)
        edge(0, 0, 2_000, 2_000, in: &network)
        edge(0, 2_000, 2_000, 0, in: &network)
        edge(4_000, 0, 4_000, 2_000, in: &network)
        edge(8_000, 1_000, 10_000, 1_000, in: &network)
        let (indexed, reference) = Self.answers(network)
        XCTAssertEqual(reference.first, [.edge(1), .edge(5)])
        XCTAssertEqual(indexed, reference)
    }

    /// Several pairs too close, found in edge order although their boxes
    /// lie the other way from left to right.
    func testPairsTooCloseComeInEdgeOrder() {
        var network = RailwayNetwork()
        let w = RailwayNetwork.trackSpacing
        edge(9_000, 0, 11_000, 0, in: &network)
        edge(0, 0, 2_000, 0, in: &network)
        edge(0, w - 1, 2_000, w - 1, in: &network)
        edge(9_000, w - 1, 11_000, w - 1, in: &network)
        let (indexed, reference) = Self.answers(network)
        XCTAssertEqual(reference.tooClose, [TrackEdgePair(.edge(1), .edge(4)), TrackEdgePair(.edge(2), .edge(3))])
        XCTAssertEqual(indexed, reference)
    }

    /// Boxes that only touch, at a corner or along a side, in x and in y:
    /// the edges meet there, and the pair is found.
    func testBoxesThatOnlyTouchAreTried() {
        for (a, b) in [
            // Along x = 1000: one ends on the other.
            ((1_000, 0, 1_000, 1_000), (0, 500, 1_000, 500)),
            // At a corner, end to end.
            ((0, 0, 1_000, 1_000), (1_000, 1_000, 2_000, 3_000)),
            // Along y = 1000.
            ((0, 1_000, 1_000, 1_000), (500, 0, 500, 1_000)),
            // The second's box lies left of the first's.
            ((1_000, 500, 2_000, 500), (1_000, 0, 1_000, 1_000)),
        ] as [((Int64, Int64, Int64, Int64), (Int64, Int64, Int64, Int64))] {
            var network = RailwayNetwork()
            edge(a.0, a.1, a.2, a.3, in: &network)
            edge(b.0, b.1, b.2, b.3, in: &network)
            let (indexed, reference) = Self.answers(network)
            XCTAssertEqual(reference.first, [.edge(1), .edge(2)], "\(a) \(b)")
            XCTAssertEqual(indexed, reference, "\(a) \(b)")
        }
    }

    /// Edges whose boxes are apart by one unit less than the spacing, in x,
    /// in y, and across a corner, are too close; one more unit apart, they
    /// keep it.
    func testEdgesTheSpacingApartAreTriedAcrossTheGap() {
        let w = RailwayNetwork.trackSpacing
        for gap in [w - 1, w] {
            for (a, b) in [
                // One after the other along x, end to end.
                ((0, 0, 1_000, 0), (1_000 + gap, 0, 2_000, 0)),
                // One above the other along y.
                ((0, 0, 0, 1_000), (0, 1_000 + gap, 0, 2_000)),
                // Side by side in y, the second's box left of the first's.
                ((1_000, 0, 2_000, 0), (1_000, gap, 1_500, gap)),
                // Side by side in x.
                ((0, 0, 0, 1_000), (gap, 0, gap, 1_000)),
            ] as [((Int64, Int64, Int64, Int64), (Int64, Int64, Int64, Int64))] {
                var network = RailwayNetwork()
                edge(a.0, a.1, a.2, a.3, in: &network)
                edge(b.0, b.1, b.2, b.3, in: &network)
                let (indexed, reference) = Self.answers(network)
                XCTAssertEqual(reference.tooClose, gap < w ? [TrackEdgePair(.edge(1), .edge(2))] : [], "gap \(gap): \(a) \(b)")
                XCTAssertEqual(indexed, reference, "gap \(gap): \(a) \(b)")
            }
        }
    }

    /// An edge ending at a T one unit closer than the spacing to the side
    /// of another, whose checkpoints (every 64 from y = −1000) pass 24 from
    /// its end: only the end's own checkpoint, the last of its edge (or the
    /// first, the other way round), comes close.
    func testOnlyAnEdgesEndCheckpointComesClose() {
        let w = RailwayNetwork.trackSpacing
        for reversed in [false, true] {
            var network = RailwayNetwork()
            if reversed {
                edge(1_000, 0, 0, 0, in: &network)
            } else {
                edge(0, 0, 1_000, 0, in: &network)
            }
            edge(1_000 + w - 1, -1_000, 1_000 + w - 1, 1_000, in: &network)
            let (indexed, reference) = Self.answers(network)
            XCTAssertEqual(reference.tooClose, [TrackEdgePair(.edge(1), .edge(2))], "reversed \(reversed)")
            XCTAssertEqual(indexed, reference, "reversed \(reversed)")
        }
    }

    /// The pairs in reach are every pair whose boxes widened by the margin
    /// meet, in order, on random boxes: wide, narrow, and of one point.
    func testPairsInReachAreEveryPairInReach() {
        var random = Generator(state: 7)
        for margin: Int64 in [0, 1, RailwayNetwork.trackSpacing] {
            for _ in 0..<20 {
                let boxes = (0..<60).map { _ in
                    let (x, y) = (random.value(below: 4_000), random.value(below: 4_000))
                    let (width, height) = [(0, 0), (random.value(below: 300), random.value(below: 300)), (random.value(below: 3_000), 2)][Int(random.value(below: 3))]
                    return PlanBox(minimum: PlanPoint(x: x, y: y), maximum: PlanPoint(x: x + width, y: y + height), lowest: 0, highest: 0)
                }
                var expected: [(Int, Int)] = []
                for i in boxes.indices {
                    for j in boxes.indices where j > i {
                        let (a, b) = (boxes[i], boxes[j])
                        if a.minimum.x - margin <= b.maximum.x + margin, b.minimum.x - margin <= a.maximum.x + margin,
                           a.minimum.y - margin <= b.maximum.y + margin, b.minimum.y - margin <= a.maximum.y + margin {
                            expected.append((i, j))
                        }
                    }
                }
                let found = PlanBox.pairsInReach(boxes, margin: margin)
                XCTAssertEqual(found.map(\.0), expected.map(\.0))
                XCTAssertEqual(found.map(\.1), expected.map(\.1))
            }
        }
    }
}
