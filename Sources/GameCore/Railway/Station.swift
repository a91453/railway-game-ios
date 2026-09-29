/// Stable identifier of a station, unique within a ``GameWorld``.
///
/// IDs are allocated sequentially by the world (never reused), so the same
/// sequence of actions always yields the same IDs.
public struct StationID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: StationID, rhs: StationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A station: the tile it was built on, the tiles it has grown onto since
/// (Phase 4.5 Stage S2), and its platforms on the track network (Stage S4).
public struct Station: Identifiable, Hashable, Sendable {
    public let id: StationID
    public let name: String
    /// The tile the station was built on.
    public let position: GridPosition
    /// The tiles the station has grown onto, in the order it grew (see
    /// ``GameWorld/extendStation(_:to:)``): each beside one of the
    /// station's tiles before it. Empty for a station of one tile.
    public internal(set) var annexes: [GridPosition]
    /// The station's platforms on the track network, in order (see
    /// ``TrackPlatform``). The grid tiles beside its tiles are platforms
    /// too (see ``GameWorld/platforms(of:)``).
    public internal(set) var trackPlatforms: [TrackPlatform]

    public init(id: StationID, name: String, position: GridPosition, annexes: [GridPosition] = [], trackPlatforms: [TrackPlatform] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.annexes = annexes
        self.trackPlatforms = trackPlatforms
    }

    /// Every tile of the station: the one it was built on, then its
    /// annexes in the order it grew.
    public var tiles: [GridPosition] {
        [position] + annexes
    }

    /// Whether every annex is beside one of the tiles before it, and no
    /// tile repeats.
    var isConnected: Bool {
        var seen = [position]
        for annex in annexes {
            guard !seen.contains(annex), seen.contains(where: { TrackDirection(from: $0, to: annex) != nil }) else { return false }
            seen.append(annex)
        }
        return true
    }
}

extension Station: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, position, annexes, trackPlatforms
    }

    /// Decodes a station. A station of one tile has no `"annexes"` key,
    /// which is also how stations saved before they could grow read; an
    /// explicit `null` is rejected, and so are annexes that are not each
    /// beside an earlier tile or that repeat a tile. A station without
    /// platforms on the track network has no `"trackPlatforms"` key (Stage
    /// S4); an explicit `null` is rejected, and so are platforms out of
    /// order. That the tiles are the station's on the map, and that the
    /// platforms fit their edges, is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(StationID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(GridPosition.self, forKey: .position)
        annexes = container.contains(.annexes) ? try container.decode([GridPosition].self, forKey: .annexes) : []
        trackPlatforms = container.contains(.trackPlatforms) ? try container.decode([TrackPlatform].self, forKey: .trackPlatforms) : []
        guard isConnected else {
            throw DecodingError.dataCorruptedError(
                forKey: .annexes, in: container, debugDescription: "Station \(id.rawValue)'s tiles must each be beside an earlier one, once each."
            )
        }
        guard zip(trackPlatforms, trackPlatforms.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .trackPlatforms, in: container, debugDescription: "Station \(id.rawValue)'s platforms must be in order, once each."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(position, forKey: .position)
        if !annexes.isEmpty {
            try container.encode(annexes, forKey: .annexes)
        }
        if !trackPlatforms.isEmpty {
            try container.encode(trackPlatforms, forKey: .trackPlatforms)
        }
    }
}
