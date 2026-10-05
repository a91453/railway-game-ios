// Service line journeys (Phase 4 Stage Q2a). A line is plan data; what its
// trains would take, and how often they could run, is derived here from the
// map on every query and never stored, like connectivity, routes and stops.
// Since Phase 4.5 Stage S5 a journey is driven on the track network: each
// leg is a TrainPath (ARCHITECTURE decision 31). Since Stage W2c each leg takes the least whole second the line's
// performance builds a running curve for over the path's exact distance
// (ARCHITECTURE decision 40), as the metro game times a leg by accelerating
// to the line's speed and braking at the next station.
// The rules port the web reference's service planning
// (docs/WEB_REFERENCE_STUDY.md): the round trip is every leg out and back
// plus a dwell at every call between the ends and a longer one at each end;
// a line runs at most as many trains as keep the minimum headway, and the
// headway is the round trip shared between its trains. Stage Q3 applies the
// same rules to each of a line's patterns, and shares every segment's room
// between the services that run over it.

/// One leg of a line's journey: from one call to the next.
public struct LineLeg: Hashable, Sendable {
    /// The index, in the line's stops, of the call the leg leaves.
    public let from: Int
    /// The index, in the line's stops, of the call the leg reaches.
    public let to: Int
    /// The path the leg takes (Stage S5), as
    /// ``GameWorld/path(from:toStation:length:)`` gives it from where the
    /// previous leg ended: edges to a platform's berth. No traversals and no
    /// distance when the train is already where it stops for the next call
    /// (a platform both share).
    public let path: TrainPath
    /// Whole seconds the leg takes with the line's performance (Stage W2c):
    /// the least in which it builds a running curve for the path's
    /// distance (see ``RunningCurve/leastSeconds(length:performance:)``),
    /// or 0 for a path of no distance.
    public let seconds: Int64

    public init(from: Int, to: Int, path: TrainPath, seconds: Int64) {
        self.from = from
        self.to = to
        self.path = path
        self.seconds = seconds
    }
}

/// A service's round trip as a train would drive it: out from its first
/// call to its last, turning round there, and back to the first. For a
/// line's own service the calls are all its stops; for a pattern, the
/// pattern's calls.
public struct LineJourney: Hashable, Sendable {
    /// Where the journey starts: at a berth of one of the first call's
    /// platforms (Stage S5).
    public let start: TrainPosition
    /// The legs out, then the legs back: `2 × (calls − 1)` of them; on a
    /// ring (``isRing``) once round instead, one leg for each of its stops,
    /// the last from its last call back to the first.
    public let legs: [LineLeg]
    /// The seconds the whole round trip takes (Stage W2c): every leg, plus
    /// ``ServiceLine/dwellMinutes`` at each call between the ends (once out
    /// and once back) and ``ServiceLine/terminalDwellMinutes`` at each end.
    /// On a ring, once round: every leg and ``ServiceLine/dwellMinutes`` at
    /// each stop, and no terminal (decision 49).
    public let roundTripSeconds: Int64
    /// Whether the journey is a ring's lap (decision 49): it never turns
    /// round, and comes back to its first call going the same way.
    public let isRing: Bool

    public init(start: TrainPosition, legs: [LineLeg], roundTripSeconds: Int64, isRing: Bool = false) {
        self.start = start
        self.legs = legs
        self.roundTripSeconds = roundTripSeconds
        self.isRing = isRing
    }

    /// The round trip in whole minutes, rounded up: what a line plans its
    /// trains and headways with, as it sends them out at whole minutes.
    public var roundTripMinutes: Int64 {
        let minute = GameTime.secondsPerMinute
        return roundTripSeconds / minute + (roundTripSeconds % minute == 0 ? 0 : 1)
    }
}

/// One round trip a line sends a train on (Stage Q2b): whether the train
/// turns round before it leaves the first call, and the journey it drives
/// from there.
struct LineTrip: Hashable, Sendable {
    let turnsFirst: Bool
    let journey: LineJourney

