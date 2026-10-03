import GameCore

// Player-facing text for service lines, their patterns and the trains that
// run them (Phase 4 Stage R), in English or Traditional Chinese (see
// ``DisplayLanguage``). Everything here is derived from the world on demand;
// nothing is stored.

extension ServiceLevel {
    /// "Peak", "Off-peak" or "Low".
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .peak: language.text("Peak", "尖峰")
        case .offPeak: language.text("Off-peak", "離峰")
        case .low: language.text("Low", "低峰")
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
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .allDay:
            return language.text("All day", "全天")
        case .hours(let open, let close):
            let end = close == 1440 ? "24:00" : clockText(minuteOfDay: close)
            let nextDay = close > 1440 ? language.text(" next day", "（翌日）") : ""
            return "\(clockText(minuteOfDay: open))–\(end)\(nextDay)"
        }
    }
}

/// A headway as the player reads it: "Every 4 min", "Every 1 h" or
/// "Every 1 h 30 min"; "每 4 分鐘一班".
public func headwayText(minutes: Int64, in language: DisplayLanguage) -> String {
    let rest = minutes % 60
    switch language {
    case .english:
        guard minutes >= 60 else { return "Every \(minutes) min" }
        return "Every \(minutes / 60) h" + (rest == 0 ? "" : " \(rest) min")
    case .traditionalChinese:
        guard minutes >= 60 else { return "每 \(minutes) 分鐘一班" }
        return "每 \(minutes / 60) 小時" + (rest == 0 ? "" : " \(rest) 分鐘") + "一班"
    }
}

/// What a service is set to run at `level`, as the line panel's stepper
/// says it: "Peak: every 5 min" with a target headway, otherwise "Peak: 2
/// wanted" (`trains`, the train count it is set to).
public func levelSettingText(_ level: ServiceLevel, trains: Int, target: Int64?, in language: DisplayLanguage) -> String {
    let name = level.title(in: language)
    guard let target else { return language.text("\(name): \(trains) wanted", "\(name)：上線 \(trains) 列") }
    let headway = headwayText(minutes: target, in: language)
    return language.text("\(name): \(headway.lowercased())", "\(name)：\(headway)")
}

/// A service's target headway: "Target: every 5 min", or "Target: none"
/// when it runs by its train count.
public func targetHeadwayText(_ minutes: Int64?, in language: DisplayLanguage) -> String {
    guard let minutes else { return language.text("Target: none", "目標：無") }
    let headway = headwayText(minutes: minutes, in: language)
    return language.text("Target: \(headway.lowercased())", "目標：\(headway)")
}

/// One service of a line (its own, or a pattern) at one level, as the line
/// panel shows it.
public struct LevelServiceSummary: Hashable, Sendable {
    public let level: ServiceLevel
    /// The trains it runs then, or `nil` if its journey cannot be driven.
    public let trains: Int?
    /// The minutes between them, or `nil` when it runs none.
    public let headway: Int64?
    /// Whether it is a ring's (decision 49): half its trains go each way
    /// round, and the headway is each way's.
    public let isRing: Bool

    /// "3 trains · Every 4 min", "No trains", or "No route"; on a ring "4
    /// trains (2 each way) · Every 5 min each way".
    public func text(in language: DisplayLanguage) -> String {
        guard let trains else { return language.text("No route", "沒有可行駛的路") }
        guard trains > 0, let headway else { return language.text("No trains", "沒有列車") }
        let count = language.text("\(trains) \(trains == 1 ? "train" : "trains")", "\(trains) 列")
        guard isRing else { return "\(count) · \(headwayText(minutes: headway, in: language))" }
        let every = headwayText(minutes: headway, in: language)
        return language.text(
            "\(count) (\(trains / 2) each way) · \(every) each way",
            "\(count)（每個方向 \(trains / 2) 列）· 每個方向\(every)"
        )
    }
}

/// One service of a line as the line panel shows it: the line's own
/// (`pattern` is `nil`) or one of its patterns.
public struct LineServiceSummary: Hashable, Sendable {
    public let pattern: Int?
    /// "All stops", "Short working" or "Express", with its ends, such as
    /// "Express Alpha–Delta"; "Ring" for a ring's.
    public let title: String
    /// The stations called at, such as "Alpha · Gamma · Delta", and for an
    /// express the ones it passes: "passes Beta"; a ring's once round, back
    /// to the first.
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
    func serviceTitle(of line: ServiceLine, calls: [Int], in language: DisplayLanguage) -> String {
        let ends = "\(stationName(line.stops[calls[0]]))–\(stationName(line.stops[calls[calls.count - 1]]))"
        let passes = calls.count < calls[calls.count - 1] - calls[0] + 1
        if passes { return language.text("Express ", "快車 ") + ends }
        return calls.count == line.stops.count
            ? language.text("All stops ", "普通車 ") + ends
            : language.text("Short working ", "區間車 ") + ends
    }

