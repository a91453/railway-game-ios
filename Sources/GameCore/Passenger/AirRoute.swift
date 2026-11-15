// Decision 758: air routes the company buys.
//
// A new direction (the owner, 2026-11-15: 「直接給航線讓玩家收購」): the
// company does not start an airline or build an airport (decision 695
// keeps airports the city's), it buys a real route an airport's flights
// already fly, one of its destinations (decision 700), at home or abroad,
// and runs it as a ferry route (decision 585) is run: a day's plan, not a
// flight moving tick by tick. The route keeps its real day's flights
// (``AirRoute/realDepartures``, from the destination's flights of a year);
// the player sets only how many of them fly (``AirRouteFrequency``: half,
// as real, half as many again) and how big the aircraft are
// (``AircraftSize``). Its aircraft are the fewest that keep its
// departures, bought with it.
//
// Its passengers are those the airport's day gives its destination
// (``AirportDeparture/passengers``, both ways, after the weekday, the
// holiday and the railway's draw): the route takes them, as many as its
// seats hold. The airport's own figures do not change, so its rail riders
// do not either: they were already the flights' passengers, and the
// route's flights leave in the hours the airport's flights leave in
// (``GameWorld/airRouteDepartureMinutes(_:)``). A typhoon over either end
// that the map holds keeps every flight on the ground; the aircraft cost
// their upkeep all the same.
//
// Each passenger pays the route's fare, by its distance; each flight costs
// its kilometres and one landing fee, paid to the airport (which the
// company never owns); each aircraft its upkeep each day. All on a ledger
// row of its own, ``LedgerEntry/Kind/dailyAirRoutes``.
//
// The rules of the owner's earlier web game (`Ci/reference_snapshot/lib/`
// `aviation_*`): an aircraft turns round in 45 minutes (`aviation_operations`,
// 2,700 s), a seat's fare grows with the distance flown above a floor
// (`aviation_economy_curves`), and the seats of the three larger sizes are
// those of its ATR 72-600 (70), A320-200 (186) and A330-300 (440). The
// money is this project's own: decisions 758 and 762 list every value.

/// An air route's number, handed out in order and never used again.
public struct AirRouteID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: AirRouteID, rhs: AirRouteID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How big an air route's aircraft are (decision 758; decisions 698 and
/// 701 name no maker or model).
public enum AircraftSize: String, CaseIterable, Hashable, Codable, Sendable {
    /// Nineteen seats, the islands' small propeller aircraft.
    case commuter
    /// Seventy seats, a regional turboprop.
    case regional
    /// A narrow-body jet.
    case narrowBody
    /// A wide-body jet.
    case wideBody

    /// The seats it holds one way.
    public var seats: Int64 {
        switch self {
        case .commuter: 19
        case .regional: 70
        case .narrowBody: 186
        case .wideBody: 440
        }
    }

    /// Its speed in the air, kilometres an hour.
    public var kilometresPerHour: Int64 {
        switch self {
        case .commuter: 330
        case .regional: 510
        case .narrowBody: 830
        case .wideBody: 870
        }
    }

    /// What one costs: NT$4 million, NT$15 million, NT$60 million and
    /// NT$150 million, about a fiftieth of a real one's, as the game's bus
    /// is of a real bus.
    public var price: Money {
        switch self {
        case .commuter: Money(400_000_000)
        case .regional: Money(1_500_000_000)
        case .narrowBody: Money(6_000_000_000)
        case .wideBody: Money(15_000_000_000)
        }
    }

    /// What one costs a day whether it flies or not: crew, insurance,
    /// upkeep (decision 762: the nineteen-seater's NT$10,000).
    public var dailyUpkeep: Money {
        switch self {
        case .commuter: Money(1_000_000)
        case .regional: Money(6_000_000)
        case .narrowBody: Money(20_000_000)
        case .wideBody: Money(50_000_000)
        }
    }

    /// What it costs for each kilometre it flies: fuel and wear. A seat's
    /// kilometre costs less the bigger the aircraft (decision 762): some
    /// NT$5.3, NT$5.0, NT$3.2 and NT$2.7.
    public var costPerKilometre: Money {
        switch self {
        case .commuter: Money(10_000)
        case .regional: Money(35_000)
        case .narrowBody: Money(60_000)
        case .wideBody: Money(120_000)
        }
    }

