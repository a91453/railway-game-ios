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
//
// Decision 730 (DEMAND-HOURS, after the rule of the owner's own earlier
// game, whose scenarios wrote a crowd "from 19:00 to 22:00, so many an
// hour"): a crowd surge has the hours it is held, opening between 17:00
// and 19:00 and lasting 2 to 3½ hours, on the half hour. Its extra
// travellers no longer spread over the day: those coming to it set out
// around half an hour before it opens, and those leaving it around half
// an hour after it closes. The day's trips are the same as before; only
// their hours move. Exhibitions and festivals keep running all day.

/// What brings the crowd.
public enum DemandEventKind: String, CaseIterable, Codable, Sendable {
    /// A large exhibition near the station (大型展覽).
    case exhibition
    /// A crowd surge, such as a concert or a match (大量人潮事件).
    case crowdSurge
    /// A festival a scenario holds on the same day every year, such as the
    /// Pingxi Sky Lantern Festival (decision 90): never drawn.
    case festival
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
    /// The named festival it is, for a festival held at a place on the map
    /// (decision 576): `nil` for the others.
    public let festival: FestivalKind?
    /// Decision 730: the minute of the day it opens and the minute it
    /// closes, each day it runs, on the half hour; both `nil` for one that
    /// runs all day (every event of a save before version 96).
    public let opens: Int64?
    public let closes: Int64?

    /// The earliest an event with hours opens and the latest it closes, so
    /// that its crowd's hour before and hour after stay inside the day.
    public static let earliestOpening: Int64 = 120
    public static let latestClosing: Int64 = 1_350

    public init(
        kind: DemandEventKind, station: StationID, announced: Int64, start: Int64, end: Int64, boost: Int64, festival: FestivalKind? = nil,
        opens: Int64? = nil, closes: Int64? = nil
    ) {
        self.festival = festival
        self.opens = opens
        self.closes = closes
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
        switch (opens, closes) {
        case (nil, nil): break
        case let (opens?, closes?):
            guard Self.earliestOpening <= opens, opens < closes, closes <= Self.latestClosing,
                  opens % 30 == 0, closes % 30 == 0 else { return false }
        default: return false
        }
        let (days, overflow) = end.subtractingReportingOverflow(start)
        return !overflow && days <= 30
    }
}

/// The events of a world that has them: the seed they are drawn from, the
/// events announced and not yet over, and when the next is drawn.
public struct DemandEventSchedule: Hashable, Sendable {
    public let seed: UInt32
    /// Announced and not yet over, in the order they were drawn.
    public internal(set) var events: [DemandEvent]
    /// The day the next event is drawn.
    public internal(set) var nextDraw: Int64
    /// How many draws there have been: each draw's keys are its number.
    public internal(set) var draws: Int64

    /// The places the named festivals are held at (decision 576).
    public internal(set) var sites: [FestivalSite] = []

    /// The most draws a save counts: more than one a day could make in any
    /// game, so counting them never overflows.
    static let maximumDraws: Int64 = 1 << 40
    /// The most events a save holds at once.
    static let maximumEvents = 64

    /// The most places a save holds: one for each festival.
    static let maximumSites = FestivalKind.allCases.count

    init(seed: UInt32, from day: Int64) {
        self.seed = seed
        events = []
        draws = 0
        nextDraw = day
        nextDraw += roll("first", in: 3...7)
    }

    /// FNV-1a, 32 bits, over the UTF-8 of `seed|key` (`aviation_disruptions`).
    func hash(_ key: String) -> UInt32 {
        SeedDraw(seed: seed).hash(key)
    }

    /// A whole number in `range`, from the hash of `key`.
    func roll(_ key: String, in range: ClosedRange<Int64>) -> Int64 {
        SeedDraw(seed: seed).roll(key, in: range)
    }
}

extension DemandEventSchedule: Codable {
    private enum CodingKeys: String, CodingKey {
        case seed, events, nextDraw, draws, sites
    }

    /// A save before version 84 has no `"sites"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seed = try container.decode(UInt32.self, forKey: .seed)
        events = try container.decode([DemandEvent].self, forKey: .events)
        nextDraw = try container.decode(Int64.self, forKey: .nextDraw)
        draws = try container.decode(Int64.self, forKey: .draws)
        sites = try container.decodeIfPresent([FestivalSite].self, forKey: .sites) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seed, forKey: .seed)
        try container.encode(events, forKey: .events)
        try container.encode(nextDraw, forKey: .nextDraw)
        try container.encode(draws, forKey: .draws)
        if !sites.isEmpty {
            try container.encode(sites, forKey: .sites)
        }
    }
}

