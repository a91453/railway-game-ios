// Decision 706: intercity coaches. A coach stop is a place on a real-world
// map where the real freeway and highway coaches call, by their real
// timetables, the same on every device: the company runs none of them.
// They do two things to the railway.
//
// They take passengers from it. Between two stations that each have a
// coach stop within walking distance, joined by a direct coach, part of the
// railway's trips ride the coach instead: more the cheaper and the quicker
// the coach is beside the train, counting the wait for each and the fares
// in minutes, and none while the train is well ahead (a high-speed line).
//
// And they bring passengers to it. A station that trains call at within
// walking distance of a coach stop takes the coach passengers the railway
// can carry on: those who get off ride from it to the stations they can
// reach, those who get on ride to it, on the hours the coaches call. They
// join the passenger plan as the air passengers do (`TouristFlows`).
//
// A world with no coach stops works nothing out here and plays exactly as
// it did.

/// The numbers of decision 706.
public enum CoachRules {
    /// The most coach stops a world holds, and the most coaches' links
    /// each lists.
    public static let maximumStops = 128
    public static let maximumLinks = 16
    /// The passengers of an average coach, both to count a stop's
    /// passengers from its coaches and to say how many a day carried.
    public static let passengersPerCoach: Int64 = 24
    /// The game's rail riders for every thousand coach passengers of a
    /// stop, before the stations within reach cap them.
    public static let ridersPerThousand: Int64 = 200
    /// One rider a day, each way, for every this many residents of the
    /// stations the stop's station can ride to, shared among the busiest
    /// ``busiestStations`` of them (as ``AirportRules``).
    public static let residentsPerRider: Int64 = AirportRules.residentsPerRider
    public static let busiestStations = AirportRules.busiestStations
    /// The most of a pair's trips the coach takes, in thousandths.
    public static let cap: Int64 = 250
    /// What a minute is worth beside the fares, in money.
    public static let moneyPerMinute: Int64 = 5
    /// The hours a day the coaches of a link are spread over, to work out
    /// the wait for one; and the longest wait counted, minutes.
    static let serviceMinutes: Int64 = 16 * 60
    static let longestWait: Int64 = 30
    /// The coach takes nothing while the train costs no more than this
    /// many thousandths of the coach, and ``cap`` from ``allAt`` on.
    static let noneAt: Int64 = 700
    static let allAt: Int64 = 1_300

    /// A day's coaches and passengers, in thousandths of a weekday's: a
    /// holiday or a Friday, a Saturday, a Sunday, another weekday (the
    /// real timetables' departures of each day beside a Wednesday's).
    public static func dayFactor(weekday: Int, holiday: Bool) -> Int64 {
        if holiday { return 1_090 }
        switch weekday {
        case 5: return 1_090
        case 6: return 900
        case 0: return 930
        default: return 1_000
        }
    }

    /// The minutes waited for one of `coaches` a day: half the gap between
    /// them, at most ``longestWait``.
    public static func waitMinutes(coaches: Int64) -> Int64 {
        min(longestWait, serviceMinutes / (2 * max(1, coaches)))
    }

    /// The share of a pair's trips that ride the coach, in thousandths,
    /// when the train costs `rail` and the coach `coach` (minutes, the
    /// fares counted at ``moneyPerMinute``): nothing up to ``noneAt``
    /// thousandths of the coach's cost, then evenly more up to ``cap`` at
    /// ``allAt``.
    public static func share(rail: Int64, coach: Int64) -> Int64 {
        let ratio = rail * 1_000 / max(1, coach)
        guard ratio > noneAt else { return 0 }
        return min(cap, (ratio - noneAt) * cap / (allAt - noneAt))
    }
}

/// The direct coaches from a stop to another (decision 706).
public struct CoachLink: Hashable, Sendable {
    /// The other stop's number.
    public let to: Int
    /// The coaches of a weekday, their minutes on the way and the fare.
    public let dailyCoaches: Int64
    public let minutes: Int64
    public let fare: Int64

