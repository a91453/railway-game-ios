// Station commerce (ARCHITECTURE decision 222): the company runs shops in
// a station, in three levels, a convenience store, then an arcade of
// shops, then a mall. They take no land: they are the station's. Each
// midnight they take in from the people who passed through the station
// that day (those who got on or off, a change counted once), the more the
// nearer their level's most, and pay their upkeep.
//
// The reference has no shops a station's riders spend in (its island
// city's shops earn by their staff, its commuter game's are walked into):
// every number below is this project's, calibrated with the balance
// report's worlds (`docs/research/STATION_COMMERCE_2026-10-14.md` §2).

/// A level of a station's shops (decision 222).
public enum StationCommerceLevel: Int, CaseIterable, Comparable, Codable, Sendable {
    case convenienceStore = 1
    case arcade = 2
    case mall = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The level after this one, `nil` for the top.
    public var next: StationCommerceLevel? { Self(rawValue: rawValue + 1) }

    /// What building this level costs, on top of the levels below, in
    /// cents.
    public var price: Money {
        switch self {
        case .convenienceStore: Money(35_000_000)
        case .arcade: Money(315_000_000)
        case .mall: Money(1_250_000_000)
        }
    }

    /// What a person through the station brings in, in cents.
    public var centsPerPerson: Int64 {
        switch self {
        case .convenienceStore: 25
        case .arcade: 30
        case .mall: 45
        }
    }

    /// The people a day at which the shops take half their most: the
    /// takings are `centsPerPerson × P × H ÷ (P + H)`, nearing
    /// `centsPerPerson × H` however many pass.
    public var halfPeople: Int64 {
        switch self {
        case .convenienceStore: 3_000
        case .arcade: 20_000
        case .mall: 90_000
        }
    }

    /// The upkeep a day, in cents.
    public var upkeep: Money {
        switch self {
        case .convenienceStore: Money(6_000)
        case .arcade: Money(30_000)
        case .mall: Money(150_000)
        }
    }

    /// What `people` through the station bring in a day, in whole
    /// dollars (cents).
    public func takings(people: Int64) -> Money {
        let people = max(0, min(people, StationCommerceDay.maximumPeople))
        let customers = people * halfPeople / (people + halfPeople)
        return Money(centsPerPerson * customers / 100 * 100)
    }
}

/// A day of a station's shops (decision 222).
public struct StationCommerceDay: Hashable, Sendable {
    /// The people through the station: got on and off, a change once.
    public let people: Int64
    public let takings: Money
    public let upkeep: Money

    public var net: Money { takings - upkeep }

    /// The most people a day the shops count: twice the most a day's
    /// boardings may hold.
    static let maximumPeople: Int64 = 2 * GameWorld.maximumHourly
}

extension GameWorld {
    // MARK: - Queries

    /// The people through station `id` on day `day` the shops count
    /// (decision 222): those who got on and off, a change at the station
    /// counted once, as the line accounts kept them; without line accounts,
    /// twice the station's trips, each setting out and coming back. None
    /// at a closed station, though its record counts those put off there.
    public func stationCommercePeople(of id: StationID, onDay day: Int64) -> Int64 {
        guard let station = station(id: id), station.operationMode != .closed else { return 0 }
        if lineAccounts != nil {
            return stationFlow(id, onDay: day)?.people ?? 0
        }
        guard let demand = stationDemand(of: id) else { return 0 }
        let trips = scaledTrips(weeklyDemand ? demand.trips(onDay: day) : demand.dailyTrips, at: id)
        return min(2 * max(0, trips), StationCommerceDay.maximumPeople)
    }

    /// What station `id`'s shops at `level` (its own by default) take and
    /// spend on day `day`; nothing for a station without them.
    public func stationCommerceDay(of id: StationID, level: StationCommerceLevel? = nil, onDay day: Int64) -> StationCommerceDay {
        guard let level = level ?? station(id: id)?.commerce else {
            return StationCommerceDay(people: 0, takings: .zero, upkeep: .zero)
        }
        let people = stationCommercePeople(of: id, onDay: day)
        return StationCommerceDay(people: people, takings: level.takings(people: people), upkeep: level.upkeep)
    }

    // MARK: - Commands

    /// Builds a convenience store in station `id` (decision 222), paying
    /// its price, kept as a building asset (30 years).
    ///
    /// - Throws: ``GameError/unknownStation(_:)``,
    ///   ``GameError/stationIsDepot(_:)``,
    ///   ``GameError/stationCommerceMaxedOut`` if it has shops already,
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func buildStationCommerce(at id: StationID) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard !stations[index].isDepot else { throw .stationIsDepot(id) }
        guard stations[index].commerce == nil else { throw .stationCommerceMaxedOut }
        try raiseStationCommerce(at: index, to: .convenienceStore)
    }

    /// Builds station `id`'s shops up a level (decision 222), paying that
    /// level's price, kept as a building asset of its own.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``,
    ///   ``GameError/noStationCommerce(_:)``,
    ///   ``GameError/stationCommerceMaxedOut``,
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func upgradeStationCommerce(at id: StationID) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard let level = stations[index].commerce else { throw .noStationCommerce(id) }
        guard let next = level.next else { throw .stationCommerceMaxedOut }
        try raiseStationCommerce(at: index, to: next)
    }

    private mutating func raiseStationCommerce(at index: Int, to level: StationCommerceLevel) throws(GameError) {
        try economy.spend(level.price)
        setStationCommerce(level, at: index)
        acquireAsset(.stationCommerce, owner: stations[index].id.rawValue, cost: level.price)
    }

    /// Demolishes station `id`'s shops (decision 222): nothing comes back,
    /// their book value is written off and their upkeep stops.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``,
    ///   ``GameError/noStationCommerce(_:)``.
    public mutating func demolishStationCommerce(at id: StationID) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard stations[index].commerce != nil else { throw .noStationCommerce(id) }
        setStationCommerce(nil, at: index)
        disposeAsset(.stationCommerce, owner: id.rawValue)
    }

    // MARK: - Settlement

    /// Settles day `day`'s takings and upkeep of every station's shops as
    /// one ledger row at `time` (decision 222).
    mutating func settleStationCommerce(day: Int64, time: GameTime) {
        var takings = Money.zero, upkeep = Money.zero
        for station in stations {
            guard station.commerce != nil else { continue }
            let result = stationCommerceDay(of: station.id, onDay: day)
            takings = takings + result.takings
            upkeep = upkeep + result.upkeep
        }
        guard takings > .zero || upkeep > .zero else { return }
        write(LedgerEntry(
            kind: .dailyStationCommerce, time: time, amount: takings - upkeep,
            breakdown: [
                LedgerLine(item: .stationCommerceRevenue, amount: takings),
                LedgerLine(item: .stationCommerceUpkeep, amount: .zero - upkeep),
            ]
        ), day: day)
    }
}
