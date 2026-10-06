// The passengers of a station (G1a, ARCHITECTURE decision 34): its demand,
// the groups waiting there in the order they came, and the counts that
// account for every passenger released there. Passengers are counted in
// groups, never one object each (ROADMAP Phase 5).

/// Which way along a line a trip goes: `outbound` from the first stop
/// toward the last, `inbound` back toward the first (the reference's
/// direction `1` and `-1`).
public enum LineDirection: String, CaseIterable, Codable, Sendable {
    case outbound
    case inbound
}

/// The line a trip between two stations takes, and which way along it
/// (see ``GameWorld/passengerTrip(from:to:)``).
public struct PassengerTrip: Hashable, Sendable {
    public let line: LineID
    public let direction: LineDirection

    public init(line: LineID, direction: LineDirection) {
        self.line = line
        self.direction = direction
    }
}

/// Passengers waiting together at a station: released there in the same
/// minute, for the same destination, to take the same line the same way.
public struct WaitingGroup: Hashable, Sendable {
    public let line: LineID
    public let direction: LineDirection
    public let destination: StationID
    /// The minute they were released at the station.
    public let since: GameTime
    /// How many, at least 1.
    public let count: Int64
    /// The selected route, including its original station and subsequent
    /// rides. `nil` for a passenger from an older direct-trip save.
    public let journey: PassengerJourney?
    /// Transfer passengers cannot board before finishing their interchange.
    /// `nil` means they were ready when they joined this queue.
    public let readyAt: GameTime?

    public init(line: LineID, direction: LineDirection, destination: StationID, since: GameTime, count: Int64,
                journey: PassengerJourney? = nil, readyAt: GameTime? = nil) {
        self.line = line
        self.direction = direction
        self.destination = destination
        self.since = since
        self.count = count
        self.journey = journey
        self.readyAt = readyAt
    }

    var trip: PassengerTrip {
        PassengerTrip(line: line, direction: direction)
    }
}

/// The part of a trip still to be released for one destination, in
/// 1/3600ths of a passenger (see ``GameWorld/advance(ticks:)``): what the
/// reference keeps as the fraction of its spawn accumulator.
public struct DemandRemainder: Hashable, Sendable {
    public let destination: StationID
    /// In `1..<3600`: a remainder of 0 is not kept.
    public let value: Int64

    public init(destination: StationID, value: Int64) {
        self.destination = destination
        self.value = value
    }
}

/// Where every passenger released at a station has gone: the audit of
/// passenger conservation. `released` always equals `waiting + riding +
/// arrived + overflowed + abandoned`.
public struct PassengerLedger: Hashable, Sendable {
    /// Every passenger ever released at the station.
    public let released: Int64
    /// Those waiting there now.
    public let waiting: Int64
    /// Those on a train now (G1b).
    public let riding: Int64
    /// Those who got off at their destination (G1b).
    public let arrived: Int64
    /// Those who found the station full when released, and left.
    public let overflowed: Int64
    /// Those whose line stopped serving their trip while they waited, and
    /// left; or whose train's service was stopped before it reached their
    /// destination (G1b).
    public let abandoned: Int64
    /// How many times a train that would have taken passengers waiting at
    /// the station left them behind for want of room (G1b). A count of
    /// refusals, not of passengers: one passenger may be refused by several
    /// trains, so it is not part of the conservation.
    public let refused: Int64

    public init(
        released: Int64, waiting: Int64, riding: Int64 = 0, arrived: Int64 = 0,
        overflowed: Int64, abandoned: Int64, refused: Int64 = 0
    ) {
        self.released = released
        self.waiting = waiting
        self.riding = riding
        self.arrived = arrived
        self.overflowed = overflowed
        self.abandoned = abandoned
        self.refused = refused
    }

    public static let empty = PassengerLedger(released: 0, waiting: 0, overflowed: 0, abandoned: 0)
}

