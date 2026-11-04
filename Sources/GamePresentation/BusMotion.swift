import GameCore

// Decision 400, 10i-6: where the buses of a player's bus route are at a
// moment of the game's day, worked out from the route alone (its legs,
// its service and its buses), so the same second always puts them in the
// same places and nothing is kept: GameCore's ``BusRoute`` stays the only
// record of the route.
//
// After the reference's `BusEngine.ts` (`Railway/geo-scene-reference-clean`):
// a bus is a share of the way along its route, turned into a point on the
// route's line (`interpolateOnLineString`), fading in and out at the ends
// of a trip (`FADE_SECONDS`). Its times come from the game's timetable
// instead of the reference's GPS trails.

/// One bus of a route through the day, for the camera that follows it:
/// the route and which of its runs (the index in ``BusMotion/departures``).
/// The same bus keeps its ID from one tick to the next; a route edited
/// changes the runs and so the IDs.
public struct BusID: Hashable, Sendable {
    public let route: BusRouteID
    public let run: Int

    public init(route: BusRouteID, run: Int) {
        self.route = route
        self.run = run
    }
}

/// The buses of one bus route through the day.
public struct BusMotion: Hashable, Sendable {
    /// One bus at a moment.
    public struct Bus: Hashable, Sendable {
        /// Which run of the day it is (the index in ``departures``).
        public let run: Int
        /// The seconds since it came to its first stop.
        public let elapsed: Double
        /// The leg it is on (from stop `leg` to the next stop, the last leg
        /// to the station) and how far along it, 0–1, counted from the
        /// first stop's end whichever way the bus goes.
        public let leg: Int
        public let share: Double
        /// Whether it is going to the station (else back to the first
        /// stop).
        public let outbound: Bool
        /// Whether it stands at a stop or the station.
        public let stopped: Bool
        /// How much of it is drawn, 0–1: it grows out of its first stop and
        /// shrinks into it at the end of its trip.
        public let scale: Double

        /// Its distance along a way whose stops and station lie at
        /// `stops` (one more than the legs), from the first stop.
        public func distance(along stops: [Double]) -> Double {
            guard stops.count > leg + 1 else { return stops.last ?? 0 }
            return stops[leg] + (stops[leg + 1] - stops[leg]) * share
        }
    }

    public let route: BusRouteID
    /// The legs' metres, the first stop's first.
    let legs: [Double]
    /// The seconds of the day a bus leaves the first stop.
    public let departures: [Double]
    /// Seconds from the first stop to the station, its stops with it.
    public let oneWay: Double
    /// Seconds standing at each stop between.
    public let dwell: Double
    /// Metres a second between the stops.
    let speed: Double

    /// The seconds a bus waits at each end: half the route's layover.
    public static let layover = Double(BusRoute.layoverMinutes) * 30
    /// The longest stand at a stop on the way.
    public static let longestDwell: Double = 20
    /// The seconds a bus grows or shrinks at the ends of its trip.
    public static let fadeSeconds: Double = 4

    /// The motion of `route`, or `nil` when it has no bus.
    public init?(_ route: BusRoute) {
        guard let headway = route.headway else { return nil }
        self.route = route.id
        legs = route.legMetres.map(Double.init)
        // As GameCore times a ride: 18 km/h with its stops.
        let metres = legs.reduce(0, +)
        oneWay = metres * 3_600 / Double(BusRoute.metresPerHour)
        let between = Double(max(legs.count - 1, 0))
        dwell = between > 0 ? min(Self.longestDwell, 0.3 * oneWay / between) : 0
        let moving = oneWay - dwell * between
        speed = moving > 0 ? metres / moving : 0
        departures = Self.departures(of: route, headway: headway).map { Double($0 * 60) }
    }

