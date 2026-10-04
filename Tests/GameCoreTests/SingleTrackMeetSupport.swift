import GameCore

/// A 512 m single track with a passing loop at M. The main platform lies
/// well clear of both junctions; the longer curved track has its own berth.
/// Both directions prefer e2 in the absence of other trains.
enum SingleTrackMeet {
    static let costs = ConstructionCosts(track: 10, station: 1_000, train: 500)
    static let west = StationID(rawValue: 1)
    static let middle = StationID(rawValue: 2)
    static let east = StationID(rawValue: 3)
    static func forward(_ edge: Int) -> TrackTraversal { .init(edge: .edge(edge), direction: .forward) }
    static func backward(_ edge: Int) -> TrackTraversal { .init(edge: .edge(edge), direction: .backward) }

    /// The nodes, every coordinate `scale` times the 512 m layout's, the
    /// loop `loop` (scaled) beside the main track.
    static func points(scale: Int64 = 1, loop: Int64 = 2_048) -> [WorldCoordinate] {
        [(1_024, 4_096), (9_216, 4_096), (25_600, 4_096), (33_792, 4_096), (13_312, 4_096 + loop), (21_504, 4_096 + loop)]
            .map { WorldCoordinate(x: $0.0 * scale, y: $0.1 * scale) }
    }

    static func curves(scale: Int64 = 1, loop: Int64 = 2_048) -> (entrance: TrackCurve, exit: TrackCurve) {
        (.cubic(.init(x: 11_264 * scale, y: 4_096 * scale), .init(x: 11_264 * scale, y: (4_096 + loop) * scale)),
         .cubic(.init(x: 23_552 * scale, y: (4_096 + loop) * scale), .init(x: 23_552 * scale, y: 4_096 * scale)))
    }

    /// The platforms, scaled: station, edge, start, end.
    static func platforms(scale: Int64 = 1) -> [(StationID, Int, Int64, Int64)] {
        [(west, 1, 1_024, 3_072), (middle, 2, 7_168, 9_216), (middle, 5, 3_072, 5_120), (east, 3, 5_120, 7_168)]
            .map { ($0.0, $0.1, $0.2 * scale, $0.3 * scale) }
    }

    static func world(scale: Int64 = 1, loop: Int64 = 2_048) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864 * scale, height: (10_240 + loop) * scale), economy: GameEconomy(balance: 1_000_000, costs: costs), clock: GameClock(speed: .normal))
        for point in points(scale: scale, loop: loop) { _ = try world.buildTrackNode(at: point) }
        let (entrance, exit) = curves(scale: scale, loop: loop)
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: entrance)
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6))
        _ = try world.buildTrackEdge(from: .node(6), to: .node(3), curve: exit)
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x * scale, y: 8_192 * scale))
        }
        for (station, edge, start, end) in platforms(scale: scale) {
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: end)
        }
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
    static func model(scale: Int64 = 1, loop: Int64 = 2_048) -> ReferenceWorld {
        var model = ReferenceWorld(width: 36_864 * scale, height: (10_240 + loop) * scale, balance: 1_000_000, costs: costs, seconds: 0, speed: .normal)
        for point in points(scale: scale, loop: loop) { precondition(model.buildNetworkNode(at: point) == nil) }
        let (entrance, exit) = curves(scale: scale, loop: loop)
        for edge in 1...3 { precondition(model.buildNetworkEdge(from: .node(edge), to: .node(edge + 1), curve: .straight) == nil) }
        precondition(model.buildNetworkEdge(from: .node(2), to: .node(5), curve: entrance) == nil)
        precondition(model.buildNetworkEdge(from: .node(5), to: .node(6), curve: .straight) == nil)
        precondition(model.buildNetworkEdge(from: .node(6), to: .node(3), curve: exit) == nil)
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            precondition(model.buildStation(named: name, at: PlanPoint(x: x * scale, y: 8_192 * scale)) == nil)
        }
        for (station, edge, start, end) in platforms(scale: scale) {
            precondition(model.addTrackPlatform(station, on: .edge(edge), from: start, to: end) == nil)
        }
        return model
    }
}
