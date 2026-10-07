// Town growth (item 5 of the author's order, Phase 6 groundwork): the
// A-Train loop of a railway that makes the places it serves grow. The
// reference pack names OpenTTD's town and industry systems
// (`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md`, "Town growth /
// industry demand": `src/town_cmd.cpp`, `src/industry_cmd.cpp`) and asks that
// they "consume transport accessibility metrics rather than directly
// controlling train movement"; their source and numbers are not in the pack,
// and `Ci/` grows nothing. So the rule is this project's (gap), built on what
// the game measures:
//
// - service: the trips from the station that reached their destinations
//   yesterday, against the trips it started (its ledger's `arrived`);
// - accessibility: how many stations with demand its passengers could reach
//   over the network (item 1's routes, the release plan's flows from it).
//
// Each midnight a growing station's daily trips rise by up to 1.5 % (1 % for
// a fully served day and 0.1 % for each station reached, up to five), up to
// four times what they were when growth first saw it; a station whose
// passengers reached nothing shrinks 0.2 % a day, never below that start.
// Only a managed company's city grows: in free play the player sets each
// station's ridership. Industries (goods and cargo) are not modelled (gap).

/// The stations a world's towns grow around, and what growth measures them
/// against.
public struct TownGrowth: Hashable, Codable, Sendable {
    /// One station's growth.
    public struct Place: Hashable, Codable, Sendable {
        public let station: StationID
        /// Its daily trips when growth first saw it: it grows to at most
        /// ``TownGrowth/maximumGrowth`` times this, and shrinks no lower.
        public let base: Int64
        /// Its ledger's arrivals at the last midnight.
        public internal(set) var counted: Int64
        /// How much it grew at the last midnight, in thousandths: negative
        /// when it shrank.
        public internal(set) var lastGrowth: Int64
        /// The share of its trips served on the day that ended at the last
        /// midnight, in thousandths (``TownGrowth/serviceShare(served:trips:)``),
        /// and how many stations its passengers could reach that day, at
        /// most ``TownGrowth/reachedStations`` (Phase 6c-2, ARCHITECTURE
        /// decision 75). Measured each midnight where the land grows
        /// (``GameWorld/landDemand``); 0 until the first midnight after
        /// growth first saw the station, and in saves from before them.
        public internal(set) var lastService: Int64
        public internal(set) var lastReached: Int64

        init(station: StationID, base: Int64, counted: Int64) {
            self.station = station
            self.base = base
            self.counted = counted
            lastGrowth = 0
            lastService = 0
            lastReached = 0
        }
    }

    /// By ascending station.
    public internal(set) var places: [Place] = []

    /// How far a station grows: four times its start.
    public static let maximumGrowth: Int64 = 4
    /// The most a fully served day adds, in thousandths: 1 %.
    public static let serviceGrowth: Int64 = 10
    /// What each station reached adds, in thousandths, up to
    /// ``reachedStations`` of them.
    public static let reachGrowth: Int64 = 1
    public static let reachedStations: Int64 = 5
    /// What an unserved day takes, in thousandths.
    public static let decline: Int64 = 2

    public init() {}

    /// The thousandths a station grows by for a day on which `served` of
    /// its `trips` reached their destinations and its passengers could
    /// reach `reached` stations: negative when nothing was served.
    public static func growth(served: Int64, trips: Int64, reached: Int) -> Int64 {
        guard served > 0 else { return -decline }
        return serviceShare(served: served, trips: trips) * serviceGrowth / 1_000 + reachedCount(reached) * reachGrowth
    }

    /// The share of a day's `trips` that `served` is, in thousandths: 0 when
    /// nothing was served, 1,000 once `served` reaches `trips` (which keeps
    /// a large `served` from a save from overflowing), else rounded down.
    public static func serviceShare(served: Int64, trips: Int64) -> Int64 {
        guard served > 0 else { return 0 }
        return served >= trips ? 1_000 : served * 1_000 / max(1, trips)
    }

