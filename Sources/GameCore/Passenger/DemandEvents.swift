// Demand events (item 4 of the author's order), after the owner's `Ci/`
// reference (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` and
// `aviation_disruptions__q_dc8f79f5de24b024.js`):
//
// - an event raises one station's demand by a boost while it lasts, and the
//   station's demand is `1 + boost` times its own
//   (`metroEventDemandMultiplier`); a station's travellers to it are raised
//   alike (the reference raises a station's flows);
// - the kinds are the metro game's exhibition and crowd surge
//   (`metro.event.exhibition` 大型展览, `metro.event.crowdSurge` 大客流事件),
//   announced days before they start ("{wait} days until start, lasts
//   {days} days");
// - the station is drawn by its traffic, the busiest fifth weighing ten
//   times as much (`metroEventStationTrafficWeights`);
// - the draws come from a hash of the world's seed and a key, FNV-1a over
//   `seed|key` (`aviation_disruptions`' `d(state, key)`), so a save gives
//   the same events however the game is played back;
// - the first event comes 3 to 7 days in and the next 8 to 12 days after
//   each draw (`aviation_disruptions`' cadence, 300,000–600,000 s and
//   720,000–1,080,000 s), sooner with more stations (`/ max(1, n / 10)`).
//
// The metro generator itself (`MetroEconomy.advanceMetroEvents`) is not in
// the snapshot, so the lengths and boosts are this project's (gap): an
// exhibition lasts 3 to 7 days at +20 % to +50 % and a crowd surge 1 to 2
// days at +50 % to +100 %, each announced 2 to 5 days ahead. Events run in
// whole days, so a day's release plan covers them.

/// What brings the crowd.
public enum DemandEventKind: String, CaseIterable, Codable, Sendable {
    /// A large exhibition near the station (大型展覽).
    case exhibition
    /// A crowd surge, such as a concert or a match (大客流事件).
    case crowdSurge
}

/// One station's demand raised for some whole days.
public struct DemandEvent: Hashable, Codable, Sendable {
    public let kind: DemandEventKind
    public let station: StationID
    /// The day it was announced.
    public let announced: Int64
    /// The first day it runs, and the day after its last.
    public let start: Int64
    public let end: Int64
    /// How much it adds to the station's demand, in thousandths.
    public let boost: Int64

    public init(kind: DemandEventKind, station: StationID, announced: Int64, start: Int64, end: Int64, boost: Int64) {
        self.kind = kind
        self.station = station
        self.announced = announced
        self.start = start
        self.end = end
        self.boost = boost
    }

    /// Whether it runs on game day `day`.
    public func isActive(onDay day: Int64) -> Bool {
        start <= day && day < end
    }

    var isValid: Bool {
        // Checked without overflow: a save's days may be anything.
        guard announced <= start, start < end, (1...2_000).contains(boost) else { return false }
        let (days, overflow) = end.subtractingReportingOverflow(start)
        return !overflow && days <= 30
    }
}

/// The events of a world that has them: the seed they are drawn from, the
/// events announced and not yet over, and when the next is drawn.
public struct DemandEventSchedule: Hashable, Codable, Sendable {
    public let seed: UInt32
    /// Announced and not yet over, in the order they were drawn.
    public internal(set) var events: [DemandEvent]
    /// The day the next event is drawn.
    public internal(set) var nextDraw: Int64
    /// How many draws there have been: each draw's keys are its number.
    public internal(set) var draws: Int64

    init(seed: UInt32, from day: Int64) {
        self.seed = seed
        events = []
        draws = 0
        nextDraw = day
        nextDraw += roll("first", in: 3...7)
    }

    /// FNV-1a, 32 bits, over the UTF-8 of `seed|key` (`aviation_disruptions`).
    func hash(_ key: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        for byte in "\(seed)|\(key)".utf8 {
            value ^= UInt32(byte)
            value = value &* 16_777_619
        }
        return value
    }