    /// The minutes of the day a bus leaves the first stop: one every
    /// headway from midnight, or the route's runs as far as its buses keep
    /// them (a run less than a headway after the one before, or before the
    /// next day's first, is left out), as many as
    /// ``BusRoute/dailyDepartures``.
    static func departures(of route: BusRoute, headway: Int64) -> [Int64] {
        switch route.service {
        case .every:
            return (0..<route.dailyDepartures).map { $0 * headway }
        case .runs(let minutes):
            var kept: [Int64] = []
            for minute in minutes where kept.count < route.dailyDepartures && kept.last.map({ minute - $0 >= headway }) ?? true {
                kept.append(minute)
            }
            while kept.count > 1, let first = kept.first, let last = kept.last, first + GameTime.minutesPerDay - last < headway {
                kept.removeLast()
            }
            return kept
        }
    }

    /// The seconds from a bus coming to its first stop to its coming back:
    /// a wait there, the trip, a wait at the station and the trip back.
    public var cycle: Double { 2 * (oneWay + Self.layover) }

    /// The buses out at `second` of the day (0 to 86,400), each day's
    /// timetable the same; the day before's and the day after's buses
    /// with them across midnight.
    public func buses(at second: Double) -> [Bus] {
        var buses: [Bus] = []
        let day = Double(GameTime.secondsPerDay)
        for offset in [-day, 0, day] {
            for (run, departure) in departures.enumerated() {
                let t = second - (departure + offset) + Self.layover
                guard t >= 0, t < cycle else { continue }
                buses.append(bus(at: t, run: run))
            }
        }
        return buses
    }

    /// The bus of `run` at `second` of the day, `nil` when it is not out.
    public func bus(run: Int, at second: Double) -> Bus? {
        buses(at: second).first { $0.run == run }
    }

    /// Decision 400 (FOLLOWBUS): the bus a camera that followed `run` to
    /// the end of its trip goes on with: of the route's other buses out at
    /// `second` and drawn in full, the one that came to its first stop last
    /// (the next run); `nil` when none is out.
    public func successor(of run: Int, at second: Double) -> Bus? {
        buses(at: second)
            .filter { $0.run != run && $0.scale >= 1 }
            .min { ($0.elapsed, $0.run) < ($1.elapsed, $1.run) }
    }

    /// The bus `t` seconds after it came to the first stop.
    func bus(at t: Double, run: Int = 0) -> Bus {
        let scale = min(1, t / Self.fadeSeconds, (cycle - t) / Self.fadeSeconds)
        let out = t - Self.layover
        if out < 0 { return Bus(run: run, elapsed: t, leg: 0, share: 0, outbound: true, stopped: true, scale: scale) }
        if out < oneWay { return place(after: out, outbound: true, scale: scale, run: run, elapsed: t) }
        let back = out - oneWay - Self.layover
        if back < 0 { return Bus(run: run, elapsed: t, leg: max(legs.count - 1, 0), share: 1, outbound: true, stopped: true, scale: scale) }
        return place(after: back, outbound: false, scale: scale, run: run, elapsed: t)
    }

    /// Where a bus is `seconds` into a trip: on a leg at ``speed``, or
    /// standing ``dwell`` at each stop between.
    func place(after seconds: Double, outbound: Bool, scale: Double, run: Int = 0, elapsed: Double = 0) -> Bus {
        func bus(_ step: Int, _ share: Double, stopped: Bool) -> Bus {
            // Back, the legs are taken from the last, each from its far end.
            outbound ? Bus(run: run, elapsed: elapsed, leg: step, share: share, outbound: true, stopped: stopped, scale: scale)
                : Bus(run: run, elapsed: elapsed, leg: legs.count - 1 - step, share: 1 - share, outbound: false, stopped: stopped, scale: scale)
        }
        guard speed > 0 else { return bus(0, 0, stopped: true) }
        var left = seconds
        let order = outbound ? legs : legs.reversed()
        for (step, metres) in order.enumerated() {
            let moving = metres / speed
            if left < moving { return bus(step, left / moving, stopped: false) }
            left -= moving
            if step < order.count - 1 {
                if left < dwell { return bus(step, 1, stopped: true) }
                left -= dwell
            }
        }
        return bus(order.count - 1, 1, stopped: true)
    }
}
