// Station expansion (decision 506): a station holds 4,000 waiting
// passengers (``StationPassengers/capacity``); the company can pay to
// expand it twice, to 8,000 and then 16,000, each once the station is busy
// enough. The owner, 2026-10-30, on a full station every day: 「要嗎不然每
// 天都一直滿」.
//
// The reference's metro quotas (`hsr.capacity.platform_expanded`,
// `metroQuotaFormatValue`, decision 506's mapping table) sell a station
// more room in steps; it has no ridership threshold, and its prices are its
// own currency's. The levels, prices and thresholds here are this
// project's, measured on the owner's 97.1 save (decision 506, 量到的).

/// How far a station has been expanded (decision 506).
public enum StationExpansion: Int, CaseIterable, Comparable, Codable, Sendable {
    /// The first expansion: a bigger concourse, 8,000 waiting.
    case concourse = 1
    /// The second: more platforms and a hall, 16,000 waiting.
    case hall = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The first expansion, for a station not expanded yet.
    public static let first: StationExpansion = .concourse

    /// The expansion after this one, `nil` for the last.
    public var next: StationExpansion? { Self(rawValue: rawValue + 1) }

    /// How many passengers may wait at a station expanded this far.
    public var capacity: Int64 {
        switch self {
        case .concourse: 8_000
        case .hall: 16_000
        }
    }

    /// What this expansion costs, in cents (of the New Taiwan dollar,
    /// decision 499): kept as a building asset.
    public var price: Money {
        switch self {
        case .concourse: Money(1)
        case .hall: Money(2)
        }
    }

    /// The people a day (got on and off, a change once: the count the
    /// station's shops use, ``GameWorld/stationCommercePeople(of:onDay:)``)
    /// the station must have had yesterday before this expansion opens.
    public var threshold: Int64 {
        switch self {
        case .concourse: 1
        case .hall: 2
        }
    }
}

extension Station {
    /// How many passengers may wait here (decision 506).
    public var capacity: Int64 {
        expansion?.capacity ?? StationPassengers.capacity
    }
}

extension GameWorld {
    // MARK: - Queries

    /// How many passengers may wait at station `id` (decision 506): 4,000,
    /// or its expansion's; 4,000 for an unknown station.
    public func stationCapacity(of id: StationID) -> Int64 {
        station(id: id)?.capacity ?? StationPassengers.capacity
    }

    /// The capacities of the expanded stations, empty when none is: the
    /// release step looks a station up here only when one is.
    var expandedStationCapacities: [StationID: Int64] {
        var capacities: [StationID: Int64] = [:]
        for station in stations {
            if let expansion = station.expansion { capacities[station.id] = expansion.capacity }
        }
        return capacities
    }

    /// The people through station `id` yesterday that an expansion's
    /// threshold is held to (decision 506): the day before today.
    public func stationExpansionPeople(of id: StationID) -> Int64 {
        let today = clock.now.seconds / 86_400
        guard today > 0 else { return 0 }
        return stationCommercePeople(of: id, onDay: today - 1)
    }

    /// The expansion station `id` would get next, `nil` when it has had
    /// both or is not a station that can be expanded.
    public func nextStationExpansion(of id: StationID) -> StationExpansion? {
        guard let station = station(id: id), !station.isDepot else { return nil }
        guard let expansion = station.expansion else { return .first }
        return expansion.next
    }

    // MARK: - Commands

    /// Expands station `id` one step (decision 506), paying its price, kept
    /// as a building asset (30 years). The station must have had the
    /// step's threshold of people yesterday.
    ///
    /// - Throws, in this order: ``GameError/unknownStation(_:)``,
    ///   ``GameError/stationIsDepot(_:)``,
    ///   ``GameError/stationExpansionMaxedOut``,
    ///   ``GameError/stationTooQuietToExpand(needed:)``,
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func expandStation(at id: StationID) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard !stations[index].isDepot else { throw .stationIsDepot(id) }
        let next: StationExpansion
        if let expansion = stations[index].expansion {
            guard let after = expansion.next else { throw .stationExpansionMaxedOut }
            next = after
        } else {
            next = .first
        }
        guard stationExpansionPeople(of: id) >= next.threshold else {
            throw .stationTooQuietToExpand(needed: next.threshold)
        }
        try economy.spend(next.price)
        setStationExpansion(next, at: index)
        acquireAsset(.stationExpansion, owner: id.rawValue, cost: next.price)
    }
}
