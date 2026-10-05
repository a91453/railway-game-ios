// Service paths (Phase 4.5 Stage S5, ARCHITECTURE decision 31): the form a
// service's route takes, and the adapters services plan with: where a
// station's trains stop, the route there, how a route becomes a train's
// movement (`follow` and `stand` in GameWorld.swift, the only file that sets
// trains), and where a train and its body are after turning round or
// following a route. Timetables, dwells, repeats, lines, dispatch and
// patterns are written on top of these. (Until Stage F3c they also told the
// grid and the track network apart; the grid went, decision 51.)

/// A path for a train (Phase 4.5 Stage S5): the edges its head enters after
/// the one it is on, in order, where it stops on the last of them, and how
/// far that is.
///
/// The form a route to a station takes (see
/// ``GameWorld/path(from:toStation:length:)``), what a service
/// gives a train to follow, and what a line's journey is made of (see
/// ``LineLeg``). It is topology only: traversals and integer distances, no
/// geometry. A train keeps its path in its ``TrainMovement``; this value is
/// not saved.
///
/// Like ``TrainPosition``, the struct accepts any values. Validity is checked
/// where a path enters a world:
/// ``GameWorld/setTrainContinuation(_:along:stoppingAt:)`` takes its
/// traversals and end.
public struct TrainPath: Hashable, Sendable {
    /// The traversals the head enters, in order, after the edge it is on.
    /// Empty when it stops on the edge it is on.
    public let traversals: [TrackTraversal]
    /// How far along the last traversal (or, when there are none, the one
    /// the train is on) the head stops, measured from where that traversal
    /// starts, or `nil` at its end.
    public let end: Int64?
    /// How far the head travels to get there, in world units: the rest of
    /// the edge it is on, every traversal in between in full, and the last
    /// one up to where it stops. Exact integers.
    public let distance: Int64

    public init(traversals: [TrackTraversal], end: Int64?, distance: Int64) {
        self.traversals = traversals
        self.end = end
        self.distance = distance
    }
}

/// Where a train stands and how its body lies (Stage S5): its head, its
/// body and its length. What services plan from.
struct TrainPlacement: Hashable, Sendable {
    var position: TrainPosition
    /// The body (see ``Train/trailEdges``).
    var trailEdges: [TrackEdgeID]
    let length: Int64
}

extension Train {
    /// Where the train stands, or `nil` while it is unplaced.
    var placement: TrainPlacement? {
        position.map { TrainPlacement(position: $0, trailEdges: trailEdges, length: length) }
    }
}

extension GameWorld {
    // MARK: - Where trains stop (resolvePlatforms)

    /// Where a train stops for a platform on the track network (Stage S5):
    /// with its head at the far end of the platform the way it travels, its
    /// body behind.
    struct Berth: Hashable {
        let traversal: TrackTraversal
        let offset: Int64
    }

    /// The berths station `id` has on the track network for a train
    /// `length` long (Stage S5): for each of its platforms that the train
    /// fits (`length <= end − start`), in order along the track, the head
    /// at the platform's `end` travelling its edge forward, then at its
    /// `start` travelling backward (`L − start` along that way, `L` the
    /// edge's length). Always above 0, so a train with a body can stop at
    /// any of them; at the end of an edge, a berth is the node, written as
    /// the end of that edge. Empty for an unknown station.
    func berths(of id: StationID, length: Int64) -> [Berth] {
        network.platforms(of: id).flatMap { platform -> [Berth] in
            guard platform.length >= length, let edge = network.edge(platform.edge) else { return [] }
            return [
                Berth(traversal: TrackTraversal(edge: platform.edge, direction: .forward), offset: platform.end),
                Berth(traversal: TrackTraversal(edge: platform.edge, direction: .backward), offset: edge.length - platform.start),
            ]
        }
    }

    // MARK: - Routes to stations (resolveRoute)

