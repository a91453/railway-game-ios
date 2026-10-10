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
    /// Shared directed physical paths for this service (decision 61).
    public internal(set) var routePreferences: [LineRoutePreference]
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
        self.routePreferences = []
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

/// One stream of a line's trains, sent out from its first call on its own
/// headway: a service of the line, or on a ring (decision 49) its own
/// service one way round.
struct DispatchStream: Hashable, Sendable {
    let service: Int
    let direction: RingDirection?
}

/// Which way round a ring line's train runs (the `Ci/` metro game's
/// `train.dir`): ``inner`` (内环, `1`) calls at the line's stops in order,
/// ``outer`` (外环, `-1`) in reverse; both come back to the first stop.
public enum RingDirection: String, CaseIterable, Codable, Sendable {
    case inner
    case outer
}

/// A service line: the stations its trains call at, in order, out from the
/// first and back from the last; the performance it plans its journeys
/// with; when it runs; how many trains it is to run at each level, or how
/// far apart; and the trains assigned to it.
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
///
/// A line may instead be a ring (``isRing``, ARCHITECTURE decision 49,
/// after the `Ci/` metro game's `isRing`): its trains run on from the last
/// stop back to the first, never turning round, half of them each way (see
/// ``RingDirection``), and it has no patterns.
public struct ServiceLine: Identifiable, Hashable, Sendable {
    public let id: LineID
    public internal(set) var name: String
    /// The stations called at, in order: at least two, and no station twice
    /// in a row. The trains run from the first to the last and back, turning
    /// round at both ends.
    public internal(set) var stops: [StationID]
    /// Shared directed physical paths for the base service (decision 61).
    public internal(set) var routePreferences: [LineRoutePreference]
    /// The performance the line's journey times are worked out with (Stage
    /// W2c): each leg takes the least whole second it builds a running
    /// curve for (see ``RunningCurve/leastSeconds(length:performance:)``).
    /// ``TrainPerformance/standard`` for a new line. The trains it sends out
    /// keep to those times with their own performance where they can.
    public internal(set) var performance: TrainPerformance
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
    /// Whether the line is a ring (decision 49): its trains go on from the
    /// last stop to the first, round and round, and never turn round. A
    /// ring has three stops or more, does not call at the same station
    /// first and last, and has no patterns; its counts of trains in service
    /// are even, half for each ``RingDirection``.
    public internal(set) var isRing: Bool
    /// When a ring last sent a train out the ``RingDirection/outer`` way,
    /// or `nil` if it never has (or the line is not a ring);
    /// ``lastDispatch`` is the ``RingDirection/inner`` way's.
    public internal(set) var outerLastDispatch: GameTime?
    /// The colour the player chose for the line, or `nil` for the app's
    /// own pick (see ``LineColor``).
    public internal(set) var color: LineColor?
    /// The runs of a real timetable the line sends its trains out on
    /// (decision 133), or none for a line that runs at a headway.
    public internal(set) var runs: [LineRun]
    /// For each run, the last game day it sent a train out, or `nil` if it
    /// never has.
    public internal(set) var runDays: [Int64?]

    /// Minutes a train stays at a stop between the ends of the line.
    public static let dwellMinutes: Int64 = 1
    /// Minutes a train stays at either end of the line, where it turns round.
    public static let terminalDwellMinutes: Int64 = 2
    /// The shortest time between two trains of a line: it never runs more
    /// trains than its round trip allows at this headway.
    public static let minimumHeadwayMinutes: Int64 = 2

    /// Creates a line with the standard window, the standard performance,
    /// no trains in service, no target headways and no trains assigned.
    public init(id: LineID, name: String, stops: [StationID]) {
        self.id = id
        self.name = name
        self.stops = stops
        self.routePreferences = []
        self.performance = .standard
        self.window = .standard
        self.trainsInService = .none
        self.targetHeadways = .none
        self.trains = []
        self.lastDispatch = nil
        self.patterns = []
        self.isRing = false
        self.outerLastDispatch = nil
        self.color = nil
        self.runs = []
        self.runDays = []
    }

