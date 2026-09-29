// Platforms on the track network (Phase 4.5 Stage S4, ARCHITECTURE decision
// 30). A Stage S2 platform is a grid track tile beside a station tile. On the
// network a platform is bound to a stretch of one edge instead: which edge,
// and where along it it starts and ends. Its level (height and structure)
// follows from the edge, so one station can have platforms on the surface,
// on a viaduct and underground, and a later stage can charge a walk between
// them by their height difference.

/// A platform along a stretch of an edge of the track network: from
/// ``start`` to ``end`` along the edge, measured from its `from` node.
///
/// The stretch lies within the edge and is level; platforms on one edge do
/// not overlap (see ``GameWorld/addTrackPlatform(_:on:from:to:)``).
public struct TrackPlatform: Hashable, Comparable, Sendable {
    /// Always ``TrackEdgeID/edge(_:)``: the grid has its own platforms.
    public let edge: TrackEdgeID
    public let start: Int64
    public let end: Int64

    public init(edge: TrackEdgeID, start: Int64, end: Int64) {
        self.edge = edge
        self.start = start
        self.end = end
    }

    /// How long the platform is, in world units of chainage.
    public var length: Int64 {
        end - start
    }

    /// By edge, then by where they start.
    public static func < (lhs: TrackPlatform, rhs: TrackPlatform) -> Bool {
        (lhs.edge, lhs.start, lhs.end) < (rhs.edge, rhs.start, rhs.end)
    }

    /// Whether the two stretches share more than a point.
    func overlaps(_ other: TrackPlatform) -> Bool {
        edge == other.edge && start < other.end && other.start < end
    }
}

/// A station's platform on the track network.
public struct StationPlatform: Hashable, Sendable {
    public let station: StationID
    public let platform: TrackPlatform

    public init(station: StationID, platform: TrackPlatform) {
        self.station = station
        self.platform = platform
    }
}

extension TrackPlatform: Codable {
    private enum CodingKeys: String, CodingKey {
        case edge, start, end
    }

    /// Decodes `{"edge", "start", "end"}`, the edge by its number. Whether
    /// the stretch fits the edge is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let number = try container.decode(Int.self, forKey: .edge)
        guard number >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .edge, in: container, debugDescription: "A platform's edge number starts at 1.")
        }
        self.init(edge: .edge(number), start: try container.decode(Int64.self, forKey: .start), end: try container.decode(Int64.self, forKey: .end))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edge.networkNumber, forKey: .edge)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}
