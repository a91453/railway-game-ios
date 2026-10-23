import GameCore

// The station's "即將進站" board (ARCHITECTURE decision 178), ported from the
// `Railway/` site's departure board
// (`Railway/site_archive_clean/index.html`: `schedBoardRows` lists the
// trains that call at the station within three hours, `boardGroupOf` groups
// them by the way they go, `renderBoard` shows "即將" under a minute and
// "{n} 分" after, "（終點到達）" for a train that ends there, and
// `todayDelayBadge` marks a late train "誤點 {n} 分" from a minute on).
//
// Here the trains are the world's own: every train running a timetable
// (a line's trains, and a fixed-timetable line's runs sent out) has the
// calls it makes and when (``Train/timetable``) and how far it has got
// (``Train/execution``); the board reads the calls still ahead at the
// station, adds the train's lateness (``GameWorld/lateness(of:)``) and
// groups them by where the trip goes. A fast train that does not call at the
// station but runs past it (it is a stop of the line, between two calls of
// the train) is listed as passing, timed between its two calls. The runs of
// a fixed-timetable line not yet sent out are listed at their timetable's
// time (``LineRun``).
//
// Presentation only: worked out from the world each time it is shown.

public struct DepartureBoard: Equatable, Sendable {
    /// One train at the station.
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        /// The train, or `nil` for a run of a timetable not yet sent out.
        public let train: TrainID?
        public let trainName: String
        public let line: LineID
        public let lineName: String
        public let color: LineColor?
        /// Where the trip goes: the next place the train turns round, or
        /// the last stop of its timetable.
        public let destination: StationID
        /// Whether the train's timetable ends at this station (it does not
        /// go on from here).
        public let endsHere: Bool
        /// Whether the train runs past without calling.
        public let passes: Bool
        /// Whether the train is at the platform now.
        public let isBoarding: Bool
        /// When it is expected: the timetable's time and the train's lateness.
        public let expected: GameTime
        /// Whole seconds from now until `expected`, never negative.
        public let secondsAway: Int64
        /// Whole minutes the train is behind its timetable, 0 when on time
        /// or early (the board shows it from one minute on).
        public let lateMinutes: Int

        /// The wording of the time: "進站中" at the platform, "即將進站"
        /// under a minute, then "N 分".
        public func awayText(in language: DisplayLanguage) -> String {
            if isBoarding { return language.text("Boarding", "進站中") }
            if secondsAway < 60 { return language.text("Arriving", "即將進站") }
            return language.text("\(secondsAway / 60) min", "\(secondsAway / 60) 分")
        }

        /// "慢 3 分", or `nil` for a train less than a minute late.
        public func lateText(in language: DisplayLanguage) -> String? {
            lateMinutes >= 1 ? language.text("\(lateMinutes) min late", "慢 \(lateMinutes) 分") : nil
        }

        /// Decision 223: the timetable's time before the lateness, struck
        /// through on the board when the train is late; `nil` when not known.
        public internal(set) var scheduled: GameTime? = nil
        /// Decision 223: late, it seems, because the train before it in the
        /// same direction is late (see ``DepartureBoard/followWindowSeconds``).
        public internal(set) var followsLateTrain = false
        /// Decision 354: the station the train calls at just before this
        /// call, or `nil` when not known (the timetable's first call, or a
        /// pass), to read the platform the line sends it to.
        public internal(set) var comesFrom: StationID? = nil

        /// What the board's status capsule says (decision 223), in words
        /// and not only in colour.
        public enum Status: Hashable, Sendable {
            case boarding
            case passes
            case onTime
            case late(minutes: Int)
            /// Late behind a late train: "前車誤點 4 分".
            case lateBehind(minutes: Int)

            public func text(in language: DisplayLanguage) -> String {
                switch self {
                case .boarding: language.text("Boarding", "進站中")
                case .passes: language.text("Passes", "通過")
                case .onTime: language.text("On time", "準點")
                case .late(let minutes): language.text("\(minutes) min late", "誤點 \(minutes) 分")
                case .lateBehind(let minutes): language.text("\(minutes) min late, train ahead", "前車誤點 \(minutes) 分")
                }
            }

            /// Whether the train is behind its timetable.
            public var isLate: Bool {
                switch self {
                case .late, .lateBehind: true
                default: false
                }
            }
        }

        public var status: Status {
            if isBoarding { return .boarding }
            if passes { return .passes }
            guard lateMinutes >= 1 else { return .onTime }
            return followsLateTrain ? .lateBehind(minutes: lateMinutes) : .late(minutes: lateMinutes)
        }

