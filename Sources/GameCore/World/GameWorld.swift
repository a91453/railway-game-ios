/// The authoritative game state and the only entry point for changing it.
///
/// `GameWorld` is a value type: every command validates its inputs before
/// touching any state, so a thrown ``GameError`` always leaves the world
/// exactly as it was. Copies are independent snapshots, which also gives
/// future undo/redo and background work a cheap starting point.
///
/// Presentation and rendering layers read from a world and send it commands;
/// they must not keep a separate copy of game state as the source of truth.
public struct GameWorld: Equatable, Sendable {
    /// How far the world reaches (Stage F3d): every track node and station
    /// stands in it. The railway is the ``network``, and stations stand at
    /// points (Stage F1); the world has no cells.
    public private(set) var bounds: WorldBounds
    /// All stations, ordered by ascending ``StationID``.
    public private(set) var stations: [Station]
    /// All trains, ordered by ascending ``TrainID``.
    public internal(set) var trains: [Train]
    /// All service lines, ordered by ascending ``LineID``.
    public internal(set) var lines: [ServiceLine]
    /// Which service level each minute of the day has, for every line.
    public private(set) var serviceDay: ServiceDay
    public internal(set) var clock: GameClock
    public internal(set) var economy: GameEconomy
    /// The railway (Phase 4.5 Stage S3): the one record of all track, the
    /// network's nodes and edges. Empty in a new world.
    public private(set) var network: RailwayNetwork
    /// Whether traffic control is on (Phase 4.6 Stage T, ARCHITECTURE
    /// decision 32): every train takes the whole of a route before it starts
    /// along it, no two trains hold the same track, and a service or a line
    /// whose route is held waits for it (see ``setTrafficControl(_:)`` and
    /// ``reservedResources(of:)``). Off in a new world, so every rule of the
    /// stages before it holds unchanged; a new game in the app turns it on.
    public private(set) var isTrafficControlEnabled: Bool
    /// The passengers of every station that has any (G1a, ARCHITECTURE
    /// decision 34): its demand, the groups waiting there and the
    /// conservation audit, by ascending ``StationID``. Empty in a new world,
    /// where no station has demand. Set by the passenger rules
    /// (`PassengerDemand.swift`) only.
    public internal(set) var passengers: [StationPassengers]
    /// The passengers riding each train that carries any (G1b, ARCHITECTURE
    /// decision 35), by ascending ``TrainID``. Set by the passenger rules
    /// (`Boarding.swift`) only.
    public internal(set) var riders: [TrainRiders]
    /// Legacy saves keep direct-trip demand; network games select a complete
    /// journey at release. A change affects future releases only.
    public internal(set) var passengerRoutingMode: PassengerRoutingMode
    /// Whether each day's demand follows the reference's weekday factors
    /// and weekends its weekend hours (item 4 of the author's order). Off in
    /// a new world and in saves from before it; the app's new games turn it
    /// on. Set by ``setWeeklyDemand(_:)`` only.
    public internal(set) var weeklyDemand: Bool = false
    /// Whether demand keeps the tide (decision 319): homes' trips leave in
    /// the morning and come back in the evening, workplaces' the other way
    /// round, and the night is all but empty. Off in a new world and in
    /// saves from before it; the app's new games turn it on. Set by
    /// ``setTidalDemand(_:)`` only.
    public internal(set) var tidalDemand: Bool = false
    /// Whether passengers who wait too long leave (decision 731): one
    /// still waiting ``PassengerPatience/minutes(longTrip:)`` after they
    /// could first board gives up. Off in a new world and in saves from
    /// before it; the player's new games with realistic rules turn it on.
    /// Set by ``setPassengerPatience(_:)`` only.
    public internal(set) var passengerPatience: Bool = false
    /// Whether the company's income tax is settled once a year (decision
    /// 734): the year's profit before tax is taxed as the year closes and
    /// paid at the end of the next year's fifth month, instead of each
    /// day's (decision 131). Off in a new world and in saves from before
    /// it; the player's new games with realistic rules turn it on. Set by
    /// ``setAnnualTaxes(_:)`` only.
    public internal(set) var annualTaxes: Bool = false
    /// Whether and how riders take a scooter or a car instead when the
    /// train is slower door to door (decision 332), or `nil` for none. Off
    /// in a new world and in saves from before it; the player's new games
    /// turn it on. Set by ``setModeShift(_:)`` only.
    public internal(set) var modeShift: ModeShift?
    /// The demand events and the seed they are drawn from, or `nil` for a
    /// world without them (item 4; see ``DemandEventSchedule``). Off in a
    /// new world and in saves from before them; the app's new games turn
    /// them on. Set by ``setDemandEvents(seed:)`` and every midnight only.
    public internal(set) var demandEvents: DemandEventSchedule?
    /// The world's disruptions (decision 154): the country whose public
    /// holidays it keeps and how strongly they bite, or `nil` for a world
    /// without them. Off in a new world and in saves from before them; the
    /// app's new games turn them on. Set by ``setDisruptions(_:)`` only.
    public internal(set) var disruptions: Disruptions?
    /// How the towns round the stations grow, or `nil` for a world whose
    /// ridership stays as set (item 5; see ``TownGrowth``). Off in a new
    /// world and in saves from before it; the app's new games turn it on.
    /// Set by ``setTownGrowth(_:)`` and every midnight only.
    public internal(set) var townGrowth: TownGrowth?
    /// Fractions left after deterministic OD route choice, by origin and
    /// destination. They are saved so advancing in batches changes nothing.
    var passengerRouteBalances: [PassengerRouteBalance]
    /// The company's accounts (G1c, ARCHITECTURE decision 36): its economy
    /// mode and fare rules, the hour being accrued and the ledger. Free and
    /// empty in a new world. Set by the economy rules (`Economy/`) only.
    public internal(set) var accounts: CompanyAccounts
    /// Where the map lies on the Earth, for a real-world game (Stage E2,
    /// ARCHITECTURE decision 50); `nil`, a blank map, in a new world. No
    /// rule reads it. Set by ``setGeoAnchor(_:)`` only.
    public internal(set) var geoAnchor: GeoAnchor?
    /// The land round the railway (Phase 6a, ARCHITECTURE decision 72): who
    /// lives and works in each 64 m cell. Empty in a new world and in saves
    /// from before it; the app's new games start with towns or a real-world
    /// map's people. No rule reads it yet. Set by ``setLand(_:)`` and
    /// ``foundTowns(seed:)`` only.
    public internal(set) var land: Land
    /// The blocks of land read in so far, by row and then column, when the
    /// land is read in as it is needed (decision 88: a map of the whole of
    /// Taiwan); `nil`, the land is whole, in a new world and in saves from
    /// before it. Set by ``setLandOnDemand()``, ``expandLand(_:cells:)``,
    /// ``setLand(_:)`` and ``foundTowns(seed:)`` only.
    public internal(set) var landBlocks: [LandBlock]?
    /// Whether a managed company's stations take their ridership from the
    /// land (Phase 6b, ARCHITECTURE decision 73). Off in a new world and in
    /// saves from before it; the app's new games turn it on. Set by
    /// ``setLandDemand(_:)`` only.
    public internal(set) var landDemand: Bool = false
    /// Whether each pair's trips keep a share by their distance (decision
    /// 137). Off in a new world and in saves from before it; the app's new
    /// games turn it on. Set by ``setDistanceDemand(_:)`` only.
    public internal(set) var distanceDemand: Bool = false
    /// Whether a station beyond ``DistanceDemand/farDistance`` from an
    /// origin draws less of its trips the farther it is (decision 828).
    /// Off in a new world and in saves from before it; the app's new
    /// overseas games turn it on. Set by ``setFarDemand(_:)`` only.
    public internal(set) var farDemand: Bool = false
    /// Whether the crowd at a train's doors slows the passengers going
    /// through them (decision 169). Off in a new world and in saves from
    /// before it; the app's new games turn it on. Set by
    /// ``setDoorCrowding(_:)`` only.
    public internal(set) var doorCrowding: Bool = false
    /// Whether trains keep left on double track (decision 202): the route
    /// a train finds to a station takes the leftmost way on at each switch
    /// unless another is more than ``keepLeftMargin`` shorter. Off in a new
    /// world and in saves from before it; the app's new games turn it on.
    /// Set by ``setKeepLeft(_:)`` only.
    public internal(set) var keepLeft: Bool = false
    /// Whether switches take time to throw (decision 756): with traffic
    /// control on, a switch lies the way the last train went through it,
    /// and a service whose route needs one the other way waits
    /// ``switchThrowSeconds`` before it moves. Off in a new world and in
    /// saves from before it. Set by ``setSwitchInterlocking(_:)`` only.
    public internal(set) var switchInterlocking: Bool = false
    /// How each switch a train has gone through lies (decision 756), by
    /// node: empty unless ``switchInterlocking`` is on. A switch whose
    /// track was taken up may stay in it; it is never asked of again.
    public internal(set) var switchLies: [TrackNodeID: SwitchLie] = [:]
    /// Whether the lines plan their timetables realistically (decision
    /// 207): each leg at the performance's usual rates with a recovery
    /// margin a late train can make up, a line's dwell by its kind, and
    /// each line's punctuality counted. Off in a new world and in saves from
    /// before it; the app's new games turn it on. Set by
    /// ``setRealisticOperation(_:)`` only.
    public internal(set) var realisticOperation: Bool = false
    /// Whether long legs are cut into block sections under traffic control
    /// (decision 212): a following train's authority ends at a block's
    /// boundary, a train following others may lead another, and a service
    /// may follow on its scheduled or preferred path. Off in a new world and
    /// in saves from before it; the app's new games turn it on. Set by
    /// ``setBlockSections(_:)`` only.
    public internal(set) var blockSections: Bool = false
    /// Whether trains keep to the curve speed limits (decision 217): a
    /// run brakes ahead of each curve's limit and accelerates once its tail
    /// is out, and the lines plan their legs so. Off in a new world and in
    /// saves from before it; the app's new games turn it on. Set by
    /// ``setCurveSpeedLimits(_:)`` only.
    public internal(set) var curveSpeedLimits: Bool = false
    /// Whether a train bought or changed to a type takes the type's real
    /// car length (decision 227, ``Train/carPitch``) rather than 16 m. Off
    /// in a new world and in saves from before it; the app's new games turn
    /// it on. It changes no train already bought. Set by
    /// ``setRealCarLengths(_:)`` only.
    public internal(set) var realCarLengths: Bool = false
    /// Decision 248: how far each train of a line with real runs may still
    /// go on before the minute ends, with traffic control off
    /// (``assessSpacing(from:memo:)``). Given as a minute begins, and to a
    /// train setting off within one; empty again as it ends, so empty at
    /// every whole minute.
    public internal(set) var spacingAllowances: [TrainID: SpacingAllowance] = [:]
    /// For tests only (decision 805): the rule before decision 801, a
    /// train leaving its platform letting a faster train behind it pass
    /// first even while that one stands held by a third, which stood three
    /// trains in a ring. Never set by the game, never saved.
    var passesHeldTrains = false
    /// Whether a line sends its trains out from either end, and runs one
    /// that stands elsewhere empty to an end (decision 172); off, only from
    /// the first stop, as before. A new game turns it on.
    public internal(set) var flexDispatch: Bool = false
    /// Whether a train costs what its type and cars cost, is sold back at
    /// 70 % of its book value, and runs at a cost that weighs its cars and
    /// its type (decision 180); off, one price and one weight for every
    /// train. Off in a new world and in saves from before it; a new game
    /// turns it on. Set by ``setRollingStockEconomics(_:)`` only.
    public internal(set) var rollingStockEconomics: Bool = false
    /// Each line's records of its last 30 days, and each station's flow of
    /// yesterday (decision 179); `nil`, off, in a world from before them. A
    /// new game turns it on. Set by ``setLineAccounts(_:)`` only.
    public internal(set) var lineAccounts: LineAccounts?
    /// Each train's trips of today and yesterday (decision 223, point 5),
    /// ordered by train and then by when they were sent out; kept with the
    /// line accounts, empty without them and in saves from before it. A
    /// record only: no rule reads it. Changed only as trains run.
    public internal(set) var tripLog: [TrainTrip] = []
    /// The sights and the tourists they draw (decision 174), or `nil`: off
    /// in a new world and in saves from before it; the app's new games turn
    /// it on. Set by ``setTourism(_:)`` and every midnight only.
    public internal(set) var tourism: Tourism?
    /// The company's record of the runs the player drove by hand (decision
    /// 693), or `nil` until one is settled, and in saves from before
    /// version 89. Set by ``settleDrivenRun(_:)`` only.
    public internal(set) var driving: DrivingRecord?
    /// The city's requests of the company and its trust (decision 183), or
    /// `nil`: off in a new world and in saves from before them; the app's
    /// new free games turn them on. Set by ``setCityRequests(seed:)``, the
    /// request commands, the counts and every managed midnight only.
    public internal(set) var cityRequests: CityRequests?
    /// Whether the stations by the map's edge are outside connections
    /// (decision 137). Off in a new world and in saves from before them; the
    /// app's new games but those of the whole of Taiwan turn them on. Set by
    /// ``setOutsideConnections(_:)`` only.
    public internal(set) var outsideConnections: Bool = false
    /// Whether the stations by real stations bring the real network's
    /// transfers (decision 298, ``Station/transferPoints``). Off in a new
    /// world and in saves from before it; the app's new games on a
    /// real-world map turn it on. Set by ``setRealTransfers(_:)`` only.
    public internal(set) var realTransfers: Bool = false
    /// The real lines the company bought (decision 315), in the order it
    /// bought them. None in a new world and in saves from before it. Set by
    /// ``recordLineAcquisition(line:realLine:dailyRiders:tier:)`` only.
    public internal(set) var acquisitions: [LineAcquisition] = []
    /// Decision 528: the track real lines bought and removed left, what
    /// buying them again takes up. None in a new world and in saves from
    /// before version 79. Set by ``recordLineAcquisition(line:realLine:dailyRiders:tier:track:)``
    /// and removing a line bought only.
    public internal(set) var leftTrack: [LeftTrack] = []
    /// The roads on the land's grid (decision 400), or `nil` for a world
    /// without them. Off in a new world and in saves from before it; the
    /// player's new games turn them on. Set by ``enableRoads(towns:)``,
    /// ``setRoads(_:in:)``, ``buildStationRoad(at:)`` and their growth once
    /// a month only.
    public internal(set) var roads: RoadGrid?
    /// The company's bus routes feeding its stations (decision 400,
    /// 10i-2), by ascending number; none in a new world and in saves from
    /// before them (save version 73). Set by
    /// ``createBusRoute(to:stops:legMetres:service:buses:)`` and the other
    /// bus commands only.
    public internal(set) var busRoutes: [BusRoute] = []
    /// The next bus route's number.
    public internal(set) var nextBusRouteID = 1
    /// The company's cableways (decision 574), by ascending number; none in
    /// a new world and in saves from before them (save version 83). Set by
    /// ``createCableway(stops:legMetres:)`` and ``removeCableway(_:)`` only.
    public internal(set) var cableways: [Cableway] = []
    /// The next cableway's number.
    public internal(set) var nextCablewayID = 1
    /// The company's ferry routes (decision 585), by ascending number; none
    /// in a new world and in saves from before them (save version 85). Set
    /// by ``createFerryRoute(piers:legMetres:service:boats:)``,
    /// ``setFerryBoats(_:to:)``, ``setFerryRuns(_:to:)`` and
    /// ``removeFerryRoute(_:)`` only.
    public internal(set) var ferryRoutes: [FerryRoute] = []
    /// The next ferry route's number.
    public internal(set) var nextFerryRouteID = 1
    /// The airports of the map (decision 695), numbered from 1; none in a
    /// new world and in saves from before them. Set by
    /// ``setAirports(_:)`` and every midnight only.
    public internal(set) var airports: [Airport] = []
    /// The company's air routes (decision 758), by ascending number; none
    /// in a new world and in saves from before them (save version 103).
    /// Set by ``buyAirRoute(from:to:farAirport:metres:size:frequency:)``,
    /// ``setAirRouteFrequency(_:to:)``, ``setAirRouteSize(_:to:)``,
    /// ``sellAirRoute(_:)`` and every midnight only.
    public internal(set) var airRoutes: [AirRoute] = []
    /// The next air route's number.
    public internal(set) var nextAirRouteID = 1
    /// The coach stops of the map (decision 706), numbered from 1; none in
    /// a world without them. Changed by ``setCoachStops(_:)`` and every
    /// midnight only.
    public internal(set) var coachStops: [CoachStop] = []
    /// The melodies the player wrote (decision 883), by ascending number;
    /// none in a new world and in saves from before them (save version
    /// 111). Set by ``addPlayerMelody(named:notes:)``,
    /// ``editPlayerMelody(_:name:notes:)`` and ``removePlayerMelody(_:)``
    /// only.
    public internal(set) var playerMelodies: [PlayerMelody] = []
    /// The next player melody's number.
    public internal(set) var nextPlayerMelodyID = 1
    /// The city's demand for homes, shops and work (decision 139), or `nil`
    /// for a city that grows as before. Off in a new world and in saves
    /// from before it; the app's new games turn it on. Set by
    /// ``setCityDemand(_:)``, the land's replacement and its growth only.
    public internal(set) var cityDemand: CityDemand?
    /// The world's freight (decision 155), or `nil` for a world without it.
    /// Off in a new world and in saves from before it. Set by
    /// ``enableFreight()`` and the freight commands only.
    public internal(set) var freight: FreightState?
    /// Whether a city building's square is its density's, 20 to 40 m
    /// across, rather than 40 m whatever its height (decision 142). Off in
    /// a new world and in saves from before it; the app's new games turn it
    /// on. Set by ``setCityFootprints(_:)`` only.
    public internal(set) var cityFootprints: Bool = false
    /// Whether the company's buildings buy out the city's by area rather
    /// than by squares (decision 146): a real-world map's own buildings are
    /// the base map's, so the game's squares do not stand in the way. Off
    /// in a new world and in saves from before it; the app's real-world new
    /// games turn it on. Set by ``setAreaBuyOut(_:)`` only.
    public internal(set) var areaBuyOut: Bool = false
    /// Whether the city's buildings stand on the land (Phase 6c-1,
    /// ARCHITECTURE decision 74). Off in a new world and in saves from
    /// before it; the app's new games turn it on. Set by
    /// ``setCityBuildings(_:)`` only.
    public internal(set) var cityBuildings: Bool = false
    /// The city's buildings (Phase 6c-1): one on each cell of land while
    /// ``cityBuildings`` is on, none while it is off. Set with the land
    /// (``setCityBuildings(_:)``, ``setLand(_:)``, ``foundTowns(seed:)`` and
    /// the land's growth) only.
    public internal(set) var buildings = CityBuildings()
    /// The stations linked for transfers however far apart (decision 81),
    /// in ascending ID order. A new world has none.
    public internal(set) var transferGroups: [TransferGroup] = []
    /// The buildings the player placed (decision 92), in ascending ID
    /// order. A new world has none.
    public internal(set) var placedBuildings: [PlacedBuilding] = []
    /// The cells the player zoned (decision 98), by row and then column. A
    /// new world has none.
    public internal(set) var zones = Zoning()
    /// The ground under the land (decision 105): which cells are water. A
    /// new world, and every blank map, has none.
    public internal(set) var terrain = Terrain()
    /// The ground's height where it has been read (decision 124). A new
    /// world, and every blank map, has none, and is flat at 0 m; a new
    /// real-world game has ground (``mapGround()``).
    public internal(set) var ground = Ground()
    /// The scenario being played, its goals and how far they are met
    /// (decision 86), or `nil`: a game without goals.
    public internal(set) var scenario: ScenarioState?
    /// The tiles of the map the company owns, when it buys its map as it
    /// grows (decision 160), or `nil`: it may build anywhere in the world.
    /// Off in a new world and in saves from before it; the app's new blank
    /// games turn it on. Set by ``enableMapExpansion(owning:townSeed:ridersStep:)``,
    /// ``buyMapTile(_:)`` and every midnight only.
    public internal(set) var mapExpansion: MapExpansion?
    /// The trips that release passengers, derived from the demands and the
    /// lines' stops and kept between calls of ``advance(ticks:)``; not game
    /// state (see ``PassengerPlanCache``).
    var passengerPlan = PassengerPlanCache()
    /// The network route choices the last plan used, kept while the derived
    /// route graph stays the same; not game state (see
    /// ``PassengerRouteMemo``).
    var passengerRouteMemo = PassengerRouteMemo()
    /// What traffic control works out from the network, the lines and the
    /// stations alone, kept between calls of ``advance(ticks:)`` while they
    /// stay the same; not game state (see ``RouteMemo``).
    var routeMemo = RouteMemo()
    /// How many edits made as one (``editTrackAsOne(_:)``, decision 275)
    /// are running: 0 between commands; not game state.
    var trackEditDepth = 0

    /// The next ID to hand out to a station, a train or a line (see
    /// `allocateID(from:)`).
    private var nextStationID: Int
    private var nextTrainID: Int
    private var nextLineID: Int
    /// The next transfer group ID to hand out (decision 81).
    var nextTransferGroupID = 1
    /// The next placed building ID to hand out (decision 92).
    var nextPlacedBuildingID = 1

    /// Creates an empty world reaching as far as `bounds`.
    public init(
        bounds: WorldBounds,
        economy: GameEconomy,
        clock: GameClock = GameClock()
    ) {
        self.bounds = bounds
        self.stations = []
        self.trains = []
        self.lines = []
        self.serviceDay = .standard
        self.clock = clock
        self.economy = economy
        self.network = RailwayNetwork()
        self.isTrafficControlEnabled = false
        self.passengers = []
        self.riders = []
        self.passengerRoutingMode = .direct
        self.passengerRouteBalances = []
        self.accounts = CompanyAccounts()
        self.geoAnchor = nil
        self.land = Land()
        self.nextStationID = 1
        self.nextTrainID = 1
        self.nextLineID = 1
    }

    // MARK: - Queries

    public func station(id: StationID) -> Station? {
        stations.first { $0.id == id }
    }

    /// The station whose ``Station/location`` is nearest `point`, if one
    /// lies within `reach` world units of it (Stage F1): the lowest
    /// numbered of equally near ones. Distances compare squared, exactly.
    public func station(near point: PlanPoint, within reach: Int64) -> Station? {
        guard reach >= 0, point.isWithinLimits, reach <= WorldCoordinate.limit else { return nil }
        var best: (station: Station, squared: Int64)?
        for station in stations {
            let location = station.location
            let dx = location.x - point.x, dy = location.y - point.y
            guard abs(dx) <= reach, abs(dy) <= reach else { continue }
            let squared = dx * dx + dy * dy
            guard squared <= reach * reach, best.map({ squared < $0.squared }) ?? true else { continue }
            best = (station, squared)
        }
        return best?.station
    }

    // MARK: - Track network

    /// Builds a node of the track network at `position` (Phase 4.5 Stage S3):
    /// a point where edges can end and meet. Free: track is paid for by its
    /// edges. Returns the new node's ID, ``TrackNodeID/node(_:)``, numbered
    /// in order from 1 and never reused.
    ///
    /// The node must lie in the world's ``bounds``, at a height within
    /// ``RailwayNetwork/heightRange`` of the ground there (Stage S4; since
    /// decision 124 the ground under it, 0 in a world without ground),
    /// where no node stands yet.
    ///
    /// - Throws, checked in this order: ``GameError/invalidTrackGeometry``
    ///   outside the bounds; ``GameError/mapTileNotOwned(_:)`` on a tile of
    ///   the map the company does not own (decision 160);
    ///   ``GameError/groundNotLoaded`` where the world
    ///   has ground but has not read it there; ``GameError/invalidTrackGeometry``
    ///   too far above or below it, or where a node stands; or
    ///   ``GameError/idsExhausted``.
    @discardableResult
    public mutating func buildTrackNode(at position: WorldCoordinate) throws(GameError) -> TrackNodeID {
        guard bounds.contains(position.plan) else { throw .invalidTrackGeometry }
        // Decision 160: on the company's own ground.
        guard ownsGround(at: position.plan) else { throw .mapTileNotOwned(MapExpansion.tile(at: position.plan)) }
        guard groundHeight(at: position.plan) != nil else { throw .groundNotLoaded }
        guard isInWorld(position), !network.hasNode(at: position) else { throw .invalidTrackGeometry }
        let (_, next) = try Self.allocateID(from: network.nextNodeNumber)

        return network.addNode(at: position, next: next)
    }

