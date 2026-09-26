/// One of the four edges of a tile that a track can connect through.
public enum TrackDirection: CaseIterable, Hashable, Codable, Sendable {
    case north, east, south, west
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
}

extension TrackConnections: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt8.self)
        guard Self.all.isSuperset(of: TrackConnections(rawValue: rawValue)) else {
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
