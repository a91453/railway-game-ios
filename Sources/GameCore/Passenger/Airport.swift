// Decision 695: airports as hubs. An airport is a place on a real-world
// map whose flights come and go by themselves, by the hour, the same on
// every device: the company runs no airline. A station of the company's
// that trains call at within walking distance of the terminal takes the
// air passengers the railway can carry: those who land ride from it to
// the stations they can reach, those who fly ride to it, each on the hours
// of the flights. They join the passenger plan as the tourists and the
// students do (`TouristFlows`), so they board, pay their fares and fill
// trains like every other passenger. The better the railway serves the
// airport, the more flights it draws. The tourists of the sights set out
// from an airport's station too (`touristSources`).
//
// Decision 700: an airport lists where its flights go, at home or abroad,
// with each destination's passengers and flights of a year. They split a
// day's passengers into domestic and international ones, say how many
// flights leave for each place today, and set the hours its riders travel
// in: a domestic passenger reaches the airport an hour before the flight
// and leaves it within the hour of landing, an international one two
// hours before and an hour after.

/// The numbers of decision 695.
public enum AirportRules {
    /// The most airports a world holds.
    public static let maximumAirports = 16
    /// The most destinations an airport lists (decision 700).
    public static let maximumDestinations = 24
    /// The game's rail riders for every thousand air passengers, each way,
    /// before the stations within reach cap them: Taoyuan's two Airport
    /// MRT stations and Songshan Airport station count some 23,000 and
    /// 5,100 riders a day beside 131,000 and 15,400 air passengers, and
    /// 150 a thousand gives about 19,000 and 2,200 (decision 695,
    /// measured).
    public static let ridersPerThousand: Int64 = 150
    /// One rider a day, each way, for every this many residents of the
    /// stations the airport's station can ride to (an outside connection
    /// counts as ``Tourism/outsideWeight`` residents): a two-station line
    /// to the terminal fills no trains.
    public static let residentsPerRider: Int64 = 60
    /// The stations riders are shared among: the busiest this many by
    /// residents among those that can ride to the airport's station.
    public static let busiestStations = 12
    /// The flights and air passengers a fully served airport gains, in
    /// thousandths: with every rider the railway could carry on board, it
    /// draws a fifth more flights.
    public static let railBonus: Int64 = 200
    /// A day's flights and passengers, in thousandths of the average day:
    /// a holiday, a Friday or a Sunday, a Saturday, another weekday.
    public static func dayFactor(weekday: Int, holiday: Bool) -> Int64 {
        if holiday { return 1_150 }
        switch weekday {
        case 0, 5: return 1_100
        case 6: return 1_000
        default: return 950
        }
    }

    /// Each hour's share of a day's flights at an airport open round the
    /// clock, hour 0 first: few at night, a wave in the morning and one in
    /// the afternoon and evening.
    static let flightShape: [Int64] = [2, 1, 0, 0, 0, 1, 4, 7, 8, 7, 6, 5, 5, 6, 7, 7, 7, 6, 6, 5, 5, 4, 4, 3]

    /// The flights of a day at an airport open from `first` to `last`
    /// (hours, `last` not included), shared among its hours.
    static func flightsByHour(_ flights: Int64, first: Int, last: Int) -> [Int64] {
        GameWorld.apportion(flights, by: (0..<24).map { (first..<last).contains($0) ? max(1, flightShape[$0]) : 0 })
    }

    /// The weights of the riders from the airport by hour: an hour after
    /// each hour's flights land, through immigration and baggage; those
    /// off a domestic flight (decision 700) within the hour it lands.
    static func landedShape(first: Int, last: Int, domestic: Bool = false) -> [Int64] {
        let flights = flightsByHour(1_000, first: first, last: last)
        return domestic ? flights : (0..<24).map { flights[($0 + 23) % 24] }
    }

    /// The weights of the riders to the airport by hour: two hours before
    /// each hour's flights leave; for a domestic flight (decision 700),
    /// whose counter closes half an hour before it leaves, one hour.
    static func leavingShape(first: Int, last: Int, domestic: Bool = false) -> [Int64] {
        let flights = flightsByHour(1_000, first: first, last: last)
        return (0..<24).map { flights[($0 + (domestic ? 1 : 2)) % 24] }
    }
}

/// A place an airport's flights go to (decision 700).
public struct AirDestination: Hashable, Sendable {
    /// Its name; empty for the rest of the airport's destinations of its
    /// kind taken together.
    public let name: String
    public let englishName: String
    /// Whether the flights stay in the country.
    public let isDomestic: Bool
    /// The passengers and the flights between the airport and it in a
    /// year, both ways together.
    public let yearlyPassengers: Int64
    public let yearlyFlights: Int64

