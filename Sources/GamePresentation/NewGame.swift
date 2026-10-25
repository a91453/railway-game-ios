import Foundation
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
    /// It keeps the public holidays (decision 154) of the country `anchor`
    /// lies in (``CountryLookup``), or Taiwan's on a blank map, at the
    /// light level. The tutorial and the challenges turn them off.
    ///
    /// Its `water` (decision 105) is a real-world map's sea, rivers and
    /// lakes (``WaterGrid``), under which there is no land, and its `steep`
    /// slopes (decision 115), where nothing new is built; a blank map has
    /// neither.
    ///
    /// A blank map that `buysMap` (decision 160) is ``buyingMapTiles``
    /// tiles a side of the usual map's size, of which the company owns the
    /// middle one, the usual map with the same towns, and buys the others
    /// as its railway grows, each growing towns of its own from
    /// `eventSeed`.
    ///
    /// Decision 258: its `rules` are realistic, every rule below on, unless
    /// simple (``NewGameRules``), as the app's new games are.
    public static func newGame(
        anchor: GeoAnchor? = nil, bounds: WorldBounds = newGameBounds, balance: Money = startingBalance, eventSeed: UInt32 = 1,
        land: [LandCell]? = nil, water: [CellPosition] = [], steep: [CellPosition] = [], buysMap: Bool = false,
        rules: NewGameRules = .realistic
    ) -> GameWorld {
        precondition(!buysMap || (anchor == nil && bounds == newGameBounds), "Only a blank map of the usual size buys its map (decision 160).")
        let bounds = buysMap ? buyingMapBounds : bounds
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
            // Decision 154: the country's public holidays raise the whole
            // network's demand, gently.
            // Decision 162: and its weather, typhoons and fuel price, drawn
            // from the game's seed.
            world.setDisruptions(Disruptions(level: .light, country: anchor.map(CountryLookup.country(at:)) ?? HolidayCalendar.home, seed: eventSeed))
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
            // Decision 400: the roads, a square in each town's middle on a
            // blank map, growing toward the stations once a month. Its
            // sequel: a real-world map whose land is read in as it is
            // needed (`land` empty, ``GameWorld/setLandOnDemand()`` next)
            // has the base map's, read in with the land
            // (``GameSession/readRoads(in:baseMap:)``), and each station
            // draws the nearest toward it.
            if anchor == nil, land == nil {
                world.enableRoads(towns: Land.townCentres(seed: eventSeed, in: bounds))
            } else if anchor != nil, land?.isEmpty == true {
                world.enableRoads()
            }
            // Decision 160: the middle tile, its towns the usual map's.
            if buysMap {
                let middle = buyingMapTiles / 2
                try world.enableMapExpansion(owning: MapTile(row: middle, column: middle), townSeed: eventSeed)
            }
            // Decision 137: short trips walk, and the stations by the map's
            // edge bring the towns beyond it, but for the whole of Taiwan,
            // whose edge is the sea.
            world.setDistanceDemand(true)
            world.setOutsideConnections(bounds != WholeTaiwan.bounds)
            // Decision 169: a crowded train's doors pass fewer passengers a
            // second, so a full train dwells longer.
            world.setDoorCrowding(true)
            // Decision 202: trains keep left on double track, as Taiwan's
            // railways and its high-speed line do.
            world.setKeepLeft(true)
            // Decision 207: legs planned at the usual rates with a recovery
            // margin, a high-speed line's real dwell, and punctuality.
            world.setRealisticOperation(true)
            // Decision 212: long legs cut into block sections, so trains
            // follow each other along them under traffic control.
            world.setBlockSections(true)
            // Decision 217: trains brake ahead of a curve's speed limit.
            world.setCurveSpeedLimits(true)
            // Decision 227: trains bought have their type's real car length.
            world.setRealCarLengths(true)
            // Decision 180: trains cost and weigh what their type and cars
            // do, and are sold back at 70 % of their books.
            world.setRollingStockEconomics(true)
            // Decision 172: trains are sent out from either end of their
            // line, and one left elsewhere runs empty to an end.
            world.setFlexDispatch(true)
            // Decision 179: each line keeps its riders, fares and costs of
            // the last 30 days, and each station its flow of yesterday.
            // Only a record: it changes nothing in play, so the challenges,
            // the tutorial and the demos built on a new game keep it.
            world.setLineAccounts(true)
            // Decision 174: the sights tourists come to, and what they
            // spend in the shops: Taiwan's own on a real-world map (the ones
            // in its bounds; elsewhere none), a few drawn from the seed on a
            // blank one once its towns are founded.
            if let anchor {
                world.setTourism(AttractionCatalog.attractions(in: RealWorldFrame(anchor: anchor, bounds: bounds), bounds: bounds))
            } else {
                world.foundAttractions(seed: eventSeed)
            }
            // Phase 6b: its stations draw their ridership from it, and it
            // grows round the well-served ones.
            world.setLandDemand(true)
            // Decision 319: homes send their riders out in the morning and
            // workplaces in the evening, by how much of a home the land
            // round each station is.
            world.setTidalDemand(true)
            // Phase 6c-1: the city's buildings stand on its land, each
            // holding so many residents and jobs.
            world.setCityBuildings(true)
            // Decision 139: the city keeps the mix of homes, shops and work
            // it starts with: what it is short of is in demand.
            world.setCityDemand(true)
            // Decision 142: a low town's buildings leave room for the
            // company's between them.
            world.setCityFootprints(true)
            // Decision 146: a real-world map's buildings are the base map's,
            // so the company's buy out the city's by the ground they cover.
            world.setAreaBuyOut(anchor != nil)
            // Decision 155: freight, for a company that builds a yard;
            // decision 156: and building materials.
            world.enableBuildingMaterials()
            // Decision 183: the city's requests, drawn from the seed once
            // the map, its sights and its freight are set: the first offers
            // come at once.
            world.setCityRequests(seed: eventSeed)
            rules.apply(to: &world)
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

    /// How many tiles a side a blank map that buys its map has (decision
    /// 160): 5, 81.92 km, room for an intercity line.
    public static let buyingMapTiles = 5

    /// The world of a blank map that buys its map: ``buyingMapTiles`` tiles
    /// of ``newGameBounds`` a side. Its middle is the middle tile's, so
    /// ``Land/towns(seed:in:)`` lays the usual map's towns there.
    public static let buyingMapBounds: WorldBounds = {
        let side = Int64(buyingMapTiles) * MapExpansion.tileLength
        do {
            return try WorldBounds(width: side, height: side)
        } catch {
            preconditionFailure("\(side) units fits a world.")
        }
    }()

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
        // Decision 169: nor do its dwells lengthen in a crowd; the demo's
        // economy is as it was measured.
        world.setDoorCrowding(false)
        world.setRollingStockEconomics(false)
        world.setFlexDispatch(false)
        // Decision 202: its routes are as they were measured.
        world.setKeepLeft(false)
        // Decision 207: its timetables are as they were measured.
        world.setRealisticOperation(false)
        // Decision 212: its traffic control takes whole legs as measured.
        world.setBlockSections(false)
        world.setCurveSpeedLimits(false)
        world.setRealCarLengths(false)
        // Decision 319: its demand keeps the hours it was measured by.
        world.setTidalDemand(false)
        // Decision 174: nor are there sights.
        world.setTourism(nil)
        // Decision 183: nor the city's requests.
        world.setCityRequests(seed: nil)
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

/// The rules a new game plays by (ARCHITECTURE decision 258, after decision
/// 254): simple, the app's default, or realistic, every rule a new game has.
///
/// Simple turns off what a new player need not learn first, as the tutorial
/// and the challenges do: block sections (decision 212), curve speed
/// limits (217), realistic operation (207), crowding at the doors (169),
/// rolling stock economics (180), building materials (156) and the weather,
/// typhoons and fuel spells (162), keeping the public holidays (154).
/// Traffic control, flexible dispatch, keeping left, real car lengths, the
/// sights and the city's requests stay on. Every one of them is a switch
/// the world already has and keeps in its saves, so a game keeps the rules
/// it began with, and nothing changes them during play.
public enum NewGameRules: String, CaseIterable, Codable, Sendable {
    case simple, realistic

    /// Turns `world`'s rules to these: simple turns the realistic ones off;
    /// realistic leaves them as they are. Free.
    public func apply(to world: inout GameWorld) {
        guard self == .simple else { return }
        world.setBlockSections(false)
        world.setCurveSpeedLimits(false)
        world.setRealisticOperation(false)
        world.setDoorCrowding(false)
        world.setRollingStockEconomics(false)
        world.setBuildingMaterials(false)
        // Decision 162: the holidays without the weather drawn from the seed.
        if let disruptions = world.disruptions, disruptions.seed != nil {
            world.setDisruptions(Disruptions(level: disruptions.level, country: disruptions.country))
        }
    }

    /// The rules `world` plays by: simple when the rules simple turns off
    /// that only a realistic game has are all off (the tutorial's, the
    /// challenges' and saves from before them too), realistic otherwise.
    public init(of world: GameWorld) {
        let realistic = world.blockSections || world.curveSpeedLimits || world.realisticOperation
            || world.doorCrowding || world.rollingStockEconomics
        self = realistic ? .realistic : .simple
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .simple: language.text("Simple", "簡單")
        case .realistic: language.text("Realistic", "寫實")
        }
    }

    /// What the rules mean for the player, in a sentence or two.
    public func explanation(in language: DisplayLanguage) -> String {
        switch self {
        case .simple:
            language.text(
                "Trains keep their speed through curves, every train costs the same, and there is no weather or building materials.",
                "列車過彎不減速，每種車價錢一樣，沒有天氣與建材。"
            )
        case .realistic:
            language.text(
                "Block signals, curve speed limits, punctuality, crowded doors, train prices, building materials and weather all count.",
                "閉塞號誌、彎道限速、準點率、車門擁擠、車價、建材與天氣都會影響營運。"
            )
        }
    }
}

