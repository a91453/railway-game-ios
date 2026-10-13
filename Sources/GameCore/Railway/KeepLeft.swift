// Keeping left on double track (ARCHITECTURE decision 202). Taiwan's
// railways and its high-speed line run on the left, but the route a train
// found to a station took the first of equally short ways by edge number,
// so on double track both directions ran on one line (TestFlight 56.1).
// With the world's ``GameWorld/keepLeft`` on, the search for a route counts
// each switch where the train does not take its leftmost way on as
// ``GameWorld/keepLeftMargin`` longer: of two ways no more than that apart,
// the one to the left wins. Selection only: a path's distance is still its
// exact length. A line's chosen route (``LineRoutePreference``) is followed
// as before.

extension GameWorld {
    /// What the route search adds for each switch where a train keeping
    /// left does not take its leftmost way on (decision 202): 3200 units,
    /// 50 m. Longer than a crossover's turnouts add, or the outer track of
    /// a curve over a few hundred metres; shorter than a detour.
    public static let keepLeftMargin: Int64 = 3_200

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
    /// starts along the straight), by the chord to its far node. x grows
    /// east and y south, so a way is left of another when the cross product
    /// from the other to it is negative. Every way on leaves within 1 in 16
    /// of straight on (see ``PlanVector/isOpposite(to:)``), so the order is
    /// an order of angles. Ways the same both ways are equally leftmost.
    func rightOfLeftmost(after arrival: TrackTraversal, among exits: [TrackTraversal]) -> Set<TrackTraversal> {
        guard exits.count > 1, let edge = network.edge(arrival.edge), let node = network.node(edge.end(of: arrival.direction)) else { return [] }
        let ways = exits.compactMap { exit -> (exit: TrackTraversal, tangent: PlanVector, chord: PlanVector)? in
            guard let end = node.end(of: exit.edge), let far = network.edge(exit.edge).flatMap({ network.node($0.end(of: exit.direction)) }) else { return nil }
            return (exit, end.direction, far.position.plan.vector(from: node.position.plan))
        }
        // Whether `a` is left of `b`.
        func isLeft(_ a: (exit: TrackTraversal, tangent: PlanVector, chord: PlanVector), of b: (exit: TrackTraversal, tangent: PlanVector, chord: PlanVector)) -> Bool {
            let turn = b.tangent.cross(a.tangent)
            return turn != 0 ? turn < 0 : b.chord.cross(a.chord) < 0
        }
        return Set(ways.filter { way in ways.contains { isLeft($0, of: way) } }.map(\.exit))
    }
}
