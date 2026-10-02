import GameCore

// Player-facing text for service lines, their patterns and the trains that
// run them (Phase 4 Stage R). Everything here is derived from the world on
// demand; nothing is stored.

extension ServiceLevel {
    /// "Peak", "Off-peak" or "Low".
    public var title: String {
        switch self {
        case .peak: "Peak"
        case .offPeak: "Off-peak"
        case .low: "Low"
        }
    }
}

/// A minute of the day as "hh:mm", such as "06:00"; minutes of the next
/// morning (1440 and later) wrap round, so 1500 is "01:00".
public func clockText(minuteOfDay minute: Int) -> String {
    let wrapped = ((minute % 1440) + 1440) % 1440
    let hours = wrapped / 60
    let minutes = wrapped % 60
    return (hours < 10 ? "0" : "") + "\(hours):" + (minutes < 10 ? "0" : "") + "\(minutes)"
}

extension GameTime {
    /// The time of day only, such as "08:30".
    public var clockText: String {
        GamePresentation.clockText(minuteOfDay: minuteOfDay)
    }
}

extension ServiceWindow {
    /// "All day", "06:00–24:00", or "22:00–01:00 next day" for a window
    /// that runs past midnight.
    public var displayText: String {
        switch self {
        case .allDay:
            return "All day"
        case .hours(let open, let close):
            let end = close == 1440 ? "24:00" : clockText(minuteOfDay: close)
            return "\(clockText(minuteOfDay: open))–\(end)\(close > 1440 ? " next day" : "")"
        }
    }
}

/// A headway as the player reads it: "Every 4 min", "Every 1 h" or
/// "Every 1 h 30 min".
public func headwayText(minutes: Int64) -> String {
    guard minutes >= 60 else { return "Every \(minutes) min" }
    let rest = minutes % 60
    return "Every \(minutes / 60) h" + (rest == 0 ? "" : " \(rest) min")
}

/// One service of a line (its own, or a pattern) at one level, as the line
/// panel shows it.
public struct LevelServiceSummary: Hashable, Sendable {
    public let level: ServiceLevel
    /// The trains it runs then, or `nil` if its journey cannot be driven.
    public let trains: Int?
    /// The minutes between them, or `nil` when it runs none.
    public let headway: Int64?

    /// "3 trains · Every 4 min", "No trains", or "No route".
    public var text: String {
        guard let trains else { return "No route" }
        guard trains > 0, let headway else { return "No trains" }
        return "\(trains) \(trains == 1 ? "train" : "trains") · \(headwayText(minutes: headway))"
    }
}

/// One service of a line as the line panel shows it: the line's own
/// (`pattern` is `nil`) or one of its patterns.
public struct LineServiceSummary: Hashable, Sendable {
    public let pattern: Int?
    /// "All stops", "Short working" or "Express", with its ends, such as
    /// "Express Alpha–Delta".
    public let title: String
    /// The stations called at, such as "Alpha · Gamma · Delta", and for an
    /// express the ones it passes: "passes Beta".
    public let callsText: String
    public let levels: [LevelServiceSummary]
    /// The trains assigned to it, and of them those on a trip now.
    public let assigned: Int
    public let running: Int
}

extension GameWorld {
    /// The name of station `id`, or "#id" if there is none.
    func stationName(_ id: StationID) -> String {
        station(id: id)?.name ?? "#\(id.rawValue)"
    }

    /// What kind of service calls at `calls` of `line`, with its ends:
    /// "All stops A–D" for every stop, "Short working B–C" for a run of
    /// neighbouring stops short of the ends, "Express A–D" when it leaves
    /// stops out.
    func serviceTitle(of line: ServiceLine, calls: [Int]) -> String {
        let ends = "\(stationName(line.stops[calls[0]]))–\(stationName(line.stops[calls[calls.count - 1]]))"
        let passes = calls.count < calls[calls.count - 1] - calls[0] + 1
        if passes { return "Express \(ends)" }
        return calls.count == line.stops.count ? "All stops \(ends)" : "Short working \(ends)"
    }

    /// Every service of line `id`, its own first, as the line panel shows
    /// it; empty if there is no such line.
    public func lineServiceSummaries(_ id: LineID) -> [LineServiceSummary] {
        guard let line = line(id: id) else { return [] }
        let services: [(pattern: Int?, calls: [Int], trains: [TrainID])] =
            [(nil, Array(line.stops.indices), line.trains)] + line.patterns.enumerated().map { ($0, $1.calls, $1.trains) }
        return services.map { service in
            let calls = service.calls
            let called = calls.map { stationName(line.stops[$0]) }
            let passed = (calls[0]...calls[calls.count - 1]).filter { !calls.contains($0) }.map { stationName(line.stops[$0]) }
            let callsText = called.joined(separator: " · ") + (passed.isEmpty ? "" : " (passes \(passed.joined(separator: ", ")))")
            let levels = ServiceLevel.allCases.map { level in
                LevelServiceSummary(
                    level: level,
                    trains: lineTrainsInService(id, at: level, pattern: service.pattern),
                    headway: lineHeadway(id, at: level, pattern: service.pattern)
                )
            }
            return LineServiceSummary(
                pattern: service.pattern,
                title: serviceTitle(of: line, calls: calls),
                callsText: callsText,
                levels: levels,
                assigned: service.trains.count,
                running: service.trains.count { train(id: $0)?.execution != nil }
            )
        }
    }

    /// Whether line `id` is running at `time` and at which level: "Peak",
    /// "Off-peak", "Low", or "Closed".
    public func lineStatusText(_ id: LineID, at time: GameTime) -> String {
        serviceLevel(of: id, at: time)?.title ?? "Closed"
    }