    /// Every service of line `id`, its own first, as the line panel shows
    /// it; empty if there is no such line.
    public func lineServiceSummaries(_ id: LineID, in language: DisplayLanguage) -> [LineServiceSummary] {
        guard let line = line(id: id) else { return [] }
        let services: [(pattern: Int?, calls: [Int], trains: [TrainID])] =
            [(nil, Array(line.stops.indices), line.trains)] + line.patterns.enumerated().map { ($0, $1.calls, $1.trains) }
        return services.map { service in
            let calls = service.calls
            let called = calls.map { stationName(line.stops[$0]) }
            let passed = (calls[0]...calls[calls.count - 1]).filter { !calls.contains($0) }.map { stationName(line.stops[$0]) }
            let passes = language.text(" (passes \(passed.joined(separator: ", ")))", "（通過 \(passed.joined(separator: "、"))）")
            var callsText = called.joined(separator: " · ") + (passed.isEmpty ? "" : passes)
            if line.isRing {
                callsText = (called + [called[0]]).joined(separator: " · ")
                    + language.text(", and half the trains the other way round", "，一半列車反方向")
            }
            let levels = ServiceLevel.allCases.map { level in
                LevelServiceSummary(
                    level: level,
                    trains: lineTrainsInService(id, at: level, pattern: service.pattern),
                    headway: lineHeadway(id, at: level, pattern: service.pattern),
                    isRing: line.isRing
                )
            }
            return LineServiceSummary(
                pattern: service.pattern,
                title: line.isRing ? language.text("Ring", "環線") : serviceTitle(of: line, calls: calls, in: language),
                callsText: callsText,
                levels: levels,
                assigned: service.trains.count,
                running: service.trains.count { train(id: $0)?.execution != nil }
            )
        }
    }

    /// Whether line `id` is running at `time` and at which level: "Peak",
    /// "Off-peak", "Low", or "Closed".
    public func lineStatusText(_ id: LineID, at time: GameTime, in language: DisplayLanguage) -> String {
        serviceLevel(of: id, at: time)?.title(in: language) ?? language.text("Closed", "已收班")
    }

    /// The stretches of line `id` no service runs over at `level`, such as
    /// "Not covered: Alpha–Beta, Gamma–Delta", or `nil` when every segment
    /// is covered (or there is no such line). A ring (decision 49) runs
    /// over all of itself or none of it.
    public func lineCoverageText(_ id: LineID, at level: ServiceLevel, in language: DisplayLanguage) -> String? {
        guard let line = line(id: id), let loads = lineSegmentLoads(id, at: level) else { return nil }
        if line.isRing {
            guard loads.allSatisfy({ $0 == 0 }) else { return nil }
            return language.text("Not covered: the whole ring", "沒有服務：整條環線")
        }
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
        guard !gaps.isEmpty else { return nil }
        return language.text("Not covered: \(gaps.joined(separator: ", "))", "沒有服務：\(gaps.joined(separator: "、"))")
    }

    /// The name of the service train `id` runs for, such as "Main" or
    /// "Main · Express Alpha–Delta", or `nil` when it is on no line.
    public func assignedServiceName(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let lineID = assignedLine(of: id), let line = line(id: lineID) else { return nil }
        guard let pattern = assignedPattern(of: id) else { return line.name }
        return "\(line.name) · \(serviceTitle(of: line, calls: line.patterns[pattern].calls, in: language))"
    }
}

/// How a train on a service stands against its timetable: its
/// ``GameWorld/lateness(of:)`` in whole minutes, never stored.
public enum Punctuality: Hashable, Sendable {
    case onTime
    /// Reached the station it waits at before its scheduled arrival.
    case early(minutes: Int64)
    /// Left its last stop late, or past the time it should have left its
    /// stop or reached the next.
    case late(minutes: Int64)

    /// `seconds` late (early when negative), in whole minutes rounded
    /// towards zero: less than a minute either way is on time.
    init(lateness seconds: Int64) {
        self = seconds >= 0 ? .late(by: seconds) : .early(by: seconds == .min ? .max : -seconds)
    }

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
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .onTime: language.text("On time", "準點")
        case .early(let minutes): language.text("\(minutes) min early", "早到 \(minutes) 分")
        case .late(let minutes): language.text("\(minutes) min late", "誤點 \(minutes) 分")
        }
    }
}

