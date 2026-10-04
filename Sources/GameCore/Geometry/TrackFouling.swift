// Tracks closer than the track spacing foul each other (Stage F2b,
// ARCHITECTURE decision 53). Two points of different edges at one level,
// less than RailwayNetwork.trackSpacing apart in plan but more than
// RailwayNetwork.foulingLength apart along the track, are beside each other:
// trains on both would touch. That is a junction's tracks before they have
// parted (Stage F2 allows them within RailwayNetwork.partingReach along the
// track), the tracks between two turnouts of a ladder, or a pair built too
// close before Stage F2. Nearer along the track the two points are one
// stretch of track round a node, which Stage T's junctions cover.
//
// The spans of the two edges there foul each other: under traffic control a
// train cannot take track that fouls track another train holds. Worked out
// from the geometry whenever the network changes, never while trains move;
// traffic control reads only the result.

extension RailwayNetwork {
    /// The least distance along the track between two points closer than
    /// ``trackSpacing`` at which trains on them stand side by side (Stage
    /// F2b): 512 units (8 m), twice the spacing. Nearer along the track the
    /// two points are one stretch of track round a node: two trains there
    /// are nose to tail, or both at the junction, which they then both hold
    /// (``junctionZone``).
    public static let foulingLength: Int64 = 512

    /// For every span of the network that fouls spans of other edges, those
    /// spans (see ``foulingSpans``): worked out from the edges, their
    /// geometry and their platforms.
    func workOutFouling() -> [TrackSpan: Set<TrackSpan>] {
        var fouling: [TrackSpan: Set<TrackSpan>] = [:]
        addFouling(of: Set(edges.map(\.id)), to: &fouling)
        return fouling
    }

    /// The fouling again after a change that can only change it between
    /// pairs of edges at least one of which is in `changed`: everything else
    /// is kept, and those pairs are worked out again. The result is the same
    /// as ``workOutFouling()``.
    func foulingAfterChange(to changed: Set<TrackEdgeID>) -> [TrackSpan: Set<TrackSpan>] {
        var fouling = foulingSpans
        for (span, partners) in foulingSpans where changed.contains(span.edge) {
            fouling[span] = nil
            for partner in partners where !changed.contains(partner.edge) {
                fouling[partner]?.remove(span)
                if fouling[partner]?.isEmpty == true { fouling[partner] = nil }
            }
        }
        addFouling(of: changed, to: &fouling)
        return fouling
    }

    /// The edges whose fouling a way along the track through node `a` or
    /// `b` can change: those with an end within ``foulingLength`` of either
    /// (a way through them shorter than that runs within it of both its
    /// points' edges' ends).
    func edgesNear(_ a: TrackNodeID, _ b: TrackNodeID) -> Set<TrackEdgeID> {
        let near = Set(trackDistances(from: a, within: Self.foulingLength).keys).union(trackDistances(from: b, within: Self.foulingLength).keys)
        return Set(edges.filter { near.contains($0.from) || near.contains($0.to) }.map(\.id))
    }

    /// Adds to `fouling` the spans that foul each other of every pair of
    /// edges at least one of which is in `changed`.
    private func addFouling(of changed: Set<TrackEdgeID>, to fouling: inout [TrackSpan: Set<TrackSpan>]) {
        let boxes = edges.map { planBox(of: $0) }
        var shapes: [TrackEdgeID: ClearanceShape] = [:]
        func shape(_ edge: TrackEdge) -> ClearanceShape? {
            if shapes[edge.id] == nil { shapes[edge.id] = clearanceShape(of: edge.id) }
            return shapes[edge.id]
        }
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        func distance(_ a: TrackNodeID, _ b: TrackNodeID) -> Int64? {
            if reach[a] == nil { reach[a] = trackDistances(from: a, within: Self.foulingLength) }
            return reach[a]?[b]
        }
        for i in edges.indices {
            for j in edges.indices where j > i {
                guard changed.contains(edges[i].id) || changed.contains(edges[j].id),
                      let boxA = boxes[i], let boxB = boxes[j], boxA.mayComeClose(to: boxB),
                      let shapeA = shape(edges[i]), let shapeB = shape(edges[j])
                else { continue }
                let a = (edges[i], shapeA)
                let b = (edges[j], shapeB)
                let pairs = TrackSpacing.besidePoints(a.1, b.1, within: Self.foulingLength, distance: distance)
                guard !pairs.isEmpty else { continue }
                let spansA = spans(of: a.0.id, length: a.0.length)
                let spansB = spans(of: b.0.id, length: b.0.length)
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
    }

    /// Whether track in `a` and track in `b` are the same or foul each
    /// other: a resource in both, or a span in one that fouls a span in the
    /// other (Stage F2b).
    func fouls(_ a: Set<TrackResource>, _ b: Set<TrackResource>) -> Bool {
        if !a.isDisjoint(with: b) { return true }
        guard !foulingSpans.isEmpty else { return false }
        for case .span(let x) in a {
            guard let partners = foulingSpans[x] else { continue }
            for case .span(let y) in b where partners.contains(y) { return true }
        }
        return false
    }
}

extension TrackSpacing {
    /// The points of `a` and `b` beside each other farther apart along the
    /// track than `limit`: for each checkpoint of either close to the other
    /// (see ``closePieces(to:of:)``) at a point more than `limit` from it
    /// along the track, its chainage along `a` and that point's along `b`.
    /// `distance` gives the shortest way along the track between two nodes,
    /// or `nil` when it is longer than `limit`.
    static func besidePoints(
        _ a: ClearanceShape, _ b: ClearanceShape, within limit: Int64, distance: (TrackNodeID, TrackNodeID) -> Int64?
    ) -> [(Int64, Int64)] {
        let w = RailwayNetwork.trackSpacing
        guard a.minimum.x - w < b.maximum.x, b.minimum.x - w < a.maximum.x, a.minimum.y - w < b.maximum.y, b.minimum.y - w < a.maximum.y else {
            return []
        }
        if a.lowest - b.highest >= TrackStructure.clearance || b.lowest - a.highest >= TrackStructure.clearance {
            return []
        }
        let ends = Ends(a, b, distance: distance)
        var found: [(Int64, Int64)] = []
        for (first, second, way, swap) in [(a, b, ends, false), (b, a, ends.swapped, true)] {
            let pieces = Pieces(second, near: first)
            guard !pieces.indices.isEmpty else { continue }
            let length = first.geometry.length
            let otherLength = second.geometry.length
            for s in checkpoints(along: length) {
                for t in closePieces(to: first.geometry.location(at: s).position, of: pieces)
                where !way.isWithin(limit, s, of: length, t, of: otherLength) {
                    found.append(swap ? (t, s) : (s, t))
                }
            }
        }
        return found
    }
}
