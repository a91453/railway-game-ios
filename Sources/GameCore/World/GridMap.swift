/// A fixed-size rectangular grid of tiles, stored densely in row-major order.
///
/// Only ``GameWorld`` mutates a map, so every change goes through validated
/// game rules. Callers read tiles via ``tile(at:)`` or ``tiles``.
public struct GridMap: Equatable, Sendable {
    /// Upper bound for either side, keeping allocations bounded. Provisional;
    /// revisit once rendering and simulation performance are measured.
    public static let maximumSideLength = 1024

    public let width: Int
    public let height: Int
    private var storage: [TileType]

    /// Creates a map with every tile empty.
    ///
    /// - Throws: ``GameError/invalidMapSize(width:height:)`` if either
    ///   dimension is outside `1...maximumSideLength`.
    public init(width: Int, height: Int) throws(GameError) {
        guard Self.isValidSize(width: width, height: height) else {
            throw .invalidMapSize(width: width, height: height)
        }
        self.width = width
        self.height = height
        self.storage = Array(repeating: .empty, count: width * height)
    }

    public func contains(_ position: GridPosition) -> Bool {
        (0..<width).contains(position.x) && (0..<height).contains(position.y)
    }

    /// The tile at `position`, or `nil` if it lies outside the map.
    public func tile(at position: GridPosition) -> MapTile? {
        guard contains(position) else { return nil }
        return MapTile(position: position, type: storage[index(of: position)])
    }

    /// Every tile in row-major order (row `y == 0` first).
    public var tiles: [MapTile] {
        storage.indices.map { index in
            MapTile(
                position: GridPosition(x: index % width, y: index / width),
                type: storage[index]
            )
        }
    }

    /// Replaces the tile at `position`. Callers must validate the position.
    mutating func setType(_ type: TileType, at position: GridPosition) {
        precondition(contains(position), "setType(_:at:) called with \(position) outside the map")
        storage[index(of: position)] = type
    }

    private func index(of position: GridPosition) -> Int {
        position.y * width + position.x
    }

    private static func isValidSize(width: Int, height: Int) -> Bool {
        let range = 1...maximumSideLength
        return range.contains(width) && range.contains(height)
    }
}

extension GridMap: Codable {
    private enum CodingKeys: String, CodingKey {
        case width, height, tiles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int.self, forKey: .width)
        let height = try container.decode(Int.self, forKey: .height)
        let tiles = try container.decode([TileType].self, forKey: .tiles)

        guard Self.isValidSize(width: width, height: height), tiles.count == width * height else {
            throw DecodingError.dataCorruptedError(
                forKey: .tiles, in: container,
                debugDescription: "Tile count \(tiles.count) does not match a valid \(width)x\(height) map."
            )
        }
        let hasEmptyTrack = tiles.contains { tile in
            if case .track(let connections) = tile { return connections.isEmpty }
            return false
        }
        guard !hasEmptyTrack else {
            throw DecodingError.dataCorruptedError(
                forKey: .tiles, in: container,
                debugDescription: "Track tiles must have at least one connection."
            )
        }
        self.width = width
        self.height = height
        self.storage = tiles
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(storage, forKey: .tiles)
    }
}