    /// Whether `stops` can be a line's stops, judged without a world: at
    /// least two, and no station twice in a row.
    static func isStopList(_ stops: [StationID]) -> Bool {
        stops.count >= 2 && zip(stops, stops.dropFirst()).allSatisfy { $0 != $1 }
    }

    /// Whether `stops` can be a ring's stops (decision 49): three or more
    /// (the reference closes a line into a ring at three stations), none
    /// twice in a row, going round from the last to the first too.
    static func isRingStopList(_ stops: [StationID]) -> Bool {
        stops.count >= 3 && isStopList(stops) && stops.first != stops.last
    }

    /// This line with station `id` taken out of its stops (decision 83,
    /// MapBuilder's `handleStationDelete`, which filters it out of every
    /// line's `stationIds`), with the patterns that no longer call at two
    /// stops, by ascending index, taken out too; `nil` when the stops left
    /// are no longer a line's (fewer than two, or on a ring three), which
    /// the `Ci/` metro game deletes (`metro.edit.line.deleted_too_short`).
    ///
    /// Where the station stood between two stops of one station, they
    /// become one stop (on a ring also the last and the first). Each
    /// pattern keeps calling at the same stations, and each route
    /// preference stays with the leg between the same two stations; a
    /// preference for a leg to or from the station, or for a leg the line
    /// no longer takes, goes.
    func removingStation(_ id: StationID) -> (line: ServiceLine, droppedPatterns: [Int])? {
        // The old index of each stop to its new one, or `nil` for the
        // station's.
        var index: [Int?] = []
        var kept: [StationID] = []
        for stop in stops {
            if stop == id {
                index.append(nil)
            } else {
                if kept.last != stop { kept.append(stop) }
                index.append(kept.count - 1)
            }
        }
        if isRing, kept.count > 1, kept.first == kept.last {
            kept.removeLast()
            index = index.map { $0 == kept.count ? 0 : $0 }
        }
        guard isRing ? Self.isRingStopList(kept) : Self.isStopList(kept) else { return nil }

        func moved(_ routes: [LineRoutePreference]) -> [LineRoutePreference] {
            routes.compactMap { route in
                guard index.indices.contains(route.from), index.indices.contains(route.to),
                      let from = index[route.from], let to = index[route.to] else { return nil }
                return LineRoutePreference(from: from, to: to, tracks: route.tracks, platform: route.platform)
            }
        }
        var line = self
        line.stops = kept
        line.routePreferences = moved(routePreferences)
        var dropped: [Int] = []
        for pattern in patterns.indices {
            var calls: [Int] = []
            for call in patterns[pattern].calls {
                if let new = index[call], calls.last != new { calls.append(new) }
            }
            line.patterns[pattern].calls = calls
            line.patterns[pattern].routePreferences = moved(patterns[pattern].routePreferences)
            if !LinePattern.isCallList(calls, stopCount: kept.count) { dropped.append(pattern) }
        }
        for pattern in dropped.reversed() {
            line.patterns.remove(at: pattern)
        }
        for service in 0..<line.serviceCount {
            let order = line.routeOrder(service: service)
            var legs: Set<[Int]> = []
            let routes = line.routes(ofService: service).filter {
                line.isValidRoute($0, order: order) && legs.insert([$0.from, $0.to]).inserted
            }
            if service == 0 {
                line.routePreferences = routes
            } else {
                line.patterns[service - 1].routePreferences = routes
            }
        }
        // Decision 133: runs name stops by index; a line that loses one
        // loses its runs.
        line.runs = []
        line.runDays = []
        return (line, dropped)
    }

    /// `count` made even, down: a ring runs its trains in pairs, one each
    /// way (the reference's `metroRingPairedTrainCountAtOrBelow`).
    static func paired(_ count: Int) -> Int {
        count - count % 2
    }

