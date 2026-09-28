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

    /// The length of every link between two joined tile centres, in logical
    /// units. 1024 resolves positions finer than a thousandth of a tile and
    /// makes halves, quarters and eighths exact.
    public static let linkLength: Int64 = 1024
}

extension TrainPosition {
    /// Whether the position could lie on some map's track: link ends are
    /// orthogonal neighbours and the offset is strictly inside the link.
    /// Says nothing about any particular map.
    var isWellFormed: Bool {
        switch self {
        case .atNode:
            true
        case .onLink(let from, let to, let offset):
            TrackDirection(from: from, to: to) != nil && 0 < offset && offset < Self.linkLength
        }
    }

    /// The same place, facing the other way: a node turns its heading around,
    /// and a link swaps its ends and measures the offset from the other end.
    /// Reversing twice gives back the original position.
    ///
    /// Only for well-formed positions.
    var reversed: TrainPosition {
        switch self {
        case .atNode(let tile, let heading):
            .atNode(tile, heading: heading.opposite)
        case .onLink(let from, let to, let offset):
            .onLink(from: to, to: from, offset: Self.linkLength - offset)
        }
    }

    /// The node the train stands on or is heading for, and the direction it
    /// faces there: the node's heading, or for a link its `to` end and the
    /// direction from `from` to `to`. Where it leaves next starts here.
    ///
    /// Only for well-formed positions.
    var ahead: (node: GridPosition, heading: TrackDirection) {
        switch self {
        case .atNode(let tile, let heading):
            return (tile, heading)
        case .onLink(let from, let to, _):
            guard let heading = TrackDirection(from: from, to: to) else {
                preconditionFailure("\(self) is not a well-formed position")
            }
            return (to, heading)
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
        }
    }
}

// MARK: - Codable

extension TrainPosition: Codable {
    private enum CodingKeys: String, CodingKey {
        case atNode, onLink
    }

    private enum NodeCodingKeys: String, CodingKey {
        case tile, heading
    }

    private enum LinkCodingKeys: String, CodingKey {
        case from, to, offset
    }

    /// Decodes `{"atNode": {"tile", "heading"}}` or
    /// `{"onLink": {"from", "to", "offset"}}`, rejecting positions that are
    /// not well formed rather than repairing them: an offset of 0 or
    /// ``linkLength`` is not read as the node at that end. Whether the
    /// position lies on track is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let kind = container.allKeys.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A train position needs exactly one of \"atNode\" and \"onLink\"."
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
        }
    }
}
