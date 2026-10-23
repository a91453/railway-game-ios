// Buildings the player places (city building P0-A, ARCHITECTURE decision
// 92). The city's own buildings (decision 74) stand one on each 64 m cell
// of land and are put up and raised by the city; these stand where the
// player puts them, at any point of the world: the cells only count and
// plan, they do not bind where a building goes. A building is a square of
// its kind's size. Since P0-C1 (decision 94) it is the company's: a managed
// company pays for it and keeps it on its books, it fills with residents and
// jobs who ride from the stations near it, and it earns rent (see
// CompanyBuildings.swift). Since P0-C2 (decision 95) it buys out the city's
// buildings in its way, and track and stations built later clear it. Since
// P0-D (decision 130) it can be sold to the city, which takes it over
// (BuildingSale.swift). Since decision 361 two kinds with an effect
// of their own stand among them, a park and a temple, and a building can
// have one of its kind's looks.

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

/// What the player can place: the three basic buildings, since decision
/// 111 two that stand on the shore, since decision 173 three subsidiaries,
/// and since decision 361 a park and a temple.
public enum PlacedBuildingKind: String, CaseIterable, Codable, Sendable {
    /// A small house: 16 m a side.
    case house
    /// A shop: 24 m a side.
    case shop
    /// An office block: 32 m a side.
    case office
    /// A fishermen's wharf (decision 111): shops and restaurants on a pier,
    /// as Tamsui's; 24 m a side, on the shore.
    case wharf
    /// A marina (decision 111): berths for pleasure boats and their club,
    /// a sight; 32 m a side, on the shore.
    case marina
    /// A department store (decision 173): 48 m a side, 8 storeys. A
    /// subsidiary business: it earns from the passengers of the stations
    /// near it (see Subsidiary.swift), not rent.
    case departmentStore
    /// A hotel (decision 173): 32 m a side, 14 storeys. A subsidiary.
    case hotel
    /// An amusement park (decision 173): 112 m a side, one storey. A
    /// subsidiary.
    case amusementPark
    /// A park (decision 361): 24 m a side, a lawn, a playground or a pond.
    /// It holds no one and lets nothing; the land within
    /// ``LandValueRules/parkReach`` of it is worth a park's more, as near
    /// the city's own parks (decision 91), so the company's buildings there
    /// let and sell for more.
    case park
    /// A temple (decision 361): 32 m a side, two storeys. A sight tourists
    /// come to (Tourism.swift) and a subsidiary that takes their offerings
    /// (Subsidiary.swift); it holds no one.
    case temple

    /// The length of a side, in world units.
    public var side: Int64 {
        switch self {
        case .house: 1_024
        case .shop, .wharf, .park: 1_536
        case .office, .marina, .hotel, .temple: 2_048
        case .departmentStore: 3_072
        case .amusementPark: 7_168
        }
    }

    /// The use of land it is.
    public var use: LandUse {
        switch self {
        case .house: .residential
        case .shop, .wharf, .departmentStore, .hotel: .commercial
        case .office: .office
        case .marina, .amusementPark, .temple: .leisure
        case .park: .park
        }
    }

    /// Its storeys (decision 94): a house, a shop, a wharf and a marina 2,
    /// an office block 6.
    public var floors: Int64 {
        switch self {
        case .house, .shop, .wharf, .marina, .temple: 2
        case .office: 6
        case .departmentStore: 8
        case .hotel: 14
        case .amusementPark, .park: 1
        }
    }

    /// Whether it stands on the shore (decision 111): part of it over
    /// water, part on land. The others stand on land only.
    public var standsOnShore: Bool {
        switch self {
        case .house, .shop, .office, .departmentStore, .hotel, .amusementPark, .park, .temple: false
        case .wharf, .marina: true
        }
    }

    /// The ground it stands on, in m²: 256, 576 and 1,024.
    public var footprintArea: Int64 {
        let metres = side / WorldCoordinate.unitsPerMetre
        return metres * metres
    }

    /// Its floor, in m²: the footprint by the storeys.
    public var floorArea: Int64 {
        footprintArea * floors
    }