/// Everything about the passengers of one station (G1a): its demand, the
/// groups waiting there, the counts of the conservation audit and the
/// remainders of the trips still to be released. A station none of this
/// applies to has no record.
public struct StationPassengers: Hashable, Sendable {
    public let station: StationID
    public internal(set) var demand: StationDemand?
    /// The groups waiting at the station, first come first: in the order
    /// they were released, so `since` never decreases.
    public private(set) var waiting: [WaitingGroup]
    public internal(set) var released: Int64
    public internal(set) var overflowed: Int64
    public internal(set) var abandoned: Int64
    /// Passengers from this station who got off at their destination (G1b).
    public internal(set) var arrived: Int64
    /// Refusals at this station (G1b, see ``PassengerLedger/refused``), up
    /// to ``maximumReleased``.
    public internal(set) var refused: Int64
    /// The remainders of the trips from this station, by ascending
    /// destination.
    public internal(set) var remainders: [DemandRemainder]
    /// How many wait in all: the sum of ``waiting``'s counts, kept with it.
    public private(set) var waitingCount: Int64

    /// Passengers waiting at a station at most: the reference's
    /// `STATION_CAPACITY × 8`. One released when the station is full leaves
    /// at once (see ``PassengerLedger/overflowed``).
    public static let capacity: Int64 = 4_000

    /// The most passengers a save may say were ever released at a station.
    /// A station releases at most a million a day, so play from any count
    /// below it would take millions of years to overflow an `Int64`, and
    /// no count can overflow before then.
    static let maximumReleased: Int64 = 1 << 62

    init(station: StationID) {
        self.station = station
        self.demand = nil
        self.waiting = []
        self.waitingCount = 0
        self.released = 0
        self.overflowed = 0
        self.abandoned = 0
        self.arrived = 0
        self.refused = 0
        self.remainders = []
    }

    /// The station's audit, given how many of its passengers are `riding`
    /// trains (see ``GameWorld/riders``).
    func ledger(waiting: Int64, riding: Int64) -> PassengerLedger {
        PassengerLedger(
            released: released, waiting: waiting, riding: riding, arrived: arrived,
            overflowed: overflowed, abandoned: abandoned, refused: refused
        )
    }

    /// Passengers released here who are neither waiting, arrived,
    /// overflowed nor abandoned: those riding trains.
    var boardedAndRiding: Int64 {
        released - waitingCount - arrived - overflowed - abandoned
    }

    /// Whether the record says nothing: no demand, no passenger ever
    /// released and no remainder. Such a record is not kept.
    var isEmpty: Bool {
        demand == nil && released == 0 && remainders.isEmpty && waiting.isEmpty
    }

    /// Releases `count` passengers for `destination` along `trip` at
    /// minute `now`: as many as the station has room for wait, as one group
    /// at the back of the queue, and the rest leave at once (the
    /// reference's `_metroAdmitDispatchPassengers`).
    mutating func release(_ count: Int64, to destination: StationID, along trip: PassengerTrip, at now: GameTime) {
        let admitted = min(count, max(0, Self.capacity - waitingCount))
        if admitted > 0 {
            waiting.append(WaitingGroup(line: trip.line, direction: trip.direction, destination: destination, since: now, count: admitted))
            waitingCount += admitted
        }
        released += count
        overflowed += count - admitted
    }

    mutating func release(_ count: Int64, along journey: PassengerJourney, at now: GameTime) {
        let admitted = min(count, max(0, Self.capacity - waitingCount))
        if admitted > 0 {
            let leg = journey.leg
            waiting.append(WaitingGroup(line: leg.line, direction: leg.direction,
                destination: leg.to, since: now, count: admitted, journey: journey))
            waitingCount += admitted
        }
        released += count
        overflowed += count - admitted
    }

    /// Admits a group arriving from another service. Its release and final
    /// outcome remain on the original station's ledger.
    mutating func enqueueTransfer(_ count: Int64, along journey: PassengerJourney,
                                   at now: GameTime, readyAt: GameTime) -> Int64 {
        let admitted = min(count, max(0, Self.capacity - waitingCount))
        guard admitted > 0 else { return 0 }
        let leg = journey.leg
        let group = WaitingGroup(line: leg.line, direction: leg.direction, destination: leg.to,
            since: now, count: admitted, journey: journey, readyAt: readyAt)
        let insert = waiting.firstIndex { $0.since > now || $0.since == now && $0.destination > leg.to } ?? waiting.count
        waiting.insert(group, at: insert)
        waitingCount += admitted
        return admitted
    }

    /// Removes groups whose chosen service is no longer valid. The world
    /// credits their original stations after all records have been scanned.
    mutating func abandonGroups(unless isServed: (WaitingGroup) -> Bool) -> [WaitingGroup] {
        let left = waiting.filter { !isServed($0) }
        waiting.removeAll { !isServed($0) }
        waitingCount -= left.reduce(0) { $0 + $1.count }
        return left
    }

