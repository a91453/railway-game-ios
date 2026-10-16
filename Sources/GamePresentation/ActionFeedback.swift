import GameCore

// Decision 256 (decision 254 §4, the core loop's third PR): every action
// answers where it happened. Fares float up over the station a train took
// them at, a goal met gets a check and a short tune, and a town that grew
// a step gets a warm ring. Presentation only: each is read from the world
// before and after a step, and nothing here is saved or changes the world.
//
// Reference: island_city's `popText` (a float per place, a day apart, at
// most 36) and train_loop's `updatePass` (a station's "+N" banner, in
// 0.15 s, held 0.6 s, out 0.12 s) give the rules of one float a place,
// merged and capped; the timing is decision 253's `MotionRule`s.

/// Fares a train took at a station within a step: what its trip was
/// credited with since the step began (``GameCore/TrainTrip/fare``),
/// where it last called.
public struct StationFare: Hashable, Sendable {
    public let station: StationID
    public let location: PlanPoint
    public let train: TrainID
    public let amount: Money

    public init(station: StationID, location: PlanPoint, train: TrainID, amount: Money) {
        self.station = station
        self.location = location
        self.train = train
        self.amount = amount
    }

    /// The fares taken within the step from `before` to `after`, by train
    /// then station (``TrainTrip/fare`` is credited at the call the riders
    /// get on). Only trips still open before the step, or opened within it,
    /// can have been credited; a trip that closed within it counts what it
    /// took before it closed. Under a dollar is left out: "+$0" says nothing.
    public static func taken(from before: GameWorld, to after: GameWorld) -> [StationFare] {
        struct Key: Hashable {
            let train: TrainID
            let opened: GameTime
        }
        var earlier: [Key: Money] = [:]
        for trip in before.tripLog where trip.arrival == nil {
            if let first = trip.calls.first { earlier[Key(train: trip.train, opened: first.arrival)] = trip.fare }
        }
        let since = before.clock.now
        var fares: [StationFare] = []
        for trip in after.tripLog {
            if let arrival = trip.arrival, arrival <= since { continue }
            guard let first = trip.calls.first, let last = trip.calls.last else { continue }
            let was = earlier[Key(train: trip.train, opened: first.arrival)] ?? .zero
            let gained = trip.fare - was
            guard gained.amount >= 100, let point = after.station(id: last.station)?.point else { continue }
            fares.append(StationFare(station: last.station, location: point, train: trip.train, amount: gained))
        }
        return fares.sorted { ($0.train, $0.station) < ($1.train, $1.station) }
    }
}

/// The fares one step took, for the map (``FareFloatBoard``).
public struct FarePulse: Hashable, Sendable {
    public let fares: [StationFare]
    /// Counts up with each pulse, so the same fares twice are two pulses.
    public let serial: Int

    public init(fares: [StationFare], serial: Int) {
        self.fares = fares
        self.serial = serial
    }
}

/// The "+$12" floats over the stations (decision 256): one a station,
/// fares taken there within ``mergeWindow`` of it added to it, each gone
/// after ``lifetime``, at most ``maximum`` at once (the oldest go first).
/// Times are real seconds from any fixed start, given by the caller.
public struct FareFloatBoard: Hashable, Sendable {
    /// One float.
    public struct Mark: Hashable, Sendable, Identifiable {
        public let id: Int
        public let station: StationID
        public let location: PlanPoint
        public internal(set) var amount: Money
        public internal(set) var trains: Set<TrainID>
        /// When it appeared, in the caller's seconds.
        public let born: Double

        /// "+$12", "+$13.4k".
        public var text: String {
            "+" + TrainRoster.shortMoney(amount)
        }
    }

