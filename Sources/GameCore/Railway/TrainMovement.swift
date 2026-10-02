/// How a placed train moves: its rate and the explicit path ahead of it.
///
/// A train never chooses a way itself. Each game minute it travels up to
/// ``rate`` units, a share of it each basic step (one game second since
/// Stage W2a; see ``distance(at:fromSecond:toSecond:)``): first to the end
/// of the link it is on, then into the links named by ``continuation``, one
/// after another. It stops at a node when the continuation is used up or
/// the next named link cannot be entered, and the distance it could not use
/// is dropped, not saved up.
///
/// On the track network (Stage S3) the path ahead is ``edges`` instead of
/// ``continuation``: the edges the train enters in order, of any length.
/// A train uses one or the other, never both, and ``cursor`` counts the
/// entries entered of whichever it uses. Since Stage S5 a path on the
/// network may end part of the way along its last edge (``end``), as at a
/// platform in the middle of an edge.
///
/// Only ``GameWorld`` changes a train's movement, through
/// ``GameWorld/setTrainMovementRate(_:to:)``,
/// ``GameWorld/setTrainContinuation(_:to:)``,
/// ``GameWorld/setTrainContinuation(_:along:)``, ``GameWorld/advance(ticks:)``,
/// and ``GameWorld/reverseTrain(_:)`` and ``GameWorld/unplaceTrain(_:)``,
/// which clear the continuation (unplacing also resets the rate).
public struct TrainMovement: Hashable, Sendable {
    /// Logical units (``TrainPosition/linkLength`` per link) the train may
    /// travel per game minute, shared out over the minute's seconds (see
    /// ``distance(at:fromSecond:toSecond:)``). Never negative; 0 keeps the
    /// train where it is without discarding its continuation.
    ///
    /// Named apart from ``GameSpeed``: the game speed decides how many basic
    /// steps a tick runs, the rate how far a train goes in them.
    public internal(set) var rate: Int64

    /// The nodes the train enters, in order, after the node it is at or the
    /// end of the link it is on. That node itself is never listed.
    ///
    /// Entries before ``cursor`` have been entered already and are kept only
    /// so that advancing the cursor needs no copying; their track may be gone.
    public internal(set) var continuation: [GridPosition]

    /// On the track network (Stage S3): the edges the train enters, in
    /// order, after the edge it is on. Always ``TrackEdgeID/edge(_:)``s,
    /// and empty for a train on the grid. Entries before ``cursor`` have
    /// been entered already, as for ``continuation``.
    public internal(set) var edges: [TrackEdgeID]

    /// How many ``continuation`` (or, on the network, ``edges``) entries the
    /// train has entered: it set off on the link toward each of the first
    /// `cursor` nodes, or along each of the first `cursor` edges. Reaching a
    /// node does not advance the cursor; starting along the next link or
    /// edge does.
    ///
    /// Once every entry has been entered, the list is spent and is stored as
    /// empty with cursor 0, so the cursor is below the count of the list in
    /// use unless both lists are empty.
    public internal(set) var cursor: Int

    /// On the track network (Stage S5): how far along the last edge of its
    /// path the train stops, measured from where it starts along that edge
    /// the way the train travels it, or `nil` to run to the end of that
    /// edge (as every path did before Stage S5). The last edge is the last
    /// of ``edges``, or, once they are spent (or when there are none), the
    /// edge the train is on. Always `nil` on the grid, whose trains stop at
    /// nodes.
    ///
    /// With ``edges`` it is the train's one path (see ``TrainPath``): a
    /// service sets it to stop a train at a platform in the middle of an
    /// edge. It stays once the train is there, so a train whose path is
    /// spent stands where the path ends. When set it is below the last
    /// edge's length (the end of the edge is `nil`), above 0 while edges
    /// are left (0 would be the end of the edge before), and not behind
    /// the train once none are.
    public internal(set) var end: Int64?

    /// No rate and no continuation: every unplaced train, and every newly
    /// placed one.
    public static let idle = TrainMovement(rate: 0, continuation: [], cursor: 0)

    /// The continuation entries not yet entered, in order. Empty on the
    /// track network.
    public var remainingContinuation: ArraySlice<GridPosition> {
        continuation.isEmpty ? [] : continuation[cursor...]
    }

