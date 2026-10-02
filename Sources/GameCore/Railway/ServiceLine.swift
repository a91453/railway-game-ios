/// Stable identifier of a service line, unique within a ``GameWorld``.
///
/// IDs are allocated sequentially by the world (never reused), so the same
/// sequence of actions always yields the same IDs.
public struct LineID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: LineID, rhs: LineID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How busy a time of day is, which sets how many trains a line runs then
/// (see ``TrainsInService``). Which minutes of the day have which level is
/// the world's ``ServiceDay``.
public enum ServiceLevel: String, CaseIterable, Codable, Sendable {
    case peak
    case offPeak
    case low
}

extension GameTime {
    /// Game minutes in a day. Game time has no calendar; days only group
    /// minutes for service planning and display.
    public static let minutesPerDay: Int64 = 24 * 60

    /// The minute of the day, `0..<1440`, counting from the start of the
    /// day that contains this second (also before second 0).
    public var minuteOfDay: Int {
        let minute = self.minute % Self.minutesPerDay
        return Int(minute < 0 ? minute + Self.minutesPerDay : minute)
    }
}

/// When a line runs during the day: all day, or from `open` to `close`,
/// both minutes of the day, where `close` may run into the next morning.
///
/// A window from `open` to `close` contains minute of the day `m` when
/// `open <= m < close`, counting minutes before `open` as the next day's
/// (`m + 1440`): a window from 06:00 to 25:00 (`360` to `1500`) runs until
/// 01:00 the next morning. `open` is in `0...1439`, `close` is later than
/// `open` and no later than ``latestClose`` (06:00 the next morning).
public enum ServiceWindow: Hashable, Sendable {
    case allDay
    case hours(open: Int, close: Int)

    /// The latest a window may close: 06:00 the next morning.
    public static let latestClose = 1800

    /// From 06:00 to midnight, the window of a new line.
    public static let standard = ServiceWindow.hours(open: 360, close: 1440)

    /// Whether the window is one a line can have (see the type's rules).
    var isValid: Bool {
        switch self {
        case .allDay:
            true
        case .hours(let open, let close):
            (0...1439).contains(open) && open < close && close <= Self.latestClose
        }
    }

    /// Whether the line runs at `minuteOfDay` (`0..<1440`).
    ///
    /// - Precondition: the window is valid.
    public func contains(minuteOfDay minute: Int) -> Bool {
        switch self {
        case .allDay:
            return true
        case .hours(let open, let close):
            let counted = minute < open ? minute + 1440 : minute
            return open <= counted && counted < close
        }
    }
}

/// How many trains a line is to run at each ``ServiceLevel``. Each count is
/// 0 or more; a line never runs more than its journey allows (see
/// ``GameWorld/lineTrainsInService(_:at:pattern:)``).
public struct TrainsInService: Hashable, Sendable {
    public var peak: Int
    public var offPeak: Int
    public var low: Int

    public init(peak: Int, offPeak: Int, low: Int) {
        self.peak = peak
        self.offPeak = offPeak
        self.low = low
    }

    /// None at any level, as on a new line.
    public static let none = TrainsInService(peak: 0, offPeak: 0, low: 0)

    public subscript(level: ServiceLevel) -> Int {
        switch level {
        case .peak: peak
        case .offPeak: offPeak
        case .low: low
        }
    }

    var isValid: Bool {
        peak >= 0 && offPeak >= 0 && low >= 0
    }
}

/// The minutes a line aims to keep between its trains at each
/// ``ServiceLevel``, or `nil` at a level where the count in
/// ``TrainsInService`` sets the service instead (as at every level of a new
/// line).
///
/// A target is at least ``ServiceLine/minimumHeadwayMinutes`` and at most a
/// day (``GameTime/minutesPerDay``). At a level with a target the line runs
/// as few trains as keep to it, and a train that is back early waits at the
/// first stop (see ``GameWorld/lineTrainsInService(_:at:pattern:)``).
public struct TargetHeadways: Hashable, Sendable {
    public var peak: Int64?
    public var offPeak: Int64?
    public var low: Int64?