    /// The trip's timetable, calling at the line's `stops` that the legs
    /// reach, for a train sent out at `dispatch`, or `nil` if a time would
    /// pass the largest second.
    ///
    /// One call per leg and one to start: the first call (arriving at
    /// `dispatch`, turning round first if the trip does, and leaving
    /// ``ServiceDwell/terminalMinimum`` later, the least a train dwells
    /// there to take on passengers; Stage W2b), then each leg's call,
    /// arriving the leg's seconds after the call before it left. A call
    /// between the ends stays ``ServiceLine/dwellMinutes``; the far end
    /// stays ``ServiceLine/terminalDwellMinutes`` and turns the train
    /// round; back at the first call the train arrives, turns round and the
    /// trip is over, the train waiting there for the rest of its terminal
    /// dwell, which is longer than the least it needs to let everyone off.
    /// So a train on time is back ready to be sent out again
    /// `roundTripMinutes` after it was sent out (or sooner: the round trip
    /// is rounded up to a whole minute).
    ///
    /// A ring's lap (decision 49) has no terminal: the first call is left
    /// ``ServiceDwell/minimum`` after `dispatch` (or
    /// ``ServiceDwell/terminalMinimum`` when the train turns round there
    /// first, as any train that turns), every call on the way stays
    /// ``ServiceLine/dwellMinutes``, nothing else turns round, and back at
    /// the first call the lap is over (the reference's ring dwell,
    /// `DWELL_GAME_SEC` at every stop).
    ///
    /// - Precondition: `dispatch` is second 0 or later.
    func timetable(calling stops: [StationID], sentOutAt dispatch: GameTime) -> [ScheduledStop]? {
        let legs = journey.legs
        if journey.isRing {
            let least = turnsFirst ? ServiceDwell.terminalMinimum : ServiceDwell.minimum
            let (departure, overflow) = dispatch.seconds.addingReportingOverflow(least)
            guard !overflow else { return nil }
            var timetable = [ScheduledStop(station: stops[legs[0].from], arrival: dispatch, departure: GameTime(seconds: departure), reverses: turnsFirst)]
            var time = departure
            for (index, leg) in legs.enumerated() {
                let dwell = index == legs.count - 1 ? 0 : ServiceLine.dwellMinutes
                let (arrival, late) = time.addingReportingOverflow(leg.seconds)
                let (leaving, later) = arrival.addingReportingOverflow(dwell * GameTime.secondsPerMinute)
                guard !late, !later else { return nil }
                timetable.append(ScheduledStop(station: stops[leg.to], arrival: GameTime(seconds: arrival), departure: GameTime(seconds: leaving)))
                time = leaving
            }
            return timetable
        }
        let farEnd = legs[legs.count / 2 - 1].to
        let (departure, overflow) = dispatch.seconds.addingReportingOverflow(ServiceDwell.terminalMinimum)
        guard !overflow else { return nil }
        var timetable = [ScheduledStop(station: stops[legs[0].from], arrival: dispatch, departure: GameTime(seconds: departure), reverses: turnsFirst)]
        var time = departure
        for (index, leg) in legs.enumerated() {
            let isLast = index == legs.count - 1
            let isFarEnd = leg.to == farEnd
            let dwell = isLast ? 0 : isFarEnd ? ServiceLine.terminalDwellMinutes : ServiceLine.dwellMinutes
            let (arrival, late) = time.addingReportingOverflow(leg.seconds)
            let (leaving, later) = arrival.addingReportingOverflow(dwell * GameTime.secondsPerMinute)
            guard !late, !later else { return nil }
            timetable.append(ScheduledStop(
                station: stops[leg.to], arrival: GameTime(seconds: arrival), departure: GameTime(seconds: leaving),
                reverses: isLast || isFarEnd
            ))
            time = leaving
        }
        return timetable
    }
}

extension GameWorld {
    /// The service level of line `id` at `time`: the world's
    /// ``serviceDay`` at that minute of the day, if the line's window is
    /// open then. `nil` when the line is closed, or does not exist.
    public func serviceLevel(of id: LineID, at time: GameTime) -> ServiceLevel? {
        guard let line = line(id: id), line.window.contains(minuteOfDay: time.minuteOfDay) else { return nil }
        return serviceDay.level(atMinuteOfDay: time.minuteOfDay)
    }

