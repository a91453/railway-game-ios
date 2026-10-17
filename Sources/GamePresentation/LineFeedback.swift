import GameCore

// Feedback, second batch (NEXT_PRIORITIES §16 item 3, decision 274): what
// an airline game shows of a route, said of a line. How well its trains
// fit the riders (yesterday's fullest train), how many wait at each end
// now, and a train's seats as filled as it is. Read from the world as it
// is; nothing is kept.
//
// The references have none to port (gap): the `Ci/` line report has the
// peak load as a number (`flowDashboardCaptureLineForDailyReport`), which
// GameCore's `LineTally.peakLoad` already counts.

/// How well a line's trains fit its riders (decision 274), from the
/// fullest a train was yesterday as it left a stop.
public enum TrainFit: Hashable, Sendable {
    /// Under ``TrainFit/tooBigBelow`` full at its busiest: fewer or
    /// shorter trains would carry them for less.
    case tooBig
    case justRight
    /// Full at its busiest: some were left behind or rode standing.
    case tooSmall

    /// Below this, in thousandths of the rated capacity, a line's trains
    /// are too big: never even a third full.
    public static let tooBigBelow: Int64 = 350
    /// From this, in thousandths, too small: full.
    public static let tooSmallFrom: Int64 = 1_000

    /// The fit for a peak load in thousandths of the rated capacity.
    public init(peakLoad: Int64) {
        if peakLoad >= Self.tooSmallFrom {
            self = .tooSmall
        } else if peakLoad < Self.tooBigBelow {
            self = .tooBig
        } else {
            self = .justRight
        }
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .tooBig: language.text("Trains too big", "列車太大")
        case .justRight: language.text("Trains just right", "列車剛好")
        case .tooSmall: language.text("Not enough room", "列車不夠")
        }
    }

    /// What it means for the player, in a sentence.
    public func advice(peakPercent: Int64, in language: DisplayLanguage) -> String {
        switch self {
        case .tooBig:
            language.text(
                "At its busiest a train was \(peakPercent)% full yesterday. Fewer or shorter trains would carry everyone for less.",
                "昨天最擠的時候也只有 \(peakPercent)% 滿。少一點或短一點的列車，一樣載得完，比較省。"
            )
        case .justRight:
            language.text(
                "At its busiest a train was \(peakPercent)% full yesterday: full enough, with room to spare.",
                "昨天最擠的時候 \(peakPercent)% 滿：坐得夠滿，也還有空位。"
            )
        case .tooSmall:
            language.text(
                "A train was full yesterday (\(peakPercent)%). Add a train or longer trains so nobody is left behind.",
                "昨天有列車坐滿了（\(peakPercent)%）。加開列車或加長車廂，才不會有人上不了車。"
            )
        }
    }
}

/// How many wait at a line's end now (decision 274), against what one of
/// its trains takes: one person, two or three, as the map's crowding marks
/// count them (art style: more people, more crowded).
public enum EndDemand: Int, Hashable, Sendable, Comparable {
    case calm = 1
    case busy = 2
    case crowded = 3

    /// The level for `waiting` people against a train of `capacity`:
    /// under half a train is calm, under a full train busy.
    public init(waiting: Int64, capacity: Int64) {
        let capacity = max(1, capacity)
        if waiting * 2 < capacity {
            self = .calm
        } else if waiting < capacity {
            self = .busy
        } else {
            self = .crowded
        }
    }

    public static func < (lhs: EndDemand, rhs: EndDemand) -> Bool { lhs.rawValue < rhs.rawValue }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .calm: language.text("Quiet", "人少")
        case .busy: language.text("Busy", "人多")
        case .crowded: language.text("More than a train takes", "一班車載不完")
        }
    }
}

/// A line's feedback for its card (decision 274).
public struct LineFeedback: Hashable, Sendable {
    /// One end of the line: its station, how many wait there and how
    /// crowded that is.
    public struct End: Hashable, Sendable {
        public let station: StationID
        public let name: String
        public let waiting: Int64
        public let demand: EndDemand
    }

    /// Yesterday's fit, or `nil` before the line has run a day.
    public let fit: TrainFit?
    /// Yesterday's fullest train, in whole percent of its rated capacity.
    public let peakPercent: Int64
    /// The first stop and the last.
    public let ends: [End]

    /// "Busy at Taipei (420 waiting), quiet at Banqiao (30)": the ends in
    /// one line.
    public func endsText(in language: DisplayLanguage) -> String {
        ends.map { end in
            language.text(
                "\(end.name): \(end.demand.title(in: language).lowercased()), \(end.waiting) waiting",
                "\(end.name)：\(end.demand.title(in: language))，\(end.waiting) 人在等"
            )
        }.joined(separator: language.text(" · ", "・"))
    }
}

extension GameWorld {
    /// Line `id`'s feedback (decision 274), or `nil` for a freight line, a
    /// ring or one without trains: its trains' fit from yesterday's fullest
    /// train, and how many wait at each end against what its smallest
    /// train takes.
    public func lineFeedback(_ id: LineID) -> LineFeedback? {
        // Against the smallest of its trains (#785's review): whichever
        // comes next, those waiting must fit it.
        guard let line = line(id: id), !line.isFreight, !line.isRing, line.stops.count >= 2,
              let capacity = line.assignedTrains.compactMap({ train(id: $0)?.ratedCapacity }).min() else { return nil }
        let peak = lineYesterday(id)?.peakLoad
        let ends = [line.stops[0], line.stops[line.stops.count - 1]].compactMap { id -> LineFeedback.End? in
            guard let station = station(id: id) else { return nil }
            // Those waiting for this line only: at a station other lines
            // call at too, their riders are not this line's crowd.
            let waiting = waitingPassengers(at: id).filter { $0.line == line.id }.reduce(Int64(0)) { $0 + $1.count }
            return LineFeedback.End(
                station: id, name: station.name, waiting: waiting,
                demand: EndDemand(waiting: waiting, capacity: capacity)
            )
        }
        return LineFeedback(fit: peak.map { TrainFit(peakLoad: $0) }, peakPercent: ((peak ?? 0) + 5) / 10, ends: ends)
    }
}

/// A train's seats as full as it is (decision 274): each car a row of
/// seats, filled from the front, and those standing when it is over its
/// rated capacity.
public struct SeatMap: Hashable, Sendable {
    /// The seats drawn for each car: two rows of four.
    public static let seatsPerCar = 8
    /// The most cars drawn side by side: six take about 240 points, within
    /// the train card on a phone (300 at most); a longer train wraps.
    public static let carsPerRow = 6

    public let cars: Int
    /// Seats filled, in all, 0 to ``cars`` × ``seatsPerCar``.
    public let filled: Int
    /// Whether more ride than the train is rated for: all seats filled,
    /// some standing.
    public let standing: Bool

    public init(load: TrainLoadInfo, cars: Int) {
        let cars = max(1, cars)
        let seats = cars * Self.seatsPerCar
        self.cars = cars
        filled = min(seats, (load.percentage * seats + 50) / 100)
        standing = load.percentage > 100
    }

    /// The cars of each row drawn, at most ``carsPerRow`` a row.
    public var rows: [Range<Int>] {
        stride(from: 0, to: cars, by: Self.carsPerRow).map { $0..<min(cars, $0 + Self.carsPerRow) }
    }

    /// Whether seat `seat` of car `car` (both from 0) is taken: the cars
    /// fill in turn, from the first.
    public func isFilled(car: Int, seat: Int) -> Bool {
        car * Self.seatsPerCar + seat < filled
    }
}
