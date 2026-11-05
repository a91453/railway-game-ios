import Foundation
import GameCore

// Decision 596: the 3D map's street traffic waits at the stop line while its
// signal (decision 429) is not green, and the people on the pavements wait
// at a zebra crossing while its little green man (decision 445) is red or
// flashing. Nothing is kept from one frame to the next: as before (decision
// 259) where a vehicle or a walker is comes from the clock alone. A trip
// along a road lasts a whole number of the signals' 70 s cycles, so every
// trip meets the same lights at the same moments and its stops are worked
// out afresh from its start each frame; the rest of the time a vehicle is
// off the road and a walker stands where it set out. A vehicle queues
// behind the one ahead of it, which stopped first and goes first.
//
// The rules of the road are those of this repository's 3D city view
// (`Web/CityView/src/world/traffic.js`, MIT): stop at amber as at red, a
// vehicle over its stop line goes on, a gap and a moment's wait behind the
// one ahead. Its vehicles keep their state frame by frame; here they do
// not. bumpinto-world (`docs/research/BUMPINTO_WORLD_2026-11-05.md`, row 1)
// was read for what it does (a bus stops at a signal not green ahead, walkers
// wait at red and while it flashes); none of its code is used.

extension Map3DStreetLife {
    /// Decision 596: where a lane's traffic going one way stops for a
    /// signal: how far along the lane's path the stop line is, metres, the
    /// way that traffic goes (1 along the path, −1 against it), its road and
    /// its junction's group.
    public struct Stop: Sendable, Equatable {
        public let at: Float
        public let direction: Float
        public let road: Map3DSignalTiming.Road
        public let group: Int
    }

    /// Decision 596: where a pavement's path crosses a road on a zebra with
    /// signals, from and to how far along it, metres, with the road whose
    /// little green man its walkers wait for (``Map3DPedestrianSignal``) and
    /// its junction's group.
    public struct Crossing: Sendable, Equatable {
        public let from: Float
        public let to: Float
        public let road: Map3DSignalTiming.Road
        public let group: Int
    }
}

/// Decision 596: when the street's traffic and walkers may go on, and their
/// trips with the stops the signals make.
enum Map3DStreetStops {
    /// When something may go on at a junction: a stretch of the signals'
    /// cycle and the junction's group.
    struct Window: Equatable, Sendable {
        let open: Range<Int64>
        let group: Int

        /// A vehicle's: while its road's signal is green (amber stops it,
        /// as red; `traffic.js`).
        static func driving(_ road: Map3DSignalTiming.Road, group: Int) -> Window {
            Window(open: Map3DPedestrianSignal.window(road), group: group)
        }

        /// A walker's: while its little green man is lit and not flashing
        /// (decision 445: who reaches the kerb as it flashes waits).
        static func walking(_ road: Map3DSignalTiming.Road, group: Int) -> Window {
            let green = Map3DPedestrianSignal.window(road)
            return Window(open: green.lowerBound..<(green.upperBound - Map3DPedestrianSignal.flashing), group: group)
        }

        /// How far into its cycle the junction is at whole second `second`.
        private func phase(_ second: Int64) -> Int64 {
            let cycle = Map3DSignalTiming.cycle
            return ((second + Map3DSignalTiming.offset(group)) % cycle + cycle) % cycle
        }

        /// Whether it is open at `time` (game seconds; the lights change at
        /// whole seconds, as ``Map3DSignalTiming/Clock`` reads them).
        func isOpen(at time: Double) -> Bool {
            open.contains(phase(Int64(time.rounded(.down))))
        }

        /// The first moment from `time` on that is open and at least
        /// `delay` seconds after the stretch opened.
        func next(from time: Double, delay: Double) -> Double {
            let cycle = Map3DSignalTiming.cycle
            let wait = min(delay, Double(open.count) - 0.5)
            let second = time.rounded(.down), at = phase(Int64(second))
            if open.contains(at) {
                let start = second - Double(at - open.lowerBound)
                return max(time, start + wait)
            }
            let ahead = ((open.lowerBound - at) % cycle + cycle) % cycle
            return second + Double(ahead) + wait
        }
    }

    /// A trip's length, seconds: a whole number of cycles, at least
    /// `moving` and the longest each of `stops` stops can make it wait.
    static func lap(moving: Double, stops: Int) -> Double {
        let cycle = Double(Map3DSignalTiming.cycle)
        return cycle * ((moving + Double(stops) * cycle + 10) / cycle).rounded(.up)
    }

