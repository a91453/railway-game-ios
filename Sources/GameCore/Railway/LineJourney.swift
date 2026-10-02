// Service line journeys (Phase 4 Stage Q2a). A line is plan data; what its
// trains would take, and how often they could run, is derived here from the
// map on every query and never stored, like connectivity, routes and stops.
// Since Phase 4.5 Stage S5 a journey is driven on the grid or on the track
// network by the same rules: each leg is a TrainPath and takes its exact
// distance at the line's rate (ARCHITECTURE decision 31).
// The rules port the web reference's service planning to whole minutes
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
    /// previous leg ended: links on the grid, edges to a platform's berth on
    /// the track network. No traversals and no distance when the train is
    /// already where it stops for the next call (a platform both share).
    public let path: TrainPath
    /// Whole minutes the leg takes at the line's rate: the path's distance
    /// divided by the rate, rounded up.
    public let minutes: Int64

    public init(from: Int, to: Int, path: TrainPath, minutes: Int64) {
        self.from = from
        self.to = to
        self.path = path
        self.minutes = minutes
    }

    /// On the grid, the continuation the leg takes: the tiles its links
    /// lead to, as ``GameWorld/route(from:toStation:length:)`` gives it.
    /// Empty on the track network.
    public var route: [GridPosition] {
        path.traversals.compactMap(\.tileAhead)
    }
}

/// A service's round trip as a train would drive it: out from its first
/// call to its last, turning round there, and back to the first. For a
/// line's own service the calls are all its stops; for a pattern, the
/// pattern's calls.
public struct LineJourney: Hashable, Sendable {
    /// Where the journey starts: at a platform of the first call, facing the
    /// way it leaves; on the track network, at a berth of one of its
    /// platforms (Stage S5).
    public let start: TrainPosition
    /// The legs out, then the legs back: `2 × (calls − 1)` of them.
    public let legs: [LineLeg]
    /// The minutes the whole round trip takes: every leg, plus
    /// ``ServiceLine/dwellMinutes`` at each call between the ends (once out
    /// and once back) and ``ServiceLine/terminalDwellMinutes`` at each end.
    public let roundTripMinutes: Int64

    public init(start: TrainPosition, legs: [LineLeg], roundTripMinutes: Int64) {
        self.start = start
        self.legs = legs
        self.roundTripMinutes = roundTripMinutes
    }
}

/// One round trip a line sends a train on (Stage Q2b): whether the train
/// turns round before it leaves the first call, and the journey it drives
/// from there.
struct LineTrip: Hashable, Sendable {
    let turnsFirst: Bool
    let journey: LineJourney

