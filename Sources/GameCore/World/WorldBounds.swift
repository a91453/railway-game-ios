/// The world's extent (Stage F3d, ARCHITECTURE decision 54): a rectangle of
/// the plan from its north-west corner, `width` world units east and
/// `height` units south. A point is in the world when `0 <= x < width` and
/// `0 <= y < height`; every track node and station stands in it.
///
/// The world has no cells. Everything in it stands at integer world
/// coordinates (``WorldCoordinate/unitsPerMetre`` to a metre), and the
/// bounds only say how far it reaches. Until Stage F3d the world was a map
/// of 1024-unit tiles (`GridMap`), whose size a save still gives in tiles
/// before save version 6 (see ``SavedGame``).
public struct WorldBounds: Hashable, Sendable {
    /// The longest either side may be: 2^25 units, 524,288 m, enough for
    /// the whole of Taiwan (decision 88). Until then it was 2^20 units,
    /// 16,384 m, a new game's world both ways (Stage E1), which a new game
    /// still is. Every coordinate in it stays inside
    /// ``WorldCoordinate/limit`` (2^29).
    public static let maximumSide: Int64 = 1 << 25

    /// The largest world: 524.288 km a side.
    public static let maximum = WorldBounds(checkedWidth: maximumSide, height: maximumSide)

    /// The world of 2^20 units, 16.384 km, a side: the largest until
    /// decision 88, and a new game's (Stage E1).
    public static let standard = WorldBounds(checkedWidth: 1 << 20, height: 1 << 20)

    /// East to west, in world units.
    public let width: Int64
    /// North to south, in world units.
    public let height: Int64

    /// A world `width` units east to west and `height` units north to
    /// south.
    ///
    /// - Throws: ``GameError/invalidMapSize(width:height:)`` if either side
    ///   is outside `1...maximumSide`.
    public init(width: Int64, height: Int64) throws(GameError) {
        guard Self.isValidSide(width), Self.isValidSide(height) else {
            throw .invalidMapSize(width: width, height: height)
        }
        self.init(checkedWidth: width, height: height)
    }

    private init(checkedWidth width: Int64, height: Int64) {
        self.width = width
        self.height = height
    }

    static func isValidSide(_ side: Int64) -> Bool {
        (1...maximumSide).contains(side)
    }

    /// Whether `point` lies in the world: `0 <= x < width` and
    /// `0 <= y < height`.
    public func contains(_ point: PlanPoint) -> Bool {
        (0..<width).contains(point.x) && (0..<height).contains(point.y)
    }
}

extension WorldBounds: Codable {
    private enum CodingKeys: String, CodingKey {
        case width, height
    }

    /// Decodes `{"width", "height"}` in world units, rejecting a side
    /// outside `1...maximumSide`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int64.self, forKey: .width)
        let height = try container.decode(Int64.self, forKey: .height)
        guard Self.isValidSide(width), Self.isValidSide(height) else {
            throw DecodingError.dataCorruptedError(
                forKey: .width, in: container,
                debugDescription: "A world \(width) by \(height) units is not one a world can be: each side is 1 to \(Self.maximumSide)."
            )
        }
        self.init(checkedWidth: width, height: height)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}
