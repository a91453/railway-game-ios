// Route finding: the shortest continuation that takes a train to a track
// tile, found by searching the network derived from the map on demand.
//
// A train cannot turn straight back (see TrainMovement), so where it can go
// next depends on the direction it faces as well as the node it is at. The
// search therefore visits states (node, heading), at most four per track
// tile, and never stores a graph: neighbours come from the same derived
// connectivity query that movement uses.

extension GameWorld {
    /// The shortest continuation that takes a train at `start` to the track
    /// tile `destination`, or `nil` if there is none.
    ///
    /// The result can be passed to ``setTrainContinuation(_:to:)`` unchanged
    /// on this world: it starts after the node ahead of the train (the node it
    /// stands on, or the `to` end of its link), every step is a joined link,
    /// and it never turns straight back, not even against the train's current
    /// heading. It ends at `destination`. An empty list means the node ahead
    /// is already `destination`.
    ///
    /// - Shortest means the fewest links. Every link is
    ///   ``TrainPosition/linkLength`` long, so this is also the shortest
    ///   distance.
    /// - Among shortest routes the result is the one whose sequence of exit
    ///   directions comes first when directions are ordered north, east,
    ///   south, west (compared step by step from the start). The answer
    ///   depends only on the map, `start` and `destination`, never on build
    ///   order, and is the same on every run and platform.
    /// - A route never reverses the train. It may loop, pass a node twice or
    ///   use a junction to change direction; if the only way to
    ///   `destination` starts by turning back, there is no route until the
    ///   train is reversed.
    ///
    /// Returns `nil` when `start` is not a valid position on this map's track
    /// (see ``placeTrain(_:at:)``), when `destination` is not a track tile
    /// (empty, a station, or outside the map), or when no route exists. To
    /// go to a station, use ``route(from:toStation:)``.
    ///
    /// Pure: reads the map only through its public queries (the start and
    /// destination checks, then ``connectedNeighbors(of:)`` while
    /// searching), changes nothing and keeps no cache. It explores only track
    /// reachable from `start`: at most four states per track tile, so time
    /// and memory are O(reachable track tiles), without scanning the map. On
    /// a nearly full 1024 x 1024 map that is seconds and hundreds of
    /// megabytes, so a host should not call it synchronously on the main
    /// actor for large maps.
    public func route(from start: TrainPosition, to destination: GridPosition) -> [GridPosition]? {
        guard isOnTrack(start), track(at: destination) != nil else { return nil }
        let (node, heading) = start.ahead
        return TrainRoute.shortest(from: node, heading: heading, to: { $0 == destination }) { connectedNeighbors(of: $0) }
    }
}

/// The route-finding kernel, separate from ``GameWorld`` so that it sees the
/// network only through the neighbour query it is given.
enum TrainRoute {
    /// A place in the search: a node and the direction the train faces there.
    private struct State: Hashable {
        var node: GridPosition
        var heading: TrackDirection
    }

    /// Breadth-first search over (node, heading) from `node` facing
    /// `heading` to any state at a node that `isDestination` accepts.
    ///
    /// `neighbors` must list the nodes joined to a node in north, east,
    /// south, west order. States are expanded in the order they were found
    /// and their neighbours in that fixed order, so each layer of the search
    /// is discovered in the order of its routes' direction sequences, and the
    /// first route found to a destination is the shortest and, among the
    /// shortest, the first in that order. It ends at the first destination
    /// it reaches, so it passes no other destination on the way. The search
    /// ends, at the latest, when every reachable state has been visited once.
    static func shortest(
        from node: GridPosition,
        heading: TrackDirection,
        to isDestination: (GridPosition) -> Bool,
        neighbors: (GridPosition) -> [GridPosition]
    ) -> [GridPosition]? {
        guard !isDestination(node) else { return [] }

        // Every discovered state with the index of the state it was reached
        // from; the queue is the array itself, read from `next` onward.
        var found: [(state: State, previous: Int)] = [(State(node: node, heading: heading), -1)]
        var seen: Set<State> = [State(node: node, heading: heading)]
        var next = 0
        while next < found.count {
            let current = found[next].state
            for neighbor in neighbors(current.node) {
                guard let direction = TrackDirection(from: current.node, to: neighbor),
                      direction != current.heading.opposite
                else { continue }
                let state = State(node: neighbor, heading: direction)
                guard seen.insert(state).inserted else { continue }
                found.append((state, next))
                if isDestination(neighbor) {
                    return path(to: found.count - 1, in: found)
                }
            }
            next += 1
        }
        return nil
    }

    /// The nodes from the start's first step to `index`, following the
    /// recorded predecessors back to the start (which is not included).
    private static func path(to index: Int, in found: [(state: State, previous: Int)]) -> [GridPosition] {
        var nodes: [GridPosition] = []
        var index = index
        while found[index].previous >= 0 {
            nodes.append(found[index].state.node)
            index = found[index].previous
        }
        return nodes.reversed()
    }
}