    /// The trip's timetable, calling at the line's `stops` that the legs
    /// reach, leaving the first call at `departure`, or `nil` if a time
    /// would pass the largest second.
    ///
    /// One call per leg and one to start: the first call (arrival and
    /// departure at `departure`, turning round first if the trip does),
    /// then each leg's call, arriving the leg's minutes after the call
    /// before it left. A call between the ends stays
    /// ``ServiceLine/dwellMinutes``; the far end stays
    /// ``ServiceLine/terminalDwellMinutes`` and turns the train round; back
    /// at the first call the train arrives, turns round and the trip is
    /// over, the train waiting there for the rest of its terminal dwell. So
    /// a train on time is back ready to leave `roundTripMinutes` after it
    /// left. The minutes are whole minutes of game seconds.
    ///
    /// - Precondition: `departure` is second 0 or later.
    func timetable(calling stops: [StationID], leavingAt departure: GameTime) -> [ScheduledStop]? {
        let legs = journey.legs
        let farEnd = legs[legs.count / 2 - 1].to
        var timetable = [ScheduledStop(station: stops[legs[0].from], arrival: departure, departure: departure, reverses: turnsFirst)]
        var time = departure.seconds
        for (index, leg) in legs.enumerated() {
            let isLast = index == legs.count - 1
            let isFarEnd = leg.to == farEnd
            let dwell = isLast ? 0 : isFarEnd ? ServiceLine.terminalDwellMinutes : ServiceLine.dwellMinutes
            let (travel, long) = leg.minutes.multipliedReportingOverflow(by: GameTime.secondsPerMinute)
            let (arrival, late) = time.addingReportingOverflow(travel)
            let (leaving, later) = arrival.addingReportingOverflow(dwell * GameTime.secondsPerMinute)
            guard !long, !late, !later else { return nil }
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
    /// The journey starts at a platform of the first call, as a train of one
    /// car. From there each leg is the path
    /// ``path(from:toStation:length:)`` finds to the next call's station,
    /// starting where the leg before ended; stops a pattern does not call at
    /// are not aimed for. At the last call the train turns round where it
    /// stands, as ``reverseTrain(_:)`` would, and comes back the same way
    /// through the calls in reverse order. The starts are every grid
    /// platform of the first call, in ``platforms(of:)`` order, each facing
    /// north, east, south and west in turn; then (Stage S5) every platform it
    /// has on the track network, in order along the track, at its berth going
    /// forward and then at its berth going back (see ``TrackPlatform``). Of
    /// those whose whole round trip can be driven, the one with the shortest
    /// round trip is chosen, the first in that order among equals. A journey
    /// that starts on the grid stays on the grid, and one on the network on
    /// the network.
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
    func journey(of line: ServiceLine, service: Int) -> LineJourney? {
        let calls = line.calls(ofService: service)
        let first = line.stops[calls[0]]
        let starts = platforms(of: first).flatMap { platform in TrackDirection.allCases.map { TrainPosition.atNode(platform, heading: $0) } }
            + berths(of: first, length: 0).map { TrainPosition.onEdge($0.traversal, offset: $0.offset) }
        var best: LineJourney?
        for start in starts {
            guard let journey = drive(line, calling: calls, from: TrainPlacement(position: start, trail: [], trailEdges: [], length: 0)) else {
                continue
            }
            if best == nil || journey.roundTripMinutes < best!.roundTripMinutes {
                best = journey
            }
        }
        return best
    }

    /// The most trains line `id`'s own service, or its pattern at index
    /// `pattern`, can run on its own: as many as keep at least
    /// ``ServiceLine/minimumHeadwayMinutes`` between them over its round
    /// trip, and at least one. `nil` if the line or pattern does not exist
    /// or its journey cannot be driven.
    public func lineMaximumTrains(_ id: LineID, pattern: Int? = nil) -> Int? {
        guard let roundTrip = lineJourney(id, pattern: pattern)?.roundTripMinutes else { return nil }
        return Int(clamping: max(1, roundTrip / ServiceLine.minimumHeadwayMinutes))
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
    /// `nil` if neither can be driven, or the train is not placed. On the
    /// grid or the track network alike (Stage S5): the train's length
    /// decides which platforms it can stop at and where its head is once it
    /// has turned round.
    func trip(of line: ServiceLine, service: Int, for train: Train) -> LineTrip? {
        guard let placement = train.placement else { return nil }
        let calls = line.calls(ofService: service)
        let ahead = drive(line, calling: calls, from: placement)
        let turned = drive(line, calling: calls, from: turnedRound(placement))
        if let turned, ahead.map({ turned.roundTripMinutes < $0.roundTripMinutes }) ?? true {
            return LineTrip(turnsFirst: true, journey: turned)
        }
        return ahead.map { LineTrip(turnsFirst: false, journey: $0) }
    }

    /// The round trip of `line` calling at `calls` (indices into its
    /// stops), driven from `start`, or `nil` if a leg has no route (or,
    /// beyond any real map, the minutes would overflow).
    ///
    /// A train of several cars (Stage S2) turns round with its head where
    /// its tail was, and each leg takes it where
    /// ``path(from:toStation:length:)`` stops a train that long: on the grid
    /// pulled along each station's platforms, on the track network (Stage
    /// S5) at a berth of a platform it fits. Each leg's minutes are its
    /// exact distance at the line's rate, rounded up; on the grid every leg
    /// starts at a node (a train is sent out stopped at a platform, and its
    /// length is whole links), so that is 1024 a link.
    func drive(_ line: ServiceLine, calling calls: [Int], from start: TrainPlacement) -> LineJourney? {
        let stops = line.stops
        let farEnd = calls[calls.count - 1]
        let order = calls + calls.dropLast().reversed()
        var placement = start
        var legs: [LineLeg] = []
        var minutes = ServiceLine.terminalDwellMinutes * 2 + ServiceLine.dwellMinutes * Int64(2 * (calls.count - 2))
        for (from, to) in zip(order, order.dropFirst()) {
            if from == farEnd {
                // The far end: turn round before coming back.
                placement = turnedRound(placement)
            }
            guard let path = path(from: placement.position, toStation: stops[to], length: placement.length) else { return nil }
            let legMinutes = path.distance / line.rate + (path.distance % line.rate == 0 ? 0 : 1)
            let (total, overflow) = minutes.addingReportingOverflow(legMinutes)
            guard !overflow else { return nil }
            minutes = total
            legs.append(LineLeg(from: from, to: to, path: path, minutes: legMinutes))
            placement = self.placement(placement, after: path)
        }
        return LineJourney(start: start.position, legs: legs, roundTripMinutes: minutes)
    }
}