/// Where a train waiting at a stop has got to in its dwell (Stage W2b),
/// derived from its service's times (see ``ServiceTimes``) and the clock,
/// never stored.
public enum DwellPhase: Hashable, Sendable {
    /// It has arrived, and its doors are opening.
    case doorsOpening
    /// Passengers are getting off and on.
    case boarding
    /// Its doors are open, and it holds until it may leave.
    case holding
    /// Its doors are closing.
    case doorsClosing
    /// Its doors have closed, and it leaves as soon as it can.
    case readyToLeave

    /// "Doors opening", "Passengers boarding", "Doors open", "Doors
    /// closing" or "Ready to leave".
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .doorsOpening: language.text("Doors opening", "開門中")
        case .boarding: language.text("Passengers boarding", "乘客上下車中")
        case .holding: language.text("Doors open", "開門停站")
        case .doorsClosing: language.text("Doors closing", "關門中")
        case .readyToLeave: language.text("Ready to leave", "準備發車")
        }
    }

    /// The phase of a dwell with `times` at `now`: the doors open until the
    /// exchange starts, passengers get off and on until `exchangeEnd`, the
    /// train holds with its doors open until `closing`, and its doors take
    /// ``ServiceDwell/doorClosing`` to close.
    public init(_ times: ServiceTimes, at now: GameTime) {
        if let closing = times.closing {
            let (closed, overflow) = closing.seconds.addingReportingOverflow(ServiceDwell.doorClosing)
            self = !overflow && now.seconds >= closed ? .readyToLeave : .doorsClosing
        } else if let exchangeEnd = times.exchangeEnd {
            self = now < exchangeEnd ? .boarding : .holding
        } else {
            self = .doorsOpening
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
    /// Where it has got to in its dwell while it waits at a stop; `nil`
    /// while it travels or waits to be sent out.
    public let dwell: DwellPhase?

    public init(serviceName: String?, stopText: String, punctuality: Punctuality?, dwell: DwellPhase? = nil) {
        self.serviceName = serviceName
        self.stopText = stopText
        self.punctuality = punctuality
        self.dwell = dwell
    }
}

extension GameWorld {
    /// Train `id`'s service now: which service it runs for, where it is in
    /// its timetable, whether it is early or late (its
    /// ``GameWorld/lateness(of:)`` in whole minutes, rounded towards zero:
    /// less than a minute either way is on time) and, waiting at a stop,
    /// where it has got to in its dwell; `nil` for a train with no service
    /// that is on no line (or no such train). Scheduled times include the
    /// cycle of a repeating timetable.
    public func trainServiceStatus(of id: TrainID, in language: DisplayLanguage) -> TrainServiceStatus? {
        guard let train = train(id: id) else { return nil }
        let serviceName = assignedServiceName(of: id, in: language)
        guard let execution = train.execution, let times = train.times, let lateness = lateness(of: id) else {
            return serviceName.map {
                TrainServiceStatus(serviceName: $0, stopText: language.text("Waiting to be sent out", "等待派車"), punctuality: nil)
            }
        }
        let stop = train.timetable[execution.stop]
        let offset = (train.timetablePeriod ?? 0) &* execution.cycle
        let arrival = GameTime(seconds: stop.arrival.seconds &+ offset)
        let departure = GameTime(seconds: stop.departure.seconds &+ offset)
        let name = stationName(stop.station)
        let punctuality = Punctuality(lateness: lateness)
        switch execution {
        case .waitingAtStop:
            let isLast = train.timetablePeriod == nil && execution.stop == train.timetable.count - 1
            let text = isLast
                ? language.text("At \(name), last stop", "停靠 \(name)，終點站")
                : language.text("At \(name), leaves \(departure.clockText)", "停靠 \(name)，\(departure.clockText) 發車")
            return TrainServiceStatus(
                serviceName: serviceName, stopText: text, punctuality: punctuality, dwell: DwellPhase(times, at: clock.now)
            )
        case .travellingToStop:
            return TrainServiceStatus(
                serviceName: serviceName,
                stopText: language.text("Next: \(name), due \(arrival.clockText)", "下一站：\(name)，\(arrival.clockText) 到站"),
                punctuality: punctuality
            )
        }
    }
}

extension GameWorld {
    /// Under traffic control, "Waiting for Express to clear the route"
    /// while train `id` is due to leave on a route another train holds
    /// (see ``trainHoldingRoute(of:)``), naming that train; `nil` otherwise.
    public func routeWaitText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let holder = trainHoldingRoute(of: id) else { return nil }
        let name = train(id: holder)?.name ?? "#\(holder.rawValue)"
        return language.text("Waiting for \(name) to clear the route", "等待 \(name) 讓出進路")
    }
}
