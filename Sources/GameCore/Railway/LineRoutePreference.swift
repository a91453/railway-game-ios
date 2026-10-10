// Decision 61: dispatch.pathIds translated to a player's directed edge
// walk and destination platform. Plan data belongs to a line service,
// never to a station or a ScheduledStop. Distances use 64 units/metre.

/// A preferred physical path for one directed leg of a line service.
/// `from` and `to` are indices in the line's stops, including for patterns.
/// `tracks` includes the starting edge and the destination platform edge.
/// An empty walk selects only the platform, leaving the path automatic.
public struct LineRoutePreference: Hashable, Sendable, Codable {
    public let from: Int
    public let to: Int
    public let tracks: [TrackTraversal]
    public let platform: TrackPlatform

    public init(from: Int, to: Int, tracks: [TrackTraversal] = [], platform: TrackPlatform) {
        self.from = from
        self.to = to
        self.tracks = tracks
        self.platform = platform
    }

    private enum CodingKeys: String, CodingKey { case from, to, tracks, platform }
    private struct Track: Codable {
        let edge: Int
        let forward: Bool
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tracks = try c.decode([Track].self, forKey: .tracks)
        guard tracks.allSatisfy({ $0.edge >= 1 }) else {
            throw DecodingError.dataCorruptedError(forKey: .tracks, in: c, debugDescription: "Track IDs start at 1.")
        }
        self.init(from: try c.decode(Int.self, forKey: .from), to: try c.decode(Int.self, forKey: .to),
                  tracks: tracks.map { TrackTraversal(edge: .edge($0.edge), direction: $0.forward ? .forward : .backward) },
                  platform: try c.decode(TrackPlatform.self, forKey: .platform))
        guard from >= 0, to >= 0, from != to, platform.start >= 0, platform.end > platform.start,
              self.tracks.isEmpty || self.tracks.last?.edge == platform.edge else {
            throw DecodingError.dataCorruptedError(forKey: .platform, in: c, debugDescription: "A preference needs distinct nonnegative calls and a platform on its last track.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(tracks.map { Track(edge: $0.edge.networkNumber!, forward: $0.direction == .forward) }, forKey: .tracks)
        try c.encode(platform, forKey: .platform)
    }
}

extension ServiceLine {
    func routes(ofService service: Int) -> [LineRoutePreference] {
        service == 0 ? routePreferences : patterns[service - 1].routePreferences
    }

    /// The timetable's ordered stop indices, including the return calls.
    func routeOrder(service: Int, direction: RingDirection = .inner) -> [Int] {
        if isRing { return ringCalls(direction) }
        let calls = calls(ofService: service)
        return calls + calls.dropLast().reversed()
    }

    var validRoutePreferences: Bool {
        guard Self.isStopList(stops) else { return false }
        for service in 0..<serviceCount {
            if service > 0, !LinePattern.isCallList(patterns[service - 1].calls, stopCount: stops.count) { return false }
            let order = routeOrder(service: service)
            var keys: Set<[Int]> = []
            for route in routes(ofService: service) {
                guard isValidRoute(route, order: order), keys.insert([route.from, route.to]).inserted else { return false }
            }
        }
        return true
    }