    /// What each landing pays the airport, by the aircraft's weight.
    public var landingFee: Money {
        switch self {
        case .commuter: Money(200_000)
        case .regional: Money(600_000)
        case .narrowBody: Money(1_500_000)
        case .wideBody: Money(4_000_000)
        }
    }
}

/// How many of a route's real flights fly (decision 758).
public enum AirRouteFrequency: String, CaseIterable, Hashable, Codable, Sendable {
    /// Half of them, rounded up.
    case reduced
    /// As many as fly it in real life.
    case real
    /// Half as many again, rounded up.
    case extra

    /// The departures each way of a day whose real ones are `real`.
    public func departures(real: Int64) -> Int64 {
        switch self {
        case .reduced: (real + 1) / 2
        case .real: real
        case .extra: (real * 3 + 1) / 2
        }
    }

    /// The thousandths of the destination's passengers who still fly the
    /// route: with half the flights some go another way. More flights draw
    /// no one more: the airport's passengers are its real ones.
    public var passengerShare: Int64 {
        switch self {
        case .reduced: 800
        case .real, .extra: 1_000
        }
    }
}

/// One day of an air route's takings (decision 758).
public struct AirRouteDay: Hashable, Codable, Sendable {
    public let day: Int64
    /// The passengers it carried, both ways.
    public let passengers: Int64
    public let fares: Money
    /// Its aircraft's upkeep and kilometres.
    public let running: Money
    /// The landings paid to the airports.
    public let landingFees: Money
    /// Whether no aircraft flew that day (a typhoon).
    public let closed: Bool

    public init(day: Int64, passengers: Int64, fares: Money, running: Money, landingFees: Money, closed: Bool) {
        self.day = day
        self.passengers = passengers
        self.fares = fares
        self.running = running
        self.landingFees = landingFees
        self.closed = closed
    }
}

/// An air route the company bought (decision 758).
public struct AirRoute: Hashable, Sendable {
    public let id: AirRouteID
    /// The airport of the map it flies from (``Airport/id``).
    public let airport: Int
    /// The destination of that airport it flies to
    /// (``AirDestination/name``).
    public let destination: String
    /// The airport of the map the destination is, when the map holds it;
    /// `nil` for a place outside the map.
    public let farAirport: Int?
    /// The flight's length.
    public let metres: Int64
    /// The departures each way of a real day, as the destination's flights
    /// of a year said when it was bought.
    public let realDepartures: Int64
    public internal(set) var frequency: AirRouteFrequency
    public internal(set) var size: AircraftSize
    /// Its aircraft: the fewest that keep its departures.
    public internal(set) var aircraft: Int
    /// The game day it was bought, and what its passengers cost.
    public let day: Int64
    public let value: Money
    /// The last ``keptDays`` days, oldest first.
    public internal(set) var days: [AirRouteDay] = []

    /// The most routes a company buys.
    public static let maximumRoutes = 32
    /// The longest flight: 5,000 km, Singapore from Taipei is some 3,200.
    public static let maximumMetres: Int64 = 5_000_000
    /// The most departures each way a day.
    public static let maximumDepartures: Int64 = 200
    /// The most aircraft a route keeps.
    public static let maximumAircraft = 60
    /// The minutes on the ground at each end: the old game's 2,700 s.
    public static let turnaroundMinutes: Int64 = 45
    /// The minutes of each flight spent taxiing, climbing out and coming
    /// in, on top of its kilometres at speed.
    public static let groundMinutes: Int64 = 30
    /// A passenger's fare: NT$1,200 and NT$6 a kilometre, rounded to the
    /// dollar: Songshan to Penghu's 140 km some NT$2,040, Taoyuan to Hong
    /// Kong's 810 some NT$6,060.
    public static let baseFare = Money(120_000)
    public static let fareCentsPerKilometre: Int64 = 600
    /// What a passenger a day of the route costs when it is bought: this
    /// many days of the route's fare (decision 762), so a long route's
    /// passengers cost more than a short one's, as they bring more.
    public static let valueDaysOfFare: Int64 = 65
    /// The days of takings kept.
    public static let keptDays = 30

