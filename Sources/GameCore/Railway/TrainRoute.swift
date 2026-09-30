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
    /// destination checks, then ``exits(from:facing:)`` while searching),
    /// changes nothing and keeps no cache. It explores only track
    /// reachable from `start`: at most four states per track tile, so time
    /// and memory are O(reachable track tiles), without scanning the map. On
    /// a nearly full 1024 x 1024 map that is seconds and hundreds of
    /// megabytes, so a host should not call it synchronously on the main
    /// actor for large maps.
    public func route(from start: TrainPosition, to destination: GridPosition) -> [GridPosition]? {
        guard isOnTrack(start), track(at: destination) != nil, let (node, heading) = start.ahead else { return nil }
        return TrainRoute.shortest(from: node, heading: heading, to: { $0 == destination }) { exits(from: $0, facing: $1) }
    }

    /// The shortest route that takes a train at `start` to node `node` of
    /// the railway graph, as the traversals it would travel after the edge
    /// or link it is on, or `nil` if there is none (Stage S3). One search
    /// for the grid and the track network:
    ///
    /// - On the grid (`start` on the grid, `node` a tile) it is
    ///   ``route(from:to:)`` written as links.
    /// - On the network (`start` on an edge, `node` a network node) it
    ///   starts at the end of the edge the train is on and ends where it
    ///   first reaches `node`: the least total length, and among routes of
    ///   that length the one whose edges come first in ascending order at
    ///   each node, compared step by step from the start. It never turns
    ///   straight back along an edge; it may loop.
    ///
    /// An empty list means the train is at, or is heading along its edge
    /// for, `node`. The result can be passed to
    /// ``setTrainContinuation(_:along:)`` unchanged on this world. `nil` when
    /// `start` is not on this world's track, `node` is not a node of the
    /// same kind of track, or no route exists. Pure: reads only topology and
    /// lengths, and explores only track no further than the route.
    public func route(from start: TrainPosition, to node: TrackNodeID) -> [TrackTraversal]? {
        guard isOnTrack(start) else { return nil }
        switch (start, node) {
        case (.onEdge(let traversal, _), .node):
            guard network.node(node) != nil else { return nil }
            return TrainRoute.shortest(from: traversal, isDestination: { network.edge($0.edge)?.end(of: $0.direction) == node }) { arrival in
                transitions(after: arrival).map { ($0, network.edge($0.edge)!.length) }
            }
        case (.onEdge, .tile), (_, .node):
            return nil
        case (_, .tile(let tile)):
            guard let path = route(from: start, to: tile), let (first, _) = start.ahead else { return nil }
            var ahead = first
            return path.map { next in
                defer { ahead = next }
                return TrackTraversal.link(from: ahead, to: next)
            }
        }
    }
}

/// The route-finding kernel, separate from ``GameWorld`` so that it sees the
/// network only through the neighbour query it is given. One search serves
/// the grid and the track network (ARCHITECTURE decision 29).
enum TrainRoute {
    /// A place in the grid search: a node and the direction the train faces
    /// there.
    private struct State: Hashable {
        var node: GridPosition
        var heading: TrackDirection
    }

    /// The grid route from `node` facing `heading` to any node that
    /// `isDestination` accepts: the generic search over (node, heading)
    /// states, every link ``TrainPosition/linkLength`` long.
    ///
    /// `exits` must list the nodes a train at a node facing a heading may go
    /// on to, in north, east, south, west order (see
    /// ``GameWorld/exits(from:facing:)``). The result is the route with the
    /// fewest links and, among those, the one whose exit directions come
    /// first in that order, compared step by step from the start. It ends at
    /// the first destination it reaches, so it passes no other destination
    /// on the way.
    static func shortest(
        from node: GridPosition,
        heading: TrackDirection,
        to isDestination: (GridPosition) -> Bool,
        exits: (GridPosition, TrackDirection) -> [GridPosition]
    ) -> [GridPosition]? {
        shortest(from: State(node: node, heading: heading), isDestination: { isDestination($0.node) }) { state in
            exits(state.node, state.heading).compactMap { neighbor in
                guard let direction = TrackDirection(from: state.node, to: neighbor), direction != state.heading.opposite else { return nil }
                return (State(node: neighbor, heading: direction), TrainPosition.linkLength)
            }
        }?.map(\.node)
    }

