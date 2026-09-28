/// One of the four edges of a tile that a track can connect through.
public enum TrackDirection: CaseIterable, Hashable, Codable, Sendable {
    case north, east, south, west

    /// The direction pointing back: a track leaving a tile through this edge
    /// enters the neighbouring tile through `opposite`.
    public var opposite: TrackDirection {
        switch self {
        case .north: .south
        case .east: .west
        case .south: .north
        case .west: .east
        }
    }

    /// The direction from `position` to `neighbor` when `neighbor` is the
    /// next tile north, east, south or west of it; `nil` for the same tile,
    /// diagonal and more distant tiles.
    ///
    /// Needs no map and is safe for any coordinates: a difference too large
    /// for `Int` is simply not a neighbour.
    init?(from position: GridPosition, to neighbor: GridPosition) {
        let dx = neighbor.x.subtractingReportingOverflow(position.x)
        let dy = neighbor.y.subtractingReportingOverflow(position.y)
        guard !dx.overflow, !dy.overflow else { return nil }
        switch (dx.partialValue, dy.partialValue) {
        case (0, -1): self = .north
        case (1, 0): self = .east
        case (0, 1): self = .south
        case (-1, 0): self = .west
        default: return nil
        }
    }
}

/// The set of tile edges a track piece connects to.
///
/// A bit set rather than `Set<TrackDirection>`: it is one byte per tile,
/// encodes to a stable value (a `Set` encodes in per-process hash order), and
/// makes straights, curves and junctions cheap to compare.
public struct TrackConnections: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let north = TrackConnections(rawValue: 1 << 0)
    public static let east = TrackConnections(rawValue: 1 << 1)
    public static let south = TrackConnections(rawValue: 1 << 2)
    public static let west = TrackConnections(rawValue: 1 << 3)

    private static let all: TrackConnections = [.north, .east, .south, .west]

    public init(_ direction: TrackDirection) {
        switch direction {
        case .north: self = .north
        case .east: self = .east
        case .south: self = .south
        case .west: self = .west
        }
    }

    /// The connected directions in a fixed order (north, east, south, west).
    public var directions: [TrackDirection] {
        TrackDirection.allCases.filter { contains(TrackConnections($0)) }
    }

    /// Whether every set bit is one of the four directions. `init(rawValue:)`
    /// accepts any byte, so values from outside GameCore are checked with this
    /// and rejected rather than masked.
    var hasOnlyKnownDirections: Bool {
        Self.all.isSuperset(of: self)
    }
}

extension TrackConnections: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt8.self)
        guard TrackConnections(rawValue: rawValue).hasOnlyKnownDirections else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown track connection bits in \(rawValue)."
            )
        }
        self.init(rawValue: rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
