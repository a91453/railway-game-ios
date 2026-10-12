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

    /// How far ahead the board looks: three hours, as the reference's.
    public static let horizonSeconds: Int64 = 3 * GameTime.secondsPerHour
    /// How many trains a direction lists.
    public static let rowsPerDirection = 6

    public var isEmpty: Bool { directions.isEmpty }

    public init(station: StationID, directions: [Direction]) {
        self.station = station
        self.directions = directions
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
        let directions = order.map { key -> Direction in
            let rows = Array(grouped[key]!.prefix(max(1, perDirection)))
            return Direction(destination: rows[0].destination, endsHere: rows[0].endsHere, rows: rows)
        }
        // The reference lists the trains that end here last.
        self.init(station: station, directions: directions.filter { !$0.endsHere } + directions.filter(\.endsHere))
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
            var j = index + 1
            while j < timetable.count {
                if timetable[j].reverses || j == timetable.count - 1 { return (timetable[j].station, false) }
                j += 1
            }
            return (timetable[index].station, true)
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
                    rows.append(Row(
                        id: "t\(train.id.rawValue)|\(cycle)|\(index)", train: train.id, trainName: train.name,
                        line: line.id, lineName: line.name, color: line.color,
                        destination: target.endsHere ? station : target.station, endsHere: target.endsHere,
                        passes: false, isBoarding: boarding, expected: GameTime(seconds: expected),
                        secondsAway: max(0, expected - now), lateMinutes: boarding ? 0 : lateMinutes))
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
                        secondsAway: max(0, expected - now), lateMinutes: lateMinutes))
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
                let last = position == calls.count - 1
                rows.append(Row(
                    id: "r\(line.id.rawValue)|\(index)|\(day)", train: nil, trainName: "",
                    line: line.id, lineName: line.name, color: line.color,
                    destination: last ? station : line.stops[run.to], endsHere: last, passes: false, isBoarding: false,
                    expected: GameTime(seconds: time), secondsAway: max(0, time - now), lateMinutes: 0))
            }
        }
        return rows
    }
}