    /// The shortest route from `start` to a state `isDestination` accepts,
    /// as the states after `start` in order; `[]` when `start` is one, and
    /// `nil` when none can be reached.
    ///
    /// `next` lists the states a state leads to, in the order that breaks
    /// ties, each with the length of the step (always positive). The result
    /// is defined by the rules alone, not by how the search runs:
    ///
    /// - it has the least total length;
    /// - among routes of that length, it is the one whose choices come first
    ///   in `next`'s order, compared step by step from the start (so on the
    ///   grid, where every step is one link, it is the route with the fewest
    ///   links whose exit directions come first north, east, south, west);
    /// - it ends at the first destination it reaches.
    ///
    /// Three passes, each over the states no further from `start` than the
    /// nearest destination: a search in order of distance (Dijkstra) that
    /// stops once that distance is passed; a pass back over those states,
    /// in reverse order, that marks which lead to a destination by steps
    /// that keep to the shortest distance; and a walk from `start` that takes
    /// the first such step each time. Time O(n log n) and memory O(n) in the
    /// number of those states; nothing is kept between calls.
    static func shortest<Place: Hashable>(
        from start: Place,
        isDestination: (Place) -> Bool,
        next: (Place) -> [(Place, Int64)]
    ) -> [Place]? {
        var distance: [Place: Int64] = [start: 0]
        var steps: [Place: [(Place, Int64)]] = [:]
        var settled: [Place] = []
        var done: Set<Place> = []
        var queue = SearchQueue<Place>()
        queue.push(start, at: 0)
        var bound: Int64?
        while let (place, reached) = queue.pop() {
            if let bound, reached > bound { break }
            guard reached == distance[place], done.insert(place).inserted else { continue }
            settled.append(place)
            if isDestination(place) {
                bound = bound ?? reached
                continue
            }
            if let bound, reached >= bound { continue }
            let following = next(place)
            steps[place] = following
            for (neighbor, length) in following {
                let through = reached + length
                if through < distance[neighbor] ?? .max {
                    distance[neighbor] = through
                    queue.push(neighbor, at: through)
                }
            }
        }
        guard let bound else { return nil }

        // Which settled places lead to a destination at the bound by steps
        // that keep to the shortest distance. Later places come first, so
        // every step's target is known before its source.
        var leads: Set<Place> = []
        for place in settled.reversed() {
            let reached = distance[place]!
            if isDestination(place) {
                if reached == bound { leads.insert(place) }
            } else if steps[place, default: []].contains(where: { leads.contains($0.0) && distance[$0.0] == reached + $0.1 }) {
                leads.insert(place)
            }
        }

        var route: [Place] = []
        var place = start
        while !isDestination(place) {
            let reached = distance[place]!
            guard let step = steps[place, default: []].first(where: { leads.contains($0.0) && distance[$0.0] == reached + $0.1 }) else {
                preconditionFailure("the walk keeps to places that lead to a destination")
            }
            route.append(step.0)
            place = step.0
        }
        return route
    }
}

/// A priority queue of places by distance, ties first in, first out, so the
/// search order is the same on every run. A binary heap.
private struct SearchQueue<Place> {
    private var heap: [(place: Place, distance: Int64, order: Int)] = []
    private var pushed = 0

    mutating func push(_ place: Place, at distance: Int64) {
        heap.append((place, distance, pushed))
        pushed += 1
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.precedes(heap[child], heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Place, Int64)? {
        guard let top = heap.first else { return nil }
        let last = heap.removeLast()
        if !heap.isEmpty {
            heap[0] = last
            var parent = 0
            while true {
                let left = 2 * parent + 1
                let right = left + 1
                var smallest = parent
                if left < heap.count, Self.precedes(heap[left], heap[smallest]) { smallest = left }
                if right < heap.count, Self.precedes(heap[right], heap[smallest]) { smallest = right }
                guard smallest != parent else { break }
                heap.swapAt(parent, smallest)
                parent = smallest
            }
        }
        return (top.place, top.distance)
    }

    private static func precedes(_ a: (place: Place, distance: Int64, order: Int), _ b: (place: Place, distance: Int64, order: Int)) -> Bool {
        (a.distance, a.order) < (b.distance, b.order)
    }
}
