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
        guard (1...32).contains(route.legs.count), let last = route.legs.last,
              route.legs.first?.from == origin else { return nil }
        self.init(origin: origin, destination: last.to, legs: route.legs.map(PassengerJourneyLeg.init), current: 0)
    }

    private init(origin: StationID, destination: StationID, legs: [PassengerJourneyLeg], current: Int) {
        self.origin = origin
        self.destination = destination
        self.legs = legs
        self.current = current
    }

    private enum CodingKeys: String, CodingKey { case origin, destination, legs, current }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try box.decode(StationID.self, forKey: .origin)
        let destination = try box.decode(StationID.self, forKey: .destination)
        let legs = try box.decode([PassengerJourneyLeg].self, forKey: .legs)
        let current = try box.decode(Int.self, forKey: .current)
        guard (1...32).contains(legs.count), legs.indices.contains(current),
              legs.first?.from == origin, legs.last?.to == destination,
              legs.allSatisfy({ $0.from != $0.to && ($0.pattern ?? 0) >= 0 }),
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
