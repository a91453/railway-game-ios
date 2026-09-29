// World coordinates (Phase 4.5 Stage S3, ARCHITECTURE decisions 28 and 29).
// One world frame holds the grid and the continuous track network: x grows
// east, y south (as on the grid) and z up, in the logical units trains
// already move in. A tile is `tileSize` units wide, so the centre of tile
// (x, y) is (1024x + 512, 1024y + 512, 0). Nominally a unit is 1/64 m (a tile
// is 16 m); only renderers and grades care, the simulation does not.
//
// Every coordinate is an integer. Floating point never holds a position:
// renderers convert these values for display and never write back.

/// A point in the world, in logical units.
///
/// Like ``TrackConnections``, the type accepts any values; where a point
/// enters a world (a command or a decoded save) it must lie within
/// ``limit`` and, for track, on the map (see ``GameWorld/buildTrackNode(at:)``).
public struct WorldCoordinate: Hashable, Sendable {
    /// East.
    public let x: Int64
    /// South.
    public let y: Int64
    /// Up. Every point of the track network is at 0 (ground level) until
    /// Stage S4 adds elevation.
    public let z: Int64

    public init(x: Int64, y: Int64, z: Int64 = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// The width of a tile in world units: the length of a grid link.
    public static let tileSize: Int64 = TrainPosition.linkLength

    /// The largest magnitude any component may have. Within it every
    /// difference fits in 2^30, every square in 2^60 and the sum of three
    /// squares below 2^62, so the geometry never overflows an `Int64`.
    public static let limit: Int64 = 1 << 29

    /// Whether every component lies within ``limit``.
    public var isWithinLimits: Bool {
        Self.isWithinLimits(x) && Self.isWithinLimits(y) && Self.isWithinLimits(z)
    }

    static func isWithinLimits(_ value: Int64) -> Bool {
        -limit <= value && value <= limit
    }

    /// The centre of the tile at `tile`, at ground level.
    ///
    /// - Precondition: `tile` lies on a map (both coordinates in
    ///   `0..<GridMap.maximumSideLength`), so the result is within ``limit``.
    public init(centreOf tile: GridPosition) {
        precondition(
            (0..<GridMap.maximumSideLength).contains(tile.x) && (0..<GridMap.maximumSideLength).contains(tile.y),
            "init(centreOf:) needs a tile on a map"
        )
        self.init(x: Int64(tile.x) * Self.tileSize + Self.tileSize / 2, y: Int64(tile.y) * Self.tileSize + Self.tileSize / 2)
    }

    /// The point seen from above: its x and y.
    public var plan: PlanPoint {
        PlanPoint(x: x, y: y)
    }
}

/// A point seen from above (x east, y south), in world units: a control
/// point of a curve, which shapes the track in plan only.
public struct PlanPoint: Hashable, Sendable {
    public let x: Int64
    public let y: Int64

    public init(x: Int64, y: Int64) {
        self.x = x
        self.y = y
    }

    /// Whether both components lie within ``WorldCoordinate/limit``.
    public var isWithinLimits: Bool {
        WorldCoordinate.isWithinLimits(x) && WorldCoordinate.isWithinLimits(y)
    }

    /// The vector from `other` to this point.
    ///
    /// - Precondition: both points are within ``WorldCoordinate/limit``, so
    ///   the difference cannot overflow.
    func vector(from other: PlanPoint) -> PlanVector {
        PlanVector(dx: x - other.x, dy: y - other.y)
    }
}

/// A direction or displacement seen from above, in world units. Directions
/// the geometry returns are not normalised: only their way matters, and
/// normalising would need floating point.
public struct PlanVector: Hashable, Sendable {
    public let dx: Int64
    public let dy: Int64

    public init(dx: Int64, dy: Int64) {
        self.dx = dx
        self.dy = dy
    }

    /// The same direction, the other way.
    public var reversed: PlanVector {
        PlanVector(dx: -dx, dy: -dy)
    }

    var isZero: Bool {
        dx == 0 && dy == 0
    }

    /// The dot product. Both vectors have components within 2^30 (differences
    /// of points within ``WorldCoordinate/limit``), so it fits in 2^61.
    func dot(_ other: PlanVector) -> Int64 {
        dx * other.dx + dy * other.dy
    }

    /// The z component of the cross product, within 2^61 like ``dot(_:)``.
    func cross(_ other: PlanVector) -> Int64 {
        dx * other.dy - dy * other.dx
    }

    /// The length rounded to the nearest unit.
    var length: Int64 {
        FixedPoint.roundedSquareRoot(dx * dx + dy * dy)
    }

    /// How far off straight a train may pass from one edge end to another
    /// at a node: the ends' directions away from the node must be opposite
    /// to within a slope of 1 in ``kinkSlope`` (about 3.6 degrees).
    static let kinkSlope: Int64 = 16

    /// Whether this direction and `other` point opposite ways, to within
    /// ``kinkSlope``: their dot product is negative and the cross product
    /// at most a sixteenth of its magnitude. Exact integer arithmetic.
    func isOpposite(to other: PlanVector) -> Bool {
        let dot = dot(other)
        return dot < 0 && abs(cross(other)) <= -dot / Self.kinkSlope
    }
}

// MARK: - Codable

extension WorldCoordinate: Codable {
    private enum CodingKeys: String, CodingKey {
        case x, y, z
    }

    /// Decodes `{"x", "y", "z"}`, rejecting a component beyond ``limit``
    /// rather than clamping it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Int64.self, forKey: .x),
            y: try container.decode(Int64.self, forKey: .y),
            z: try container.decode(Int64.self, forKey: .z)
        )
        guard isWithinLimits else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A world coordinate lies beyond \(Self.limit).")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
    }
}

extension PlanPoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case x, y
    }

    /// Decodes `{"x", "y"}`, rejecting a component beyond
    /// ``WorldCoordinate/limit`` rather than clamping it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decode(Int64.self, forKey: .x), y: try container.decode(Int64.self, forKey: .y))
        guard isWithinLimits else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A plan point lies beyond \(WorldCoordinate.limit).")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}