    public init(name: String, englishName: String, isDomestic: Bool, yearlyPassengers: Int64, yearlyFlights: Int64) {
        self.name = name
        self.englishName = englishName
        self.isDomestic = isDomestic
        self.yearlyPassengers = yearlyPassengers
        self.yearlyFlights = yearlyFlights
    }

    /// Whether it stands for the rest of its kind.
    public var isRest: Bool { name.isEmpty }

    var isValid: Bool {
        (1...GameWorld.maximumAccrued).contains(yearlyPassengers) && (0...GameWorld.maximumAccrued).contains(yearlyFlights)
            && name.isEmpty == englishName.isEmpty
    }
}

/// An airport on the map (decision 695).
public struct Airport: Hashable, Sendable {
    /// Its number, from 1 in the order the map lists them.
    public let id: Int
    public let name: String
    public let englishName: String
    /// Its passenger terminal.
    public let point: PlanPoint
    /// The air passengers of an average day, arriving and leaving
    /// together, as its real figures say.
    public let dailyPassengers: Int64
    /// The flights of an average day, landings and take-offs together.
    public let dailyFlights: Int64
    /// The hours flights land and leave in: from `firstHour` to `lastHour`,
    /// the last not included (0 and 24 for an airport with no curfew).
    public let firstHour: Int
    public let lastHour: Int
    /// Where its flights go (decision 700), in the map's order; empty when
    /// the map does not say, and then every passenger keeps the
    /// international hours.
    public let destinations: [AirDestination]
    /// The flights, the air passengers and the riders on the company's
    /// trains (both ways together) of the day that last ended.
    public internal(set) var yesterdayFlights: Int64
    public internal(set) var yesterdayPassengers: Int64
    public internal(set) var yesterdayRiders: Int64

    public init(id: Int, name: String, englishName: String, point: PlanPoint, dailyPassengers: Int64, dailyFlights: Int64,
                firstHour: Int = 0, lastHour: Int = 24, destinations: [AirDestination] = []) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.point = point
        self.dailyPassengers = dailyPassengers
        self.dailyFlights = dailyFlights
        self.firstHour = firstHour
        self.lastHour = lastHour
        self.destinations = destinations
        yesterdayFlights = 0
        yesterdayPassengers = 0
        yesterdayRiders = 0
    }

    /// The domestic passengers among a thousand of the airport's, as its
    /// destinations' years say (decision 700); 0 with no destinations.
    public var domesticShare: Int64 {
        let all = destinations.reduce(Int64(0)) { $0 + $1.yearlyPassengers }
        guard all > 0 else { return 0 }
        return destinations.reduce(Int64(0)) { $0 + ($1.isDomestic ? $1.yearlyPassengers : 0) } * 1_000 / all
    }
}

/// The flights that leave an airport for one of its destinations in a day,
/// and the passengers between them both ways (decision 700).
public struct AirportDeparture: Hashable, Sendable {
    public let destination: AirDestination
    public let flights: Int64
    public let passengers: Int64
}

/// An airport's day (``GameWorld/airportDays()``).
public struct AirportDay: Hashable, Sendable {
    public let airport: Airport
    /// The station whose trains its passengers ride, or `nil` when none
    /// that trains call at stands within ``Tourism/reach`` of the terminal.
    public let station: StationID?
    /// Whether a typhoon shuts it today: no flight, no passenger.
    public let isClosed: Bool
    /// The day's flights and air passengers, landing and leaving together.
    public let flights: Int64
    public let passengers: Int64
    /// The air passengers who ride the company's trains from the airport
    /// and to it today.
    public let ridersFrom: Int64
    public let ridersTo: Int64
    /// The most the railway could carry each way if every station of the
    /// city rode to the terminal: what ``ridersFrom`` and ``ridersTo``
    /// grow towards.
    public let ridersAtMost: Int64
    /// The day's landings and take-offs in each hour, hour 0 first.
    public let landings: [Int64]
    public let takeOffs: [Int64]
    /// The domestic passengers among ``passengers`` (decision 700); 0 at
    /// an airport that lists no destinations.
    public let domesticPassengers: Int64
    /// The day's take-offs and passengers by destination, in the airport's
    /// order; empty at an airport that lists none.
    public let departures: [AirportDeparture]

    public var riders: Int64 { ridersFrom + ridersTo }
    public var internationalPassengers: Int64 { passengers - domesticPassengers }
}

extension GameWorld {
    // MARK: - Command