    /// Fares at a station within a second of its float join it.
    public static let mergeWindow = 1.0
    /// How long a float stays, in seconds: decision 253's `pop` in, a
    /// hold, its `cardOut` out (the design's 1.2 s).
    public static let lifetime = 1.2
    /// How long it holds between coming in and going.
    public static var hold: Double {
        lifetime - MotionRule.pop.seconds - MotionRule.cardOut.seconds
    }
    /// The most floats at once.
    public static let maximum = 12
    /// At 600× and faster, the stations shown besides the followed train's:
    /// the ones nearest the middle of the map.
    public static let fastStations = 3

    public private(set) var floats: [Mark] = []
    private var nextID = 1

    public init() {}

    /// Adds `fares`, taken at `now`, and drops the floats gone by then.
    public mutating func add(_ fares: [StationFare], at now: Double) {
        expire(at: now)
        for fare in fares {
            if let index = floats.firstIndex(where: { $0.station == fare.station && now - $0.born < Self.mergeWindow }) {
                floats[index].amount = floats[index].amount + fare.amount
                floats[index].trains.insert(fare.train)
                continue
            }
            floats.append(Mark(id: nextID, station: fare.station, location: fare.location, amount: fare.amount, trains: [fare.train], born: now))
            nextID += 1
        }
        if floats.count > Self.maximum { floats.removeFirst(floats.count - Self.maximum) }
    }

    /// Drops the floats gone by `now`.
    public mutating func expire(at now: Double) {
        floats.removeAll { now - $0.born >= Self.lifetime }
    }

    /// The floats to draw. At 600× and faster (`fast`) only those of the
    /// followed train and of the ``fastStations`` stations nearest the
    /// middle of the map (`distance`, from it, in any unit), so the sky is
    /// not full of them; slower, all.
    public func shown(fast: Bool, followed: TrainID?, distance: (PlanPoint) -> Double) -> [Mark] {
        guard fast else { return floats }
        let central = Set(
            floats.map { ($0.station, distance($0.location)) }
                .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
                .prefix(Self.fastStations).map(\.0)
        )
        return floats.filter { float in
            central.contains(float.station) || followed.map { float.trains.contains($0) } == true
        }
    }

    /// Whether `speed` is fast enough to thin the floats: 600× and faster.
    public static func isFast(_ speed: GameSpeed) -> Bool {
        speed.tenthsPerTick >= GameSpeed.normal.tenthsPerTick
    }
}

/// Goals met within a step (decision 256): a challenge's goals and the
/// city's requests met, by title, for the check and the tune.
public struct GoalPulse: Hashable, Sendable {
    public let titles: [String]
    /// Counts up with each pulse.
    public let serial: Int

    public init(titles: [String], serial: Int) {
        self.titles = titles
        self.serial = serial
    }

    /// The titles of the goals met from `before` to `after`, in
    /// `language`: the challenge's (the same challenge, a goal without a
    /// day before and with one after) by goal, then the city's requests
    /// met (a result new since `before`, succeeded) by their order.
    public static func met(from before: GameWorld, to after: GameWorld, in language: DisplayLanguage) -> [String] {
        var titles: [String] = []
        if let was = before.scenario, let now = after.scenario, was.scenario.id == now.scenario.id {
            let indices = now.achieved.indices.filter { now.achieved[$0] != nil && was.achieved.indices.contains($0) && was.achieved[$0] == nil }
            if !indices.isEmpty {
                let progress = after.goalProgress(in: language)
                titles += indices.compactMap { progress.indices.contains($0) ? progress[$0].title : nil }
            }
        }
        if let results = after.cityRequests?.results, results != before.cityRequests?.results {
            let ended = Set(before.cityRequests?.results.map(\.request.id) ?? [])
            let met = results.filter { $0.succeeded && !ended.contains($0.request.id) }.map(\.request.id)
            if !met.isEmpty {
                let rows = after.cityRequestResults(in: language)
                titles += met.compactMap { id in rows.first { $0.id == id }?.title }
            }
        }
        return titles
    }

    /// What the chip says: "Goal met: Riders a day", or with several,
    /// "2 goals met".
    public func text(in language: DisplayLanguage) -> String {
        if titles.count == 1, let title = titles.first {
            return language.text("Goal met: \(title)", "目標達成：\(title)")
        }
        return language.text("\(titles.count) goals met", "達成 \(titles.count) 個目標")
    }

