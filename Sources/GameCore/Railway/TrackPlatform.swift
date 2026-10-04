// Platforms on the railway network (Phase 4.5 Stage S4, ARCHITECTURE
// decision 30). (A Stage S2 platform was a grid track tile beside a station
// tile; it went with the grid in Stage F3c, decision 51.) A platform is
// railway infrastructure in its own right, kept in the
// RailwayNetwork like the edge it lies on (Stage S3A: the network is the one
// record of the railway): a station's stretch of one edge, from where it
// starts to where it ends. Its level (height and structure) follows from the
// edge, so one station can have platforms on the surface, on a viaduct and
// underground, straight or curved, and a later stage can charge a walk
// between them by their height difference. Its ends cut the edge's resource
// spans, so a train at a platform holds the platform's own spans.

/// A station's platform along a stretch of an edge of the track network:
/// from ``start`` to ``end`` along the edge, measured from its `from` node.
///
/// The stretch lies within the edge and is level; platforms on one edge do
/// not overlap (see ``GameWorld/addTrackPlatform(_:on:from:to:)``).
public struct TrackPlatform: Hashable, Comparable, Sendable {
    /// The station it serves.
    public let station: StationID
    public let edge: TrackEdgeID
    public let start: Int64
    public let end: Int64

    public init(station: StationID, edge: TrackEdgeID, start: Int64, end: Int64) {
        self.station = station
        self.edge = edge
        self.start = start
        self.end = end
    }

    /// How long the platform is, in world units of chainage.
    public var length: Int64 {
        end - start
    }

    /// Along the track: by edge, then by where they start. Platforms never
    /// overlap, so no two are equal in this order.
    public static func < (lhs: TrackPlatform, rhs: TrackPlatform) -> Bool {
        (lhs.edge, lhs.start, lhs.end, lhs.station) < (rhs.edge, rhs.start, rhs.end, rhs.station)
    }

    /// Whether the two stretches share more than a point.
    func overlaps(_ other: TrackPlatform) -> Bool {
        edge == other.edge && start < other.end && other.start < end
    }
}

extension TrackPlatform: Codable {
    private enum CodingKeys: String, CodingKey {
        case station, edge, start, end
    }

    /// Decodes `{"station", "edge", "start", "end"}`, the edge by its number.
    /// Whether the station exists and the stretch fits the edge is checked by
    /// the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let station = try container.decode(Int.self, forKey: .station)
        let number = try container.decode(Int.self, forKey: .edge)
        guard number >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .edge, in: container, debugDescription: "A platform's edge number starts at 1.")
        }
        self.init(
            station: StationID(rawValue: station), edge: .edge(number),
            start: try container.decode(Int64.self, forKey: .start), end: try container.decode(Int64.self, forKey: .end)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station.rawValue, forKey: .station)
        try container.encode(edge.networkNumber, forKey: .edge)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}
