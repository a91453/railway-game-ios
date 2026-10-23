#if DEBUG
import GameCore
import GamePresentation

/// Small worlds for decisions 284–286's and 305's UI tests. The app only asks for
/// these under -ui-testing, writes them into its cleared temporary save
/// library, and loads them through the ordinary save reader. No fixtures
/// or player saves are changed. Assertions belong to the UI tests.
@MainActor
enum FeatureUITestWorld {
    static func make(_ name: String) throws -> GameWorld {
        if name == "big-grid" || name == "big-grid-night" { return try bigGrid(night: name == "big-grid-night") }
        if name == "story" { return try story() }
        guard ["separate-tracks", "missing-platform", "double-platform", "catalog", "sightseeing", "quiet-night"].contains(name) else {
            preconditionFailure("Unknown -ui-test-world: \(name)")
        }
        let bounds = try WorldBounds(width: 40_960, height: 20_480)
        // Decision 305's night: 01:00, running, until a 06:00 first train.
        let clock = name == "quiet-night" ? GameClock(now: GameTime(minutes: 60), speed: .normal) : GameClock(speed: .paused)
        let builder = GameSession(world: GameWorld(bounds: bounds, economy: GameEconomy(balance: 100_000_000),
                                                  clock: clock))
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
        if name == "quiet-night" {
            // One train standing at 海岸 on a line open 06:00–20:00, as
            // NightSkipTests' full-size line.
            let line = try world.createLine(named: "海岸線", stops: [west, east]).id
            try world.setLineServiceWindow(line, to: .hours(open: 360, close: 1200))
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
            let train = try world.purchaseTrain(named: "海岸1號").id
            guard let site = world.trackEdgePoint(near: PlanPoint(x: 6_144, y: 10_240), within: 64) else {
                preconditionFailure("No track at the UI test train")
            }
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: site.edge, direction: .forward), offset: site.distance))
            try world.setTrainContinuation(train, along: [], stoppingAt: site.distance)
            try world.setTrainMovementRate(train, to: 512)
            try world.assignTrain(train, to: line)
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

    /// Decision 371's map for timing the flat map: a new game with four
    /// lines of eleven stations each (44 stations, a train on each line,
    /// traffic control on), running at 1× from 08:00, or at the opening
    /// speed from 20:30 (`night`).
    private static func bigGrid(night: Bool) throws -> GameWorld {
        let metre = WorldCoordinate.unitsPerMetre
        var world = GameWorld.newGame(balance: 1_000_000_000)
        // The fourth line cost more than a new game has (the launch crashed
        // in run 39886381587); the map is for timing, not for money.
        world.setUnlimitedFunds(true)
        for line in 0..<4 {
            let y = 8_000 * metre + Int64(line - 2) * 1_500 * metre
            let points = (0..<11).map { PlanPoint(x: 3_000 * metre + Int64($0) * 700 * metre, y: y) }
            world = try LineBuilder.line(through: points, in: world)
        }
        // On from the opening 00:00 to the morning or the evening, ten
        // minutes a tick.
        world.setSpeed(.fast)
        try world.advance(ticks: night ? 123 : 48)
        world.setSpeed(night ? .normal : .x1)
        return world
    }

    /// Decision 387's story card: the Pingxi challenge on a small map, its
    /// first beat due at the next midnight, some 12 seconds away at the
    /// speed it runs at (ten game minutes a second), so the card shows soon
    /// after the game opens but not before it is watched.
    private static func story() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 1)
        world.setDisruptions(nil)
        world.setCityRequests(seed: nil)
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        let shifen = try world.buildStation(named: "十分", at: middle).id
        let pingxi = try world.buildStation(named: "平溪", at: PlanPoint(x: middle.x + 64_000, y: middle.y)).id
        let line = try world.createLine(named: "平溪線", stops: [shifen, pingxi]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line, pattern: nil)
        try world.startScenario(Scenario(
            id: Challenge.pingxi.id, goals: [.dailyRiders(80_000), .annualNetProfit(Money(200_000_000))],
            goldDays: 360, silverDays: 720, deadlineDays: 1_080, insolvencyDays: 60
        ))
        // On to 22:00 of the challenge's first day, a minute a tick.
        world.setSpeed(.normal)
        try world.advance(ticks: Int(1_440 + 22 * 60 - world.clock.now.seconds / 60))
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
