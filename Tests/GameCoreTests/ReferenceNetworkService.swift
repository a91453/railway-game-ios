import GameCore

/// Decision 31 (Stage S5), written a second time for ``ReferenceWorld``:
/// stops, timetables, lines and dispatch on the track network. Written from
/// the rules, not from GameCore, and differently where it can be:
///
/// - a platform is looked at along the run the train is on (its stretch
///   measured the way the train travels), never by chainage from the edge's
///   `from` node;
/// - the way to a station is the distance from the start of every run to
///   the nearest berth, relaxed until nothing changes, then a greedy walk
///   taking the first choice that keeps to it (not a search in order of
///   distance over places);
/// - a train already where it stops for the next call is recognised by
///   standing at the far end of a platform it fits, not by a path of no
///   distance;
/// - after a leg the train's body is read off the whole path it came along,
///   as the reference's movement does, not cut edge by edge;
/// - a journey on the network is driven by its own loop, beside the grid's.
extension ReferenceWorld {
    // MARK: - Platforms and stops

    /// `platform`'s stretch along `run`: where a train travelling that way
    /// reaches it and where it leaves it.
    func stretch(of platform: TrackPlatform, along run: Run) -> (from: Int64, to: Int64) {
        let length = networkEdges[run.edge]!.length
        return run.forward ? (platform.start, platform.end) : (length - platform.end, length - platform.start)
    }

    /// Whether `train`'s path on the network is spent: no edge left to
    /// enter, and the head where the path ends.
    func isStanding(_ train: Train) -> Bool {
        guard case .onEdge(let traversal, let offset)? = train.position, let run = Run(traversal), let edge = networkEdges[run.edge] else { return false }
        return train.cursor >= train.edges.count && offset == (train.end ?? edge.length)
    }

    /// The stations a standing train's head is on a platform of, on its
    /// own edge, ends included; by ID.
    func networkStops(of train: Train) -> [StationID] {
        guard isStanding(train), case .onEdge(let traversal, let offset)? = train.position, let run = Run(traversal) else { return [] }
        var found: Set<Int> = []
        for station in stations {
            for platform in station.trackPlatforms where platform.edge == traversal.edge {
                let (from, to) = stretch(of: platform, along: run)
                if from <= offset, offset <= to { found.insert(station.id) }
            }
        }
        return found.sorted().map(StationID.init(rawValue:))
    }

    /// Where a train `length` long stops for station `id`, by run: the far
    /// end, the way it travels, of each platform no shorter than the train;
    /// nearest first.
    func berthsForStation(_ id: StationID, length: Int64) -> [Run: [Int64]] {
        guard let station = stations.first(where: { $0.id == id.rawValue }) else { return [:] }
        var berths: [Run: [Int64]] = [:]
        for platform in station.trackPlatforms where platform.end - platform.start >= length {
            for forward in [true, false] {
                let run = Run(edge: platform.edge.number, forward: forward)
                berths[run, default: []].append(stretch(of: platform, along: run).to)
            }
        }
        return berths.mapValues { $0.sorted() }
    }

    /// Whether `train` stands at the far end of a platform of station `id`
    /// that it fits, the way it travels.
    func isAtBerth(_ train: Train, of id: StationID) -> Bool {
        guard case .onEdge(let traversal, let offset)? = train.position, let run = Run(traversal) else { return false }
        return berthsForStation(id, length: Self.length(train))[run]?.contains(offset) == true
    }

    // MARK: - The way to a station

    /// The distance from the start of every run to the nearest of `berths`
    /// ahead of it, relaxed until nothing changes; runs that lead to none
    /// are left out.
    func distancesToBerths(_ berths: [Run: [Int64]]) -> [Run: Int64] {
        let allRuns = networkEdges.keys.sorted().flatMap { [Run(edge: $0, forward: true), Run(edge: $0, forward: false)] }
        var best: [Run: Int64] = [:]
        for run in allRuns {
            if let nearest = berths[run]?.first { best[run] = nearest }
        }
        var changed = true
        while changed {
            changed = false
            for run in allRuns {
                let length = networkEdges[run.edge]!.length
                for next in runs(after: run) {
                    guard let beyond = best[next], length + beyond < best[run] ?? .max else { continue }
                    best[run] = length + beyond
                    changed = true
                }
            }
        }
        return best
    }