    // MARK: Vehicles

    /// A vehicle's braking (3 m/s², gentler than `traffic.js`'s 6) and its
    /// pulling away (2.2 m/s², `traffic.js`'s), metres a second squared.
    static let braking = 3.0
    static let pulling = 2.2
    /// Behind a vehicle that stopped, the next one stops this many metres
    /// back from its tail, and goes this many seconds after it.
    static let queueGap: Float = 2
    static let reaction = 0.4

    /// The shortest time between vehicles on a lane with signals, seconds,
    /// at `speed` metres a second: few enough that a green clears what came
    /// in during the cycle (each pulls away `reaction` and a car's length
    /// with its gap after the one ahead), so a queue does not grow.
    static func headway(speed: Float) -> Double {
        let cycle = Double(Map3DSignalTiming.cycle), shortestGreen = Double(Map3DPedestrianSignal.window(.cross).count)
        return cycle / shortestGreen * (reaction + 6.5 / Double(max(speed, 1))) * 1.1
    }

    /// One way along a lane with signals: its stops (how far along the way
    /// the vehicles go, ascending), how fast, how far, and each trip's
    /// length.
    struct Lane: Sendable {
        let stops: [(at: Double, window: Window)]
        let speed: Double
        let length: Double
        let lap: Double

        init(stops: [(at: Double, window: Window)], speed: Float, length: Float) {
            self.stops = stops
            self.speed = Double(max(speed, 0.5))
            self.length = Double(length)
            lap = Map3DStreetStops.lap(moving: Double(length) / self.speed, stops: stops.count)
        }

        /// A vehicle's stops on its trip: where it stood, from when (had it
        /// not slowed) and until when, by stop; `nil` where it went on.
        struct Trip {
            var stood: [Stood?]
            var end: Double
        }

        /// The trips of vehicles entering at `entries` (seconds on the
        /// clock, slot `i + 1` entering before slot `i`, all within one
        /// trip's length), their halves' lengths `halves` (front, rear)
        /// metres: each behind the one that entered before it, the last
        /// behind the first of the trip before.
        func trips(entries: [Double], halves: [(front: Float, rear: Float)]) -> [Trip] {
            let count = entries.count
            var trips = [Trip](repeating: Trip(stood: Array(repeating: nil, count: stops.count), end: 0), count: count)
            guard count > 0 else { return trips }
            // Twice round: the first vehicle of a trip waits behind the
            // last of the trip before, worked out the first time round.
            for round in 0..<2 {
                for slot in stride(from: count - 1, through: 0, by: -1) {
                    let ahead: (slot: Int, shift: Double)? = slot < count - 1 ? (slot + 1, 0) : round == 0 || count == 1 ? nil : (0, -lap)
                    trips[slot] = trip(entry: entries[slot], half: halves[slot].front,
                                       behind: ahead.map { (trips[$0.slot], $0.shift, halves[$0.slot].rear) })
                }
            }
            return trips
        }

        /// One vehicle's trip from `entry`, its front half `half` long,
        /// `behind` the trip of the one ahead (moved `shift` seconds, its
        /// rear half `rear` long).
        func trip(entry: Double, half: Float, behind: (trip: Trip, shift: Double, rear: Float)?) -> Trip {
            var trip = Trip(stood: Array(repeating: nil, count: stops.count), end: 0)
            var clock = entry, at = 0.0
            let pull = speed / Map3DStreetStops.pulling / 2
            for (index, stop) in stops.enumerated() {
                var standAt = stop.at, earliest = -Double.infinity, queued = false
                if let behind, let ahead = behind.trip.stood[index] {
                    let spot = ahead.at - Double(behind.rear + half + Map3DStreetStops.queueGap)
                    let leave = ahead.until + behind.shift + Map3DStreetStops.reaction
                    if clock + (spot - at) / speed < leave {
                        // A queue back past the stop before: it waits over
                        // that line; back past the lane's start, before it
                        // comes onto the lane (not drawn).
                        let past = index > 0 ? stops[index - 1].at : -Double.infinity
                        (standAt, earliest, queued) = (max(spot, past), leave, true)
                    }
                }
                if !queued, stop.window.isOpen(at: clock + (stop.at - at) / speed) { continue }
                let reach = clock + (standAt - at) / speed
                var until = max(reach, earliest)
                let crossing = until + (stop.at - standAt) / speed
                let allowed = stop.window.next(from: crossing, delay: pull)
                if allowed > crossing { until = allowed - (stop.at - standAt) / speed }
                trip.stood[index] = Stood(at: standAt, from: reach, until: until)
                (clock, at) = (until, standAt)
            }
            trip.end = clock + (length - at) / speed
            return trip
        }

