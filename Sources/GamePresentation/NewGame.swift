import GameCore

extension GameWorld {
    /// The world a new game starts with: `bounds`, ``newGameBounds``
    /// (16.384 km a side) but for the whole of Taiwan (decision 88),
    /// running at 600× (`normal`), with traffic control on (Phase 4.6
    /// Stage T): trains take their whole route before they leave, a
    /// managed company (G1c) in a city whose fare baseline is the standard
    /// fare, and passengers routed over the whole network (Phase 5F).
    /// GameCore's own new worlds start with all three off and the
    /// reference's default city.
    ///
    /// A blank map, or with `anchor` a real-world map with its middle there
    /// (Stage E2): the same game either way, laid over the Earth or not.
    /// It starts with `balance`: ``startingBalance`` but for a game that
    /// comes with its railway built (``RealWorldDemo``).
    ///
    /// Its demand events (item 4) are drawn from `eventSeed`: the app's
    /// new games pass a random one, so each game has its own events.
    ///
    /// Its land (Phase 6a, ARCHITECTURE decision 72) is `land`, a
    /// real-world map's people (``LandImport``), or without it the towns
    /// ``Land/towns(seed:in:)`` draws from `eventSeed`: a blank map, or a
    /// real-world one where the app has no people. Its city's buildings
    /// (Phase 6c-1, ARCHITECTURE decision 74) stand on that land.
    ///
    /// Its pairs' trips keep a share by their distance, and the stations by
    /// its edge are outside connections (decision 137), but for the whole
    /// of Taiwan.
    ///
    /// Its `water` (decision 105) is a real-world map's sea, rivers and
    /// lakes (``WaterGrid``), under which there is no land, and its `steep`
    /// slopes (decision 115), where nothing new is built; a blank map has
    /// neither.
    public static func newGame(
        anchor: GeoAnchor? = nil, bounds: WorldBounds = newGameBounds, balance: Money = startingBalance, eventSeed: UInt32 = 1,
        land: [LandCell]? = nil, water: [CellPosition] = [], steep: [CellPosition] = []
    ) -> GameWorld {
        do {
            var world = GameWorld(
                bounds: bounds,
                economy: GameEconomy(balance: balance, costs: .newGame),
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
            // Phase 5F: passengers choose a route over the whole network,
            // changing trains at a station or walking to one near by
            // (the reference's global OD paths). Saves of earlier games
            // keep their direct trips.
            world.setPassengerRoutingMode(.network)
            // Item 4: weekdays and weekends differ, as the reference's
            // weekday factors and weekend hours.
            world.setWeeklyDemand(true)
            // Item 4: exhibitions and crowd surges raise a station's demand
            // for some days, announced days ahead.
            world.setDemandEvents(seed: eventSeed)
            // Item 5: the towns round well-served stations grow.
            world.setTownGrowth(true)
            world.setGeoAnchor(anchor)
            // Decision 105: the ground first, then the city on it.
            try world.setWater(water)
            try world.setSteep(steep)
            // Phase 6a: the city the railway serves.
            if let land {
                try world.setLand(land)
            } else {
                world.foundTowns(seed: eventSeed)
            }
            // Decision 137: short trips walk, and the stations by the map's
            // edge bring the towns beyond it, but for the whole of Taiwan,
            // whose edge is the sea.
            world.setDistanceDemand(true)
            world.setOutsideConnections(bounds != WholeTaiwan.bounds)
            // Phase 6b: its stations draw their ridership from it, and it
            // grows round the well-served ones.
            world.setLandDemand(true)
            // Phase 6c-1: the city's buildings stand on its land, each
            // holding so many residents and jobs.
            world.setCityBuildings(true)
            // Decision 139: the city keeps the mix of homes, shops and work
            // it starts with: what it is short of is in demand.
            world.setCityDemand(true)
            // Decision 142: a low town's buildings leave room for the
            // company's between them.
            world.setCityFootprints(true)
            return world
        } catch {
            // An empty world has no trains to share track, and land and
            // water come from ``LandImport`` and ``WaterGrid`` in this
            // world's bounds, the land off the water, so failing here is a
            // programming error.
            preconditionFailure("Could not create the new-game world: \(error)")
        }
    }

    /// A new game's world (Stage E1): 1,048,576 units (16.384 km) a side,
    /// the largest a world could be until decision 88, so lines kilometres
    /// long have room to speed up and slow down. Saves of games begun
    /// before E1 keep their 512 × 384 m. Only the whole of Taiwan is larger
    /// (``WholeTaiwan/bounds``).
    public static let newGameBounds = WorldBounds.standard

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
/// device (Stage C4): a new game with three lines already running, built
/// only on the track network, as the app builds since Stage F1.
///
/// Not a shortcut: it starts from ``GameWorld/newGame()`` and builds
/// everything with ordinary `GameWorld` commands that charge their usual
/// costs.
///
/// - Line 1 runs on the ground from West through Central to East.
/// - Line 2 runs on a viaduct 8 m up from North through Central to South,
///   over Line 1, so the two never share track; Central has a platform on
///   each, one station at a point with two platforms.
/// - The Ring Line (decision 49) runs round Central through West, North,
///   East and South, on two circles of track, one each way round, with a
///   platform on each at every station: North and South have Line 2's
///   platform above the ring's, West and East Line 1's beside them. Lines 1
///   and 2 end inside the ring, so no track crosses another at its height.
/// - Lines 1 and 2 have one four-car train each and the ring two two-car
///   trains, one each way; all run all day, so passengers, fares and costs
///   start at once. What is left of the starting money still builds the
///   tutorial's first line.
/// - Its stations draw their ridership from the land as a new game's do
///   (Phase 6b, ARCHITECTURE decision 78): a city round Central, larger
///   and denser than a new game's first town, which the demo's stations
///   share, so the network pays for itself in about eight days; the new
///   game's two outer towns are there to build to. The city grows round
///   the stations, and its buildings go up a density as they fill.
/// - Its pairs keep all their trips however near (decision 137): its
///   stations are a few hundred metres apart.
/// - Central is the middle of the map (Stage E1) and of what the demo
///   builds, so the map opens on it, with room to build on every side.
public enum DemoWorld {
    public static func make(in language: DisplayLanguage) -> GameWorld {
        var world = GameWorld.newGame()
        // Decision 137: the demo's stations stand a few hundred metres
        // apart to show the tools on one screen, so its pairs keep all their
        // trips, as before; nothing of it is by the map's edge.
        world.setDistanceDemand(false)
        world.setOutsideConnections(false)
        do throws(GameError) {
            try build(in: &world, language: language)
        } catch {
            preconditionFailure("The demo map no longer builds: \(error)")
        }
        return world
    }

    /// The demo's layout step: 1024 units, 16 m. Its distances are whole
    /// steps (the map's tiles when it was first laid out, Stage C4).
    private static let step: Int64 = 1_024
    private static let cars = 4
    private static let ringCars = 2
    /// The inner ring track's radius and how far Lines 1 and 2 reach from
    /// Central, in steps: the lines end three steps inside the ring, so no
    /// track crosses another at its height. The outer ring track is a step
    /// further out.
    private static let ringRadius: Int64 = 12
    private static let reach: Int64 = 9

    /// The demo's city (decision 78): a town of the new game's shape
    /// (ARCHITECTURE decision 72) round Central, reaching `cityRadius`
    /// cells (896 m) from its middle, so nearly every cell is within reach
    /// of a station, with `cityPeak` people in its middle cell.
    static let cityRadius: Int64 = 14
    static let cityPeak: Int64 = 600

    /// The demo's land: the city in place of the new game's first town,
    /// and the new game's other two towns, 2 km and more away, as they are.
    /// A cell `d` cells from the middle one has `cityPeak × (r² − d²) / r²`
    /// people, as in a new game's town. Its middle third is offices west
    /// of the middle column and shops from it east, each with a quarter of
    /// its people living there and three times as many working.
    static func land(replacingTheMiddleOf land: Land, in bounds: WorldBounds) -> [LandCell] {
        let middleRow = Int((bounds.height / 2) / Land.cellLength), middleColumn = Int((bounds.width / 2) / Land.cellLength)
        let squared = cityRadius * cityRadius
        func distance(_ row: Int, _ column: Int) -> Int64 {
            let dr = Int64(row - middleRow), dc = Int64(column - middleColumn)
            return dr * dr + dc * dc
        }
        var cells = land.cells.filter { distance($0.row, $0.column) >= squared }
        for dr in -cityRadius...cityRadius {
            for dc in -cityRadius...cityRadius {
                let row = middleRow + Int(dr), column = middleColumn + Int(dc)
                let d = distance(row, column)
                guard d < squared else { continue }
                var residents = cityPeak * ((squared - d) * 1_000 / squared) / 1_000
                var jobs: Int64 = 0
                var use = LandUse.residential
                if 9 * d < squared {
                    use = dc < 0 ? .office : .commercial
                    jobs = 3 * residents
                    residents /= 4
                }
                guard residents + jobs > 0 else { continue }
                cells.append(LandCell(row: row, column: column, use: use, residents: residents, jobs: jobs))
            }
        }
        return cells
    }

    private static func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
        // Decision 78: the demo's stations draw their ridership from its
        // city, as a new game's do.
        try world.setLand(land(replacingTheMiddleOf: world.land, in: world.bounds))
        let platform = Int64(cars) * Train.carLength
        let ringPlatform = Int64(ringCars) * Train.carLength
        // Central, the middle of the world: the demo is built around it.
        let cx = world.bounds.width / 2, cy = world.bounds.height / 2
        let span = 2 * reach * step
        // Line 1: west to east through Central, on the ground.
        let west = try world.buildTrackNode(at: WorldCoordinate(x: cx - reach * step, y: cy))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: cx + reach * step, y: cy))
        let ground = try world.buildTrackEdge(from: west, to: east)
        // Line 2: north to south through Central, 8 m up all the way.
        let height: Int64 = 512
        let north = try world.buildTrackNode(at: WorldCoordinate(x: cx, y: cy - reach * step, z: height))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: cx, y: cy + reach * step, z: height))
        let viaduct = try world.buildTrackEdge(from: north, to: south, structure: .elevated)
        // The ring: two circles round Central on the ground, one track each
        // way (the inner one the inner way round, clockwise on the map, the
        // outer one the outer way), never joined, so the two ways never
        // meet head on. Each is four quarter arcs between nodes on the
        // diagonals, each a cubic Bézier with handles 4/3 (√2 − 1) of the
        // radius long along the circle (square roots only, exact in IEEE
        // arithmetic, so every platform builds it the same), built
        // clockwise: the arc through North, then East, South and West.
        func plan(_ x: Double, _ y: Double) -> PlanPoint {
            PlanPoint(x: cx + Int64(x.rounded()), y: cy + Int64(y.rounded()))
        }
        func circle(radius steps: Int64) throws(GameError) -> [TrackEdgeID] {
            let radius = Double(steps * step)
            let d = radius / 2.0.squareRoot()
            let m = 4.0 / 3.0 * (2.0.squareRoot() - 1) * radius / 2.0.squareRoot()
            var nodes: [TrackNodeID] = []
            for corner in [plan(-d, -d), plan(d, -d), plan(d, d), plan(-d, d)] {
                nodes.append(try world.buildTrackNode(at: WorldCoordinate(x: corner.x, y: corner.y)))
            }
            let handles = [
                (plan(-d + m, -d - m), plan(d - m, -d - m)),
                (plan(d + m, -d + m), plan(d + m, d - m)),
                (plan(d - m, d + m), plan(-d + m, d + m)),
                (plan(-d - m, d - m), plan(-d - m, -d + m)),
            ]
            var edges: [TrackEdgeID] = []
            for (index, handle) in handles.enumerated() {
                edges.append(try world.buildTrackEdge(from: nodes[index], to: nodes[(index + 1) % 4], curve: .cubic(handle.0, handle.1)))
            }
            return edges
        }
        let innerRing = try circle(radius: ringRadius)
        let outerRing = try circle(radius: ringRadius + 1)

        let names = language == .english
            ? ["West", "Central", "East", "North", "South"]
            : ["西站", "中央", "東站", "北站", "南站"]
        // Each station stands at the middle of its first platform on Line 1
        // or 2.
        func station(_ name: String, at x: Int64, _ y: Int64) throws(GameError) -> StationID {
            try world.buildStation(named: name, at: PlanPoint(x: x, y: y)).id
        }
        let first = reach * step - step - platform / 2
        let westStation = try station(names[0], at: cx - first, cy)
        let central = try station(names[1], at: cx, cy)
        let eastStation = try station(names[2], at: cx + first, cy)
        let northStation = try station(names[3], at: cx, cy - first)
        let southStation = try station(names[4], at: cx, cy + first)
        // Offsets along each edge, measured from its first node.
        for (edge, stations) in [(ground, (westStation, eastStation)), (viaduct, (northStation, southStation))] {
            try world.addTrackPlatform(stations.0, on: edge, from: step, to: step + platform)
            try world.addTrackPlatform(central, on: edge, from: span / 2 - platform / 2, to: span / 2 + platform / 2)
            try world.addTrackPlatform(stations.1, on: edge, from: span - step - platform, to: span - step)
        }
        // The ring calls at the four ends, a platform on each track in the
        // middle of its arc: at North and South below Line 2's, at West and
        // East beside Line 1's.
        for ring in [innerRing, outerRing] {
            for (edge, id) in zip(ring, [northStation, eastStation, southStation, westStation]) {
                guard let length = world.network.edge(edge)?.length else { continue }
                try world.addTrackPlatform(id, on: edge, from: length / 2 - ringPlatform / 2, to: length / 2 + ringPlatform / 2)
            }
        }

        let lines = language == .english ? ["Line 1", "Line 2", "Ring Line"] : ["1 號線", "2 號線", "環狀線"]
        let trains = language == .english
            ? ["Train 1", "Train 2", "Ring Train 1", "Ring Train 2"]
            : ["列車 1", "列車 2", "環狀線列車 1", "環狀線列車 2"]
        // Where a train waits at its line's first platform: on `edge` going
        // `direction`, its head at the platform's far end.
        func place(
            _ name: String, cars: Int = Self.cars, at berth: (edge: TrackEdgeID, direction: TrackEdgeDirection, offset: Int64)
        ) throws(GameError) -> TrainID {
            let train = try world.purchaseTrain(named: name).id
            try world.setTrainCars(train, to: cars)
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: berth.edge, direction: berth.direction), offset: berth.offset))
            try world.setTrainContinuation(train, along: [], stoppingAt: berth.offset)
            try world.setTrainMovementRate(train, to: 512)
            return train
        }
        func run(_ name: String, calling stops: [StationID], ring: Bool = false) throws(GameError) -> LineID {
            let line = try world.createLine(named: name, stops: stops).id
            try world.setLineRing(line, to: ring)
            try world.setLineServiceWindow(line, to: .allDay)
            // A ring runs its trains in pairs, one each way.
            let count = ring ? 2 : 1
            try world.setLineTrainsInService(line, to: TrainsInService(peak: count, offPeak: count, low: count))
            return line
        }
        let line1 = try run(lines[0], calling: [westStation, central, eastStation])
        try world.assignTrain(try place(trains[0], at: (ground, .forward, step + platform)), to: line1)
        let line2 = try run(lines[1], calling: [northStation, central, southStation])
        try world.assignTrain(try place(trains[1], at: (viaduct, .forward, step + platform)), to: line2)
        // The ring from West: its first train the inner way round on the
        // inner track (clockwise, north first), its second the outer way on
        // the outer track, both at West's platform on the arc through West.
        let ringLine = try run(lines[2], calling: [westStation, northStation, eastStation, southStation], ring: true)
        for (name, edge, direction) in [(trains[2], innerRing[3], TrackEdgeDirection.forward), (trains[3], outerRing[3], .backward)] {
            guard let length = world.network.edge(edge)?.length else { continue }
            try world.assignTrain(try place(name, cars: ringCars, at: (edge, direction, length / 2 + ringPlatform / 2)), to: ringLine)
        }
    }
}