    public init(id: AirRouteID, airport: Int, destination: String, farAirport: Int?, metres: Int64, realDepartures: Int64,
                frequency: AirRouteFrequency, size: AircraftSize, aircraft: Int, day: Int64, value: Money) {
        self.id = id
        self.airport = airport
        self.destination = destination
        self.farAirport = farAirport
        self.metres = metres
        self.realDepartures = realDepartures
        self.frequency = frequency
        self.size = size
        self.aircraft = aircraft
        self.day = day
        self.value = value
    }

    /// The departures each way a day.
    public var departures: Int64 {
        frequency.departures(real: realDepartures)
    }

    /// The minutes from leaving the stand to reaching the other's: its
    /// kilometres at its aircraft's speed, rounded up, and
    /// ``groundMinutes``.
    public var flightMinutes: Int64 {
        Self.flightMinutes(metres: metres, size: size)
    }

    static func flightMinutes(metres: Int64, size: AircraftSize) -> Int64 {
        let perHour = size.kilometresPerHour * 1_000
        return (metres * 60 + perHour - 1) / perHour + groundMinutes
    }

    /// A passenger's fare one way.
    public var fare: Money {
        Self.fare(metres: metres)
    }

    /// The fare of a flight of `metres`.
    public static func fare(metres: Int64) -> Money {
        Money(baseFare.amount + (metres * fareCentsPerKilometre / 100 + 500) / 1_000 * 100)
    }

    /// The seats a day, both ways.
    public var dailySeats: Int64 {
        2 * departures * size.seats
    }

    /// What one flight costs for its kilometres, rounded half up to the
    /// cent.
    public var flightCost: Money {
        Money((metres * size.costPerKilometre.amount + 500) / 1_000)
    }

    /// The fewest aircraft of `size` that fly `departures` each way of
    /// `metres` in a day of `minutes`: each goes there and back, turning
    /// round at both ends, rounded up; one at least.
    static func aircraftNeeded(departures: Int64, metres: Int64, size: AircraftSize, minutes: Int64) -> Int64 {
        let round = 2 * (flightMinutes(metres: metres, size: size) + turnaroundMinutes)
        let day = max(round, minutes)
        return max(1, (departures * round + day - 1) / day)
    }

    var isValid: Bool {
        id.rawValue >= 1 && (1...AirportRules.maximumAirports).contains(airport) && !destination.isEmpty
            && farAirport.map { (1...AirportRules.maximumAirports).contains($0) && $0 != airport } ?? true
            && (1...Self.maximumMetres).contains(metres) && (1...Self.maximumDepartures).contains(realDepartures)
            && (1...Self.maximumAircraft).contains(aircraft) && day >= 0 && value >= .zero
            && days.count <= Self.keptDays
            && days.allSatisfy { $0.passengers >= 0 && $0.fares >= .zero && $0.running >= .zero && $0.landingFees >= .zero }
            && zip(days, days.dropFirst()).allSatisfy { $0.day < $1.day }
    }
}

/// What buying an air route would cost and run (decision 758,
/// ``GameWorld/airRouteOffer(from:to:farAirport:metres:size:frequency:)``).
public struct AirRouteOffer: Hashable, Sendable {
    /// The route as it would be bought, numbered as the next.
    public let route: AirRoute
    /// Its aircraft's price and its passengers' value; the sum is paid.
    public let aircraftPrice: Money
    public let value: Money
    /// The destination's passengers of an average day, both ways.
    public let dailyPassengers: Int64

    public var price: Money { aircraftPrice + value }
}

// MARK: - Codable

extension AirRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, airport, destination, farAirport, metres, realDepartures, frequency, size, aircraft, day, value, days
    }

    /// The route and its takings; refused when malformed. The world checks
    /// that no two are the same route.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AirRouteID.self, forKey: .id)
        airport = try container.decode(Int.self, forKey: .airport)
        destination = try container.decode(String.self, forKey: .destination)
        farAirport = try container.decodeIfPresent(Int.self, forKey: .farAirport)
        metres = try container.decode(Int64.self, forKey: .metres)
        realDepartures = try container.decode(Int64.self, forKey: .realDepartures)
        frequency = try container.decode(AirRouteFrequency.self, forKey: .frequency)
        size = try container.decode(AircraftSize.self, forKey: .size)
        aircraft = try container.decode(Int.self, forKey: .aircraft)
        day = try container.decode(Int64.self, forKey: .day)
        value = try container.decode(Money.self, forKey: .value)
        days = try container.decodeIfPresent([AirRouteDay].self, forKey: .days) ?? []
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container,
                debugDescription: "An air route flies from an airport to a named destination, 1 to \(Self.maximumMetres) m, with 1 to \(Self.maximumDepartures) real departures and 1 to \(Self.maximumAircraft) aircraft."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(airport, forKey: .airport)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(farAirport, forKey: .farAirport)
        try container.encode(metres, forKey: .metres)
        try container.encode(realDepartures, forKey: .realDepartures)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(size, forKey: .size)
        try container.encode(aircraft, forKey: .aircraft)
        try container.encode(day, forKey: .day)
        try container.encode(value, forKey: .value)
        if !days.isEmpty { try container.encode(days, forKey: .days) }
    }
}

