// Block sections (ARCHITECTURE decision 212). Under traffic control a
// service whose route another train holds may follow the trains ahead
// (Stage U2, decision 56), but on a high-speed leg of 30 to 180 km few
// could: a train following another led nobody, only a service's default
// path could be followed, a following train waited for all its route ahead
// and kept every other train from it, and it took more of its route almost
// every second (docs/research/BLOCK_SECTIONS_2026-10-13.md).
//
// With the world's ``GameWorld/blockSections`` on:
//
// 1. every edge is cut into blocks of ``blockLength`` from its `from` node,
//    its ends bounding blocks too, and a following train's authority ends
//    at a block's boundary (still ``followingGap`` short of the track the
//    trains ahead hold), so it takes its route a block at a time;
// 2. a train following others leads a train behind it as well;
// 3. a following train holds only what it has taken: the track of its
//    route it has not taken yet keeps no other train from it (decision 56,
//    point 6, does not apply);
// 4. a service may follow the trains ahead on its scheduled path (decision
//    59) or its line's preferred path (decision 61), not only on its
//    default one.
//
// The boundaries are worked out from topology and integer chainage only,
// never saved. Missing key is off: GameCore's new world, old saves, the
// demos, the challenges and the tutorial take and follow as before.

extension GameWorld {
    /// The length of a block section (decision 212): 96,000 units, 1.5 km,
    /// the length of the track circuits a Shinkansen's digital ATC works on.
    public static let blockLength: Int64 = 96_000

    /// Turns block sections on or off (decision 212). A train already
    /// following another keeps what it holds; from then on it takes more by
    /// the new rule.
    public mutating func setBlockSections(_ enabled: Bool) {
        guard enabled != blockSections else { return }
        blockSections = enabled
    }

    /// How far a following train's authority may reach along its route
    /// (see ``AuthorityEnvelopes``) when the track as far as `free` is
    /// clear: ``followingGap`` short of it and, with block sections, back
    /// to the boundary of a block at or before that.
    func followingAuthority(_ envelopes: AuthorityEnvelopes, free: Int64) -> Int64 {
        let authority = free - Self.followingGap
        return blockSections ? blockBoundary(envelopes, atOrBefore: authority) : authority
    }

    /// How far clear a following train's track must be for its authority
    /// to reach beyond `held` (see ``followingAuthority(_:free:)``): one
    /// past ``followingGap`` beyond it, or, with block sections,
    /// ``followingGap`` beyond the next block's boundary; `nil` when only
    /// its whole route will do.
    func reachToExtend(_ envelopes: AuthorityEnvelopes, beyond held: Int64) -> Int64? {
        guard blockSections else {
            let (reach, overflow) = held.addingReportingOverflow(Self.followingGap + 1)
            return overflow ? nil : reach
        }
        guard let boundary = blockBoundary(envelopes, after: held) else { return nil }
        let (reach, overflow) = boundary.addingReportingOverflow(Self.followingGap)
        return overflow ? nil : reach
    }

    /// Whether `chainage` along edge `edge`, measured from its `from` node,
    /// bounds a block: an end of the edge, or a whole number of
    /// ``blockLength`` from its `from` node. Never at a junction, nor within
    /// ``RailwayNetwork/junctionZone`` of one (a node where more than two
    /// edges end): a train waits for more of its route on plain track, and
    /// takes its way through a station's turnouts at once, as decision 32
    /// takes a whole route, so it never stands among them holding half a
    /// way another train needs to cross.
    private func isBlockBoundary(_ chainage: Int64, of edge: TrackEdge) -> Bool {
        if isJunction(edge.from), chainage < RailwayNetwork.junctionZone { return false }
        if isJunction(edge.to), edge.length - chainage < RailwayNetwork.junctionZone { return false }
        return chainage == 0 || chainage == edge.length || chainage % Self.blockLength == 0
    }

    /// Whether more than two edges end at node `node`.
    private func isJunction(_ node: TrackNodeID) -> Bool {
        (network.node(node)?.ends.count ?? 0) > 2
    }

    /// The farthest block boundary along the route of `envelopes`, measured
    /// from the head as its distances are, at or before `distance`; 0 when
    /// there is none beyond the head.
    func blockBoundary(_ envelopes: AuthorityEnvelopes, atOrBefore distance: Int64) -> Int64 {
        guard distance > 0, !envelopes.stretches.isEmpty else { return 0 }
        let last = envelopes.ends.firstIndex { distance <= $0 } ?? envelopes.stretches.count - 1
        let distance = min(distance, envelopes.length)
        for index in stride(from: last, through: 0, by: -1) {
            let start = index == 0 ? 0 : envelopes.ends[index - 1]
            let limit = index == last ? distance - start : envelopes.ends[index] - start
            if let along = boundaries(on: envelopes.stretches[index], upTo: limit).last { return start + along }
        }
        return 0
    }

    /// The nearest block boundary along the route of `envelopes` beyond
    /// `distance`, or `nil` when there is none before its end.
    func blockBoundary(_ envelopes: AuthorityEnvelopes, after distance: Int64) -> Int64? {
        let distance = max(distance, 0)
        guard let first = envelopes.ends.firstIndex(where: { distance < $0 }) else { return nil }
        for index in first..<envelopes.stretches.count {
            let start = index == 0 ? 0 : envelopes.ends[index - 1]
            let stretch = envelopes.stretches[index]
            if let along = boundaries(on: stretch, upTo: stretch.to - stretch.from).first(where: { start + $0 > distance }) {
                return start + along
            }
        }
        return nil
    }

    /// The block boundaries on `stretch`, as distances from its start the
    /// way it is travelled, in order, up to `limit` along it. Its start
    /// counts only where it leaves a node (it is the end of the stretch
    /// before); its end only where it reaches one.
    private func boundaries(on stretch: TrackStretch, upTo limit: Int64) -> [Int64] {
        guard let edge = network.edge(stretch.traversal.edge) else { return [] }
        let forward = stretch.traversal.direction == .forward
        let (low, high) = (stretch.from, min(stretch.to, stretch.from + limit))
        guard low <= high else { return [] }
        // Points along the way it is travelled: the edge's ends, and every
        // whole block from its `from` node.
        var points: [Int64] = [0, edge.length]
        var block = Self.blockLength
        while block < edge.length {
            points.append(forward ? block : edge.length - block)
            block += Self.blockLength
        }
        return points.filter { $0 > low || ($0 == low && low == 0) }
            .filter { $0 <= high && (($0 < stretch.to) || stretch.to == edge.length) }
            .filter { isBlockBoundary(forward ? $0 : edge.length - $0, of: edge) }
            .sorted()
            .map { $0 - low }
    }
}
