import GameCore

// The network tool's plans written out for the command log (ARCHITECTURE
// decision 193, later): the X crossover, the platform track beside a
// platform and the levelling of a platform's stretch. Each is worked out
// from the tool's picks on screen, so the command keeps the plan itself and
// its replay builds it again. Nodes and edges are written as their numbers,
// places on an edge as the edge's number and the distance along it; curves,
// profiles, structures and platforms with GameCore's own coding.

/// A place on an edge as the log writes it.
private struct EdgePlace: Codable {
    let edge: Int
    let distance: Int64

    init(_ point: NetworkEdgePoint) {
        edge = point.edge.number
        distance = point.distance
    }

    var point: NetworkEdgePoint {
        NetworkEdgePoint(edge: .edge(edge), distance: distance)
    }
}

extension ScissorsPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case places, positions, middle, halves
    }

    private struct HalfRecord: Codable {
        let from: Int
        let curve: TrackCurve
        let to: Int
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let places = try container.decode([EdgePlace].self, forKey: .places)
        let positions = try container.decode([WorldCoordinate].self, forKey: .positions)
        guard places.count == positions.count else {
            throw DecodingError.dataCorruptedError(forKey: .positions, in: container, debugDescription: "A position for each place.")
        }
        self.places = zip(places, positions).map { Place(point: $0.point, position: $1) }
        middle = try container.decode(WorldCoordinate.self, forKey: .middle)
        halves = try container.decode([HalfRecord].self, forKey: .halves).map { Half(from: $0.from, curve: $0.curve, to: $0.to) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(places.map { EdgePlace($0.point) }, forKey: .places)
        try container.encode(places.map(\.position), forKey: .positions)
        try container.encode(middle, forKey: .middle)
        try container.encode(halves.map { HalfRecord(from: $0.from, curve: $0.curve, to: $0.to) }, forKey: .halves)
    }
}

extension PlatformTrackTurnout: Codable {
    private enum CodingKeys: String, CodingKey {
        case node, point, position, leaving
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        node = try container.decodeIfPresent(Int.self, forKey: .node).map(TrackNodeID.node)
        point = try container.decodeIfPresent(EdgePlace.self, forKey: .point)?.point
        position = try container.decode(WorldCoordinate.self, forKey: .position)
        let leaving = try container.decode([Int64].self, forKey: .leaving)
        guard leaving.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .leaving, in: container, debugDescription: "A way is dx and dy.")
        }
        self.leaving = PlanVector(dx: leaving[0], dy: leaving[1])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if case .node(let number)? = node { try container.encode(number, forKey: .node) }
        try container.encodeIfPresent(point.map(EdgePlace.init), forKey: .point)
        try container.encode(position, forKey: .position)
        try container.encode([leaving.dx, leaving.dy], forKey: .leaving)
    }
}

extension PlatformTrackPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case platform, near, far, beside, curves, structure
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(TrackPlatform.self, forKey: .platform)
        near = try container.decode(PlatformTrackTurnout.self, forKey: .near)
        far = try container.decode(PlatformTrackTurnout.self, forKey: .far)
        let beside = try container.decode([WorldCoordinate].self, forKey: .beside)
        let curves = try container.decode([TrackCurve].self, forKey: .curves)
        guard beside.count == 2, curves.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .curves, in: container, debugDescription: "Two nodes beside and three curves.")
        }
        self.beside = Beside(near: beside[0], far: beside[1])
        self.curves = Curves(out: curves[0], along: curves[1], back: curves[2])
        structure = try container.decode(TrackStructure.self, forKey: .structure)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(near, forKey: .near)
        try container.encode(far, forKey: .far)
        try container.encode([beside.near, beside.far], forKey: .beside)
        try container.encode([curves.out, curves.along, curves.back], forKey: .curves)
        try container.encode(structure, forKey: .structure)
    }
}

extension PlatformLevelling: Codable {
    private enum CodingKeys: String, CodingKey {
        case edge, start, end, legs, stretchStart, stretchEnd, structure, levelLeg
    }

    private struct LegRecord: Codable {
        let from: WorldCoordinate
        let to: WorldCoordinate
        let curve: TrackCurve
        let profile: TrackProfile
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        edge = .edge(try container.decode(Int.self, forKey: .edge))
        start = try container.decode(Int64.self, forKey: .start)
        end = try container.decode(Int64.self, forKey: .end)
        legs = try container.decode([LegRecord].self, forKey: .legs).map { Leg(from: $0.from, to: $0.to, curve: $0.curve, profile: $0.profile) }
        stretchStart = try container.decodeIfPresent(WorldCoordinate.self, forKey: .stretchStart)
        stretchEnd = try container.decodeIfPresent(WorldCoordinate.self, forKey: .stretchEnd)
        structure = try container.decode(TrackStructure.self, forKey: .structure)
        levelLeg = try container.decode(Int.self, forKey: .levelLeg)
        guard legs.indices.contains(levelLeg) else {
            throw DecodingError.dataCorruptedError(forKey: .levelLeg, in: container, debugDescription: "The level leg is one of the legs.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edge.number, forKey: .edge)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(legs.map { LegRecord(from: $0.from, to: $0.to, curve: $0.curve, profile: $0.profile) }, forKey: .legs)
        try container.encodeIfPresent(stretchStart, forKey: .stretchStart)
        try container.encodeIfPresent(stretchEnd, forKey: .stretchEnd)
        try container.encode(structure, forKey: .structure)
        try container.encode(levelLeg, forKey: .levelLeg)
    }
}

extension PassingLoopPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case edge, start, end, stretch, near, far, beside, curves, structure, name, station
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        edge = .edge(try container.decode(Int.self, forKey: .edge))
        start = try container.decode(Int64.self, forKey: .start)
        end = try container.decode(Int64.self, forKey: .end)
        let stretch = try container.decode([WorldCoordinate].self, forKey: .stretch)
        near = try container.decode(PlatformTrackTurnout.self, forKey: .near)
        far = try container.decode(PlatformTrackTurnout.self, forKey: .far)
        let beside = try container.decode([WorldCoordinate].self, forKey: .beside)
        let curves = try container.decode([TrackCurve].self, forKey: .curves)
        guard stretch.count == 2, beside.count == 2, curves.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .curves, in: container, debugDescription: "Two ends of the stretch, two nodes beside and three curves.")
        }
        stretchStart = stretch[0]
        stretchEnd = stretch[1]
        self.beside = PlatformTrackPlan.Beside(near: beside[0], far: beside[1])
        self.curves = PlatformTrackPlan.Curves(out: curves[0], along: curves[1], back: curves[2])
        structure = try container.decode(TrackStructure.self, forKey: .structure)
        name = try container.decode(String.self, forKey: .name)
        let station = try container.decode([Int64].self, forKey: .station)
        guard station.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .station, in: container, debugDescription: "A point is x and y.")
        }
        self.station = PlanPoint(x: station[0], y: station[1])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edge.number, forKey: .edge)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode([stretchStart, stretchEnd], forKey: .stretch)
        try container.encode(near, forKey: .near)
        try container.encode(far, forKey: .far)
        try container.encode([beside.near, beside.far], forKey: .beside)
        try container.encode([curves.out, curves.along, curves.back], forKey: .curves)
        try container.encode(structure, forKey: .structure)
        try container.encode(name, forKey: .name)
        try container.encode([station.x, station.y], forKey: .station)
    }
}