// MARK: - Commands

extension GameWorld {
    /// What buying the route from airport `airport` to its destination
    /// named `destination` would cost and run, without buying it. With
    /// `farAirport` (an airport of the map that is the destination) the
    /// flight is the straight line between the terminals unless `metres`
    /// says otherwise; a destination outside the map needs `metres`. The
    /// real departures each way are the destination's flights of a year
    /// over 730, rounded half up, one at least; the aircraft the fewest
    /// that fly them in the airport's open hours; the passengers' value
    /// ``AirRoute/valueDaysOfFare`` days of its fare for each of an average day.
    ///
    /// - Throws, checked in this order: ``GameError/idsExhausted``;
    ///   ``GameError/invalidAirRoute`` for an airport the map has not, a
    ///   destination it does not list by that name, a far airport the map
    ///   has not or the same, no length for a place outside the map, a
    ///   length not 1 to ``AirRoute/maximumMetres`` m, or more aircraft
    ///   than ``AirRoute/maximumAircraft``;
    ///   ``GameError/airRouteAlreadyBought`` when the company has it (or,
    ///   between two airports of the map, the route the other way), or
    ///   ``AirRoute/maximumRoutes``.
    public func airRouteOffer(from airport: Int, to destination: String, farAirport: Int? = nil, metres: Int64? = nil,
                              size: AircraftSize, frequency: AirRouteFrequency = .real) throws(GameError) -> AirRouteOffer {
        let (id, _) = try Self.allocateID(from: nextAirRouteID)
        guard let origin = airports.first(where: { $0.id == airport }),
              let place = origin.destinations.first(where: { !$0.isRest && $0.name == destination })
        else { throw .invalidAirRoute }
        var length = metres
        if let farAirport {
            guard farAirport != airport, let far = airports.first(where: { $0.id == farAirport }) else { throw .invalidAirRoute }
            if length == nil {
                let units = FixedPoint.roundedSquareRoot(Self.squaredDistance(origin.point, far.point))
                length = max(1, (units + WorldCoordinate.unitsPerMetre / 2) / WorldCoordinate.unitsPerMetre)
            }
        }
        guard let length, (1...AirRoute.maximumMetres).contains(length) else { throw .invalidAirRoute }
        let real = min(AirRoute.maximumDepartures, max(1, (place.yearlyFlights + 365) / 730))
        let departures = frequency.departures(real: real)
        let needed = AirRoute.aircraftNeeded(departures: departures, metres: length, size: size,
                                             minutes: Int64(origin.lastHour - origin.firstHour) * 60)
        guard needed <= Int64(AirRoute.maximumAircraft) else { throw .invalidAirRoute }
        if airRoutes.count >= AirRoute.maximumRoutes || airRoutes.contains(where: { bought in
            (bought.airport == airport && bought.destination == destination)
                || (farAirport != nil && bought.airport == farAirport && bought.farAirport == airport)
        }) { throw .airRouteAlreadyBought }
        let daily = place.yearlyPassengers / 365
        let value = Money(daily * AirRoute.valueDaysOfFare * AirRoute.fare(metres: length).amount)
        let route = AirRoute(id: AirRouteID(rawValue: id), airport: airport, destination: destination, farAirport: farAirport,
                             metres: length, realDepartures: real, frequency: frequency, size: size, aircraft: Int(needed),
                             day: dayIndex(of: clock.now), value: value)
        return AirRouteOffer(route: route, aircraftPrice: Money(size.price.amount * needed), value: value, dailyPassengers: daily)
    }