    public init(peak: Int64? = nil, offPeak: Int64? = nil, low: Int64? = nil) {
        self.peak = peak
        self.offPeak = offPeak
        self.low = low
    }

    /// No target at any level, as on a new line.
    public static let none = TargetHeadways()

    public subscript(level: ServiceLevel) -> Int64? {
        switch level {
        case .peak: peak
        case .offPeak: offPeak
        case .low: low
        }
    }

    var isValid: Bool {
        [peak, offPeak, low].allSatisfy { target in
            target.map { (ServiceLine.minimumHeadwayMinutes...GameTime.minutesPerDay).contains($0) } ?? true
        }
    }
}

/// Which ``ServiceLevel`` each minute of the day has, for every line of a
/// world: a list of bands, each starting at a minute of the day and lasting
/// until the next band starts (the last until midnight).
///
/// The first band starts at minute 0 and the starts strictly increase, so
/// every minute of the day has exactly one level.
public struct ServiceDay: Hashable, Sendable {
    /// A level from a minute of the day on.
    public struct Band: Hashable, Sendable {
        public let start: Int
        public let level: ServiceLevel

        public init(start: Int, level: ServiceLevel) {
            self.start = start
            self.level = level
        }
    }

    public let bands: [Band]

    public init(bands: [Band]) {
        self.bands = bands
    }

    /// Peak from 07:00 to 10:00 and 16:00 to 20:00, low from midnight to
    /// 07:00 and from 21:00, and off-peak otherwise: the day of the web
    /// reference (docs/WEB_REFERENCE_STUDY.md), and of every new world.
    public static let standard = ServiceDay(bands: [
        Band(start: 0, level: .low),
        Band(start: 420, level: .peak),
        Band(start: 600, level: .offPeak),
        Band(start: 960, level: .peak),
        Band(start: 1200, level: .offPeak),
        Band(start: 1260, level: .low),
    ])

    /// Whether the bands start at minute 0 and strictly increase within the
    /// day.
    var isValid: Bool {
        guard bands.first?.start == 0, let last = bands.last, last.start < 1440 else { return false }
        return zip(bands, bands.dropFirst()).allSatisfy { $0.start < $1.start }
    }

    /// The level at `minuteOfDay` (`0..<1440`).
    ///
    /// - Precondition: the day is valid.
    public func level(atMinuteOfDay minute: Int) -> ServiceLevel {
        bands.last { $0.start <= minute }!.level
    }
}

/// A further service of a line (Stage Q3): its trains call at some of the
/// line's stops, in the line's order, out from the first of them to the
/// last and back, turning round at both. Calling at a run of neighbouring
/// stops short of the ends makes a short working; leaving stops out makes
/// an express, which passes them. Which it is, is only in its calls.
///
/// Like the line's own service it has train counts or target headways at
/// each level and its own trains, which it sends out from its first call;
/// where it shares segments of the line with services before it, it runs
/// only as many trains as still fit (see
/// ``GameWorld/lineSegmentLoads(_:at:)``).
public struct LinePattern: Hashable, Sendable {
    /// The line's stops called at, as indices into ``ServiceLine/stops``:
    /// at least two, strictly increasing.
    public internal(set) var calls: [Int]
    public internal(set) var trainsInService: TrainsInService
    /// The minutes the pattern aims to keep between its trains, at the
    /// levels where it has a target (see ``TargetHeadways``).
    public internal(set) var targetHeadways: TargetHeadways
    /// The trains assigned to the pattern, in ascending ID order.
    public internal(set) var trains: [TrainID]
    /// When the pattern last sent a train out from its first call,
    /// or `nil` if it never has.
    public internal(set) var lastDispatch: GameTime?