    /// The network edges not yet entered, in order. Empty on the grid.
    public var remainingEdges: ArraySlice<TrackEdgeID> {
        edges.isEmpty ? [] : edges[cursor...]
    }

    /// Whether any entry of either list is still to be entered.
    public var hasRemainingPath: Bool {
        !remainingContinuation.isEmpty || !remainingEdges.isEmpty
    }

    init(rate: Int64, continuation: [GridPosition], cursor: Int, edges: [TrackEdgeID] = [], end: Int64? = nil) {
        self.rate = rate
        self.continuation = continuation
        self.edges = edges
        self.cursor = cursor
        self.end = end
    }

    /// The units a train with `rate` units a minute may travel from second
    /// `start` to second `end` of a minute (Stage W2a): `⌊rate·end/60⌋ −
    /// ⌊rate·start/60⌋`. The seconds of a minute share the rate out with
    /// the remainder at the end of each, so they add up to exactly `rate`
    /// over the whole minute, and a span takes what its seconds would one
    /// at a time.
    ///
    /// - Precondition: `rate >= 0` and `0 <= start <= end <= 60`.
    public static func distance(at rate: Int64, fromSecond start: Int64, toSecond end: Int64) -> Int64 {
        precondition(rate >= 0 && 0 <= start && start <= end && end <= GameTime.secondsPerMinute, "distance(at:fromSecond:toSecond:) needs a rate of 0 or more and seconds within a minute")
        // ⌊rate·s/60⌋ = q·s + ⌊r·s/60⌋ for rate = 60q + r: no overflow.
        func covered(by second: Int64) -> Int64 {
            rate / GameTime.secondsPerMinute * second + rate % GameTime.secondsPerMinute * second / GameTime.secondsPerMinute
        }
        return covered(by: end) - covered(by: start)
    }
}

// MARK: - Kernel

extension TrainMovement {
    /// Where a train ends up after travelling up to `distance` units from
    /// `start`, along the rest of its link and then `continuation` from
    /// entry `cursor` on, and the cursor it ends with. Pure: it reads the
    /// network only through `mayPass` and changes nothing.
    ///
    /// - A partial link is `onLink`; reaching a node exactly is `atNode`,
    ///   facing the way the train arrived. Arriving exactly never looks at,
    ///   enters or consumes the next entry, whether or not it is passable.
    /// - At a node with distance left, the train enters the next entry only if
    ///   it does not lead straight back (the opposite of the heading) and
    ///   `mayPass` accepts it (the link exists and the piece lets a train
    ///   facing that way go on to it). Otherwise it stops there, the entry
    ///   stays unconsumed, and the rest of `distance` is unused.
    /// - Without further entries it stops at the node. It never picks a way.
    ///
    /// Terminates for any `distance`: every loop pass enters one entry, and
    /// there are finitely many. Remaining distance is compared with the
    /// distance to the next node before subtracting, so no sum can overflow.
    ///
    /// - Precondition: `start` is well formed, `distance >= 0`, and
    ///   `0 <= cursor <= continuation.count`.
    static func travel(
        from start: TrainPosition,
        distance: Int64,
        continuation: [GridPosition],
        cursor: Int,
        mayPass: (GridPosition, TrackDirection, GridPosition) -> Bool
    ) -> (position: TrainPosition, cursor: Int) {
        precondition(distance >= 0, "travel(from:distance:...) requires a non-negative distance")
        guard var (node, heading) = start.ahead else { preconditionFailure("travel(from:distance:...) is for positions on the grid") }
        var budget = distance
        var cursor = cursor

        if case .onLink(let from, let to, let offset) = start {
            let toEnd = TrainPosition.linkLength - offset
            guard budget >= toEnd else {
                return (.onLink(from: from, to: to, offset: offset + budget), cursor)
            }
            budget -= toEnd
        }

        while budget > 0, cursor < continuation.count {
            let next = continuation[cursor]
            guard let direction = TrackDirection(from: node, to: next),
                  direction != heading.opposite,
                  mayPass(node, heading, next)
            else { break }
            cursor += 1
            guard budget >= TrainPosition.linkLength else {
                return (.onLink(from: node, to: next, offset: budget), cursor)
            }
            budget -= TrainPosition.linkLength
            (node, heading) = (next, direction)
        }
        return (.atNode(node, heading: heading), cursor)
    }