    /// A whole number in `range`, from the hash of `key`.
    func roll(_ key: String, in range: ClosedRange<Int64>) -> Int64 {
        range.lowerBound + Int64(hash(key)) % (range.upperBound - range.lowerBound + 1)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns demand events on, drawn from `seed`, or off with `nil` (which
    /// ends every event). Turning them on again starts a new schedule.
    public mutating func setDemandEvents(seed: UInt32?) {
        guard let seed else {
            guard demandEvents != nil else { return }
            demandEvents = nil
            passengerPlan = PassengerPlanCache()
            return
        }
        guard demandEvents?.seed != seed else { return }
        demandEvents = DemandEventSchedule(seed: seed, from: dayIndex(of: clock.now))
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    /// The events running at station `id` today.
    public func activeDemandEvents(at id: StationID) -> [DemandEvent] {
        let day = dayIndex(of: clock.now)
        return demandEvents?.events.filter { $0.station == id && $0.isActive(onDay: day) } ?? []
    }

    /// How much station `id`'s demand is raised today, in thousandths of
    /// its own: 1000, or 1000 + the largest boost running there
    /// (`metroEventDemandMultiplier`, `1 + max(boost)`).
    public func demandMultiplier(at id: StationID) -> Int64 {
        guard let schedule = demandEvents else { return 1_000 }
        let day = dayIndex(of: clock.now)
        return 1_000 + schedule.events.reduce(0) { $1.station == id && $1.isActive(onDay: day) ? max($0, $1.boost) : $0 }
    }

    // MARK: - Days

    /// The start of game day `day`, at midnight: events over by then end,
    /// and the next event is drawn when its day has come.
    mutating func startDemandEventDay(_ day: Int64) {
        guard var schedule = demandEvents else { return }
        schedule.events.removeAll { $0.end <= day }
        if schedule.nextDraw <= day {
            if let event = drawDemandEvent(schedule, on: day) {
                schedule.events.append(event)
            }
            let stations = Int64(passengers.count { ($0.demand?.dailyTrips ?? 0) > 0 })
            let gap = schedule.roll("gap.\(schedule.draws)", in: 8...12)
            schedule.nextDraw = day + max(1, gap / max(1, stations / 10))
            schedule.draws += 1
        }
        demandEvents = schedule
    }

    /// The event of draw `schedule.draws`, at a station drawn by its
    /// traffic, or `nil` with no station that has demand.
    private func drawDemandEvent(_ schedule: DemandEventSchedule, on day: Int64) -> DemandEvent? {
        let draw = schedule.draws
        // The reference weighs each station's flow, the busiest fifth ten
        // times over (`metroEventStationTrafficWeights`).
        let flows = passengers.compactMap { record -> (StationID, Int64)? in
            guard let trips = record.demand?.dailyTrips, trips > 0 else { return nil }
            return (record.station, trips)
        }
        guard !flows.isEmpty else { return nil }
        let ranked = flows.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        let busiest = ranked[(ranked.count + 4) / 5 - 1].1
        let weights = flows.map { $0.1 * ($0.1 >= busiest ? 10 : 1) }
        var pick = schedule.roll("event.\(draw).station", in: 0...(weights.reduce(0, +) - 1))
        var station = flows[0].0
        for (index, weight) in weights.enumerated() {
            if pick < weight {
                station = flows[index].0
                break
            }
            pick -= weight
        }
        let kind: DemandEventKind = schedule.roll("event.\(draw).kind", in: 0...1) == 0 ? .exhibition : .crowdSurge
        let start = day + schedule.roll("event.\(draw).wait", in: 2...5)
        let days = kind == .exhibition ? schedule.roll("event.\(draw).days", in: 3...7) : schedule.roll("event.\(draw).days", in: 1...2)
        let boost = kind == .exhibition
            ? schedule.roll("event.\(draw).boost", in: 200...500)
            : schedule.roll("event.\(draw).boost", in: 500...1_000)
        return DemandEvent(kind: kind, station: station, announced: day, start: start, end: start + days, boost: boost)
    }

    // MARK: - Validation

    /// Why the events break a rule, or `nil`: each is well formed, at a
    /// station that exists, announced by today and not yet over, and the
    /// draws counted are no more than one a day could make (2^40 days are
    /// beyond any game), so counting the next never overflows.
    func demandEventProblem() -> String? {
        guard let schedule = demandEvents else { return nil }
        let day = dayIndex(of: clock.now)
        guard (0...(1 << 40)).contains(schedule.draws), schedule.events.count <= 64 else { return "The demand events are out of range." }
        for event in schedule.events {
            guard event.isValid, station(id: event.station) != nil, event.announced <= day, day <= event.end else {
                return "A demand event is not one the game could have drawn."
            }
        }
        return nil
    }
}