    /// A pattern calling at `calls`, with no trains in service, no target
    /// headways and no trains assigned, as a new one has.
    public init(calls: [Int]) {
        self.calls = calls
        self.trainsInService = .none
        self.targetHeadways = .none
        self.trains = []
        self.lastDispatch = nil
    }

    /// Whether `calls` can be the calls of a pattern of a line with
    /// `stopCount` stops: at least two, strictly increasing, each an index
    /// of a stop.
    static func isCallList(_ calls: [Int], stopCount: Int) -> Bool {
        guard calls.count >= 2, calls[0] >= 0, calls[calls.count - 1] < stopCount else { return false }
        return zip(calls, calls.dropFirst()).allSatisfy { $0 < $1 }
    }
}

/// A service line: the stations its trains call at, in order, out from the
/// first and back from the last; the rate it plans its journeys at; when it
/// runs; how many trains it is to run at each level, or how far apart; and
/// the trains assigned to it.
///
/// The plan itself never moves or routes a train; what its trains would
/// take, and how often they could run, is derived by
/// ``GameWorld/lineJourney(_:pattern:)`` and the queries beside it. A line
/// sends out only the trains assigned to it, one round trip at a time (see
/// ``GameWorld/advance(ticks:)``).
///
/// Besides its own service, calling at every stop from end to end, a line
/// may run further ``patterns``: short workings and expresses over the same
/// stops, each with its own trains. Where services share a stretch of the
/// line, together they run no more trains than the minimum headway allows
/// (see ``GameWorld/lineSegmentLoads(_:at:)``).
public struct ServiceLine: Identifiable, Hashable, Sendable {
    public let id: LineID
    public internal(set) var name: String
    /// The stations called at, in order: at least two, and no station twice
    /// in a row. The trains run from the first to the last and back, turning
    /// round at both ends.
    public internal(set) var stops: [StationID]
    /// The rate, in logical units per game minute, that the line's journey
    /// times are worked out at (see ``TrainMovement``). At least 1.
    public internal(set) var rate: Int64
    public internal(set) var window: ServiceWindow
    public internal(set) var trainsInService: TrainsInService
    /// The minutes the line aims to keep between trains, at the levels
    /// where it has a target; the other levels run
    /// ``trainsInService``.
    public internal(set) var targetHeadways: TargetHeadways
    /// The trains assigned to the line, in ascending ID order. A train is
    /// assigned to one line at most, and the line runs its timetable and
    /// service (see ``GameWorld/assignTrain(_:to:pattern:)``).
    public internal(set) var trains: [TrainID]
    /// When the line last sent a train out from its first stop, or
    /// `nil` if it never has. The next train leaves a headway later at the
    /// earliest.
    public internal(set) var lastDispatch: GameTime?
    /// The line's further services, in the order they claim room on the
    /// line after its own (see ``LinePattern``). A new line has none.
    public internal(set) var patterns: [LinePattern]

    /// The rate of a new line: one link a minute.
    public static let defaultRate: Int64 = TrainPosition.linkLength
    /// Minutes a train stays at a stop between the ends of the line.
    public static let dwellMinutes: Int64 = 1
    /// Minutes a train stays at either end of the line, where it turns round.
    public static let terminalDwellMinutes: Int64 = 2
    /// The shortest time between two trains of a line: it never runs more
    /// trains than its round trip allows at this headway.
    public static let minimumHeadwayMinutes: Int64 = 2

    /// Creates a line with the standard window, the default rate, no trains
    /// in service, no target headways and no trains assigned.
    public init(id: LineID, name: String, stops: [StationID]) {
        self.id = id
        self.name = name
        self.stops = stops
        self.rate = Self.defaultRate
        self.window = .standard
        self.trainsInService = .none
        self.targetHeadways = .none
        self.trains = []
        self.lastDispatch = nil
        self.patterns = []
    }

    /// Whether `stops` can be a line's stops, judged without a world: at
    /// least two, and no station twice in a row.
    static func isStopList(_ stops: [StationID]) -> Bool {
        stops.count >= 2 && zip(stops, stops.dropFirst()).allSatisfy { $0 != $1 }
    }

