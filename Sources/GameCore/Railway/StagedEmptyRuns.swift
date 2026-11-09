// Empty runs a station at a time (decision 666). Under traffic control
// without block sections a train takes its route whole, or follows a
// train ahead that it can be sure leads the way (Stage U2). A service
// takes its route a call at a time, from one station to the next; an
// empty run out of a depot (decision 221) has only two calls, the depot
// and the end of its run, so it must take all the way at once. On a line
// with trains every few minutes that whole way is never free: on the
// Taoyuan Airport MRT the run from the Luzhu depot to Huanbei, thirteen
// minutes, waited from 14:00 to 15:44 on the second day and the evening's
// shuttles went without a train (TYMC-AFTERNOON).
//
// A real railway sends empty stock along the line as it sends its trains,
// a station at a time. So when an empty run out of a depot cannot take
// its whole route, it is sent instead calling at each station of its line
// on the way, without passengers, the least dwell each: it then takes its
// route a call at a time, as the services do, and the dispatcher's ways
// out of a deadlock know it as they know them. With block sections (whose
// own rules already take a route a block at a time) or traffic control
// off, nothing changes; nor for an empty run that can take its whole way.

extension GameWorld {
    /// Decision 666: `trip`, an empty run of `train` out of a depot to a
    /// stop of `line` (see ``emptyRun(of:for:to:facing:)``), calling at
    /// each station of the line whose platform its way passes over before
    /// its end, in the order it reaches them, the least dwell each; its
    /// seconds shared among the calls by distance. `nil` with traffic
    /// control off, with block sections, or when its way passes no such
    /// station.
    func stagedEmptyRun(of line: ServiceLine, for train: Train, _ trip: LineTrip) -> LineTrip? {
        guard isTrafficControlEnabled, !blockSections, let run = trip.deadhead, run.calls.isEmpty,
              let placement = train.placement else { return nil }
        let from = trip.turnsFirst ? turnedRound(placement) : placement
        guard let path = path(from: from.position, toStation: run.to, length: train.length), path.distance > 0,
              case .onEdge(let first, let offset) = from.position, let edge = network.edge(first.edge) else { return nil }
        let stops = Set(line.stops).subtracting([run.from, run.to])
        // How far along the way the head stops at each station's
        // platform, the first it reaches of each.
        var platforms: [TrackEdgeID: [TrackPlatform]] = [:]
        for platform in network.platforms where stops.contains(platform.station) && platform.length >= train.length
            && station(id: platform.station)?.isDepot == false {
            platforms[platform.edge, default: []].append(platform)
        }
        var reached: [(station: StationID, distance: Int64)] = []
        var start = -offset
        var length = edge.length
        for traversal in [first] + path.traversals {
            defer { start += length }
            if traversal != first {
                guard let next = network.edge(traversal.edge) else { return nil }
                length = next.length
            }
            for platform in platforms[traversal.edge] ?? [] where !reached.contains(where: { $0.station == platform.station }) {
                let stop = start + (traversal.direction == .forward ? platform.end : length - platform.start)
                guard stop > 0, stop < path.distance else { continue }
                reached.append((platform.station, stop))
            }
        }
        reached.sort { $0.distance < $1.distance }
        guard !reached.isEmpty else { return nil }
        var calls: [LineTrip.DeadheadRun.Call] = []
        var before: Int64 = 0
        var spent: Int64 = 0
        for stop in reached {
            let seconds = max(1, run.seconds * (stop.distance - before) / path.distance)
            calls.append(.init(station: stop.station, seconds: seconds))
            spent += seconds
            before = stop.distance
        }
        let last = max(1, run.seconds - spent)
        let seconds = spent + last + ServiceDwell.minimum * Int64(calls.count)
        var staged = LineTrip.DeadheadRun(from: run.from, to: run.to, seconds: seconds)
        staged.calls = calls
        return LineTrip(turnsFirst: trip.turnsFirst, journey: trip.journey, deadhead: staged)
    }
}