    public init(to: Int, dailyCoaches: Int64, minutes: Int64, fare: Int64) {
        self.to = to
        self.dailyCoaches = dailyCoaches
        self.minutes = minutes
        self.fare = fare
    }

    var isValid: Bool {
        to >= 1 && (1...GameWorld.maximumAccrued).contains(dailyCoaches) && (1...GameWorld.maximumAccrued).contains(minutes)
            && (0...GameWorld.maximumAccrued).contains(fare)
    }

    /// What riding it costs, in minutes: the ride, the wait and the fare.
    var cost: Int64 {
        minutes + CoachRules.waitMinutes(coaches: dailyCoaches) + fare / CoachRules.moneyPerMinute
    }
}

/// A coach stop on the map (decision 706): the stops of the real coaches
/// within a short walk of each other, taken as one.
public struct CoachStop: Hashable, Sendable {
    /// Its number, from 1 in the order the map lists them.
    public let id: Int
    public let name: String
    public let point: PlanPoint
    /// The coaches that call on a weekday, and the passengers who get on
    /// and off them here.
    public let dailyCoaches: Int64
    public let dailyPassengers: Int64
    /// The weights of the 24 hours its coaches call in, hour 0 first.
    public let hours: [Int64]
    /// The direct coaches to the map's other stops, by ascending number.
    public let links: [CoachLink]
    /// The coach passengers here and the riders among them on the
    /// company's trains (both ways together) of the day that last ended.
    public internal(set) var yesterdayPassengers: Int64
    public internal(set) var yesterdayRiders: Int64

    public init(id: Int, name: String, point: PlanPoint, dailyCoaches: Int64, dailyPassengers: Int64, hours: [Int64], links: [CoachLink] = []) {
        self.id = id
        self.name = name
        self.point = point
        self.dailyCoaches = dailyCoaches
        self.dailyPassengers = dailyPassengers
        self.hours = hours
        self.links = links
        yesterdayPassengers = 0
        yesterdayRiders = 0
    }
}

/// A coach stop's day (``GameWorld/coachDays()``).
public struct CoachDay: Hashable, Sendable {
    public let stop: CoachStop
    /// The station whose trains its passengers ride, or `nil` when none
    /// that trains call at stands within ``Tourism/reach`` of it.
    public let station: StationID?
    /// Whether a typhoon stops the coaches today.
    public let isClosed: Bool
    /// The day's coaches and the passengers who get on and off here.
    public let coaches: Int64
    public let passengers: Int64
    /// Those of them who ride the company's trains from the stop and to it.
    public let ridersFrom: Int64
    public let ridersTo: Int64

    public var riders: Int64 { ridersFrom + ridersTo }
}

extension GameWorld {
    // MARK: - Command