    /// How many trains the line's own service runs at `level`, and the
    /// minutes between them, for a round trip of `roundTrip` minutes; `nil`
    /// when it runs none then. Other services on the line never take room
    /// from it (see ``services(at:roundTrips:)``).
    ///
    /// - Precondition: `roundTrip >= 1`, as every journey's is (it includes
    ///   a dwell at both ends).
    func service(at level: ServiceLevel, roundTrip: Int64) -> (trains: Int, headway: Int64)? {
        Self.service(trainsInService, targetHeadways, at: level, roundTrip: roundTrip)
    }

    /// How many trains a service with `counts` and `targets` runs at
    /// `level`, and the minutes between them, for a round trip of
    /// `roundTrip` minutes, on its own; `nil` when it runs none then.
    ///
    /// Never more trains than keep ``minimumHeadwayMinutes`` apart, and at
    /// least one: `max(1, roundTrip / 2)`. Without a target the count is
    /// the one set for the level, and the headway the round trip shared
    /// between the trains, rounded up. With a target the count is the
    /// fewest trains that keep to it (the round trip divided by the target,
    /// rounded up), and the headway the target, or longer when even that
    /// many trains is more than the service can run.
    ///
    /// - Precondition: `roundTrip >= 1`.
    static func service(
        _ counts: TrainsInService, _ targets: TargetHeadways, at level: ServiceLevel, roundTrip: Int64
    ) -> (trains: Int, headway: Int64)? {
        let maximum = Int(clamping: max(1, roundTrip / minimumHeadwayMinutes))
        let count: Int
        if let target = targets[level] {
            count = min(Int(clamping: dividedRoundingUp(roundTrip, by: target)), maximum)
        } else {
            count = min(counts[level], maximum)
        }
        guard count > 0 else { return nil }
        return (count, headway(of: count, roundTrip: roundTrip, target: targets[level]))
    }

    /// The minutes between `trains` trains (at least one) sharing a round
    /// trip of `roundTrip` minutes: the round trip shared between them,
    /// rounded up, or the target if that is longer.
    static func headway(of trains: Int, roundTrip: Int64, target: Int64?) -> Int64 {
        let shared = dividedRoundingUp(roundTrip, by: Int64(trains))
        return max(target ?? shared, shared)
    }

    /// The most trains a day each way that one segment of a line (from a
    /// stop to the next) carries, over all the line's services: one every
    /// ``minimumHeadwayMinutes``, 720.
    public static let segmentCapacity = Int(GameTime.minutesPerDay / minimumHeadwayMinutes)

    /// The load a service running a train every `headway` minutes puts on
    /// each segment it runs over: trains a day each way at that headway,
    /// rounded up, so that a share of the capacity is never undercounted.
    static func load(ofHeadway headway: Int64) -> Int {
        Int(dividedRoundingUp(GameTime.minutesPerDay, by: headway))
    }

    /// The number of services the line runs: its own and its patterns'.
    /// Service 0 is the line's own; service `k + 1` is pattern `k`.
    var serviceCount: Int {
        1 + patterns.count
    }

    /// The service that `pattern` names: 0, the line's own, for `nil`, or
    /// `pattern + 1`; `nil` when the line has no such pattern.
    func service(_ pattern: Int?) -> Int? {
        guard let pattern else { return 0 }
        return patterns.indices.contains(pattern) ? pattern + 1 : nil
    }

    /// The indices, in ``stops``, of the calls of service `service` (see
    /// ``serviceCount``): every stop for the line's own.
    func calls(ofService service: Int) -> [Int] {
        service == 0 ? Array(stops.indices) : patterns[service - 1].calls
    }

    /// The trains assigned to service `service` (see ``serviceCount``).
    func trains(ofService service: Int) -> [TrainID] {
        service == 0 ? trains : patterns[service - 1].trains
    }

