import GameCore

// Feedback, second batch, part two (decision 276): each trip's result
// stamped where it ends, as an airline game stamps a flight "full" or
// "plenty of seats". The fullest a trip's train was is read from the world
// after every step, as the fares are (decision 256); nothing here is saved
// or changes the world.
//
// The references have none to port (gap): `Ci/`'s line report counts a
// day's peak load (GameCore's `LineTally.peakLoad`), not a trip's.

/// What a trip is stamped (decision 276): full, or plenty of seats, by
/// decision 274's fit of the fullest its train was. A trip in between gets
/// none, so the map stays quiet while a line runs well.
public enum TripStampKind: Hashable, Sendable {
    /// Full at its busiest (``TrainFit/tooSmall``).
    case full
    /// Never a third full (``TrainFit/tooBig``).
    case roomy

    /// The stamp for a trip whose train was at most `peakLoad` thousandths
    /// of its rated capacity, or `nil` for one just right.
    public init?(peakLoad: Int64) {
        switch TrainFit(peakLoad: peakLoad) {
        case .tooSmall: self = .full
        case .tooBig: self = .roomy
        case .justRight: return nil
        }
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .full: language.text("Full", "客滿")
        case .roomy: language.text("Plenty of seats", "空位多")
        }
    }
}

/// A trip that ended within a step, stamped at its last call.
public struct TripStamp: Hashable, Sendable {
    public let station: StationID
    public let location: PlanPoint
    public let train: TrainID
    public let kind: TripStampKind

    public init(station: StationID, location: PlanPoint, train: TrainID, kind: TripStampKind) {
        self.station = station
        self.location = location
        self.train = train
        self.kind = kind
    }
}

/// The fullest each running trip's train has been, read after every step
/// (decision 276), in thousandths of its rated capacity. A passenger trip
/// of a line that ends as planned is stamped from it; a trip that began
/// and ended within one step was never read, and is not.
public struct TripLoads: Hashable, Sendable {
    struct Key: Hashable, Sendable {
        let train: TrainID
        let opened: GameTime
    }

    private(set) var peaks: [Key: Int64] = [:]

    public init() {}

    /// The stamps of the trips that ended from `before` to `after`, by
    /// train, then reads the trips still running in `after`.
    public mutating func step(from before: GameWorld, to after: GameWorld) -> [TripStamp] {
        let since = before.clock.now
        var stamps: [TripStamp] = []
        for trip in after.tripLog where !trip.isDeadhead && !trip.isInterrupted {
            guard let arrival = trip.arrival, arrival > since, let line = trip.line, after.line(id: line)?.isFreight == false,
                  let first = trip.calls.first, let last = trip.calls.last,
                  let peak = peaks[Key(train: trip.train, opened: first.arrival)],
                  let kind = TripStampKind(peakLoad: peak),
                  let point = after.station(id: last.station)?.point
            else { continue }
            stamps.append(TripStamp(station: last.station, location: point, train: trip.train, kind: kind))
        }
        var running: [Key: Int64] = [:]
        for trip in after.tripLog where trip.arrival == nil && !trip.isDeadhead {
            guard let first = trip.calls.first, let train = after.train(id: trip.train), train.ratedCapacity > 0 else { continue }
            let key = Key(train: trip.train, opened: first.arrival)
            let riders = after.riders(of: trip.train).reduce(Int64(0)) { $0 + $1.count }
            running[key] = max(peaks[key] ?? 0, riders * 1_000 / train.ratedCapacity)
        }
        peaks = running
        return stamps.sorted { ($0.train, $0.station) < ($1.train, $1.station) }
    }
}

/// The trips one step stamped, for the map (``TripStampBoard``).
public struct TripStampPulse: Hashable, Sendable {
    public let stamps: [TripStamp]
    /// Counts up with each pulse, so the same stamps twice are two pulses.
    public let serial: Int

    public init(stamps: [TripStamp], serial: Int) {
        self.stamps = stamps
        self.serial = serial
    }
}

/// The stamps over the stations (decision 276): one a station, a newer
/// one taking its place, each gone after ``lifetime``, at most ``maximum``
/// at once (the oldest go first). Times are real seconds from any fixed
/// start, given by the caller.
public struct TripStampBoard: Hashable, Sendable {
    /// One stamp.
    public struct Mark: Hashable, Sendable, Identifiable {
        public let id: Int
        public let station: StationID
        public let location: PlanPoint
        public let train: TrainID
        public let kind: TripStampKind
        /// When it appeared, in the caller's seconds.
        public let born: Double
    }

    /// How long a stamp stays, in seconds: decision 253's `pop` in, a
    /// hold long enough to read two words, its `cardOut` out.
    public static let lifetime = 2.0
    /// How long it holds between coming in and going.
    public static var hold: Double {
        lifetime - MotionRule.pop.seconds - MotionRule.cardOut.seconds
    }
    /// The most stamps at once.
    public static let maximum = 6

    public private(set) var stamps: [Mark] = []
    private var nextID = 1

    public init() {}

    /// Adds `new`, stamped at `now`, and drops the stamps gone by then.
    public mutating func add(_ new: [TripStamp], at now: Double) {
        expire(at: now)
        for stamp in new {
            stamps.removeAll { $0.station == stamp.station }
            stamps.append(Mark(id: nextID, station: stamp.station, location: stamp.location, train: stamp.train, kind: stamp.kind, born: now))
            nextID += 1
        }
        if stamps.count > Self.maximum { stamps.removeFirst(stamps.count - Self.maximum) }
    }

    /// Drops the stamps gone by `now`.
    public mutating func expire(at now: Double) {
        stamps.removeAll { now - $0.born >= Self.lifetime }
    }

    /// The stamps to draw: at 600× and faster (`fast`) only the followed
    /// train's and those at the ``FareFloatBoard/fastStations`` stations
    /// nearest the middle of the map (`distance`, from it, in any unit), as
    /// the fares; slower, all.
    public func shown(fast: Bool, followed: TrainID?, distance: (PlanPoint) -> Double) -> [Mark] {
        guard fast else { return stamps }
        let central = Set(
            stamps.map { ($0.station, distance($0.location)) }
                .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
                .prefix(FareFloatBoard.fastStations).map(\.0)
        )
        return stamps.filter { $0.train == followed || central.contains($0.station) }
    }
}
