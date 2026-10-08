// Buildings the player places (city building P0-A, ARCHITECTURE decision
// 92). The city's own buildings (decision 74) stand one on each 64 m cell
// of land and are put up and raised by the city; these stand where the
// player puts them, at any point of the world: the cells only count and
// plan, they do not bind where a building goes. A first step: a building
// is a square of its kind's size, placed free of charge, and does not yet
// house anyone (cost, demolition and the people in it come with P0-C).

/// Identifies a building the player placed. IDs are allocated by
/// ``GameWorld`` from 1 and never handed out again.
public struct PlacedBuildingID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: PlacedBuildingID, rhs: PlacedBuildingID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the player can place: the three basic buildings.
public enum PlacedBuildingKind: String, CaseIterable, Codable, Sendable {
    /// A small house: 16 m a side.
    case house
    /// A shop: 24 m a side.
    case shop
    /// An office block: 32 m a side.
    case office

    /// The length of a side, in world units.
    public var side: Int64 {
        switch self {
        case .house: 1_024
        case .shop: 1_536
        case .office: 2_048
        }
    }

    /// The use of land it is.
    public var use: LandUse {
        switch self {
        case .house: .residential
        case .shop: .commercial
        case .office: .office
        }
    }
}

/// A building the player placed: a square of its kind's ``PlacedBuildingKind/side``,
/// its sides north–south and east–west, centred on ``centre``. It covers
/// the points `x` in `centre.x − side / 2 ..< centre.x + side / 2`, and
/// likewise `y`.
public struct PlacedBuilding: Hashable, Codable, Sendable {
    public let id: PlacedBuildingID
    public let kind: PlacedBuildingKind
    public let centre: PlanPoint

    public init(id: PlacedBuildingID, kind: PlacedBuildingKind, centre: PlanPoint) {
        self.id = id
        self.kind = kind
        self.centre = centre
    }

    /// The west, north, east and south edges: `minX ..< maxX`, `minY ..< maxY`.
    public var minX: Int64 { centre.x - kind.side / 2 }
    public var minY: Int64 { centre.y - kind.side / 2 }
    public var maxX: Int64 { minX + kind.side }
    public var maxY: Int64 { minY + kind.side }

    /// Whether it shares any ground with `other` (touching edges do not).
    func overlaps(_ other: PlacedBuilding) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }
}

/// The rules of placing a building.
public enum PlacedBuildingRules {
    /// How far a building keeps from a track's centre line and from a
    /// station's point, in world units: 2 m, a little more than half the
    /// widest car (3.38 m).
    public static let clearance: Int64 = 128
}

extension GameWorld {
    /// Places a building of `kind` centred on `centre` (decision 92):
    /// numbered next, free of charge, in no one's way. A first step: it
    /// houses no one yet.
    ///
    /// - Throws, checked in this order: ``GameError/outOfBounds(_:)`` naming
    ///   `centre` unless the whole square lies in the world;
    ///   ``GameError/buildingOverlaps(_:)`` naming the lowest numbered
    ///   building it would share ground with;
    ///   ``GameError/buildingOnTrack(_:)`` naming the lowest numbered edge
    ///   whose centre line passes closer than ``PlacedBuildingRules/clearance``
    ///   to the square (or crosses it); ``GameError/buildingOnStation(_:)``
    ///   naming the lowest numbered station whose point is that near; or
    ///   ``GameError/idsExhausted``.
    @discardableResult
    public mutating func placeBuilding(_ kind: PlacedBuildingKind, at centre: PlanPoint) throws(GameError) -> PlacedBuilding {
        let candidate = PlacedBuilding(id: PlacedBuildingID(rawValue: nextPlacedBuildingID), kind: kind, centre: centre)
        guard Self.lies(candidate, in: bounds) else { throw .outOfBounds(centre) }
        if let other = placedBuildings.first(where: { $0.overlaps(candidate) }) {
            throw .buildingOverlaps(other.id)
        }
        if let edge = edgeInTheWay(of: candidate) {
            throw .buildingOnTrack(edge)
        }
        if let station = stations.first(where: { Self.isNear($0.point, candidate) }) {
            throw .buildingOnStation(station.id)
        }
        let (id, next) = try Self.allocateID(from: nextPlacedBuildingID)
        let building = PlacedBuilding(id: PlacedBuildingID(rawValue: id), kind: kind, centre: centre)
        nextPlacedBuildingID = next
        placedBuildings.append(building)
        return building
    }