    /// When service `service` (see ``serviceCount``) last sent a train out.
    func lastDispatch(ofService service: Int) -> GameTime? {
        service == 0 ? lastDispatch : patterns[service - 1].lastDispatch
    }

    /// Records that service `service` (see ``serviceCount``) sent a train
    /// out at `time`.
    mutating func recordDispatch(ofService service: Int, at time: GameTime) {
        if service == 0 {
            lastDispatch = time
        } else {
            patterns[service - 1].lastDispatch = time
        }
    }

    /// What the line's first `roundTrips.count` services run at `level`,
    /// and the load they put on each segment of the line:
    /// `roundTrips[k]` is service `k`'s round trip (see ``serviceCount``),
    /// or `nil` when its journey cannot be driven and it runs none.
    ///
    /// The services claim room in order, so the line's own service is
    /// never cut. Each asks for what it would run on its own (see
    /// ``service(_:_:at:roundTrip:)``), and runs the most trains, up to
    /// that many, whose load (see ``load(ofHeadway:)``) still fits on
    /// every segment it runs over, from its first call to its last,
    /// passing stops or not, beside what the services before it put there:
    /// the frequencies of services sharing a segment add up, and never
    /// past ``segmentCapacity``. A service left with no room runs none.
    ///
    /// - Precondition: `roundTrips.count <= serviceCount`, each at least 1.
    func services(at level: ServiceLevel, roundTrips: [Int64?]) -> (plans: [(trains: Int, headway: Int64)?], loads: [Int]) {
        var loads = Array(repeating: 0, count: stops.count - 1)
        var plans: [(trains: Int, headway: Int64)?] = []
        for (service, roundTrip) in roundTrips.enumerated() {
            let (counts, targets) = service == 0
                ? (trainsInService, targetHeadways)
                : (patterns[service - 1].trainsInService, patterns[service - 1].targetHeadways)
            let calls = calls(ofService: service)
            let span = calls[0]..<calls[calls.count - 1]
            guard let roundTrip, let wanted = Self.service(counts, targets, at: level, roundTrip: roundTrip) else {
                plans.append(nil)
                continue
            }
            let room = span.map { Self.segmentCapacity - loads[$0] }.min()!
            // Fewer trains never load a segment more: find the most that fit.
            var (fits, tooMany) = (0, wanted.trains + 1)
            while tooMany - fits > 1 {
                let middle = fits + (tooMany - fits) / 2
                if Self.load(ofHeadway: Self.headway(of: middle, roundTrip: roundTrip, target: targets[level])) <= room {
                    fits = middle
                } else {
                    tooMany = middle
                }
            }
            guard fits > 0 else {
                plans.append(nil)
                continue
            }
            let headway = Self.headway(of: fits, roundTrip: roundTrip, target: targets[level])
            for segment in span {
                loads[segment] += Self.load(ofHeadway: headway)
            }
            plans.append((fits, headway))
        }
        return (plans, loads)
    }

    /// `value / divisor`, rounded up. Both are positive.
    static func dividedRoundingUp(_ value: Int64, by divisor: Int64) -> Int64 {
        value / divisor + (value % divisor == 0 ? 0 : 1)
    }

    /// The start of the first minute after the one `now` is in at which
    /// this line's window opens or closes or a band of `day` starts,
    /// whichever comes first; `nil` if none of them fits in a ``GameTime``.
    /// Between two such minutes the line's window and level stay the same.
    func nextChange(after now: GameTime, in day: ServiceDay) -> GameTime? {
        var minutesOfDay = day.bands.map(\.start)
        if case .hours(let open, let close) = window {
            minutesOfDay += [open, close % Int(GameTime.minutesPerDay)]
        }
        let today = Int64(now.minuteOfDay)
        return minutesOfDay.compactMap { minute -> GameTime? in
            // Always a whole day ahead at the most, never now itself.
            let ahead = (Int64(minute) - today + GameTime.minutesPerDay - 1) % GameTime.minutesPerDay + 1
            let (minute, overflow) = now.minute.addingReportingOverflow(ahead)
            let (time, beyond) = minute.multipliedReportingOverflow(by: GameTime.secondsPerMinute)
            return overflow || beyond ? nil : GameTime(seconds: time)
        }.min()
    }
}