    /// Decision 31: the way a train `length` long at `position` on the
    /// network gets to where it stops for station `id`: the least distance
    /// and, among equals, the choices that come first step by step (a berth
    /// ahead on the same run, nearest first, before any turn; turns by
    /// ascending edge number).
    func networkPathToStation(from position: TrainPosition, station id: StationID, length: Int64) -> TrainPath? {
        guard case .onEdge(let traversal, let offset) = position, let start = Run(traversal), isOnNetwork(traversal, offset) else { return nil }
        let berths = berthsForStation(id, length: length)
        guard !berths.isEmpty else { return nil }
        let best = distancesToBerths(berths)
        var (run, at) = (start, offset)
        var taken: [Run] = []
        var total: Int64 = 0
        while true {
            let runLength = networkEdges[run.edge]!.length
            // In the order that breaks ties: berths ahead, then turns.
            var choices: [(berth: Int64?, next: Run?, cost: Int64, beyond: Int64)] = []
            for berth in berths[run] ?? [] where berth >= at {
                choices.append((berth, nil, berth - at, 0))
            }
            for next in runs(after: run) {
                if let beyond = best[next] { choices.append((nil, next, runLength - at, beyond)) }
            }
            guard let least = choices.map({ $0.cost + $0.beyond }).min() else { return nil }
            let pick = choices.first { $0.cost + $0.beyond == least }!
            total += pick.cost
            if let berth = pick.berth {
                return TrainPath(traversals: taken.map(\.traversal), end: berth == runLength ? nil : berth, distance: total)
            }
            run = pick.next!
            at = 0
            taken.append(run)
        }
    }

    /// Decision 31: the way to station `id` for a train of `length` at
    /// `start`, on the grid (its route as links) or on the network.
    func pathToStation(from start: TrainPosition, station id: StationID, length: Int64) -> TrainPath? {
        if case .onEdge = start { return networkPathToStation(from: start, station: id, length: length) }
        guard isOnTrack(start), let route = route(from: start, toStation: id, length: length) else { return nil }
        var node = Self.ahead(start).0
        let links = route.map { next -> TrackTraversal in
            defer { node = next }
            return TrackTraversal.link(from: node, to: next)
        }
        let rest: Int64 = if case .onLink(_, _, let offset) = start { Self.linkLength - offset } else { 0 }
        return TrainPath(traversals: links, end: nil, distance: rest + Int64(route.count) * Self.linkLength)
    }

    // MARK: - Trains

    /// `train` standing where it is: its path on the network ends at its
    /// head.
    func standing(_ train: Train) -> Train {
        var train = train
        guard case .onEdge(let traversal, let offset)? = train.position, let run = Run(traversal) else { return train }
        train.edges = []
        train.cursor = 0
        train.end = offset == networkEdges[run.edge]!.length ? nil : offset
        return train
    }

    /// `train` once its head has followed `path` on the network to where it
    /// stops: its body read off the whole way it came.
    func followed(_ train: Train, along path: TrainPath) -> Train {
        var train = train
        let before = self.path(of: train)
        let entered = path.traversals.map { Run($0)! }
        let last = entered.last ?? before[before.count - 1]
        let end = path.end ?? networkEdges[last.edge]!.length
        train.position = .onEdge(last.traversal, offset: end)
        train.trailEdges = trail(on: before + entered, offset: end, length: Self.length(train))
        return train
    }

    /// A train of `length` (in whole cars) at `position` with body
    /// `trailEdges`, to drive a journey with.
    static func driver(at position: TrainPosition, trailEdges: [Int], length: Int64) -> Train {
        Train(id: 0, name: "", position: position, cars: Int(length / linkLength) + 1, trailEdges: trailEdges)
    }

    // MARK: - Services

