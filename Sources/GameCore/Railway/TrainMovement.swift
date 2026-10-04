/// How a placed train moves: its rate and the explicit path ahead of it.
///
/// A train never chooses a way itself. Each game minute it travels up to
/// ``rate`` units, a share of it each basic step (one game second since
/// Stage W2a; see ``distance(at:fromSecond:toSecond:)``): first to the end
/// of the edge it is on, then along the edges named by ``edges``, one after
/// another, of any length (Stage S3). It stops at the end of an edge when
/// the path is used up or the next named edge cannot be entered, and the
/// distance it could not use is dropped, not saved up. Since Stage S5 a path
/// may end part of the way along its last edge (``end``), as at a platform
/// in the middle of an edge. (Until Stage F3c a train on the grid followed a
/// continuation of tiles instead; it went with the grid, ARCHITECTURE
/// decision 51.)
///
/// Only ``GameWorld`` changes a train's movement, through
/// ``GameWorld/setTrainMovementRate(_:to:)``,
/// ``GameWorld/setTrainContinuation(_:along:stoppingAt:)``,
/// ``GameWorld/advance(ticks:)``, and ``GameWorld/reverseTrain(_:)`` and
/// ``GameWorld/unplaceTrain(_:)``, which clear the path (unplacing also
/// resets the rate).
public struct TrainMovement: Hashable, Sendable {
    /// World units (``WorldCoordinate/unitsPerMetre`` to a metre) the
    /// train may travel per game minute, shared out over the minute's seconds
    /// (see ``distance(at:fromSecond:toSecond:)``). Never negative; 0 keeps
    /// the train where it is without discarding its path.
    ///
    /// Named apart from ``GameSpeed``: the game speed decides how many basic
    /// steps a tick runs, the rate how far a train goes in them.
    public internal(set) var rate: Int64

    /// The edges the train enters, in order, after the edge it is on (Stage
    /// S3). Entries before ``cursor`` have been entered already and are kept
    /// only so that advancing the cursor needs no copying; their track may be
    /// gone.
    public internal(set) var edges: [TrackEdgeID]

    /// How many ``edges`` the train has entered: it set off along each of
    /// the first `cursor` edges. Reaching the end of an edge does not advance
    /// the cursor; starting along the next edge does.
    ///
    /// Once every entry has been entered, the list is spent and is stored as
    /// empty with cursor 0, so the cursor is below the count of the list
    /// unless it is empty.
    public internal(set) var cursor: Int

    /// How far along the last edge of its path the train stops (Stage S5),
    /// measured from where it starts along that edge the way the train
    /// travels it, or `nil` to run to the end of that edge (as every path did
    /// before Stage S5). The last edge is the last of ``edges``, or, once they
    /// are spent (or when there are none), the edge the train is on.
    ///
    /// With ``edges`` it is the train's one path (see ``TrainPath``): a
    /// service sets it to stop a train at a platform in the middle of an
    /// edge. It stays once the train is there, so a train whose path is
    /// spent stands where the path ends. When set it is below the last
    /// edge's length (the end of the edge is `nil`), above 0 while edges
    /// are left (0 would be the end of the edge before), and not behind
    /// the train once none are.
    public internal(set) var end: Int64?

    /// No rate and no path: every unplaced train, and every newly placed
    /// one.
    public static let idle = TrainMovement(rate: 0, cursor: 0)

    /// The edges not yet entered, in order.
    public var remainingEdges: ArraySlice<TrackEdgeID> {
        edges.isEmpty ? [] : edges[cursor...]
    }

    /// Whether any edge is still to be entered.
    public var hasRemainingPath: Bool {
        !remainingEdges.isEmpty
    }