    /// Whether `route` fits a service of this line whose timetable calls
    /// at the stops of `order` (``routeOrder(service:direction:)``): two
    /// different stops it takes one after the other, the platform one of
    /// the second's, and a walk ending on the platform's edge. Whether
    /// another of the service's preferences is for the same leg is not
    /// checked.
    func isValidRoute(_ route: LineRoutePreference, order: [Int]) -> Bool {
        route.from >= 0 && route.to >= 0 && route.from != route.to
            && stops.indices.contains(route.from) && stops.indices.contains(route.to)
            && route.platform.station == stops[route.to] && (route.platform.edge.networkNumber ?? 0) >= 1
            && route.tracks.allSatisfy({ ($0.edge.networkNumber ?? 0) >= 1 })
            && route.platform.start >= 0 && route.platform.end > route.platform.start
            && (route.tracks.isEmpty || route.tracks.last?.edge == route.platform.edge)
            && zip(order, order.dropFirst()).contains(where: { ($0 == route.from && $1 == route.to) || (isRing && $1 == route.from && $0 == route.to) })
    }
}

extension GameWorld {
    /// Deterministic physical choices for a service leg: each fitting
    /// destination platform alone, then the path to it from each starting
    /// berth, in platform/berth order. Every choice is shared by the service.
    public func lineRouteChoices(_ id: LineID, from: Int, to: Int, pattern: Int? = nil) -> [LineRoutePreference] {
        guard let line = line(id: id), let service = line.service(pattern),
              line.stops.indices.contains(from), line.stops.indices.contains(to) else { return [] }
        let order = line.routeOrder(service: service)
        guard zip(order, order.dropFirst()).contains(where: { ($0 == from && $1 == to) || (line.isRing && $1 == from && $0 == to) }) else { return [] }
        var choices: [LineRoutePreference] = []
        for platform in network.platforms(of: line.stops[to]) {
            choices.append(.init(from: from, to: to, platform: platform))
            for start in berths(of: line.stops[from], length: 0) {
                let position = TrainPosition.onEdge(start.traversal, offset: start.offset)
                for destination in berths(of: platform.station, length: 0) where destination.traversal.edge == platform.edge {
                    guard let edge = network.edge(platform.edge),
                          destination.offset == (destination.traversal.direction == .forward ? platform.end : edge.length - platform.start),
                          let path = trafficPath(from: position, toStation: platform.station, length: 0, berthPenalty: [:], edgePenalty: [:], only: destination) else { continue }
                    let choice = LineRoutePreference(from: from, to: to, tracks: [start.traversal] + path.traversals, platform: platform)
                    if !choices.contains(choice) { choices.append(choice) }
                }
            }
        }
        return choices
    }

    /// Resolve the exact walk from the train's current edge, or a route to
    /// an explicitly selected platform. A lost connection, a removed
    /// platform, a wrong facing or insufficient length yields no preference.
    /// No world state or reservation changes during this query.
    func preferredPath(from start: TrainPosition, preference: LineRoutePreference, length: Int64) -> TrainPath? {
        let platform = preference.platform
        guard network.platforms.contains(platform), platform.length >= length,
              case .onEdge(let current, let offset) = start,
              isOnNetwork(current, offset: offset), let lastEdge = network.edge(platform.edge) else { return nil }
        if preference.tracks.isEmpty {
            let fitting = Set(berths(of: platform.station, length: length).filter { berth in
                berth.traversal.edge == platform.edge && (berth.traversal.direction == .forward ? berth.offset == platform.end : berth.offset == lastEdge.length - platform.start)
            })
            return trafficPath(from: start, toStation: platform.station, length: length, berthPenalty: [:], edgePenalty: [:], eligible: fitting)
        }
        // A train returning from a passing place may rejoin later in the
        // same walk. Repeated edges retain their first reachable occurrence.
        for index in preference.tracks.indices where preference.tracks[index] == current {
            let walk = Array(preference.tracks[index...])
            guard walk.allSatisfy({ network.edge($0.edge) != nil }),
                  zip(walk, walk.dropFirst()).allSatisfy({ transitions(after: $0).contains($1) }) else { continue }
            let last = walk.last!
            let end = last.direction == .forward ? platform.end : lastEdge.length - platform.start
            if walk.count == 1, end < offset { continue }
            var distance = -offset
            for run in walk.dropLast() {
                let (sum, overflow) = distance.addingReportingOverflow(network.edge(run.edge)!.length)
                guard !overflow else { return nil }
                distance = sum
            }
            let (total, overflow) = distance.addingReportingOverflow(end)
            guard !overflow, total >= 0 else { return nil }
            return TrainPath(traversals: Array(walk.dropFirst()), end: end == lastEdge.length ? nil : end, distance: total)
        }
        return nil
    }