    /// Which way round train `id` runs, if the line is a ring and the train
    /// is on it: the first of its trains in ascending ID order, the third,
    /// and so on ``RingDirection/inner``, the second, the fourth and so on
    /// ``RingDirection/outer`` (the reference's
    /// `equalRedistributeRingServiceTrains`, by the trains' creation order,
    /// which here is their IDs' order).
    public func ringDirection(of id: TrainID) -> RingDirection? {
        guard isRing, let index = trains.firstIndex(of: id) else { return nil }
        return index % 2 == 0 ? .inner : .outer
    }

    /// A ring's trains that run `direction`, in ascending ID order.
    func ringTrains(_ direction: RingDirection) -> [TrainID] {
        trains.indices.filter { ($0 % 2 == 0) == (direction == .inner) }.map { trains[$0] }
    }

    /// The calls of a ring's lap `direction`, as indices into ``stops``:
    /// from the first stop round to it again, in order or in reverse.
    func ringCalls(_ direction: RingDirection) -> [Int] {
        switch direction {
        case .inner: Array(stops.indices) + [0]
        case .outer: [0] + stops.indices.dropFirst().reversed() + [0]
        }
    }

    /// The line's streams of trains, each sent out from its first call on
    /// its own headway: one for each service (see ``serviceCount``), or on
    /// a ring one each way round (decision 49).
    var dispatchStreams: [DispatchStream] {
        isRing
            ? RingDirection.allCases.map { DispatchStream(service: 0, direction: $0) }
            : (0..<serviceCount).map { DispatchStream(service: $0, direction: nil) }
    }

    /// The stream train `id` runs in, if it is on the line.
    func dispatchStream(of id: TrainID) -> DispatchStream? {
        dispatchStreams.first { trains(of: $0).contains(id) }
    }

    /// The trains of `stream`, in ascending ID order.
    func trains(of stream: DispatchStream) -> [TrainID] {
        stream.direction.map(ringTrains) ?? trains(ofService: stream.service)
    }

    /// When `stream` last sent a train out.
    func lastDispatch(of stream: DispatchStream) -> GameTime? {
        switch stream.direction {
        case .inner: lastDispatch
        case .outer: outerLastDispatch
        case nil: lastDispatch(ofService: stream.service)
        }
    }

    /// Records that `stream` sent a train out at `time`.
    mutating func recordDispatch(of stream: DispatchStream, at time: GameTime) {
        switch stream.direction {
        case .inner: lastDispatch = time
        case .outer: outerLastDispatch = time
        case nil: recordDispatch(ofService: stream.service, at: time)
        }
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
        _ counts: TrainsInService, _ targets: TargetHeadways, at level: ServiceLevel, roundTrip: Int64,
        capacity: ServiceCapacityProfile? = nil
    ) -> (trains: Int, headway: Int64)? {
        let maximum = capacity?.maximum(roundTrip: roundTrip, ring: false)
            ?? Int(clamping: max(1, roundTrip / minimumHeadwayMinutes))
        let count: Int
        if let target = targets[level] {
            count = min(Int(clamping: dividedRoundingUp(roundTrip, by: target)), maximum)
        } else {
            count = min(counts[level], maximum)
        }
        guard count > 0 else { return nil }
        return (count, headway(of: count, roundTrip: roundTrip, target: targets[level]))
    }