    /// Takes `counts[i]` passengers out of the group at index `i` of
    /// ``waiting`` for every entry, as they board a train (G1b). A group
    /// left with none goes; the others keep their order and their minute.
    mutating func board(_ counts: [Int: Int64]) {
        var total: Int64 = 0
        var kept: [WaitingGroup] = []
        for (index, group) in waiting.enumerated() {
            let taken = counts[index] ?? 0
            total += taken
            if taken < group.count {
                kept.append(WaitingGroup(
                    line: group.line, direction: group.direction, destination: group.destination,
                    since: group.since, count: group.count - taken,
                    journey: group.journey, readyAt: group.readyAt
                ))
            }
        }
        waiting = kept
        waitingCount -= total
    }

    /// Adds `count` refusals, stopping at ``maximumReleased``.
    mutating func refuse(_ count: Int64) {
        refused = min(Self.maximumReleased, refused + count)
    }

    /// Replaces the remainders for the destinations of `updates` (by
    /// ascending destination) with theirs; a value of 0 drops one. The
    /// remainders for other destinations stay.
    mutating func updateRemainders(_ updates: [DemandRemainder]) {
        var merged: [DemandRemainder] = []
        var next = 0
        for kept in remainders {
            while next < updates.count, updates[next].destination < kept.destination {
                if updates[next].value != 0 { merged.append(updates[next]) }
                next += 1
            }
            if next < updates.count, updates[next].destination == kept.destination {
                if updates[next].value != 0 { merged.append(updates[next]) }
                next += 1
            } else {
                merged.append(kept)
            }
        }
        for update in updates[next...] where update.value != 0 {
            merged.append(update)
        }
        remainders = merged
    }
}

extension WaitingGroup: Codable {
    private enum CodingKeys: String, CodingKey {
        case line, direction, destination, since, count, journey, readyAt
    }

    /// Decodes a group, rejecting a count below 1. That its trip is one
    /// its station's lines make is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(LineID.self, forKey: .line)
        direction = try container.decode(LineDirection.self, forKey: .direction)
        destination = try container.decode(StationID.self, forKey: .destination)
        since = try container.decode(GameTime.self, forKey: .since)
        count = try container.decode(Int64.self, forKey: .count)
        journey = try container.decodeIfPresent(PassengerJourney.self, forKey: .journey)
        readyAt = try container.decodeIfPresent(GameTime.self, forKey: .readyAt)
        guard count >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .count, in: container, debugDescription: "A waiting group has at least one passenger.")
        }
        if let journey, journey.leg.line != line || journey.leg.direction != direction || journey.leg.to != destination {
            throw DecodingError.dataCorruptedError(forKey: .journey, in: container,
                debugDescription: "A waiting group's current journey leg must match its queue.")
        }
        if let readyAt, readyAt < since || journey == nil {
            throw DecodingError.dataCorruptedError(forKey: .readyAt, in: container,
                debugDescription: "Only a planned transfer may wait until a later time.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(line, forKey: .line)
        try container.encode(direction, forKey: .direction)
        try container.encode(destination, forKey: .destination)
        try container.encode(since, forKey: .since)
        try container.encode(count, forKey: .count)
        if let journey { try container.encode(journey, forKey: .journey) }
        if let readyAt { try container.encode(readyAt, forKey: .readyAt) }
    }
}

extension DemandRemainder: Codable {
    private enum CodingKeys: String, CodingKey {
        case destination, value
    }

    /// Decodes a remainder, rejecting a value outside `1..<3600`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destination = try container.decode(StationID.self, forKey: .destination)
        value = try container.decode(Int64.self, forKey: .value)
        guard (1..<GameWorld.releaseUnit).contains(value) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "A remainder is 1 to 3599 3600ths of a passenger.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(destination, forKey: .destination)
        try container.encode(value, forKey: .value)
    }
}

extension StationPassengers: Codable {
    private enum CodingKeys: String, CodingKey {
        case station, demand, waiting, released, overflowed, abandoned, arrived, refused, remainders
    }

