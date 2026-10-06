// The passenger's durable choice of services. Running times and waits belong
// to the derived route query; only the calls needed to finish the trip are
// stored with a passenger group.

public struct PassengerJourneyLeg: Hashable, Codable, Sendable {
    public let line: LineID
    public let pattern: Int?
    public let direction: LineDirection
    public let from: StationID
    public let to: StationID

    public init(_ leg: PassengerRouteLeg) {
        line = leg.line
        pattern = leg.pattern
        direction = leg.direction
        from = leg.from
        to = leg.to
    }

    private init(_ leg: PassengerJourneyLeg, pattern: Int) {
        line = leg.line
        self.pattern = pattern
        direction = leg.direction
        from = leg.from
        to = leg.to
    }

    func reindexed(afterRemoving pattern: Int) -> PassengerJourneyLeg {
        guard let previous = self.pattern, previous > pattern else { return self }
        return PassengerJourneyLeg(self, pattern: previous - 1)
    }
}

/// A chosen route and the leg a waiting or riding group is completing.
/// Its origin stays fixed so transfer passengers remain in that station's
/// conservation ledger.
public struct PassengerJourney: Hashable, Codable, Sendable {
    public let origin: StationID
    public let destination: StationID
    public let legs: [PassengerJourneyLeg]
    public let current: Int

    public var leg: PassengerJourneyLeg { legs[current] }
    public var next: PassengerJourney? {
        guard current + 1 < legs.count else { return nil }
        return PassengerJourney(origin: origin, destination: destination, legs: legs, current: current + 1)
    }

    public init?(origin: StationID, route: PassengerRoute) {
        guard (1...32).contains(route.legs.count), let last = route.legs.last, origin != last.to,
              route.legs.first?.from == origin,
              route.legs.allSatisfy({ $0.from != $0.to && ($0.pattern == nil || (0..<Int.max).contains($0.pattern!)) }),
              zip(route.legs, route.legs.dropFirst()).allSatisfy({ $0.to == $1.from }) else { return nil }
        self.init(origin: origin, destination: last.to, legs: route.legs.map(PassengerJourneyLeg.init), current: 0)
    }

    private init(origin: StationID, destination: StationID, legs: [PassengerJourneyLeg], current: Int) {
        self.origin = origin
        self.destination = destination
        self.legs = legs
        self.current = current
    }

    /// Completed legs are history. A rider may finish the removed service's
    /// current leg using its unchanged timetable; a removed future ride or
    /// a waiting group's removed ride invalidates the remaining journey.
    func reindexed(on line: LineID, removing pattern: Int, riding: Bool) -> PassengerJourney? {
        let pending = riding ? current + 1 : current
        guard !legs.dropFirst(pending).contains(where: { $0.line == line && $0.pattern == pattern }) else { return nil }
        let updated = legs.enumerated().map { index, leg in
            index >= current && leg.line == line ? leg.reindexed(afterRemoving: pattern) : leg
        }
        return PassengerJourney(origin: origin, destination: destination, legs: updated, current: current)
    }

    private enum CodingKeys: String, CodingKey { case origin, destination, legs, current }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try box.decode(StationID.self, forKey: .origin)
        let destination = try box.decode(StationID.self, forKey: .destination)
        let legs = try box.decode([PassengerJourneyLeg].self, forKey: .legs)
        let current = try box.decode(Int.self, forKey: .current)
        guard (1...32).contains(legs.count), legs.indices.contains(current),
              origin != destination,
              legs.first?.from == origin, legs.last?.to == destination,
              legs.allSatisfy({ $0.from != $0.to && ($0.pattern == nil || (0..<Int.max).contains($0.pattern!)) }),
              zip(legs, legs.dropFirst()).allSatisfy({ $0.to == $1.from })
        else {
            throw DecodingError.dataCorruptedError(forKey: .legs, in: box,
                debugDescription: "A passenger journey has one to 32 connected service legs and a valid current leg.")
        }
        self.init(origin: origin, destination: destination, legs: legs, current: current)
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(origin, forKey: .origin)
        try box.encode(destination, forKey: .destination)
        try box.encode(legs, forKey: .legs)
        try box.encode(current, forKey: .current)
    }
}

/// Direct is the behavior of saves written before network passenger routing.
/// Network games assign a complete journey when passengers are released.
public enum PassengerRoutingMode: String, Codable, Sendable {
    case direct
    case network
}

/// Fractional route shares carried between minute releases of one OD pair.
/// Keeping this in the save makes a batch split equivalent to minute steps.
struct PassengerRouteBalance: Hashable, Codable, Sendable {
    let origin: StationID
    let destination: StationID
    let journeys: [PassengerJourney]
    let weights: [Int64]
    var balances: [Int64]

    /// Smooth weighted round robin. Ties go to the earlier route, and the
    /// credit survives saving so release boundaries cannot change the split.
    mutating func allocate(_ count: Int64) -> [Int64] {
        let denominator = weights.reduce(0, +)
        var shares = Array(repeating: Int64(0), count: weights.count)
        for _ in 0..<count {
            for choice in weights.indices { balances[choice] += weights[choice] }
            let selected = weights.indices.max { lhs, rhs in
                balances[lhs] != balances[rhs] ? balances[lhs] < balances[rhs] : lhs > rhs
            }!
            shares[selected] += 1
            balances[selected] -= denominator
        }
        return shares
    }
}