        /// The time struck through, "HH:MM", when the train is late and its
        /// timetable's time is known; `nil` otherwise.
        public var replacedTimeText: String? {
            guard status.isLate, let scheduled, scheduled.clockText != expected.clockText else { return nil }
            return scheduled.clockText
        }
    }

    /// The trains going one way, soonest first.
    public struct Direction: Equatable, Sendable, Identifiable {
        public let destination: StationID
        /// Trains that end at the station are in a direction of their own
        /// (the reference's "抵達本站").
        public let endsHere: Bool
        public let rows: [Row]
        public var id: String { "\(destination.rawValue)|\(endsHere)" }
    }

    /// The station's name, as it was asked about.
    public let station: StationID
    /// The ways trains go, the one with the soonest train first.
    public let directions: [Direction]
    /// Decision 354: every train in the next three hours, soonest first,
    /// not only the first ``rowsPerDirection`` of each way.
    public let rows: [Row]

    /// How far ahead the board looks: three hours, as the reference's.
    public static let horizonSeconds: Int64 = 3 * GameTime.secondsPerHour
    /// How many trains a direction lists.
    public static let rowsPerDirection = 6
    /// Decision 223: a late train due at most this long after a late train
    /// before it, going the same way, is taken to be held up by it
    /// ("前車誤點"). The world keeps no cause for lateness; this is the
    /// board's guess, and a train further behind is simply "late".
    public static let followWindowSeconds: Int64 = 10 * GameTime.secondsPerMinute

    public var isEmpty: Bool { directions.isEmpty }

    public init(station: StationID, directions: [Direction], rows: [Row]? = nil) {
        self.station = station
        self.directions = directions
        self.rows = rows ?? directions.flatMap(\.rows).sorted { ($0.secondsAway, $0.id) < ($1.secondsAway, $1.id) }
    }

    /// The board of `station` in `world`.
    public init(world: GameWorld, station: StationID, perDirection: Int = DepartureBoard.rowsPerDirection) {
        let now = world.clock.now.seconds
        var rows: [Row] = []
        var seen = Set<String>()
        for line in world.lines where line.stops.contains(station) {
            for trainID in line.assignedTrains {
                guard let train = world.train(id: trainID) else { continue }
                for row in Self.rows(of: train, on: line, at: station, in: world, now: now) where seen.insert(row.id).inserted {
                    rows.append(row)
                }
            }
            for row in Self.runRows(of: line, at: station, in: world, now: now) where seen.insert(row.id).inserted {
                rows.append(row)
            }
        }
        rows.sort { ($0.secondsAway, $0.id) < ($1.secondsAway, $1.id) }
        var grouped: [String: [Row]] = [:]
        var order: [String] = []
        for row in rows {
            let key = "\(row.destination.rawValue)|\(row.endsHere)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        let marked = order.map { Self.markingFollowers(grouped[$0]!) }
        let directions = marked.map { all -> Direction in
            let rows = Array(all.prefix(max(1, perDirection)))
            return Direction(destination: rows[0].destination, endsHere: rows[0].endsHere, rows: rows)
        }
        // The reference lists the trains that end here last.
        self.init(station: station, directions: directions.filter { !$0.endsHere } + directions.filter(\.endsHere),
                  rows: marked.flatMap { $0 }.sorted { ($0.secondsAway, $0.id) < ($1.secondsAway, $1.id) })
    }

    /// `rows`, one direction's soonest first, with each late train due
    /// within ``followWindowSeconds`` after another late train marked as
    /// following it. The train ahead is the last one before it that calls
    /// at the station: one that runs past is not waited for there.
    static func markingFollowers(_ rows: [Row]) -> [Row] {
        var rows = rows
        for index in rows.indices.dropFirst() {
            guard let ahead = rows[..<index].last(where: { !$0.passes }),
                  rows[index].lateMinutes >= 1, !rows[index].passes, !rows[index].isBoarding,
                  ahead.train != rows[index].train, ahead.lateMinutes >= 1,
                  rows[index].expected.seconds - ahead.expected.seconds <= followWindowSeconds
            else { continue }
            rows[index].followsLateTrain = true
        }
        return rows
    }

    // MARK: - From a train's timetable

    /// The calls of `train` still ahead at `station` (and the passes), in
    /// the next three hours.
    static func rows(of train: Train, on line: ServiceLine, at station: StationID, in world: GameWorld, now: Int64) -> [Row] {
        // An empty run back to the line's other end (decision 172) carries no one.
        guard let execution = train.execution, !train.timetable.isEmpty, !train.isDeadheading else { return [] }
        let timetable = train.timetable
        let late = max(0, world.lateness(of: train.id) ?? 0)
        let lateMinutes = Int(min(late, 24 * 3600) / 60)
        let period = train.timetablePeriod
        let lastCycle: Int64
        if let period, period > 0 {
            lastCycle = execution.cycle + horizonCycles(period: period) + 1
        } else {
            lastCycle = 0
        }
        var rows: [Row] = []
        func destination(after index: Int) -> (station: StationID, endsHere: Bool) {
            // Where the trip goes: the next turn-round, or the last stop.
            guard index < timetable.count - 1, let trip = train.trip(leaving: index) else { return (timetable[index].station, true) }
            return (timetable[trip.upperBound].station, false)
        }
        for cycle in execution.cycle...max(execution.cycle, lastCycle) {
            let shift = period.map { cycle * $0 } ?? 0
            for (index, stop) in timetable.enumerated() {
                // Behind the train: not ahead.
                let ahead = (cycle, index) >= (execution.cycle, execution.stop)
                guard ahead else { continue }
                let next = index + 1 < timetable.count ? timetable[index + 1] : nil
                if stop.station == station {
                    let boarding: Bool
                    if case .waitingAtStop(let at, let inCycle) = execution { boarding = at == index && inCycle == cycle } else { boarding = false }
                    let scheduled = stop.arrival.seconds + shift
                    let expected = boarding ? now : max(now, scheduled + late)
                    guard expected - now <= horizonSeconds else { continue }
                    let target = destination(after: index)
                    // The call before, round the end of a repeating timetable.
                    let before = index > 0 ? timetable[index - 1].station : period == nil ? nil : timetable.last?.station
                    rows.append(Row(
                        id: "t\(train.id.rawValue)|\(cycle)|\(index)", train: train.id, trainName: train.name,
                        line: line.id, lineName: line.name, color: line.color,
                        destination: target.endsHere ? station : target.station, endsHere: target.endsHere,
                        passes: false, isBoarding: boarding, expected: GameTime(seconds: expected),
                        secondsAway: max(0, expected - now), lateMinutes: boarding ? 0 : lateMinutes,
                        scheduled: GameTime(seconds: scheduled), comesFrom: before))
                } else if let next, !line.isRing {
                    // A pass: the station is a stop of the line between two
                    // calls of this train, one after the other.
                    let a = line.stops.firstIndex(of: stop.station), b = line.stops.firstIndex(of: next.station)
                    let p = line.stops.firstIndex(of: station)
                    guard let a, let b, let p, a != b, (min(a, b) + 1)..<max(a, b) ~= p else { continue }
                    let left = stop.departure.seconds + shift, right = next.arrival.seconds + shift
                    let fraction = Double(abs(p - a)) / Double(abs(b - a))
                    let scheduled = left + Int64(Double(max(0, right - left)) * fraction)
                    let expected = max(now, scheduled + late)
                    guard expected - now <= horizonSeconds else { continue }
                    let target = destination(after: index)
                    rows.append(Row(
                        id: "p\(train.id.rawValue)|\(cycle)|\(index)", train: train.id, trainName: train.name,
                        line: line.id, lineName: line.name, color: line.color,
                        destination: target.endsHere ? next.station : target.station, endsHere: false,
                        passes: true, isBoarding: false, expected: GameTime(seconds: expected),
                        secondsAway: max(0, expected - now), lateMinutes: lateMinutes,
                        scheduled: GameTime(seconds: scheduled)))
                }
            }
        }
        return rows
    }

    private static func horizonCycles(period: Int64) -> Int64 {
        min(60, horizonSeconds / period + 1)
    }

    // MARK: - From a fixed timetable

    /// The runs of `line` that call at `station` and have not been sent out,
    /// at their timetable's time.
    static func runRows(of line: ServiceLine, at station: StationID, in world: GameWorld, now: Int64) -> [Row] {
        guard !line.runs.isEmpty else { return [] }
        let today = now >= 0 ? now / GameTime.secondsPerDay : 0
        var rows: [Row] = []
        for (index, run) in line.runs.enumerated() {
            let calls = run.calls
            guard let position = calls.firstIndex(where: { line.stops[$0] == station }) else { continue }
            let sent = line.runDays.indices.contains(index) ? line.runDays[index] : nil
            for day in max(0, today - 1)...(today + 1) {
                guard run.days & (1 << StationDemand.weekday(ofDay: day)) != 0, (sent ?? -1) < day else { continue }
                let time = day * GameTime.secondsPerDay + run.times[position].arrival
                guard time >= now - 30, time - now <= horizonSeconds else { continue }
                // A run no train took out in time is dropped for the day
                // (``LineRun/latestDispatch``): it is no train coming.
                guard now <= day * GameTime.secondsPerDay + run.times[0].departure + LineRun.latestDispatch else { continue }
                let last = position == calls.count - 1
                rows.append(Row(
                    id: "r\(line.id.rawValue)|\(index)|\(day)", train: nil, trainName: "",
                    line: line.id, lineName: line.name, color: line.color,
                    destination: last ? station : line.stops[run.to], endsHere: last, passes: false, isBoarding: false,
                    expected: GameTime(seconds: time), secondsAway: max(0, time - now), lateMinutes: 0,
                    scheduled: GameTime(seconds: time), comesFrom: position > 0 ? line.stops[calls[position - 1]] : nil))
            }
        }
        return rows
    }
}

