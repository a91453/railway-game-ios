/// Where a ``GameWorld`` keeps its state (decision 590, step 2): on the
/// heap, shared by copies of the world until one of them is changed.
///
/// A world was a struct of some 2 KB; every copy of it (the trial copies
/// that price a command before it is taken, the copies a command makes to
/// stay failure atomic) took that much of the stack, and a function with
/// dozens of them took tens of KB of stack, enough, stacked under the
/// screen's update on the main thread, to run out of it (112.1). Now a
/// world is one reference, and the state is copied, whole, only when a
/// world shared with another copy is changed (``GameWorld``'s
/// `uniqueState`), as Swift's own arrays are. Nothing a world says or
/// saves changes: its fields keep their names, access and order, it still
/// compares by content, and the caches that are not game state are copied
/// with it as they were.
final class GameWorldStorage: @unchecked Sendable {
    // `@unchecked`: the state is changed only through a world that holds
    // the one reference to it (`GameWorld.uniqueState`); a shared storage
    // is only read.

    /// The state, in memory of its own rather than a stored property of
    /// the class, so reading and changing a field takes no dynamic
    /// exclusivity check (a class's stored properties take one at every
    /// access). Its accesses are checked statically instead, by the
    /// world's own exclusivity: a world's fields are read (`_read`) or
    /// changed (`_modify`) only while the world itself is, the world
    /// changes it only after `uniqueState` has made this storage its own,
    /// and a storage shared by several worlds is only read.
    let state: UnsafeMutablePointer<GameWorldState>

    init(_ state: GameWorldState = GameWorldState()) {
        self.state = .allocate(capacity: 1)
        self.state.initialize(to: state)
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
    }
}

/// The stored state of a ``GameWorld`` (decision 590, step 2): every
/// field the world keeps, held on the heap by ``GameWorldStorage`` so a
/// world is one reference and copying it costs nothing until one of the
/// copies is changed.
///
/// Every field has a default, so ``GameWorld`` can make its storage before
/// its initializers set the fields. The compiler therefore no longer checks
/// that an initializer sets each of them, as it did while they were the
/// struct's own (`bounds`, `stations`, `clock`, `economy`, `accounts`,
/// `land`, the next IDs and the rest had no default): a new initializer
/// that forgets one gets the default here (`.standard`, empty, 1) without
/// a word. `init(bounds:economy:clock:)` and `init(from:madeBeforeSpacing:)`
/// set every field that had none.
struct GameWorldState: Equatable, Sendable {
    var bounds: WorldBounds = .standard
    var stations: [Station] = []
    var trains: [Train] = []
    var lines: [ServiceLine] = []
    var serviceDay: ServiceDay = .standard
    var clock: GameClock = GameClock()
    var economy: GameEconomy = GameEconomy(balance: .zero)
    var isTrafficControlEnabled: Bool = false
    var passengers: [StationPassengers] = []
    var riders: [TrainRiders] = []
    var passengerRoutingMode: PassengerRoutingMode = .direct
    var weeklyDemand: Bool = false
    var tidalDemand: Bool = false
    var modeShift: ModeShift? = nil
    var demandEvents: DemandEventSchedule? = nil
    var disruptions: Disruptions? = nil
    var townGrowth: TownGrowth? = nil
    var passengerRouteBalances: [PassengerRouteBalance] = []
    var accounts: CompanyAccounts = CompanyAccounts()
    var geoAnchor: GeoAnchor? = nil
    var land: Land = Land()
    var landBlocks: [LandBlock]? = nil
    var landDemand: Bool = false
    var distanceDemand: Bool = false
    var doorCrowding: Bool = false
    var keepLeft: Bool = false
    var realisticOperation: Bool = false
    var blockSections: Bool = false
    var curveSpeedLimits: Bool = false
    var realCarLengths: Bool = false
    var spacingAllowances: [TrainID: SpacingAllowance] = [:]
    var flexDispatch: Bool = false
    var rollingStockEconomics: Bool = false
    var lineAccounts: LineAccounts? = nil
    var tripLog: [TrainTrip] = []
    var tourism: Tourism? = nil
    var cityRequests: CityRequests? = nil
    var outsideConnections: Bool = false
    var realTransfers: Bool = false
    var acquisitions: [LineAcquisition] = []
    var leftTrack: [LeftTrack] = []
    var roads: RoadGrid? = nil
    var busRoutes: [BusRoute] = []
    var nextBusRouteID: Int = 1
    var cableways: [Cableway] = []
    var nextCablewayID: Int = 1
    var ferryRoutes: [FerryRoute] = []
    var nextFerryRouteID: Int = 1
    var cityDemand: CityDemand? = nil
    var freight: FreightState? = nil
    var cityFootprints: Bool = false
    var areaBuyOut: Bool = false
    var cityBuildings: Bool = false
    var buildings: CityBuildings = CityBuildings()
    var transferGroups: [TransferGroup] = []
    var placedBuildings: [PlacedBuilding] = []
    var zones: Zoning = Zoning()
    var terrain: Terrain = Terrain()
    var ground: Ground = Ground()
    var scenario: ScenarioState? = nil
    var mapExpansion: MapExpansion? = nil
    var passengerPlan: GameWorld.PassengerPlanCache = GameWorld.PassengerPlanCache()
    var passengerRouteMemo: PassengerRouteMemo = PassengerRouteMemo()
    var routeMemo: GameWorld.RouteMemo = GameWorld.RouteMemo()
    var trackEditDepth: Int = 0
    var nextStationID: Int = 1
    var nextTrainID: Int = 1
    var nextLineID: Int = 1
    var nextTransferGroupID: Int = 1
    var nextPlacedBuildingID: Int = 1
}