    /// Builds an edge of the track network from node `from` to node `to`,
    /// shaped in plan by `curve` (Phase 4.5 Stage S3) and in height by
    /// `profile`, carried by `structure` (Stage S4), and charges
    /// ``ConstructionCosts/track`` times the structure's
    /// ``TrackStructure/costFactor`` for every
    /// ``ConstructionCosts/trackPricingLength`` of its length (1024 units,
    /// 16 m), rounded up. Returns the new edge's ID,
    /// ``TrackEdgeID/edge(_:)``, numbered in order from 1 and never reused.
    ///
    /// The edge's length, centre line and heights are worked out from its
    /// end nodes, curve and profile (see ``TrackGeometry``); its control
    /// points must lie in the world's ``bounds``. Which edges it joins at each end follows
    /// from the way it leaves the node (see ``TrackNodeEnd``): an edge that
    /// meets others at an angle joins none of them there. Edges that cross
    /// in plan without a shared node never join, and must pass one over the
    /// other (see ``TrackClearance``). Since Stage F2 edges at one level keep
    /// ``RailwayNetwork/trackSpacing`` apart but at points within
    /// ``RailwayNetwork/partingReach`` of each other along the track, where
    /// they are one junction's tracks parting (see ``TrackSpacing``). Several
    /// edges may join the same two nodes.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackNode(_:)``
    ///   for `from`, then for `to`; ``GameError/invalidTrackGeometry`` (the
    ///   same node twice, a control point outside the bounds, or a curve or profile
    ///   that does not make an edge); ``GameError/mapTileNotOwned(_:)``
    ///   for the first tile of the map it passes over that the company does
    ///   not own (decision 160); ``GameError/trackTooSteep``;
    ///   ``GameError/invalidTrackStructure``;
    ///   ``GameError/trackSystemMismatch(_:)`` (decision 951) for the
    ///   lowest numbered edge at `from`, then at `to`, of another track
    ///   system than `system`, or for mountain track on a guideway
    ///   (the edge it would be, numbered 0 until built);
    ///   ``GameError/trackConflict(_:)`` for the lowest numbered edge it
    ///   would meet without clearance; ``GameError/trackTooClose(_:)`` for
    ///   the lowest numbered edge it would run too close beside;
    ///   ``GameError/idsExhausted``; under
    ///   traffic control (Stage T), ``GameError/trackReserved(_:)`` when a
    ///   train holds either end node, or track within
    ///   ``RailwayNetwork/junctionZone`` of it, since a new edge there may
    ///   change which trains foul that junction; or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildTrackEdge(
        from: TrackNodeID, to: TrackNodeID, curve: TrackCurve = .straight, profile: TrackProfile = .uniform, structure: TrackStructure = .surface,
        mountain: Bool = false, system: TrackSystem? = nil
    ) throws(GameError) -> TrackEdgeID {
        let id = try buildTrackEdge(from: from, to: to, curve: curve, profile: profile, structure: structure, mountain: mountain, system: system,
                                    checksSpacing: true)
        abandonUnservedPassengers()
        return id
    }

    /// Builds the edges `plans` describe, in order, as one command (the
    /// owner's play-test, 2026-10-06): each as
    /// ``buildTrackEdge(from:to:curve:profile:structure:mountain:)`` would, charged
    /// the same, except that the spacing rule is checked once all of them
    /// are built, along the ways they make together. An X crossover's
    /// diagonal runs within 4 m of the other track near the middle and parts
    /// from it only by way of its other half; built one at a time, the first
    /// half would be refused. All or nothing. Returns the new edges in order.
    ///
    /// - Throws: what ``buildTrackEdge(from:to:curve:profile:structure:mountain:)``
    ///   throws for the first plan it refuses, checked as that plan is
    ///   built (``GameError/insufficientFunds(required:available:)`` for
    ///   the first the money left does not cover); then
    ///   ``GameError/trackTooClose(_:)`` for the lowest numbered edge the
    ///   first new edge, in order, runs too close beside.
    @discardableResult
    public mutating func buildTrackEdges(_ plans: [TrackEdgePlan]) throws(GameError) -> [TrackEdgeID] {
        var after = self
        var built: [TrackEdgeID] = []
        for plan in plans {
            built.append(try after.buildTrackEdge(from: plan.from, to: plan.to, curve: plan.curve, profile: plan.profile,
                                                  structure: plan.structure, mountain: plan.mountain, system: plan.system,
                                                  checksSpacing: false))
        }
        for id in built {
            if let other = after.network.firstTooClose(existing: id, besides: []) {
                throw .trackTooClose(other)
            }
        }
        self = after
        abandonUnservedPassengers()
        return built
    }

    private mutating func buildTrackEdge(
        from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, profile: TrackProfile, structure: TrackStructure, mountain: Bool,
        system wanted: TrackSystem?, checksSpacing: Bool
    ) throws(GameError) -> TrackEdgeID {
        guard let start = network.node(from) else { throw .unknownTrackNode(from) }
        guard let end = network.node(to) else { throw .unknownTrackNode(to) }
        guard from != to, curve.controlPoints.allSatisfy(bounds.contains),
              let geometry = TrackGeometry(from: start.position, to: end.position, curve: curve, profile: profile)
        else { throw .invalidTrackGeometry }
        // Decision 160: the whole of it on the company's own ground.
        if let tile = firstTileNotOwned(along: geometry.points.map(\.plan)) { throw .mapTileNotOwned(tile) }
        // Decision 515: mountain track may be steeper.
        guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade(mountain: mountain)) else { throw .trackTooSteep }
        // Decision 124: what carries it, measured from the ground.
        let sections = try sections(of: geometry, structure: structure)
        // Decision 951: of the system asked for, or of the track it joins;
        // a guideway joins only its own system, and is never mountain
        // track.
        let joined = [from, to].compactMap { network.system(at: $0) }
        let system = wanted ?? joined.first?.system ?? .conventional
        if let other = joined.first(where: { $0.system != system }) { throw .trackSystemMismatch(other.edge) }
        guard !mountain || !system.isGuideway else { throw .trackSystemMismatch(.edge(0)) }
        if let other = network.firstConflict(from: from, to: to, curve: curve, geometry: geometry) {
            throw .trackConflict(other)
        }
        if checksSpacing, let other = network.firstTooClose(from: from, to: to, curve: curve, geometry: geometry) {
            throw .trackTooClose(other)
        }
        let (_, next) = try Self.allocateID(from: network.nextEdgeNumber)
        if isTrafficControlEnabled, let train = trains.first(where: { train in
            held(train).contains { resource in [from, to].contains { isWithinJunctionZone(resource, of: $0) } }
        }) {
            throw .trackReserved(train.id)
        }
        let price = try edgeCost(of: geometry, structure: structure, sections: sections, system: system)
        // Decision 95: the company's buildings in its way come down, for
        // what demolishing them costs; track in a tunnel passes under
        // (decision 124: an automatic edge's tunnel sections).
        let edge = TrackEdge(id: .edge(0), from: from, to: to, curve: curve, length: geometry.length, structure: structure, sections: sections)
        let open = edge.openStretches(of: geometry)
        let cleared = placedBuildings.filter { building in open.contains { Self.line($0, comesNear: building) } }
        try checkFunds(price, clearing: cleared)
        try economy.spend(price)

        let id = network.addEdge(
            from: from, to: to, curve: curve, profile: profile, structure: structure, sections: sections, mountain: mountain, system: system,
            geometry: geometry, next: next
        )
        network.dropSpacedExemptions()
        // Phase 7a: the edge is on the books at what it cost.
        acquireAsset(.track, owner: id.networkNumber ?? 0, cost: price)
        clear(cleared)
        return id
    }

    /// Decision 951: each edge of `systems` is of its system from now on
    /// (``RailwayNetwork/setSystems(_:)``), for ``layGuideways()``.
    mutating func setTrackSystems(_ systems: [TrackEdgeID: TrackSystem]) {
        network.setSystems(systems)
    }

    /// The lower numbered of the first two placed trains, in ID order, whose
    /// held track would foul without edge `id` but does not now (Stage F2b):
    /// removing an edge makes ways along the track longer, so track near
    /// each other along it may come to foul. `nil` when there are none.
    private func firstTrainFouled(removing id: TrackEdgeID) -> TrainID? {
        var after = network
        after.removeEdge(id)
        guard !after.foulingSpans.isEmpty else { return nil }
        let placed = trains.filter { $0.position != nil }.map { ($0.id, held($0)) }
        for j in placed.indices {
            for i in placed.indices where i < j {
                if after.fouls(placed[i].1, placed[j].1), !network.fouls(placed[i].1, placed[j].1) { return placed[i].0 }
            }
        }
        return nil
    }

    /// Removes edge `id` of the track network (Stage S3). Removal is free and
    /// not refunded. Its nodes stay; the edges it joined there no longer join
    /// it. A train whose path names it stops at the node before it and waits
    /// there: IDs are never reused, so give that train a new path. A train
    /// running a service cannot be given one, so track still ahead of it on
    /// its way to its next stop cannot be removed.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackEdge(_:)``;
    ///   ``GameError/trackEdgeInUse(_:)`` while a placed train's head or
    ///   body is on it (unplace the train first); or
    ///   ``GameError/trackEdgeHasPlatform(_:)`` while a station has a
    ///   platform on it (Stage S4); or ``GameError/trackReserved(_:)``
    ///   while it is ahead of a train running a service, on its way to its
    ///   next stop; or, under traffic control (Stage T),
    ///   ``GameError/trackReserved(_:)`` while a train has reserved some of
    ///   it for its route, or (Stage F2b) when without it track two trains
    ///   hold would foul (see ``RailwayNetwork/fouls(_:_:)``): the lower
    ///   numbered of the first two such trains; or
    ///   ``GameError/tracksWouldBeTooClose(_:_:)`` when
    ///   two edges part from each other only by way of it, so that without
    ///   it they would be too close (Stage F2, ARCHITECTURE decision 52).
    public mutating func removeTrackEdge(_ id: TrackEdgeID) throws(GameError) {
        guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        guard !trains.contains(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == id { return true }
            return train.trailEdges.contains(id)
        }) else { throw .trackEdgeInUse(id) }
        guard network.platforms(on: id).isEmpty else { throw .trackEdgeHasPlatform(id) }
        if let train = trains.first(where: { $0.execution != nil && $0.movement.remainingEdges.contains(id) }) {
            throw .trackReserved(train.id)
        }
        if isTrafficControlEnabled, let train = trains.first(where: { $0.reservation.contains { $0.isSpan(of: id) } }) {
            throw .trackReserved(train.id)
        }
        if isTrafficControlEnabled, let train = firstTrainFouled(removing: id) {
            throw .trackReserved(train)
        }
        if let pair = network.firstPairLeftTooClose(removing: id) {
            throw .tracksWouldBeTooClose(pair.first, pair.second)
        }

        network.removeEdge(id)
        if let number = id.networkNumber {
            disposeAsset(.track, owner: number)
        }
        abandonUnservedPassengers()
    }

    /// The shortest piece either part of a split edge may be: a junction
    /// zone (``RailwayNetwork/junctionZone``, 16 m), so the new node's
    /// junction never reaches past the far end.
    public static let minimumSplitPiece: Int64 = RailwayNetwork.junctionZone

    /// Splits edge `id` of the track network into two edges joined at a new
    /// node `distance` along it from its `from` node, so that new track can
    /// branch from there (a turnout in the middle of a line). Free: the
    /// track is paid for. Returns the new node.
    ///
    /// A straight edge splits into two straight edges at its point
    /// `distance` along. A cubic edge splits at its sampled point nearest
    /// `distance` along (see ``TrackGeometry``), the curve cut there by de
    /// Casteljau's rule with each control point rounded to the nearest unit,
    /// halves up; the parts' geometry and lengths are worked out again from
    /// them. Each part keeps the edge's structure. The parts join each other
    /// at the new node and the edges the old one joined at its ends, and a
    /// platform on the edge moves to the part it lies on, at the same
    /// distances from the edge's `from` node (the second part's less the
    /// first part's length); one that would end past its part's rounded
    /// end moves back to end there, its length kept.
    ///
    /// On a slope (decision 233) the cut must fall on the edge's steady
    /// grade, not on a vertical curve, and the grade must be no steeper
    /// than ``TrackProfile/maximumTurnoutGrade``. The new node takes the
    /// edge's height at the cut (``TrackGeometry/height(at:)``, a whole
    /// unit); the first part keeps the edge's vertical curve at its `from`
    /// end, the second the one at its `to` end, so both run on at the
    /// edge's grade, within the rounding of the node's height.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackEdge(_:)``;
    ///   ``GameError/invalidTrackGeometry`` for a cut less than
    ///   ``minimumSplitPiece`` from either end or on a vertical curve, an
    ///   edge in a spacing exemption, or parts that would not be edges,
    ///   would be steeper than ``TrackProfile/maximumGrade`` or not join as
    ///   it did; ``GameError/turnoutTooSteep`` for an edge steeper than
    ///   ``TrackProfile/maximumTurnoutGrade``;
    ///   ``GameError/trackReserved(_:)`` for the lowest numbered train that
    ///   stands on the edge, has its body on it, will enter it along its
    ///   path or has reserved some of it; ``GameError/trackEdgeHasPlatform(_:)``
    ///   when a platform spans the cut; ``GameError/trackEdgeInLineRoute(_:)``
    ///   for the lowest numbered line whose chosen path runs along it or
    ///   stops at a platform on it; ``GameError/trackConflict(_:)`` or
    ///   ``GameError/trackTooClose(_:)`` when a part would meet other track;
    ///   or ``GameError/idsExhausted``. Since decision 124, before the trains,
    ///   what ``buildTrackEdge(from:to:curve:profile:structure:mountain:)`` throws when
    ///   a part's structure does not suit the ground under it; since decision
    ///   160, after the parts' geometry, ``GameError/mapTileNotOwned(_:)``
    ///   when a part's centre line passes over a tile the company does not
    ///   own. Since decision 282 an automatic edge's parts keep its sections
    ///   (``keptSections(of:part:from:)``), and after them
    ///   ``GameError/buildingOnTrack(_:)`` names the edge when a part's open
    ///   track would come near a company building.
    @discardableResult
    public mutating func splitTrackEdge(_ id: TrackEdgeID, at distance: Int64) throws(GameError) -> TrackNodeID {
        let (edge, geometry, start, end, cut) = try splitCut(id, at: distance)
        // Decision 233: the new node at the edge's height there, rounded as
        // the profile rounds it; the first part keeps the vertical curve at
        // the `from` end, the second the one at the `to` end, so each runs
        // on at the edge's steady grade. A part left level keeps none.
        let middle = WorldCoordinate(x: cut.point.x, y: cut.point.y, z: geometry.height(at: cut.chainage))
        let firstProfile = middle.z == start.position.z ? TrackProfile.uniform : TrackProfile(startTransition: edge.profile.startTransition)
        let secondProfile = middle.z == end.position.z ? TrackProfile.uniform : TrackProfile(endTransition: edge.profile.endTransition)
        guard isInWorld(middle), !network.hasNode(at: middle),
              cut.first.controlPoints.allSatisfy(bounds.contains), cut.second.controlPoints.allSatisfy(bounds.contains),
              let firstGeometry = TrackGeometry(from: start.position, to: middle, curve: cut.first, profile: firstProfile),
              let secondGeometry = TrackGeometry(from: middle, to: end.position, curve: cut.second, profile: secondProfile),
              firstGeometry.steepestGrade.isNoSteeper(than: edge.maximumGrade),
              secondGeometry.steepestGrade.isNoSteeper(than: edge.maximumGrade)
        else { throw .invalidTrackGeometry }
        // Decision 160: each part is sampled afresh, so it is checked on the
        // company's own ground as an edge built is.
        if let tile = firstTileNotOwned(along: firstGeometry.points.map(\.plan))
            ?? firstTileNotOwned(along: secondGeometry.points.map(\.plan)) {
            throw .mapTileNotOwned(tile)
        }
        // Decision 124: each part is carried as the ground under it asks;
        // decision 282: an automatic edge's parts keep its sections, parted
        // at the cut, and no company building comes near their open track.
        let firstSections: [TrackSection], secondSections: [TrackSection]
        if edge.structure == .automatic {
            firstSections = try keptSections(of: edge, part: firstGeometry, from: 0)
            secondSections = try keptSections(of: edge, part: secondGeometry, from: cut.chainage)
        } else {
            firstSections = try sections(of: firstGeometry, structure: edge.structure)
            secondSections = try sections(of: secondGeometry, structure: edge.structure)
        }
        let open = [(firstGeometry, cut.first, firstProfile, firstSections), (secondGeometry, cut.second, secondProfile, secondSections)]
            .flatMap { geometry, curve, profile, sections in
                TrackEdge(id: id, from: edge.from, to: edge.to, curve: curve, length: geometry.length, profile: profile,
                          structure: edge.structure, sections: sections).openStretches(of: geometry)
            }
        guard !placedBuildings.contains(where: { building in open.contains { Self.line($0, comesNear: building) } }) else {
            throw .buildingOnTrack(id)
        }

        var after = network
        let platforms = after.platforms(on: id)
        for platform in platforms {
            guard let index = after.platforms.firstIndex(of: platform) else { continue }
            after.removePlatform(at: index)
        }
        // Decision 716: the parts of a closed edge stay closed, those of
        // one being closed stay so.
        let closure = after.closure(of: id)
        after.removeEdge(id)
        let (_, nodeNext) = try Self.allocateID(from: after.nextNodeNumber)
        let node = after.addNode(at: middle, next: nodeNext)
        if let other = after.firstConflict(from: edge.from, to: node, curve: cut.first, geometry: firstGeometry) {
            throw .trackConflict(other)
        }
        let (_, firstNext) = try Self.allocateID(from: after.nextEdgeNumber)
        let first = after.addEdge(from: edge.from, to: node, curve: cut.first, profile: firstProfile, structure: edge.structure,
                                  sections: firstSections, mountain: edge.mountain, system: edge.system, geometry: firstGeometry,
                                  next: firstNext)
        if let other = after.firstConflict(from: node, to: edge.to, curve: cut.second, geometry: secondGeometry) {
            throw .trackConflict(other)
        }
        let (_, secondNext) = try Self.allocateID(from: after.nextEdgeNumber)
        let second = after.addEdge(from: node, to: edge.to, curve: cut.second, profile: secondProfile, structure: edge.structure,
                                   sections: secondSections, mountain: edge.mountain, system: edge.system, geometry: secondGeometry,
                                   next: secondNext)
        if closure != .open {
            after.setClosure(first, closure)
            after.setClosure(second, closure)
        }
        // Spacing along the ways of the network with both parts: alone,
        // neither reaches the junction where the edge parted from track
        // beside it.
        for part in [first, second] {
            if let other = after.firstTooClose(existing: part, besides: [first, second]) {
                throw .trackTooClose(other)
            }
        }
        // The parts join each other, and at the old ends what the edge did.
        func exits(_ edge: TrackEdgeID, at node: TrackNodeID, in network: RailwayNetwork) -> Set<TrackEdgeID> {
            Set(network.node(node)?.end(of: edge)?.exits ?? [])
        }
        guard exits(first, at: node, in: after) == [second], exits(second, at: node, in: after) == [first],
              exits(first, at: edge.from, in: after) == exits(id, at: edge.from, in: network),
              exits(second, at: edge.to, in: after) == exits(id, at: edge.to, in: network)
        else { throw .invalidTrackGeometry }
        // The parts' lengths are rounded, so one can end a few units short
        // of where the edge did: a platform past its end moves back, its
        // length kept, so a train that fitted it still does.
        func moved(_ platform: TrackPlatform, to part: TrackEdgeID, length: Int64, from offset: Int64) -> TrackPlatform {
            let end = min(platform.end - offset, length)
            let start = max(0, min(platform.start - offset, end - (platform.end - platform.start)))
            return TrackPlatform(station: platform.station, edge: part, start: start, end: end)
        }
        for platform in platforms {
            let moved = platform.end <= cut.chainage
                ? moved(platform, to: first, length: firstGeometry.length, from: 0)
                : moved(platform, to: second, length: secondGeometry.length, from: cut.chainage)
            guard moved.start >= 0, moved.start < moved.end, !after.platforms.contains(where: { $0.overlaps(moved) }) else {
                throw .invalidTrackGeometry
            }
            after.addPlatform(moved)
        }
        after.dropSpacedExemptions()
        network = after
        if let edge = id.networkNumber, let firstNumber = first.networkNumber, let secondNumber = second.networkNumber {
            splitTrackAsset(edge, into: (firstNumber, firstGeometry.length), (secondNumber, secondGeometry.length))
        }
        // Decision 528: what a purchase laid or a line removed left keeps
        // both parts in its place.
        splitAcquiredTrack(id, into: first, second)
        // Decision 204: the lines' journeys run on the parts, as after any
        // other change to the track.
        abandonUnservedPassengers()
        return node
    }

    /// The refusal ``splitTrackEdge(_:at:)`` would meet first among the
    /// checks it makes before working out the parts (decision 378): the
    /// cut, the grade, the trains, a platform and the lines, in that order;
    /// `nil` when they pass, though working out the parts may still refuse
    /// the split. Changes nothing, and costs far less than splitting: a
    /// preview trying many places (a double track's crossovers) skips those
    /// these refuse.
    public func trackEdgeSplitRefusal(_ id: TrackEdgeID, at distance: Int64) -> GameError? {
        do throws(GameError) {
            _ = try splitCut(id, at: distance)
            return nil
        } catch {
            return error
        }
    }

    /// ``splitTrackEdge(_:at:)``'s checks before it works out the parts,
    /// and what they found: the edge, its geometry, its end nodes and the cut.
    private func splitCut(_ id: TrackEdgeID, at distance: Int64) throws(GameError)
        -> (edge: TrackEdge, geometry: TrackGeometry, start: TrackNode, end: TrackNode,
            cut: (first: TrackCurve, second: TrackCurve, point: PlanPoint, chainage: Int64))
    {
        guard let edge = network.edge(id), let geometry = network.geometry(of: id),
              let start = network.node(edge.from), let end = network.node(edge.to) else { throw .unknownTrackEdge(id) }
        guard distance >= Self.minimumSplitPiece, distance <= geometry.length - Self.minimumSplitPiece,
              !network.spacingExemptions.contains(where: { $0.contains(id) }),
              let cut = Self.split(edge.curve, from: start.position.plan, to: end.position.plan, near: distance),
              // Decision 233: on the steady grade, never on a vertical curve.
              cut.chainage >= edge.profile.startTransition, cut.chainage <= geometry.length - edge.profile.endTransition
        else { throw .invalidTrackGeometry }
        guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumTurnoutGrade) else { throw .turnoutTooSteep }
        if let train = trains.first(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == id { return true }
            return train.trailEdges.contains(id) || train.movement.remainingEdges.contains(id)
                || train.reservation.contains { $0.isSpan(of: id) }
        }) {
            throw .trackReserved(train.id)
        }
        guard !network.platforms(on: id).contains(where: { $0.start < cut.chainage && cut.chainage < $0.end }) else {
            throw .trackEdgeHasPlatform(id)
        }
        if let line = lines.first(where: { line in
            (0..<line.serviceCount).contains { service in
                line.routes(ofService: service).contains { route in
                    route.platform.edge == id || route.tracks.contains { $0.edge == id } || route.alternates.contains { $0.edge == id }
                }
            }
        }) {
            throw .trackEdgeInLineRoute(line.id)
        }
        return (edge, geometry, start, end, cut)
    }

    /// Edge `curve` from `p0` to `p3` cut at its sampled point nearest
    /// `distance` along it (see ``splitTrackEdge(_:at:)``): the two parts'
    /// curves, the point, and its chainage along the uncut edge. `nil` when
    /// the cut would fall on an end.
    static func split(_ curve: TrackCurve, from p0: PlanPoint, to p3: PlanPoint, near distance: Int64)
        -> (first: TrackCurve, second: TrackCurve, point: PlanPoint, chainage: Int64)?
    {
        switch curve {
        case .straight:
            guard let geometry = TrackGeometry(from: WorldCoordinate(x: p0.x, y: p0.y, z: 0), to: WorldCoordinate(x: p3.x, y: p3.y, z: 0),
                                               curve: .straight) else { return nil }
            let position = geometry.location(at: distance).position
            let point = PlanPoint(x: position.x, y: position.y)
            guard point != p0, point != p3 else { return nil }
            return (.straight, .straight, point, distance)
        case .cubic(let c1, let c2):
            // The samples of TrackGeometry, kept with their indices.
            let polygon = c1.vector(from: p0).length + c2.vector(from: c1).length + p3.vector(from: c2).length
            var count = TrackGeometry.minimumSamples
            var shift = 9
            while count < TrackGeometry.maximumSamples, count * TrackGeometry.sampleSpacing < polygon {
                count *= 2
                shift += 3
            }
            let unit = shift / 3
            func point(_ step: Int64) -> PlanPoint {
                let rest = count - step
                let w0 = rest * rest * rest, w1 = 3 * rest * rest * step, w2 = 3 * rest * step * step, w3 = step * step * step
                return PlanPoint(x: FixedPoint.roundedShift(w0 * p0.x + w1 * c1.x + w2 * c2.x + w3 * p3.x, by: shift),
                                 y: FixedPoint.roundedShift(w0 * p0.y + w1 * c1.y + w2 * c2.y + w3 * p3.y, by: shift))
            }
            var best: (step: Int64, chainage: Int64)?
            var previous = p0
            var travelled: Int64 = 0
            for step in 1..<count {
                let here = point(step)
                travelled += here.vector(from: previous).length
                previous = here
                if best == nil || abs(travelled - distance) < abs(best!.chainage - distance) {
                    best = (step, travelled)
                }
            }
            guard let best else { return nil }
            let i = best.step, rest = count - i
            func linear(_ a: PlanPoint, _ b: PlanPoint) -> PlanPoint {
                PlanPoint(x: FixedPoint.roundedShift(rest * a.x + i * b.x, by: unit),
                          y: FixedPoint.roundedShift(rest * a.y + i * b.y, by: unit))
            }
            func quadratic(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint) -> PlanPoint {
                let w0 = rest * rest, w1 = 2 * rest * i, w2 = i * i
                return PlanPoint(x: FixedPoint.roundedShift(w0 * a.x + w1 * b.x + w2 * c.x, by: 2 * unit),
                                 y: FixedPoint.roundedShift(w0 * a.y + w1 * b.y + w2 * c.y, by: 2 * unit))
            }
            let middle = point(i)
            let first = TrackCurve.cubic(linear(p0, c1), quadratic(p0, c1, c2))
            let second = TrackCurve.cubic(quadratic(c1, c2, p3), linear(c2, p3))
            guard middle != p0, middle != p3 else { return nil }
            return (first, second, middle, best.chainage)
        }
    }

    /// Removes node `id` of the track network (Stage S3). Free. No edge may
    /// end at it, so no train can be there.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackNode(_:)`` or
    ///   ``GameError/trackNodeInUse(_:)`` while edges end at it.
    public mutating func removeTrackNode(_ id: TrackNodeID) throws(GameError) {
        guard let node = network.node(id) else { throw .unknownTrackNode(id) }
        guard node.ends.isEmpty else { throw .trackNodeInUse(id) }

        network.removeNode(id)
    }

    /// Adds a platform to the railway network for station `id`, along edge
    /// `edge` from `start` to `end` measured from the edge's `from` node
    /// (Phase 4.5 Stage S4). Free: the station has been paid for. A station
    /// may have any number of platforms, straight or curved, at different
    /// levels (surface, elevated, underground); each platform's level is its
    /// edge's height and structure there. Its ends cut the edge's resource
    /// spans (see ``trackSpans(of:)``).
    ///
    /// The stretch must lie within the edge (`0 <= start < end <= length`),
    /// be level (the edge's height at `start` and at `end` is the same, and
    /// heights never turn back along an edge), and not overlap another
    /// platform on the edge, of this station or another.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/unknownTrackEdge(_:)``; ``GameError/invalidPlatform``;
    ///   ``GameError/trainServiceActive(_:)`` naming the lowest numbered
    ///   train whose service stands at a passing place (Stage V2) with its
    ///   head where the platform would be, of the station of its call; or,
    ///   under traffic control (Stage T), ``GameError/trackReserved(_:)``
    ///   while a train holds a span of the edge, whose spans the platform's
    ///   ends would cut.
    public mutating func addTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64, to end: Int64) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard network.edge(edge) != nil else { throw .unknownTrackEdge(edge) }
        let platform = TrackPlatform(station: id, edge: edge, start: start, end: end)
        guard isValidPlatform(platform), !network.platforms.contains(where: { $0.overlaps(platform) }) else {
            throw .invalidPlatform
        }
        // Stage V2: a service at a passing place stands there with its path
        // spent; a platform of its call under its head would stop it at its
        // call without arriving.
        if let train = trains.first(where: { train in
            guard isAtPassingPlace(train), case .travellingToStop(let stop, _)? = train.execution,
                  train.timetable[stop].station == id, let (standing, chainage) = standingPoint(of: train) else { return false }
            return standing == edge && start <= chainage && chainage <= end
        }) {
            throw .trainServiceActive(train.id)
        }
        try requireSpansUnheld(on: edge)

        network.addPlatform(platform)
        abandonUnservedPassengers()
    }

    /// Removes station `id`'s platform on edge `edge` that starts at `start`
    /// (Stage S4). Free.
    ///
    /// A platform a timetable service needs cannot be removed (Stage S5):
    /// one where a service waits at this station with the train's head on
    /// the platform, or one on the edge where a service travelling to this
    /// station ends its path, or one of a passing place it travels to or
    /// stands at, or of the call it goes on to from there (Stage V2). Stop
    /// the service first (for a line's train, take it off the line). So a
    /// waiting service is always stopped at its station, and a travelling
    /// one always has a platform to arrive at.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/invalidPlatform`` when the station has no such
    ///   platform; ``GameError/trainServiceActive(_:)`` naming the
    ///   lowest numbered train whose service needs it; or, under traffic
    ///   control (Stage T), ``GameError/trackReserved(_:)`` while a train
    ///   holds a span of the edge, which removing the platform's ends would
    ///   join to its neighbours.
    public mutating func removeTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard let index = network.platforms.firstIndex(where: { $0.station == id && $0.edge == edge && $0.start == start }) else {
            throw .invalidPlatform
        }
        let platform = network.platforms[index]
        if let train = trains.first(where: { serviceNeeds($0, platform) }) {
            throw .trainServiceActive(train.id)
        }
        try requireSpansUnheld(on: edge)

        network.removePlatform(at: index)
        abandonUnservedPassengers()
    }

    /// Decision 687: lengthens station `id`'s platform on edge `edge` that
    /// starts at `start`, where it stands, to the stretch from `newStart`
    /// to `newEnd`, which holds all of the old one and more. Free, as a
    /// platform is (``addTrackPlatform(_:on:from:to:)``): a platform built
    /// long costs what one built short does. The platform stays on its
    /// edge: it grows only as far as the edge's ends, the level stretch it
    /// lies on and the next platform along (``trackPlatformRoom(of:)``).
    ///
    /// A service waiting at the platform stays at its call (its head is on
    /// the longer platform too), and one on its way arrives as before. A
    /// line's chosen platform (``LineRoutePreference``) that was this one
    /// follows it to its new length.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/invalidPlatform`` when the station has no such
    ///   platform, the new stretch does not hold the old one or is no
    ///   longer, or it does not fit the edge, is not level or overlaps
    ///   another platform; ``GameError/trainServiceActive(_:)`` naming the
    ///   lowest numbered train whose service stands at a passing place
    ///   (Stage V2) with its head on a part the platform would gain, of
    ///   the station of its call; or, under traffic control (Stage T),
    ///   ``GameError/trackReserved(_:)`` while a train holds a span of the
    ///   edge, whose spans the platform's ends cut.
    public mutating func extendTrackPlatform(
        _ id: StationID, on edge: TrackEdgeID, from start: Int64, toStart newStart: Int64, end newEnd: Int64
    ) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard let index = network.platforms.firstIndex(where: { $0.station == id && $0.edge == edge && $0.start == start }) else {
            throw .invalidPlatform
        }
        let old = network.platforms[index]
        let longer = TrackPlatform(station: id, edge: edge, start: newStart, end: newEnd)
        guard newStart <= old.start, old.end <= newEnd, longer.length > old.length, isValidPlatform(longer),
              !network.platforms.contains(where: { $0 != old && $0.overlaps(longer) }) else {
            throw .invalidPlatform
        }
        // As a new platform there (addTrackPlatform): a service at a
        // passing place with its head on a part gained would be at its
        // call without arriving.
        if let train = trains.first(where: { train in
            guard isAtPassingPlace(train), case .travellingToStop(let stop, _)? = train.execution,
                  train.timetable[stop].station == id, let (standing, chainage) = standingPoint(of: train) else { return false }
            return standing == edge && newStart <= chainage && chainage <= newEnd && !(old.start <= chainage && chainage <= old.end)
        }) {
            throw .trainServiceActive(train.id)
        }
        try requireSpansUnheld(on: edge)

        network.replacePlatform(at: index, with: longer)
        for line in lines.indices {
            lines[line].routePreferences = lines[line].routePreferences.map { $0.replacing(old, with: longer) }
            for pattern in lines[line].patterns.indices {
                lines[line].patterns[pattern].routePreferences = lines[line].patterns[pattern].routePreferences.map {
                    $0.replacing(old, with: longer)
                }
            }
        }
        abandonUnservedPassengers()
    }

    /// Decision 687: how far `platform` could be lengthened
    /// (``extendTrackPlatform(_:on:from:toStart:end:)``) towards each end
    /// of its edge: over level track, up to the edge's end or the next
    /// platform along. `nil` when the network has no such platform.
    public func trackPlatformRoom(of platform: TrackPlatform) -> (before: Int64, after: Int64)? {
        guard network.platforms.contains(platform), let geometry = network.geometry(of: platform.edge) else { return nil }
        let others = network.platforms(on: platform.edge).filter { $0 != platform }
        var low = others.filter { $0.end <= platform.start }.map(\.end).max() ?? 0
        var high = others.filter { $0.start >= platform.end }.map(\.start).min() ?? geometry.length
        // Heights never turn back along an edge, so the level stretch
        // round the platform is one run: halve towards where it ends.
        let level = geometry.height(at: platform.start)
        var known = platform.start
        while low < known {
            let middle = low + (known - low) / 2
            if geometry.height(at: middle) == level { known = middle } else { low = middle + 1 }
        }
        known = platform.end
        while known < high {
            let middle = known + (high - known + 1) / 2
            if geometry.height(at: middle) == level { known = middle } else { high = middle - 1 }
        }
        return (platform.start - low, high - platform.end)
    }

    // MARK: - Decision 691: a station's tracks lengthened with their turnouts

    /// Decision 691: a station's tracks between its two turnouts: the main
    /// track, an edge straight from one turnout to the other, and each
    /// loop beside it, a connector out from the near turnout (the main
    /// edge's `from` node), a straight track along and a connector back to
    /// the far one. What the platform track tool builds, and any track
    /// laid by hand to the same shape.
    struct StationThroat {
        struct Loop {
            let out: TrackEdgeID
            let along: TrackEdge
            let back: TrackEdgeID
            /// The along edge's node on the near turnout's side, and the other.
            let start: TrackNodeID
            let end: TrackNodeID
        }

        let main: TrackEdge
        /// The line beyond the near turnout, and beyond the far one.
        let outerNear: TrackEdge
        let outerFar: TrackEdge
        let loops: [Loop]

        /// The tracks a platform can stand on: the main one and each loop's.
        var tracks: [TrackEdgeID] { [main.id] + loops.map(\.along.id) }
        /// Every edge a turnout's move reshapes.
        var edges: [TrackEdgeID] { [outerNear.id, main.id, outerFar.id] + loops.flatMap { [$0.out, $0.along.id, $0.back] } }
        /// Every node a turnout's move moves.
        var nodes: [TrackNodeID] { [main.from, main.to] + loops.flatMap { [$0.start, $0.end] } }

        /// Whether `track`'s `from` node is on the near turnout's side.
        func runsWithMain(_ track: TrackEdgeID) -> Bool {
            loops.first { $0.along.id == track }.map { $0.along.from == $0.start } ?? true
        }
    }

    /// How far past what a platform's lengthening needs a turnout moves
    /// (decision 691): 2 units, 3 cm. The moved nodes stand on whole
    /// units, so a track's new length is within 2 units of the sum.
    static let loopExtensionMargin: Int64 = 2

    /// Whether `edge` is straight and level. The track tools lay a
    /// straight track as a curve whose two control points lie on the line
    /// between its ends, a third and two thirds along.
    private func isLevelStraight(_ edge: TrackEdge) -> Bool {
        guard edge.profile == .uniform, edge.from != edge.to,
              let from = network.node(edge.from), let to = network.node(edge.to), from.position.z == to.position.z else { return false }
        guard case .cubic(let first, let second) = edge.curve else { return true }
        let line = to.position.plan.vector(from: from.position.plan)
        let a = first.vector(from: from.position.plan), b = second.vector(from: from.position.plan)
        let along = line.dot(line)
        return abs(a.cross(line)) <= 2 * line.length && abs(b.cross(line)) <= 2 * line.length
            && a.dot(line) > 0 && a.dot(line) < b.dot(line) && b.dot(line) < along
    }

    /// The line beyond `main` at its node `id` and the connectors that
    /// leave the line there, when the node is a station's turnout: a train
    /// from the line may go on along any of the others, and each of them
    /// leads only to the line.
    private func throatEnd(of main: TrackEdge, at id: TrackNodeID) -> (outer: TrackEdge, connectors: [TrackEdgeID])? {
        guard let node = network.node(id), node.ends.count >= 3, let exits = node.end(of: main.id)?.exits, exits.count == 1,
              let outer = network.edge(exits[0]), isLevelStraight(outer) else { return nil }
        let connectors = node.ends.map(\.edge).filter { $0 != main.id && $0 != outer.id }
        guard connectors.allSatisfy({ node.end(of: $0)?.exits == [outer.id] }),
              Set(node.end(of: outer.id)?.exits ?? []) == Set(connectors + [main.id]) else { return nil }
        return (outer, connectors)
    }

    /// The station throat whose main track is `main`, or `nil`.
    private func stationThroat(main: TrackEdge) -> StationThroat? {
        guard isLevelStraight(main), let near = throatEnd(of: main, at: main.from), let far = throatEnd(of: main, at: main.to),
              near.connectors.count == far.connectors.count,
              let nearNode = network.node(main.from)?.position.plan, let farNode = network.node(main.to)?.position.plan else { return nil }
        let way = farNode.vector(from: nearNode)
        // The line runs straight on through each turnout: a turnout slides
        // along it without bending the main track.
        func isOnLine(_ point: PlanPoint, from a: PlanPoint, to b: PlanPoint) -> Bool {
            let line = b.vector(from: a)
            return abs(point.vector(from: a).cross(line)) <= 2 * line.length
        }
        guard let beyondNear = network.node(near.outer.from == main.from ? near.outer.to : near.outer.from)?.position.plan,
              let beyondFar = network.node(far.outer.from == main.to ? far.outer.to : far.outer.from)?.position.plan,
              isOnLine(nearNode, from: beyondNear, to: farNode), isOnLine(farNode, from: nearNode, to: beyondFar) else { return nil }
        var backs = Set(far.connectors)
        var loops: [StationThroat.Loop] = []
        for out in near.connectors {
            guard let outEdge = network.edge(out) else { return nil }
            let startID = outEdge.from == main.from ? outEdge.to : outEdge.from
            guard let start = network.node(startID), start.ends.count == 2,
                  let along = start.ends.first(where: { $0.edge != out }).flatMap({ network.edge($0.edge) }), isLevelStraight(along) else { return nil }
            let endID = along.from == startID ? along.to : along.from
            guard let end = network.node(endID), end.ends.count == 2,
                  let back = end.ends.first(where: { $0.edge != along.id })?.edge, backs.remove(back) != nil else { return nil }
            // Beside the main track, the same way.
            let beside = end.position.plan.vector(from: start.position.plan)
            guard beside.dot(way) > 0, abs(beside.cross(way)) <= beside.length * way.length / 256 else { return nil }
            loops.append(StationThroat.Loop(out: out, along: along, back: back, start: startID, end: endID))
        }
        let throat = StationThroat(main: main, outerNear: near.outer, outerFar: far.outer, loops: loops)
        guard Set(throat.edges).count == throat.edges.count, Set(throat.nodes).count == throat.nodes.count,
              !network.spacingExemptions.contains(where: { pair in throat.edges.contains { pair.contains($0) } }) else { return nil }
        return throat
    }

    /// The station throat `edge` is a track of (its main track or a
    /// loop's), or `nil`.
    func stationThroat(of id: TrackEdgeID) -> StationThroat? {
        guard let edge = network.edge(id) else { return nil }
        if let throat = stationThroat(main: edge) { return throat }
        guard let from = network.node(edge.from), let to = network.node(edge.to), from.ends.count == 2, to.ends.count == 2,
              let out = from.ends.first(where: { $0.edge != id }).flatMap({ network.edge($0.edge) }),
              let back = to.ends.first(where: { $0.edge != id }).flatMap({ network.edge($0.edge) }) else { return nil }
        let turnouts: Set<TrackNodeID> = [out.from == edge.from ? out.to : out.from, back.from == edge.to ? back.to : back.from]
        for end in network.node(out.from == edge.from ? out.to : out.from)?.ends ?? [] {
            guard let main = network.edge(end.edge), Set([main.from, main.to]) == turnouts, main.id != out.id, main.id != back.id,
                  let throat = stationThroat(main: main), throat.loops.contains(where: { $0.along.id == id }) else { continue }
            return throat
        }
        return nil
    }

    /// How far the turnout at one end of `throat` can move out along the
    /// line: the line beyond it stays a split's least piece long
    /// (``minimumSplitPiece``) and keeps its platforms.
    private func reach(of throat: StationThroat, near: Bool) -> Int64 {
        let outer = near ? throat.outerNear : throat.outerFar, node = near ? throat.main.from : throat.main.to
        var reach = outer.length - Self.minimumSplitPiece
        for platform in network.platforms(on: outer.id) {
            reach = min(reach, outer.from == node ? platform.start : outer.length - platform.end)
        }
        return max(0, reach - Self.loopExtensionMargin)
    }

    /// Decision 691: how far past the ends of its edge `platform` could be
    /// lengthened by moving the station's turnouts out
    /// (``extendPlatformLoop(_:on:from:toStart:end:)``), at each end of its
    /// edge; with ``trackPlatformRoom(of:)``, all the room it has. `nil`
    /// when the platform is not on a track between a station's two
    /// turnouts (``StationThroat``).
    public func platformLoopRoom(of platform: TrackPlatform) -> (before: Int64, after: Int64)? {
        guard network.platforms.contains(platform), let throat = stationThroat(of: platform.edge) else { return nil }
        let near = reach(of: throat, near: true), far = reach(of: throat, near: false)
        return throat.runsWithMain(platform.edge) ? (near, far) : (far, near)
    }

    /// How a platform `extra` longer grows at its two ends, with room for
    /// `before` and `after` (decision 687): half to each end; what one end
    /// has no room for goes to the other. `nil` when there is no room for
    /// it all.
    public static func platformGrowth(_ extra: Int64, before: Int64, after: Int64) -> (before: Int64, after: Int64)? {
        guard extra > 0, before >= 0, after >= 0, extra - before <= after else { return nil }
        var first = min(before, extra / 2)
        var second = extra - first
        if second > after {
            second = after
            first = extra - second
        }
        return (first, second)
    }

    /// A platform a station's lengthening lengthens (decision 691): how
    /// far towards each turnout, and the room it has on its own edge.
    private struct GrowingPlatform {
        let platform: TrackPlatform
        /// Whether its edge runs from the near turnout's side.
        let forward: Bool
        let near: Int64
        let far: Int64
        let roomNear: Int64
        let roomFar: Int64

        /// How far it grows towards its edge's `from` node, and its `to`.
        var before: Int64 { forward ? near : far }
        var after: Int64 { forward ? far : near }
    }

    /// What ``extendPlatformLoop(_:on:from:toStart:end:)`` does to the
    /// track, worked out before anything changes: the platforms that grow
    /// and how far each turnout moves.
    private struct LoopShift {
        let throat: StationThroat
        let growing: [GrowingPlatform]
        /// How far the near and the far turnout move out; 0 when it stays.
        let near: Int64
        let far: Int64
    }

    private func loopShift(
        _ id: StationID, on edge: TrackEdgeID, from start: Int64, toStart newStart: Int64, end newEnd: Int64
    ) throws(GameError) -> LoopShift {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        let limit = Int64(1) << 40
        guard let old = network.platforms.first(where: { $0.station == id && $0.edge == edge && $0.start == start }),
              -limit < newStart, newStart <= old.start, old.end <= newEnd, newEnd < limit, newEnd - newStart > old.length,
              let throat = stationThroat(of: edge) else { throw .invalidPlatform }
        let reach = (near: reach(of: throat, near: true), far: reach(of: throat, near: false))
        let length = newEnd - newStart
        func room(_ platform: TrackPlatform) -> (forward: Bool, near: Int64, far: Int64)? {
            guard let room = trackPlatformRoom(of: platform) else { return nil }
            let forward = throat.runsWithMain(platform.edge)
            return (forward, forward ? room.before : room.after, forward ? room.after : room.before)
        }
        guard let own = room(old) else { throw .invalidPlatform }
        let before = old.start - newStart, after = newEnd - old.end
        let asked = GrowingPlatform(platform: old, forward: own.forward, near: own.forward ? before : after, far: own.forward ? after : before,
                                    roomNear: own.near, roomFar: own.far)
        guard asked.near <= asked.roomNear + reach.near, asked.far <= asked.roomFar + reach.far else { throw .invalidPlatform }
        var growing = [asked]
        // The station's platform on each other track grows to the same
        // length where it is shorter and has the room: as the asked one
        // does when they are as long, so two platforms side by side stay
        // side by side.
        for track in throat.tracks where track != edge {
            let partners = network.platforms(on: track).filter { $0.station == id }
            guard partners.count == 1, partners[0].length < length, let room = room(partners[0]) else { continue }
            let most = (near: room.near + reach.near, far: room.far + reach.far)
            let growth: (before: Int64, after: Int64)
            if partners[0].length == old.length, asked.near <= most.near, asked.far <= most.far {
                growth = (asked.near, asked.far)
            } else if let halves = Self.platformGrowth(length - partners[0].length, before: most.near, after: most.far) {
                growth = halves
            } else {
                continue
            }
            growing.append(GrowingPlatform(platform: partners[0], forward: room.forward, near: growth.before, far: growth.after,
                                           roomNear: room.near, roomFar: room.far))
        }
        let near = growing.map { $0.near - $0.roomNear }.max() ?? 0, far = growing.map { $0.far - $0.roomFar }.max() ?? 0
        return LoopShift(throat: throat, growing: growing, near: near > 0 ? near + Self.loopExtensionMargin : 0,
                         far: far > 0 ? far + Self.loopExtensionMargin : 0)
    }

    /// Where the turnout at `node` of `outer` stands once moved `distance`
    /// out along it.
    private func slid(_ node: TrackNodeID, along outer: TrackEdge, by distance: Int64) -> WorldCoordinate? {
        guard let here = network.node(node)?.position, let geometry = network.geometry(of: outer.id), distance <= geometry.length else { return nil }
        guard distance > 0 else { return here }
        let point = geometry.location(at: outer.from == node ? distance : geometry.length - distance).position
        return WorldCoordinate(x: point.x, y: point.y, z: here.z)
    }

    /// The track and platforms after a ``LoopShift``, its price and what
    /// else changes with it.
    private struct LoopExtensionPlan {
        var network: RailwayNetwork
        /// What the longer loops cost, by their along edge's number.
        var prices: [(edge: Int, cost: Money)] = []
        var cleared: [PlacedBuilding] = []
        /// Each platform whose stretch changed, and what it became.
        var replaced: [(old: TrackPlatform, new: TrackPlatform)] = []
        /// How far each reshaped edge grew at its `from` node and at its `to`.
        var grown: [TrackEdgeID: (from: Int64, to: Int64)] = [:]

        var price: Money { Money(prices.reduce(0) { $0 + $1.cost.amount }) }
    }

    private func loopExtensionPlan(_ shift: LoopShift) throws(GameError) -> LoopExtensionPlan {
        let throat = shift.throat
        let ids = throat.edges
        let olds = ids.compactMap { network.edge($0) }
        guard olds.count == ids.count,
              let near = slid(throat.main.from, along: throat.outerNear, by: shift.near),
              let far = slid(throat.main.to, along: throat.outerFar, by: shift.far),
              let nearNow = network.node(throat.main.from)?.position, let farNow = network.node(throat.main.to)?.position
        else { throw .invalidTrackGeometry }
        let nearWay = near.plan.vector(from: nearNow.plan), farWay = far.plan.vector(from: farNow.plan)
        func moved(_ point: PlanPoint, by way: PlanVector) -> PlanPoint { PlanPoint(x: point.x + way.dx, y: point.y + way.dy) }
        func moved(_ curve: TrackCurve, by way: PlanVector) -> TrackCurve {
            switch curve {
            case .straight: .straight
            case .cubic(let first, let second): .cubic(moved(first, by: way), moved(second, by: way))
            }
        }

        var plan = LoopExtensionPlan(network: network)
        let platforms = network.platforms.filter { ids.contains($0.edge) }
        for platform in platforms {
            guard let index = plan.network.platforms.firstIndex(of: platform) else { continue }
            plan.network.removePlatform(at: index)
        }
        for id in ids { plan.network.removeEdge(id, updatingFouling: false) }
        var curves: [TrackEdgeID: TrackCurve] = [:]
        var positions: [(TrackNodeID, WorldCoordinate)] = [(throat.main.from, near), (throat.main.to, far)]
        plan.grown[throat.main.id] = (shift.near, shift.far)
        plan.grown[throat.outerNear.id] = throat.outerNear.from == throat.main.from ? (-shift.near, 0) : (0, -shift.near)
        plan.grown[throat.outerFar.id] = throat.outerFar.from == throat.main.to ? (-shift.far, 0) : (0, -shift.far)
        for loop in throat.loops {
            guard let start = network.node(loop.start)?.position, let end = network.node(loop.end)?.position,
                  let out = network.edge(loop.out), let back = network.edge(loop.back) else { throw .invalidTrackGeometry }
            let startPlan = moved(start.plan, by: nearWay), endPlan = moved(end.plan, by: farWay)
            positions.append((loop.start, WorldCoordinate(x: startPlan.x, y: startPlan.y, z: start.z)))
            positions.append((loop.end, WorldCoordinate(x: endPlan.x, y: endPlan.y, z: end.z)))
            curves[loop.out] = moved(out.curve, by: nearWay)
            curves[loop.back] = moved(back.curve, by: farWay)
            plan.grown[loop.along.id] = loop.along.from == loop.start ? (shift.near, shift.far) : (shift.far, shift.near)
        }
        for (node, position) in positions {
            guard isInWorld(position) else { throw .invalidTrackGeometry }
            plan.network.moveNode(node, to: position)
        }
        guard positions.allSatisfy({ moved in plan.network.nodes.filter { $0.position == moved.1 }.count == 1 }) else { throw .invalidTrackGeometry }

        var geometries: [TrackEdgeID: (geometry: TrackGeometry, sections: [TrackSection])] = [:]
        for old in olds {
            guard let from = plan.network.node(old.from), let to = plan.network.node(old.to) else { throw .invalidTrackGeometry }
            // A straight track stays the kind of curve it was: its control
            // points a third and two thirds along again.
            var curve = curves[old.id] ?? old.curve
            if curves[old.id] == nil, case .cubic = old.curve {
                let a = from.position.plan, b = to.position.plan
                curve = .cubic(
                    PlanPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3),
                    PlanPoint(x: a.x + (b.x - a.x) * 2 / 3, y: a.y + (b.y - a.y) * 2 / 3)
                )
            }
            guard curve.controlPoints.allSatisfy(bounds.contains),
                  let geometry = TrackGeometry(from: from.position, to: to.position, curve: curve, profile: old.profile),
                  geometry.steepestGrade.isNoSteeper(than: old.maximumGrade) else { throw .invalidTrackGeometry }
            if let tile = firstTileNotOwned(along: geometry.points.map(\.plan)) { throw .mapTileNotOwned(tile) }
            let sections = try sections(of: geometry, structure: old.structure)
            if let other = plan.network.firstConflict(from: old.from, to: old.to, curve: curve, geometry: geometry) { throw .trackConflict(other) }
            plan.network.restoreEdge(old, curve: curve, sections: sections, geometry: geometry)
            // Decision 716: closed, or being closed, as it was.
            if network.closure(of: old.id) != .open { plan.network.setClosure(old.id, network.closure(of: old.id)) }
            geometries[old.id] = (geometry, sections)
        }
        for id in ids {
            if let other = plan.network.firstTooClose(existing: id, besides: []) { throw .trackTooClose(other) }
        }
        // Every end joins what it joined.
        let touched = Set(olds.flatMap { [$0.from, $0.to] })
        for id in touched {
            guard let before = network.node(id), let after = plan.network.node(id), before.ends.count == after.ends.count,
                  zip(before.ends, after.ends).allSatisfy({ $0.edge == $1.edge && Set($0.exits) == Set($1.exits) })
            else { throw .invalidTrackGeometry }
        }

        // The platforms again, where their track lies now: each as far from
        // the same place on the ground as it was, the growing ones longer.
        for platform in platforms {
            guard let length = plan.network.edge(platform.edge)?.length else { continue }
            let grown = plan.grown[platform.edge] ?? (0, 0)
            var start = platform.start + grown.from, end = platform.end + grown.from
            let longer = shift.growing.first { $0.platform == platform }
            if let longer {
                start -= longer.before
                end += longer.after
                // The moved nodes stand on whole units: within a few of
                // an end of its track, the platform runs to that end.
                if start <= 4 * Self.loopExtensionMargin { start = 0 }
                if length - end <= 4 * Self.loopExtensionMargin { end = length }
                guard end - start >= platform.length + longer.before + longer.after else { throw .invalidPlatform }
            } else {
                end = min(end, length)
                start = max(0, min(start, end - platform.length))
            }
            let moved = TrackPlatform(station: platform.station, edge: platform.edge, start: start, end: end)
            guard start >= 0, start < end, end <= length, !plan.network.platforms.contains(where: { $0.overlaps(moved) }) else { throw .invalidPlatform }
            plan.network.addPlatform(moved)
            if moved != platform { plan.replaced.append((platform, moved)) }
        }
        plan.network.dropSpacedExemptions()
        var changed = Set(ids)
        for (a, b) in zip(throat.nodes, throat.nodes.dropFirst()) {
            changed.formUnion(network.edgesNear(a, b))
            changed.formUnion(plan.network.edgesNear(a, b))
        }
        plan.network.refreshFouling(of: changed)

        // What the longer loops cost beyond what they did, and what stands
        // in their way (decision 95). The main track lies where it lay.
        for loop in throat.loops {
            var new: Int64 = 0, old: Int64 = 0
            for id in [loop.out, loop.along.id, loop.back] {
                guard let edge = network.edge(id), let was = network.geometry(of: id), let now = geometries[id] else { throw .invalidTrackGeometry }
                old += try edgeCost(of: was, structure: edge.structure, sections: edge.sections, system: edge.system).amount
                let (sum, overflow) = new.addingReportingOverflow(
                    try edgeCost(of: now.geometry, structure: edge.structure, sections: now.sections, system: edge.system).amount)
                guard !overflow else { throw .insufficientFunds(required: Money(.max), available: economy.balance) }
                new = sum
                let open = TrackEdge(id: id, from: edge.from, to: edge.to, curve: curves[id] ?? edge.curve, length: now.geometry.length,
                                     profile: edge.profile, structure: edge.structure, sections: now.sections).openStretches(of: now.geometry)
                for building in placedBuildings where !plan.cleared.contains(building) && open.contains(where: { Self.line($0, comesNear: building) }) {
                    plan.cleared.append(building)
                }
            }
            plan.prices.append((loop.along.id.networkNumber ?? 0, Money(max(0, new - old))))
        }
        guard plan.prices.reduce(Int64(0), { $0.addingReportingOverflow($1.cost.amount).overflow ? .max : $0 + $1.cost.amount }) < .max else {
            throw .insufficientFunds(required: Money(.max), available: economy.balance)
        }
        return plan
    }

    /// Decision 691: what ``extendPlatformLoop(_:on:from:toStart:end:)``
    /// would do now, whatever trains are about and whatever the company
    /// has. Changes nothing.
    ///
    /// - Throws: what the command would, but for the trains and the money.
    public func platformLoopExtensionPreview(
        _ id: StationID, on edge: TrackEdgeID, from start: Int64, toStart newStart: Int64, end newEnd: Int64
    ) throws(GameError) -> PlatformLoopExtensionPreview {
        let shift = try loopShift(id, on: edge, from: start, toStart: newStart, end: newEnd)
        // Within each platform's own room (``trackPlatformRoom(of:)``).
        guard shift.near > 0 || shift.far > 0 else {
            return PlatformLoopExtensionPreview(cost: .zero, platforms: shift.growing.count, movesTurnouts: false)
        }
        let plan = try loopExtensionPlan(shift)
        let (total, overflow) = plan.price.amount.addingReportingOverflow(clearingCost(of: plan.cleared).amount)
        return PlatformLoopExtensionPreview(cost: Money(overflow ? .max : total), platforms: shift.growing.count, movesTurnouts: true)
    }

    /// Decision 691: the places on the ground the new track of
    /// ``extendPlatformLoop(_:on:from:toStart:end:)`` would lie over that
    /// the station's track does not lie over now, for a world with ground
    /// to read it there first. Empty when the command would be refused
    /// before its track is worked out, or moves no turnout.
    public func platformLoopExtensionGround(
        _ id: StationID, on edge: TrackEdgeID, from start: Int64, toStart newStart: Int64, end newEnd: Int64
    ) -> [PlanPoint] {
        guard let shift = try? loopShift(id, on: edge, from: start, toStart: newStart, end: newEnd) else { return [] }
        var points: [PlanPoint] = []
        let throat = shift.throat
        for (turnout, outer, distance, near) in [(throat.main.from, throat.outerNear, shift.near, true), (throat.main.to, throat.outerFar, shift.far, false)]
        where distance > 0 {
            guard let here = network.node(turnout)?.position.plan else { continue }
            var along: Int64 = 0
            while true {
                along = min(distance, along + ConstructionCosts.trackPricingLength / 2)
                guard let there = slid(turnout, along: outer, by: along)?.plan else { break }
                let way = there.vector(from: here)
                for loop in throat.loops {
                    guard let beside = network.node(near ? loop.start : loop.end)?.position.plan else { continue }
                    let moved = PlanPoint(x: beside.x + way.dx, y: beside.y + way.dy)
                    points.append(moved)
                    points.append(PlanPoint(x: (moved.x + there.x) / 2, y: (moved.y + there.y) / 2))
                }
                if along == distance { break }
            }
        }
        return points
    }

    /// Lengthens each of `growing` on its own edge
    /// (``extendTrackPlatform(_:on:from:toStart:end:)``).
    private mutating func lengthen(_ growing: [GrowingPlatform]) throws(GameError) {
        for longer in growing {
            let platform = longer.platform
            try extendTrackPlatform(platform.station, on: platform.edge, from: platform.start,
                                    toStart: platform.start - longer.before, end: platform.end + longer.after)
        }
    }

    /// Decision 691: lengthens station `id`'s platform on edge `edge` that
    /// starts at `start` to the stretch from `newStart` to `newEnd`,
    /// measured along its edge as it lies now, which may reach past the
    /// edge's ends when the platform stands between a station's two
    /// turnouts (``StationThroat``): a turnout the stretch reaches past
    /// moves out along the line with everything joined to it. The main
    /// track and each loop's track grow by as much, each loop's
    /// connectors keep their shape, and every node and edge keeps its ID,
    /// so the lines' chosen tracks stay chosen. The station's platform on
    /// each other track between the turnouts grows to the same length
    /// where it is shorter and has the room. A platform track built with
    /// its platform from end to end (the platform track tool's) could not
    /// be lengthened at all (``extendTrackPlatform(_:on:from:toStart:end:)``
    /// stays on its edge).
    ///
    /// Charges what the longer loops cost beyond what they cost as they
    /// were (the main track lies where it lay; a platform is free), and
    /// clears the company's buildings in their way (decision 95). When no
    /// turnout need move it lengthens the platforms where they stand, free.
    ///
    /// A train on its way whose path runs through the station keeps its
    /// path and stops where it would have. All or nothing.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/invalidPlatform`` when the station has no such
    ///   platform, the new stretch does not hold the old one or is no
    ///   longer, the platform is not between a station's turnouts, or the
    ///   stretch reaches farther than a turnout can move
    ///   (``platformLoopRoom(of:)``); when no turnout moves, what
    ///   ``extendTrackPlatform(_:on:from:toStart:end:)`` throws; otherwise
    ///   what ``buildTrackEdge(from:to:curve:profile:structure:mountain:)``
    ///   throws for the reshaped track, ``GameError/invalidPlatform`` for
    ///   a platform that no longer fits its track;
    ///   ``GameError/trackReserved(_:)`` naming the lowest numbered train
    ///   that stands on the station's track or the line next to a turnout,
    ///   has its body there, has reserved or (under traffic control)
    ///   holds some of it, or whose path ends there where no track would
    ///   be; or ``GameError/insufficientFunds(required:available:)``.
    public mutating func extendPlatformLoop(
        _ id: StationID, on edge: TrackEdgeID, from start: Int64, toStart newStart: Int64, end newEnd: Int64
    ) throws(GameError) {
        let shift = try loopShift(id, on: edge, from: start, toStart: newStart, end: newEnd)
        guard shift.near > 0 || shift.far > 0 else {
            var after = self
            try after.lengthen(shift.growing)
            self = after
            return
        }
        let plan = try loopExtensionPlan(shift)
        let edges = Set(shift.throat.edges), nodes = shift.throat.nodes
        // Where each train's path ends, measured along its last edge as it
        // will lie.
        var ends: [(train: Int, end: Int64)] = []
        for (index, train) in trains.enumerated() {
            guard case .onEdge(let traversal, _)? = train.position else { continue }
            let holds = edges.contains(traversal.edge) || train.trailEdges.contains(where: edges.contains)
                || train.reservation.contains { resource in edges.contains { resource.isSpan(of: $0) } }
                || (isTrafficControlEnabled && held(train).contains { resource in
                    edges.contains { resource.isSpan(of: $0) } || nodes.contains { isWithinJunctionZone(resource, of: $0) }
                })
            guard !holds else { throw .trackReserved(train.id) }
            guard let end = train.movement.end, let last = train.movement.remainingEdges.last, let grown = plan.grown[last],
                  grown.from != 0 || grown.to != 0 else { continue }
            // Which way it runs along its last edge: followed from where it is.
            var node = network.edge(traversal.edge)?.end(of: traversal.direction)
            var forward: Bool?
            for id in train.movement.remainingEdges {
                guard let edge = network.edge(id), let here = node, edge.from == here || edge.to == here else { throw .trackReserved(train.id) }
                forward = edge.from == here
                node = forward == true ? edge.to : edge.from
            }
            let moved = end + (forward == true ? grown.from : grown.to)
            guard let length = plan.network.edge(last)?.length, moved > 0, moved < length else { throw .trackReserved(train.id) }
            ends.append((index, moved))
        }
        try checkFunds(plan.price, clearing: plan.cleared)
        try economy.spend(plan.price)

        network = plan.network
        for (old, new) in plan.replaced {
            for line in lines.indices {
                lines[line].routePreferences = lines[line].routePreferences.map { $0.replacing(old, with: new) }
                for pattern in lines[line].patterns.indices {
                    lines[line].patterns[pattern].routePreferences = lines[line].patterns[pattern].routePreferences.map {
                        $0.replacing(old, with: new)
                    }
                }
            }
        }
        for (index, end) in ends { trains[index].movement.end = end }
        for (edge, cost) in plan.prices { extendTrackAsset(edge, cost: cost) }
        clear(plan.cleared)
        abandonUnservedPassengers()
    }

    /// Whether `train`'s service needs `platform` (Stage S5): it waits at
    /// the platform's station with its head on the platform, or travels to
    /// that station along a path whose last edge is the platform's. Since
    /// Stage V2 also a passing place's (see ``isAtPassingPlace(_:)``): the
    /// platform of another station a service travels to, or stands at with
    /// its head on it, and while it stands there, every platform of its
    /// call, which it goes on to from there.
    private func serviceNeeds(_ train: Train, _ platform: TrackPlatform) -> Bool {
        guard let execution = train.execution,
              case .onEdge(let traversal, let offset)? = train.position, let edge = network.edge(traversal.edge)
        else { return false }
        let call = train.timetable[execution.stop].station
        let chainage = traversal.direction == .forward ? offset : edge.length - offset
        let headOn = traversal.edge == platform.edge && platform.start <= chainage && chainage <= platform.end
        switch execution {
        case .waitingAtStop:
            return platform.station == call && headOn
        case .travellingToStop:
            if isAtPassingPlace(train) { return headOn || platform.station == call }
            guard (train.movement.remainingEdges.last ?? traversal.edge) == platform.edge else { return false }
            return platform.station == call
                || (!pathEndsAtBerth(of: train, for: call) && pathEndsAtBerth(of: train, for: platform.station))
        }
    }

    /// Under traffic control (Stage T), refuses a change to the spans of
    /// `edge` while a train holds any of them (it stands on them or has
    /// reserved them): a reserved span must keep its meaning, and two trains
    /// in neighbouring spans must not end up sharing one.
    private func requireSpansUnheld(on edge: TrackEdgeID) throws(GameError) {
        guard isTrafficControlEnabled, let train = trains.first(where: { held($0).contains { $0.isSpan(of: edge) } }) else { return }
        throw .trackReserved(train.id)
    }

    /// The platforms of station `id` on the track network, in order along
    /// the track (Stage S4); empty for none or an unknown station.
    public func trackPlatforms(of id: StationID) -> [TrackPlatform] {
        network.platforms(of: id)
    }

    /// Whether `platform` fits its edge: the edge exists, the stretch lies
    /// within it and is level.
    private func isValidPlatform(_ platform: TrackPlatform) -> Bool {
        guard let geometry = network.geometry(of: platform.edge) else { return false }
        return 0 <= platform.start && platform.start < platform.end && platform.end <= geometry.length
            && geometry.height(at: platform.start) == geometry.height(at: platform.end)
    }

    /// Whether a node at `position` would lie in the world's ``bounds``, at
    /// a height within ``RailwayNetwork/heightRange`` of the ground there
    /// (decision 124; 0 in a world without ground), which the world has
    /// read.
    private func isInWorld(_ position: WorldCoordinate) -> Bool {
        guard bounds.contains(position.plan), let ground = groundHeight(at: position.plan) else { return false }
        return RailwayNetwork.heightRange.contains(position.z - ground)
    }

    /// Throws ``GameError/insufficientFunds(required:available:)`` unless
    /// the balance covers `price` and clearing `cleared` together
    /// (decision 95).
    private func checkFunds(_ price: Money, clearing cleared: [PlacedBuilding]) throws(GameError) {
        let (total, overflow) = price.amount.addingReportingOverflow(clearingCost(of: cleared).amount)
        guard !overflow, economy.canAfford(Money(total)) else {
            throw .insufficientFunds(required: overflow ? Money(.max) : Money(total), available: economy.balance)
        }
    }


    /// Builds a station standing at `point` (Stage F1) and charges
    /// ``ConstructionCosts/station``. Other stations may stand anywhere
    /// near it. It has no platforms until the track network gives it some
    /// (``addTrackPlatform(_:on:from:to:)``). Since decision 95 the
    /// company's buildings closer than the clearance to `point` come down
    /// with it, for what demolishing them costs.
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/outOfBounds(_:)`` naming `point` when it lies outside
    ///   the world's ``bounds``, ``GameError/mapTileNotOwned(_:)`` on a
    ///   tile of the map the company does not own (decision 160),
    ///   ``GameError/onWater(row:column:)`` in a
    ///   world with ground when `point` lies over water (decision 124),
    ///   ``GameError/idsExhausted``, or
    ///   ``GameError/insufficientFunds(required:available:)`` for the
    ///   station and the clearing together.
    @discardableResult
    public mutating func buildStation(named name: String, at point: PlanPoint) throws(GameError) -> Station {
        guard Self.isValidName(name) else { throw .invalidName }
        guard bounds.contains(point) else { throw .outOfBounds(point) }
        // Decision 160: on the company's own ground.
        guard ownsGround(at: point) else { throw .mapTileNotOwned(MapExpansion.tile(at: point)) }
        // Decision 124: in a world with ground, not on water (a platform
        // may still lie on a bridge).
        let row = Land.cellIndex(point.y), column = Land.cellIndex(point.x)
        if ground.isMapped, terrain.isWater(row: row, column: column) { throw .onWater(row: row, column: column) }
        let (id, nextID) = try Self.allocateID(from: nextStationID)
        let cleared = placedBuildings(inTheWayOf: [point])
        try checkFunds(economy.costs.station, clearing: cleared)
        try economy.spend(economy.costs.station)
        clear(cleared)

        let station = Station(id: StationID(rawValue: id), name: name, point: point)
        nextStationID = nextID
        stations.append(station)
        acquireAsset(.station, owner: id, cost: economy.costs.station)
        // Phase 6b: a managed company's new station draws its ridership
        // from the land, and takes its share from its neighbours.
        refreshLandDemand()
        return station
    }

    /// Makes station `id` a depot, or an ordinary station again (decision
    /// 209). Free. A depot is a station no line calls at, whose platforms
    /// are sidings no line's service runs over; lines keep their trains
    /// there (``setLineDepot(_:to:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   making it a depot, ``GameError/depotIsLineStop(_:)`` while a line
    ///   calls at it and ``GameError/depotBlocksLine(_:)`` naming the first
    ///   line, in ID order, with a service that could be driven and no
    ///   longer could be without its sidings; making it an ordinary
    ///   station, ``GameError/depotInUse(_:)`` naming the first line whose
    ///   depot it is.
    public mutating func setStationDepot(_ id: StationID, to isDepot: Bool) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard stations[index].isDepot != isDepot else { return }
        if isDepot {
            guard !lines.contains(where: { $0.stops.contains(id) }) else { throw .depotIsLineStop(id) }
            guard stations[index].commerce == nil else { throw .stationHasCommerce(id) }
            guard stations[index].expansion == nil else { throw .stationIsExpanded(id) }
            var changed = self
            changed.stations[index].isDepot = true
            for line in lines {
                for service in 0..<line.serviceCount where journey(of: line, service: service) != nil {
                    guard changed.journey(of: line, service: service) != nil else { throw .depotBlocksLine(line.id) }
                }
            }
        } else if let line = lines.first(where: { $0.depots.contains(id) }) {
            throw .depotInUse(line.id)
        }
        stations[index].isDepot = isDepot
        // Decision 298: a depot brings no transfers.
        if isDepot, stations[index].transferPoints > 0 {
            stations[index].transferPoints = 0
            passengerPlan = PassengerPlanCache()
            refreshLandDemand()
        } else if !busRoutes.isEmpty || !cableways.isEmpty || !ferryRoutes.isEmpty {
            // Decision 587, continued: no city bus route, cableway or
            // sailing route meets a depot (REVIEW-L10, L10-2).
            passengerPlan = PassengerPlanCache()
            refreshLandDemand()
        }
    }

    /// Sets the level of the shops of the station at `index` (decision
    /// 222); ``buildStationCommerce(at:)`` and the commands beside it check
    /// and charge.
    mutating func setStationCommerce(_ level: StationCommerceLevel?, at index: Int) {
        stations[index].commerce = level
    }

    /// Sets how far the station at `index` is expanded (decision 506);
    /// ``expandStation(at:)`` checks and charges.
    mutating func setStationExpansion(_ expansion: StationExpansion?, at index: Int) {
        stations[index].expansion = expansion
    }

    /// Sets the transfer points of the station at `index` (decision 298);
    /// ``setTransfers(_:)`` and ``setRealTransfers(_:)`` check.
    mutating func setTransferPoints(_ points: Int64, at index: Int) {
        stations[index].transferPoints = points
    }

    /// Gives line `id` the depot `depot` as its only one, or with `nil`
    /// none (decision 209). Free. From then on the line sends its trains to
    /// the depot empty when it no longer needs them, and out of it in time
    /// for their trips; a train on its way to another depot gets there
    /// first. Without one, trains stay where their trips end, as before. A
    /// line with runs (decision 133) may have one too (decision 221).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``;
    ///   for a depot, ``GameError/unknownStation(_:)`` or
    ///   ``GameError/notADepot(_:)``.
    public mutating func setLineDepot(_ id: LineID, to depot: StationID?) throws(GameError) {
        try setLineDepots(id, to: depot.map { [$0] } ?? [])
    }

    /// Gives line `id` the depots `depots`, none for none (decision 221).
    /// Free. Its trains run into the one they reach soonest, and out of the
    /// one nearest where they are wanted. A line whose trains stand at both
    /// its ends at night keeps them near each.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``;
    ///   for the first depot, in the order given, that is not one,
    ///   ``GameError/unknownStation(_:)``, ``GameError/notADepot(_:)`` or
    ///   ``GameError/depotListedTwice(_:)``.
    public mutating func setLineDepots(_ id: LineID, to depots: [StationID]) throws(GameError) {
        let index = try lineIndex(of: id)
        for (position, depot) in depots.enumerated() {
            guard !depots[..<position].contains(depot) else { throw .depotListedTwice(depot) }
            guard let station = station(id: depot) else { throw .unknownStation(depot) }
            guard station.isDepot else { throw .notADepot(depot) }
        }
        lines[index].depots = depots
    }

    /// Sets station `id`'s operation mode (Phase 5F, see
    /// ``StationOperationMode``; the reference's
    /// `applyStationOperationToStation`). Free.
    ///
    /// Closing a station sends everyone waiting there away, counted as
    /// abandoned at their original station (the reference's
    /// `clearStationWaitingPassengers`), and so does any journey waiting
    /// elsewhere that still has to board, change or arrive at a closed
    /// station. The reference's automatic modes after the last train
    /// (`metroComputeStationAutoOperationMode`) are not ported: only the
    /// player sets the mode. Passengers on
    /// board stay on their train; nobody gets off at a closed station. The
    /// new mode changes the passengers released from now on.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``.
    public mutating func setStationOperationMode(_ id: StationID, to mode: StationOperationMode) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard stations[index].operationMode != mode else { return }
        stations[index].operationMode = mode
        if mode == .closed {
            abandonPassengers(waitingAt: id)
        }
        // Forgets the release plan (the next release follows the new mode),
        // and sends away every waiting journey elsewhere that still needs
        // to board, change or arrive here.
        abandonUnservedPassengers()
        // Decision 77: a closed station's catchment goes back to its
        // neighbours, and comes back to it when it opens.
        refreshLandDemand()
    }

    /// Demolishes station `id` (decision 83; MapBuilder's
    /// `handleStationDelete`, the `Ci/` metro game's
    /// `confirmDeleteStationAllLines`). Free: like removing track, nothing
    /// is refunded. Its ID is never handed out again.
    ///
    /// The station goes with everything that is only its: its platforms on
    /// the track network, its passenger record (its demand, its ledger and
    /// the remainders of its trips), its demand events and its town growth.
    /// Everyone waiting there leaves first, counted as abandoned at their
    /// original station, as when it closes (`clearStationWaitingPassengers`);
    /// those who set out from it go with its ledger, wherever they wait.
    /// Every line loses it from its stops (see
    /// ``ServiceLine/removingStation(_:)``); a line left too short goes, as
    /// after ``removeLine(_:)``, and so does a pattern left with fewer than
    /// two calls, as after ``removeLinePattern(_:at:)``. A train not
    /// running a service loses it from its timetable (a repeating one left
    /// empty stops repeating) and forgets its traffic visits; a running
    /// one forgets its visits there. The station leaves its transfer group,
    /// and a group left with one station goes. Then, as after
    /// ``setLineStops(_:to:)``, everyone waiting elsewhere for a trip that
    /// went to, through or from it leaves, and a managed company's
    /// neighbouring stations take back its catchment.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/trainServiceActive(_:)`` naming the lowest numbered
    ///   train whose service calls at the station, needs one of its
    ///   platforms (see ``removeTrackPlatform(_:on:from:)``) or carries
    ///   passengers from it, to it or changing there, or runs a service of
    ///   a line with runs that calls at it (decision 133: the line loses its
    ///   runs) (stop the service first; for a line's train, take it off the
    ///   line), so no one on board is left with nowhere to go; or, under
    ///   traffic control (Stage
    ///   T), ``GameError/trackReserved(_:)`` while a train holds a span of a
    ///   platform's edge.
    public mutating func removeStation(_ id: StationID) throws(GameError) {
        guard let stationIndex = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        let platforms = network.platforms.filter { $0.station == id }
        func touches(_ group: RidingGroup) -> Bool {
            group.origin == id || group.destination == id
                || group.journey?.legs.contains { $0.from == id || $0.to == id } == true
        }
        // Decision 133: a line that loses the station loses its runs, which
        // a train on one still follows one way to its end.
        let runLines = Set(lines.filter { $0.hasRuns && $0.stops.contains(id) }.map(\.id))
        if let train = trains.first(where: { train in
            (train.execution != nil && train.timetable.contains { $0.station == id })
                || (train.execution != nil && assignedLine(of: train.id).map(runLines.contains) == true)
                || platforms.contains { serviceNeeds(train, $0) }
                || riders.contains { $0.train == train.id && $0.groups.contains(where: touches) }
        }) {
            throw .trainServiceActive(train.id)
        }
        for platform in platforms {
            try requireSpansUnheld(on: platform.edge)
        }

        // The passengers: those waiting here leave, counted at their
        // original station; the station's own go with its ledger.
        abandonPassengers(waitingAt: id)
        for index in passengers.indices where passengers[index].station != id {
            _ = passengers[index].abandonGroups(unless: { $0.journey?.origin != id })
            passengers[index].remainders.removeAll { $0.destination == id }
        }
        passengers.removeAll { $0.station == id }
        forgetFreight(of: id)
        passengerRouteBalances.removeAll { balance in
            balance.origin == id || balance.destination == id
                || balance.journeys.contains { $0.legs.contains { $0.from == id || $0.to == id } }
        }

        for index in network.platforms.indices.reversed() where network.platforms[index].station == id {
            network.removePlatform(at: index)
        }
        for index in lines.indices.reversed() where lines[index].stops.contains(id) {
            guard let (line, dropped) = lines[index].removingStation(id) else {
                removeLineAccounts(of: lines[index].id)
                // Decision 315: as removing the line does; decision 528,
                // its purchase with it.
                disposeAsset(.acquiredLine, owner: lines[index].id.rawValue)
                forgetAcquisition(ofLine: lines[index].id)
                lines.remove(at: index)
                continue
            }
            lines[index] = line
            for pattern in dropped.reversed() {
                reindexPassengerJourneys(on: line.id, removing: pattern)
            }
        }
        // Decision 209: a line whose depot it was has none (decision 221:
        // keeps its others).
        for index in lines.indices {
            lines[index].depots.removeAll { $0 == id }
        }
        for index in trains.indices {
            if trains[index].execution == nil, trains[index].timetable.contains(where: { $0.station == id }) {
                trains[index].timetable.removeAll { $0.station == id }
                if trains[index].timetable.isEmpty { trains[index].timetablePeriod = nil }
                trains[index].trafficVisits = []
            } else {
                trains[index].trafficVisits.removeAll { $0.station == id }
            }
        }
        if let group = transferGroups.firstIndex(where: { $0.stations.contains(id) }) {
            transferGroups[group].stations.removeAll { $0 == id }
            if transferGroups[group].stations.count < 2 { transferGroups.remove(at: group) }
        }
        demandEvents?.events.removeAll { $0.station == id }
        townGrowth?.places.removeAll { $0.station == id }
        // Decision 400, 10i-2: the bus routes feeding it close; decision
        // 528, a real route bought goes on sale again.
        let closing = Set(busRoutes.filter { $0.station == id }.map(\.id))
        busRoutes.removeAll { closing.contains($0.id) }
        acquisitions.removeAll { $0.busRoute.map(closing.contains) ?? false }
        // Decision 574: a cableway meeting it meets none until the land is
        // shared out again.
        for index in cableways.indices where cableways[index].transfer?.station == id {
            cableways[index].transfer = nil
            cableways[index].feederTrips = 0
            cableways[index].feederMinutes = 0
        }
        // Decision 585: and so does a ferry route.
        for index in ferryRoutes.indices where ferryRoutes[index].transfer?.station == id {
            ferryRoutes[index].transfer = nil
            ferryRoutes[index].feederTrips = 0
            ferryRoutes[index].feederMinutes = 0
        }
        stations.remove(at: stationIndex)
        removeStationFlows(of: id)
        disposeAsset(.station, owner: id.rawValue)
        // Decision 222: its shops go with it.
        disposeAsset(.stationCommerce, owner: id.rawValue)
        // Decision 506: and its expansions.
        disposeAsset(.stationExpansion, owner: id.rawValue)

        abandonUnservedPassengers()
        refreshLandDemand()
    }

    /// Buys a new train and charges ``ConstructionCosts/train``, or, with
    /// ``rollingStockEconomics`` on, the first car's price of its type
    /// (``RollingStock/price(of:cars:)``, decision 180).
    ///
    /// The new train is unplaced (its ``Train/position`` is `nil`); put it on
    /// the track with ``placeTrain(_:at:)``.
    ///
    /// In a scenario whose era has train types (decision 153) the train has
    /// the era's first type, and runs as that type does
    /// (``TrainType/performance``), or as standard.
    ///
    /// - Throws: ``GameError/invalidName``, ``GameError/idsExhausted``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func purchaseTrain(named name: String) throws(GameError) -> Train {
        try buyTrain(named: name, as: eraTrainType)
    }

    /// Buys a new train of `type` (decision 180) and charges its first car's
    /// price at once, where buying one of the standard car and changing its
    /// type would pay a refit on top: ``ConstructionCosts/train`` without
    /// ``rollingStockEconomics``, the type's price with it. The train runs
    /// as the type does (``TrainType/performance``), or as standard.
    ///
    /// - Throws: ``GameError/trainTypeUnavailable(_:)`` for a type the
    ///   scenario's era does not have (decision 86), then as
    ///   ``purchaseTrain(named:)``.
    @discardableResult
    public mutating func purchaseTrain(named name: String, as type: TrainType) throws(GameError) -> Train {
        if let allowed = scenario?.scenario.trainTypes, !allowed.contains(type) { throw .trainTypeUnavailable(type) }
        return try buyTrain(named: name, as: type)
    }

    private mutating func buyTrain(named name: String, as type: TrainType?) throws(GameError) -> Train {
        guard Self.isValidName(name) else { throw .invalidName }
        let (id, nextID) = try Self.allocateID(from: nextTrainID)
        // Decision 180: with rolling-stock economics on, the price is the
        // type's (the era's, or the standard car's).
        let price = rollingStockEconomics ? RollingStock.price(of: type, cars: 1) : economy.costs.train
        try economy.spend(price)

        var train = Train(id: TrainID(rawValue: id), name: name)
        if let type {
            train.type = type
            train.performance = type.performance ?? .standard
        }
        train.carPitch = Train.carPitch(of: type, real: realCarLengths)
        nextTrainID = nextID
        trains.append(train)
        acquireAsset(.train, owner: id, cost: price)
        return train
    }

    // MARK: - Trains

    /// The train with `id`, or `nil` if there is none.
    public func train(id: TrainID) -> Train? {
        trains.first { $0.id == id }
    }

    /// Puts an unplaced train on the track at `position`. Placement is free.
    ///
    /// `position` must be on this world's track (Stage S3):
    /// ``TrainPosition/onEdge(_:offset:)`` on an edge, `0 <= offset <=` its
    /// length; a train with a body stands at an offset above 0 (at a node,
    /// at the end of the edge it arrived along; see ``TrainPosition``). Its
    /// body is laid back from the start of its edge the way a train could
    /// have come, the lowest numbered edge first where the track branches.
    /// Other trains at the same place do not matter. The train starts idle:
    /// rate 0 and no path.
    ///
    /// Under traffic control (Stage T) the train must also be able to take
    /// the track it would stand on, the junctions it would foul, and the
    /// way it would run by itself, to the end of its edge (see
    /// ``reservedResources(of:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainAlreadyPlaced(_:)`` (placement never moves a
    ///   train), ``GameError/invalidTrainPosition``,
    ///   ``GameError/trainCannotClimb(_:)`` when the train is not a mountain
    ///   train and its head or body would stand on mountain track (decision
    ///   515 continued), or, under traffic control,
    ///   ``GameError/trackReserved(_:)``.
    public mutating func placeTrain(_ id: TrainID, at position: TrainPosition) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }
        guard isOnTrack(position) else { throw .invalidTrainPosition }
        var train = trains[index]
        let length = train.length
        switch position {
        case .onEdge(let traversal, let offset):
            guard length == 0 || offset > 0, let trail = networkTrailBehind(traversal, offset: offset, length: length) else {
                throw .invalidTrainPosition
            }
            train.position = position
            train.trailEdges = trail
            // Decision 515 continued: only a mountain train stands on
            // mountain track, head or body.
            if !train.climbsMountains, ([traversal.edge] + trail).contains(where: { network.edge($0)?.mountain ?? false }) {
                throw .trainCannotClimb(id)
            }
            // Decision 951: and only on track of its own system.
            guard runs(train, over: [traversal.edge] + trail) else { throw .trainTrackMismatch(id) }
        }

        try admit(train, at: index)
    }

    /// Sets how many cars an unplaced train has (Phase 4.5 Stage S2),
    /// ``Train/carLength`` apart: ``Train/minimumCars`` to ``Train/maximumCars``. Each car
    /// added costs ``ConstructionCosts/car`` (its type's car price with
    /// ``rollingStockEconomics`` on, decision 180); taking cars off refunds
    /// nothing. Cars that cost nothing are added whatever the balance, even
    /// a negative one. A train of more than one car is placed with its body behind
    /// its head along the track it could have come by (see
    /// ``placeTrain(_:at:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/invalidTrainLength``,
    ///   ``GameError/trainAlreadyPlaced(_:)`` (take it off the track first),
    ///   or ``GameError/insufficientFunds(required:available:)``.
    public mutating func setTrainCars(_ id: TrainID, to cars: Int) throws(GameError) {
        let index = try trainIndex(of: id)
        guard (Train.minimumCars...Train.maximumCars).contains(cars) else { throw .invalidTrainLength }
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }

        let added = Int64(cars - trains[index].cars)
        if added > 0 {
            let carPrice = rollingStockEconomics ? RollingStock.pricing(of: trains[index].type).eachCar : economy.costs.car
            let (price, overflow) = carPrice.amount.multipliedReportingOverflow(by: added)
            guard !overflow else { throw .insufficientFunds(required: Money(.max), available: economy.balance) }
            // Free cars are added even in the red: `spend` would refuse a
            // price of 0 against a negative balance.
            if price > 0 {
                try economy.spend(Money(price))
                acquireAsset(.cars, owner: id.rawValue, cars: Int(added), cost: Money(price))
            }
        } else if added < 0 {
            removeCarAssets(of: id.rawValue, count: Int(-added))
        }
        trains[index].cars = cars
        // The longest train of a line sets where its trains can pass, and
        // so the service it can run.
        abandonUnservedPassengers()
    }

    /// Renames station `id` (the reference's station rename). Free.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)`` or
    ///   ``GameError/invalidName``.
    public mutating func renameStation(_ id: StationID, to name: String) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard Self.isValidName(name) else { throw .invalidName }
        stations[index].name = name
    }

    /// Decision 866: sets the arrival chime station `id` rings, or `nil`
    /// for the one its place in the network calls for. Free; no rule
    /// reads it.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``.
    public mutating func setStationChime(_ id: StationID, to chime: StationChime?) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        stations[index].chime = chime
    }

    /// Decision 866: sets the departure melody station `id` plays as a
    /// train's doors close, or `nil` for the line's own. Free; no rule
    /// reads it. Decision 883: either takes the place of any player
    /// melody the station was set to.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``.
    public mutating func setStationDepartureMelody(_ id: StationID, to melody: DepartureMelody?) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        stations[index].departureMelody = melody
        stations[index].playerMelody = nil
    }

    /// Decision 883: sets station `id` to play player melody `melody` as a
    /// train's doors close, or `nil` for each line's own, either in place
    /// of any official melody it was set to. Free; no rule reads it.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)`` or
    ///   ``GameError/unknownPlayerMelody(_:)``.
    public mutating func setStationPlayerMelody(_ id: StationID, to melody: PlayerMelodyID?) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        if let melody, playerMelody(id: melody) == nil { throw .unknownPlayerMelody(melody) }
        stations[index].playerMelody = melody
        stations[index].departureMelody = nil
    }

    /// Decision 883: the stations set to player melody `id` play each
    /// line's own again (``removePlayerMelody(_:)``).
    mutating func stopPlaying(_ id: PlayerMelodyID) {
        for station in stations.indices where stations[station].playerMelody == id {
            stations[station].playerMelody = nil
        }
    }

    /// Renames line `id`. Free.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidName``.
    public mutating func renameLine(_ id: LineID, to name: String) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        guard Self.isValidName(name) else { throw .invalidName }
        lines[index].name = name
    }

    /// Sets line `id`'s colour, or `nil` for the app's own pick (the
    /// reference's line colour, from its `PRESET_COLORS` or any other).
    /// Free; no rule reads it.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func setLineColor(_ id: LineID, to color: LineColor?) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        lines[index].color = color
    }

    /// Sets line `id`'s code (decision 216), or `nil` for the app's own
    /// from the line's colour. Free; no rule reads it. Two lines may have
    /// the same code, as they may the same name.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func setLineCode(_ id: LineID, to code: LineCode?) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        lines[index].code = code
    }

    /// Sets the type of train `id`'s cars (the reference's `TRAIN_TYPES`),
    /// or `nil` for the standard car: what each car carries and how many
    /// doors it has (see ``TrainType``). Free, and only while the train is
    /// off the track, as its cars are (see ``setTrainCars(_:to:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainAlreadyPlaced(_:)``, or
    ///   ``GameError/trainTypeUnavailable(_:)`` for a type the scenario's era
    ///   does not have (decision 86), or `nil` in an era with types, which
    ///   has no standard car (decision 153); or, since decision 515,
    ///   ``GameError/trainCannotClimb(_:)`` for a type that is not a
    ///   mountain train while the train is on a line that runs on
    ///   mountain track.
    public mutating func setTrainType(_ id: TrainID, to type: TrainType?) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }
        // Decision 86: a scenario's era has only its own train types, and
        // since decision 153 no standard car.
        if let allowed = scenario?.scenario.trainTypes, !(type.map(allowed.contains) ?? false) {
            throw .trainTypeUnavailable(type)
        }
        if !(type?.climbsMountains ?? false), let line = assignedLine(of: id).flatMap({ self.line(id: $0) }), runsOnMountainTrack(line) {
            throw .trainCannotClimb(id)
        }
        // Decision 951: nor to a type of another track system than its
        // line's track (a guideway train a save from before version 112
        // has on ordinary track keeps a type of its own system).
        if (type?.trackSystem ?? .conventional) != trains[index].trackSystem,
           let line = assignedLine(of: id).flatMap({ self.line(id: $0) }), !runs(type, on: line) {
            throw .trainTrackMismatch(id)
        }
        // Decision 180: a change of type is the old train sold on the sale
        // rule and the new one bought: the new type's price for the cars it
        // has, less what the old would bring, at least nothing.
        if rollingStockEconomics, trains[index].type != type {
            let price = RollingStock.price(of: type, cars: trains[index].cars)
            let tradeIn = trainSaleQuote(id)
            let fee = RollingStock.refitFee(price: price, tradeIn: tradeIn)
            guard economy.canAfford(fee) else { throw .insufficientFunds(required: fee, available: economy.balance) }
            // Dearer than the new train, the old brings no more than the
            // new costs: nothing is paid back.
            let owner = id.rawValue
            let proceeds = min(tradeIn, price)
            let trainPart = RollingStock.salePrice(bookValue: bookValue(.train, owner: owner))
            let trainShare = tradeIn > .zero ? AssetRecord.share(of: trainPart, numerator: proceeds.amount, denominator: tradeIn.amount) : .zero
            sellAsset(.train, owner: owner, for: trainShare)
            sellAsset(.cars, owner: owner, for: proceeds - trainShare)
            // The fee was checked: what is paid is the new price less the
            // proceeds just received, so a change the old train pays for is
            // made even in the red (a later fix: spending the whole price
            // could throw there, with the old train already sold).
            economy.settle(Money(-price.amount))
            // As bought: the first car the train's record, the others a
            // record of cars, so that cars taken off later write off their
            // share (a later fix).
            let pricing = RollingStock.pricing(of: type)
            let cars = trains[index].cars
            acquireAsset(.train, owner: owner, cost: pricing.firstCar)
            if cars > 1 {
                acquireAsset(.cars, owner: owner, cars: cars - 1, cost: price - pricing.firstCar)
            }
        }
        trains[index].type = type
        // Decision 227: the new type's cars, at its length in a world with
        // real car lengths. The train is off the track, so no body moves.
        trains[index].carPitch = Train.carPitch(of: type, real: realCarLengths)
    }

    /// Turns real car lengths on or off for the trains bought or changed
    /// from now on (decision 227). Free, and no network command: a new game
    /// turns it on, demos, challenges and the tutorial keep it off.
    public mutating func setRealCarLengths(_ enabled: Bool) {
        realCarLengths = enabled
    }

    /// Sells train `id` back (decision 180): it brings
    /// ``RollingStock/salePercent`` of what is left of its cost on the
    /// books, its cars' too, booked as a sale with the gain or loss
    /// realized, as a building's is (decision 130). The train is gone with
    /// its timetable; its ID is not given out again. Free play keeps no
    /// accounts and is paid nothing.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainInService(_:)`` for a train on the track, on a
    ///   line, or running a service (a train going back empty to an end,
    ///   decision 172, is running one).
    public mutating func sellTrain(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        guard canSellTrain(id) else { throw .trainInService(id) }
        let owner = id.rawValue
        sellAsset(.train, owner: owner, for: RollingStock.salePrice(bookValue: bookValue(.train, owner: owner)))
        sellAsset(.cars, owner: owner, for: RollingStock.salePrice(bookValue: bookValue(.cars, owner: owner)))
        abandonRiders(of: id)
        loseCargo(of: id)
        trains.remove(at: index)
        abandonUnservedPassengers()
    }

    /// The type a train bought in the scenario's era has, and whose
    /// performance its new lines plan with (decision 153): the era's
    /// first, or `nil` without an era.
    var eraTrainType: TrainType? {
        scenario?.scenario.trainTypes?.first
    }

    /// Takes a placed train off the track. The train keeps its ID, name and
    /// timetable (and its period); its movement becomes ``TrainMovement/idle`` (rate 0, no
    /// path), so placing it again never resumes an old journey.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (stop the service first).
    public mutating func unplaceTrain(_ id: TrainID) throws(GameError) {
        let (index, _) = try manuallyControlledTrain(id)

        trains[index].position = nil
        trains[index].trafficVisits = []
        trains[index].movement = .idle
        trains[index].trailEdges = []
        trains[index].reservation = []
    }

    /// Turns a placed train around where it stands, without moving it: its
    /// head goes to where its tail was, travelling its edge the other way,
    /// and its body lies back over the same track (see
    /// ``TrainPosition``). Reversing twice restores the original position
    /// exactly.
    ///
    /// The path is cleared, including where it stops, because it was a path
    /// for the other direction; the rate is kept. A reversed train therefore
    /// runs to the end of its edge and stops there until it is given a new
    /// path.
    ///
    /// Under traffic control (Stage T) the train's reservation goes with its
    /// path. A reversed train stands on the same track as before, but then
    /// runs to the end of its edge by itself, and must be able to take that
    /// way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (stop the service first), or, under traffic control,
    ///   ``GameError/trackReserved(_:)``.
    public mutating func reverseTrain(_ id: TrainID) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        var train = trains[index]

        switch position {
        case .onEdge(let traversal, let offset):
            (train.position, train.trailEdges) = reversedOnNetwork(traversal, offset: offset, trail: train.trailEdges, length: train.length)
        }
        train.movement.edges = []
        train.movement.cursor = 0
        train.movement.end = nil
        try admit(train, at: index)
    }

    // MARK: - Train movement

    /// Sets how many logical units a placed train may travel in each basic
    /// step (one game minute). 0 holds the train where it is and keeps its
    /// path, so setting a rate again resumes the same journey. Any
    /// non-negative `Int64` is accepted: travel adds distance to an offset
    /// only after checking that it is shorter than the rest of the edge, so
    /// no rate can overflow.
    ///
    /// Allowed while the train runs its timetable: a service never sets the
    /// rate. Between calls a service's train follows its running curve
    /// (Stage W2c, see ``ServiceRun``) whatever its rate, unless the rate is
    /// 0, which holds it (a service still gives it a path when a departure
    /// comes); the rate is how fast it goes only when its
    /// performance builds no curve for the way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/invalidMovementRate`` for a negative rate.
    public mutating func setTrainMovementRate(_ id: TrainID, to rate: Int64) throws(GameError) {
        let (index, _) = try placedTrain(id)
        guard rate >= 0 else { throw .invalidMovementRate }

        trains[index].movement.rate = rate
    }

    /// Enables movement using the train's configured km/h performance.
    /// Services still follow their acceleration/braking curve; manual
    /// movement uses the same top speed, converted to integer world units
    /// per minute. The old rate command remains for save/replay compatibility
    /// and explicit holds, rather than a second player speed setting.
    public mutating func useTrainPerformanceForMovement(_ id: TrainID) throws(GameError) {
        let (index, _) = try placedTrain(id)
        let speed = trains[index].performance.topSpeed
        let minutesPerHour = GameTime.secondsPerHour / GameTime.secondsPerMinute
        // Valid performances cap speed at 2^20, so this product fits Int64.
        trains[index].movement.rate = speed * WorldCoordinate.unitsPerMetre * 1000 / minutesPerHour
    }

    /// Sets how train `id` accelerates, brakes and coasts, and how fast it may
    /// run (Stage W2c; see ``Train/performance``): the running curves its
    /// services follow between calls. Placed or not, at no cost.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while it runs a service (its
    ///   run follows the curve of the performance it set off with), or
    ///   ``GameError/invalidTrainPerformance`` (see
    ///   ``TrainPerformance/isValid``).
    public mutating func setTrainPerformance(_ id: TrainID, to performance: TrainPerformance) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        guard performance.isValid else { throw .invalidTrainPerformance }
        trains[index].performance = performance
    }

    /// Sets train `id` back to its type's own performance (decision 961,
    /// ``Train/factoryPerformance``): the way out for a train a save gave
    /// a performance of its own before the type and its performance became
    /// one choice. Placed or not, at no cost; a train already running as
    /// its type, or of a type without a performance of its own, is left as
    /// it is.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainServiceActive(_:)`` while it runs a service (its
    ///   run follows the curve of the performance it set off with).
    public mutating func restoreTrainFactoryPerformance(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        guard let factory = trains[index].factoryPerformance, trains[index].performance != factory else { return }
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        trains[index].performance = factory
    }

    /// Replaces a placed train's path with `traversals` (Stage S3): the form
    /// ``route(from:to:)`` returns. Each traversal must be one a train may
    /// take after the one before it (see ``transitions(after:)``), the first
    /// after the edge the train is on. The whole list is checked against the
    /// current track, then replaces the old path (``TrainMovement/edges``),
    /// and the cursor goes back to 0; an empty list clears it. The train
    /// never picks a way itself, and clearing its path does not move it: it
    /// still runs to the end of its edge at its rate (set the rate to 0 to
    /// hold it where it is).
    ///
    /// The path may stop part of the way along its last edge (Stage S5):
    /// `end` is how far along it the head stops, measured the way the train
    /// travels it (see ``TrainMovement/end``); `nil`, the default, runs to
    /// the end of that edge. The last edge is the last
    /// traversal, or the train's own edge when there are none. `end` must be
    /// below that edge's length, above 0 after a traversal, and not behind
    /// the train on its own edge; with no traversals and `end` where the
    /// head is, the train stands where it is. A path from
    /// ``path(from:toStation:length:)`` goes in unchanged, as
    /// `along: path.traversals, stoppingAt: path.end`.
    ///
    /// Under traffic control (Stage T) the train takes its whole new route
    /// at once, with everything its whole length covers on the way (see
    /// ``reservedResources(of:)``), in place of its old reservation; if
    /// another train holds any of it, nothing changes.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (the service owns the path; stop it first),
    ///   ``GameError/invalidContinuation`` (a step a train may not take, or
    ///   an `end` that does not fit), ``GameError/trainCannotClimb(_:)``
    ///   when the train is not a mountain train and the path runs onto
    ///   mountain track (decision 515 continued), or, under traffic
    ///   control, ``GameError/trackReserved(_:)``.
    public mutating func setTrainContinuation(_ id: TrainID, along traversals: [TrackTraversal], stoppingAt end: Int64? = nil) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        let (traversal, offset): (TrackTraversal, Int64) = switch position {
        case .onEdge(let traversal, let offset): (traversal, offset)
        }
        var arrival = traversal
        for next in traversals {
            guard transitions(after: arrival).contains(next) else { throw .invalidContinuation }
            arrival = next
        }
        if let end {
            guard end < network.edge(arrival.edge)!.length, end >= (traversals.isEmpty ? offset : 1) else { throw .invalidContinuation }
        }
        // Decision 515 continued: a train that cannot climb is never sent
        // onto mountain track.
        if !trains[index].climbsMountains, traversals.contains(where: { network.edge($0.edge)?.mountain ?? false }) {
            throw .trainCannotClimb(id)
        }
        // Decision 951: nor onto track of another system.
        guard runs(trains[index], over: traversals.map(\.edge)) else { throw .trainTrackMismatch(id) }

        var train = trains[index]
        train.movement.edges = traversals.map(\.edge)
        train.movement.cursor = 0
        train.movement.end = end
        try admit(train, at: index)
    }

    /// Makes edge `id`, which exists, open to trains, closing or closed
    /// (decision 716; ``closeTrack(_:)-(TrackEdgeID)`` and ``openTrack(_:)``
    /// check the rest), and starts again what is kept between steps from
    /// the routes the network gives.
    mutating func setTrackClosure(_ id: TrackEdgeID, _ closure: RailwayNetwork.Closure) {
        network.setClosure(id, closure)
        passengerPlan = PassengerPlanCache()
        passengerRouteMemo = PassengerRouteMemo()
        routeMemo = RouteMemo()
    }

    /// Puts `candidate`, train `index` with a new place or path, into the
    /// world: under traffic control (Stage T) with the reservation of its
    /// route, in place of its old one, only if no other train holds track
    /// it needs (see ``reserving(_:)``); otherwise nothing changes.
    ///
    /// - Throws: ``GameError/trackClosed(_:)`` naming the lowest numbered
    ///   edge closed to trains (decision 716) that it would stand on or
    ///   its path runs along, or being closed unless the train already
    ///   stands on such track, with or without traffic control; then
    ///   ``GameError/trackReserved(_:)`` naming the lowest numbered
    ///   train holding such track.
    private mutating func admit(_ candidate: Train, at index: Int) throws(GameError) {
        if let closed = closedTrack(under: candidate, now: trains[index]) { throw .trackClosed(closed) }
        switch reserving(candidate) {
        case .granted(let train): trains[index] = train
        case .held(let holder): throw .trackReserved(holder)
        }
    }

    // MARK: - Traffic control

    /// Turns traffic control on or off (Phase 4.6 Stage T, ARCHITECTURE
    /// decision 32; see ``isTrafficControlEnabled``).
    ///
    /// Turning it on works out, for every placed train in ID order, the
    /// track it needs now: what it stands on and the junctions it fouls
    /// (see ``heldResources(of:)``), and for a train with a way left to go
    /// the whole of it (see ``reservedResources(of:)``). If two trains need
    /// the same track nothing changes; otherwise every train takes its
    /// reservation and traffic control is on, all at once. Turning it on
    /// again changes nothing.
    ///
    /// Turning it off always succeeds: every reservation is dropped, and
    /// trains keep their positions, paths, timetables, services and lines,
    /// passing through each other again as before.
    ///
    /// - Throws: ``GameError/trainsShareTrack(_:_:)`` when turning it on:
    ///   the first train, in ID order, that needs track an earlier train
    ///   needs, and the earliest such train.
    public mutating func setTrafficControl(_ enabled: Bool) throws(GameError) {
        guard enabled else {
            isTrafficControlEnabled = false
            for index in trains.indices {
                trains[index].reservation = []
            }
            abandonUnservedPassengers()
            return
        }
        guard !isTrafficControlEnabled else { return }
        var needs: [(index: Int, resources: Set<TrackResource>, moves: Bool)] = []
        for index in trains.indices where trains[index].position != nil {
            let envelope = routeEnvelope(of: trains[index])
            if let earlier = needs.first(where: { network.fouls($0.resources, envelope.resources) }) {
                throw .trainsShareTrack(trains[earlier.index].id, trains[index].id)
            }
            needs.append((index, envelope.resources, envelope.moves))
        }
        isTrafficControlEnabled = true
        for need in needs where need.moves {
            trains[need.index].reservation = need.resources.sorted()
        }
        abandonUnservedPassengers()
    }

    // MARK: - Timetables

    /// Replaces a train's timetable with `stops`, in order (see
    /// ``ScheduledStop``), running once or, with a `period`, repeating every
    /// `period` seconds (see ``Train/timetablePeriod``; minutes before Stage
    /// W2a). An empty list without a period clears it. Free, and the train
    /// may be placed or not.
    ///
    /// The whole list is checked before anything changes: its times never go
    /// back in time, starting from second 0 (`0 <= arrival <= departure` at
    /// every stop, and each departure no later than the next stop's
    /// arrival), and every stop names a station of this world. A repeating
    /// timetable also needs a stop and a period of at least one second, and
    /// its times must not go back when it starts again: the last departure
    /// no later than the first arrival one period later. Equal times,
    /// repeated stations, stations without platforms, turning round at any
    /// stop and times the clock has already passed are all allowed; whether
    /// the train could keep to the timetable (a route between the stations,
    /// the travel time, where the train is now, the last stop leading back
    /// to the first) is not checked.
    ///
    /// Only the timetable and its period change. Setting one never places,
    /// moves, routes or stops the train, and never starts a service: only a
    /// service started with ``startTrainService(_:)`` reads the timetable.
    /// While a service runs, its timetable cannot be replaced: an index into
    /// the old timetable has no meaning in a new one. Stop the service, set
    /// the timetable, and start the service again. A train assigned to a
    /// line gets its timetables from the line.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``,
    ///   ``GameError/trainServiceActive(_:)``,
    ///   ``GameError/invalidTimetable`` (for the times or the period), or
    ///   ``GameError/unknownStation(_:)`` naming the first stop, in
    ///   timetable order, whose station does not exist.
    public mutating func setTrainTimetable(
        _ id: TrainID,
        to stops: [ScheduledStop],
        repeatingEvery period: Int64? = nil
    ) throws(GameError) {
        let index = try trainIndex(of: id)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        guard ScheduledStop.isTimetable(stops, period: period) else { throw .invalidTimetable }
        if let stop = stops.first(where: { station(id: $0.station) == nil }) {
            throw .unknownStation(stop.station)
        }

        trains[index].trafficVisits = []
        trains[index].timetable = stops
        trains[index].timetablePeriod = period
    }

    // MARK: - Timetable services

    /// Starts running the train's timetable as a service, stop by stop in
    /// timetable order, from the first stop to the last: once, or cycle
    /// after cycle for a repeating timetable (see ``Train/timetablePeriod``).
    ///
    /// The train must be stopped at the first stop's station (see
    /// ``stationsStoppedAt(by:)``; a platform shared with other stations is
    /// fine). It then waits there as if it had just arrived
    /// (``TimetableExecution/waitingAtStop(_:cycle:)`` with index 0). A
    /// service always starts from the first stop, however late it is. A
    /// timetable that runs once starts in its only cycle, so if its times
    /// have all passed it leaves every stop as soon as it can. A repeating
    /// timetable starts in the first cycle whose first departure is not
    /// before now, so the train leaves on time; a cycle that has begun
    /// already is not joined halfway. Starting changes nothing else; nothing
    /// moves until time passes (see ``advance(ticks:)`` for how a service
    /// runs, turns trains round and starts a timetable again). A train
    /// assigned to a line is sent out by the line.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` if a service is already
    ///   running, ``GameError/noTimetable(_:)`` for an empty timetable,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainNotAtFirstStop(_:)``.
    public mutating func startTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        let train = trains[index]
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard train.execution == nil else { throw .trainServiceActive(id) }
        guard let first = train.timetable.first else { throw .noTimetable(id) }
        guard train.position != nil else { throw .trainNotPlaced(id) }
        guard isStopped(train, at: first.station) else { throw .trainNotAtFirstStop(id) }

        trains[index].trafficVisits = []
        trains[index].isStandingAside = false
        trains[index].execution = .waitingAtStop(0, cycle: train.startingCycle(at: clock.now))
        // Stage W2b: starting counts as arriving at the first stop now, so
        // the train dwells there before it leaves.
        trains[index].times = ServiceTimes(arrival: clock.now)
        logArrival(of: index)
    }

    /// Stops the train's service, wherever it has got to. Only the
    /// automation ends: the train keeps its timetable, position, rate and
    /// path, so a train on its way to a stop carries on to it and
    /// stops there, now under manual control. Stopping a service is not a
    /// brake; set the rate to 0 to hold the train. A line's train is taken
    /// off the line first (``unassignTrain(_:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``, or
    ///   ``GameError/trainServiceNotActive(_:)``.
    public mutating func stopTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution != nil else { throw .trainServiceNotActive(id) }

        trains[index].execution = nil
        trains[index].isDeadheading = false
        trains[index].times = nil
        trains[index].trafficVisits = []
        abandonRiders(of: id)
        interruptTrip(of: id)
    }

    // MARK: - Service lines

    /// The line with `id`, or `nil` if there is none.
    public func line(id: LineID) -> ServiceLine? {
        lines.first { $0.id == id }
    }

    /// Creates a service line calling at `stops`, in order, with the
    /// standard window (06:00 to midnight), the default rate (one link a
    /// minute) and no trains in service. Free.
    ///
    /// A line is plan data: it never moves, routes or schedules a train.
    /// Whether its stations are joined by track is not checked; what its
    /// journey would take is derived by ``lineJourney(_:pattern:)``.
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/invalidLineStops`` (fewer than two, or a station twice
    ///   in a row), ``GameError/unknownStation(_:)`` naming the first stop
    ///   whose station does not exist, or ``GameError/idsExhausted``.
    ///
    /// In a scenario whose era's first train type runs its own way (decision
    /// 153), the line plans its journeys with that type's performance.
    @discardableResult
    public mutating func createLine(named name: String, stops: [StationID]) throws(GameError) -> ServiceLine {
        guard Self.isValidName(name) else { throw .invalidName }
        try requireLineStops(stops)
        let (id, nextID) = try Self.allocateID(from: nextLineID)

        var line = ServiceLine(id: LineID(rawValue: id), name: name, stops: stops)
        if let performance = eraTrainType?.performance {
            line.performance = performance
        }
        nextLineID = nextID
        lines.append(line)
        passengerPlan = PassengerPlanCache()
        return line
    }

    /// Removes a line. Its ID is never handed out again. Its trains are no
    /// longer assigned to a line; a train on a round trip keeps its
    /// timetable and finishes the trip as an ordinary service.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func removeLine(_ id: LineID) throws(GameError) {
        let index = try lineIndex(of: id)
        let wasHighSpeed = lines[index].isHighSpeed
        lines.remove(at: index)
        removeLineAccounts(of: id)
        // Decision 315: what a line bought cost for its riders goes with it;
        // decision 528, and its purchase, so the real line is on sale again.
        disposeAsset(.acquiredLine, owner: id.rawValue)
        forgetAcquisition(ofLine: id)
        abandonUnservedPassengers()
        // Decision 168: its stations draw no intercity trips unless
        // another high-speed line calls at them.
        if wasHighSpeed { refreshLandDemand() }
    }

    /// Replaces a line's stops with `stops`, in order. Each stop the line
    /// keeps takes its patterns' calls and its route preferences with it
    /// (decision 291, ``ServiceLine/stopIndices(from:to:)``): a pattern
    /// calls at the same stations, and a preferred path is kept for a leg
    /// its service still takes between the same two stations; the others
    /// go, back to the automatic route.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/invalidLineStops`` (on a ring also fewer than three, or
    ///   the same station first and last, see ``setLineRing(_:to:)``),
    ///   ``GameError/unknownStation(_:)`` naming the first stop whose
    ///   station does not exist, ``GameError/invalidLinePattern`` if the
    ///   new stops leave out a stop a pattern calls at (remove the pattern
    ///   first), or, on a line with runs (decision 133),
    ///   ``GameError/trainServiceActive(_:)`` while one of its trains runs a
    ///   service.
    public mutating func setLineStops(_ id: LineID, to stops: [StationID]) throws(GameError) {
        let index = try lineIndex(of: id)
        try requireLineStops(stops, ring: lines[index].isRing)
        let moved = ServiceLine.stopIndices(from: lines[index].stops, to: stops)
        var changed = lines[index]
        changed.stops = stops
        for pattern in changed.patterns.indices {
            let calls = changed.patterns[pattern].calls.compactMap { moved[$0] }.sorted()
            guard calls.count == changed.patterns[pattern].calls.count, LinePattern.isCallList(calls, stopCount: stops.count) else {
                throw .invalidLinePattern
            }
            changed.patterns[pattern].calls = calls
        }
        changed.routePreferences = changed.movedRoutes(changed.routePreferences, service: 0, by: moved)
        for pattern in changed.patterns.indices {
            changed.patterns[pattern].routePreferences = changed.movedRoutes(changed.patterns[pattern].routePreferences, service: pattern + 1, by: moved)
        }
        // Decision 133: new stops end the runs, which a train on one still
        // follows one way to its end; not under it, as setLineRuns.
        if lines[index].hasRuns, let running = lines[index].trains.first(where: { train(id: $0)?.execution != nil }) {
            throw .trainServiceActive(running)
        }
        lines[index].stops = stops
        lines[index].patterns = changed.patterns
        lines[index].routePreferences = changed.routePreferences
        // Decision 133: runs name stops by index, so new stops end them.
        lines[index].runs = []
        lines[index].runDays = []
        abandonUnservedPassengers()
        // Decision 168: the stations of a high-speed line draw intercity
        // trips.
        if lines[index].isHighSpeed { refreshLandDemand() }
    }

    /// Reverses the order of a line's stops (decision 80, MapBuilder's
    /// `handleReverseStationOrder`). Free. Its services call at the same
    /// stations as before: each pattern's calls and every route preference
    /// are mapped to the reversed indices, so a preferred path between two
    /// stations stays theirs. A ring then goes round the other way, so its
    /// two dispatch times swap with its directions. Passengers waiting for a
    /// trip the line no longer takes leave, as after
    /// ``setLineStops(_:to:)``.
    ///
    /// Without ``flexDispatch`` only a line with no trains can be reversed
    /// (decision 134): a train sent out would finish its trip at what is
    /// then the last stop, where the line never sends a train out, so
    /// ``GameError/trainOnLine(_:)`` names the lowest numbered train. With
    /// it, a line with trains can be reversed (decision 172, which ends
    /// decision 134's refusal): a train sent out finishes its trip, and one that then
    /// stands at what is now the line's last stop is sent out from there,
    /// first back along the line. Only a ring with a train running a
    /// service is refused, as its trains' ways round are by their order
    /// and would be swapped under their riders. Its passengers keep their
    /// trips on it, the other way along its stops.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/trainServiceActive(_:)`` naming the lowest numbered
    ///   train of a ring that runs a service.
    public mutating func reverseLineStops(_ id: LineID) throws(GameError) {
        let index = try lineIndex(of: id)
        if !flexDispatch {
            if let assigned = lines[index].assignedTrains.first { throw .trainOnLine(assigned) }
        } else if lines[index].isRing, let running = lines[index].trains.first(where: { train(id: $0)?.execution != nil }) {
            throw .trainServiceActive(running)
        }
        var line = lines[index]
        let last = line.stops.count - 1
        func reversed(_ routes: [LineRoutePreference]) -> [LineRoutePreference] {
            routes.map { $0.between(last - $0.from, last - $0.to) }
        }
        line.stops.reverse()
        line.routePreferences = reversed(line.routePreferences)
        for pattern in line.patterns.indices {
            line.patterns[pattern].calls = line.patterns[pattern].calls.reversed().map { last - $0 }
            line.patterns[pattern].routePreferences = reversed(line.patterns[pattern].routePreferences)
        }
        if line.isRing {
            swap(&line.lastDispatch, &line.outerLastDispatch)
        } else if line.dispatchPattern == .fromBothEnds {
            // Decision 309: the ends change places, and their clocks.
            swap(&line.lastDispatch, &line.endLastDispatch)
        }
        // Decision 133: each run calls at the same stations, the other way
        // along the reversed stops.
        // Decision 535: on a ring, the other way round too.
        line.runs = line.runs.map {
            LineRun(from: last - $0.from, to: last - $0.to, times: $0.times, days: $0.days, way: $0.way.map { $0 == .inner ? .outer : .inner },
                    passes: $0.passes.map { last - $0 })
        }
        lines[index] = line
        // Its passengers still take it between the same stations, now the
        // other way along its stops (decision 80: only those whose trip it
        // no longer goes leave).
        for record in passengers.indices {
            passengers[record].reverseDirections(on: id)
        }
        for train in riders.indices {
            riders[train].groups = riders[train].groups.map { group in
                RidingGroup(origin: group.origin, destination: group.destination, count: group.count,
                    journey: group.journey?.reversingDirections(on: id))
            }
        }
        passengerRouteBalances = passengerRouteBalances.map { balance in
            PassengerRouteBalance(origin: balance.origin, destination: balance.destination,
                journeys: balance.journeys.map { $0.reversingDirections(on: id) }, weights: balance.weights, balances: balance.balances)
        }
        abandonUnservedPassengers()
    }

    /// Gives line `id` the runs of a real timetable (decision 133), or with
    /// `[]` takes them away: from then on the line sends its trains out at
    /// the runs' times, each from where the run starts, and not at a
    /// headway; given runs, it spaces its trains evenly (decision 309). None
    /// of its runs has sent a train out yet. Free.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``;
    ///   ``GameError/invalidLineRuns`` for runs that are not the line's
    ///   (see ``LineRun``: on a ring, decision 535, each going one way
    ///   round), or any on a line with patterns or one calling at a station
    ///   twice; or
    ///   ``GameError/trainServiceActive(_:)`` for the first of its trains,
    ///   in ID order, running a service: the way its riders go is the
    ///   line's, which this would change under them.
    public mutating func setLineRuns(_ id: LineID, to runs: [LineRun]) throws(GameError) {
        let index = try lineIndex(of: id)
        guard lines[index].canHave(runs) else { throw .invalidLineRuns }
        if let running = lines[index].trains.first(where: { train(id: $0)?.execution != nil }) {
            throw .trainServiceActive(running)
        }
        lines[index].runs = runs
        lines[index].runDays = Array(repeating: nil, count: runs.count)
        if !runs.isEmpty {
            // Decision 309: the runs' times send the trains out, so the
            // line spaces them evenly, as a ring does.
            lines[index].dispatchPattern = .even
            lines[index].endLastDispatch = nil
            lines[index].opensPair = false
        }
        abandonUnservedPassengers()
    }

    /// Marks every run of line `index` as having sent its train out on
    /// `day` (`nil`: never), so it runs from the day after (decision 315).
    mutating func setRunsDone(ofLine index: Int, through day: Int64?) {
        lines[index].runDays = Array(repeating: day, count: lines[index].runs.count)
    }

    /// The line IDs handed out are those below this (decision 315).
    var lineIDsHandedOut: Int { nextLineID }

    /// Copies line `id` as a new line named `name` (decision 80,
    /// MapBuilder's `handleLineDuplicate`, which names the copy
    /// "<name> - Fork"). Free. The copy has the line's stops, route
    /// preferences, performance, window, train counts, target headways,
    /// patterns, ring, colour and freight (decision 155), but no trains:
    /// those belong to the line they are assigned to, so the copy sends
    /// nothing out until trains are assigned to it. Its ID is the next line
    /// ID.
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/unknownLine(_:)`` or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func duplicateLine(_ id: LineID, named name: String) throws(GameError) -> ServiceLine {
        guard Self.isValidName(name) else { throw .invalidName }
        let original = lines[try lineIndex(of: id)]
        let (newID, nextID) = try Self.allocateID(from: nextLineID)
        var copy = ServiceLine(id: LineID(rawValue: newID), name: name, stops: original.stops)
        copy.routePreferences = original.routePreferences
        copy.performance = original.performance
        copy.window = original.window
        copy.trainsInService = original.trainsInService
        copy.targetHeadways = original.targetHeadways
        copy.depots = original.depots
        copy.dispatchPattern = original.dispatchPattern
        copy.patterns = original.patterns.map { pattern in
            var copied = pattern
            copied.trains = []
            copied.lastDispatch = nil
            return copied
        }
        copy.isRing = original.isRing
        copy.color = original.color
        // Decision 155: a freight line's copy carries freight too.
        copy.isFreight = original.isFreight
        // Decision 564: and keeps to the same side.
        copy.keepsRight = original.keepsRight
        copy.runs = original.runs
        copy.runDays = Array(repeating: nil, count: original.runs.count)
        nextLineID = nextID
        lines.append(copy)
        passengerPlan = PassengerPlanCache()
        return copy
    }

    /// Makes a line a ring, or no longer one (decision 49, the `Ci/` metro
    /// game's `completeRingLine` and opening a ring with `metroSplitOpenRing`).
    /// Free.
    ///
    /// A ring's trains run on from its last stop back to the first, round
    /// and round, never turning round: the first of its trains in ID order,
    /// the third and so on the ``RingDirection/inner`` way, the others the
    /// ``RingDirection/outer`` way (see ``ServiceLine/ringDirection(of:)``).
    /// Making a line a ring makes its counts of trains in service even,
    /// down (the reference's `normalizeRingPairedTrainCaps`) and its trains
    /// spaced evenly (decision 309: a ring has no other pattern); making it a
    /// line again forgets when it last sent a train out the outer way.
    /// Trains already sent out keep their timetables either way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/invalidLineStops`` to make a ring of fewer than three
    ///   stops or of one calling at the same station first and last, or
    ///   ``GameError/invalidLinePattern`` to make a ring of a line with
    ///   patterns (the reference keeps a ring's route legs to one over the
    ///   whole ring, `consolidateRingRouteLegs`; its ring express is not
    ///   ported), or ``GameError/invalidLineRuns`` to make a ring of a line
    ///   with runs, or a line again of a ring with runs (decision 535: a
    ///   ring's runs go one way round, a line's from end to end).
    public mutating func setLineRing(_ id: LineID, to isRing: Bool) throws(GameError) {
        let index = try lineIndex(of: id)
        if isRing {
            guard ServiceLine.isRingStopList(lines[index].stops) else { throw .invalidLineStops }
            guard lines[index].patterns.isEmpty else { throw .invalidLinePattern }
            guard lines[index].isRing || !lines[index].hasRuns else { throw .invalidLineRuns }
            let counts = lines[index].trainsInService
            lines[index].trainsInService = TrainsInService(
                peak: ServiceLine.paired(counts.peak), offPeak: ServiceLine.paired(counts.offPeak), low: ServiceLine.paired(counts.low)
            )
            // Decision 309: a ring spaces its trains evenly.
            lines[index].dispatchPattern = .even
            lines[index].endLastDispatch = nil
            lines[index].opensPair = false
        } else {
            // Decision 535: a ring's runs go one way round, which a line
            // with ends has no way to follow.
            guard !lines[index].isRing || !lines[index].hasRuns else { throw .invalidLineRuns }
            lines[index].outerLastDispatch = nil
        }
        if lines[index].isRing != isRing { lines[index].routePreferences = [] }
        lines[index].isRing = isRing
        abandonUnservedPassengers()
    }

    /// Replaces one service's preferences atomically. Missing physical
    /// track/platform is permitted: rebuilding the map falls back to the
    /// automatic route until that preference becomes usable again.
    public mutating func setLineRoutePreferences(_ id: LineID, to routes: [LineRoutePreference], pattern: Int? = nil) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        if let pattern, !lines[index].patterns.indices.contains(pattern) { throw .unknownLinePattern(pattern) }
        var changed = lines[index]
        if let pattern { changed.patterns[pattern].routePreferences = routes }
        else { changed.routePreferences = routes }
        guard changed.validRoutePreferences else { throw .invalidLineRoutePreference }
        lines[index] = changed
        abandonUnservedPassengers()
    }

    /// Sets the performance a line's journey times are worked out with
    /// (Stage W2c; see ``ServiceLine/performance`` and
    /// ``lineJourney(_:pattern:)``). Trains already sent out keep their
    /// timetables.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidTrainPerformance`` (see
    ///   ``TrainPerformance/isValid``).
    public mutating func setLinePerformance(_ id: LineID, to performance: TrainPerformance) throws(GameError) {
        let index = try lineIndex(of: id)
        guard performance.isValid else { throw .invalidTrainPerformance }
        let wasHighSpeed = lines[index].isHighSpeed
        lines[index].performance = performance
        abandonUnservedPassengers()
        // Decision 168: planned at high speed, a line is a high-speed line:
        // its stations have the hinterlands of the people round them, and
        // those who ride it pay the high-speed fare. Read again at once, for
        // a company whose land sets its ridership.
        if lines[index].isHighSpeed != wasHighSpeed {
            passengerPlan = PassengerPlanCache()
            refreshLandDemand()
        }
    }

    /// Sets line `id`'s dwell at a stop between its ends (decision 207), or
    /// with `nil` gives it back the world's default
    /// (``dwellSeconds(of:)``). A train already on its way keeps its
    /// timetable.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidLineDwell``.
    public mutating func setLineDwell(_ id: LineID, seconds: Int64?) throws(GameError) {
        let index = try lineIndex(of: id)
        if let seconds, !ServiceLine.dwellRange.contains(seconds) { throw .invalidLineDwell }
        lines[index].dwellSeconds = seconds
        abandonUnservedPassengers()
    }

    /// Sets how line `id`'s own service spaces its trains out (decision
    /// 309). Free; a train on its way keeps its trip, and the next train
    /// out follows the new pattern. The ends' dispatch times and an open
    /// pair are forgotten on a change.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidDispatchPattern`` for a stagger outside
    ///   ``DispatchPattern/staggerRange``, a pattern other than even on a
    ///   ring or a line with runs, or from both ends in a world without
    ///   flexible dispatch.
    public mutating func setLineDispatchPattern(_ id: LineID, to pattern: DispatchPattern) throws(GameError) {
        let index = try lineIndex(of: id)
        let line = lines[index]
        guard pattern.isValid, pattern == .even || !line.isRing && !line.hasRuns,
              pattern != .fromBothEnds || flexDispatch
        else { throw .invalidDispatchPattern }
        guard pattern != line.dispatchPattern else { return }
        lines[index].dispatchPattern = pattern
        lines[index].endLastDispatch = nil
        lines[index].opensPair = false
    }

    /// Sets when a line runs during the day (see ``ServiceWindow``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidServiceWindow``.
    public mutating func setLineServiceWindow(_ id: LineID, to window: ServiceWindow) throws(GameError) {
        let index = try lineIndex(of: id)
        guard window.isValid else { throw .invalidServiceWindow }
        lines[index].window = window
        abandonUnservedPassengers()
    }

    /// Sets how many trains a line's own service, or its pattern at index
    /// `pattern`, is to run at each service level. Any count from 0 to
    /// ``TrainsInService/maximum`` is kept as it is; how many it can run is
    /// derived (see ``lineTrainsInService(_:at:pattern:)``).
    ///
    /// On a ring (decision 49) each count is made even, down: a ring runs
    /// its trains in pairs, one each way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/unknownLinePattern(_:)``, or
    ///   ``GameError/invalidTrainsInService`` for a count below 0 or above
    ///   ``TrainsInService/maximum``.
    public mutating func setLineTrainsInService(_ id: LineID, to trains: TrainsInService, pattern: Int? = nil) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        guard trains.isValid else { throw .invalidTrainsInService }
        if lines[index].isRing {
            lines[index].trainsInService = TrainsInService(
                peak: ServiceLine.paired(trains.peak), offPeak: ServiceLine.paired(trains.offPeak), low: ServiceLine.paired(trains.low)
            )
        } else if service == 0 {
            lines[index].trainsInService = trains
        } else {
            lines[index].patterns[service - 1].trainsInService = trains
        }
        abandonUnservedPassengers()
    }

    /// Sets which service level each minute of the day has, for every line.
    ///
    /// - Throws: ``GameError/invalidServiceDay`` unless the bands start at
    ///   minute 0 and strictly increase within the day.
    public mutating func setServiceDay(_ day: ServiceDay) throws(GameError) {
        guard day.isValid else { throw .invalidServiceDay }
        serviceDay = day
        abandonUnservedPassengers()
    }

    /// Sets the minutes a line's own service, or its pattern at index
    /// `pattern`, aims to keep between its trains, at the levels with a
    /// target; the other levels run the count set by
    /// ``setLineTrainsInService(_:to:pattern:)`` (see ``TargetHeadways``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/unknownLinePattern(_:)``, or
    ///   ``GameError/invalidHeadway`` for a target outside `2...1440`.
    public mutating func setLineTargetHeadways(_ id: LineID, to headways: TargetHeadways, pattern: Int? = nil) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        guard headways.isValid else { throw .invalidHeadway }
        if service == 0 {
            lines[index].targetHeadways = headways
        } else {
            lines[index].patterns[service - 1].targetHeadways = headways
        }
        abandonUnservedPassengers()
    }

    /// Adds a pattern to a line, calling at `calls` (indices into the
    /// line's stops), after its other patterns, with no trains in service,
    /// no target headways and no trains; returns its index. Free.
    ///
    /// Calls that are a run of neighbouring stops make a short working;
    /// calls that leave stops out make an express, which passes them.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidLinePattern`` on a ring (decision 49), or
    ///   unless there are two calls or more, strictly increasing, each an
    ///   index of one of the line's stops.
    @discardableResult
    public mutating func addLinePattern(_ id: LineID, calling calls: [Int]) throws(GameError) -> Int {
        let index = try lineIndex(of: id)
        guard !lines[index].isRing, !lines[index].hasRuns, LinePattern.isCallList(calls, stopCount: lines[index].stops.count) else {
            throw .invalidLinePattern
        }
        lines[index].patterns.append(LinePattern(calls: calls))
        return lines[index].patterns.count - 1
    }

    /// Removes a line's pattern at index `pattern`; the patterns after it
    /// move down one index. Its trains are no longer assigned to a line: a
    /// train on a round trip keeps its timetable and finishes the trip as
    /// an ordinary service, as when a line is removed.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/unknownLinePattern(_:)``.
    public mutating func removeLinePattern(_ id: LineID, at pattern: Int) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        lines[index].patterns.remove(at: service - 1)
        reindexPassengerJourneys(on: id, removing: pattern)
        abandonUnservedPassengers()
    }

    /// The line train `id` is assigned to, or `nil` if it is on none (or
    /// does not exist).
    public func assignedLine(of id: TrainID) -> LineID? {
        lines.first { line in (0..<line.serviceCount).contains { line.trains(ofService: $0).contains(id) } }?.id
    }

    /// The index of the pattern train `id` is assigned to, or `nil` if it
    /// is assigned to a line's own service, or to no line.
    public func assignedPattern(of id: TrainID) -> Int? {
        for line in lines {
            if let pattern = line.patterns.firstIndex(where: { $0.trains.contains(id) }) { return pattern }
        }
        return nil
    }

    /// Assigns a train to a line's own service, or to its pattern at index
    /// `pattern`, which from then on runs the train's timetable and
    /// service: it sends the train out on round trips from its first call
    /// (see ``advance(ticks:)``). Free, and the train may be placed or not,
    /// anywhere; only a train stopped at the first call can be sent out.
    /// Nothing else changes until the service sends the train out.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/unknownLine(_:)``, ``GameError/unknownLinePattern(_:)``,
    ///   ``GameError/trainOnLine(_:)`` if it is on a line already (this one
    ///   included), ``GameError/trainServiceActive(_:)`` while it runs a
    ///   service of its own (stop it first), or, since decision 515,
    ///   ``GameError/trainCannotClimb(_:)`` when the line runs on mountain
    ///   track and the train is not a mountain train, or, since decision
    ///   951, ``GameError/trainTrackMismatch(_:)`` when the line runs on
    ///   track of another system than the train's (``TrackCompatibility``).
    public mutating func assignTrain(_ id: TrainID, to line: LineID, pattern: Int? = nil) throws(GameError) {
        let index = try trainIndex(of: id)
        let (target, service) = try lineService(line, pattern: pattern)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        guard trains[index].climbsMountains || !runsOnMountainTrack(lines[target]) else { throw .trainCannotClimb(id) }
        // Decision 951: a train runs only on track of its own system.
        guard runs(trains[index].type, on: lines[target]) else { throw .trainTrackMismatch(id) }

        if service == 0 {
            lines[target].trains.insert(id, at: lines[target].trains.firstIndex { $0 > id } ?? lines[target].trains.count)
        } else {
            let roster = lines[target].patterns[service - 1].trains
            lines[target].patterns[service - 1].trains.insert(id, at: roster.firstIndex { $0 > id } ?? roster.count)
        }
        abandonUnservedPassengers()
    }

    /// Takes a train off its line, whichever of the line's services it is
    /// on. Only the assignment ends: a train on a round trip keeps its
    /// timetable and finishes the trip as an ordinary service, which can
    /// then be stopped like any other.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainNotOnLine(_:)``.
    public mutating func unassignTrain(_ id: TrainID) throws(GameError) {
        _ = try trainIndex(of: id)
        guard let index = lines.firstIndex(where: { $0.id == assignedLine(of: id) }) else { throw .trainNotOnLine(id) }

        lines[index].trains.removeAll { $0 == id }
        for pattern in lines[index].patterns.indices {
            lines[index].patterns[pattern].trains.removeAll { $0 == id }
        }
        abandonUnservedPassengers()
    }

    /// Takes every train that cannot climb (``Train/climbsMountains``) off
    /// each line that now runs on mountain track (decision 515 continued):
    /// after an edit moved the line's way onto it, as ``unassignTrain(_:)``
    /// would, from the line's own service and its patterns. A train on a
    /// round trip finishes it as an ordinary service. Called once at the
    /// end of every command that may change a line's journey (from
    /// ``abandonUnservedPassengers()``, before the passengers are checked);
    /// a world with no mountain track changes nothing and answers at once.
    mutating func releaseTrainsThatCannotClimb() {
        guard network.edges.contains(where: \.mountain) else { return }
        let climbers = Set(trains.filter(\.climbsMountains).map(\.id))
        for index in lines.indices {
            let assigned = lines[index].trains + lines[index].patterns.flatMap(\.trains)
            guard assigned.contains(where: { !climbers.contains($0) }), runsOnMountainTrack(lines[index]) else { continue }
            lines[index].trains.removeAll { !climbers.contains($0) }
            for pattern in lines[index].patterns.indices {
                lines[index].patterns[pattern].trains.removeAll { !climbers.contains($0) }
            }
        }
    }

    /// Makes line `id` keep to the right on double track, or to the left
    /// again (decision 564; ``ServiceLine/keepsRight``). Free. A train
    /// already on its way keeps the route it was given.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func setLineKeepsRight(_ id: LineID, to keepsRight: Bool) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        lines[index].keepsRight = keepsRight
    }

    /// Makes line `id` a freight line, or a passenger line again. Free.
    ///
    /// - Throws, checked in this order: ``GameError/freightNotEnabled`` (to
    ///   make one), ``GameError/unknownLine(_:)`` or ``GameError/trainOnLine(_:)``
    ///   naming a train assigned to it (take them off first).
    public mutating func setLineFreight(_ id: LineID, to isFreight: Bool) throws(GameError) {
        if isFreight, freight == nil { throw .freightNotEnabled }
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        guard lines[index].isFreight != isFreight else { return }
        if let train = lines[index].assignedTrains.first { throw .trainOnLine(train) }
        let wasHighSpeed = lines[index].isHighSpeed
        lines[index].isFreight = isFreight
        passengerPlan = PassengerPlanCache()
        abandonUnservedPassengers()
        // Decision 168: a freight line is not a high-speed line, whatever
        // it is planned at.
        if lines[index].isHighSpeed != wasHighSpeed { refreshLandDemand() }
    }

    // MARK: - Validation


    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    /// The index of line `id` and the service `pattern` names on it (see
    /// ``ServiceLine/serviceCount``).
    private func lineService(_ id: LineID, pattern: Int?) throws(GameError) -> (index: Int, service: Int) {
        let index = try lineIndex(of: id)
        guard let service = lines[index].service(pattern) else { throw .unknownLinePattern(pattern ?? 0) }
        return (index, service)
    }

    func lineIndex(of id: LineID) throws(GameError) -> Int {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        return index
    }

    private func requireLineStops(_ stops: [StationID], ring: Bool = false) throws(GameError) {
        guard ring ? ServiceLine.isRingStopList(stops) : ServiceLine.isStopList(stops) else { throw .invalidLineStops }
        if let missing = stops.first(where: { station(id: $0) == nil }) {
            throw .unknownStation(missing)
        }
        // Decision 209: no line calls at a depot.
        if let depot = stops.first(where: { station(id: $0)?.isDepot == true }) {
            throw .depotIsLineStop(depot)
        }
    }

    private func trainIndex(of id: TrainID) throws(GameError) -> Int {
        guard let index = trains.firstIndex(where: { $0.id == id }) else { throw .unknownTrain(id) }
        return index
    }

    private func placedTrain(_ id: TrainID) throws(GameError) -> (index: Int, position: TrainPosition) {
        let index = try trainIndex(of: id)
        guard let position = trains[index].position else { throw .trainNotPlaced(id) }
        return (index, position)
    }

    /// A placed train that no service is running: the commands that change
    /// its path or take it off the track need one.
    private func manuallyControlledTrain(_ id: TrainID) throws(GameError) -> (index: Int, position: TrainPosition) {
        let (index, position) = try placedTrain(id)
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        return (index, position)
    }

    /// Whether `position` is well formed and lies on this world's track: the
    /// edge exists and the offset lies within it (see
    /// ``isOnNetwork(_:offset:)``).
    func isOnTrack(_ position: TrainPosition) -> Bool {
        guard position.isWellFormed else { return false }
        switch position {
        case .onEdge(let traversal, let offset):
            return isOnNetwork(traversal, offset: offset)
        }
    }
}