extension Train {
    /// The stops of the trip that leaves stop `index` of the timetable, as
    /// the board reads it: from the last stop at or before it where the
    /// train turns round (``ScheduledStop/reverses``), or the first stop,
    /// to the next stop after it where the train turns round, or the last
    /// stop. A timetable that turns round (A → B → A) is two trips, A → B
    /// and B → A. At the last stop, the trip that ends there. `nil` for a
    /// timetable of fewer than two stops or an index outside it.
    func trip(leaving index: Int) -> ClosedRange<Int>? {
        guard timetable.count > 1, timetable.indices.contains(index) else { return nil }
        let from = min(index, timetable.count - 2)
        let start = (0...from).last { timetable[$0].reverses } ?? 0
        let end = (from + 1..<timetable.count).first { timetable[$0].reverses } ?? timetable.count - 1
        return start...end
    }

    /// The trip the train is on (``trip(leaving:)``): the one leaving the
    /// stop it waits at, or the stop it last left; between trips, the last
    /// one of its timetable. A train turned back short (``shortTurnCall``)
    /// is on the trip from where it turned, not from the place it never
    /// reached.
    var currentTrip: ClosedRange<Int>? {
        guard let at = lastCall else { return trip(leaving: timetable.count - 1) }
        guard let trip = trip(leaving: at) else { return nil }
        if let back = shortTurnCall(at: at, on: trip) { return back...trip.upperBound }
        return trip
    }