    /// The round trip of line `id`'s own service, or of its pattern at
    /// index `pattern`, as a train would drive it on this map; `nil` if the
    /// line or pattern does not exist or some leg has no route.
    ///
    /// The journey starts at a berth of the first call, as a train of one
    /// car. From there each leg is the path
    /// ``path(from:toStation:length:)`` finds to the next call's station,
    /// starting where the leg before ended; stops a pattern does not call at
    /// are not aimed for. At the last call the train turns round where it
    /// stands, as ``reverseTrain(_:)`` would, and comes back the same way
    /// through the calls in reverse order. The starts are every platform of
    /// the first call (Stage S5), in order along the track, at its berth
    /// going forward and then at its berth going back (see
    /// ``TrackPlatform``). Of those whose whole round trip can be driven, the
    /// one with the shortest round trip is chosen, the first in that order
    /// among equals.
    ///
    /// Pure. Costs one drive of the service per start, each one route
    /// search per leg (see ``route(from:to:)``).
    public func lineJourney(_ id: LineID, pattern: Int? = nil) -> LineJourney? {
        guard let line = line(id: id), let service = line.service(pattern) else { return nil }
        return journey(of: line, service: service)
    }

    /// The journey of `line`'s service `service` (see
    /// ``ServiceLine/serviceCount``), as ``lineJourney(_:pattern:)``
    /// finds it.
    ///
    /// A ring's journey (decision 49) is its lap the
    /// ``RingDirection/inner`` way, from the same starts: once round, in
    /// the order of its stops, back to the first (see
    /// ``driveLap(_:calling:from:)``).
    func journey(of line: ServiceLine, service: Int) -> LineJourney? {
        let calls = line.calls(ofService: service)
        let first = line.stops[calls[0]]
        let starts = berths(of: first, length: 0).map { TrainPosition.onEdge($0.traversal, offset: $0.offset) }
        var best: LineJourney?
        var mostMatched = -1
        for start in starts {
            let placement = TrainPlacement(position: start, trailEdges: [], length: 0)
            let driven = line.isRing ? driveLap(line, calling: line.ringCalls(.inner), from: placement, routes: line.routes(ofService: service)) : drive(line, calling: calls, from: placement, routes: line.routes(ofService: service))
            guard let journey = driven else {
                continue
            }
            let matched = matchedRoutes(journey, routes: line.routes(ofService: service), start: placement)
            if matched > mostMatched || matched == mostMatched && (best == nil || journey.roundTripSeconds < best!.roundTripSeconds) {
                best = journey
                mostMatched = matched
            }
        }
        return best
    }

    /// The most trains line `id`'s own service, or its pattern at index
    /// `pattern`, can run on its own: as many as keep at least
    /// ``ServiceLine/minimumHeadwayMinutes`` between them over its round
    /// trip, and at least one. `nil` if the line or pattern does not exist
    /// or its journey cannot be driven.
    ///
    /// A ring (decision 49) runs that many each way, twice as many in all
    /// (the reference's `(isRing ? 2 : 1) * floor(…)`).
    public func lineMaximumTrains(_ id: LineID, pattern: Int? = nil) -> Int? {
        guard let journey = lineJourney(id, pattern: pattern) else { return nil }
        let eachWay = Int(clamping: max(1, journey.roundTripMinutes / ServiceLine.minimumHeadwayMinutes))
        return journey.isRing ? eachWay * 2 : eachWay
    }

    /// How many trains line `id`'s own service, or its pattern at index
    /// `pattern`, runs at `level`: the count set for that level, or at a
    /// level with a target headway the fewest trains that keep to it (its
    /// round trip divided by the target, rounded up); in both cases no more
    /// than ``lineMaximumTrains(_:pattern:)``, and for a pattern no more
    /// than still fit beside the services before it (see
    /// ``lineSegmentLoads(_:at:)``). `nil` if the line or pattern does not
    /// exist or its journey cannot be driven.
    public func lineTrainsInService(_ id: LineID, at level: ServiceLevel, pattern: Int? = nil) -> Int? {
        guard let (line, service, roundTrips) = serviceRoundTrips(id, pattern: pattern), roundTrips[service] != nil else { return nil }
        return line.services(at: level, roundTrips: roundTrips).plans[service]?.trains ?? 0
    }