    /// Buys the route ``airRouteOffer(from:to:farAirport:metres:size:frequency:)``
    /// describes (decision 758), paying its price.
    ///
    /// - Throws: what the offer throws;
    ///   ``GameError/insufficientFunds(required:available:)``. The world is
    ///   then unchanged.
    @discardableResult
    public mutating func buyAirRoute(from airport: Int, to destination: String, farAirport: Int? = nil, metres: Int64? = nil,
                                     size: AircraftSize, frequency: AirRouteFrequency = .real) throws(GameError) -> AirRoute {
        let offer = try airRouteOffer(from: airport, to: destination, farAirport: farAirport, metres: metres, size: size, frequency: frequency)
        try spendOnAirRoutes(offer.price)
        airRoutes.append(offer.route)
        nextAirRouteID = offer.route.id.rawValue + 1
        return offer.route
    }

    /// Flies `frequency` of route `id`'s real flights, buying the aircraft
    /// more it then needs at ``AircraftSize/price``; those it no longer
    /// needs are sold for nothing, as a ferry's boats (decision 585).
    ///
    /// - Throws: ``GameError/unknownAirRoute(_:)``;
    ///   ``GameError/invalidAirRoute`` for more aircraft than
    ///   ``AirRoute/maximumAircraft``;
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func setAirRouteFrequency(_ id: AirRouteID, to frequency: AirRouteFrequency) throws(GameError) {
        let index = try airRouteIndex(of: id)
        guard frequency != airRoutes[index].frequency else { return }
        var route = airRoutes[index]
        route.frequency = frequency
        let needed = try aircraftNeeded(by: route)
        try spendOnAirRoutes(Money(route.size.price.amount * Int64(max(0, needed - route.aircraft))))
        route.aircraft = needed
        airRoutes[index] = route
    }

    /// Flies route `id` with aircraft of `size`: the fleet it then needs is
    /// bought new at ``AircraftSize/price``, the old one sold for nothing.
    ///
    /// - Throws: ``GameError/unknownAirRoute(_:)``;
    ///   ``GameError/invalidAirRoute`` for more aircraft than
    ///   ``AirRoute/maximumAircraft``;
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func setAirRouteSize(_ id: AirRouteID, to size: AircraftSize) throws(GameError) {
        let index = try airRouteIndex(of: id)
        guard size != airRoutes[index].size else { return }
        var route = airRoutes[index]
        route.size = size
        let needed = try aircraftNeeded(by: route)
        try spendOnAirRoutes(Money(size.price.amount * Int64(needed)))
        route.aircraft = needed
        airRoutes[index] = route
    }

    /// Sells route `id`: it flies no more, and is on sale again. Neither
    /// its aircraft nor its passengers are paid back, as a ferry's boats
    /// (decision 585).
    ///
    /// - Throws: ``GameError/unknownAirRoute(_:)``.
    public mutating func sellAirRoute(_ id: AirRouteID) throws(GameError) {
        airRoutes.remove(at: try airRouteIndex(of: id))
    }

    // MARK: - Queries

    /// Route `id`, or `nil`.
    public func airRoute(id: AirRouteID) -> AirRoute? {
        airRoutes.first { $0.id == id }
    }

    /// The minutes of the day route `id`'s aircraft leave its airport, in
    /// order: its departures shared among the airport's open hours as its
    /// flights are (``AirportRules/flightsByHour(_:first:last:)``), each
    /// hour's spread evenly through it. Empty for no such route or an
    /// airport the map no longer has.
    public func airRouteDepartureMinutes(_ id: AirRouteID) -> [Int64] {
        guard let route = airRoute(id: id), let origin = airports.first(where: { $0.id == route.airport }) else { return [] }
        let hours = AirportRules.flightsByHour(route.departures, first: origin.firstHour, last: origin.lastHour)
        return hours.enumerated().flatMap { hour, count in
            (0..<count).map { Int64(hour) * 60 + ($0 + 1) * 60 / (count + 1) }
        }
    }

    // MARK: - Internals

    func airRouteIndex(of id: AirRouteID) throws(GameError) -> Int {
        guard let index = airRoutes.firstIndex(where: { $0.id == id }) else { throw .unknownAirRoute(id) }
        return index
    }