    /// The call it came back to when it turned back short on the trip it
    /// is on (decision 255), or `nil`: where it waits, or the call it last
    /// left, at or after it.
    var shortTurnCall: Int? {
        guard let at = lastCall, let trip = trip(leaving: at) else { return nil }
        return shortTurnCall(at: at, on: trip)
    }

    /// The stop it waits at, or the stop it last left; `nil` between trips.
    private var lastCall: Int? {
        switch execution {
        case .waitingAtStop(let stop, _)?: stop
        case .travellingToStop(let stop, _)?: max(0, stop - 1)
        case nil: nil
        }
    }

    /// Turning a train back short, the dispatcher leaves out the calls up
    /// to where it would have turned round and, on a trip of its own,
    /// brings the rest forward (decision 288): the calls left out, and its
    /// arrival back at the station it turned at, are all due the moment it
    /// turned. That is how it reads here, from the timetable alone: no run
    /// of calls it made takes no time. A repeating timetable keeps its
    /// times, so a turn on one does not read.
    private func shortTurnCall(at index: Int, on trip: ClosedRange<Int>) -> Int? {
        let start = trip.lowerBound
        guard timetablePeriod == nil, start > 0, timetable[start].reverses else { return nil }
        let turned = timetable[start].arrival
        func leftOut(_ call: Int) -> Bool { timetable[call].arrival == turned && timetable[call].departure == turned }
        guard leftOut(start) else { return nil }
        // The calls left out run from just after where it turned.
        var first = start
        while first > 1, leftOut(first - 1) { first -= 1 }
        let station = timetable[first - 1].station
        guard start < index,
              let back = (start + 1...index).first(where: { timetable[$0].station == station }),
              (start + 1..<back).allSatisfy(leftOut), timetable[back].arrival == turned
        else { return nil }
        return back
    }
}