    /// How long the chip stays, in seconds, before it goes.
    public static let shownSeconds = 3.0
}

/// Towns that grew a step at the last midnight (decision 256): a warm ring
/// over each station.
public struct TownGrowthPulse: Hashable, Sendable {
    public let stations: [StationID]
    public let locations: [PlanPoint]
    /// Counts up with each pulse.
    public let serial: Int

    public init(stations: [StationID], locations: [PlanPoint], serial: Int) {
        self.stations = stations
        self.locations = locations
        self.serial = serial
    }

    /// A step of a town: each quarter of the daily trips it started with
    /// (``TownGrowth/Place/base``) that it has grown by. A town grows to at
    /// most four times its start, so twelve steps; at the best service, a
    /// step takes about two weeks.
    public static func step(dailyTrips: Int64, base: Int64) -> Int64 {
        guard base > 0, dailyTrips > base else { return 0 }
        return (dailyTrips - base) * 4 / base
    }

    /// The most rings a midnight: those that grew most (then by station).
    public static let maximum = 3

    /// A town as two worlds see it: its station, the daily trips growth
    /// started it at, its daily trips before and after, and how much it
    /// grew at the last midnight (thousandths).
    public struct Town: Hashable, Sendable {
        public let station: StationID
        public let base: Int64
        public let before: Int64
        public let after: Int64
        public let growth: Int64

        public init(station: StationID, base: Int64, before: Int64, after: Int64, growth: Int64) {
            self.station = station
            self.base = base
            self.before = before
            self.after = after
            self.growth = growth
        }
    }

    /// The stations of `towns` that are a step higher after than before,
    /// the most grown first (then by station), at most ``maximum``.
    public static func grown(_ towns: [Town]) -> [StationID] {
        towns.filter { step(dailyTrips: $0.after, base: $0.base) > step(dailyTrips: $0.before, base: $0.base) }
            .sorted { ($1.growth, $0.station) < ($0.growth, $1.station) }
            .prefix(maximum).map(\.station)
    }

    /// ``grown(_:)`` of the towns growth knows in `after`, with their daily
    /// trips in `before`. A station whose ridership the player set has no
    /// place until the next midnight sees it again, from the new trips.
    public static func grown(from before: GameWorld, to after: GameWorld) -> [StationID] {
        guard let places = after.townGrowth?.places else { return [] }
        return grown(places.compactMap { place in
            guard let was = before.stationDemand(of: place.station)?.dailyTrips,
                  let now = after.stationDemand(of: place.station)?.dailyTrips else { return nil }
            return Town(station: place.station, base: place.base, before: was, after: now, growth: place.lastGrowth)
        })
    }
}

extension GameSession {
    /// Decision 256: what a step did that the map answers: fares over
    /// the stations, goals met (the tune), towns grown a step at
    /// midnight. Called after the step with the world before it.
    func noteActions(since before: GameWorld) {
        let fares = StationFare.taken(from: before, to: world)
        if !fares.isEmpty {
            farePulse = FarePulse(fares: fares, serial: (farePulse?.serial ?? 0) + 1)
        }
        let titles = GoalPulse.met(from: before, to: world, in: language)
        if !titles.isEmpty {
            goalPulse = GoalPulse(titles: titles, serial: (goalPulse?.serial ?? 0) + 1)
            playSound?(.goalMet)
        }
        if world.clock.now.seconds / GameTime.secondsPerDay > before.clock.now.seconds / GameTime.secondsPerDay {
            let grown = TownGrowthPulse.grown(from: before, to: world)
            let located = grown.compactMap { id in world.station(id: id).map { (id, $0.point) } }
            if !located.isEmpty {
                townPulse = TownGrowthPulse(
                    stations: located.map(\.0), locations: located.map(\.1), serial: (townPulse?.serial ?? 0) + 1
                )
            }
        }
    }
}