// MARK: - Codable

extension ServiceWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case open, close
    }

    /// Decodes `"allDay"` or `{"open", "close"}`, rejecting a window no line
    /// can have rather than repairing it.
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            guard text == "allDay" else {
                throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unknown service window \"\(text)\".")
            }
            self = .allDay
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .hours(open: try container.decode(Int.self, forKey: .open), close: try container.decode(Int.self, forKey: .close))
        guard isValid else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A service window opens in 0...1439 and closes after it, by 1800."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .allDay:
            var container = encoder.singleValueContainer()
            try container.encode("allDay")
        case .hours(let open, let close):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(open, forKey: .open)
            try container.encode(close, forKey: .close)
        }
    }
}

extension TrainsInService: Codable {
    private enum CodingKeys: String, CodingKey {
        case peak, offPeak, low
    }

    /// Decodes `{"peak", "offPeak", "low"}`, rejecting a negative count.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            peak: try container.decode(Int.self, forKey: .peak),
            offPeak: try container.decode(Int.self, forKey: .offPeak),
            low: try container.decode(Int.self, forKey: .low)
        )
        guard isValid else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath, debugDescription: "Trains in service cannot be negative."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(peak, forKey: .peak)
        try container.encode(offPeak, forKey: .offPeak)
        try container.encode(low, forKey: .low)
    }
}

extension TargetHeadways: Codable {
    private enum CodingKeys: String, CodingKey {
        case peak, offPeak, low
    }

    /// Decodes `{"peak", "offPeak", "low"}`, each present only at a level
    /// with a target. An explicit `null`, or a target outside `2...1440`,
    /// is rejected.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func target(_ key: CodingKeys) throws -> Int64? {
            container.contains(key) ? try container.decode(Int64.self, forKey: key) : nil
        }
        self.init(peak: try target(.peak), offPeak: try target(.offPeak), low: try target(.low))
        guard isValid else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath, debugDescription: "A target headway is 2 to 1440 minutes."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(peak, forKey: .peak)
        try container.encodeIfPresent(offPeak, forKey: .offPeak)
        try container.encodeIfPresent(low, forKey: .low)
    }
}

extension ServiceDay: Codable {
    /// Decodes a list of `{"start", "level"}`, rejecting a day whose bands
    /// do not start at minute 0 or do not strictly increase within the day.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(bands: try container.decode([Band].self))
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A service day's bands start at minute 0 and strictly increase within the day."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bands)
    }
}

extension ServiceDay.Band: Codable {}

