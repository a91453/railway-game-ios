import GameCore

extension GameWorld {
    /// The world a new game starts with: a map ``newGameMapSize`` tiles a
    /// side, running at 600× (`normal`), with traffic control on (Phase 4.6
    /// Stage T): trains take their whole route before they leave, and a
    /// managed company (G1c) in a city whose fare baseline is the standard
    /// fare. GameCore's own new worlds start with both off and the
    /// reference's default city.
    public static func newGame() -> GameWorld {
        do {
            var world = try GameWorld(
                width: newGameMapSize,
                height: newGameMapSize,
                economy: GameEconomy(balance: startingBalance, costs: .newGame),
                clock: GameClock(speed: .normal)
            )
            try world.setTrafficControl(true)
            // G1c: a new game is a managed company, so fares are charged
            // and running costs settled.
            world.setEconomyMode(.management)
            // The city's passengers think the standard fare fair (decision
            // 46): trips pay it until the player sets fares, and setting
            // the same fare keeps their demand.
            try world.setFareBaseline(FareRules.standardFare)
            return world
        } catch {
            // The size is a constant within GridMap's limits and an empty
            // world has no trains to share track, so failing here is a
            // programming error.
            preconditionFailure("Could not create the new-game world: \(error)")
        }
    }

    /// A new game's map, tiles a side (Stage E1): the most a map may have,
    /// 1024 tiles of 16 m, about 16 km, so lines kilometres long have room
    /// to speed up and slow down. Saves of games begun before E1 keep their
    /// 32 × 24 tiles.
    public static let newGameMapSize = GridMap.maximumSideLength

    /// What a new game starts with: $3,000,000, a first line and some to
    /// spare (ARCHITECTURE decision 46; the reference's starting cash is in
    /// its economy engine, which its snapshot does not have).
    public static let startingBalance: Money = 300_000_000
}

extension ConstructionCosts {
    /// A new game's prices (ARCHITECTURE decision 46), set so a first line
    /// pays for itself in about ten days of its fares less its running
    /// costs: about $35,000 a day for each station of the city's ridership
    /// at the standard fare. Track is $100,000 a kilometre on the ground
    /// (times 3 on a viaduct, 4 on a bridge, 5 in a tunnel), a station
    /// $200,000, a train $150,000 with its first car and each car added
    /// $40,000. The reference prices building in quotas, from its economy
    /// engine, which its snapshot does not have.
    public static let newGame = ConstructionCosts(track: 160_000, station: 20_000_000, train: 15_000_000, car: 4_000_000)
}

/// A small prebuilt network for trying the game and testing it on a
/// device (Stage C4): a new game with two lines already running, built only
/// on the track network, as the app builds since Stage F1.
///
/// Not a shortcut: it starts from ``GameWorld/newGame()`` and builds
/// everything with ordinary `GameWorld` commands that charge their usual
/// costs.
///
/// - Line 1 runs on the ground from West through Central to East.
/// - Line 2 runs on a viaduct 8 m up from North through Central to South,
///   over Line 1, so the two never share track; Central has a platform on
///   each, one station at a point with two platforms.
/// - Each line has one four-car train, runs all day, and every station has
///   ridership, so passengers, fares and costs start at once.
/// - It stands in the middle of the map (Stage E1), with room to build on
///   every side.
public enum DemoWorld {
    public static func make(in language: DisplayLanguage) -> GameWorld {
        var world = GameWorld.newGame()
        do throws(GameError) {
            try build(in: &world, language: language)
        } catch {
            preconditionFailure("The demo map no longer builds: \(error)")
        }
        return world
    }

    private static let tile = WorldCoordinate.tileSize
    private static let cars = 4
    /// The ring's radius and how far Lines 1 and 2 reach from Central, in
    /// tiles: the lines end three tiles inside the ring, so no track
    /// crosses another at its height.
    private static let ringRadius: Int64 = 20
    private static let reach: Int64 = 17