/// Draws from a world's seed (the cross-stage rule: a seed, a purpose and a
/// number, hashed): FNV-1a, 32 bits, over the UTF-8 of `seed|key`, the
/// reference's `aviation_disruptions` `d(state, key)`. The demand events
/// and the towns of a blank map (``Land/towns(seed:in:)``) draw with it.
struct SeedDraw {
    let seed: UInt32

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
        let sites = demandEvents?.sites ?? []
        demandEvents = DemandEventSchedule(seed: seed, from: dayIndex(of: clock.now))
        demandEvents?.sites = sites
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
        demandMultiplier(at: id, onDay: dayIndex(of: clock.now))
    }

    /// The same on game day `day`, of the events kept now: one that ended
    /// at the last midnight is gone.
    func demandMultiplier(at id: StationID, onDay day: Int64) -> Int64 {
        guard let schedule = demandEvents else { return 1_000 }
        return 1_000 + schedule.events.reduce(0) { $1.station == id && $1.isActive(onDay: day) ? max($0, $1.boost) : $0 }
    }

    /// Decision 730: at each station, the event that sets its demand on
    /// game day `day` (the largest boost there, the first drawn of equal
    /// ones), when it has hours. Empty without events with hours.
    func timedDemandEvents(onDay day: Int64) -> [StationID: DemandEvent] {
        guard let schedule = demandEvents else { return [:] }
        var largest: [StationID: DemandEvent] = [:]
        for event in schedule.events where event.isActive(onDay: day) {
            if let kept = largest[event.station], kept.boost >= event.boost { continue }
            largest[event.station] = event
        }
        return largest.filter { $0.value.opens != nil }
    }

    // MARK: - Days

    /// The start of game day `day`, at midnight: events over by then end,
    /// and the next event is drawn when its day has come.
    mutating func startDemandEventDay(_ day: Int64) {
        guard var schedule = demandEvents else { return }
        schedule.events.removeAll { $0.end <= day }
        // Decision 90: the scenario's festivals, announced their notice
        // before they start, every year, at stations still standing.
        if let state = scenario {
            for festival in state.scenario.events where station(id: festival.station) != nil {
                let start = day + festival.notice
                // Decision 576: one that follows a named festival starts
                // when that festival's year-by-year date says.
                let isStart = festival.follows?.starts(onDay: start)
                    ?? (CompanyAccounts.floorDivide(start - festival.dayOfYear, FinancePeriod.year.days) * FinancePeriod.year.days
                        == start - festival.dayOfYear)
                guard start > state.startDay, isStart,
                      schedule.events.count < DemandEventSchedule.maximumEvents else { continue }
                schedule.events.append(DemandEvent(
                    kind: .festival, station: festival.station, announced: day, start: start, end: start + festival.days, boost: festival.boost
                ))
            }
        }
        // Decision 576: the named festivals at their places.
        for event in namedFestivalEvents(on: day, sites: schedule.sites) where schedule.events.count < DemandEventSchedule.maximumEvents {
            schedule.events.append(event)
        }
        // A save counts at most 2^40 draws (``demandEventProblem()``): the
        // last it may count is the last.
        if schedule.nextDraw <= day, schedule.draws < DemandEventSchedule.maximumDraws {
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
        guard kind == .crowdSurge else {
            return DemandEvent(kind: kind, station: station, announced: day, start: start, end: start + days, boost: boost)
        }
        // Decision 730: a concert or a match in the evening, opening at
        // 17:00 to 19:00 and lasting 2 to 3½ hours, on the half hour.
        let opens = 1_020 + 30 * schedule.roll("event.\(draw).opens", in: 0...4)
        let closes = opens + 120 + 30 * schedule.roll("event.\(draw).hours", in: 0...3)
        return DemandEvent(kind: kind, station: station, announced: day, start: start, end: start + days, boost: boost,
                           opens: opens, closes: closes)
    }

    // MARK: - Validation

    /// Why the events break a rule, or `nil`: each is well formed, at a
    /// station that exists, announced by today and not yet over, and the
    /// draws counted are no more than one a day could make (2^40 days are
    /// beyond any game), so counting the next never overflows.
    func demandEventProblem() -> String? {
        guard let schedule = demandEvents else { return nil }
        let day = dayIndex(of: clock.now)
        guard (0...DemandEventSchedule.maximumDraws).contains(schedule.draws), schedule.events.count <= DemandEventSchedule.maximumEvents else { return "The demand events are out of range." }
        guard schedule.sites.count <= DemandEventSchedule.maximumSites, Set(schedule.sites.map(\.kind)).count == schedule.sites.count,
              schedule.sites.allSatisfy({ (0..<bounds.width).contains($0.point.x) && (0..<bounds.height).contains($0.point.y) })
        else { return "A festival place is out of range." }
        for event in schedule.events {
            guard event.isValid, station(id: event.station) != nil, event.announced <= day, day <= event.end else {
                return "A demand event is not one the game could have drawn."
            }
        }
        return nil
    }
}