    /// The shortest path that takes a train `length` long at `start` to
    /// where it stops for the station `id` (Stage S5), or `nil` if there is
    /// none: the route every service and line takes to a station.
    ///
    /// It ends at a berth of one of the station's platforms that the train
    /// fits: its head at the platform's far end the way it travels (see
    /// ``TrackPlatform``). It is the shortest exact distance to any such
    /// berth; among paths of that distance, the one whose choices come first
    /// step by step, with a berth ahead on the same traversal before a turn
    /// and turns in ascending edge order at each node, as
    /// ``route(from:to:)`` does. It never turns straight back along an edge;
    /// it may loop. `end` is `nil` when the berth is the end of its edge.
    ///
    /// No traversals and no distance means the train is already where it
    /// stops for the station.
    /// The result can be passed to
    /// ``setTrainContinuation(_:along:stoppingAt:)`` unchanged on this
    /// world, as `along: path.traversals, stoppingAt: path.end`.
    ///
    /// `nil` when `start` is not on this world's track, when the station
    /// does not exist or has no platform that the train fits, or when none
    /// can be reached
    /// without turning straight back. Pure: reads only topology, edge
    /// lengths and platforms, and explores only track no further than the
    /// nearest berth.
    public func path(from start: TrainPosition, toStation id: StationID, length: Int64 = 0) -> TrainPath? {
        switch start {
        case .onEdge(let traversal, let offset):
            return networkPath(from: traversal, offset: offset, toStation: id, length: length)
        }
    }

    /// A place in the search for a berth: where the train starts, the start
    /// of a traversal it has just entered, or a berth.
    private enum BerthSearch: Hashable {
        case start
        case entered(TrackTraversal)
        case berth(TrackTraversal, Int64)
    }

    /// ``path(from:toStation:length:)``: the one search
    /// of ``TrainRoute/shortest(from:isDestination:next:)`` over the start,
    /// the traversals the train could enter and the station's berths. Every
    /// step's length is the distance the head travels: from a traversal to
    /// a berth on it, the berth's offset less where the head is on it (0
    /// just after entering it); to the next traversal, the rest of this
    /// one. Only a step from the start can be 0.
    private func networkPath(from start: TrackTraversal, offset: Int64, toStation id: StationID, length: Int64, blocked: Set<TrackResource> = [], forbidden: Set<TrackTraversal> = [], berthPenalty: [Berth: Int64] = [:], edgePenalty: [TrackEdgeID: Int64] = [:]) -> TrainPath? {
        guard isOnNetwork(start, offset: offset) else { return nil }
        // Each traversal's berths, nearest first. Only looked up by key.
        var berthsAlong: [TrackTraversal: [Int64]] = [:]
        for berth in berths(of: id, length: length) {
            berthsAlong[berth.traversal, default: []].append(berth.offset)
        }
        guard !berthsAlong.isEmpty else { return nil }
        berthsAlong = berthsAlong.mapValues { $0.sorted() }
        let route = TrainRoute.shortest(from: BerthSearch.start, isDestination: { place in
            if case .berth = place { true } else { false }
        }) { place -> [(BerthSearch, Int64)] in
            let (traversal, from): (TrackTraversal, Int64)
            switch place {
            case .start: (traversal, from) = (start, offset)
            case .entered(let entered): (traversal, from) = (entered, 0)
            case .berth: return []
            }
            let edgeLength = network.edge(traversal.edge)!.length
            func allowed(to end: Int64) -> Bool {
                if end > from, forbidden.contains(traversal) { return false }
                guard !blocked.isEmpty else { return true }
                let step = [TrackStretch(traversal: traversal, from: from, to: end)]
                let track = Set(resources(covering: step)).union(foulingNodes(covering: step))
                return !network.fouls(track, blocked)
            }
            let stops = (berthsAlong[traversal] ?? []).filter { $0 >= from && allowed(to: $0) }
                .map { (BerthSearch.berth(traversal, $0), $0 - from + (berthPenalty[Berth(traversal: traversal, offset: $0)] ?? 0) + (edgePenalty[traversal.edge] ?? 0)) }
            return stops + (allowed(to: edgeLength) ? transitions(after: traversal).map { (.entered($0), edgeLength - from + (edgePenalty[traversal.edge] ?? 0)) } : [])
        }
        guard let route, case .berth(let last, let end)? = route.last else { return nil }
        let traversals = route.dropLast().map { place -> TrackTraversal in
            guard case .entered(let traversal) = place else { preconditionFailure("only the last place of a route is a berth") }
            return traversal
        }
        // The rest of the start's edge, every traversal between in full,
        // and the last up to the berth; on the start's edge alone, the way
        // to the berth.
        let stop = end == network.edge(last.edge)!.length ? nil : end
        guard !traversals.isEmpty else { return TrainPath(traversals: [], end: stop, distance: end - offset) }
        var distance = network.edge(start.edge)!.length - offset
        for part in traversals.dropLast().map({ network.edge($0.edge)!.length }) + [end] {
            let (sum, overflow) = distance.addingReportingOverflow(part)
            guard !overflow else { return nil }
            distance = sum
        }
        return TrainPath(traversals: traversals, end: stop, distance: distance)
    }