        /// How far along a vehicle on `trip` from `entry` is at `time`
        /// (seconds, on the same clock), slowing into each stop and pulling
        /// away from it; `nil` once it has left the lane.
        func position(of trip: Trip, entry: Double, at time: Double) -> Double? {
            position(trip.stood.lazy.compactMap { $0 }, entry: entry, end: trip.end, at: time)
        }

        /// The same for a trip from `entry` to `end` that stood at `stood`,
        /// in order.
        func position<S: Sequence>(_ stood: S, entry: Double, end: Double, at time: Double) -> Double? where S.Element == Stood {
            let local = entry + Self.wrapped(time - entry, lap)
            guard local < end else { return nil }
            let brake = speed / Map3DStreetStops.braking / 2, pull = speed / Map3DStreetStops.pulling / 2
            var clock = entry, at = 0.0, moving = entry
            for stood in stood {
                // Slowing over `b` either side of when it would have
                // reached the spot, pulling away over `p` either side of
                // when it goes: as much as the stop and the way to it allow.
                let still = max(stood.until - stood.from, 0)
                let share = min(1, still / max(brake + pull, 1e-9))
                let b = min(brake * share, max(stood.from - moving, 0)), p = pull * share
                if local <= stood.from - b { return at + speed * (local - clock) }
                if local <= stood.from + b { return stood.at - speed * pow(stood.from + b - local, 2) / (4 * max(b, 1e-9)) }
                if local <= stood.until - p { return stood.at }
                if local <= stood.until + p { return stood.at + speed * pow(local - stood.until + p, 2) / (4 * max(p, 1e-9)) }
                (clock, at, moving) = (stood.until, stood.at, stood.until + p)
            }
            return at + speed * (local - clock)
        }