    /// The minutes between two trains of line `id`'s own service, or of its
    /// pattern at index `pattern`, at `level`: its round trip shared
    /// between the trains it runs then (see
    /// ``lineTrainsInService(_:at:pattern:)``), rounded up, or at a level
    /// with a target headway the target, unless the trains it runs need
    /// longer. `nil` if the line or pattern does not exist, its journey
    /// cannot be driven, or it runs no trains at that level.
    public func lineHeadway(_ id: LineID, at level: ServiceLevel, pattern: Int? = nil) -> Int64? {
        guard let (line, service, roundTrips) = serviceRoundTrips(id, pattern: pattern) else { return nil }
        return line.services(at: level, roundTrips: roundTrips).plans[service]?.headway
    }

    /// The load on each segment of line `id` at `level`, in trains a day
    /// each way: element `i` is the segment from stop `i` to stop `i + 1`.
    /// Every service running trains then adds, on each segment from its
    /// first call to its last, a day's trains at its headway, rounded up;
    /// no segment carries more than ``ServiceLine/segmentCapacity``. A
    /// segment with no load is not covered by any service at that level.
    /// `nil` if the line does not exist.
    ///
    /// Pure. Drives every service of the line (see
    /// ``lineJourney(_:pattern:)``).
    public func lineSegmentLoads(_ id: LineID, at level: ServiceLevel) -> [Int]? {
        guard let line = line(id: id) else { return nil }
        let roundTrips = (0..<line.serviceCount).map { journey(of: line, service: $0)?.roundTripMinutes }
        return line.services(at: level, roundTrips: roundTrips).loads
    }

    /// Line `id`, the service that `pattern` names (see
    /// ``ServiceLine/serviceCount``), and the round trips of that service
    /// and every one before it, which are all that decide what it runs.
    /// `nil` if the line or pattern does not exist.
    private func serviceRoundTrips(_ id: LineID, pattern: Int?) -> (ServiceLine, Int, [Int64?])? {
        guard let line = line(id: id), let service = line.service(pattern) else { return nil }
        return (line, service, (0...service).map { journey(of: line, service: $0)?.roundTripMinutes })
    }

    /// The round trip `train` would make for `line`'s service `service`
    /// from where it stands at the first call: as it faces, or turned round
    /// first (with its head where its tail was, for a train of several
    /// cars) when only that can be driven or its round trip is shorter.
    /// `nil` if neither can be driven, or the train is not placed. The
    /// train's length decides which platforms it can stop at and where its
    /// head is once it has turned round (Stage S5).
    ///
    /// On a ring (decision 49) the trip is a lap the way the train runs
    /// (``ServiceLine/ringDirection(of:)``; the ``RingDirection/inner``
    /// way for a train not on it), from where it stands as it faces or
    /// turned round first, by the same choice.
    func trip(of line: ServiceLine, service: Int, for train: Train) -> LineTrip? {
        guard let placement = train.placement else { return nil }
        let calls = line.calls(ofService: service)
        let ahead: LineJourney?, turned: LineJourney?
        if line.isRing {
            let lap = line.ringCalls(line.ringDirection(of: train.id) ?? .inner)
            ahead = driveLap(line, calling: lap, from: placement, routes: line.routes(ofService: service))
            turned = driveLap(line, calling: lap, from: turnedRound(placement), routes: line.routes(ofService: service))
        } else {
            ahead = drive(line, calling: calls, from: placement, routes: line.routes(ofService: service))
            turned = drive(line, calling: calls, from: turnedRound(placement), routes: line.routes(ofService: service))
        }
        if let turned, ahead.map({ other in
            let a = matchedRoutes(other, routes: line.routes(ofService: service), start: placement)
            let b = matchedRoutes(turned, routes: line.routes(ofService: service), start: turnedRound(placement))
            return b > a || b == a && turned.roundTripSeconds < other.roundTripSeconds
        }) ?? true {
            return LineTrip(turnsFirst: true, journey: turned)
        }
        return ahead.map { LineTrip(turnsFirst: false, journey: $0) }
    }