    /// Where a train on the track network ends up after travelling up to
    /// `distance` units from `start`, along the rest of its edge and then
    /// `edges` from entry `cursor` on, and the cursor it ends with: the same
    /// rules as ``travel(from:distance:continuation:cursor:mayPass:)``,
    /// with each edge as long as it is.
    ///
    /// - Reaching the end of an edge exactly stops there (offset = length),
    ///   facing on, and never looks at the next entry.
    /// - With distance left at the end of an edge, the train enters the next
    ///   entry only if `enter` gives a traversal of it from there (the edge
    ///   exists, ends at that node and joins the edge the train arrived
    ///   along) and its length. Otherwise it stops at the end of its edge,
    ///   the entry stays unconsumed, and the rest of `distance` is unused.
    /// - On the last edge of the path (no entry left), a path that ends at
    ///   `end` (Stage S5) stops the train there; the rest of `distance` is
    ///   unused, and a train already there does not move.
    ///
    /// Terminates for any `distance`: every loop pass enters one entry.
    /// Distance left is compared with the distance to the end of the edge
    /// (or to `end`) before subtracting, so no sum can overflow. The
    /// geometry is never read: only lengths.
    ///
    /// - Precondition: `distance >= 0`, `0 <= offset <= length`,
    ///   `0 <= cursor <= edges.count`, and when `end` is set and no entry is
    ///   left, `offset <= end`.
    static func travel(
        along traversal: TrackTraversal,
        offset: Int64,
        length: Int64,
        distance: Int64,
        edges: [TrackEdgeID],
        cursor: Int,
        end: Int64? = nil,
        enter: (TrackTraversal, TrackEdgeID) -> (traversal: TrackTraversal, length: Int64)?
    ) -> (position: TrainPosition, cursor: Int) {
        precondition(distance >= 0, "travel(along:...) requires a non-negative distance")
        var budget = distance
        var cursor = cursor
        var (current, offset, length) = (traversal, offset, length)
        while true {
            if cursor == edges.count, let end {
                // The last edge of the path, which ends part of the way along.
                precondition(offset <= end, "travel(along:...) requires the train not to be past the end of its path")
                return (.onEdge(current, offset: budget >= end - offset ? end : offset + budget), cursor)
            }
            let toEnd = length - offset
            guard budget > toEnd else {
                return (.onEdge(current, offset: offset + budget), cursor)
            }
            budget -= toEnd
            guard cursor < edges.count, let next = enter(current, edges[cursor]) else {
                return (.onEdge(current, offset: length), cursor)
            }
            cursor += 1
            (current, offset, length) = (next.traversal, 0, next.length)
        }
    }

    /// Whether a train at `node` facing `heading` could follow `nodes` in
    /// order: each is the next tile north, east, south or west of the one
    /// before, none leads straight back the way the train is facing (no
    /// immediate U-turn, including at `node` itself), and `mayPass` accepts
    /// every step from the node and heading before it. Loops and revisits
    /// are allowed.
    static func isPath(
        _ nodes: some Sequence<GridPosition>,
        from node: GridPosition,
        heading: TrackDirection,
        mayPass: (GridPosition, TrackDirection, GridPosition) -> Bool
    ) -> Bool {
        var (node, heading) = (node, heading)
        for next in nodes {
            guard let direction = TrackDirection(from: node, to: next),
                  direction != heading.opposite,
                  mayPass(node, heading, next)
            else { return false }
            (node, heading) = (next, direction)
        }
        return true
    }