// MARK: - ID allocation

extension GameWorld {
    /// The ID a counter hands out, and the counter's value afterwards.
    ///
    /// A counter holds the next ID to hand out, and every ID is below it, so
    /// handing out `next` needs `next + 1` to fit in an `Int`: the last ID is
    /// `Int.max - 1`, leaving the counter at `Int.max`, where it stays. Only
    /// reads the counter, so a command can check before changing anything.
    ///
    /// - Throws: ``GameError/idsExhausted`` once the counter is at `Int.max`.
    static func allocateID(from next: Int) throws(GameError) -> (id: Int, next: Int) {
        let (following, overflow) = next.addingReportingOverflow(1)
        guard !overflow else { throw .idsExhausted }
        return (next, following)
    }
}

// MARK: - Codable

extension GameWorld: Codable {
    private enum CodingKeys: String, CodingKey {
        case bounds, map, stations, trains, lines, serviceDay, clock, economy, nextStationID, nextTrainID, nextLineID, network, trafficControl
        case passengers, riders, passengerRoutingMode, passengerRouteBalances, weeklyDemand, tidalDemand, passengerPatience, annualTaxes, modeShift, demandEvents, disruptions, townGrowth, accounts, geoAnchor
        case land, landBlocks, landDemand, distanceDemand, farDemand, doorCrowding, keepLeft, switchInterlocking, switchLies, realisticOperation, blockSections, curveSpeedLimits, realCarLengths, spacingAllowances, flexDispatch, rollingStockEconomics, lineAccounts, tripLog, tourism, cityRequests, outsideConnections, realTransfers, acquisitions, leftTrack, cityDemand, cityFootprints, areaBuyOut, cityBuildings, buildings, transferGroups, nextTransferGroupID, scenario
        case placedBuildings, nextPlacedBuildingID, zones, terrain, ground, freight, mapExpansion, roads, busRoutes, nextBusRouteID, airports, coachStops, cableways, nextCablewayID, ferryRoutes, nextFerryRouteID, airRoutes, nextAirRouteID, driving
        case playerMelodies, nextPlayerMelodyID
    }