    /// Stage V1: the same shortest-path order, excluding each head step
    /// whose spans or fouling nodes conflict with the other trains' track.
    /// A berth short of a blocked span on the same edge remains reachable.
    /// The caller must still reserve the whole envelope, including the body.
    func path(from start: TrainPosition, toStation id: StationID, length: Int64, avoiding blocked: Set<TrackResource>, forbidden: Set<TrackTraversal> = []) -> TrainPath? {
        switch start {
        case .onEdge(let traversal, let offset):
            networkPath(from: traversal, offset: offset, toStation: id, length: length, blocked: blocked, forbidden: forbidden)
        }
    }

    /// V3 generalized path cost (migration map §7). The geometric length
    /// in TrainPath remains exact; penalties affect selection only.
    func trafficPath(from start: TrainPosition, toStation id: StationID, length: Int64,
                     berthPenalty: [Berth: Int64], edgePenalty: [TrackEdgeID: Int64]) -> TrainPath? {
        switch start {
        case .onEdge(let traversal, let offset):
            networkPath(from: traversal, offset: offset, toStation: id, length: length,
                        berthPenalty: berthPenalty, edgePenalty: edgePenalty)
        }
    }

    // MARK: - Trains and their bodies

    /// `placement` turned round where it stands, as ``reverseTrain(_:)``
    /// turns a train: its head where its tail was, facing away from where
    /// its head was. Turning round twice gives back the same placement.
    func turnedRound(_ placement: TrainPlacement) -> TrainPlacement {
        var turned = placement
        switch placement.position {
        case .onEdge(let traversal, let offset):
            (turned.position, turned.trailEdges) = reversedOnNetwork(traversal, offset: offset, trail: placement.trailEdges, length: placement.length)
        }
        return turned
    }

    /// Where `placement` stands once its head has followed `path` to where
    /// it stops, its body behind it along the way it came.
    ///
    /// - Precondition: `path` is a path for a train at `placement` on this
    ///   world (as ``path(from:toStation:length:)`` gives it).
    func placement(_ placement: TrainPlacement, after path: TrainPath) -> TrainPlacement {
        var moved = placement
        switch placement.position {
        case .onEdge(let traversal, _):
            let last = path.traversals.last ?? traversal
            let end = path.end ?? network.edge(last.edge)!.length
            moved.position = .onEdge(last, offset: end)
            moved.trailEdges = networkTrail(
                after: traversal.edge, trail: placement.trailEdges, entered: path.traversals.map(\.edge)[...], offset: end, length: placement.length
            )
        }
        return moved
    }
}