    /// Sets the coach stops of the map (decision 706), numbered from 1 in
    /// the order given. Free. Those outside the map, those with no coaches
    /// or passengers and those past ``CoachRules/maximumStops`` are left
    /// out, as are a stop's links to stops left out, to itself or past
    /// ``CoachRules/maximumLinks``; a link's `to` counts the stops of
    /// `list` from 1. A stop the map already had, by its name and point,
    /// keeps the counts of the day that last ended.
    public mutating func setCoachStops(_ list: [CoachStop]) {
        var number: [Int: Int] = [:]
        var picked: [(index: Int, stop: CoachStop)] = []
        for (index, stop) in list.enumerated() where picked.count < CoachRules.maximumStops {
            guard (0..<bounds.width).contains(stop.point.x), (0..<bounds.height).contains(stop.point.y), !stop.name.isEmpty,
                  (1...Self.maximumAccrued).contains(stop.dailyCoaches), (1...Self.maximumAccrued).contains(stop.dailyPassengers),
                  stop.hours.count == 24, stop.hours.allSatisfy({ (0...Self.maximumAccrued).contains($0) }), stop.hours.contains(where: { $0 > 0 })
            else { continue }
            number[index + 1] = picked.count + 1
            picked.append((index, stop))
        }
        let kept = picked.map { entry -> CoachStop in
            var seen: Set<Int> = []
            let links = entry.stop.links.compactMap { link -> CoachLink? in
                guard link.isValid, link.to != entry.index + 1, let to = number[link.to], seen.insert(to).inserted else { return nil }
                return CoachLink(to: to, dailyCoaches: link.dailyCoaches, minutes: link.minutes, fare: link.fare)
            }.sorted { $0.to < $1.to }
            var next = CoachStop(id: number[entry.index + 1]!, name: entry.stop.name, point: entry.stop.point,
                                 dailyCoaches: entry.stop.dailyCoaches, dailyPassengers: entry.stop.dailyPassengers,
                                 hours: entry.stop.hours, links: Array(links.prefix(CoachRules.maximumLinks)))
            if let old = coachStops.first(where: { $0.name == entry.stop.name && $0.point == entry.stop.point }) {
                next.yesterdayPassengers = old.yesterdayPassengers
                next.yesterdayRiders = old.yesterdayRiders
            }
            return next
        }
        guard kept != coachStops else { return }
        coachStops = kept
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    /// The coach stops' stations today, in the stops' order (`nil` for a
    /// stop no station serves): the passenger plan is worked out again
    /// when one changes.
    var coachStations: [StationID?] {
        coachStops.map { servingStation(at: $0.point) }
    }

    /// The cheapest direct coach between each pair of stations that both
    /// serve a coach stop; empty without coach stops.
    func coachRivals() -> [StationID: [StationID: CoachLink]] {
        guard !coachStops.isEmpty else { return [:] }
        let serving = coachStations
        var rivals: [StationID: [StationID: CoachLink]] = [:]
        for (index, stop) in coachStops.enumerated() {
            guard let origin = serving[index] else { continue }
            for link in stop.links {
                guard let destination = serving[link.to - 1], destination != origin else { continue }
                if let old = rivals[origin]?[destination], old.cost <= link.cost { continue }
                rivals[origin, default: [:]][destination] = link
            }
        }
        return rivals
    }

    /// `trips` less those that ride `rival`'s coach instead, when the
    /// railway's fastest way takes `minutes`.
    func coachKept(_ trips: Int64, from origin: StationID, to destination: StationID, minutes: Int64, rival: CoachLink?) -> Int64 {
        guard let rival, trips > 0 else { return trips }
        let fare = tripFare(from: origin, to: destination)?.amount ?? 0
        let rail = minutes + fare / CoachRules.moneyPerMinute
        return trips - ModeShift.lost(trips, share: CoachRules.share(rail: rail, coach: rival.cost))
    }

    /// How many pairs of stations, counted each way, have a direct coach
    /// between coach stops they serve.
    public func coachPairCount() -> Int {
        coachRivals().values.reduce(0) { $0 + $1.count }
    }

    /// The trips a day from `origin` that ride a direct coach instead of
    /// the company's trains, all its destinations together; 0 without
    /// coach stops. Read from the world; nothing is kept.
    public func tripsTakenByCoaches(from origin: StationID) -> Int64 {
        guard !coachStops.isEmpty, passengerRoutingMode == .network else { return 0 }
        return dailyDemandDetails(from: origin).reduce(Int64(0)) { $0 + $1.byCoach }
    }

    /// Coach stop `stop`'s day `day`, with the stations its riders are
    /// shared among each way.
    func coachDay(of stop: CoachStop, onDay day: Int64,
                  candidates: [(station: StationID, outside: Bool, residents: Int64)],
                  reaches: (StationID, StationID) -> Bool)
        -> (day: CoachDay, from: [(station: StationID, riders: Int64)], to: [(station: StationID, riders: Int64)]) {
        let station = servingStation(at: stop.point)
        let closed = typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(stop.point) }
        let factor = closed ? 0 : CoachRules.dayFactor(weekday: StationDemand.weekday(ofDay: day), holiday: holiday(onDay: day) != nil)
        let passengers = stop.dailyPassengers * factor / 1_000
        // The coach passengers each way that would take the train.
        let wanting = passengers * CoachRules.ridersPerThousand / 2_000
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
                for entry in weighed where picked.count < CoachRules.busiestStations && rides(entry.station) {
                    picked.append(entry)
                }
                picked.sort { $0.station < $1.station }
                let riders = min(wanting, picked.reduce(Int64(0)) { $0 + $1.weight } / CoachRules.residentsPerRider)
                return zip(picked, Self.apportion(riders, by: picked.map(\.weight))).compactMap { $1 > 0 ? ($0.station, $1) : nil }
            }
            to = shared { reaches($0, station) }
            from = shared { reaches(station, $0) }
        }
        let result = CoachDay(stop: stop, station: station, isClosed: closed, coaches: stop.dailyCoaches * factor / 1_000,
                              passengers: passengers, ridersFrom: from.reduce(Int64(0)) { $0 + $1.riders },
                              ridersTo: to.reduce(Int64(0)) { $0 + $1.riders })
        return (result, from, to)
    }

    /// Adds the coach stops' riders of game day `day` to `flows`, `reaches`
    /// saying which pairs can ride, and returns each stop's day, in the
    /// stops' order.
    @discardableResult
    func addCoachFlows(onDay day: Int64, to flows: inout TouristFlows, reaches: (StationID, StationID) -> Bool) -> [CoachDay] {
        guard !coachStops.isEmpty else { return [] }
        let candidates = touristCandidates()
        return coachStops.map { stop in
            let counted = coachDay(of: stop, onDay: day, candidates: candidates, reaches: reaches)
            guard let station = counted.day.station else { return counted.day }
            for entry in counted.from {
                flows.add(hours: Self.apportion(entry.riders, by: stop.hours), from: station, to: entry.station)
            }
            for entry in counted.to {
                flows.add(hours: Self.apportion(entry.riders, by: stop.hours), from: entry.station, to: station)
            }
            return counted.day
        }
    }

    /// Every coach stop's day today, as the passenger model reaches the
    /// stations now, in the stops' order; empty without coach stops.
    public func coachDays() -> [CoachDay] {
        guard !coachStops.isEmpty else { return [] }
        let world = self
        let served = coachStops.contains { servingStation(at: $0.point) != nil }
        let graph = served && passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        var flows = TouristFlows()
        return addCoachFlows(onDay: dayIndex(of: clock.now), to: &flows) { world.reaches(from: $0, to: $1, graph: graph) }
    }

    /// The days of the coach stops station `id` serves today; empty for
    /// none.
    public func coachDays(at id: StationID) -> [CoachDay] {
        guard coachStops.contains(where: { servingStation(at: $0.point) == id }) else { return [] }
        return coachDays().filter { $0.station == id }
    }

    /// The coach stops station `id` serves, with the counts of the day
    /// that last ended; empty for none.
    public func coachStops(at id: StationID) -> [CoachStop] {
        coachStops.filter { servingStation(at: $0.point) == id }
    }

    // MARK: - Midnight

    /// Counts the coach stops' day that ended. Runs at midnight, on the
    /// network as it ran at noon of that day (decision 551).
    mutating func closeCoachDay(_ day: Int64) {
        guard !coachStops.isEmpty, day >= 0 else { return }
        let world = self
        let served = coachStops.contains { servingStation(at: $0.point) != nil }
        let graph = served && passengerRoutingMode == .network ? Tourism.countingGraph(of: self, day: day) : nil
        var flows = TouristFlows()
        let days = world.addCoachFlows(onDay: day, to: &flows) { world.reaches(from: $0, to: $1, graph: graph) }
        for (index, counted) in days.enumerated() {
            coachStops[index].yesterdayPassengers = counted.passengers
            coachStops[index].yesterdayRiders = counted.riders
        }
    }

    // MARK: - Validation

    func coachStopsProblem() -> String? {
        guard coachStops.count <= CoachRules.maximumStops else { return "A world has at most \(CoachRules.maximumStops) coach stops." }
        for (index, stop) in coachStops.enumerated() {
            guard stop.id == index + 1, !stop.name.isEmpty else { return "Coach stops are numbered from 1 and named." }
            guard stop.point.x >= 0, stop.point.y >= 0, stop.point.x < bounds.width, stop.point.y < bounds.height else {
                return "A coach stop lies outside the world."
            }
            guard (1...Self.maximumAccrued).contains(stop.dailyCoaches), (1...Self.maximumAccrued).contains(stop.dailyPassengers),
                  stop.hours.count == 24, stop.hours.allSatisfy({ (0...Self.maximumAccrued).contains($0) }), stop.hours.contains(where: { $0 > 0 }),
                  (0...Self.maximumAccrued).contains(stop.yesterdayPassengers), (0...Self.maximumAccrued).contains(stop.yesterdayRiders)
            else { return "A coach stop's coaches, passengers, hours or counts are out of range." }
            guard stop.links.count <= CoachRules.maximumLinks, stop.links.allSatisfy({ $0.isValid && $0.to <= coachStops.count && $0.to != stop.id }),
                  zip(stop.links, stop.links.dropFirst()).allSatisfy({ $0.to < $1.to })
            else { return "A coach stop's links are too many, out of order or out of range." }
        }
        return nil
    }
}

