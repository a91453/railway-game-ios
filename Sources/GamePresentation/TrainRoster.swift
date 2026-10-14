import GameCore

// The train roster (列車運用表, ARCHITECTURE decision 223, point 3): a row
// for each train, a cell for each trip it ran on a day, read from the trip
// log (decision 223, point 5). The app's `TrainRosterView` draws it; all
// that it shows is worked out here.

/// What every train did on a day: a row each, a cell for each trip.
public struct TrainRoster: Equatable, Sendable {
    /// Which day the roster shows: the log keeps today and yesterday.
    public enum Day: Hashable, Sendable, CaseIterable {
        case today, yesterday

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .today: language.text("Today", "今天")
            case .yesterday: language.text("Yesterday", "昨天")
            }
        }
    }

    /// One trip of a train, as a cell from its start to its end.
    public struct Cell: Hashable, Sendable {
        public enum State: Hashable, Sendable {
            /// Arrived no more than five minutes late.
            case onTime
            /// Arrived late, by `minutes`.
            case late(minutes: Int64)
            /// Still on its way; `minutes` late now (0 when on time).
            case running(lateMinutes: Int64)
            /// Its service stopped before the last stop.
            case interrupted
            /// A trip its own timetable has yet to run today.
            case planned
        }

        /// Its place among the train's trips of the day, from 1; `nil` for
        /// an empty run, which carries no one.
        public let number: Int?
        public let from: String
        public let to: String
        /// When it was sent out, in seconds of game time.
        public let start: Int64
        /// When it arrived, or (running or planned) when it is due to.
        public let end: Int64
        /// Its line's share of what its riders paid.
        public let fare: Money
        public let state: State
        public let isEmptyRun: Bool

        /// Whether it ran late, or runs late now: shown with a mark as
        /// well as the warning colour, which grey alone cannot tell apart
        /// (decision 223, point 4).
        public var isLate: Bool {
            switch state {
            case .late: true
            case .running(let minutes): minutes > 0
            default: false
            }
        }

        /// "+6" for a trip six minutes late, else `nil`.
        public var lateText: String? {
            switch state {
            case .late(let minutes): "+\(minutes)"
            case .running(let minutes) where minutes > 0: "+\(minutes)"
            default: nil
            }
        }

        /// "Taipei → Hsinchu".
        public var routeText: String { "\(from) → \(to)" }

        /// The cell's second line: "No. 4 · $2.1k"; "Planned"; "Empty run".
        public func detailText(in language: DisplayLanguage) -> String {
            if isEmptyRun { return language.text("Empty run", "回送") }
            if state == .interrupted { return language.text("Stopped", "中斷") }
            let number = number.map { language.text("No. \($0)", "第 \($0) 趟") } ?? ""
            if state == .planned { return number + " · " + language.text("Planned", "預定") }
            return number + " · " + TrainRoster.shortMoney(fare)
        }

        /// What a screen reader says of the cell.
        public func spokenText(in language: DisplayLanguage) -> String {
            var parts = [routeText, GameTime(seconds: start).clockText + "–" + GameTime(seconds: end).clockText]
            switch state {
            case .onTime: parts.append(language.text("on time", "準點"))
            case .late(let minutes): parts.append(language.text("\(minutes) min late", "誤點 \(minutes) 分"))
            case .running(let minutes):
                parts.append(minutes > 0 ? language.text("running, \(minutes) min late", "行駛中，誤點 \(minutes) 分")
                                         : language.text("running", "行駛中"))
            case .interrupted: parts.append(language.text("stopped", "中斷"))
            case .planned: parts.append(language.text("planned", "預定"))
            }
            if !isEmptyRun, state != .planned { parts.append(TrainRoster.shortMoney(fare)) }
            return parts.joined(separator: "，")
        }
    }

    /// A train's day.
    public struct Row: Hashable, Sendable, Identifiable {
        public let train: TrainID
        public let name: String
        public let line: LineID?
        /// The line's badge code (decision 216), or `nil` for a train on
        /// no line.
        public let lineCode: String?
        /// What its trips earned that day.
        public let revenue: Money
        /// Of the time the network ran that day (from the first trip
        /// sent out to now, or to midnight for yesterday), the share this
        /// train spent on trips, in whole percent.
        public let utilisation: Int
        public let cells: [Cell]

        public var id: TrainID { train }
    }

    public let day: Day
    /// The first second of the day shown.
    public let dayStart: Int64
    /// Now, in seconds of game time.
    public let now: Int64
    public let rows: [Row]

    /// The last second of the day shown, exclusive.
    public var dayEnd: Int64 { dayStart + GameTime.secondsPerDay }

    /// The trains' average utilisation, or `nil` without a train.
    public var averageUtilisation: Int? {
        rows.isEmpty ? nil : rows.reduce(0) { $0 + $1.utilisation } / rows.count
    }

    /// "Today · 7 trains · average use 73%".
    public func summaryText(in language: DisplayLanguage) -> String {
        var text = day.title(in: language) + " · " + language.text("\(rows.count) trains", "\(rows.count) 列")
        if let average = averageUtilisation {
            text += " · " + language.text("average use \(average)%", "平均使用率 \(average)%")
        }
        return text
    }

    /// The roster of `day`: every train that ran a trip that day, and
    /// today also every train on a line or running a service, ordered by
    /// line (the world's order; trains on no line last) and then as the
    /// world lists them.
    public init(world: GameWorld, day: Day = .today) {
        let now = world.clock.now.seconds
        let today = TrainRoster.floorDivide(now, GameTime.secondsPerDay)
        let dayStart = (day == .today ? today : today - 1) * GameTime.secondsPerDay
        let dayEnd = dayStart + GameTime.secondsPerDay
        let until = min(now, dayEnd)
        self.day = day
        self.dayStart = dayStart
        self.now = now

        let codes = LineBadge.codes(for: world.lines)
        let lineOrder = Dictionary(uniqueKeysWithValues: world.lines.enumerated().map { ($0.element.id, $0.offset) })
        func name(_ id: StationID) -> String { world.station(id: id)?.name ?? "?" }
        let trips = world.tripLog.filter { (dayStart..<dayEnd).contains($0.sentOut.seconds) }
        // The network ran from the day's first trip.
        let opened = max(dayStart, trips.map(\.sentOut.seconds).min() ?? until)
        let span = max(0, until - opened)

        var rows: [(order: Int, index: Int, row: Row)] = []
        for (index, train) in world.trains.enumerated() {
            let own = trips.filter { $0.train == train.id }
            let line = world.assignedLine(of: train.id) ?? own.last?.line
            guard !own.isEmpty || day == .today && (line != nil || train.execution != nil) else { continue }
            var cells: [Cell] = []
            var number = 0
            var busy: Int64 = 0
            for trip in own {
                let state: Cell.State
                let end: Int64
                if let arrival = trip.arrival {
                    end = arrival.seconds
                    if trip.isInterrupted {
                        state = .interrupted
                    } else if trip.isLate == true {
                        state = .late(minutes: (trip.delay ?? 0) / GameTime.secondsPerMinute)
                    } else {
                        state = .onTime
                    }
                } else {
                    let late = max(0, world.lateness(of: train.id) ?? 0)
                    end = max(now, trip.scheduledArrival.seconds + late)
                    state = .running(lateMinutes: late > GameWorld.punctualSeconds ? late / GameTime.secondsPerMinute : 0)
                }
                if !trip.isDeadhead { number += 1 }
                cells.append(Cell(number: trip.isDeadhead ? nil : number, from: name(trip.from), to: name(trip.to),
                                  start: trip.sentOut.seconds, end: end, fare: trip.fare, state: state, isEmptyRun: trip.isDeadhead))
                busy += max(0, min(end, until) - max(trip.sentOut.seconds, opened))
            }
            if day == .today {
                for planned in TrainRoster.plannedTrips(of: train, after: cells.last?.end ?? now, before: dayEnd) {
                    if !planned.isEmptyRun { number += 1 }
                    cells.append(Cell(number: number, from: name(planned.from), to: name(planned.to), start: planned.start,
                                      end: planned.end, fare: .zero, state: .planned, isEmptyRun: false))
                }
            }
            let revenue = own.reduce(Money.zero) { $0 + $1.fare }
            let utilisation = span > 0 ? Int(min(100, busy * 100 / span)) : 0
            rows.append((line.flatMap { lineOrder[$0] } ?? Int.max, index,
                         Row(train: train.id, name: train.name, line: line, lineCode: line.flatMap { codes[$0] },
                             revenue: revenue, utilisation: utilisation, cells: cells)))
        }
        self.rows = rows.sorted { ($0.order, $0.index) < ($1.order, $1.index) }.map(\.row)
    }

    /// The trips a train's own repeating timetable will run after `after`
    /// and before `before`: each later cycle, from its arrival at its first
    /// stop (where a trip in the log starts too) to its last stop's
    /// arrival. A line's trains get their
    /// trips one at a time from the line, so theirs are not known ahead.
    static func plannedTrips(of train: Train, after: Int64, before: Int64) -> [(from: StationID, to: StationID, start: Int64, end: Int64, isEmptyRun: Bool)] {
        guard train.execution != nil, let period = train.timetablePeriod, period > 0,
              let first = train.timetable.first, let last = train.timetable.last else { return [] }
        var trips: [(from: StationID, to: StationID, start: Int64, end: Int64, isEmptyRun: Bool)] = []
        // The first cycle that starts after `after`.
        let gap = after - first.arrival.seconds
        var cycle = gap < 0 ? 0 : gap / period + 1
        while trips.count < 48 {
            let (shift, overflow) = cycle.multipliedReportingOverflow(by: period)
            guard !overflow else { break }
            let start = first.arrival.seconds &+ shift
            guard start < before, start >= first.arrival.seconds else { break }
            trips.append((first.station, last.station, start, last.arrival.seconds &+ shift, false))
            cycle += 1
        }
        return trips
    }

    /// Money in short: "$850", "$5.4k", "$1.2M".
    public static func shortMoney(_ money: Money) -> String {
        let dollars = money.amount / 100
        let sign = dollars < 0 ? "-" : ""
        let size = dollars.magnitude
        if size < 1_000 { return "\(sign)$\(size)" }
        if size < 999_950 { return "\(sign)$\(tenths(size, 1_000))k" }
        return "\(sign)$\(tenths(size, 1_000_000))M"
    }

    /// `value / unit` to one decimal, rounded half up: "5.4"; "12" once
    /// it reaches ten.
    private static func tenths(_ value: UInt64, _ unit: UInt64) -> String {
        let scaled = (value * 10 + unit / 2) / unit
        return scaled >= 100 ? "\(scaled / 10)" : "\(scaled / 10).\(scaled % 10)"
    }

    static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }
}

/// How tall the roster's rows are (decision 223: on an iPhone held
/// sideways with many trains, the rows of layout C).
public enum TrainRosterLayout {
    /// The row height with the route and the fare on two lines.
    public static let fullRowHeight: Double = 40
    /// The row height with one line, the fare only.
    public static let compactRowHeight: Double = 26

    /// Whether `rows` rows fit only as compact rows in `height` points.
    public static func usesCompactRows(rows: Int, height: Double) -> Bool {
        Double(rows) * fullRowHeight > height
    }
}