    /// Decodes a world, rejecting data that breaks cross-object invariants
    /// (IDs must be unique and below the next ID to allocate; every station
    /// must stand in the world's bounds; every placed train must be on this world's
    /// track, as ``placeTrain(_:at:)`` requires; every timetable stop must
    /// name one of this world's stations, as
    /// ``setTrainTimetable(_:to:repeatingEvery:)`` requires; a waiting
    /// service's train must be stopped at its stop's station, and a
    /// travelling service's journey must end beside the station of the stop
    /// it travels to, as a route from the service would; every line's
    /// and patterns' trains must exist and be on that service only, none of
    /// them may run a repeating timetable, and no service may have sent a
    /// train out after the current minute, as ``assignTrain(_:to:pattern:)`` and dispatching require).
    ///
    /// The edges of a path are not required to exist: track ahead of a train
    /// may have been removed after the path was set, and a world where a
    /// train waits at the end of its edge for a new path is valid.
    ///
    /// The grid went in Stage F3c (ARCHITECTURE decision 51). A save that
    /// holds any of it, which only a save made by hand could (the app has
    /// saved only the track network since saves began, Stage C4), is refused
    /// with that reason: grid track or a station on a tile in the map, a
    /// station on tiles, a train or a reservation on the grid, a body or a
    /// path on the grid.
    ///
    /// The world's extent is `"bounds"` in world units (Stage F3d, save
    /// version 6). A world saved before that has a `"map"` of tiles instead,
    /// read as the bounds its tiles cover (see `LegacyMap`); exactly one of
    /// the two is accepted.
    ///
    /// Under traffic control (Stage T) every reservation must fit its train
    /// and this world, and no two trains may hold the same track (see
    /// `trafficProblem()`); without it, no train may have a reservation.
    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, madeBeforeSpacing: false)
    }

    /// Decodes a world as ``init(from:)`` does. When `madeBeforeSpacing`,
    /// the world comes from a save made before Stage F2 (save version 4 or
    /// below, see ``SavedGame``): it has no `"spacingExemptions"`, and
    /// whatever pairs of edges it has closer than the track spacing become
    /// its exemptions, so the save loads as it was (ARCHITECTURE decision
    /// 52).
    init(from decoder: any Decoder, madeBeforeSpacing: Bool) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.bounds), container.contains(.map)) {
        case (true, false):
            bounds = try container.decode(WorldBounds.self, forKey: .bounds)
        case (false, true):
            bounds = try container.decode(LegacyMap.self, forKey: .map).bounds
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A world has its bounds (\"bounds\"), or, in a save before version 6, its map (\"map\"): exactly one of them."
            ))
        }
        stations = try container.decode([Station].self, forKey: .stations)
        trains = try container.decode([Train].self, forKey: .trains)
        clock = try container.decode(GameClock.self, forKey: .clock)
        economy = try container.decode(GameEconomy.self, forKey: .economy)
        nextStationID = try container.decode(Int.self, forKey: .nextStationID)
        nextTrainID = try container.decode(Int.self, forKey: .nextTrainID)
        lines = container.contains(.lines) ? try container.decode([ServiceLine].self, forKey: .lines) : []
        nextLineID = container.contains(.nextLineID) ? try container.decode(Int.self, forKey: .nextLineID) : 1
        serviceDay = container.contains(.serviceDay) ? try container.decode(ServiceDay.self, forKey: .serviceDay) : .standard
        network = container.contains(.network) ? try container.decode(RailwayNetwork.self, forKey: .network) : RailwayNetwork()
        isTrafficControlEnabled = container.contains(.trafficControl) ? try container.decode(Bool.self, forKey: .trafficControl) : false
        passengers = container.contains(.passengers) ? try container.decode([StationPassengers].self, forKey: .passengers) : []
        riders = container.contains(.riders) ? try container.decode([TrainRiders].self, forKey: .riders) : []
        passengerRoutingMode = container.contains(.passengerRoutingMode)
            ? try container.decode(PassengerRoutingMode.self, forKey: .passengerRoutingMode) : .direct
        weeklyDemand = container.contains(.weeklyDemand) ? try container.decode(Bool.self, forKey: .weeklyDemand) : false
        tidalDemand = try container.decodeIfPresent(Bool.self, forKey: .tidalDemand) ?? false
        passengerPatience = try container.decodeIfPresent(Bool.self, forKey: .passengerPatience) ?? false
        annualTaxes = try container.decodeIfPresent(Bool.self, forKey: .annualTaxes) ?? false
        modeShift = try container.decodeIfPresent(ModeShift.self, forKey: .modeShift)
        demandEvents = container.contains(.demandEvents) ? try container.decode(DemandEventSchedule.self, forKey: .demandEvents) : nil
        disruptions = try container.decodeIfPresent(Disruptions.self, forKey: .disruptions)
        townGrowth = container.contains(.townGrowth) ? try container.decode(TownGrowth.self, forKey: .townGrowth) : nil
        passengerRouteBalances = container.contains(.passengerRouteBalances)
            ? try container.decode([PassengerRouteBalance].self, forKey: .passengerRouteBalances) : []
        // A balance listing a journey twice, which builds before #366 (its
        // item 10) saved for a line calling twice at the same two stations,
        // is dropped rather than refused, so those saves load again. It is
        // only the rounding carried from one release to the next, and the
        // next release starts a new one from the plan, which lists each
        // journey once: merging the twins would give weights the plan never
        // has, and be dropped there all the same.
        passengerRouteBalances.removeAll { Set($0.journeys).count != $0.journeys.count }
        accounts = container.contains(.accounts) ? try container.decode(CompanyAccounts.self, forKey: .accounts) : CompanyAccounts()
        // Decision 315, later (PR #945–#961 review): a bought line removed
        // with its stations before #955 left its asset behind, so the save
        // was refused. It goes as removing the line writes it off; the loss
        // is not booked again.
        let lineIDs = Set(lines.map(\.id.rawValue))
        accounts.assets.removeAll { $0.kind == .acquiredLine && !lineIDs.contains($0.owner) }
        geoAnchor = container.contains(.geoAnchor) ? try container.decode(GeoAnchor.self, forKey: .geoAnchor) : nil
        land = container.contains(.land) ? try container.decode(Land.self, forKey: .land) : Land()
        if container.contains(.landBlocks) {
            // Decision 400's later point 2: no more blocks than the world
            // has, refused before they are spread out.
            let runs = try container.decode([LandBlockRun].self, forKey: .landBlocks)
            guard LandBlockRun.count(of: runs, atMost: Land.blockRows(in: bounds) * Land.blockColumns(in: bounds)) else {
                throw DecodingError.dataCorruptedError(forKey: .landBlocks, in: container, debugDescription: "The land blocks are more blocks than the world has.")
            }
            guard let blocks = LandBlockRun.blocks(of: runs) else {
                throw DecodingError.dataCorruptedError(forKey: .landBlocks, in: container, debugDescription: "A run of land blocks is empty or too long.")
            }
            landBlocks = blocks
        }
        landDemand = container.contains(.landDemand) ? try container.decode(Bool.self, forKey: .landDemand) : false
        distanceDemand = try container.decodeIfPresent(Bool.self, forKey: .distanceDemand) ?? false
        farDemand = try container.decodeIfPresent(Bool.self, forKey: .farDemand) ?? false
        doorCrowding = try container.decodeIfPresent(Bool.self, forKey: .doorCrowding) ?? false
        keepLeft = try container.decodeIfPresent(Bool.self, forKey: .keepLeft) ?? false
        switchInterlocking = try container.decodeIfPresent(Bool.self, forKey: .switchInterlocking) ?? false
        if let saved = try container.decodeIfPresent([SavedSwitchLie].self, forKey: .switchLies) {
            guard switchInterlocking, let lies = Self.switchLies(of: saved) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .switchLies, in: container,
                    debugDescription: "Switch lies are kept only with switch interlocking on, ordered by node, one each, with two ascending edges."
                )
            }
            switchLies = lies
        }
        realisticOperation = container.contains(.realisticOperation) ? try container.decode(Bool.self, forKey: .realisticOperation) : false
        blockSections = container.contains(.blockSections) ? try container.decode(Bool.self, forKey: .blockSections) : false
        curveSpeedLimits = container.contains(.curveSpeedLimits) ? try container.decode(Bool.self, forKey: .curveSpeedLimits) : false
        realCarLengths = try container.decodeIfPresent(Bool.self, forKey: .realCarLengths) ?? false
        if let saved = try container.decodeIfPresent([SavedSpacingAllowance].self, forKey: .spacingAllowances) {
            guard zip(saved, saved.dropFirst()).allSatisfy({ $0.train < $1.train }) else {
                throw DecodingError.dataCorruptedError(forKey: .spacingAllowances, in: container, debugDescription: "Spacing allowances must be ordered by train, one each.")
            }
            spacingAllowances = Dictionary(uniqueKeysWithValues: saved.map { ($0.train, $0.allowance) })
        }
        flexDispatch = try container.decodeIfPresent(Bool.self, forKey: .flexDispatch) ?? false
        rollingStockEconomics = try container.decodeIfPresent(Bool.self, forKey: .rollingStockEconomics) ?? false
        lineAccounts = try container.decodeIfPresent(LineAccounts.self, forKey: .lineAccounts)
        tripLog = container.contains(.tripLog) ? try container.decode([TrainTrip].self, forKey: .tripLog) : []
        acquisitions = try container.decodeIfPresent([LineAcquisition].self, forKey: .acquisitions) ?? []
        if container.contains(.acquisitions), acquisitions.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .acquisitions, in: container, debugDescription: "A world is written with \"acquisitions\" only when it bought a line.")
        }
        leftTrack = try container.decodeIfPresent([LeftTrack].self, forKey: .leftTrack) ?? []
        if container.contains(.leftTrack), leftTrack.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .leftTrack, in: container, debugDescription: "A world is written with \"leftTrack\" only when a line bought left some.")
        }
        tourism = try container.decodeIfPresent(Tourism.self, forKey: .tourism)
        driving = try container.decodeIfPresent(DrivingRecord.self, forKey: .driving)
        cityRequests = try container.decodeIfPresent(CityRequests.self, forKey: .cityRequests)
        outsideConnections = try container.decodeIfPresent(Bool.self, forKey: .outsideConnections) ?? false
        // Decision 298: written only when on (every save before version 64
        // has it off), and only then may a station have transfer points.
        realTransfers = container.contains(.realTransfers) ? try container.decode(Bool.self, forKey: .realTransfers) : false
        if container.contains(.realTransfers), !realTransfers {
            throw DecodingError.dataCorruptedError(forKey: .realTransfers, in: container, debugDescription: "A world is written with \"realTransfers\" only when they are on.")
        }
        if !realTransfers, let station = stations.first(where: { $0.transferPoints > 0 }) {
            throw DecodingError.dataCorruptedError(forKey: .stations, in: container, debugDescription: "Station \(station.id.rawValue) has transfer points, but real transfers are off.")
        }
        cityDemand = try container.decodeIfPresent(CityDemand.self, forKey: .cityDemand)
        cityFootprints = try container.decodeIfPresent(Bool.self, forKey: .cityFootprints) ?? false
        areaBuyOut = try container.decodeIfPresent(Bool.self, forKey: .areaBuyOut) ?? false
        cityBuildings = container.contains(.cityBuildings) ? try container.decode(Bool.self, forKey: .cityBuildings) : false
        buildings = container.contains(.buildings) ? try container.decode(CityBuildings.self, forKey: .buildings) : CityBuildings()
        transferGroups = container.contains(.transferGroups) ? try container.decode([TransferGroup].self, forKey: .transferGroups) : []
        nextTransferGroupID = container.contains(.nextTransferGroupID) ? try container.decode(Int.self, forKey: .nextTransferGroupID) : 1
        scenario = try container.decodeIfPresent(ScenarioState.self, forKey: .scenario)
        placedBuildings = container.contains(.placedBuildings) ? try container.decode([PlacedBuilding].self, forKey: .placedBuildings) : []
        nextPlacedBuildingID = container.contains(.nextPlacedBuildingID) ? try container.decode(Int.self, forKey: .nextPlacedBuildingID) : 1
        zones = container.contains(.zones) ? try container.decode(Zoning.self, forKey: .zones) : Zoning()
        terrain = container.contains(.terrain) ? try container.decode(Terrain.self, forKey: .terrain) : Terrain()
        ground = container.contains(.ground) ? try container.decode(Ground.self, forKey: .ground) : Ground()
        freight = try container.decodeIfPresent(FreightState.self, forKey: .freight)
        mapExpansion = try container.decodeIfPresent(MapExpansion.self, forKey: .mapExpansion)
        // Decision 400's later point 2: no more road cells than the world
        // has, refused before they are spread out.
        if container.contains(.roads), try !container.decodeNil(forKey: .roads) {
            roads = try RoadGrid(from: container.superDecoder(forKey: .roads),
                                 cellLimit: Land.rows(in: bounds) * Land.columns(in: bounds),
                                 blockLimit: Land.blockRows(in: bounds) * Land.blockColumns(in: bounds))
        }
        busRoutes = try container.decodeIfPresent([BusRoute].self, forKey: .busRoutes) ?? []
        nextBusRouteID = try container.decodeIfPresent(Int.self, forKey: .nextBusRouteID) ?? 1
        cableways = try container.decodeIfPresent([Cableway].self, forKey: .cableways) ?? []
        nextCablewayID = try container.decodeIfPresent(Int.self, forKey: .nextCablewayID) ?? 1
        ferryRoutes = try container.decodeIfPresent([FerryRoute].self, forKey: .ferryRoutes) ?? []
        nextFerryRouteID = try container.decodeIfPresent(Int.self, forKey: .nextFerryRouteID) ?? 1
        airports = try container.decodeIfPresent([Airport].self, forKey: .airports) ?? []
        airRoutes = try container.decodeIfPresent([AirRoute].self, forKey: .airRoutes) ?? []
        nextAirRouteID = try container.decodeIfPresent(Int.self, forKey: .nextAirRouteID) ?? 1
        coachStops = try container.decodeIfPresent([CoachStop].self, forKey: .coachStops) ?? []
        // Decision 883: a world without player melodies has neither key
        // (every save before version 111).
        playerMelodies = try container.decodeIfPresent([PlayerMelody].self, forKey: .playerMelodies) ?? []
        nextPlayerMelodyID = try container.decodeIfPresent(Int.self, forKey: .nextPlayerMelodyID) ?? 1
        // Decision 528: a purchase whose line or bus route was removed
        // before it went with it is dropped, so the real line is on sale
        // again; nothing is paid back or booked again. One naming a number
        // never handed out is still refused below.
        let busRouteIDs = Set(busRoutes.map(\.id)), linesHandedOut = lineIDsHandedOut, routesHandedOut = nextBusRouteID
        acquisitions.removeAll { bought in
            if let line = bought.line { return line.rawValue < linesHandedOut && !lineIDs.contains(line.rawValue) }
            if let route = bought.busRoute { return route.rawValue < routesHandedOut && !busRouteIDs.contains(route) }
            return false
        }
        if madeBeforeSpacing {
            guard network.spacingExemptions.isEmpty else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "A save made before Stage F2 has no spacing exemptions."
                ))
            }
            let geometries = network.edges.compactMap { network.geometry(of: $0.id) }
            network.exemptFromSpacing(network.tooClosePairs(geometries: geometries))
        }

        if let problem = invariantViolation() {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: problem)
            )
        }
    }

    /// Encodes the world. A world without lines has no `"lines"` key, one
    /// that never had a line no `"nextLineID"`, and one with the standard
    /// service day no `"serviceDay"`: such worlds save exactly as before
    /// lines existed, and those saves read as having none, handing out line
    /// IDs from 1, with the standard day. Likewise a world whose track
    /// network never had a node or an edge has no `"network"` key (Stage
    /// S3), and a save without one reads as an empty network; a world
    /// with traffic control off has no `"trafficControl"` key (Stage T),
    /// which is also how saves made before it read; a blank map has no
    /// `"geoAnchor"` (Stage E2); a world without land has no `"land"`
    /// (Phase 6a), and one whose land is whole no `"landBlocks"` (decision
    /// 88); a world with the city's buildings off has no
    /// `"cityBuildings"` and no `"buildings"` (Phase 6c-1); and one without
    /// transfer groups has no `"transferGroups"`, and one that never had
    /// one no `"nextTransferGroupID"` (decision 81); likewise
    /// `"placedBuildings"` and `"nextPlacedBuildingID"` (decision 92), and
    /// `"zones"` (decision 98), `"terrain"` (decision 105), and `"ground"`
    /// (decision 124). An explicit
    /// `null` for any of them is
    /// rejected. The world's extent is written as `"bounds"`, in world units
    /// (Stage F3d).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bounds, forKey: .bounds)
        try container.encode(stations, forKey: .stations)
        try container.encode(trains, forKey: .trains)
        if !lines.isEmpty {
            try container.encode(lines, forKey: .lines)
        }
        if serviceDay != .standard {
            try container.encode(serviceDay, forKey: .serviceDay)
        }
        try container.encode(clock, forKey: .clock)
        try container.encode(economy, forKey: .economy)
        try container.encode(nextStationID, forKey: .nextStationID)
        try container.encode(nextTrainID, forKey: .nextTrainID)
        if nextLineID != 1 {
            try container.encode(nextLineID, forKey: .nextLineID)
        }
        if !network.isPristine {
            try container.encode(network, forKey: .network)
        }
        if isTrafficControlEnabled {
            try container.encode(true, forKey: .trafficControl)
        }
        if !passengers.isEmpty {
            try container.encode(passengers, forKey: .passengers)
        }
        if !riders.isEmpty {
            try container.encode(riders, forKey: .riders)
        }
        if weeklyDemand {
            try container.encode(weeklyDemand, forKey: .weeklyDemand)
        }
        if tidalDemand {
            try container.encode(tidalDemand, forKey: .tidalDemand)
        }
        if passengerPatience {
            try container.encode(true, forKey: .passengerPatience)
        }
        if annualTaxes {
            try container.encode(true, forKey: .annualTaxes)
        }
        try container.encodeIfPresent(modeShift, forKey: .modeShift)
        try container.encodeIfPresent(demandEvents, forKey: .demandEvents)
        try container.encodeIfPresent(disruptions, forKey: .disruptions)
        try container.encodeIfPresent(townGrowth, forKey: .townGrowth)
        if passengerRoutingMode != .direct {
            try container.encode(passengerRoutingMode, forKey: .passengerRoutingMode)
        }
        if !passengerRouteBalances.isEmpty {
            try container.encode(passengerRouteBalances, forKey: .passengerRouteBalances)
        }
        if !accounts.isPristine {
            try container.encode(accounts, forKey: .accounts)
        }
        if let geoAnchor {
            try container.encode(geoAnchor, forKey: .geoAnchor)
        }
        if !land.isEmpty {
            try container.encode(land, forKey: .land)
        }
        if let landBlocks {
            try container.encode(LandBlockRun.runs(of: landBlocks), forKey: .landBlocks)
        }
        if landDemand {
            try container.encode(true, forKey: .landDemand)
        }
        if distanceDemand {
            try container.encode(true, forKey: .distanceDemand)
        }
        if farDemand {
            try container.encode(true, forKey: .farDemand)
        }
        if doorCrowding {
            try container.encode(true, forKey: .doorCrowding)
        }
        if keepLeft {
            try container.encode(true, forKey: .keepLeft)
        }
        if switchInterlocking {
            try container.encode(true, forKey: .switchInterlocking)
        }
        if !switchLies.isEmpty {
            try container.encode(savedSwitchLies, forKey: .switchLies)
        }
        if realisticOperation {
            try container.encode(true, forKey: .realisticOperation)
        }
        if blockSections {
            try container.encode(true, forKey: .blockSections)
        }
        if curveSpeedLimits {
            try container.encode(true, forKey: .curveSpeedLimits)
        }
        if realCarLengths {
            try container.encode(true, forKey: .realCarLengths)
        }
        if !spacingAllowances.isEmpty {
            let saved = spacingAllowances.sorted { $0.key < $1.key }.map { SavedSpacingAllowance(train: $0.key, $0.value) }
            try container.encode(saved, forKey: .spacingAllowances)
        }
        if flexDispatch {
            try container.encode(true, forKey: .flexDispatch)
        }
        if rollingStockEconomics {
            try container.encode(true, forKey: .rollingStockEconomics)
        }
        if let lineAccounts {
            try container.encode(lineAccounts, forKey: .lineAccounts)
        }
        if !tripLog.isEmpty {
            try container.encode(tripLog, forKey: .tripLog)
        }
        if !leftTrack.isEmpty {
            try container.encode(leftTrack, forKey: .leftTrack)
        }
        if !acquisitions.isEmpty {
            try container.encode(acquisitions, forKey: .acquisitions)
        }
        try container.encodeIfPresent(tourism, forKey: .tourism)
        try container.encodeIfPresent(driving, forKey: .driving)
        try container.encodeIfPresent(cityRequests, forKey: .cityRequests)
        if outsideConnections {
            try container.encode(true, forKey: .outsideConnections)
        }
        if realTransfers {
            try container.encode(true, forKey: .realTransfers)
        }
        if let cityDemand {
            try container.encode(cityDemand, forKey: .cityDemand)
        }
        if let freight {
            try container.encode(freight, forKey: .freight)
        }
        try container.encodeIfPresent(mapExpansion, forKey: .mapExpansion)
        try container.encodeIfPresent(roads, forKey: .roads)
        if !busRoutes.isEmpty {
            try container.encode(busRoutes, forKey: .busRoutes)
        }
        if nextBusRouteID != 1 {
            try container.encode(nextBusRouteID, forKey: .nextBusRouteID)
        }
        if !airports.isEmpty {
            try container.encode(airports, forKey: .airports)
        }
        if !coachStops.isEmpty {
            try container.encode(coachStops, forKey: .coachStops)
        }
        if !playerMelodies.isEmpty {
            try container.encode(playerMelodies, forKey: .playerMelodies)
        }
        if nextPlayerMelodyID != 1 {
            try container.encode(nextPlayerMelodyID, forKey: .nextPlayerMelodyID)
        }
        if !cableways.isEmpty {
            try container.encode(cableways, forKey: .cableways)
        }
        if nextCablewayID != 1 {
            try container.encode(nextCablewayID, forKey: .nextCablewayID)
        }
        if !ferryRoutes.isEmpty {
            try container.encode(ferryRoutes, forKey: .ferryRoutes)
        }
        if nextFerryRouteID != 1 {
            try container.encode(nextFerryRouteID, forKey: .nextFerryRouteID)
        }
        if !airRoutes.isEmpty {
            try container.encode(airRoutes, forKey: .airRoutes)
        }
        if nextAirRouteID != 1 {
            try container.encode(nextAirRouteID, forKey: .nextAirRouteID)
        }
        if cityFootprints {
            try container.encode(true, forKey: .cityFootprints)
        }
        if areaBuyOut {
            try container.encode(true, forKey: .areaBuyOut)
        }
        if cityBuildings {
            try container.encode(true, forKey: .cityBuildings)
        }
        if !buildings.isEmpty {
            try container.encode(buildings, forKey: .buildings)
        }
        if !transferGroups.isEmpty {
            try container.encode(transferGroups, forKey: .transferGroups)
        }
        if nextTransferGroupID != 1 {
            try container.encode(nextTransferGroupID, forKey: .nextTransferGroupID)
        }
        try container.encodeIfPresent(scenario, forKey: .scenario)
        if !placedBuildings.isEmpty {
            try container.encode(placedBuildings, forKey: .placedBuildings)
        }
        if nextPlacedBuildingID != 1 {
            try container.encode(nextPlacedBuildingID, forKey: .nextPlacedBuildingID)
        }
        if !zones.isEmpty {
            try container.encode(zones, forKey: .zones)
        }
        if !terrain.isEmpty {
            try container.encode(terrain, forKey: .terrain)
        }
        if ground.isMapped {
            try container.encode(ground, forKey: .ground)
        }
    }

    /// The world's size as a save before version 6 holds it: a map of
    /// tiles (``LegacyGrid/tileLength`` units a tile) with its land, read as
    /// the bounds it covers and never written (Stage F3d, ARCHITECTURE
    /// decision 54).
    ///
    /// Two forms (Stage E1, ARCHITECTURE decision 48):
    ///
    /// - `{"width", "height", "occupied"}`, written from save version 2 to
    ///   5: only the tiles that are not empty ground, each with its
    ///   position, in row-major order.
    /// - `{"width", "height", "tiles"}`: every tile in row-major order, the
    ///   form every save had from Stage I to save version 1.
    ///
    /// Every tile is empty ground, so `"occupied"` is `[]`. Until Stage F3c
    /// a tile could hold grid track (`"track"`, `"turnout"`, `"crossing"`)
    /// or a station (`"station"`); a save with any, which only a save made
    /// by hand could hold, is refused with that reason (ARCHITECTURE
    /// decision 51).
    private struct LegacyMap: Decodable {
        /// A saved tile: `{"empty": {}}`, or one of the grid's kinds,
        /// refused.
        private struct Tile: Decodable {
            private struct Key: CodingKey {
                let stringValue: String
                var intValue: Int? { nil }
                init(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { nil }
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                guard container.allKeys.count == 1, let kind = container.allKeys.first else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: "A tile is exactly one kind."))
                }
                switch kind.stringValue {
                case "empty":
                    _ = try container.nestedContainer(keyedBy: Key.self, forKey: kind)
                case "track", "turnout", "crossing", "station":
                    throw DecodingError.dataCorruptedError(
                        forKey: kind, in: container,
                        debugDescription: "A map with grid track or a station on a tile (\"\(kind.stringValue)\") is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold one."
                    )
                default:
                    throw DecodingError.dataCorruptedError(forKey: kind, in: container, debugDescription: "\(kind.stringValue) is not a kind of tile.")
                }
            }
        }

        /// A tile that is not empty ground, and where it is: never one now.
        private struct Occupied: Decodable {
            let x: Int
            let y: Int
            let tile: Tile
        }

        private enum CodingKeys: String, CodingKey {
            case width, height, occupied, tiles
        }

        /// The bounds the map covers.
        let bounds: WorldBounds

        /// Decodes either form, rejecting a size the map could not have
        /// (1 to ``LegacyGrid/maximumTiles`` tiles a side), both forms or
        /// neither, a tile count that does not match the size, an occupied
        /// tile off the map, and any tile that is not empty ground.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let width = try container.decode(Int.self, forKey: .width)
            let height = try container.decode(Int.self, forKey: .height)
            func corrupt(_ key: CodingKeys, _ description: String) -> DecodingError {
                DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: description)
            }
            let sides = 1...LegacyGrid.maximumTiles
            guard sides.contains(width), sides.contains(height) else {
                throw corrupt(.width, "\(width)x\(height) is not a size a map can have.")
            }
            switch (container.contains(.occupied), container.contains(.tiles)) {
            case (true, false):
                // A tile that is not empty is refused while it is read; one
                // that is empty is not occupied.
                if let entry = try container.decode([Occupied].self, forKey: .occupied).first {
                    guard (0..<width).contains(entry.x), (0..<height).contains(entry.y) else {
                        throw corrupt(.occupied, "Tile (\(entry.x), \(entry.y)) lies off the \(width)x\(height) map.")
                    }
                    throw corrupt(.occupied, "Tile (\(entry.x), \(entry.y)) is listed as occupied but empty.")
                }
            case (false, true):
                let tiles = try container.decode([Tile].self, forKey: .tiles)
                guard tiles.count == width * height else {
                    throw corrupt(.tiles, "Tile count \(tiles.count) does not match a valid \(width)x\(height) map.")
                }
            case (true, true):
                throw corrupt(.occupied, "A map has its occupied tiles or every tile, not both.")
            case (false, false):
                throw corrupt(.occupied, "A map needs its occupied tiles.")
            }
            // At most 1024 × 1024 units a side: within the bounds' limit.
            bounds = try WorldBounds(width: Int64(width) * LegacyGrid.tileLength, height: Int64(height) * LegacyGrid.tileLength)
        }
    }

    private func invariantViolation() -> String? {
        let stationIDs = stations.map(\.id.rawValue)
        guard Self.isStrictlyIncreasing(stationIDs, below: nextStationID) else {
            return "Station IDs must be unique, ascending and below nextStationID."
        }
        // Decision 325: the high-speed fare table names only stations that
        // were handed out, so a station built later cannot take on a fare.
        guard accounts.highSpeedFares.allSatisfy({ $0.from.rawValue >= 1 && $0.to.rawValue < nextStationID }) else {
            return "High-speed fares must be between stations below nextStationID."
        }
        guard Self.isStrictlyIncreasing(trains.map(\.id.rawValue), below: nextTrainID) else {
            return "Train IDs must be unique, ascending and below nextTrainID."
        }
        guard Self.isStrictlyIncreasing(lines.map(\.id.rawValue), below: nextLineID) else {
            return "Line IDs must be unique, ascending and below nextLineID."
        }
        if let book = lineAccounts, !book.isValid(lines: Set(lines.map(\.id)), stations: Set(stations.map(\.id))) {
            return "The line accounts must be well formed, for lines and stations that exist."
        }
        if let problem = tripLogProblem(trainIDsBelow: nextTrainID) { return problem }
        if let problem = acquisitionsProblem() { return problem }
        guard spacingAllowances.allSatisfy({ $0.key.rawValue < nextTrainID && $0.value.isValid }) else {
            return "Every spacing allowance must be well formed, of a train ID handed out."
        }
        if let problem = transferGroupProblem() { return problem }
        if let problem = placedBuildingProblem() { return problem }
        if let problem = freightProblem() { return problem }
        if let problem = tourismProblem() { return problem }
        if let problem = drivingProblem() { return problem }
        if let problem = cityRequestsProblem() { return problem }
        var assigned: Set<TrainID> = []
        for line in lines {
            guard Self.isValidName(line.name) else { return "Line \(line.id.rawValue) has an invalid name." }
            if let missing = line.stops.first(where: { station(id: $0) == nil }) {
                return "Line \(line.id.rawValue) calls at station \(missing.rawValue), which does not exist."
            }
            // Decision 209: no line calls at a depot, and a line's depots
            // are depots (decision 221: several, none twice, on a line with
            // runs too).
            if let depot = line.stops.first(where: { station(id: $0)?.isDepot == true }) {
                return "Line \(line.id.rawValue) calls at station \(depot.rawValue), which is a depot."
            }
            if let depot = line.depots.first(where: { station(id: $0)?.isDepot != true }) {
                return "Line \(line.id.rawValue)'s depot \(depot.rawValue) must be a depot station."
            }
            if Set(line.depots).count != line.depots.count {
                return "Line \(line.id.rawValue) has a depot twice."
            }
            for service in 0..<line.serviceCount {
                for id in line.trains(ofService: service) {
                    guard let train = train(id: id) else { return "Line \(line.id.rawValue) has train \(id.rawValue), which does not exist." }
                    guard assigned.insert(id).inserted else { return "Train \(id.rawValue) is assigned to two lines or services." }
                    // A line sends its trains out on trips that run once, and
                    // no other service can start while a train is on a line.
                    guard train.execution == nil || train.timetablePeriod == nil else {
                        return "Line \(line.id.rawValue)'s train \(id.rawValue) runs a repeating timetable."
                    }
                }
                if let last = line.lastDispatch(ofService: service), last > clock.now {
                    return "Line \(line.id.rawValue) sent a train out after the current minute."
                }
            }
            if let last = line.endLastDispatch, last > clock.now {
                return "Line \(line.id.rawValue) sent a train out from its last stop after the current minute."
            }
            if let last = line.outerLastDispatch, last > clock.now {
                return "Line \(line.id.rawValue) sent a train out the outer way after the current minute."
            }
            // Decision 133: a run sends its train out at most
            // `LineRun.earliestDispatch` before its day's first departure.
            let (ahead, past) = clock.now.seconds.addingReportingOverflow(LineRun.earliestDispatch)
            if let latest = line.runDays.compactMap({ $0 }).max(),
               latest > GameTime.floorDivide(past ? .max : ahead, GameTime.secondsPerDay) {
                return "Line \(line.id.rawValue) ran a run on a day that has not come."
            }
        }
        for station in stations {
            guard Self.isValidName(station.name) else { return "Station \(station.id.rawValue) has an invalid name." }
            guard bounds.contains(station.point) else {
                return "Station \(station.id.rawValue) stands outside the world's bounds."
            }
        }
        guard trains.allSatisfy({ Self.isValidName($0.name) }) else {
            return "A train has an invalid name."
        }
        // Stage S3: the network lies in the world's bounds; Stage S4: at the
        // heights a world allows.
        guard network.nodes.allSatisfy({ isInWorld($0.position) }) else {
            return "A track node lies outside the world's bounds or beyond the heights track may have."
        }
        guard network.edges.allSatisfy({ $0.curve.controlPoints.allSatisfy(bounds.contains) }) else {
            return "A track edge's curve leaves the world's bounds."
        }
        if let problem = networkRuleProblem() {
            return problem
        }
        for train in trains {
            if train.trafficVisits.contains(where: { visit in station(id: visit.station) == nil || visit.arrival > clock.now || visit.departure.map { $0 > clock.now || $0 < visit.arrival } == true }) {
                return "Traffic visit is invalid or after the clock."
            }
            if let position = train.position, !isOnTrack(position) {
                return "Train \(train.id.rawValue) is not on this map's track."
            }
            if case .onEdge(let traversal, let offset)? = train.position,
               !isNetworkTrail(train.trailEdges, behind: traversal, offset: offset, length: train.length) {
                return "Train \(train.id.rawValue)'s body is not on track it could have come along."
            }
            // IDs are never reused, so an edge that was built once is below
            // the next number even after it was removed.
            guard train.movement.edges.allSatisfy({ ($0.networkNumber ?? .max) < network.nextEdgeNumber }) else {
                return "Train \(train.id.rawValue)'s path names an edge that was never built."
            }
            // Stage S5: a path that stops part of the way along its last edge
            // stops inside it (checked while that edge is still there).
            if let end = train.movement.end, case .onEdge(let traversal, _)? = train.position,
               let last = network.edge(train.movement.edges.last ?? traversal.edge), end >= last.length {
                return "Train \(train.id.rawValue)'s path stops beyond the end of its last edge."
            }
            if let stop = train.timetable.first(where: { station(id: $0.station) == nil }) {
                return "Train \(train.id.rawValue)'s timetable names station \(stop.station.rawValue), which does not exist."
            }
            if let problem = serviceProblem(of: train) {
                return problem
            }
            // Stage W2b: what a service did happened no later than now: it
            // arrived, its doors opened if its exchange has started, they
            // started closing, and it left the call before.
            // Decision 756: a run may start as long after as its switches
            // take to throw, also once the interlocking or traffic control
            // was turned off while they were thrown.
            if let times = train.times,
               times.latest(throwing: Self.switchThrowSeconds) > clock.now || (times.exchangeEnd != nil && Self.saturating(times.arrival, plus: ServiceDwell.doorOpening) > clock.now) {
                return "Train \(train.id.rawValue)'s service times are after the clock."
            }
        }
        if let problem = trafficProblem() ?? passengerProblem() ?? riderProblem() ?? accountsProblem() ?? scenarioProblem() ?? demandEventProblem()
            ?? townGrowthProblem() {
            return problem
        }
        if let problem = land.problem(in: bounds) ?? landBlocksProblem() ?? buildingProblem() ?? zones.problem(in: bounds) ?? terrainProblem()
            ?? ground.problem(in: bounds) ?? mapExpansionProblem() ?? roads?.problem(in: bounds) {
            return problem
        }
        return busRoutesProblem() ?? cablewaysProblem() ?? ferryRoutesProblem() ?? airportsProblem() ?? airRoutesProblem() ?? coachStopsProblem() ?? playerMelodiesProblem()
    }

    /// Why the trains' reservations break a Stage T rule (ARCHITECTURE
    /// decision 32, point 14), or `nil`. ``Train``'s decoder has checked
    /// each reservation is in order without repeats, and only on a placed
    /// train.
    ///
    /// Without traffic control no train has a reservation. With it, a train
    /// with a way left to go has one holding at least everything the rest of
    /// its route needs, and a train that stands has none; every reserved
    /// resource exists (a node, or a span of an edge as its platforms cut it
    /// now), except on the train's own way ahead; and no two trains hold the
    /// same track. A reservation may hold more than the
    /// route still needs (track the train has passed, which Stage T does not
    /// release): that is a lock, not an error.
    private func trafficProblem() -> String? {
        guard isTrafficControlEnabled else {
            guard trains.allSatisfy({ $0.reservation.isEmpty }) else { return "A train has a reservation while traffic control is off." }
            return nil
        }
        var held: [(id: TrainID, resources: Set<TrackResource>)] = []
        for train in trains where train.position != nil {
            let id = train.id.rawValue
            let envelope = routeEnvelope(of: train)
            guard envelope.moves != train.reservation.isEmpty else {
                return envelope.moves
                    ? "Train \(id) has a way left to go under traffic control but no reservation."
                    : "Train \(id) stands but keeps a reservation."
            }
            if envelope.moves, !envelope.resources.isSubset(of: Set(train.reservation)) {
                // Stage U2: a train following another holds its route part
                // of the way, from where it stands, and never where it ends:
                // one that holds the end is taken to hold all of it (see
                // ``authority(of:)``), so a hole before it is refused.
                guard isFollowing(train), authorityEnvelope(of: train, to: 0).isSubset(of: Set(train.reservation)) else {
                    return "Train \(id)'s reservation does not hold the rest of its route."
                }
            }
            for resource in train.reservation where !resourceExists(resource) && !envelope.resources.contains(resource) {
                return "Train \(id) has reserved \(resource), which is not track of this world."
            }
            let resources = self.held(train)
            if let other = held.first(where: { !$0.resources.isDisjoint(with: resources) }) {
                return "Trains \(other.id.rawValue) and \(id) hold the same track under traffic control."
            }
            held.append((train.id, resources))
        }
        return nil
    }

    /// Whether `resource` is track of this world now: a node of the track
    /// network, or a span of an edge as its platforms cut it now (see
    /// ``trackSpans(of:)``).
    private func resourceExists(_ resource: TrackResource) -> Bool {
        switch resource {
        case .node(let node):
            return trackNode(node) != nil
        case .span(let span):
            return trackSpans(of: span.edge).contains(span)
        }
    }

    /// Why the track network breaks a Stage S4 rule, or `nil`: an edge
    /// steeper than the maximum grade or on a structure that cannot carry it
    /// at its heights, two edges meeting without clearance, two edges closer
    /// than the track spacing that are not exempt or exempt edges that are
    /// not (Stage F2), or a platform that does not fit its edge or overlaps
    /// another.
    private func networkRuleProblem() -> String? {
        var geometries: [TrackGeometry] = []
        for edge in network.edges {
            guard let geometry = network.geometry(of: edge.id) else { return "Track edge \(edge.id) has no geometry." }
            geometries.append(geometry)
            guard geometry.steepestGrade.isNoSteeper(than: edge.maximumGrade) else {
                return "Track edge \(edge.id) is steeper than the maximum grade."
            }
            if let problem = structureProblem(of: edge, geometry: geometry) {
                return problem
            }
        }
        if let (a, b) = network.firstConflictingPair(geometries: geometries) {
            return "Track edges \(a) and \(b) meet without clearance."
        }
        let tooClose = network.tooClosePairs(geometries: geometries)
        if tooClose != network.spacingExemptions {
            if let pair = tooClose.first(where: { !network.spacingExemptions.contains($0) }) {
                return "Track edges \(pair.first) and \(pair.second) are closer than the track spacing."
            }
            return "A spacing exemption lists two edges that keep the track spacing."
        }
        // The network's decoder has checked the platforms are in order and
        // do not overlap.
        for platform in network.platforms {
            guard station(id: platform.station) != nil else {
                return "A platform belongs to station \(platform.station.rawValue), which does not exist."
            }
            guard isValidPlatform(platform) else {
                return "Station \(platform.station.rawValue) has a platform that does not fit its edge."
            }
        }
        return nil
    }

    /// Why a train's service does not fit this world's stations, or `nil`.
    /// ``Train``'s decoder has already checked that the service fits the
    /// timetable, position and movement as far as it can without the map.
    ///
    /// A waiting train is stopped at its stop's station. A travelling train's
    /// path is not spent, and it ends at a berth of a platform of the
    /// station of the stop it travels to that the train fits (Stage S5), as every path from the service does; such a platform
    /// cannot be removed while the service needs it (see
    /// ``removeTrackPlatform(_:on:from:)``). Since Stage V2 a travelling
    /// train may also be on its way to, or stand at, a passing place: a
    /// berth of another station (see ``isAtPassingPlace(_:)``). Where an edge on the way was
    /// removed, so the path can no longer be followed to its last edge, that
    /// edge still has such a berth, one way or the other, where it ends.
    private func serviceProblem(of train: Train) -> String? {
        guard let execution = train.execution, train.position != nil,
              let station = station(id: train.timetable[execution.stop].station)
        else { return nil }
        switch execution {
        case .waitingAtStop:
            guard isStopped(train, at: station.id) else {
                return "Train \(train.id.rawValue)'s service waits at a station the train is not stopped at."
            }
        case .travellingToStop:
            if standingPoint(of: train) != nil {
                // Stage V2: only at a passing place, a berth of another
                // station than its call's.
                guard !isStopped(train, at: station.id), stations.contains(where: { standsAtBerth(train, of: $0.id) }) else {
                    return "Train \(train.id.rawValue)'s service travels, but its path is spent."
                }
            } else {
                // Stage V2: or to a passing place.
                guard pathEndsAtBerth(of: train, for: station.id) || stations.contains(where: { pathEndsAtBerth(of: train, for: $0.id) }) else {
                    return "Train \(train.id.rawValue)'s service travels on a path that does not end at its next stop."
                }
            }
        }
        return nil
    }

    /// Whether `train` stands at a berth of station `id` for its length
    /// (see ``berths(of:length:)``): its head exactly there, the way it
    /// faces.
    private func standsAtBerth(_ train: Train, of id: StationID) -> Bool {
        guard case .onEdge(let traversal, let offset)? = train.position else { return false }
        return berths(of: id, length: train.length).contains(Berth(traversal: traversal, offset: offset))
    }

    /// Whether the path of `train` ends at a berth
    /// of station `id` for its length (Stage S5; see ``berths(of:length:)``):
    /// followed along its edges to the last, exactly; when an edge on the
    /// way no longer exists, at a berth on the last edge either way.
    private func pathEndsAtBerth(of train: Train, for id: StationID) -> Bool {
        guard case .onEdge(let traversal, _)? = train.position else { return false }
        let lastEdge = train.movement.remainingEdges.last ?? traversal.edge
        guard let length = network.edge(lastEdge)?.length else { return false }
        let end = train.movement.end ?? length
        let berths = berths(of: id, length: train.length)
        var last: TrackTraversal? = traversal
        for edge in train.movement.remainingEdges {
            last = last.flatMap { arrival in transitions(after: arrival).first { $0.edge == edge } }
        }
        guard let last else { return berths.contains { $0.traversal.edge == lastEdge && $0.offset == end } }
        return berths.contains(Berth(traversal: last, offset: end))
    }

    static func isStrictlyIncreasing(_ ids: [Int], below limit: Int) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 } && (ids.last ?? 0) < limit && (ids.first ?? 1) >= 1
    }
}