    func linePath(_ line: ServiceLine, from: Int, to: Int, start: TrainPosition, length: Int64, routes: [LineRoutePreference]) -> TrainPath? {
        routes.first(where: { $0.from == from && $0.to == to }).flatMap { preferredPath(from: start, preference: $0, length: length) }
            ?? path(from: start, toStation: line.stops[to], length: length)
    }

    /// Match the whole currently running order before using a line's plan:
    /// editing its stops does not attach new legs to an old timetable.
    func routePreference(for train: Train, from: Int, to: Int) -> LineRoutePreference? {
        // Decision 133: a run's calls are the line's stops one way, each
        // once, so its legs are the line's.
        if let id = assignedLine(of: train.id), let line = line(id: id), line.hasRuns {
            guard let order = runOrder(of: train, on: line), order.indices.contains(from), order.indices.contains(to) else { return nil }
            return line.routePreferences.first { $0.from == order[from] && $0.to == order[to] }
        }
        guard let id = assignedLine(of: train.id), let line = line(id: id), let stream = line.dispatchStream(of: train.id), !line.routes(ofService: stream.service).isEmpty else { return nil }
        let order = line.routeOrder(service: stream.service, direction: stream.direction ?? .inner)
        guard order.map({ line.stops[$0] }) == train.timetable.map(\.station), order.indices.contains(from), order.indices.contains(to) else { return nil }
        return line.routes(ofService: stream.service).first { $0.from == order[from] && $0.to == order[to] }
    }

    /// The indices, in `line`'s stops, of the calls of `train`'s timetable
    /// on a line with runs (decision 133), or `nil` when one is not the
    /// line's.
    func runOrder(of train: Train, on line: ServiceLine) -> [Int]? {
        let order = train.timetable.compactMap { stop in line.stops.firstIndex(of: stop.station) }
        return order.count == train.timetable.count && !order.isEmpty ? order : nil
    }

    func hasRoutePreferences(_ train: Train) -> Bool {
        if let id = assignedLine(of: train.id), let line = line(id: id), line.hasRuns {
            return !line.routePreferences.isEmpty && runOrder(of: train, on: line) != nil
        }
        guard let id = assignedLine(of: train.id), let line = line(id: id), let stream = line.dispatchStream(of: train.id),
              !line.routes(ofService: stream.service).isEmpty else { return false }
        return line.routeOrder(service: stream.service, direction: stream.direction ?? .inner).map { line.stops[$0] } == train.timetable.map(\.station)
    }

    /// Source dispatch plans describe one directed run. A shared physical
    /// plan's out-and-back timetable is matched one run at a time.
    func preferredTrafficCommon(_ a: TrafficService, _ b: TrafficService) -> [[(ai: Int, bi: Int)]] {
        func runs(_ service: TrafficService) -> [Range<Int>] {
            var ranges: [Range<Int>] = [], start = 0
            for i in service.points.indices where i > 0 && i + 1 < service.points.count {
                let point = service.points[i]
                if point.calls && service.train.timetable[point.stop].reverses {
                    ranges.append(start..<(i + 1)); start = i
                }
            }
            ranges.append(start..<service.points.count)
            return ranges
        }
        var sequences: [[(ai: Int, bi: Int)]] = []
        for x in runs(a) {
            for y in runs(b) {
                let common = y.compactMap { j in x.first { a.points[$0].station == b.points[j].station }.map { (ai: $0, bi: j) } }
                if common.count >= 2 && zip(common, common.dropFirst()).allSatisfy({ $0.ai < $1.ai }) { sequences.append(common) }
            }
        }
        return sequences
    }