    /// How many trains a ring with `counts` and `targets` runs at `level`,
    /// both ways together, and the minutes between two trains going the
    /// same way, for a lap of `lap` minutes; `nil` when it runs none then
    /// (decision 49, the reference's `metroHeadwayRoundTripMinutes` for a
    /// ring and `calcLineHeadwayMin`, which shares the lap between the
    /// trains of one way, `Math.ceil(n/2)`).
    ///
    /// Each way runs half the count set for the level (a ring's counts are
    /// even, see ``paired(_:)``), or with a target the fewest trains that
    /// keep to it, the lap divided by the target, rounded up; and never
    /// more than keep ``minimumHeadwayMinutes`` apart, at least one each
    /// way (the reference's `(isRing ? 2 : 1) * floor(…)`). The headway
    /// is the lap shared between one way's trains, rounded up, or the
    /// target if that is longer.
    ///
    /// - Precondition: `lap >= 1`.
    static func ringService(
        _ counts: TrainsInService, _ targets: TargetHeadways, at level: ServiceLevel, lap: Int64,
        capacity: ServiceCapacityProfile? = nil
    ) -> (trains: Int, headway: Int64)? {
        let maximum = capacity.map { $0.maximum(roundTrip: lap, ring: true) / 2 }
            ?? Int(clamping: max(1, lap / minimumHeadwayMinutes))
        let eachWay: Int
        if let target = targets[level] {
            eachWay = min(Int(clamping: dividedRoundingUp(lap, by: target)), maximum)
        } else {
            eachWay = min(counts[level] / 2, maximum)
        }
        guard eachWay > 0 else { return nil }
        return (2 * eachWay, headway(of: eachWay, roundTrip: lap, target: targets[level]))
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

    /// Every train assigned to the line, to its own service or to a
    /// pattern, in ascending ID order.
    public var assignedTrains: [TrainID] {
        (trains + patterns.flatMap(\.trains)).sorted()
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
    ///
    /// A ring (decision 49) has only its own service, and its plan comes
    /// from ``ringService(_:_:at:lap:)``, the round trip being its lap; its
    /// load is on every segment, the last one from its last stop back to
    /// the first included, each way at its headway.
    func services(at level: ServiceLevel, roundTrips: [Int64?], capacities: [ServiceCapacityProfile?]? = nil) -> (plans: [(trains: Int, headway: Int64)?], loads: [Int]) {
        // Decision 133: a line with runs runs its trains at the runs'
        // times, every level alike: as many as are assigned to it, at the
        // runs' headway.
        if hasRuns {
            guard roundTrips.first ?? nil != nil, !trains.isEmpty else { return ([nil], Array(repeating: 0, count: stops.count - 1)) }
            return ([(trains.count, runHeadway)], Array(repeating: Self.load(ofHeadway: runHeadway), count: stops.count - 1))
        }
        if isRing {
            guard let lap = roundTrips.first ?? nil, let plan = Self.ringService(trainsInService, targetHeadways, at: level, lap: lap, capacity: capacities?.first ?? nil) else {
                return ([nil], Array(repeating: 0, count: stops.count))
            }
            return ([plan], Array(repeating: Self.load(ofHeadway: plan.headway), count: stops.count))
        }
        var loads = Array(repeating: 0, count: stops.count - 1)
        var occupied = Array(repeating: Int64(0), count: stops.count - 1)
        let day = GameTime.minutesPerDay * GameTime.secondsPerMinute
        var plans: [(trains: Int, headway: Int64)?] = []
        for (service, roundTrip) in roundTrips.enumerated() {
            let (counts, targets) = service == 0
                ? (trainsInService, targetHeadways)
                : (patterns[service - 1].trainsInService, patterns[service - 1].targetHeadways)
            let calls = calls(ofService: service)
            let span = calls[0]..<calls[calls.count - 1]
            let capacity = capacities?[service]
            guard let roundTrip, let wanted = Self.service(counts, targets, at: level, roundTrip: roundTrip, capacity: capacity) else {
                plans.append(nil)
                continue
            }
            let room = span.map { Self.segmentCapacity - loads[$0] }.min()!
            // Fewer trains never load a segment more: find the most that fit.
            var (fits, tooMany) = (0, wanted.trains + 1)
            while tooMany - fits > 1 {
                let middle = fits + (tooMany - fits) / 2
                let gap = Self.headway(of: middle, roundTrip: roundTrip, target: targets[level])
                let singleFits = capacity.map { profile in
                    profile.work.indices.allSatisfy { segment in
                        ServiceCapacityProfile.usage(profile.work[segment], headway: gap) <= day - occupied[segment]
                    }
                } ?? true
                if Self.load(ofHeadway: gap) <= room && singleFits {
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
            if let capacity {
                for segment in capacity.work.indices {
                    occupied[segment] += ServiceCapacityProfile.usage(capacity.work[segment], headway: headway)
                }
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
        case id, name, stops, performance, window, trainsInService, targetHeadways, trains, lastDispatch, patterns, ring, outerLastDispatch, routePreferences, color
        case runs, runDays
    }

    /// Decodes a line, rejecting stops, a performance, a window, train counts or
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
    /// checked by the ``GameWorld`` decoder. A line with the standard
    /// performance (Stage W2c) has no `"performance"` key, which is also how
    /// lines saved before Stage W2c read (their `"rate"` is not read). A
    /// ring (decision 49) has `"ring": true`, and `"outerLastDispatch"`
    /// once it has sent a train out the outer way; a line that is not a
    /// ring has neither, which is how lines saved before rings read. A ring
    /// with fewer than three stops, the same station first and last,
    /// patterns or an odd count of trains in service is rejected, and so is
    /// an outer dispatch on a line that is not a ring.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LineID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        stops = try container.decode([StationID].self, forKey: .stops)
        routePreferences = container.contains(.routePreferences) ? try container.decode([LineRoutePreference].self, forKey: .routePreferences) : []
        performance = container.contains(.performance) ? try container.decode(TrainPerformance.self, forKey: .performance) : .standard
        window = try container.decode(ServiceWindow.self, forKey: .window)
        trainsInService = try container.decode(TrainsInService.self, forKey: .trainsInService)
        targetHeadways = container.contains(.targetHeadways) ? try container.decode(TargetHeadways.self, forKey: .targetHeadways) : .none
        trains = container.contains(.trains) ? try container.decode([TrainID].self, forKey: .trains) : []
        lastDispatch = container.contains(.lastDispatch) ? try container.decode(GameTime.self, forKey: .lastDispatch) : nil
        patterns = container.contains(.patterns) ? try container.decode([LinePattern].self, forKey: .patterns) : []
        isRing = container.contains(.ring) ? try container.decode(Bool.self, forKey: .ring) : false
        outerLastDispatch = container.contains(.outerLastDispatch) ? try container.decode(GameTime.self, forKey: .outerLastDispatch) : nil
        color = container.contains(.color) ? try container.decode(LineColor.self, forKey: .color) : nil
        runs = container.contains(.runs) ? try container.decode([LineRun].self, forKey: .runs) : []
        runDays = container.contains(.runDays) ? try container.decode([Int64?].self, forKey: .runDays) : Array(repeating: nil, count: runs.count)
        guard Self.isStopList(stops) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stops, in: container, debugDescription: "Line \(id.rawValue) needs two stops or more, none twice in a row."
            )
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
        guard validRoutePreferences else {
            throw DecodingError.dataCorruptedError(forKey: .routePreferences, in: container, debugDescription: "Route preferences must name distinct directed legs of their service and its destination station.")
        }
        if isRing {
            guard Self.isRingStopList(stops), patterns.isEmpty,
                  ServiceLevel.allCases.allSatisfy({ trainsInService[$0] % 2 == 0 })
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .ring, in: container,
                    debugDescription: "Ring \(id.rawValue) needs three stops or more, not the same first and last, no patterns and even train counts."
                )
            }
        } else if container.contains(.ring) {
            // `false` is never written: a line that is not a ring has no key.
            throw DecodingError.dataCorruptedError(forKey: .ring, in: container, debugDescription: "Only a ring has \"ring\".")
        }
        guard isRing || outerLastDispatch == nil, (outerLastDispatch?.seconds ?? 0) >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .outerLastDispatch, in: container,
                debugDescription: "Line \(id.rawValue): only a ring sends trains out the outer way, never before second 0."
            )
        }
        // Decision 133 (save version 30): runs the line can have, each with
        // the last day it sent a train out, never before day 0.
        guard container.contains(.runs) ? !runs.isEmpty : !container.contains(.runDays), canHave(runs),
              runDays.count == runs.count, runDays.allSatisfy({ ($0 ?? 0) >= 0 })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .runs, in: container,
                debugDescription: "Line \(id.rawValue)'s runs must be its own, on a line that is not a ring, has no patterns and calls at no station twice, each with the day it last ran."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(stops, forKey: .stops)
        if !routePreferences.isEmpty { try container.encode(routePreferences, forKey: .routePreferences) }
        if performance != .standard {
            try container.encode(performance, forKey: .performance)
        }
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
        if isRing {
            try container.encode(true, forKey: .ring)
        }
        try container.encodeIfPresent(outerLastDispatch, forKey: .outerLastDispatch)
        try container.encodeIfPresent(color, forKey: .color)
        if hasRuns {
            try container.encode(runs, forKey: .runs)
            if runDays.contains(where: { $0 != nil }) {
                try container.encode(runDays, forKey: .runDays)
            }
        }
    }
}

