import GameCore

// Decision 61 oracle: a prescribed walk is validated as absolute distance
// intervals, using the model's signed runs and connectivity. No GameWorld.
extension ReferenceWorld {
    static func routeOrder(_ line: Line, service: Int, outer: Bool = false) -> [Int] {
        let calls = line.service(service).calls
        return line.ring ? lap(line, outer: outer) : calls + calls.dropLast().reversed()
    }

    mutating func setLineRoutes(_ id: LineID, _ routes: [LineRoutePreference], pattern: Int? = nil) -> GameError? {
        guard let i = lines.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownLine(id) }
        if let pattern, !lines[i].patterns.indices.contains(pattern) { return .unknownLinePattern(pattern) }
        let sequence = Self.routeOrder(lines[i], service: pattern.map { $0 + 1 } ?? 0)
        var remaining = routes
        for index in 1..<sequence.count {
            let pair = (sequence[index - 1], sequence[index])
            remaining.removeAll { $0.from == pair.0 && $0.to == pair.1 || lines[i].ring && $0.from == pair.1 && $0.to == pair.0 }
        }
        let keys = routes.map { [$0.from, $0.to] }
        guard remaining.isEmpty, Set(keys).count == routes.count,
              routes.allSatisfy({ r in
                  lines[i].stops.indices.contains(r.to) && lines[i].stops[r.to] == r.platform.station && r.platform.edge.number >= 1 && r.tracks.allSatisfy({ $0.edge.number >= 1 }) && r.platform.start >= 0 && r.platform.end > r.platform.start && (r.tracks.isEmpty || r.tracks.last?.edge == r.platform.edge)
              }) else { return .invalidLineRoutePreference }
        if let pattern { lines[i].patterns[pattern].routes = routes }
        else { lines[i].routes = routes }
        return nil
    }

    func preferenceRoute(from start: TrainPosition, _ preference: LineRoutePreference, length: Int64) -> TrainPath? {
        let p = preference.platform
        guard stations.contains(where: { $0.trackPlatforms.contains(p) }), p.length >= length,
              case .onEdge(let traversal, let offset) = start, let current = Run(traversal),
              let edge = networkEdges[current.edge], (0...edge.length).contains(offset),
              let lastEdge = networkEdges[p.edge.number] else { return nil }
        if preference.tracks.isEmpty {
            let forward = Run(edge: p.edge.number, forward: true), backward = Run(edge: p.edge.number, forward: false)
            return networkPathToStation(from: start, station: p.station, length: length,
                                        eligible: [forward: [p.end], backward: [lastEdge.length - p.start]])
        }
        let walk = preference.tracks.compactMap(Run.init)
        guard walk.count == preference.tracks.count else { return nil }
        for i in walk.indices where walk[i] == current {
            let suffix = Array(walk[i...])
            if suffix.contains(where: { networkEdges[$0.edge] == nil }) { continue }
            var valid = true
            for j in 1..<suffix.count where !runs(after: suffix[j - 1]).contains(suffix[j]) { valid = false }
            if !valid { continue }
            let stop = stretch(of: p, along: suffix.last!).to
            var origin: Int64 = 0
            for run in suffix.dropLast() {
                let (next, overflow) = origin.addingReportingOverflow(networkEdges[run.edge]!.length)
                if overflow { return nil }
                origin = next
            }
            let (finish, overflow) = origin.addingReportingOverflow(stop)
            if overflow { return nil }
            if finish < offset { continue }
            return TrainPath(traversals: suffix.dropFirst().map(\.traversal), end: stop == lastEdge.length ? nil : stop, distance: finish - offset)
        }
        return nil
    }

    func routePreference(_ train: Train, from: Int, to: Int) -> LineRoutePreference? {
        for line in lines {
            for service in 0...line.patterns.count where line.service(service).roster.contains(train.id) {
                if line.service(service).routes.isEmpty { return nil }
                let order = Self.routeOrder(line, service: service, outer: Self.isOuter(train.id, on: line) == true)
                guard order.map({ line.stops[$0] }) == train.timetable.map(\.station), order.indices.contains(from), order.indices.contains(to) else { return nil }
                return line.service(service).routes.first { $0.from == order[from] && $0.to == order[to] }
            }
        }
        return nil
    }

    func nominalRoute(_ train: Train, start: TrainPosition, from: Int, to: Int) -> TrainPath? {
        routePreference(train, from: from, to: to).flatMap { preferenceRoute(from: start, $0, length: Self.length(train)) }
            ?? networkPathToStation(from: start, station: train.timetable[to].station, length: Self.length(train))
    }

    func hasRoutes(_ train: Train) -> Bool {
        for line in lines {
            for service in 0...line.patterns.count where line.service(service).roster.contains(train.id) && !line.service(service).routes.isEmpty {
                if Self.routeOrder(line, service: service, outer: Self.isOuter(train.id, on: line) == true).map({ line.stops[$0] }) == train.timetable.map(\.station) { return true }
            }
        }
        return false
    }

    func prescribedCommon(_ a: PlannedService, _ b: PlannedService) -> [[(Int, Int)]] {
        func boundaries(_ service: PlannedService) -> [Int] {
            [0] + service.visits.indices.filter { i in
                i > 0 && i + 1 < service.visits.count && service.visits[i].call && service.train.timetable[service.visits[i].stop].reverses
            } + [service.visits.count - 1]
        }
        let x = boundaries(a), y = boundaries(b)
        var result: [[(Int, Int)]] = []
        for (lo, hi) in zip(x, x.dropFirst()) {
            for (low, high) in zip(y, y.dropFirst()) {
                var pairs: [(Int, Int)] = []
                for j in low...high {
                    for i in lo...hi where a.visits[i].station == b.visits[j].station { pairs.append((i, j)); break }
                }
                if pairs.count >= 2 && zip(pairs, pairs.dropFirst()).allSatisfy({ $0.0 < $1.0 }) { result.append(pairs) }
            }
        }
        return result
    }

    func prescribedCorridor(_ a: PlannedService, _ ai: Int, _ aj: Int, _ b: PlannedService, _ bi: Int, _ bj: Int) -> Bool {
        func intervals(_ service: PlannedService, _ i: Int, _ j: Int) -> [(Run, Int64, Int64)] {
            let p = service.visits[i], q = service.visits[j]
            var driver = service.train
            driver.position = .onEdge(p.run.traversal, offset: p.offset); driver.trailEdges = []
            if p.call && driver.timetable[p.stop].reverses { driver = turnedOnNetwork(driver) }
            guard let path = prescribedStationRoute(service, q, start: driver.position!, run: q.run, offset: q.offset)
                ?? networkPathToStation(from: driver.position!, station: q.station, length: Self.length(driver), only: (q.run, q.offset)),
                  case .onEdge(let track, let offset) = driver.position!, let run = Run(track) else { return [] }
            let walk = [run] + path.traversals.compactMap(Run.init)
            return walk.enumerated().compactMap { index, run in
                let low = index == 0 ? offset : 0
                let high = index + 1 == walk.count ? path.end ?? networkEdges[run.edge]!.length : networkEdges[run.edge]!.length
                return low < high ? (run, low, high) : nil
            }
        }
        let x = intervals(a, ai, aj), y = intervals(b, bi, bj)
        for p in x {
            for q in y where p.0 == q.0 && max(p.1, q.1) < min(p.2, q.2) { return true }
        }
        return false
    }
    func matchedRoutes(_ journey: LineJourney, routes: [LineRoutePreference], start: Train) -> Int {
        if routes.isEmpty { return 0 }
        var driver = start, count = 0
        for index in journey.legs.indices {
            let leg = journey.legs[index]
            if !journey.isRing && index * 2 == journey.legs.count { driver = turnedOnNetwork(driver) }
            if let r = routes.first(where: { $0.from == leg.from && $0.to == leg.to }), preferenceRoute(from: driver.position!, r, length: Self.length(driver)) == leg.path { count += 1 }
            driver = followed(driver, along: leg.path)
        }
        return count
    }

    func prescribedStationRoute(_ service: PlannedService, _ visit: PlannedVisit, start: TrainPosition, run: Run, offset: Int64) -> TrainPath? {
        guard visit.stop > 0, let r = routePreference(service.train, from: visit.stop - 1, to: visit.stop), !r.tracks.isEmpty else { return nil }
        var prefix: [TrackTraversal] = []
        for track in r.tracks {
            prefix.append(track)
            if track != run.traversal { continue }
            for platform in stations.first(where: { $0.id == visit.station.rawValue })?.trackPlatforms ?? [] where platform.edge == track.edge {
                if stretch(of: platform, along: run).to == offset {
                    let cut = LineRoutePreference(from: r.from, to: r.to, tracks: prefix, platform: platform)
                    return preferenceRoute(from: start, cut, length: Self.length(service.train))
                }
            }
            return nil
        }
        return nil
    }

}