    /// The stations reached that count: `reached`, 0 to ``reachedStations``.
    public static func reachedCount(_ reached: Int) -> Int64 {
        max(0, min(Int64(reached), reachedStations))
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns town growth on or off (item 5). Turning it off keeps every
    /// station's ridership as it has grown.
    public mutating func setTownGrowth(_ enabled: Bool) {
        guard enabled != (townGrowth != nil) else { return }
        townGrowth = enabled ? TownGrowth() : nil
    }

    // MARK: - Queries

    /// How station `id` has grown: its start and its last day's growth in
    /// thousandths, or `nil` if growth has not seen it.
    public func townGrowth(of id: StationID) -> TownGrowth.Place? {
        townGrowth?.places.first { $0.station == id }
    }

    // MARK: - Days

    /// How many destinations each origin of `release`'s plan sends
    /// passengers to: the stations its passengers can reach.
    static func reachedStations(_ release: PassengerRelease) -> [StationID: Int] {
        var reached: [StationID: Int] = [:]
        for flow in release.plan.flows {
            reached[flow.origin, default: 0] += 1
        }
        return reached
    }

    /// Midnight's growth, from the day that ended: `reached` is how many
    /// stations each origin's passengers could reach in that day's plan.
    mutating func growTowns(reached: [StationID: Int]) {
        // Phase 6b: with demand from land, the land grows instead.
        guard !landDemand else { return growLand(reached: reached) }
        guard var growth = townGrowth, accounts.mode == .management else { return }
        var places: [TownGrowth.Place] = []
        for index in passengers.indices {
            let record = passengers[index]
            guard let demand = record.demand, demand.dailyTrips > 0 else { continue }
            guard var place = growth.places.first(where: { $0.station == record.station }) else {
                places.append(TownGrowth.Place(station: record.station, base: demand.dailyTrips, counted: record.arrived))
                continue
            }
            let served = record.arrived - place.counted
            place.counted = record.arrived
            let rate = TownGrowth.growth(served: served, trips: demand.dailyTrips, reached: reached[record.station] ?? 0)
            let limit = min(StationDemand.maximumDailyTrips, place.base * TownGrowth.maximumGrowth)
            var trips = demand.dailyTrips + (demand.dailyTrips * rate + (rate >= 0 ? 500 : -500)) / 1_000
            if rate > 0, trips == demand.dailyTrips { trips += 1 }
            trips = max(place.base, min(limit, trips))
            place.lastGrowth = (trips - demand.dailyTrips) * 1_000 / max(1, demand.dailyTrips)
            if trips != demand.dailyTrips {
                passengers[index].demand = StationDemand(kind: demand.kind, dailyTrips: trips)
                passengerPlan = PassengerPlanCache()
            }
            places.append(place)
        }
        growth.places = places
        townGrowth = growth
    }

    // MARK: - Validation

    /// Why the growth breaks a rule, or `nil`: places once each, by
    /// ascending existing station, with counts in range.
    func townGrowthProblem() -> String? {
        guard let growth = townGrowth else { return nil }
        guard zip(growth.places, growth.places.dropFirst()).allSatisfy({ $0.station < $1.station }) else {
            return "Town growth must list each station once, by ascending station."
        }
        for place in growth.places {
            guard station(id: place.station) != nil, (1...StationDemand.maximumDailyTrips).contains(place.base),
                  place.counted >= 0, (-1_000...1_000).contains(place.lastGrowth),
                  (0...1_000).contains(place.lastService), (0...TownGrowth.reachedStations).contains(place.lastReached)
            else { return "A station's town growth is out of range." }
        }
        return nil
    }
}

// MARK: - Codable

extension TownGrowth.Place {
    private enum CodingKeys: String, CodingKey {
        case station, base, counted, lastGrowth, lastService, lastReached
    }

    /// Decodes a place; a save from before Phase 6c-2 has no
    /// `"lastService"` or `"lastReached"`, which read as 0 (an explicit
    /// `null` is refused).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        station = try container.decode(StationID.self, forKey: .station)
        base = try container.decode(Int64.self, forKey: .base)
        counted = try container.decode(Int64.self, forKey: .counted)
        lastGrowth = try container.decode(Int64.self, forKey: .lastGrowth)
        lastService = container.contains(.lastService) ? try container.decode(Int64.self, forKey: .lastService) : 0
        lastReached = container.contains(.lastReached) ? try container.decode(Int64.self, forKey: .lastReached) : 0
    }

    /// Encodes a place, leaving out `"lastService"` and `"lastReached"`
    /// while they are 0, so worlds without them save as before.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station, forKey: .station)
        try container.encode(base, forKey: .base)
        try container.encode(counted, forKey: .counted)
        try container.encode(lastGrowth, forKey: .lastGrowth)
        if lastService != 0 {
            try container.encode(lastService, forKey: .lastService)
        }
        if lastReached != 0 {
            try container.encode(lastReached, forKey: .lastReached)
        }
    }
}