    /// Decodes a station's passengers. A station without demand has no
    /// `"demand"` key (an explicit `null` is rejected), and one with none
    /// arrived or refused (G1b) no `"arrived"` or `"refused"`. Rejects
    /// negative counts, counts that account for more passengers than were
    /// released (waiting + `arrived` + `overflowed` + `abandoned` at most
    /// `released`; the rest ride trains, which the ``GameWorld`` decoder
    /// checks), `refused` above ``maximumReleased``, more waiting
    /// than ``capacity``, groups out of the order they came in, remainders
    /// out of order or twice, and a record with nothing in it (it is never
    /// saved). That the station, lines and destinations exist, and that the
    /// groups' trips and times fit the world, is checked by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let station = try container.decode(StationID.self, forKey: .station)
        let demand = container.contains(.demand) ? try container.decode(StationDemand.self, forKey: .demand) : nil
        let waiting = try container.decode([WaitingGroup].self, forKey: .waiting)
        let released = try container.decode(Int64.self, forKey: .released)
        let overflowed = try container.decode(Int64.self, forKey: .overflowed)
        let abandoned = try container.decode(Int64.self, forKey: .abandoned)
        let arrived = container.contains(.arrived) ? try container.decode(Int64.self, forKey: .arrived) : 0
        let refused = container.contains(.refused) ? try container.decode(Int64.self, forKey: .refused) : 0
        let remainders = try container.decode([DemandRemainder].self, forKey: .remainders)
        func corrupt(_ key: CodingKeys, _ description: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Station \(station.rawValue): \(description)")
        }
        // Every count is checked against a bound before it is added, so no
        // sum below can overflow.
        guard Int64(waiting.count) <= Self.capacity, waiting.allSatisfy({ $0.count <= Self.capacity }) else {
            throw corrupt(.waiting, "more passengers wait than the station holds.")
        }
        let total = waiting.reduce(Int64(0)) { $0 + $1.count }
        guard total <= Self.capacity else { throw corrupt(.waiting, "more passengers wait than the station holds.") }
        // Released minute by minute, one group per destination a minute, by
        // ascending destination.
        guard zip(waiting, waiting.dropFirst()).allSatisfy({ $0.since < $1.since || ($0.since == $1.since && $0.destination < $1.destination) }) else {
            throw corrupt(.waiting, "waiting groups must be in the order they came.")
        }
        guard released >= 0, overflowed >= 0, abandoned >= 0, arrived >= 0, refused >= 0 else {
            throw corrupt(.released, "counts cannot be negative.")
        }
        guard released <= Self.maximumReleased else { throw corrupt(.released, "more passengers released than a station can count.") }
        guard refused <= Self.maximumReleased else { throw corrupt(.refused, "more refusals than a station can count.") }
        // Taken off what was released one at a time, so nothing overflows.
        let waitingFromHere = waiting.reduce(Int64(0)) { partial, group in
            partial + ((group.journey?.origin ?? station) == station ? group.count : 0)
        }
        guard overflowed <= released, abandoned <= released - overflowed,
              arrived <= released - overflowed - abandoned,
              waitingFromHere <= released - overflowed - abandoned - arrived
        else {
            throw corrupt(.released, "more passengers are accounted for than were released.")
        }
        guard zip(remainders, remainders.dropFirst()).allSatisfy({ $0.destination < $1.destination }) else {
            throw corrupt(.remainders, "remainders must be listed once each, by ascending destination.")
        }
        guard demand != nil || released > 0 || !remainders.isEmpty || !waiting.isEmpty else {
            throw corrupt(.station, "a record with nothing in it is not saved.")
        }
        self.station = station
        self.demand = demand
        self.waiting = waiting
        self.waitingCount = total
        self.released = released
        self.overflowed = overflowed
        self.abandoned = abandoned
        self.arrived = arrived
        self.refused = refused
        self.remainders = remainders
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station, forKey: .station)
        if let demand {
            try container.encode(demand, forKey: .demand)
        }
        try container.encode(waiting, forKey: .waiting)
        try container.encode(released, forKey: .released)
        try container.encode(overflowed, forKey: .overflowed)
        try container.encode(abandoned, forKey: .abandoned)
        if arrived != 0 {
            try container.encode(arrived, forKey: .arrived)
        }
        if refused != 0 {
            try container.encode(refused, forKey: .refused)
        }
        try container.encode(remainders, forKey: .remainders)
    }
}