    /// Whether the stored fields have a shape any world could hold: a
    /// non-negative rate, at most one of the two lists in use, a cursor
    /// inside the one in use if it is not spent (or 0 when both are empty),
    /// a continuation whose consecutive nodes are neighbours with no node
    /// returning to the one two before it, and network edges numbered from 1
    /// with no edge straight after itself (which would turn straight back).
    /// An ``end`` (Stage S5) is only for the network, so never with a grid
    /// continuation, and is 0 or more, above 0 while edges are left.
    var isWellFormed: Bool {
        guard rate >= 0 else { return false }
        guard continuation.isEmpty || edges.isEmpty else { return false }
        if let end {
            guard continuation.isEmpty, end >= (edges.isEmpty ? 0 : 1) else { return false }
        }
        let count = max(continuation.count, edges.count)
        guard count == 0 ? cursor == 0 : (0..<count).contains(cursor) else { return false }
        guard edges.allSatisfy({ ($0.networkNumber ?? 0) >= 1 }) else { return false }
        for index in edges.indices.dropFirst() where edges[index] == edges[index - 1] {
            return false
        }
        for index in continuation.indices.dropFirst() {
            guard TrackDirection(from: continuation[index - 1], to: continuation[index]) != nil else { return false }
        }
        for index in continuation.indices.dropFirst(2) {
            guard continuation[index] != continuation[index - 2] else { return false }
        }
        return true
    }

    /// Whether this movement fits a train at `position`, judged without a
    /// map, so that a continuation whose future track was removed after it
    /// was set still fits.
    ///
    /// An unplaced train is idle. Otherwise, with entries entered, the train
    /// is at or heading for the last entered node, and after two it faces the
    /// way the last entered link runs. The entries left must be a path from
    /// there without an immediate U-turn.
    ///
    /// On the track network the same holds for ``edges``: with entries
    /// entered, the train is on the last entered edge, and the first edge
    /// left is not the one it is on. A train on the network has no grid
    /// continuation, and one on the grid no network edges and no ``end``.
    /// With no edges left, a path that ends part of the way along the
    /// train's edge does not end behind it (Stage S5).
    func fits(_ position: TrainPosition?) -> Bool {
        guard let position else { return self == .idle }
        if case .onEdge(let traversal, let offset) = position {
            guard continuation.isEmpty else { return false }
            guard !edges.isEmpty else { return end.map { offset <= $0 } ?? true }
            if cursor >= 1 {
                guard edges[cursor - 1] == traversal.edge else { return false }
            }
            return edges[cursor] != traversal.edge
        }
        guard edges.isEmpty, end == nil else { return false }
        guard !continuation.isEmpty, let (node, heading) = position.ahead else { return true }
        if cursor >= 1 {
            guard node == continuation[cursor - 1] else { return false }
        }
        if cursor >= 2 {
            guard TrackDirection(from: continuation[cursor - 2], to: continuation[cursor - 1]) == heading else { return false }
        }
        return Self.isPath(remainingContinuation, from: node, heading: heading) { _, _, _ in true }
    }
}

// MARK: - Codable

extension TrainMovement: Codable {
    private enum CodingKeys: String, CodingKey {
        case rate, continuation, cursor, edges, end
    }

    /// Decodes `{"rate", "continuation", "cursor"}`, plus `"edges"` (network
    /// edge numbers) for a train on the track network; without it, which is
    /// also how movements saved before Stage S3 read, there are none, and
    /// an explicit `null` is rejected. Since Stage S5 also `"end"` for a
    /// path on the network that ends part of the way along its last edge;
    /// without it, which is also how movements saved before read, the path
    /// runs to the end of that edge, and an explicit `null` is rejected.
    /// Rejects values that are not well formed (see ``isWellFormed``)
    /// rather than repairing them. Whether the movement fits the train's
    /// position is checked by ``Train``'s decoder, and that the nodes lie on
    /// the map (or the edges were built, and `"end"` lies within the last
    /// one) by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rate: try container.decode(Int64.self, forKey: .rate),
            continuation: try container.decode([GridPosition].self, forKey: .continuation),
            cursor: try container.decode(Int.self, forKey: .cursor),
            edges: container.contains(.edges) ? try container.decode([Int].self, forKey: .edges).map(TrackEdgeID.edge) : [],
            end: container.contains(.end) ? try container.decode(Int64.self, forKey: .end) : nil
        )
        guard isWellFormed else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A train movement needs a non-negative rate, one continuation at most with a cursor inside it unless spent, neighbouring nodes without U-turns, network edges from 1 without an edge straight after itself, and an end only on the network, not negative, and above 0 while edges are left."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rate, forKey: .rate)
        try container.encode(continuation, forKey: .continuation)
        try container.encode(cursor, forKey: .cursor)
        if !edges.isEmpty {
            try container.encode(edges.map { $0.networkNumber }, forKey: .edges)
        }
        try container.encodeIfPresent(end, forKey: .end)
    }
}
