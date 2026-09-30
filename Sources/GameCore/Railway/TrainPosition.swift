/// Where a placed train is on the track network.
///
/// A train that is not on the track is *unplaced*: its ``Train/position`` is
/// `nil`. There is no unplaced case here, so there is only one way to say it.
///
/// Distances are logical, not map geometry: every link between the centres of
/// two joined track tiles is ``linkLength`` units long, straight or not. A
/// unit is an abstract fraction of the distance between tile centres, not
/// metres, points or pixels, and it implies no speed.
///
/// Every place on the track has exactly one representation:
///
/// - At the centre of a track tile the train is ``atNode(_:heading:)``, never
///   ``onLink(from:to:offset:)`` with an offset of 0 or ``linkLength``.
/// - Strictly between two tile centres it is ``onLink(from:to:offset:)``:
///   `from` and `to` are orthogonal neighbours, and the train is `offset`
///   units from `from`, facing `to`, with `0 < offset < linkLength`. Its
///   direction of travel is the direction from `from` to `to`; it is not
///   stored separately, so it cannot disagree with the endpoints.
///
/// On the continuous track network (Phase 4.5 Stage S3) a train is always
/// on an edge: ``onEdge(_:offset:)``, travelling the edge one way, `offset`
/// units from where that traversal starts, with `0 <= offset <=` the edge's
/// length. Edges are any length. At a node the train is at the end of the
/// edge it arrived along (offset = length), and a train with a body (see
/// ``Train/length``) is always written that way; only a train of one car
/// may stand at offset 0, facing into an edge from its start (as one does
/// after turning round at a dead end). Every other place on an edge has one
/// representation.
///
/// Like `TrackConnections(rawValue:)`, the enum accepts any values. Validity
/// is checked where a position enters a world: ``GameWorld/placeTrain(_:at:)``
/// and decoding, which also require it to lie on that world's track.
public enum TrainPosition: Hashable, Sendable {
    /// At the centre of the track tile at the given position, facing
    /// `heading`: the way it would leave the tile.
    ///
    /// The heading need not be an exit of the track piece or lead to more
    /// track: a train can face a dead end, an empty tile or the map edge.
    case atNode(GridPosition, heading: TrackDirection)

    /// Between the centres of two joined track tiles, `offset` units from
    /// `from` and facing `to`.
    case onLink(from: GridPosition, to: GridPosition, offset: Int64)

    /// On an edge of the track network (Stage S3), travelling it the way
    /// the traversal goes, `offset` units from where the traversal starts
    /// (the edge's `from` node going forward, its `to` node going
    /// backward). The edge is always ``TrackEdgeID/edge(_:)``.
    case onEdge(TrackTraversal, offset: Int64)

    /// The length of every link between two joined tile centres, in logical
    /// units. 1024 resolves positions finer than a thousandth of a tile and
    /// makes halves, quarters and eighths exact.
    public static let linkLength: Int64 = 1024
}

extension TrainPosition {
    /// Whether the position could lie on some map's track: link ends are
    /// orthogonal neighbours and the offset is strictly inside the link.
    /// Says nothing about any particular map.
    ///
    /// A position on the network needs a network edge and an offset of 0 or
    /// more; whether the offset is within the edge is up to the world.
    var isWellFormed: Bool {
        switch self {
        case .atNode:
            true
        case .onLink(let from, let to, let offset):
            TrackDirection(from: from, to: to) != nil && 0 < offset && offset < Self.linkLength
        case .onEdge(let traversal, let offset):
            (traversal.edge.networkNumber ?? 0) >= 1 && offset >= 0
        }
    }

    /// Whether the position is on the grid (a node or a link) rather than
    /// on the track network.
    var isOnGrid: Bool {
        if case .onEdge = self { false } else { true }
    }

    /// The same place, facing the other way: a node turns its heading around,
    /// and a link swaps its ends and measures the offset from the other end.
    /// Reversing twice gives back the original position.
    ///
    /// Only for well-formed positions on the grid: turning round on the
    /// network needs the edge's length (see `GameWorld.reversedOnNetwork`).
    var reversed: TrainPosition {
        switch self {
        case .atNode(let tile, let heading):
            .atNode(tile, heading: heading.opposite)
        case .onLink(let from, let to, let offset):
            .onLink(from: to, to: from, offset: Self.linkLength - offset)
        case .onEdge:
            preconditionFailure("reversed is for positions on the grid")
        }
    }

