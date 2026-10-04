import GameCore

/// Double track with one crossover before M and none after M.
/// Inputs from the review reproduction; model geometry is independent.
enum DoubleTrackCrossover {
    static let west = StationID(rawValue: 1)
    static let middle = StationID(rawValue: 2)
    static let east = StationID(rawValue: 3)
    static let outer = StationID(rawValue: 4)

    static func world(extended: Bool = false) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: extended ? 53_248 : 45_056, height: 12_288), economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 10, station: 1_000, train: 500)), clock: GameClock(speed: .normal))
        let points: [(Int64, Int64)] = [(1_024, 4_096), (9_216, 4_096), (40_960, 4_096), (1_024, 6_144), (13_312, 6_144), (extended ? 30_720 : 40_960, 6_144)] + (extended ? [(40_960, 6_144), (51_200, 6_144)] : [])
        for (x, y) in points {
            _ = try world.buildTrackNode(at: .init(x: x, y: y))
        }
        _ = try world.buildTrackEdge(from: .node(1), to: .node(2)) // e1: A at W
        _ = try world.buildTrackEdge(from: .node(2), to: .node(3)) // e2: A, 31744
        _ = try world.buildTrackEdge(from: .node(4), to: .node(5)) // e3: B at W
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6)) // e4: B, 27648
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: .cubic(.init(x: 11_264, y: 4_096), .init(x: 11_264, y: 6_144))) // e5: crossover
        if extended {
            _ = try world.buildTrackEdge(from: .node(6), to: .node(7))
            _ = try world.buildTrackEdge(from: .node(7), to: .node(8))
        }
        for (name, x) in [("W", Int64(3_072)), ("M", 21_504), ("E", 37_888)] + (extended ? [("Z", 46_080)] : []) {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 9_216))
        }
        try world.addTrackPlatform(Self.west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(Self.west, on: .edge(3), from: 1_024, to: 3_072)
        try world.addTrackPlatform(Self.middle, on: .edge(2), from: 11_264, to: 13_312)
        try world.addTrackPlatform(Self.middle, on: .edge(4), from: 7_168, to: 9_216)
        try world.addTrackPlatform(Self.east, on: .edge(2), from: 27_648, to: 29_696)
        try world.addTrackPlatform(Self.east, on: .edge(extended ? 6 : 4), from: extended ? 6_144 : 23_552, to: extended ? 8_192 : 25_600)
        if extended { try world.addTrackPlatform(Self.outer, on: .edge(7), from: 4_096, to: 6_144) }
        return world
    }

    static func stand(_ world: inout GameWorld, _ traversal: TrackTraversal, at offset: Int64) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(id, to: 1_024)
        return id
    }

    static func calls(_ calls: [(StationID, Int64)]) -> [ScheduledStop] {
        calls.map { ScheduledStop(station: $0.0, arrival: GameTime(seconds: $0.1), departure: GameTime(seconds: $0.1)) }
    }


    static func model(extended: Bool = false) -> ReferenceWorld {
        var model = ReferenceWorld(width: extended ? 53_248 : 45_056, height: 12_288, balance: 1_000_000, costs: ConstructionCosts(track: 10, station: 1_000, train: 500), seconds: 0, speed: .normal)
        let points: [(Int64, Int64)] = [(1_024, 4_096), (9_216, 4_096), (40_960, 4_096), (1_024, 6_144), (13_312, 6_144), (extended ? 30_720 : 40_960, 6_144)] + (extended ? [(40_960, 6_144), (51_200, 6_144)] : [])
        for (x, y) in points {
            precondition(model.buildNetworkNode(at: .init(x: x, y: y)) == nil)
        }
        for (a, b) in [(1, 2), (2, 3), (4, 5), (5, 6)] {
            precondition(model.buildNetworkEdge(from: .node(a), to: .node(b), curve: .straight) == nil)
        }
        precondition(model.buildNetworkEdge(from: .node(2), to: .node(5), curve: .cubic(.init(x: 11_264, y: 4_096), .init(x: 11_264, y: 6_144))) == nil)
        if extended {
            precondition(model.buildNetworkEdge(from: .node(6), to: .node(7), curve: .straight) == nil)
            precondition(model.buildNetworkEdge(from: .node(7), to: .node(8), curve: .straight) == nil)
        }
        for (name, x) in [("W", Int64(3_072)), ("M", 21_504), ("E", 37_888)] + (extended ? [("Z", 46_080)] : []) {
            precondition(model.buildStation(named: name, at: PlanPoint(x: x, y: 9_216)) == nil)
        }
        for (station, edge, from, to) in [(west, 1, Int64(1_024), Int64(3_072)), (west, 3, 1_024, 3_072), (middle, 2, 11_264, 13_312), (middle, 4, 7_168, 9_216), (east, 2, 27_648, 29_696), (east, extended ? 6 : 4, extended ? 6_144 : 23_552, extended ? 8_192 : 25_600)] + (extended ? [(outer, 7, 4_096, 6_144)] : []) {
            precondition(model.addTrackPlatform(station, on: .edge(edge), from: from, to: to) == nil)
        }
        return model
    }
}