    /// The building numbered `id`, or `nil`.
    public func placedBuilding(id: PlacedBuildingID) -> PlacedBuilding? {
        placedBuildings.first { $0.id == id }
    }

    /// Whether `building`'s whole square lies in `bounds`.
    static func lies(_ building: PlacedBuilding, in bounds: WorldBounds) -> Bool {
        building.minX >= 0 && building.minY >= 0 && building.maxX <= bounds.width && building.maxY <= bounds.height
    }

    /// Whether `point` lies closer than the clearance to `building`'s square.
    static func isNear(_ point: PlanPoint, _ building: PlacedBuilding) -> Bool {
        let c = PlacedBuildingRules.clearance
        return point.x > building.minX - c && point.x < building.maxX + c && point.y > building.minY - c && point.y < building.maxY + c
    }

    /// The lowest numbered edge whose centre line comes closer than the
    /// clearance to `building`'s square (its points `minX ... maxX` by
    /// `minY ... maxY`), or `nil`: one passing a whole clearance away is
    /// clear.
    private func edgeInTheWay(of building: PlacedBuilding) -> TrackEdgeID? {
        let c = PlacedBuildingRules.clearance
        let box = (minX: building.minX - c + 1, minY: building.minY - c + 1, maxX: building.maxX + c - 1, maxY: building.maxY + c - 1)
        for edge in network.edges.sorted(by: { $0.id < $1.id }) {
            guard let points = network.geometry(of: edge.id)?.points.map(\.plan) else { continue }
            for (a, b) in zip(points, points.dropFirst()) where Self.segment(a, b, crosses: box) {
                return edge.id
            }
        }
        return nil
    }

    /// Whether the segment from `a` to `b` has a point strictly inside
    /// `box` or on its edge, in exact integers: their extents overlap, and
    /// the box's corners do not all lie strictly on one side of the line.
    static func segment(_ a: PlanPoint, _ b: PlanPoint, crosses box: (minX: Int64, minY: Int64, maxX: Int64, maxY: Int64)) -> Bool {
        guard max(a.x, b.x) >= box.minX, min(a.x, b.x) <= box.maxX, max(a.y, b.y) >= box.minY, min(a.y, b.y) <= box.maxY else {
            return false
        }
        let dx = b.x - a.x, dy = b.y - a.y
        var below = false, above = false
        for (x, y) in [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.maxY)] {
            let side = dx * (y - a.y) - dy * (x - a.x)
            if side <= 0 { below = true }
            if side >= 0 { above = true }
        }
        return below && above
    }

    /// Why the placed buildings break the world's rules, or `nil`: IDs
    /// ascending and below the next, each wholly in the world and none
    /// sharing ground with another. Track and stations may stand on one
    /// built since (a first step: they are not checked against buildings).
    func placedBuildingProblem() -> String? {
        guard Self.isStrictlyIncreasing(placedBuildings.map(\.id.rawValue), below: nextPlacedBuildingID) else {
            return "Placed building IDs must be unique, ascending and below nextPlacedBuildingID."
        }
        for (index, building) in placedBuildings.enumerated() {
            guard Self.lies(building, in: bounds) else {
                return "Placed building \(building.id.rawValue) does not lie wholly in the world."
            }
            if let other = placedBuildings[..<index].first(where: { $0.overlaps(building) }) {
                return "Placed buildings \(other.id.rawValue) and \(building.id.rawValue) share ground."
            }
        }
        return nil
    }
}