extension LinePattern: Codable {
    private enum CodingKeys: String, CodingKey {
        case calls, trainsInService, targetHeadways, trains, lastDispatch, routePreferences
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
        routePreferences = container.contains(.routePreferences) ? try container.decode([LineRoutePreference].self, forKey: .routePreferences) : []
        trainsInService = try container.decode(TrainsInService.self, forKey: .trainsInService)
        targetHeadways = container.contains(.targetHeadways) ? try container.decode(TargetHeadways.self, forKey: .targetHeadways) : .none
        trains = container.contains(.trains) ? try container.decode([TrainID].self, forKey: .trains) : []
        lastDispatch = container.contains(.lastDispatch) ? try container.decode(GameTime.self, forKey: .lastDispatch) : nil
        guard Self.isCallList(calls, stopCount: .max) else {
            throw DecodingError.dataCorruptedError(
                forKey: .calls, in: container, debugDescription: "A pattern calls at two stops or more, in strictly increasing order."
            )
        }
        let routeKeys = routePreferences.map { [$0.from, $0.to] }
        guard Set(routeKeys).count == routeKeys.count, routePreferences.allSatisfy({ route in
            zip(calls, calls.dropFirst()).contains { ($0 == route.from && $1 == route.to) || ($1 == route.from && $0 == route.to) }
        }) else {
            throw DecodingError.dataCorruptedError(forKey: .routePreferences, in: container, debugDescription: "Pattern preferences must name distinct directed adjacent calls.")
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
        if !routePreferences.isEmpty { try container.encode(routePreferences, forKey: .routePreferences) }
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

/// A line's colour: red, green and blue, 0 to 255 each, packed as
/// `0xRRGGBB`, as the reference stores a line's `color` (`"#ef5350"`).
public struct LineColor: Hashable, Sendable {
    public let rgb: Int

    /// `nil` unless `rgb` is within `0...0xFFFFFF`.
    public init?(rgb: Int) {
        guard (0...0xFF_FFFF).contains(rgb) else { return nil }
        self.rgb = rgb
    }

    /// The reference's line colours to choose from (`PRESET_COLORS`).
    public static let presets: [LineColor] = [
        0xF5F5F5, 0xEF5350, 0xFF7043, 0xFFD54F, 0xAED581, 0x66BB6A, 0x26A69A, 0x4DD0E1, 0x42A5F5, 0x5C6BC0,
        0xAB47BC, 0xEC407A, 0xFF80AB, 0xA1887F, 0x78909C, 0xFFCC02, 0xFF6E40, 0x00E5FF, 0x69F0AE, 0xEEFF41,
    ].map { LineColor(rgb: $0)! }
}

extension LineColor: Codable {
    /// Decodes the packed number, rejecting one outside `0...0xFFFFFF`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rgb = try container.decode(Int.self)
        guard let color = LineColor(rgb: rgb) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A line colour is 0 to 0xFFFFFF.")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rgb)
    }
}
