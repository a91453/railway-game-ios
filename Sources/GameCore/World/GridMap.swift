/// A fixed-size rectangular grid of tiles: the land (empty ground and the
/// tiles stations stand on). Railway track is in ``RailwayNetwork`` (Stage
/// S3A).
///
/// Only the tiles that are not empty are stored (Stage E1): a new game's map
/// is 1024 tiles a side, about 16 km, and since Stage F1 stations stand at
/// points rather than on tiles, so nearly all of it stays empty ground.
///
/// Only ``GameWorld`` mutates a map, so every change goes through validated
/// game rules. Callers read tiles via ``tile(at:)`` or ``tiles``.
public struct GridMap: Equatable, Sendable {
    /// Upper bound for either side, keeping allocations bounded: 1024 tiles
    /// of 16 m, a new game's map since Stage E1.
    public static let maximumSideLength = 1024

    public let width: Int
    public let height: Int
    /// The tiles that are not ``TileType/empty``, by their index in
    /// row-major order. Never holds `.empty`, so equal maps have equal
    /// storage.
    private var occupied: [Int: TileType]

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
        self.occupied = [:]
    }

    public func contains(_ position: GridPosition) -> Bool {
        (0..<width).contains(position.x) && (0..<height).contains(position.y)
    }

    /// The tile at `position`, or `nil` if it lies outside the map.
    public func tile(at position: GridPosition) -> MapTile? {
        guard contains(position) else { return nil }
        return MapTile(position: position, type: occupied[index(of: position)] ?? .empty)
    }

    /// Every tile in row-major order (row `y == 0` first): `width × height`
    /// of them, over a million on a new game's map. ``occupiedTiles`` has
    /// only the ones that are not empty.
    public var tiles: [MapTile] {
        (0..<(width * height)).map { index in
            MapTile(position: position(of: index), type: occupied[index] ?? .empty)
        }
    }

    /// The tiles that are not ``TileType/empty``, in row-major order.
    public var occupiedTiles: [MapTile] {
        occupied.keys.sorted().map { index in
            MapTile(position: position(of: index), type: occupied[index]!)
        }
    }

    /// The position one tile from `position` toward `direction`, or `nil` if
    /// either position lies outside the map.
    ///
    /// `position` is checked first, so the one-tile step cannot overflow even
    /// for extreme coordinates.
    func neighbor(of position: GridPosition, toward direction: TrackDirection) -> GridPosition? {
        guard contains(position) else { return nil }
        var neighbor = position
        switch direction {
        case .north: neighbor.y -= 1
        case .east: neighbor.x += 1
        case .south: neighbor.y += 1
        case .west: neighbor.x -= 1
        }
        return contains(neighbor) ? neighbor : nil
    }

    /// Replaces the tile at `position`. Callers must validate the position.
    mutating func setType(_ type: TileType, at position: GridPosition) {
        precondition(contains(position), "setType(_:at:) called with \(position) outside the map")
        occupied[index(of: position)] = type == .empty ? nil : type
    }

    private func index(of position: GridPosition) -> Int {
        position.y * width + position.x
    }

    private func position(of index: Int) -> GridPosition {
        GridPosition(x: index % width, y: index / width)
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
        self.width = width
        self.height = height
        self.occupied = [:]
        for (index, tile) in tiles.enumerated() where tile != .empty {
            occupied[index] = tile
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(tiles.map(\.type), forKey: .tiles)
    }
}
