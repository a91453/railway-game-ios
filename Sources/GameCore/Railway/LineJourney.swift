// Service line journeys (Phase 4 Stage Q2a). A line is plan data; what its
// trains would take, and how often they could run, is derived here from the
// map on every query and never stored, like connectivity, routes and stops.
// The rules port the web reference's service planning to whole minutes
// (docs/WEB_REFERENCE_STUDY.md): the round trip is every leg out and back
// plus a dwell at every call between the ends and a longer one at each end;
// a line runs at most as many trains as keep the minimum headway, and the
// headway is the round trip shared between its trains.

/// One leg of a line's journey: from one call to the next.
public struct LineLeg: Hashable, Sendable {
    /// The index, in the line's stops, of the call the leg leaves.
    public let from: Int
    /// The index, in the line's stops, of the call the leg reaches.
    public let to: Int
    /// The continuation the leg takes, as ``GameWorld/route(from:toStation:)``
    /// gives it from where the previous leg ended; empty when the train is
    /// already at the next call's station (a platform both share).
    public let route: [GridPosition]
    /// Whole minutes the leg takes at the line's rate: its links times
    /// ``TrainPosition/linkLength`` divided by the rate, rounded up.
    public let minutes: Int64

    public init(from: Int, to: Int, route: [GridPosition], minutes: Int64) {
        self.from = from
        self.to = to
        self.route = route
        self.minutes = minutes
    }
}

/// A line's round trip as a train would drive it: out from its first stop
/// to its last, turning round there, and back to the first.
public struct LineJourney: Hashable, Sendable {
    /// Where the journey starts: at a platform of the first stop, facing the
    /// way it leaves.
    public let start: TrainPosition
    /// The legs out, then the legs back: `2 × (stops − 1)` of them.
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
/// turns round before it leaves the first stop, and the journey it drives
/// from there.
struct LineTrip: Hashable, Sendable {
    let turnsFirst: Bool
    let journey: LineJourney

