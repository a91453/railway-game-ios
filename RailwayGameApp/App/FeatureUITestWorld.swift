#if DEBUG
import GameCore
import GamePresentation

/// Small worlds for decisions 284–286's UI tests. The app only asks for
/// these under -ui-testing, writes them into its cleared temporary save
/// library, and loads them through the ordinary save reader. No fixtures
/// or player saves are changed. Assertions belong to the UI tests.
@MainActor
enum FeatureUITestWorld {
    static func make(_ name: String) throws -> GameWorld {
        guard ["separate-tracks", "missing-platform", "double-platform", "catalog", "sightseeing"].contains(name) else {
            preconditionFailure("Unknown -ui-test-world: \(name)")
        }
        let bounds = try WorldBounds(width: 40_960, height: 20_480)
        let builder = GameSession(world: GameWorld(bounds: bounds, economy: GameEconomy(balance: 100_000_000),
                                                  clock: GameClock(speed: .paused)))
        builder.selectTool(.network)
        builder.networkBuildsDouble = true
        builder.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        builder.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        builder.buildNetworkTrack()
        guard builder.message?.kind == .success else {
            preconditionFailure("Could not build UI test tracks: \(builder.message?.text ?? "")")
        }
        var world = builder.world
        // Decision 284 needs the old one-platform-per-track arrangement,
        // built through GameWorld commands, not the tool decision 285 fixes.
        let west = try world.buildStation(named: "海岸", at: PlanPoint(x: 6_144, y: 10_240)).id
        if name == "double-platform" { return world }
        let eastY: Int64 = name == "separate-tracks" ? 9_920 : 10_240
        let east = try world.buildStation(named: "山邊", at: PlanPoint(x: 30_720, y: eastY)).id
        try addPlatform(to: west, at: PlanPoint(x: 6_144, y: 10_240), in: &world)
        if name != "missing-platform" {
            try addPlatform(to: east, at: PlanPoint(x: 30_720, y: eastY), in: &world)
        }
        if name == "catalog" || name == "sightseeing" {
            world.setTourism([
                Attraction(id: AttractionID(rawValue: 1), name: "海岸老街", englishName: "Coastal Old Street",
                           point: PlanPoint(x: 30_720, y: 14_336), kind: .town, baseStars: 350),
            ])
            let line = try world.createLine(named: "海岸線", stops: [west, east]).id
            if name == "sightseeing" {
                let train = try world.purchaseTrain(named: "藍皮解憂號").id
                try world.setTrainType(train, to: .blueTrain)
                try world.assignTrain(train, to: line)
            }
        }
        return world
    }

    private static func addPlatform(to station: StationID, at point: PlanPoint, in world: inout GameWorld) throws {
        guard let site = world.trackEdgePoint(near: point, within: 64) else {
            preconditionFailure("No track at UI test platform")
        }
        try world.addTrackPlatform(station, on: site.edge, from: site.distance - 2_048, to: site.distance + 2_048)
    }
}
#endif