// MARK: - Codable

extension CoachStop: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, x, y, dailyCoaches, dailyPassengers, hours, links, yesterdayPassengers, yesterdayRiders
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        point = PlanPoint(x: try container.decode(Int64.self, forKey: .x), y: try container.decode(Int64.self, forKey: .y))
        dailyCoaches = try container.decode(Int64.self, forKey: .dailyCoaches)
        dailyPassengers = try container.decode(Int64.self, forKey: .dailyPassengers)
        hours = try container.decode([Int64].self, forKey: .hours)
        // Four numbers a link: the stop, its coaches, minutes and fare.
        let flat = try container.decodeIfPresent([Int64].self, forKey: .links) ?? []
        guard flat.count.isMultiple(of: 4) else {
            throw DecodingError.dataCorruptedError(forKey: .links, in: container, debugDescription: "A coach stop's links are four numbers each.")
        }
        links = stride(from: 0, to: flat.count, by: 4).map {
            CoachLink(to: Int(clamping: flat[$0]), dailyCoaches: flat[$0 + 1], minutes: flat[$0 + 2], fare: flat[$0 + 3])
        }
        yesterdayPassengers = try container.decodeIfPresent(Int64.self, forKey: .yesterdayPassengers) ?? 0
        yesterdayRiders = try container.decodeIfPresent(Int64.self, forKey: .yesterdayRiders) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(point.x, forKey: .x)
        try container.encode(point.y, forKey: .y)
        try container.encode(dailyCoaches, forKey: .dailyCoaches)
        try container.encode(dailyPassengers, forKey: .dailyPassengers)
        try container.encode(hours, forKey: .hours)
        if !links.isEmpty {
            try container.encode(links.flatMap { [Int64($0.to), $0.dailyCoaches, $0.minutes, $0.fare] }, forKey: .links)
        }
        if yesterdayPassengers != 0 { try container.encode(yesterdayPassengers, forKey: .yesterdayPassengers) }
        if yesterdayRiders != 0 { try container.encode(yesterdayRiders, forKey: .yesterdayRiders) }
    }
}
