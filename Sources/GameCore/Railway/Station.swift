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

/// A station: the tile it was built on, and the tiles it has grown onto
/// since (Phase 4.5 Stage S2); or, from Stage F1, a point of the world it
/// stands at, taking no tile.
///
/// A station on tiles has the grid track beside its tiles as platforms (see
/// ``GameWorld/platforms(of:)``). A station at a point has only platforms on
/// the track network (Stage S4, ``GameWorld/trackPlatforms(of:)``), and
/// several of them, or a station on tiles, may stand over the same tile.
public struct Station: Identifiable, Hashable, Sendable {
    public let id: StationID
    public let name: String
    /// The tile the station was built on; for a station at a point, the
    /// tile under the point, which it does not take.
    public let position: GridPosition
    /// The tiles the station has grown onto, in the order it grew (see
    /// ``GameWorld/extendStation(_:to:)``): each beside one of the
    /// station's tiles before it. Empty for a station of one tile and for a
    /// station at a point.
    public internal(set) var annexes: [GridPosition]
    /// Where a station built at a point stands (Stage F1), or `nil` for a
    /// station on tiles.
    public let point: PlanPoint?

    public init(id: StationID, name: String, position: GridPosition, annexes: [GridPosition] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.annexes = annexes
        self.point = nil
    }

    /// A station standing at `point`, taking no tile (Stage F1). Its
    /// ``position`` is the tile under the point.
    ///
    /// - Precondition: both components of `point` are 0 or more.
    public init(id: StationID, name: String, point: PlanPoint) {
        precondition(point.x >= 0 && point.y >= 0, "A station's point lies on the map")
        self.id = id
        self.name = name
        self.position = GridPosition(x: Int(point.x / WorldCoordinate.tileSize), y: Int(point.y / WorldCoordinate.tileSize))
        self.annexes = []
        self.point = point
    }

    /// Every tile the station takes: the one it was built on, then its
    /// annexes in the order it grew. None for a station at a point.
    public var tiles: [GridPosition] {
        point == nil ? [position] + annexes : []
    }

    /// Where the station is seen from above: its point, or the centre of
    /// the tile it was built on.
    public var location: PlanPoint {
        let size = WorldCoordinate.tileSize
        return point ?? PlanPoint(x: Int64(position.x) * size + size / 2, y: Int64(position.y) * size + size / 2)
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
        case id, name, position, annexes, point
    }

    /// Decodes a station: on tiles, `{"id", "name", "position"}` and, once
    /// it has grown, `"annexes"`; at a point (Stage F1), `{"id", "name",
    /// "point"}`. A station of one tile has no `"annexes"` key, which is
    /// also how stations saved before they could grow read; an explicit
    /// `null` is rejected, and so are annexes that are not each beside an
    /// earlier tile or that repeat a tile, a station with both a position
    /// and a point or with neither, and a point with a negative component.
    /// That the tiles are the station's on the map, and that the point lies
    /// on it, is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(StationID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        if container.contains(.point) {
            guard !container.contains(.position), !container.contains(.annexes) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .point, in: container, debugDescription: "Station \(id.rawValue) stands either at a point or on tiles, not both."
                )
            }
            let point = try container.decode(PlanPoint.self, forKey: .point)
            guard point.x >= 0, point.y >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .point, in: container, debugDescription: "Station \(id.rawValue) stands off the map."
                )
            }
            self.init(id: id, name: name, point: point)
            return
        }
        self.init(
            id: id, name: name, position: try container.decode(GridPosition.self, forKey: .position),
            annexes: container.contains(.annexes) ? try container.decode([GridPosition].self, forKey: .annexes) : []
        )
        guard isConnected else {
            throw DecodingError.dataCorruptedError(
                forKey: .annexes, in: container, debugDescription: "Station \(id.rawValue)'s tiles must each be beside an earlier one, once each."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if let point {
            try container.encode(point, forKey: .point)
            return
        }
        try container.encode(position, forKey: .position)
        if !annexes.isEmpty {
            try container.encode(annexes, forKey: .annexes)
        }
    }
}