extension ServiceLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, stops, rate, window, trainsInService, targetHeadways, trains, lastDispatch, patterns
    }

    /// Decodes a line, rejecting stops, a rate, a window, train counts or
    /// target headways no line can have, trains listed out of order or
    /// twice, or a dispatch before second 0, rather than repairing them.
    /// A line without targets has no `"targetHeadways"` key, one without
    /// trains no `"trains"`, and one that never sent a train out no
    /// `"lastDispatch"`, which is also how lines saved before they could
    /// dispatch read; an explicit `null` is rejected. A line without
    /// patterns has no `"patterns"` key, as lines saved before patterns
    /// existed read; a pattern calling at a stop the line does not have is
    /// rejected. That the stations and trains exist, that no train is on
    /// two lines or services and that no dispatch is after the clock are
    /// checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LineID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        stops = try container.decode([StationID].self, forKey: .stops)
        rate = try container.decode(Int64.self, forKey: .rate)
        window = try container.decode(ServiceWindow.self, forKey: .window)
        trainsInService = try container.decode(TrainsInService.self, forKey: .trainsInService)
        targetHeadways = container.contains(.targetHeadways) ? try container.decode(TargetHeadways.self, forKey: .targetHeadways) : .none
        trains = container.contains(.trains) ? try container.decode([TrainID].self, forKey: .trains) : []
        lastDispatch = container.contains(.lastDispatch) ? try container.decode(GameTime.self, forKey: .lastDispatch) : nil
        patterns = container.contains(.patterns) ? try container.decode([LinePattern].self, forKey: .patterns) : []
        guard Self.isStopList(stops) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stops, in: container, debugDescription: "Line \(id.rawValue) needs two stops or more, none twice in a row."
            )
        }
        guard rate >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .rate, in: container, debugDescription: "Line \(id.rawValue)'s rate must be at least 1.")
        }
        guard zip(trains, trains.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .trains, in: container, debugDescription: "Line \(id.rawValue)'s trains must be listed once each, in ascending order."
            )
        }
        guard (lastDispatch?.seconds ?? 0) >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastDispatch, in: container, debugDescription: "Line \(id.rawValue) cannot have sent a train out before second 0."
            )
        }
        guard patterns.allSatisfy({ LinePattern.isCallList($0.calls, stopCount: stops.count) }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .patterns, in: container, debugDescription: "Line \(id.rawValue) has a pattern calling at a stop it does not have."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(stops, forKey: .stops)
        try container.encode(rate, forKey: .rate)
        try container.encode(window, forKey: .window)
        try container.encode(trainsInService, forKey: .trainsInService)
        if targetHeadways != .none {
            try container.encode(targetHeadways, forKey: .targetHeadways)
        }
        if !trains.isEmpty {
            try container.encode(trains, forKey: .trains)
        }
        try container.encodeIfPresent(lastDispatch, forKey: .lastDispatch)
        if !patterns.isEmpty {
            try container.encode(patterns, forKey: .patterns)
        }
    }
}

extension LinePattern: Codable {
    private enum CodingKeys: String, CodingKey {
        case calls, trainsInService, targetHeadways, trains, lastDispatch
    }

    /// Decodes a pattern, rejecting calls that are fewer than two or not
    /// strictly increasing from 0 up, train counts or target headways no
    /// service can have, trains listed out of order or twice, or a dispatch
    /// before second 0. As on a line, `"targetHeadways"`, `"trains"` and
    /// `"lastDispatch"` are present only when used, and an explicit `null`
    /// is rejected. That the calls fit the line is checked by the line's
    /// decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calls = try container.decode([Int].self, forKey: .calls)
        trainsInService = try container.decode(TrainsInService.self, forKey: .trainsInService)
        targetHeadways = container.contains(.targetHeadways) ? try container.decode(TargetHeadways.self, forKey: .targetHeadways) : .none
        trains = container.contains(.trains) ? try container.decode([TrainID].self, forKey: .trains) : []
        lastDispatch = container.contains(.lastDispatch) ? try container.decode(GameTime.self, forKey: .lastDispatch) : nil
        guard Self.isCallList(calls, stopCount: .max) else {
            throw DecodingError.dataCorruptedError(
                forKey: .calls, in: container, debugDescription: "A pattern calls at two stops or more, in strictly increasing order."
            )
        }
        guard zip(trains, trains.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .trains, in: container, debugDescription: "A pattern's trains must be listed once each, in ascending order."
            )
        }
        guard (lastDispatch?.seconds ?? 0) >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastDispatch, in: container, debugDescription: "A pattern cannot have sent a train out before second 0."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(calls, forKey: .calls)
        try container.encode(trainsInService, forKey: .trainsInService)
        if targetHeadways != .none {
            try container.encode(targetHeadways, forKey: .targetHeadways)
        }
        if !trains.isEmpty {
            try container.encode(trains, forKey: .trains)
        }
        try container.encodeIfPresent(lastDispatch, forKey: .lastDispatch)
    }
}