    /// Sets the airports of the map (decision 695), numbered from 1 in the
    /// order given. Free. Those outside the map, those with no passengers
    /// or flights and those past ``AirportRules/maximumAirports`` are left
    /// out, as are the destinations past
    /// ``AirportRules/maximumDestinations`` and those with no passengers.
    /// An airport the map already had, by its name and terminal, keeps the
    /// counts of the day that last ended (decision 700); any other starts
    /// with no day counted.
    public mutating func setAirports(_ list: [Airport]) {
        var kept: [Airport] = []
        for airport in list where kept.count < AirportRules.maximumAirports {
            guard (0..<bounds.width).contains(airport.point.x), (0..<bounds.height).contains(airport.point.y),
                  airport.dailyPassengers > 0, airport.dailyFlights > 0, !airport.name.isEmpty,
                  airport.dailyPassengers <= Self.maximumAccrued, airport.dailyFlights <= Self.maximumAccrued,
                  airport.firstHour >= 0, airport.firstHour < airport.lastHour, airport.lastHour <= 24
            else { continue }
            var next = Airport(id: kept.count + 1, name: airport.name, englishName: airport.englishName, point: airport.point,
                               dailyPassengers: airport.dailyPassengers, dailyFlights: airport.dailyFlights,
                               firstHour: airport.firstHour, lastHour: airport.lastHour,
                               destinations: Array(airport.destinations.filter(\.isValid).prefix(AirportRules.maximumDestinations)))
            if let old = airports.first(where: { $0.name == airport.name && $0.point == airport.point }) {
                next.yesterdayFlights = old.yesterdayFlights
                next.yesterdayPassengers = old.yesterdayPassengers
                next.yesterdayRiders = old.yesterdayRiders
            }
            kept.append(next)
        }
        guard kept != airports else { return }
        airports = kept
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    /// The airports' stations and what each weighs as a place tourists set
    /// out from: its airport's passengers of an average day (several
    /// airports at a station add up). Empty without airports.
    func airportTouristWeights() -> [StationID: Int64] {
        var weights: [StationID: Int64] = [:]
        for airport in airports {
            guard let station = servingStation(at: airport.point) else { continue }
            weights[station, default: 0] += airport.dailyPassengers
        }
        return weights
    }

    /// The airports' stations today, in the airports' order (`nil` for an
    /// airport no station serves): the passenger plan is worked out again
    /// when one changes.
    var airportStations: [StationID?] {
        airports.map { servingStation(at: $0.point) }
    }

    /// Airport `airport`'s day `day`, `reaches` saying which pairs can
    /// ride, with the stations its riders are shared among each way.
    func airportDay(of airport: Airport, onDay day: Int64,
                    candidates: [(station: StationID, outside: Bool, residents: Int64)],
                    reaches: (StationID, StationID) -> Bool)
        -> (day: AirportDay, from: [(station: StationID, riders: Int64)], to: [(station: StationID, riders: Int64)]) {
        let station = servingStation(at: airport.point)
        let closed = typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(airport.point) }
        let factor = closed ? 0 : AirportRules.dayFactor(weekday: StationDemand.weekday(ofDay: day), holiday: holiday(onDay: day) != nil)
        // The air passengers each way that would take the train.
        let wanting = airport.dailyPassengers * factor / 1_000 * AirportRules.ridersPerThousand / 2_000
        var from: [(station: StationID, riders: Int64)] = []
        var to: [(station: StationID, riders: Int64)] = []
        if let station, wanting > 0 {
            let cityless = candidates.allSatisfy { $0.residents == 0 }
            var weighed: [(station: StationID, weight: Int64)] = candidates.compactMap { candidate in
                guard candidate.station != station else { return nil }
                let own = cityless ? stationDemand(of: candidate.station)?.dailyTrips ?? 0 : candidate.residents
                let weight = own + (candidate.outside ? Tourism.outsideWeight : 0)
                return weight > 0 ? (candidate.station, weight) : nil
            }
            weighed.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.station < $1.station }
            func shared(_ rides: (StationID) -> Bool) -> [(station: StationID, riders: Int64)] {
                var picked: [(station: StationID, weight: Int64)] = []
                for entry in weighed where picked.count < AirportRules.busiestStations && rides(entry.station) {
                    picked.append(entry)
                }
                picked.sort { $0.station < $1.station }
                let riders = min(wanting, picked.reduce(Int64(0)) { $0 + $1.weight } / AirportRules.residentsPerRider)
                return zip(picked, Self.apportion(riders, by: picked.map(\.weight))).compactMap { $1 > 0 ? ($0.station, $1) : nil }
            }
            to = shared { reaches($0, station) }
            from = shared { reaches(station, $0) }
        }
        let ridersFrom = from.reduce(Int64(0)) { $0 + $1.riders }, ridersTo = to.reduce(Int64(0)) { $0 + $1.riders }
        // The railway's share of what it could carry draws more flights.
        let bonus = wanting > 0 ? AirportRules.railBonus * (ridersFrom + ridersTo) / (2 * wanting) : 0
        let flights = airport.dailyFlights * factor / 1_000 * (1_000 + bonus) / 1_000
        let passengers = airport.dailyPassengers * factor / 1_000 * (1_000 + bonus) / 1_000
        let landings = AirportRules.flightsByHour((flights + 1) / 2, first: airport.firstHour, last: airport.lastHour)
        let takeOffs = AirportRules.flightsByHour(flights / 2, first: airport.firstHour, last: airport.lastHour)
        // Decision 700: the day by destination.
        let leaving = Self.apportion(flights / 2, by: airport.destinations.map(\.yearlyFlights))
        let carried = Self.apportion(passengers, by: airport.destinations.map(\.yearlyPassengers))
        let departures = closed ? [] : airport.destinations.indices.map {
            AirportDeparture(destination: airport.destinations[$0], flights: leaving[$0], passengers: carried[$0])
        }
        let result = AirportDay(airport: airport, station: station, isClosed: closed, flights: flights, passengers: passengers,
                                ridersFrom: ridersFrom, ridersTo: ridersTo, ridersAtMost: wanting, landings: landings, takeOffs: takeOffs,
                                domesticPassengers: passengers * airport.domesticShare / 1_000, departures: departures)
        return (result, from, to)
    }

    /// Adds the airports' riders of game day `day` to `flows`, `reaches`
    /// saying which pairs can ride (decision 695), and returns each
    /// airport's day, in the airports' order.
    @discardableResult
    func addAirportFlows(onDay day: Int64, to flows: inout TouristFlows, reaches: (StationID, StationID) -> Bool) -> [AirportDay] {
        guard !airports.isEmpty else { return [] }
        let candidates = touristCandidates()
        return airports.map { airport in
            let counted = airportDay(of: airport, onDay: day, candidates: candidates, reaches: reaches)
            guard let station = counted.day.station else { return counted.day }
            let landed = AirportRules.landedShape(first: airport.firstHour, last: airport.lastHour)
            let leaving = AirportRules.leavingShape(first: airport.firstHour, last: airport.lastHour)
            // Decision 700: the domestic riders keep their own hours.
            let share = airport.domesticShare
            let landedHome = share > 0 ? AirportRules.landedShape(first: airport.firstHour, last: airport.lastHour, domestic: true) : []
            let leavingHome = share > 0 ? AirportRules.leavingShape(first: airport.firstHour, last: airport.lastHour, domestic: true) : []
            func hours(_ riders: Int64, abroad: [Int64], home: [Int64]) -> [Int64] {
                let domestic = riders * share / 1_000
                let far = Self.apportion(riders - domestic, by: abroad)
                guard domestic > 0 else { return far }
                return zip(far, Self.apportion(domestic, by: home)).map { $0 + $1 }
            }
            for entry in counted.from {
                flows.add(hours: hours(entry.riders, abroad: landed, home: landedHome), from: station, to: entry.station)
            }
            for entry in counted.to {
                flows.add(hours: hours(entry.riders, abroad: leaving, home: leavingHome), from: entry.station, to: station)
            }
            return counted.day
        }
    }

    /// Every airport's day today, as the passenger model reaches the
    /// stations now, in the airports' order; empty without airports.
    public func airportDays() -> [AirportDay] {
        guard !airports.isEmpty else { return [] }
        let world = self
        let served = airports.contains { servingStation(at: $0.point) != nil }
        let graph = served && passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        var flows = TouristFlows()
        return addAirportFlows(onDay: dayIndex(of: clock.now), to: &flows) { world.reaches(from: $0, to: $1, graph: graph) }
    }

    /// The days of the airports station `id` serves today; empty for none.
    public func airportDays(at id: StationID) -> [AirportDay] {
        guard airports.contains(where: { servingStation(at: $0.point) == id }) else { return [] }
        return airportDays().filter { $0.station == id }
    }

    // MARK: - Midnight

    /// Counts the airports' day that ended. Runs at midnight, on the
    /// network as it ran at noon of that day (decision 551).
    mutating func closeAirportDay(_ day: Int64) {
        guard !airports.isEmpty, day >= 0 else { return }
        let world = self
        let served = airports.contains { servingStation(at: $0.point) != nil }
        let graph = served && passengerRoutingMode == .network ? Tourism.countingGraph(of: self, day: day) : nil
        var flows = TouristFlows()
        let days = world.addAirportFlows(onDay: day, to: &flows) { world.reaches(from: $0, to: $1, graph: graph) }
        for (index, counted) in days.enumerated() {
            airports[index].yesterdayFlights = counted.flights
            airports[index].yesterdayPassengers = counted.passengers
            airports[index].yesterdayRiders = counted.riders
        }
    }

    // MARK: - Validation

    func airportsProblem() -> String? {
        guard airports.count <= AirportRules.maximumAirports else { return "A world has at most \(AirportRules.maximumAirports) airports." }
        for (index, airport) in airports.enumerated() {
            guard airport.id == index + 1, !airport.name.isEmpty else { return "Airports are numbered from 1 and named." }
            guard airport.point.x >= 0, airport.point.y >= 0, airport.point.x < bounds.width, airport.point.y < bounds.height else {
                return "An airport lies outside the world."
            }
            guard (1...Self.maximumAccrued).contains(airport.dailyPassengers), (1...Self.maximumAccrued).contains(airport.dailyFlights),
                  airport.firstHour >= 0, airport.firstHour < airport.lastHour, airport.lastHour <= 24,
                  (0...Self.maximumAccrued).contains(airport.yesterdayFlights), (0...Self.maximumAccrued).contains(airport.yesterdayPassengers),
                  (0...Self.maximumAccrued).contains(airport.yesterdayRiders)
            else { return "An airport's passengers, flights, hours or counts are out of range." }
            guard airport.destinations.count <= AirportRules.maximumDestinations, airport.destinations.allSatisfy(\.isValid) else {
                return "An airport's destinations are too many or out of range."
            }
        }
        return nil
    }
}