    /// The trip's timetable, calling at `stops` (the line's), leaving the
    /// first stop at `departure`, or `nil` if a time would pass the largest
    /// minute.
    ///
    /// One call per stop: the first stop (arrival and departure at
    /// `departure`, turning round first if the trip does), then each leg's
    /// call, arriving the leg's minutes after the call before it left. A
    /// call between the ends stays ``ServiceLine/dwellMinutes``; the last
    /// stop stays ``ServiceLine/terminalDwellMinutes`` and turns the train
    /// round; back at the first stop the train arrives, turns round and
    /// the trip is over, the train waiting there for the rest of its
    /// terminal dwell. So a train on time is back ready to leave
    /// `roundTripMinutes` after it left.
    ///
    /// - Precondition: `departure` is minute 0 or later.
    func timetable(calling stops: [StationID], leavingAt departure: GameTime) -> [ScheduledStop]? {
        var timetable = [ScheduledStop(station: stops[0], arrival: departure, departure: departure, reverses: turnsFirst)]
        var time = departure.minutes
        for (index, leg) in journey.legs.enumerated() {
            let isLast = index == journey.legs.count - 1
            let isFarEnd = leg.to == stops.count - 1
            let dwell = isLast ? 0 : isFarEnd ? ServiceLine.terminalDwellMinutes : ServiceLine.dwellMinutes
            let (arrival, late) = time.addingReportingOverflow(leg.minutes)
            let (leaving, later) = arrival.addingReportingOverflow(dwell)
            guard !late, !later else { return nil }
            timetable.append(ScheduledStop(
                station: stops[leg.to], arrival: GameTime(minutes: arrival), departure: GameTime(minutes: leaving),
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

    /// Line `id`'s round trip as a train would drive it on this map, or
    /// `nil` if the line does not exist or some leg has no route.
    ///
    /// The journey starts at a platform of the first stop facing one of the
    /// four directions. From there each leg is the route
    /// ``route(from:toStation:)`` finds to the next call's station, starting
    /// where the leg before ended. At the last stop the train turns round
    /// where it stands, as ``reverseTrain(_:)`` would, and comes back the
    /// same way through the stops in reverse order. Of the starts (every
    /// platform of the first stop, in ``platforms(of:)`` order, each facing
    /// north, east, south and west in turn) whose whole round trip can be
    /// driven, the one with the shortest round trip is chosen, the first in
    /// that order among equals.
    ///
    /// Pure. Costs up to sixteen drives of the line, each one route search
    /// per leg (see ``route(from:to:)``).
    public func lineJourney(_ id: LineID) -> LineJourney? {
        guard let line = line(id: id) else { return nil }
        var best: LineJourney?
        for platform in platforms(of: line.stops[0]) {
            for heading in TrackDirection.allCases {
                guard let journey = drive(line, from: .atNode(platform, heading: heading)) else { continue }
                if best == nil || journey.roundTripMinutes < best!.roundTripMinutes {
                    best = journey
                }
            }
        }
        return best
    }

    /// The most trains line `id` can run: as many as keep at least
    /// ``ServiceLine/minimumHeadwayMinutes`` between them over its round
    /// trip, and at least one. `nil` if the line does not exist or its
    /// journey cannot be driven.
    public func lineMaximumTrains(_ id: LineID) -> Int? {
        guard let roundTrip = lineJourney(id)?.roundTripMinutes else { return nil }
        return Int(clamping: max(1, roundTrip / ServiceLine.minimumHeadwayMinutes))
    }

    /// How many trains line `id` runs at `level`: the count set for that
    /// level, or at a level with a target headway the fewest trains that
    /// keep to it (its round trip divided by the target, rounded up); in
    /// both cases no more than ``lineMaximumTrains(_:)``. `nil` if the line
    /// does not exist or its journey cannot be driven.
    public func lineTrainsInService(_ id: LineID, at level: ServiceLevel) -> Int? {
        guard let line = line(id: id), let roundTrip = lineJourney(id)?.roundTripMinutes else { return nil }
        return line.service(at: level, roundTrip: roundTrip)?.trains ?? 0
    }

    /// The minutes between two trains of line `id` at `level`: its round
    /// trip shared between the trains it runs then, rounded up, or at a
    /// level with a target headway the target, unless the trains the line
    /// can run need longer. `nil` if the line does not exist, its journey
    /// cannot be driven, or it runs no trains at that level.
    public func lineHeadway(_ id: LineID, at level: ServiceLevel) -> Int64? {
        guard let line = line(id: id), let roundTrip = lineJourney(id)?.roundTripMinutes else { return nil }
        return line.service(at: level, roundTrip: roundTrip)?.headway
    }

    /// The round trip line `line`'s train would make from `position`,
    /// where it stands at the first stop: as it faces, or turned round
    /// first when only that can be driven or its round trip is shorter.
    /// `nil` if neither can be driven.
    func trip(of line: ServiceLine, from position: TrainPosition) -> LineTrip? {
        let ahead = drive(line, from: position)
        let turned = drive(line, from: position.reversed)
        if let turned, ahead.map({ turned.roundTripMinutes < $0.roundTripMinutes }) ?? true {
            return LineTrip(turnsFirst: true, journey: turned)
        }
        return ahead.map { LineTrip(turnsFirst: false, journey: $0) }
    }

    /// The round trip of `line` driven from `start`, or `nil` if a leg has
    /// no route (or, beyond any real map, the minutes would overflow).
    func drive(_ line: ServiceLine, from start: TrainPosition) -> LineJourney? {
        let stops = line.stops
        let calls = Array(stops.indices) + stops.indices.dropLast().reversed()
        var position = start
        var legs: [LineLeg] = []
        var minutes = ServiceLine.terminalDwellMinutes * 2 + ServiceLine.dwellMinutes * Int64(2 * (stops.count - 2))
        for (from, to) in zip(calls, calls.dropFirst()) {
            if from == stops.count - 1 {
                // The far end: turn round before coming back.
                position = position.reversed
            }
            guard let route = route(from: position, toStation: stops[to]) else { return nil }
            let distance = Int64(route.count) * TrainPosition.linkLength
            let legMinutes = distance / line.rate + (distance % line.rate == 0 ? 0 : 1)
            let (total, overflow) = minutes.addingReportingOverflow(legMinutes)
            guard !overflow else { return nil }
            minutes = total
            legs.append(LineLeg(from: from, to: to, route: route, minutes: legMinutes))
            if let last = route.last {
                let before = route.count >= 2 ? route[route.count - 2] : position.ahead.node
                position = .atNode(last, heading: TrackDirection(from: before, to: last)!)
            }
        }
        return LineJourney(start: start, legs: legs, roundTripMinutes: minutes)
    }
}