        static func wrapped(_ value: Double, _ length: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: length)
            return r < 0 ? r + length : r
        }
    }

    /// Where a vehicle stood on its trip (metres along its way), from
    /// when (had it not slowed into it) and until when (seconds).
    struct Stood: Sendable, Equatable {
        let at: Double
        let from: Double
        let until: Double
    }

    /// One way along a lane with signals, worked out with the scene (the
    /// trips are the same every lap): its vehicles' places, when each
    /// enters a trip, when it leaves the lane and where it stands on the
    /// way.
    struct Schedule: Sendable {
        let direction: Float
        let way: Lane
        let entries: [Double]
        let ends: [Double]
        /// Slot `i`'s stops are `stood[first[i]..<first[i + 1]]`.
        let first: [Int32]
        let stood: [Stood]

        init(direction: Float, way: Lane, entries: [Double], halves: [(front: Float, rear: Float)]) {
            let trips = way.trips(entries: entries, halves: halves)
            var first: [Int32] = [0], stood: [Stood] = []
            for trip in trips {
                stood += trip.stood.compactMap { $0 }
                first.append(Int32(stood.count))
            }
            self.direction = direction
            self.way = way
            self.entries = entries
            ends = trips.map(\.end)
            self.first = first
            self.stood = stood
        }

        var count: Int { entries.count }

        /// How far along its way slot `slot`'s vehicle is at `time`, or
        /// `nil` while it is off the lane.
        func position(_ slot: Int, at time: Double) -> Double? {
            way.position(stood[Int(first[slot])..<Int(first[slot + 1])], entry: entries[slot], end: ends[slot], at: time)
        }
    }

    // MARK: Walkers

    /// A walker's wait after its little green man lights, seconds, the
    /// least and the most (by its seed).
    static let stepOff: (least: Double, most: Double) = (0.3, 1.5)
    /// How far before a crossing's kerb a walker waits, metres.
    static let kerbGap: Float = 0.6
    /// The slowest a walker walks to fill its trip, as a share of its pace.
    static let slowest = 0.8

    /// Where a walker may wait for a crossing's little green man, metres
    /// along its way there and back.
    struct Wait: Sendable, Equatable {
        let at: Double
        let window: Window
    }

    /// A pavement's waits on the way up it and back (ascending), made with
    /// the scene: going out before each crossing's near side, coming back
    /// before its far side.
    struct Route: Sendable {
        let waits: [Wait]
        /// There and back, metres.
        let length: Double

        init(length: Float, crossings: [Map3DStreetLife.Crossing]) {
            let way = 2 * Double(length)
            var waits: [Wait] = []
            for crossing in crossings {
                let window = Window.walking(crossing.road, group: crossing.group)
                for at in [Double(crossing.from - Map3DStreetStops.kerbGap), way - Double(crossing.to + Map3DStreetStops.kerbGap)] {
                    waits.append(Wait(at: Lane.wrapped(at, way), window: window))
                }
            }
            self.waits = waits.sorted { $0.at < $1.at }
            self.length = way
        }
    }

    /// A walker's trip up and down a pavement and back from where it sets
    /// out: a whole number of the signals' cycles, at its pace or, to fill
    /// them, a little slower; the rest of the trip it stands where it set
    /// out.
    struct Walk {
        let route: Route
        let start: Double
        /// How far into the signals' clock its trips start, seconds.
        let phase: Double
        let stepOff: Double
        /// The first of the route's waits from `start` on.
        let first: Int
        private(set) var lap: Double
        private(set) var pace: Double

        /// A walker setting out `start` metres along `route` at `pace` m/s,
        /// its trips starting `phase` seconds into the signals' clock;
        /// going `stepOff` seconds after the green man lights.
        init(route: Route, start: Double, pace: Double, phase: Double, stepOff: Double) {
            self.route = route
            self.start = start
            self.phase = phase
            self.stepOff = stepOff
            first = route.waits.firstIndex { $0.at >= start } ?? 0
            lap = 0
            self.pace = pace
            // The trip: the whole cycles its walk and waits take.
            let cycle = Double(Map3DSignalTiming.cycle)
            let took = end(pace: pace, phase: phase)
            let lap = cycle * max((took / cycle).rounded(.up), 1)
            // Slower, to fill the trip, while that makes it no longer.
            let slower = route.length / max(lap - (took - route.length / pace), 1)
            if slower >= pace * Map3DStreetStops.slowest, slower < pace, end(pace: slower, phase: phase) <= lap {
                self.pace = slower
            }
            self.lap = lap
        }

        /// The waits in the order the walker meets them, metres from where
        /// it sets out.
        var waits: [Wait] { (0..<route.waits.count).map(wait) }

        func wait(_ number: Int) -> Wait {
            let wait = route.waits[(first + number) % route.waits.count]
            return Wait(at: Lane.wrapped(wait.at - start, route.length), window: wait.window)
        }

        /// When a walker at `pace` gets back where it set out, from a trip
        /// starting `phase` seconds into the clock.
        func end(pace: Double, phase: Double) -> Double {
            var clock = 0.0, at = 0.0
            for number in 0..<route.waits.count {
                let wait = wait(number)
                let reach = clock + (wait.at - at) / pace
                clock = wait.window.isOpen(at: phase + reach) ? reach : wait.window.next(from: phase + reach, delay: stepOff) - phase
                at = wait.at
            }
            return clock + (route.length - at) / pace
        }

        /// Where on its way there and back a walker is at `time` seconds
        /// into its trip (which started `phase` seconds into the clock),
        /// and whether it is walking.
        func place(at time: Double, phase: Double) -> (at: Double, walking: Bool) {
            var clock = 0.0, at = 0.0
            for number in 0..<route.waits.count {
                let wait = wait(number)
                let reach = clock + (wait.at - at) / pace
                if time < reach { return (Lane.wrapped(start + at + pace * (time - clock), route.length), true) }
                if !wait.window.isOpen(at: phase + reach) {
                    let go = wait.window.next(from: phase + reach, delay: stepOff) - phase
                    if time < go { return (Lane.wrapped(start + wait.at, route.length), false) }
                    clock = go
                } else {
                    clock = reach
                }
                at = wait.at
            }
            let left = clock + (route.length - at) / pace
            if time < left { return (Lane.wrapped(start + at + pace * (time - clock), route.length), true) }
            return (start, false)
        }
    }
}

// MARK: - Finding them with the scene