// MARK: - Codable

extension Airport: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, englishName, x, y, dailyPassengers, dailyFlights, firstHour, lastHour
        case yesterdayFlights, yesterdayPassengers, yesterdayRiders, destinations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        englishName = try container.decode(String.self, forKey: .englishName)
        point = PlanPoint(x: try container.decode(Int64.self, forKey: .x), y: try container.decode(Int64.self, forKey: .y))
        dailyPassengers = try container.decode(Int64.self, forKey: .dailyPassengers)
        dailyFlights = try container.decode(Int64.self, forKey: .dailyFlights)
        firstHour = try container.decodeIfPresent(Int.self, forKey: .firstHour) ?? 0
        lastHour = try container.decodeIfPresent(Int.self, forKey: .lastHour) ?? 24
        destinations = try container.decodeIfPresent([AirDestination].self, forKey: .destinations) ?? []
        yesterdayFlights = try container.decodeIfPresent(Int64.self, forKey: .yesterdayFlights) ?? 0
        yesterdayPassengers = try container.decodeIfPresent(Int64.self, forKey: .yesterdayPassengers) ?? 0
        yesterdayRiders = try container.decodeIfPresent(Int64.self, forKey: .yesterdayRiders) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(englishName, forKey: .englishName)
        try container.encode(point.x, forKey: .x)
        try container.encode(point.y, forKey: .y)
        try container.encode(dailyPassengers, forKey: .dailyPassengers)
        try container.encode(dailyFlights, forKey: .dailyFlights)
        if firstHour != 0 { try container.encode(firstHour, forKey: .firstHour) }
        if lastHour != 24 { try container.encode(lastHour, forKey: .lastHour) }
        if yesterdayFlights != 0 { try container.encode(yesterdayFlights, forKey: .yesterdayFlights) }
        if yesterdayPassengers != 0 { try container.encode(yesterdayPassengers, forKey: .yesterdayPassengers) }
        if yesterdayRiders != 0 { try container.encode(yesterdayRiders, forKey: .yesterdayRiders) }
        if !destinations.isEmpty { try container.encode(destinations, forKey: .destinations) }
    }
}

extension AirDestination: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, englishName, domestic, passengers, flights
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        englishName = try container.decodeIfPresent(String.self, forKey: .englishName) ?? ""
        isDomestic = try container.decodeIfPresent(Bool.self, forKey: .domestic) ?? false
        yearlyPassengers = try container.decode(Int64.self, forKey: .passengers)
        yearlyFlights = try container.decodeIfPresent(Int64.self, forKey: .flights) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !name.isEmpty { try container.encode(name, forKey: .name) }
        if !englishName.isEmpty { try container.encode(englishName, forKey: .englishName) }
        if isDomestic { try container.encode(true, forKey: .domestic) }
        try container.encode(yearlyPassengers, forKey: .passengers)
        if yearlyFlights != 0 { try container.encode(yearlyFlights, forKey: .flights) }
    }
}