    /// Who it holds when full, by decision 74's rule: the eighths of the
    /// floor of its use that are homes, at 48 m² a resident, the rest jobs
    /// at 32 m², each rounded down. A house 9 residents and 2 jobs, a shop
    /// and a wharf 6 and 27, an office block 16 and 168, a marina 5 and 56.
    /// A park and a temple (decision 361) hold no one.
    public var capacity: BuildingCapacity {
        guard self != .park, self != .temple else { return BuildingCapacity(residents: 0, jobs: 0) }
        let homes = Building.homeEighths(of: use)
        return BuildingCapacity(
            residents: floorArea * homes / 8 / Building.areaPerResident,
            jobs: floorArea * (8 - homes) / 8 / Building.areaPerJob
        )
    }
}

extension PlacedBuildingKind {
    /// How many looks it comes in (decision 361): a park a lawn, a
    /// playground or a garden with a pond; a temple a temple square with a
    /// gate, or a large temple; the others one. A look is only how it is
    /// drawn, numbered from 0.
    public var looks: Int {
        switch self {
        case .park: 3
        case .temple: 2
        default: 1
        }
    }
}

/// A building the player placed: a square of its kind's ``PlacedBuildingKind/side``,
/// its sides north–south and east–west, centred on ``centre``. It covers
/// the points `x` in `centre.x − side / 2 ..< centre.x + side / 2`, and
/// likewise `y`.
public struct PlacedBuilding: Hashable, Sendable {
    public let id: PlacedBuildingID
    public let kind: PlacedBuildingKind
    public let centre: PlanPoint
    /// Who lives and works in it now (decision 94): 0 when it is built,
    /// filling towards its kind's capacity while a station serves it.
    public internal(set) var residents: Int64 = 0
    public internal(set) var jobs: Int64 = 0
    /// What a managed company paid for it: the building, and the right to
    /// use the land under it (decision 94); nothing in free play, and
    /// nothing recorded for one placed before save version 22.
    public internal(set) var buildingCost: Money = .zero
    public internal(set) var landCost: Money = .zero
    /// A subsidiary's trading books (decision 173); empty for the others.
    public internal(set) var books: SubsidiaryBooks = SubsidiaryBooks()
    /// Which of its kind's ``PlacedBuildingKind/looks`` it has (decision
    /// 361), 0 for the first: only how it is drawn.
    public let look: Int
    /// A temple's tourists of the day that last ended (decision 361); 0
    /// for the others.
    public internal(set) var visitors: Int64 = 0

    public init(id: PlacedBuildingID, kind: PlacedBuildingKind, centre: PlanPoint, look: Int = 0) {
        self.id = id
        self.kind = kind
        self.centre = centre
        self.look = look
    }

