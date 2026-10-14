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

    /// Whether `chainage` along an edge `length` long, measured from its
    /// `from` node, bounds a block: an end of the edge, or a whole number
    /// of ``blockLength`` from its `from` node.
    private static func isBlockBoundary(_ chainage: Int64, length: Int64) -> Bool {
        chainage == 0 || chainage == length || chainage % blockLength == 0
    }

    /// The farthest block boundary along the route of `envelopes`, measured
    /// from the head as its distances are, at or before `distance`; 0 when
    /// there is none beyond the head.
    func blockBoundary(_ envelopes: AuthorityEnvelopes, atOrBefore distance: Int64) -> Int64 {
        guard distance > 0, !envelopes.stretches.isEmpty else { return 0 }
        var index = envelopes.ends.firstIndex { distance <= $0 } ?? envelopes.stretches.count - 1
        var distance = min(distance, envelopes.length)
        while index >= 0 {
            let stretch = envelopes.stretches[index]
            let start = index == 0 ? 0 : envelopes.ends[index - 1]
            guard let length = network.edge(stretch.traversal.edge)?.length else { return 0 }
            let at = stretch.from + (distance - start)
            // The boundary at or before `at`, the way the stretch is
            // travelled.
            let boundary: Int64
            if Self.isBlockBoundary(stretch.traversal.direction == .forward ? at : length - at, length: length) {
                boundary = at
            } else if stretch.traversal.direction == .forward {
                boundary = at / Self.blockLength * Self.blockLength
            } else {
                let chainage = length - at
                boundary = length - min(length, (chainage / Self.blockLength + 1) * Self.blockLength)
            }
            if boundary >= stretch.from {
                return max(0, start + (boundary - stretch.from))
            }
            // None on this stretch: the end of the one before, where it
            // leaves its edge.
            index -= 1
            guard index >= 0 else { return 0 }
            distance = envelopes.ends[index]
        }
        return 0
    }

    /// The nearest block boundary along the route of `envelopes` beyond
    /// `distance`, or `nil` when there is none before its end.
    func blockBoundary(_ envelopes: AuthorityEnvelopes, after distance: Int64) -> Int64? {
        let distance = max(distance, 0)
        guard let index = envelopes.ends.firstIndex(where: { distance < $0 }) else { return nil }
        let stretch = envelopes.stretches[index]
        let start = index == 0 ? 0 : envelopes.ends[index - 1]
        guard let length = network.edge(stretch.traversal.edge)?.length else { return nil }
        let at = stretch.from + (distance - start)
        let boundary: Int64
        if stretch.traversal.direction == .forward {
            boundary = min(length, (at / Self.blockLength + 1) * Self.blockLength)
        } else {
            let chainage = length - at
            boundary = length - (chainage - 1) / Self.blockLength * Self.blockLength
        }
        guard boundary <= stretch.to else {
            // The stretch ends first: where it leaves its edge, unless the
            // route ends there.
            return stretch.to == length ? envelopes.ends[index] : nil
        }
        return start + (boundary - stretch.from)
    }
}