    /// The stretches of line `id` no service runs over at `level`, such as
    /// "Not covered: Alpha–Beta, Gamma–Delta", or `nil` when every segment
    /// is covered (or there is no such line).
    public func lineCoverageText(_ id: LineID, at level: ServiceLevel) -> String? {
        guard let line = line(id: id), let loads = lineSegmentLoads(id, at: level) else { return nil }
        var gaps: [String] = []
        var start: Int?
        for segment in 0...loads.count {
            let empty = segment < loads.count && loads[segment] == 0
            if empty, start == nil {
                start = segment
            } else if !empty, let first = start {
                gaps.append("\(stationName(line.stops[first]))–\(stationName(line.stops[segment]))")
                start = nil
            }
        }
        return gaps.isEmpty ? nil : "Not covered: \(gaps.joined(separator: ", "))"
    }

    /// The name of the service train `id` runs for, such as "Main" or
    /// "Main · Express Alpha–Delta", or `nil` when it is on no line.
    public func assignedServiceName(of id: TrainID) -> String? {
        guard let lineID = assignedLine(of: id), let line = line(id: lineID) else { return nil }
        guard let pattern = assignedPattern(of: id) else { return line.name }
        return "\(line.name) · \(serviceTitle(of: line, calls: line.patterns[pattern].calls))"
    }
}

/// How a train on a service stands against its timetable, derived from
/// the scheduled times and the clock, never stored.
public enum Punctuality: Hashable, Sendable {
    case onTime
    /// Stopped at a station before its scheduled arrival there.
    case early(minutes: Int64)
    /// Past the time it should have left its stop, or reached the next.
    case late(minutes: Int64)

    /// Late by `seconds`, in whole minutes rounded down: less than a minute
    /// late is on time.
    static func late(by seconds: Int64) -> Punctuality {
        let minutes = seconds / GameTime.secondsPerMinute
        return minutes > 0 ? .late(minutes: minutes) : .onTime
    }

    /// Early by `seconds`, in whole minutes rounded down: less than a minute
    /// early is on time.
    static func early(by seconds: Int64) -> Punctuality {
        let minutes = seconds / GameTime.secondsPerMinute
        return minutes > 0 ? .early(minutes: minutes) : .onTime
    }

    /// "On time", "2 min early" or "5 min late".
    public var text: String {
        switch self {
        case .onTime: "On time"
        case .early(let minutes): "\(minutes) min early"
        case .late(let minutes): "\(minutes) min late"
        }
    }
}

/// A train's service as the train panel shows it.
public struct TrainServiceStatus: Hashable, Sendable {
    /// The line or pattern it runs for (see
    /// ``GameWorld/assignedServiceName(of:)``), or `nil` for a timetable of
    /// its own.
    public let serviceName: String?
    /// Where it is in its timetable: "At Beta, leaves 08:35", "Next: Gamma,
    /// due 08:40", or, for a line's train between trips, "Waiting to be
    /// sent out".
    public let stopText: String
    public let punctuality: Punctuality?

    public init(serviceName: String?, stopText: String, punctuality: Punctuality?) {
        self.serviceName = serviceName
        self.stopText = stopText
        self.punctuality = punctuality
    }
}

extension GameWorld {
    /// Train `id`'s service now: which service it runs for, where it is in
    /// its timetable and whether it is early or late; `nil` for a train
    /// with no service that is on no line (or no such train).
    ///
    /// Waiting at a stop, a train is late by the minutes since its
    /// scheduled departure once that has passed, and early by the minutes
    /// until its scheduled arrival if it is already there. Travelling, it is
    /// late by the minutes since its scheduled arrival at the next stop once
    /// that has passed. Minutes are whole minutes, rounded down: less than
    /// a minute either way is on time. Scheduled times include the cycle of a repeating
    /// timetable.
    public func trainServiceStatus(of id: TrainID) -> TrainServiceStatus? {
        guard let train = train(id: id) else { return nil }
        let serviceName = assignedServiceName(of: id)
        guard let execution = train.execution else {
            return serviceName.map { TrainServiceStatus(serviceName: $0, stopText: "Waiting to be sent out", punctuality: nil) }
        }
        let stop = train.timetable[execution.stop]
        let offset = (train.timetablePeriod ?? 0) &* execution.cycle
        let arrival = GameTime(seconds: stop.arrival.seconds &+ offset)
        let departure = GameTime(seconds: stop.departure.seconds &+ offset)
        let now = clock.now
        let name = stationName(stop.station)
        switch execution {
        case .waitingAtStop:
            let punctuality = now > departure ? Punctuality.late(by: now.seconds - departure.seconds)
                : now < arrival ? .early(by: arrival.seconds - now.seconds) : .onTime
            let isLast = train.timetablePeriod == nil && execution.stop == train.timetable.count - 1
            let text = isLast ? "At \(name), last stop" : "At \(name), leaves \(departure.clockText)"
            return TrainServiceStatus(serviceName: serviceName, stopText: text, punctuality: punctuality)
        case .travellingToStop:
            let punctuality = now > arrival ? Punctuality.late(by: now.seconds - arrival.seconds) : .onTime
            return TrainServiceStatus(
                serviceName: serviceName, stopText: "Next: \(name), due \(arrival.clockText)", punctuality: punctuality
            )
        }
    }
}

extension GameWorld {
    /// Under traffic control, "Waiting for Express to clear the route"
    /// while train `id` is due to leave on a route another train holds
    /// (see ``trainHoldingRoute(of:)``), naming that train; `nil` otherwise.
    public func routeWaitText(of id: TrainID) -> String? {
        guard let holder = trainHoldingRoute(of: id) else { return nil }
        return "Waiting for \(train(id: holder)?.name ?? "#\(holder.rawValue)") to clear the route"
    }
}