    init(rate: Int64, cursor: Int, edges: [TrackEdgeID] = [], end: Int64? = nil) {
        self.rate = rate
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
    /// `offset` along `traversal` (an edge `length` long), along the rest of
    /// its edge and then `edges` from entry `cursor` on, and the cursor it
    /// ends with. Pure: it reads the network only through `enter` and
    /// changes nothing.
    ///
    /// - Reaching the end of an edge exactly stops there (offset = length),
    ///   facing on, and never looks at the next entry.
    /// - With distance left at the end of an edge, the train enters the next
    ///   entry only if `enter` gives a traversal of it from there (the edge
    ///   exists, ends at that node and joins the edge the train arrived
    ///   along) and its length. Otherwise it stops at the end of its edge,
    ///   the entry stays unconsumed, and the rest of `distance` is unused.
    ///   It never picks a way.
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

    /// Whether the stored fields have a shape any world could hold: a
    /// non-negative rate, a cursor inside the edges if they are not spent (or
    /// 0 when there are none), edges numbered from 1 with no edge straight
    /// after itself (which would turn straight back), and an ``end``
    /// (Stage S5) of 0 or more, above 0 while edges are left.
    var isWellFormed: Bool {
        guard rate >= 0 else { return false }
        if let end {
            guard end >= (edges.isEmpty ? 0 : 1) else { return false }
        }
        guard edges.isEmpty ? cursor == 0 : edges.indices.contains(cursor) else { return false }
        guard edges.allSatisfy({ ($0.networkNumber ?? 0) >= 1 }) else { return false }
        for index in edges.indices.dropFirst() where edges[index] == edges[index - 1] {
            return false
        }
        return true
    }

    /// Whether this movement fits a train at `position`, judged without a
    /// map, so that a path whose future track was removed after it was set
    /// still fits.
    ///
    /// An unplaced train is idle. Otherwise, with entries entered, the train
    /// is on the last entered edge, and the first edge left is not the one it
    /// is on. With no edges left, a path that ends part of the way along the
    /// train's edge does not end behind it (Stage S5).
    func fits(_ position: TrainPosition?) -> Bool {
        guard let position else { return self == .idle }
        switch position {
        case .onEdge(let traversal, let offset):
            guard !edges.isEmpty else { return end.map { offset <= $0 } ?? true }
            if cursor >= 1 {
                guard edges[cursor - 1] == traversal.edge else { return false }
            }
            return edges[cursor] != traversal.edge
        }
    }
}

// MARK: - Codable

extension TrainMovement: Codable {
    private enum CodingKeys: String, CodingKey {
        case rate, continuation, cursor, edges, end
    }

    /// Decodes `{"rate", "cursor"}`, plus `"edges"` (edge
    /// numbers, Stage S3); without them, which is also how movements saved
    /// before Stage S3 read, there are none, and an explicit `null` is
    /// rejected. Since Stage S5 also `"end"` for a path that ends part of
    /// the way along its last edge; without it, which is also how movements
    /// saved before read, the path runs to the end of that edge, and an
    /// explicit `null` is rejected. Rejects values that are not well formed
    /// (see ``isWellFormed``) rather than repairing them. Whether the
    /// movement fits the train's position is checked by ``Train``'s decoder,
    /// and that the edges were built, and `"end"` lies within the last one,
    /// by the ``GameWorld`` decoder.
    ///
    /// `"continuation"` was the grid's path. Saves before version 6 write it,
    /// always `[]` for a train on the track network (ARCHITECTURE decision
    /// 51 kept the key); since then it is not written (Stage F3d), and an
    /// empty one is still read. A continuation of tiles, which only a save
    /// made by hand could hold, is refused with that reason: the grid went
    /// in Stage F3c.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.continuation), try !container.decode([LegacyGrid.Cell].self, forKey: .continuation).isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: .continuation, in: container,
                debugDescription: "A path on the grid (\"continuation\") is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold one."
            )
        }
        self.init(
            rate: try container.decode(Int64.self, forKey: .rate),
            cursor: try container.decode(Int.self, forKey: .cursor),
            edges: container.contains(.edges) ? try container.decode([Int].self, forKey: .edges).map(TrackEdgeID.edge) : [],
            end: container.contains(.end) ? try container.decode(Int64.self, forKey: .end) : nil
        )
        guard isWellFormed else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A train movement needs a non-negative rate, a cursor inside its edges unless they are spent, edges from 1 without an edge straight after itself, and an end that is not negative, and above 0 while edges are left."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rate, forKey: .rate)
        try container.encode(cursor, forKey: .cursor)
        if !edges.isEmpty {
            try container.encode(edges.map { $0.networkNumber }, forKey: .edges)
        }
        try container.encodeIfPresent(end, forKey: .end)
    }
}
