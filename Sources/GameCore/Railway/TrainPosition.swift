/// Where a placed train is on the track network.
///
/// A train that is not on the track is *unplaced*: its ``Train/position`` is
/// `nil`. There is no unplaced case here, so there is only one way to say it.
///
/// A train is always on an edge: ``onEdge(_:offset:)``, travelling the edge
/// one way, `offset` units from where that traversal starts, with `0 <=
/// offset <=` the edge's length. Edges are any length. At a node the train is
/// at the end of the edge it arrived along (offset = length), and a train
/// with a body (see ``Train/length``) is always written that way; only a train
/// of one car may stand at offset 0, facing into an edge from its start (as
/// one does after turning round at a dead end). Every other place on an edge
/// has one representation.
///
/// Distances are world units (``WorldCoordinate/unitsPerMetre`` to a metre)
/// and imply no speed. Until Stage F3c a train could also stand on the grid
/// (at a track tile's centre, or on the link between two); the grid went
/// with ARCHITECTURE decision 51.
///
/// The enum accepts any values. Validity is checked where a position enters
/// a world: ``GameWorld/placeTrain(_:at:)`` and decoding, which also require
/// it to lie on that world's track.
public enum TrainPosition: Hashable, Sendable {
    /// On an edge of the track network (Stage S3), travelling it the way
    /// the traversal goes, `offset` units from where the traversal starts
    /// (the edge's `from` node going forward, its `to` node going
    /// backward).
    case onEdge(TrackTraversal, offset: Int64)
}

extension TrainPosition {
    /// Whether the position could lie on some network's track: an edge
    /// numbered from 1 and an offset of 0 or more. Whether the offset is
    /// within the edge is up to the world.
    var isWellFormed: Bool {
        switch self {
        case .onEdge(let traversal, let offset):
            (traversal.edge.networkNumber ?? 0) >= 1 && offset >= 0
        }
    }
}

// MARK: - Codable

extension TrainPosition: Codable {
    private enum CodingKeys: String, CodingKey {
        case atNode, onLink, onEdge
    }

    private enum EdgeCodingKeys: String, CodingKey {
        case edge, direction, offset
    }

    /// Decodes `{"onEdge": {"edge", "direction", "offset"}}` (the edge's
    /// number, `"forward"` or `"backward"`), rejecting positions that are not
    /// well formed rather than repairing them: an edge below 1 or a negative
    /// offset is refused. Whether the position lies on track (and the offset
    /// within the edge) is checked by the ``GameWorld`` decoder.
    ///
    /// A position on the grid (`"atNode"` or `"onLink"`), which only a save
    /// made by hand could hold (the app has saved only the track network
    /// since saves began, Stage C4), is refused with that reason: the grid
    /// went in Stage F3c (ARCHITECTURE decision 51).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let kind = container.allKeys.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A train position needs exactly one key, \"onEdge\"."
            ))
        }
        switch kind {
        case .atNode, .onLink:
            throw DecodingError.dataCorruptedError(
                forKey: kind, in: container,
                debugDescription: "A train on the grid (\"\(kind.stringValue)\") is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold one."
            )
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
        case .onEdge(let traversal, let offset):
            var edge = container.nestedContainer(keyedBy: EdgeCodingKeys.self, forKey: .onEdge)
            try edge.encode(traversal.edge.networkNumber, forKey: .edge)
            try edge.encode(traversal.direction, forKey: .direction)
            try edge.encode(offset, forKey: .offset)
        }
    }
}