    /// What was paid for it, together.
    public var cost: Money {
        buildingCost + landCost
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
    /// Places a building of `kind` centred on `centre` (decision 92), in
    /// its `look` (decision 361):
    /// numbered next, in no one's way, empty. Since decision 94 a managed
    /// company pays ``placedBuildingQuote(_:at:)`` for it, the building and
    /// the right to use the land, and keeps it on its books; free play pays
    /// nothing. Since decision 95 it buys out the city's buildings it
    /// claims (``cityCells(claimedBy:)``), which are pulled down with their
    /// cells of land: their residents and jobs move in, up to what it
    /// holds, and the rest leave. Buying out by area (decision 146), it
    /// pulls nothing down: from each cell it covers part of
    /// (``cityShares(coveredBy:)``), the share of the residents and of the
    /// jobs that its ground is of the ground the company's buildings left
    /// there, each rounded down, move in as before, and the cell keeps the
    /// rest; a cell it finishes covering goes, its people all moved in
    /// (decision 146, later). Track in a tunnel is not in its way.
    ///
    /// - Throws, checked in this order: ``GameError/invalidBuildingLook``
    ///   unless `look` is one of the kind's ``PlacedBuildingKind/looks``;
    ///   ``GameError/outOfBounds(_:)`` naming
    ///   `centre` unless the whole square lies in the world;
    ///   ``GameError/mapTileNotOwned(_:)`` naming the first tile of the map
    ///   it covers part of that the company does not own (decision 160);
    ///   ``GameError/buildingOverlaps(_:)`` naming the lowest numbered
    ///   building it would share ground with;
    ///   ``GameError/buildingOnTrack(_:)`` naming the lowest numbered edge
    ///   whose centre line passes closer than ``PlacedBuildingRules/clearance``
    ///   to the square (or crosses it); ``GameError/buildingOnStation(_:)``
    ///   naming the lowest numbered station whose point is that near;
    ///   ``GameError/onWater(row:column:)`` naming the first cell of water
    ///   (decision 105) under any part of the square, by row and then
    ///   column, or for a kind that ``PlacedBuildingKind/standsOnShore``
    ///   ``GameError/needsShore`` (decision 111) unless the square has both water and land
    ///   under it; ``GameError/onSteepSlope(row:column:)`` naming the first
    ///   steep cell under it (decision 115); ``GameError/idsExhausted``; or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func placeBuilding(_ kind: PlacedBuildingKind, at centre: PlanPoint, look: Int = 0) throws(GameError) -> PlacedBuilding {
        guard (0..<kind.looks).contains(look) else { throw .invalidBuildingLook }
        let candidate = PlacedBuilding(id: PlacedBuildingID(rawValue: nextPlacedBuildingID), kind: kind, centre: centre)
        guard Self.lies(candidate, in: bounds) else { throw .outOfBounds(centre) }
        // Decision 160: the whole square on the company's own ground.
        if let tile = firstTileNotOwned(minX: candidate.minX, minY: candidate.minY, maxX: candidate.maxX, maxY: candidate.maxY) {
            throw .mapTileNotOwned(tile)
        }
        if let other = placedBuildings.first(where: { $0.overlaps(candidate) }) {
            throw .buildingOverlaps(other.id)
        }
        if let edge = edgeInTheWay(of: candidate) {
            throw .buildingOnTrack(edge)
        }
        if let station = stations.first(where: { Self.isNear($0.point, candidate) }) {
            throw .buildingOnStation(station.id)
        }
        if kind.standsOnShore {
            guard straddlesShore(candidate) else { throw .needsShore }
        } else if let water = waterUnder(candidate) {
            throw .onWater(row: water.row, column: water.column)
        }
        if let steep = steepUnder(candidate) {
            throw .onSteepSlope(row: steep.row, column: steep.column)
        }
        let (id, next) = try Self.allocateID(from: nextPlacedBuildingID)
        let quote = placedBuildingQuote(kind, at: centre) ?? PlacedBuildingQuote(building: .zero, land: .zero)
        try economy.spend(quote.total)
        var building = PlacedBuilding(id: PlacedBuildingID(rawValue: id), kind: kind, centre: centre, look: look)
        building.buildingCost = quote.building
        building.landCost = quote.land + quote.buyOut
        let cleared = areaBuyOut ? [] : cityCells(claimedBy: candidate)
        // Decision 146, later: each covered cell's people in the share of
        // its ground the company's buildings left that this one covers, so
        // its people go by the ground as its price does. The building that
        // covers the last of the ground takes them all, and the cell with
        // them.
        let moved: [(cell: LandCell, residents: Int64, jobs: Int64, isLast: Bool)] = areaBuyOut ? cityShares(coveredBy: candidate).map { share in
            let left = Land.cellArea - coveredArea(row: share.cell.row, column: share.cell.column)
            return (cell: share.cell,
                    residents: share.cell.residents * share.area / left,
                    jobs: share.cell.jobs * share.area / left,
                    isLast: share.area == left)
        } : []
        building.residents = min(kind.capacity.residents, cleared.reduce(0) { $0 + $1.residents } + moved.reduce(0) { $0 + $1.residents })
        building.jobs = min(kind.capacity.jobs, cleared.reduce(0) { $0 + $1.jobs } + moved.reduce(0) { $0 + $1.jobs })
        nextPlacedBuildingID = next
        placedBuildings.append(building)
        acquireAsset(.building, owner: id, cost: quote.total)
        if !cleared.isEmpty {
            removeLand(at: Set(cleared.map(\.position)))
            refreshLandDemand()
        }
        let movers = moved.filter { !$0.isLast && $0.residents + $0.jobs > 0 }
        let whole = Set(moved.filter(\.isLast).map(\.cell.position))
        if !movers.isEmpty || !whole.isEmpty {
            for (cell, residents, jobs, _) in movers {
                guard let index = land.cells.firstIndex(where: { $0.position == cell.position }) else { continue }
                land.cells[index] = cell.with(residents: cell.residents - residents, jobs: cell.jobs - jobs)
            }
            // A cell the company now covers whole is its own: the city
            // keeps no land there (``isClaimedByPlacedBuilding(row:column:side:)``).
            removeLand(at: whole)
            refreshLandDemand()
        }
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
    /// clear, and so (decision 95) is one in a tunnel, which passes under
    /// (decision 124: an automatic edge's tunnel sections).
    private func edgeInTheWay(of building: PlacedBuilding) -> TrackEdgeID? {
        for edge in network.edges.sorted(by: { $0.id < $1.id }) where edge.structure != .tunnel {
            guard let stretches = network.geometry(of: edge.id).map(edge.openStretches(of:)) else { continue }
            if stretches.contains(where: { Self.line($0, comesNear: building) }) {
                return edge.id
            }
        }
        return nil
    }

    /// Whether the line through `points` comes closer than the clearance
    /// to `building`'s square.
    static func line(_ points: [PlanPoint], comesNear building: PlacedBuilding) -> Bool {
        let c = PlacedBuildingRules.clearance
        let box = (minX: building.minX - c + 1, minY: building.minY - c + 1, maxX: building.maxX + c - 1, maxY: building.maxY + c - 1)
        if points.count == 1, let point = points.first {
            return isNear(point, building)
        }
        return zip(points, points.dropFirst()).contains { Self.segment($0, $1, crosses: box) }
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
            let capacity = building.kind.capacity
            guard (0...capacity.residents).contains(building.residents), (0...capacity.jobs).contains(building.jobs),
                  building.buildingCost >= .zero, building.landCost >= .zero,
                  // Each part within range first, so their sum cannot overflow.
                  building.buildingCost.amount <= CompanyAccounts.maximumAssetCost,
                  building.landCost.amount <= CompanyAccounts.maximumAssetCost,
                  building.cost.amount <= CompanyAccounts.maximumAssetCost
            else {
                return "Placed building \(building.id.rawValue) holds more than it may or cost out of range."
            }
            guard building.books.isValid(for: building.kind) else {
                return "Placed building \(building.id.rawValue) has trading books out of range."
            }
            guard (0..<building.kind.looks).contains(building.look),
                  building.kind == .temple ? (0...Self.maximumAccrued).contains(building.visitors) : building.visitors == 0
            else {
                return "Placed building \(building.id.rawValue) has a look or visitors out of range."
            }
        }
        return nil
    }
}