extension Map3DStreetLife.Path {
    /// Decision 596: the point of the path nearest `point` on the level:
    /// how far along it is, how far off, and the path's way there.
    func nearest(to point: Map3DBaseMap.Point) -> (along: Float, off: Float, way: Map3DPoint) {
        var best: (along: Float, off: Float, way: Map3DPoint) = (0, .infinity, Map3DPoint(1, 0, 0))
        let p = (x: Float(point.x), z: Float(point.z))
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let dx = b.x - a.x, dz = b.z - a.z, span = dx * dx + dz * dz
            guard span > 1e-6 else { continue }
            let t = min(max(((p.x - a.x) * dx + (p.z - a.z) * dz) / span, 0), 1)
            let x = a.x + dx * t - p.x, z = a.z + dz * t - p.z, off = (x * x + z * z).squareRoot()
            if off < best.off {
                let length = span.squareRoot()
                best = (distances[index - 1] + length * t, off, Map3DPoint(dx / length, 0, dz / length))
            }
        }
        return best
    }

    /// Decision 596: where the path runs across `crossing`'s road (within
    /// its half width either side of its middle line, near the zebra):
    /// from and to how far along, or `nil`.
    func span(across crossing: Map3DRoadMarkings.Crossing, near: Float) -> ClosedRange<Float>? {
        let out = (x: Float(crossing.out.x), z: Float(crossing.out.z)), right = (x: -out.z, z: out.x)
        let centre = (x: Float(crossing.centre.x), z: Float(crossing.centre.z)), half = Float(crossing.half)
        var low = Float.infinity, high = -Float.infinity
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            func side(_ p: Map3DPoint) -> Float { (p.x - centre.x) * right.x + (p.z - centre.z) * right.z }
            func ahead(_ p: Map3DPoint) -> Float { (p.x - centre.x) * out.x + (p.z - centre.z) * out.z }
            let sa = side(a), sb = side(b)
            // The share of the segment inside −half…half across the road.
            var t0: Float = 0, t1: Float = 1
            if abs(sb - sa) < 1e-6 {
                guard abs(sa) < half else { continue }
            } else {
                let ta = (-half - sa) / (sb - sa), tb = (half - sa) / (sb - sa)
                t0 = max(t0, min(ta, tb))
                t1 = min(t1, max(ta, tb))
            }
            guard t1 > t0 else { continue }
            let middle = a + (b - a) * ((t0 + t1) / 2)
            guard abs(ahead(middle)) < near else { continue }
            let span = distances[index] - distances[index - 1]
            low = min(low, distances[index - 1] + span * t0)
            high = max(high, distances[index - 1] + span * t1)
        }
        return high - low >= 1 ? low...high : nil
    }
}

extension Map3DScene.Builder {
    /// Decision 596: the stop lines of `stops` on `path`'s road: those on
    /// its middle line (within a metre) facing along it or against it.
    static func laneStops(_ path: Map3DStreetLife.Path, stops: [Map3DRoadMarkings.Stop]) -> [Map3DStreetLife.Stop] {
        var found: [Map3DStreetLife.Stop] = []
        for stop in stops where path.boxDistance(to: Map3DPoint(Float(stop.point.x), 0, Float(stop.point.z))) < 1 {
            let near = path.nearest(to: stop.point)
            let facing = near.way.x * Float(stop.along.x) + near.way.z * Float(stop.along.z)
            guard near.off < 1, abs(facing) > 0.9 else { continue }
            found.append(Map3DStreetLife.Stop(at: near.along, direction: facing > 0 ? 1 : -1, road: stop.road, group: stop.group))
        }
        return found.sorted { ($0.direction, $0.at) < ($1.direction, $1.at) }
    }

    /// Decision 596: where a pavement's `path` crosses the roads of
    /// `crossings` on their zebras.
    static func pavementCrossings(_ path: Map3DStreetLife.Path, crossings: [Map3DRoadMarkings.Crossing]) -> [Map3DStreetLife.Crossing] {
        // A pavement passes a zebra's middle by at most the crossing's
        // depth and its own width.
        let near = Float(Map3DRoadMarkings.crosswalkDepth / 2 + 6)
        var found: [Map3DStreetLife.Crossing] = []
        for crossing in crossings where path.boxDistance(to: Map3DPoint(Float(crossing.centre.x), 0, Float(crossing.centre.z))) < Float(crossing.half) + near {
            guard let span = path.span(across: crossing, near: near) else { continue }
            found.append(Map3DStreetLife.Crossing(from: span.lowerBound, to: span.upperBound, road: crossing.road, group: crossing.group))
        }
        return found.sorted { $0.from < $1.from }
    }
}