    /// The grid node the train stands on or is heading for, and the
    /// direction it faces there: the node's heading, or for a link its `to`
    /// end and the direction from `from` to `to`. Where it leaves next
    /// starts here. `nil` on the track network.
    ///
    /// Only for well-formed positions.
    var ahead: (node: GridPosition, heading: TrackDirection)? {
        switch self {
        case .atNode(let tile, let heading):
            return (tile, heading)
        case .onLink(let from, let to, _):
            guard let heading = TrackDirection(from: from, to: to) else {
                preconditionFailure("\(self) is not a well-formed position")
            }
            return (to, heading)
        case .onEdge:
            return nil
        }
    }

    /// Whether the train rests on the track at `tile`: the tile of a node, or
    /// either end of a link. Removing that track would leave the train on
    /// track that no longer exists.
    func isSupported(by tile: GridPosition) -> Bool {
        switch self {
        case .atNode(let node, _):
            node == tile
        case .onLink(let from, let to, _):
            from == tile || to == tile
        case .onEdge:
            false
        }
    }
}

// MARK: - Codable

extension TrainPosition: Codable {
    private enum CodingKeys: String, CodingKey {
        case atNode, onLink, onEdge
    }

    private enum NodeCodingKeys: String, CodingKey {
        case tile, heading
    }

    private enum LinkCodingKeys: String, CodingKey {
        case from, to, offset
    }

    private enum EdgeCodingKeys: String, CodingKey {
        case edge, direction, offset
    }

    /// Decodes `{"atNode": {"tile", "heading"}}`,
    /// `{"onLink": {"from", "to", "offset"}}` or, on the track network,
    /// `{"onEdge": {"edge", "direction", "offset"}}` (the edge's number,
    /// `"forward"` or `"backward"`), rejecting positions that are not well
    /// formed rather than repairing them: an offset of 0 or ``linkLength``
    /// is not read as the node at that end, and an edge below 1 or a
    /// negative offset is refused. Whether the position lies on track (and
    /// an edge offset within the edge) is checked by the ``GameWorld``
    /// decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let kind = container.allKeys.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A train position needs exactly one of \"atNode\", \"onLink\" and \"onEdge\"."
            ))
        }
        switch kind {
        case .atNode:
            let node = try container.nestedContainer(keyedBy: NodeCodingKeys.self, forKey: .atNode)
            self = try .atNode(
                node.decode(GridPosition.self, forKey: .tile),
                heading: node.decode(TrackDirection.self, forKey: .heading)
            )
        case .onLink:
            let link = try container.nestedContainer(keyedBy: LinkCodingKeys.self, forKey: .onLink)
            self = try .onLink(
                from: link.decode(GridPosition.self, forKey: .from),
                to: link.decode(GridPosition.self, forKey: .to),
                offset: link.decode(Int64.self, forKey: .offset)
            )
            guard isWellFormed else {
                throw DecodingError.dataCorruptedError(
                    forKey: .onLink, in: container,
                    debugDescription: "Link ends must be orthogonal neighbours and the offset must lie strictly between 0 and \(Self.linkLength)."
                )
            }
        case .onEdge:
            let edge = try container.nestedContainer(keyedBy: EdgeCodingKeys.self, forKey: .onEdge)
            self = try .onEdge(
                TrackTraversal(edge: .edge(edge.decode(Int.self, forKey: .edge)), direction: edge.decode(TrackEdgeDirection.self, forKey: .direction)),
                offset: edge.decode(Int64.self, forKey: .offset)
            )
            guard isWellFormed else {
                throw DecodingError.dataCorruptedError(
                    forKey: .onEdge, in: container,
                    debugDescription: "A position on the track network needs an edge from 1 and an offset of 0 or more."
                )
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .atNode(let tile, let heading):
            var node = container.nestedContainer(keyedBy: NodeCodingKeys.self, forKey: .atNode)
            try node.encode(tile, forKey: .tile)
            try node.encode(heading, forKey: .heading)
        case .onLink(let from, let to, let offset):
            var link = container.nestedContainer(keyedBy: LinkCodingKeys.self, forKey: .onLink)
            try link.encode(from, forKey: .from)
            try link.encode(to, forKey: .to)
            try link.encode(offset, forKey: .offset)
        case .onEdge(let traversal, let offset):
            var edge = container.nestedContainer(keyedBy: EdgeCodingKeys.self, forKey: .onEdge)
            try edge.encode(traversal.edge.networkNumber, forKey: .edge)
            try edge.encode(traversal.direction, forKey: .direction)
            try edge.encode(offset, forKey: .offset)
        }
    }
}