    private static func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
        let platform = Int64(cars) * Train.carLength
        // Central, the middle of the map: the demo is built around it.
        let cx = Int64(world.map.width / 2) * tile, cy = Int64(world.map.height / 2) * tile
        let span = 2 * reach * tile
        // Line 1: west to east through Central, on the ground.
        let west = try world.buildTrackNode(at: WorldCoordinate(x: cx - reach * tile, y: cy))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: cx + reach * tile, y: cy))
        let ground = try world.buildTrackEdge(from: west, to: east)
        // Line 2: north to south through Central, 8 m up all the way.
        let height: Int64 = 512
        let north = try world.buildTrackNode(at: WorldCoordinate(x: cx, y: cy - reach * tile, z: height))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: cx, y: cy + reach * tile, z: height))
        let viaduct = try world.buildTrackEdge(from: north, to: south, structure: .elevated)
        // The ring: a circle round Central on the ground, four quarter arcs
        // between nodes on the diagonals, each a cubic Bézier with handles
        // 4/3 (√2 − 1) of the radius long along the circle (square roots
        // only, exact in IEEE arithmetic, so every platform builds it the
        // same). Clockwise on the map: the arc through North, then East,
        // South and West.
        let radius = Double(ringRadius * tile)
        let d = radius / 2.0.squareRoot()
        let m = 4.0 / 3.0 * (2.0.squareRoot() - 1) * radius / 2.0.squareRoot()
        func plan(_ x: Double, _ y: Double) -> PlanPoint {
            PlanPoint(x: cx + Int64(x.rounded()), y: cy + Int64(y.rounded()))
        }
        let corners = [plan(-d, -d), plan(d, -d), plan(d, d), plan(-d, d)]
        var ringNodes: [TrackNodeID] = []
        for corner in corners {
            ringNodes.append(try world.buildTrackNode(at: WorldCoordinate(x: corner.x, y: corner.y)))
        }
        let handles = [
            (plan(-d + m, -d - m), plan(d - m, -d - m)),
            (plan(d + m, -d + m), plan(d + m, d - m)),
            (plan(d - m, d + m), plan(-d + m, d + m)),
            (plan(-d - m, d - m), plan(-d - m, -d + m)),
        ]
        var ring: [TrackEdgeID] = []
        for (index, handle) in handles.enumerated() {
            ring.append(try world.buildTrackEdge(from: ringNodes[index], to: ringNodes[(index + 1) % 4], curve: .cubic(handle.0, handle.1)))
        }

        let names = language == .english
            ? ["West", "Central", "East", "North", "South"]
            : ["西站", "中央", "東站", "北站", "南站"]
        // Each station stands at the middle of its first platform on Line 1
        // or 2.
        func station(_ name: String, at x: Int64, _ y: Int64) throws(GameError) -> StationID {
            try world.buildStation(named: name, at: PlanPoint(x: x, y: y)).id
        }
        let first = reach * tile - tile - platform / 2
        let westStation = try station(names[0], at: cx - first, cy)
        let central = try station(names[1], at: cx, cy)
        let eastStation = try station(names[2], at: cx + first, cy)
        let northStation = try station(names[3], at: cx, cy - first)
        let southStation = try station(names[4], at: cx, cy + first)
        // Offsets along each edge, measured from its first node.
        for (edge, stations) in [(ground, (westStation, eastStation)), (viaduct, (northStation, southStation))] {
            try world.addTrackPlatform(stations.0, on: edge, from: tile, to: tile + platform)
            try world.addTrackPlatform(central, on: edge, from: span / 2 - platform / 2, to: span / 2 + platform / 2)
            try world.addTrackPlatform(stations.1, on: edge, from: span - tile - platform, to: span - tile)
        }
        // The ring calls at the four ends, each a platform in the middle of
        // its arc: two levels at North and South, two tracks side by side
        // at West and East.
        for (edge, id) in zip(ring, [northStation, eastStation, southStation, westStation]) {
            guard let length = world.network.edge(edge)?.length else { continue }
            try world.addTrackPlatform(id, on: edge, from: length / 2 - platform / 2, to: length / 2 + platform / 2)
        }

        let demands: [(StationID, StationDemandKind, Int64)] = [
            (westStation, .residential, 20_000),
            (central, .office, 30_000),
            (eastStation, .shopping, 10_000),
            (northStation, .residential, 15_000),
            (southStation, .scenic, 5_000),
        ]
        for (id, kind, trips) in demands {
            try world.setStationDemand(id, to: StationDemand(kind: kind, dailyTrips: trips))
        }

        let lines = language == .english ? ["Line 1", "Line 2"] : ["1 號線", "2 號線"]
        let trains = language == .english ? ["Train 1", "Train 2"] : ["列車 1", "列車 2"]
        let services: [(name: String, train: String, stops: [StationID], edge: TrackEdgeID, berth: Int64)] = [
            (lines[0], trains[0], [westStation, central, eastStation], ground, tile + platform),
            (lines[1], trains[1], [northStation, central, southStation], viaduct, tile + platform),
        ]
        for service in services {
            let line = try world.createLine(named: service.name, stops: service.stops).id
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
            // The train waits at the line's first platform, its head at the
            // platform's far end, and the line sends it out.
            let train = try world.purchaseTrain(named: service.train).id
            try world.setTrainCars(train, to: cars)
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: service.edge, direction: .forward), offset: service.berth))
            try world.setTrainContinuation(train, along: [], stoppingAt: service.berth)
            try world.setTrainMovementRate(train, to: 512)
            try world.assignTrain(train, to: line)
        }
    }
}