extension PlacedBuilding: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, centre, residents, jobs, buildingCost, landCost, books, look, visitors
    }

    /// Decodes `{"id", "kind", "centre"}` and, since save version 22
    /// (decision 94), `"residents"`, `"jobs"`, `"buildingCost"` and
    /// `"landCost"`, each written only when not 0: a building placed before
    /// is empty and was paid nothing for. Since save version 71 (decision
    /// 361) `"look"` and a temple's `"visitors"`, each written only when
    /// not 0: a building before has the first look.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlacedBuildingID.self, forKey: .id)
        kind = try container.decode(PlacedBuildingKind.self, forKey: .kind)
        centre = try container.decode(PlanPoint.self, forKey: .centre)
        residents = try container.decodeIfPresent(Int64.self, forKey: .residents) ?? 0
        jobs = try container.decodeIfPresent(Int64.self, forKey: .jobs) ?? 0
        buildingCost = try container.decodeIfPresent(Money.self, forKey: .buildingCost) ?? .zero
        landCost = try container.decodeIfPresent(Money.self, forKey: .landCost) ?? .zero
        books = try container.decodeIfPresent(SubsidiaryBooks.self, forKey: .books) ?? SubsidiaryBooks()
        look = try container.decodeIfPresent(Int.self, forKey: .look) ?? 0
        visitors = try container.decodeIfPresent(Int64.self, forKey: .visitors) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(centre, forKey: .centre)
        if residents != 0 { try container.encode(residents, forKey: .residents) }
        if jobs != 0 { try container.encode(jobs, forKey: .jobs) }
        if buildingCost != .zero { try container.encode(buildingCost, forKey: .buildingCost) }
        if landCost != .zero { try container.encode(landCost, forKey: .landCost) }
        if books != SubsidiaryBooks() { try container.encode(books, forKey: .books) }
        if look != 0 { try container.encode(look, forKey: .look) }
        if visitors != 0 { try container.encode(visitors, forKey: .visitors) }
    }
}
