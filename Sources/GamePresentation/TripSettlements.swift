import GameCore

// Today's trips as the operations overview settles them (ARCHITECTURE
// decision 224, 1C, "今天的結算"; decision 223, point 5): the day's
// finished trips, how many ran on time, what they earned, and the latest
// of them one by one, read from the trip log. The screen draws it.

/// Today's finished trips, settled.
public struct TripSettlements: Equatable, Sendable {
    /// One finished trip.
    public struct Entry: Hashable, Sendable, Identifiable {
        public let train: TrainID
        public let trainName: String
        public let line: LineID?
        /// The line's badge code (decision 216), or `nil`.
        public let lineCode: String?
        public let from: String
        public let to: String
        /// When it arrived at its last stop, in seconds of game time.
        public let arrival: Int64
        /// Its line's share of what its riders paid (its trip's takings;
        /// the trip log keeps no costs by trip).
        public let fare: Money
        /// Minutes late at its last stop when more than five, else `nil`
        /// (on time, as a line's punctuality counts it, decision 207).
        public let lateMinutes: Int64?

        public var id: String { "\(train.rawValue)|\(arrival)" }
        public var isLate: Bool { lateMinutes != nil }

        /// "Taipei → Hsinchu".
        public var routeText: String { "\(from) → \(to)" }

        /// "+$13.4k".
        public var fareText: String { "+" + TrainRoster.shortMoney(fare) }

        /// "+6 min" for a late trip, else `nil`.
        public func lateText(in language: DisplayLanguage) -> String? {
            lateMinutes.map { language.text("+\($0) min", "+\($0) 分") }
        }

        /// The stamp beside it: "On time" or "Late".
        public func stampText(in language: DisplayLanguage) -> String {
            isLate ? language.text("Late", "誤") : language.text("On time", "準")
        }
    }

    /// Today's finished trips with riders (not empty runs, not stopped on
    /// the way).
    public let completed: Int
    /// Of those, how many were on time.
    public let onTime: Int
    /// What they earned together.
    public let fares: Money
    /// The latest of them, the latest first, at most the limit asked.
    public let entries: [Entry]

    /// The share on time in whole percent, or `nil` with no trip yet.
    public var onTimePercent: Int? {
        completed == 0 ? nil : onTime * 100 / completed
    }

    /// Today's trips of `world` (empty without the trip log), with the
    /// `limit` latest as entries.
    public init(world: GameWorld, limit: Int = 8) {
        let now = world.clock.now.seconds
        let today = TrainRoster.floorDivide(now, GameTime.secondsPerDay) * GameTime.secondsPerDay
        let finished = world.tripLog.filter { trip in
            guard let arrival = trip.arrival, !trip.isInterrupted, !trip.isDeadhead else { return false }
            return arrival.seconds >= today
        }
        completed = finished.count
        onTime = finished.filter { $0.isLate == false }.count
        fares = finished.reduce(.zero) { $0 + $1.fare }
        let codes = LineBadge.codes(for: world.lines)
        func name(_ id: StationID) -> String { world.station(id: id)?.name ?? "?" }
        let latest = finished.sorted { ($0.arrival!.seconds, $0.train.rawValue) > ($1.arrival!.seconds, $1.train.rawValue) }
        entries = latest.prefix(max(0, limit)).map { trip in
            Entry(train: trip.train, trainName: world.train(id: trip.train)?.name ?? "",
                  line: trip.line, lineCode: trip.line.flatMap { codes[$0] },
                  from: name(trip.from), to: name(trip.to), arrival: trip.arrival!.seconds, fare: trip.fare,
                  lateMinutes: trip.isLate == true ? (trip.delay ?? 0) / GameTime.secondsPerMinute : nil)
        }
    }
}