    /// The aircraft `route` needs in its airport's open hours (all day
    /// when the map no longer has it).
    private func aircraftNeeded(by route: AirRoute) throws(GameError) -> Int {
        let origin = airports.first { $0.id == route.airport }
        let minutes = origin.map { Int64($0.lastHour - $0.firstHour) * 60 } ?? GameTime.minutesPerDay
        let needed = AirRoute.aircraftNeeded(departures: route.departures, metres: route.metres, size: route.size, minutes: minutes)
        guard needed <= Int64(AirRoute.maximumAircraft) else { throw .invalidAirRoute }
        return Int(needed)
    }

    private mutating func spendOnAirRoutes(_ price: Money) throws(GameError) {
        guard price > .zero else { return }
        try economy.spend(price)
        if accounts.mode == .management {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + price }
        }
    }

    // MARK: - Midnight

    /// The routes' day `day` that ended, `days` the airports' that day in
    /// their order (``closeAirportDay(_:at:)``): each route carries the
    /// passengers its airport's day gave its destination, at
    /// ``AirRouteFrequency/passengerShare``, as many as its seats hold,
    /// none on a day a typhoon covers either end the map holds; they pay
    /// its fare. Its aircraft's upkeep goes out every day, its flights'
    /// kilometres and landings on a day they fly. Kept on the route for
    /// ``AirRoute/keptDays`` days; one row for them all. A managed
    /// company's only.
    mutating func settleAirRoutes(day: Int64, airportDays days: [AirportDay], time: GameTime) {
        guard accounts.mode == .management, !airRoutes.isEmpty else { return }
        let covering = typhoons(onDay: day).filter { $0.isActive(onDay: day) }
        var fares = Money.zero, running = Money.zero, landings = Money.zero
        for index in airRoutes.indices {
            let route = airRoutes[index]
            let counted = days.first { $0.airport.id == route.airport }
            let farClosed = route.farAirport.flatMap { far in airports.first { $0.id == far } }.map { far in covering.contains { $0.covers(far.point) } } ?? false
            let closed = (counted?.isClosed ?? false) || farClosed
            let wanted = closed ? 0 : (counted?.departures.first { $0.destination.name == route.destination }?.passengers ?? 0)
            let passengers = min(route.dailySeats, wanted * route.frequency.passengerShare / 1_000)
            let flights = closed ? 0 : 2 * route.departures
            let dayFares = Money(passengers * route.fare.amount)
            let dayRunning = Money(Int64(route.aircraft) * route.size.dailyUpkeep.amount + flights * route.flightCost.amount)
            let dayLandings = Money(flights * route.size.landingFee.amount)
            fares = fares + dayFares
            running = running + dayRunning
            landings = landings + dayLandings
            airRoutes[index].days.append(AirRouteDay(day: day, passengers: passengers, fares: dayFares, running: dayRunning,
                                                     landingFees: dayLandings, closed: closed))
            if airRoutes[index].days.count > AirRoute.keptDays { airRoutes[index].days.removeFirst() }
        }
        guard fares > .zero || running > .zero || landings > .zero else { return }
        write(LedgerEntry(
            kind: .dailyAirRoutes, time: time, amount: fares - running - landings,
            breakdown: [
                LedgerLine(item: .airFares, amount: fares),
                LedgerLine(item: .airRunning, amount: .zero - running),
                LedgerLine(item: .landingFees, amount: .zero - landings),
            ]
        ), day: day)
    }

    // MARK: - Validation

    func airRoutesProblem() -> String? {
        guard nextAirRouteID >= 1 else { return "The next air route's number is 1 or more." }
        guard !airRoutes.isEmpty else { return nil }
        guard airRoutes.count <= AirRoute.maximumRoutes,
              airRoutes.allSatisfy({ $0.isValid && $0.id.rawValue < nextAirRouteID }),
              zip(airRoutes, airRoutes.dropFirst()).allSatisfy({ $0.id < $1.id })
        else {
            return "Each air route is well formed, a number handed out, in order, at most \(AirRoute.maximumRoutes)."
        }
        for (index, route) in airRoutes.enumerated() {
            for other in airRoutes[..<index] where (other.airport == route.airport && other.destination == route.destination)
                || (route.farAirport != nil && other.airport == route.farAirport && other.farAirport == route.airport) {
                return "No air route is bought twice."
            }
        }
        return nil
    }
}