// V3 actual traffic events, written only by GameWorld.
extension GameWorld {
    /// Record only actual visits needed by this plan. Crossing tests use
    /// the physical path, so a zero rate or truncated authority never
    /// creates a fictitious event. Called at one-second boundaries in V3.
    mutating func recordTrafficVisits(_ plan: TrafficPlan, before: [Train]?) {
        guard !plan.waits.isEmpty else { return }
        for index in trains.indices {
            let train = trains[index]
            guard let service = plan.services.first(where: { $0.train.id == train.id }) else { continue }
            let needed = service.points.filter { p in
                plan.waits.contains { w in
                    w.station == p.station && ((w.train == train.id && w.stop == p.stop && w.cycle == p.cycle)
                                              || (w.other == train.id && w.otherStop == p.stop && w.otherCycle == p.cycle))
                }
            }
            for point in needed {
                var arrival: GameTime?, departure: GameTime?
                if let execution = train.execution, execution.cycle == point.cycle, execution.stop == point.stop,
                   isStopped(train, at: point.station) {
                    arrival = point.calls ? train.times?.arrival : clock.now
                }
                if let old = before?.first(where: { $0.id == train.id }), let execution = old.execution {
                    let fromStop = execution.stop
                    let belongs = execution.cycle == point.cycle && (fromStop == point.stop || (point.calls && fromStop + 1 == point.stop))
                    if belongs {
                        let stretches = routeStretches(of: old).stretches
                        let moved = max(0, routeLength(of: old) - routeLength(of: train))
                        var distance: Int64 = 0
                        for stretch in stretches {
                            for berth in berths(of: point.station, length: train.length) where berth.traversal == stretch.traversal {
                                let reach = distance + berth.offset - stretch.from
                                if berth.offset >= stretch.from, berth.offset <= stretch.to, reach > 0, reach <= moved {
                                    arrival = clock.now
                                    if !(standingPoint(of: train) != nil && isStopped(train, at: point.station)) { departure = clock.now }
                                }
                            }
                            distance += stretch.to - stretch.from
                        }
                    }
                }
                if let found = trains[index].trafficVisits.firstIndex(where: { $0.station == point.station && $0.stop == point.stop && $0.cycle == point.cycle }) {
                    if let departure { trains[index].trafficVisits[found].departure = departure }
                } else if let arrival {
                    trains[index].trafficVisits.append(TrafficVisit(station: point.station, stop: point.stop, cycle: point.cycle, arrival: arrival, departure: departure))
                }
            }
            trains[index].trafficVisits.sort {
                if $0.cycle != $1.cycle { return $0.cycle < $1.cycle }
                if $0.stop != $1.stop { return $0.stop < $1.stop }
                return $0.station < $1.station
            }
            // A plan names only the cycle each service is on (or, ended,
            // last visited), and one worked out earlier in the step the
            // cycle before: older visits are never read again, so a
            // repeating service keeps a bounded history.
            if let latest = trains[index].execution?.cycle ?? trains[index].trafficVisits.last?.cycle {
                trains[index].trafficVisits.removeAll { $0.cycle < latest - 1 }
            }
        }
    }

    mutating func recordTrafficDeparture(_ index: Int) {
        let train = trains[index]
        for i in trains[index].trafficVisits.indices where trains[index].trafficVisits[i].departure == nil {
            let visit = trains[index].trafficVisits[i]
            if let execution = train.execution, visit.cycle == execution.cycle, visit.stop == execution.stop,
               isStopped(train, at: visit.station) {
                trains[index].trafficVisits[i].departure = clock.now
            }
        }
    }
}

/// Decision 691: what lengthening a station's platforms between its
/// turnouts would do (`GameWorld.platformLoopExtensionPreview`).
public struct PlatformLoopExtensionPreview: Hashable, Sendable {
    /// The longer track and what it clears; zero when no turnout moves.
    public let cost: Money
    /// How many of the station's platforms grow: the one asked for and
    /// those beside it.
    public let platforms: Int
    /// Whether a turnout moves out along the line.
    public let movesTurnouts: Bool
}