    /// Different station platforms can share the same corridor beyond a
    /// turnout. Compare positive head stretches and their actual directions.
    func preferredTrafficSharesCorridor(_ a: TrafficService, from ai: Int, to aj: Int, _ b: TrafficService, from bi: Int, to bj: Int) -> Bool {
        func stretches(_ service: TrafficService, _ i: Int, _ j: Int) -> [TrackStretch] {
            let p = service.points[i], q = service.points[j]
            var start = TrainPlacement(position: .onEdge(p.berth.traversal, offset: p.berth.offset), trailEdges: [], length: service.train.length)
            if p.calls && service.train.timetable[p.stop].reverses { start = turnedRound(start) }
            guard let path = preferredTrafficPath(service, to: q, from: start.position, berth: q.berth)
                ?? trafficPath(from: start.position, toStation: q.station, length: service.train.length, berthPenalty: [:], edgePenalty: [:], only: q.berth) else { return [] }
            return trafficStretches(from: start.position, along: path).filter { $0.to > $0.from }
        }
        let x = stretches(a, ai, aj), y = stretches(b, bi, bj)
        return x.contains { p in y.contains { q in p.traversal == q.traversal && p.from < q.to && q.from < p.to } }
    }

    func plannedPath(for train: Train, from start: TrainPosition, departing stop: Int, to next: Int) -> TrainPath? {
        routePreference(for: train, from: stop, to: next).flatMap { preferredPath(from: start, preference: $0, length: train.length) }
            ?? path(from: start, toStation: train.timetable[next].station, length: train.length)
    }

    /// Like ``goingOn(_:)``, facing the way it goes on: turned round in a
    /// dead-end passing berth (see ``passingContinuation(from:to:)``), as
    /// the independent model's `goOn` has it.
    func preferredGoingOn(_ train: Train) -> Train? {
        guard isAtPassingPlace(train), case .travellingToStop(let stop, _)? = train.execution, stop > 0, let place = train.placement,
              let route = routePreference(for: train, from: stop - 1, to: stop),
              let start = passingContinuation(from: place, to: train.timetable[stop].station)?.start,
              let path = preferredPath(from: start.position, preference: route, length: train.length), path.distance > 0 else { return nil }
        var candidate = train
        candidate.position = start.position
        candidate.trailEdges = start.trailEdges
        follow(path, &candidate)
        let fastest = run(of: candidate, length: path.distance)
        candidate.times?.run = fastest
        return candidate
    }

    /// Rank physically usable preferences before duration when choosing a
    /// journey's initial berth/facing. Automatic legs keep the old ties.
    func matchedRoutes(_ journey: LineJourney, routes: [LineRoutePreference], start: TrainPlacement) -> Int {
        guard !routes.isEmpty else { return 0 }
        var place = start, count = 0
        for (index, leg) in journey.legs.enumerated() {
            if !journey.isRing && (index == journey.legs.count / 2 || journey.intermediateTurnbacks.contains(index)) { place = turnedRound(place) }
            if let preference = routes.first(where: { $0.from == leg.from && $0.to == leg.to }),
               preferredPath(from: place.position, preference: preference, length: place.length) == leg.path { count += 1 }
            place = placement(place, after: leg.path)
        }
        return count
    }

    /// Cut a shared physical leg at an intermediate nominal station. This
    /// retains the prescribed corridor in the station moves table; a
    /// different passing berth still uses V1's local alternative search.
    func preferredTrafficPath(_ service: TrafficService, to point: TrafficPoint, from start: TrainPosition, berth: Berth) -> TrainPath? {
        guard point.stop > 0, let route = routePreference(for: service.train, from: point.stop - 1, to: point.stop), !route.tracks.isEmpty,
              let index = route.tracks.firstIndex(of: berth.traversal),
              let platform = network.platforms(of: point.station).first(where: { p in
                  guard p.edge == berth.traversal.edge, let edge = network.edge(p.edge) else { return false }
                  return berth.offset == (berth.traversal.direction == .forward ? p.end : edge.length - p.start)
              }) else { return nil }
        let partial = LineRoutePreference(from: route.from, to: route.to, tracks: Array(route.tracks[...index]), platform: platform)
        return preferredPath(from: start, preference: partial, length: service.train.length)
    }
}
