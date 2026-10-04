import GameCore

/// A 512 m single track with a passing loop at M. The main platform lies
/// well clear of both junctions; the longer curved track has its own berth.
/// Both directions prefer e2 in the absence of other trains.
enum SingleTrackMeet {
    static let costs = ConstructionCosts(track: 10, station: 1_000, train: 500)
    static let points: [WorldCoordinate] = [
        .init(x: 1_024, y: 4_096), .init(x: 9_216, y: 4_096),
        .init(x: 25_600, y: 4_096), .init(x: 33_792, y: 4_096),
        .init(x: 13_312, y: 6_144), .init(x: 21_504, y: 6_144),
    ]
    static let entrance = TrackCurve.cubic(.init(x: 11_264, y: 4_096), .init(x: 11_264, y: 6_144))
    static let exit = TrackCurve.cubic(.init(x: 23_552, y: 6_144), .init(x: 23_552, y: 4_096))
    static let west = StationID(rawValue: 1)
    static let middle = StationID(rawValue: 2)
    static let east = StationID(rawValue: 3)
    static func forward(_ edge: Int) -> TrackTraversal { .init(edge: .edge(edge), direction: .forward) }
    static func backward(_ edge: Int) -> TrackTraversal { .init(edge: .edge(edge), direction: .backward) }

    static func world() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864, height: 12_288), economy: GameEconomy(balance: 1_000_000, costs: costs), clock: GameClock(speed: .normal))
        for point in points { _ = try world.buildTrackNode(at: point) }
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: entrance)
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6))
        _ = try world.buildTrackEdge(from: .node(6), to: .node(3), curve: exit)
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(middle, on: .edge(2), from: 7_168, to: 9_216)
        try world.addTrackPlatform(middle, on: .edge(5), from: 3_072, to: 5_120)
        try world.addTrackPlatform(east, on: .edge(3), from: 5_120, to: 7_168)
        return world
    }

    static func stand(_ world: inout GameWorld, edge: TrackTraversal, offset: Int64, cars: Int = 2) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: cars)
        try world.placeTrain(id, at: .onEdge(edge, offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(id, to: 1_024)
        return id
    }

    static func timetable(eastbound: Bool, delay: Int64 = 0) -> [ScheduledStop] {
        [eastbound ? west : east, middle, eastbound ? east : west].enumerated().map { index, station in
            ScheduledStop(station: station, arrival: GameTime(seconds: delay + Int64(index) * 120), departure: GameTime(seconds: delay + Int64(index) * 120))
        }
    }
}

extension SingleTrackMeet {
    static func model() -> ReferenceWorld {
        var model = ReferenceWorld(width: 36_864, height: 12_288, balance: 1_000_000, costs: costs, seconds: 0, speed: .normal)
        for point in points { precondition(model.buildNetworkNode(at: point) == nil) }
        for edge in 1...3 { precondition(model.buildNetworkEdge(from: .node(edge), to: .node(edge + 1), curve: .straight) == nil) }
        precondition(model.buildNetworkEdge(from: .node(2), to: .node(5), curve: entrance) == nil)
        precondition(model.buildNetworkEdge(from: .node(5), to: .node(6), curve: .straight) == nil)
        precondition(model.buildNetworkEdge(from: .node(6), to: .node(3), curve: exit) == nil)
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            precondition(model.buildStation(named: name, at: PlanPoint(x: x, y: 8_192)) == nil)
        }
        for (station, edge, start, end) in [(west, 1, Int64(1_024), Int64(3_072)), (middle, 2, 7_168, 9_216), (middle, 5, 3_072, 5_120), (east, 3, 5_120, 7_168)] {
            precondition(model.addTrackPlatform(station, on: .edge(edge), from: start, to: end) == nil)
        }
        return model
    }
}
