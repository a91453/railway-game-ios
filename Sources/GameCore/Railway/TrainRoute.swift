// Route finding on the railway graph: the shortest route a train can take to
// a node, found by searching the network on demand. A train cannot turn
// straight back along an edge, so the search visits traversals (the edge it
// arrived along, and which way), and never stores a graph: what follows each
// comes from the same transitions query that movement uses.

extension GameWorld {
    /// The shortest route that takes a train at `start` to node `node` of
    /// the track network, as the traversals it would travel after the edge
    /// it is on, or `nil` if there is none (Stage S3). It starts at the end
    /// of the edge the train is on and ends where it first reaches `node`:
    /// the least total length, and among routes of that length the one
    /// whose edges come first in ascending order at each node, compared step
    /// by step from the start. It never turns straight back along an edge;
    /// it may loop.
    ///
    /// An empty list means the train is heading along its edge for `node`.
    /// The result can be passed to ``setTrainContinuation(_:along:stoppingAt:)``
    /// unchanged on this world. `nil` when `start` is not on this world's
    /// track, `node` is not one of its nodes, or no route exists. Pure: reads
    /// only topology and lengths, and explores only track no further than the
    /// route.
    public func route(from start: TrainPosition, to node: TrackNodeID) -> [TrackTraversal]? {
        guard isOnTrack(start), network.node(node) != nil else { return nil }
        switch start {
        case .onEdge(let traversal, _):
            return TrainRoute.shortest(from: traversal, isDestination: { network.edge($0.edge)?.end(of: $0.direction) == node }) { arrival in
                transitions(after: arrival).map { ($0, network.edge($0.edge)!.length) }
            }
        }
    }
}

/// The route-finding kernel, separate from ``GameWorld`` so that it sees the
/// network only through the neighbour query it is given (ARCHITECTURE
/// decision 29).
enum TrainRoute {
    /// The shortest route from `start` to a state `isDestination` accepts,
    /// as the states after `start` in order; `[]` when `start` is one, and
    /// `nil` when none can be reached.
    ///
    /// `next` lists the states a state leads to, in the order that breaks
    /// ties, each with the length of the step: never negative, and 0 only
    /// for a step from `start` (Stage S5: a train already where it stops for
    /// a station, or at the end of its edge). The result is defined by the
    /// rules alone, not by how the search runs:
    ///
    /// - it has the least total length;
    /// - among routes of that length, it is the one whose choices come first
    ///   in `next`'s order, compared step by step from the start;
    /// - it ends at the first destination it reaches.
    ///
    /// Three passes, each over the states no further from `start` than the
    /// nearest destination: a search in order of distance (Dijkstra) that
    /// stops once that distance is passed; a pass back over those states,
    /// in reverse order, that marks which lead to a destination by steps
    /// that keep to the shortest distance; and a walk from `start` that takes
    /// the first such step each time. `start` is settled first, so a step
    /// of 0 from it still leads to a state settled later, and the pass back
    /// sees every step's target before its source. Time O(n log n) and
    /// memory O(n) in the number of those states; nothing is kept between
    /// calls.
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
