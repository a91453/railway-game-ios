/// How a placed train moves: its rate and the explicit path ahead of it.
///
/// A train never chooses a way itself. Each basic step (one game minute) it
/// travels up to ``rate`` units: first to the end of the link it is on, then
/// into the links named by ``continuation``, one after another. It stops at a
/// node when the continuation is used up or the next named link cannot be
/// entered, and the distance it could not use is dropped, not saved up.
///
/// Only ``GameWorld`` changes a train's movement, through
/// ``GameWorld/setTrainMovementRate(_:to:)``,
/// ``GameWorld/setTrainContinuation(_:to:)``, ``GameWorld/advance(ticks:)``,
/// and ``GameWorld/reverseTrain(_:)`` and ``GameWorld/unplaceTrain(_:)``,
/// which clear the continuation (unplacing also resets the rate).
public struct TrainMovement: Hashable, Sendable {
    /// Logical units (``TrainPosition/linkLength`` per link) the train may
    /// travel in each basic step, that is per game minute. Never negative;
    /// 0 keeps the train where it is without discarding its continuation.
    ///
    /// Named apart from ``GameSpeed``: the game speed decides how many basic
    /// steps a tick runs, the rate how far a train goes in one of them.
    public internal(set) var rate: Int64

    /// The nodes the train enters, in order, after the node it is at or the
    /// end of the link it is on. That node itself is never listed.
    ///
    /// Entries before ``cursor`` have been entered already and are kept only
    /// so that advancing the cursor needs no copying; their track may be gone.
    public internal(set) var continuation: [GridPosition]

    /// How many ``continuation`` entries the train has entered: it set off on
    /// the link toward each of the first `cursor` nodes. Reaching a node does
    /// not advance the cursor; starting along the next link does.
    ///
    /// Once every entry has been entered, the continuation is spent and is
    /// stored as empty with cursor 0, so `cursor < continuation.count` unless
    /// both are empty.
    public internal(set) var cursor: Int

    /// No rate and no continuation: every unplaced train, and every newly
    /// placed one.
    public static let idle = TrainMovement(rate: 0, continuation: [], cursor: 0)

    /// The continuation entries not yet entered, in order.
    public var remainingContinuation: ArraySlice<GridPosition> {
        continuation[cursor...]
    }

    init(rate: Int64, continuation: [GridPosition], cursor: Int) {
        self.rate = rate
        self.continuation = continuation
        self.cursor = cursor
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
        var budget = distance
        var cursor = cursor
        var (node, heading) = start.ahead

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
    /// non-negative rate, a cursor inside a non-spent continuation (or both
    /// empty), and a continuation whose consecutive nodes are neighbours with
    /// no node returning to the one two before it.
    var isWellFormed: Bool {
        guard rate >= 0 else { return false }
        guard continuation.isEmpty ? cursor == 0 : (0..<continuation.count).contains(cursor) else { return false }
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
    func fits(_ position: TrainPosition?) -> Bool {
        guard let position else { return self == .idle }
        guard !continuation.isEmpty else { return true }
        let (node, heading) = position.ahead
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
        case rate, continuation, cursor
    }

    /// Decodes `{"rate", "continuation", "cursor"}`, rejecting values that are
    /// not well formed (see ``isWellFormed``) rather than repairing them.
    /// Whether the movement fits the train's position is checked by
    /// ``Train``'s decoder, and that the nodes lie on the map by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rate: try container.decode(Int64.self, forKey: .rate),
            continuation: try container.decode([GridPosition].self, forKey: .continuation),
            cursor: try container.decode(Int.self, forKey: .cursor)
        )
        guard isWellFormed else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A train movement needs a non-negative rate, a cursor inside an unspent continuation, and a continuation of neighbouring nodes without U-turns."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rate, forKey: .rate)
        try container.encode(continuation, forKey: .continuation)
        try container.encode(cursor, forKey: .cursor)
    }
}
