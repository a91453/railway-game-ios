// Keeping left on double track (ARCHITECTURE decision 202). Taiwan's
// railways and its high-speed line run on the left, but the route a train
// found to a station took the first of equally short ways by edge number,
// so on double track both directions ran on one line (TestFlight 56.1).
// With the world's ``GameWorld/keepLeft`` on, the search for a route counts
// each switch where the train does not take its leftmost way on as
// ``GameWorld/keepLeftMargin`` longer: of two ways no more than that apart,
// the one to the left wins. Selection only: a path's distance is still its
// exact length. A line's chosen route (``LineRoutePreference``) is followed
// as before. Decision 564: a way to a station only lines keeping right
// (metros and light rails, ``ServiceLine/keepsRight``) serve keeps right
// instead, the same margin to the right, with keepLeft on or off.

extension GameWorld {
    /// What the route search adds for each switch where a train keeping
    /// left does not take its leftmost way on (decision 202): 3200 units,
    /// 50 m. Longer than a crossover's turnouts add, or the outer track of
    /// a curve over a few hundred metres; shorter than a detour.
    public static let keepLeftMargin: Int64 = 3_200

    /// Decision 564: two ways on whose end tangents differ by less than a
    /// slope of 1 in this leave the node the same way, and their chords
    /// order them. A crossover laid as an S-curve starts along its track
    /// but for the tangents' rounding (a slope of some 1 in 15,000 seen on
    /// the Sanying Line), which alone would put it on the wrong side.
    static let sameWaySlope: Int64 = 256

    /// Turns keeping left on or off (decision 202). A train already on its
    /// way keeps the route it was given.
    public mutating func setKeepLeft(_ enabled: Bool) {
        guard enabled != keepLeft else { return }
        keepLeft = enabled
    }

    /// The ways on from `arrival` that are not its leftmost, which a train
    /// keeping left takes only for a route ``keepLeftMargin`` shorter.
    /// Empty where there is one way on.
    ///
    /// The ways on are ordered by the way each leaves the node (its end
    /// tangent), then, where two leave it the same way (a turnout's curve
    /// starts along the straight; decision 564, to within a slope of 1 in
    /// ``sameWaySlope``), by the chord to its far node. x grows
    /// east and y south, so a way is left of another when the cross product
    /// from the other to it is negative. Every way on leaves within 1 in 16
    /// of straight on (see ``PlanVector/isOpposite(to:)``), so the order is
    /// an order of angles. Ways the same both ways are equally leftmost.
    /// With `mirrored` (decision 564), the ways on that are not its
    /// rightmost, which a train keeping right takes only for a route that
    /// much shorter.
    func rightOfLeftmost(after arrival: TrackTraversal, among exits: [TrackTraversal], mirrored: Bool = false) -> Set<TrackTraversal> {
        guard exits.count > 1, let edge = network.edge(arrival.edge), let node = network.node(edge.end(of: arrival.direction)) else { return [] }
        let ways = exits.compactMap { exit -> (exit: TrackTraversal, tangent: PlanVector, chord: PlanVector)? in
            guard let end = node.end(of: exit.edge), let far = network.edge(exit.edge).flatMap({ network.node($0.end(of: exit.direction)) }) else { return nil }
            return (exit, end.direction, far.position.plan.vector(from: node.position.plan))
        }
        // Whether `a` is left of `b`.
        func isLeft(_ a: (exit: TrackTraversal, tangent: PlanVector, chord: PlanVector), of b: (exit: TrackTraversal, tangent: PlanVector, chord: PlanVector)) -> Bool {
            let turn = b.tangent.cross(a.tangent)
            return abs(turn) > b.tangent.dot(a.tangent) / Self.sameWaySlope ? turn < 0 : b.chord.cross(a.chord) < 0
        }
        return Set(ways.filter { way in ways.contains { mirrored ? isLeft(way, of: $0) : isLeft($0, of: way) } }.map(\.exit))
    }

    /// Whether a way to station `id` keeps right rather than left
    /// (decision 564): every line that stops there or keeps its trains
    /// there (a depot of its) keeps right, and there is one. A station
    /// that lines keeping left serve too, or none, keeps left. Lines do
    /// not change within one advance or question, so ``PathMemo`` keeps
    /// its answers by station as before.
    func keepsRight(toward id: StationID) -> Bool {
        guard lines.contains(where: \.keepsRight) else { return false }
        var serving = false
        for line in lines where line.stops.contains(id) || line.depots.contains(id) {
            guard line.keepsRight else { return false }
            serving = true
        }
        return serving
    }
}