    /// Decision 20's departures (with decision 21's turning and repeats) for
    /// a train on the network, one at a time: turned first where the stop
    /// says so, but only if it then finishes, is already at a berth of the
    /// next call's station, or finds a way there; then standing, or setting
    /// off. Decision 32: under traffic control, only if the train can take
    /// what that needs. `true` when it arrived at once.
    mutating func departOnNetwork(_ i: Int) -> Bool {
        let service = trains[i].service!
        let stop = trains[i].timetable[service.stop]
        let start = stop.reverses ? turnedOnNetwork(trains[i]) : trains[i]
        var next = (stop: service.stop + 1, cycle: service.cycle)
        if next.stop == trains[i].timetable.count {
            next = (0, service.cycle + 1)
            if trains[i].period == nil || !Self.fits(trains[i], cycle: next.cycle) {
                var done = standing(start)
                done.service = nil
                _ = admit(done, at: i)
                return false
            }
        }
        let target = trains[i].timetable[next.stop].station
        if isAtBerth(start, of: target) {
            var there = standing(start)
            there.service = Service(stop: next.stop, waiting: true, cycle: next.cycle, arrival: clockSeconds, departure: clockSeconds)
            departedDistance = 0
            return admit(there, at: i) == nil
        }
        let key = RouteMemo.Key(start: start.position!, station: target, length: Self.length(start))
        let found = routeMemo.network[key] ?? networkPathToStation(from: start.position!, station: target, length: Self.length(start))
        routeMemo.network[key] = .some(found)
        guard let path = found else { return false }
        departedDistance = path.distance
        var off = standing(start)
        off.edges = path.traversals.map { Run($0)!.edge }
        off.cursor = 0
        off.end = path.end
        off.service = Service(stop: next.stop, waiting: false, cycle: next.cycle, arrival: service.arrival, departure: clockSeconds)
        _ = admit(off, at: i)
        return false
    }

    /// Decision 31: whether removing `platform` would take a platform from
    /// a service: one waiting at its station with its head on it, or
    /// travelling there along a path whose last edge is the platform's.
    func serviceNeeding(_ platform: TrackPlatform) -> TrainID? {
        for train in trains.sorted(by: { $0.id < $1.id }) {
            guard let service = train.service, train.timetable[service.stop].station == platform.station,
                  case .onEdge(let traversal, let offset)? = train.position, let run = Run(traversal)
            else { continue }
            if service.waiting {
                let (from, to) = stretch(of: platform, along: run)
                if traversal.edge == platform.edge, from <= offset, offset <= to { return TrainID(rawValue: train.id) }
            } else {
                let last = train.cursor < train.edges.count ? train.edges[train.edges.count - 1] : run.edge
                if TrackEdgeID.edge(last) == platform.edge { return TrainID(rawValue: train.id) }
            }
        }
        return nil
    }

    // MARK: - Lines

    /// Decision 31: every berth of station `id` a line's journey may start
    /// from, in order along the track: each platform going forward, then
    /// going back.
    func journeyStarts(onNetworkOf id: StationID) -> [TrainPosition] {
        guard let station = stations.first(where: { $0.id == id.rawValue }) else { return [] }
        return station.trackPlatforms.flatMap { platform in
            [true, false].map { forward in
                let run = Run(edge: platform.edge.number, forward: forward)
                return TrainPosition.onEdge(run.traversal, offset: stretch(of: platform, along: run).to)
            }
        }
    }

    /// The line driven once on the network from `start` for a train of
    /// `length` with body `trailEdges`: out along `calls`, turned at the
    /// last, back; `nil` if a leg has no way.
    func networkJourney(of line: Line, calling calls: [Int], from start: TrainPosition, trailEdges: [Int], length: Int64) -> LineJourney? {
        let n = calls.count
        var train = Self.driver(at: start, trailEdges: trailEdges, length: length)
        var legs: [LineLeg] = []
        var pairs: [(Int, Int)] = (0..<(n - 1)).map { (calls[$0], calls[$0 + 1]) }
        pairs += (1..<n).reversed().map { (calls[$0], calls[$0 - 1]) }
        for (from, to) in pairs {
            if from == calls[n - 1] { train = turnedOnNetwork(train) }
            guard let path = networkPathToStation(from: train.position!, station: line.stops[to], length: length) else { return nil }
            let units = path.distance
            legs.append(LineLeg(from: from, to: to, path: path, minutes: units == 0 ? 0 : (units - 1) / line.rate + 1))
            train = followed(train, along: path)
        }
        let total = legs.reduce(Int64(0)) { $0 + $1.minutes } + 2 * 2 + Int64(2 * (n - 2)) * 1
        return LineJourney(start: start, legs: legs, roundTripMinutes: total)
    }
}