/// What a new game is set up with (ARCHITECTURE decision 177), after A-Train's
/// difficulty choice (やさしい／標準／達人): the starting cash, how much the
/// holidays, weather and typhoons disturb the traffic, and the rules a new
/// game turns on. The default is the new game as it was before the options
/// were asked: standard, $3,000,000, light disruptions. Presentation only:
/// the options are applied to the world with ordinary `GameWorld` commands
/// (``GameWorld/newGame(anchor:bounds:balance:eventSeed:land:water:steep:buysMap:)``
/// and ``apply(to:)``) and are not saved with the game, which holds what
/// they set. The weekly challenge is not touched by them.
public struct NewGameOptions: Hashable, Codable, Sendable {
    /// Easy, standard or expert: the cash, and (unless ``disruption`` is set)
    /// the disruptions.
    public enum Difficulty: String, CaseIterable, Codable, Sendable {
        case easy, standard, expert

        /// $5,000,000, $3,000,000 or $1,500,000.
        public var startingBalance: Money {
            switch self {
            case .easy: 500_000_000
            case .standard: GameWorld.startingBalance
            case .expert: 150_000_000
            }
        }

        /// What it does to the disruptions unless they are chosen apart.
        public var disruption: Disruption {
            switch self {
            case .easy: .off
            case .standard: .light
            case .expert: .standard
            }
        }

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .easy: language.text("Easy", "輕鬆")
            case .standard: language.text("Standard", "標準")
            case .expert: language.text("Expert", "達人")
            }
        }
    }

    /// How much the holidays, weather, typhoons and fuel price disturb the
    /// traffic (decisions 154 and 162): not at all, gently, or in full.
    public enum Disruption: String, CaseIterable, Codable, Sendable {
        case off, light, standard

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .off: language.text("Off", "關閉")
            case .light: language.text("Light", "輕")
            case .standard: language.text("Standard", "標準")
            }
        }
    }

    /// A real-world map's ground (decision 198): its real heights, which
    /// track climbs and tunnels through (decision 124), or flat, where
    /// track is always level. Blank maps are flat either way.
    public enum Ground: String, CaseIterable, Codable, Sendable {
        case real, flat

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .real: language.text("Real", "真實")
            case .flat: language.text("Flat", "平坦")
            }
        }
    }

    /// Decision 200: whether the company pays for what it builds. With
    /// unlimited funds nothing is charged and the game counts no
    /// achievements; the rest of the rules are a managed game's.
    public enum Funds: String, CaseIterable, Codable, Sendable {
        case standard, unlimited

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .standard: language.text("Standard", "一般")
            case .unlimited: language.text("Unlimited", "無限")
            }
        }
    }

    public var difficulty: Difficulty = .standard
    /// Disruptions apart from the difficulty's; `nil` follows it.
    public var disruptionChoice: Disruption?
    /// Decision 156: towns grow slowly without the building materials a
    /// freight yard sends.
    public var buildingMaterials = true
    /// Decision 137: the towns beyond the map's edge send riders to the
    /// stations by it.
    public var outsideConnections = true
    /// Decision 298: on a real-world map, the stations by real ones bring
    /// the travellers changing from the real railways.
    public var realTransfers = true
    /// Decision 160: a blank map is bought tile by tile as the railway
    /// grows; off, it is the usual 16 km map. Real-world maps decide for
    /// themselves.
    public var buysMap = true
    /// The seed the towns and events are drawn from, so a map can be shared;
    /// `nil` draws a new one for each game.
    public var seed: UInt32?
    /// Decision 198: a real-world map's ground, real unless chosen flat.
    public var ground = Ground.real
    /// Decision 200: standard unless chosen unlimited.
    public var funds = Funds.standard
    /// Decision 258: simple unless chosen realistic, options kept from
    /// before it included.
    public var rules = NewGameRules.simple

    public init() {}

    /// Reads the options as written, an option missing from the file as its
    /// default: the options written before an option was added (and the
    /// launcher's other preferences with them) still read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self()
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? standard.difficulty
        disruptionChoice = try container.decodeIfPresent(Disruption.self, forKey: .disruptionChoice)
        buildingMaterials = try container.decodeIfPresent(Bool.self, forKey: .buildingMaterials) ?? standard.buildingMaterials
        outsideConnections = try container.decodeIfPresent(Bool.self, forKey: .outsideConnections) ?? standard.outsideConnections
        realTransfers = try container.decodeIfPresent(Bool.self, forKey: .realTransfers) ?? standard.realTransfers
        buysMap = try container.decodeIfPresent(Bool.self, forKey: .buysMap) ?? standard.buysMap
        seed = try container.decodeIfPresent(UInt32.self, forKey: .seed)
        ground = try container.decodeIfPresent(Ground.self, forKey: .ground) ?? standard.ground
        funds = try container.decodeIfPresent(Funds.self, forKey: .funds) ?? standard.funds
        rules = try container.decodeIfPresent(NewGameRules.self, forKey: .rules) ?? standard.rules
    }

    public var startingBalance: Money { difficulty.startingBalance }

    public var disruption: Disruption { disruptionChoice ?? difficulty.disruption }

    /// A game's seed: ``seed``, or a random one.
    public func eventSeed() -> UInt32 {
        seed ?? .random(in: .min ... .max)
    }

    /// Turns `world`'s disruptions, building materials, outside
    /// connections, real transfers (on a real-world map), riders switching
    /// to scooters and cars (decision 332), funds and rules (decision 258: simple rules have no
    /// weather or building materials, whatever the options say) to these
    /// options. Free, and nothing else changes. The realistic rule lets
    /// at most `modeShiftCap` thousandths of a pair's trips switch: the
    /// share of the county the map starts in (``ModeShiftCounties``).
    public func apply(to world: inout GameWorld, modeShiftCap: Int64 = ModeShift.nationalShare) {
        switch disruption {
        case .off:
            world.setDisruptions(nil)
        case .light, .standard:
            let level: DisruptionLevel = disruption == .light ? .light : .standard
            if let current = world.disruptions, let changed = Disruptions(level: level, country: current.country, seed: current.seed) {
                world.setDisruptions(changed)
            }
        }
        world.setBuildingMaterials(buildingMaterials)
        if !outsideConnections { world.setOutsideConnections(false) }
        // Decision 298: real-world maps only.
        world.setRealTransfers(realTransfers && world.geoAnchor != nil)
        world.setUnlimitedFunds(funds == .unlimited)
        // Decision 332: riders take a scooter or a car instead of a slow
        // train, gently with simple rules.
        try? world.setModeShift(rules == .simple ? .simple : ModeShift.realistic(cap: modeShiftCap))
        rules.apply(to: &world)
    }

    /// The seed as typed: digits only, up to ``UInt32/max``; `nil` for
    /// empty or anything else.
    public static func seed(from text: String) -> UInt32? {
        UInt32(text.trimmingCharacters(in: .whitespaces))
    }

    /// One short paragraph on what these options change from the standard
    /// game, shown under the options.
    public func summary(in language: DisplayLanguage) -> String {
        let cash = funds == .unlimited ? "∞" : startingBalance.moneyText
        let disruptions = switch (disruption, self.rules) {
        case (.off, _): language.text("No holidays, weather or typhoons disturb the traffic.", "假日、天氣與颱風不影響客流。")
        case (.light, .realistic): language.text("Holidays, weather and typhoons disturb the traffic gently.", "假日、天氣與颱風對客流的影響較輕。")
        case (.standard, .realistic): language.text("Holidays, weather and typhoons disturb the traffic in full.", "假日、天氣與颱風對客流的影響完整。")
        case (.light, .simple): language.text("Holidays raise the traffic gently; no weather or typhoons.", "假日讓客流稍微增加；沒有天氣與颱風。")
        case (.standard, .simple): language.text("Holidays raise the traffic in full; no weather or typhoons.", "假日讓客流完整增加；沒有天氣與颱風。")
        }
        var rules: [String] = []
        // Decision 258: simple rules have none, which their explanation says.
        if !buildingMaterials && self.rules == .realistic { rules.append(language.text("towns grow without building materials", "城市不需要建材就能成長")) }
        if !outsideConnections { rules.append(language.text("no riders from beyond the map's edge", "地圖邊緣外沒有旅客")) }
        if !realTransfers { rules.append(language.text("no riders changing from real railways", "沒有從真實鐵路轉乘的旅客")) }
        if !buysMap { rules.append(language.text("a fixed 16 km map", "固定 16 公里的地圖")) }
        if ground == .flat { rules.append(language.text("flat ground on real-world maps", "實景地圖地形平坦")) }
        if funds == .unlimited {
            rules.append(language.text("unlimited funds, no achievements", "資金無限，不計成就"))
        }
        let rule = rules.isEmpty
            ? (self.rules == .simple
                ? language.text("Outside connections and map purchase are on.", "外部連接與地圖購買都開啟。")
                : language.text("Building materials, outside connections and map purchase are on.", "建材、外部連接與地圖購買都開啟。"))
            : language.text("Changed: \(rules.joined(separator: ", ")).", "已更改：\(rules.joined(separator: "、"))。")
        let seedText = seed.map { language.text("Seed \($0).", "種子 \($0)。") } ?? language.text("A random map each game.", "每局隨機地圖。")
        return language.text("Starts with \(cash). ", "起始資金 \(cash)。") + self.rules.explanation(in: language) + " "
            + disruptions + " " + rule + " " + seedText
    }
}