    /// The round trip of `line` calling at `calls` (indices into its
    /// stops), driven from `start`, or `nil` if a leg has no route or the
    /// line's performance builds no running curve for one in up to
    /// ``RunningCurve/maximumSeconds`` (or, beyond any real map, the
    /// seconds would overflow).
    ///
    /// A train of several cars (Stage S2) turns round with its head where
    /// its tail was, and each leg takes it where
    /// ``path(from:toStation:length:)`` stops a train that long: at a berth
    /// of a platform it fits (Stage S5). Each leg's seconds are the least in
    /// which the line's performance builds a running curve for its exact
    /// distance (Stage W2c).
    func drive(_ line: ServiceLine, calling calls: [Int], from start: TrainPlacement, routes: [LineRoutePreference]) -> LineJourney? {
        let farEnd = calls[calls.count - 1]
        let order = calls + calls.dropLast().reversed()
        var placement = start
        var legs: [LineLeg] = []
        var seconds = (ServiceLine.terminalDwellMinutes * 2 + ServiceLine.dwellMinutes * Int64(2 * (calls.count - 2))) * GameTime.secondsPerMinute
        for (from, to) in zip(order, order.dropFirst()) {
            if from == farEnd {
                // The far end: turn round before coming back.
                placement = turnedRound(placement)
            }
            guard let path = linePath(line, from: from, to: to, start: placement.position, length: placement.length, routes: routes) else { return nil }
            var legSeconds: Int64 = 0
            if path.distance > 0 {
                guard let least = RunningCurve.leastSeconds(length: path.distance, performance: line.performance) else { return nil }
                legSeconds = least
            }
            let (total, overflow) = seconds.addingReportingOverflow(legSeconds)
            guard !overflow else { return nil }
            seconds = total
            legs.append(LineLeg(from: from, to: to, path: path, seconds: legSeconds))
            placement = self.placement(placement, after: path)
        }
        return LineJourney(start: start.position, legs: legs, roundTripSeconds: seconds)
    }

    /// A ring's lap calling at `calls` (indices into its stops, from the
    /// first stop round to it again, see ``ServiceLine/ringCalls(_:)``),
    /// driven from `start`, or `nil` as for ``drive(_:calling:from:)``
    /// (decision 49). Each leg as there, never turning round; the lap's
    /// seconds are every leg and ``ServiceLine/dwellMinutes`` at each stop
    /// it calls at once round (the reference's
    /// `metroHeadwayRoundTripMinutes` for a ring: one dwell a stop, no
    /// terminal).
    func driveLap(_ line: ServiceLine, calling calls: [Int], from start: TrainPlacement, routes: [LineRoutePreference]) -> LineJourney? {
        var placement = start
        var legs: [LineLeg] = []
        var seconds = ServiceLine.dwellMinutes * Int64(calls.count - 1) * GameTime.secondsPerMinute
        for (from, to) in zip(calls, calls.dropFirst()) {
            guard let path = linePath(line, from: from, to: to, start: placement.position, length: placement.length, routes: routes) else { return nil }
            var legSeconds: Int64 = 0
            if path.distance > 0 {
                guard let least = RunningCurve.leastSeconds(length: path.distance, performance: line.performance) else { return nil }
                legSeconds = least
            }
            let (total, overflow) = seconds.addingReportingOverflow(legSeconds)
            guard !overflow else { return nil }
            seconds = total
            legs.append(LineLeg(from: from, to: to, path: path, seconds: legSeconds))
            placement = self.placement(placement, after: path)
        }
        return LineJourney(start: start.position, legs: legs, roundTripSeconds: seconds, isRing: true)
    }
}
