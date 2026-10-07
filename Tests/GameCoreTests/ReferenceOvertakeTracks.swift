@testable import GameCore

// Independent V4a oracle. Relaxed exact-berth routes and absolute-distance
// windows form the station table. The availability oracle expands sets of
// covered candidate indices rather than production's UInt32 masks.
extension ReferenceWorld {
    struct StationMove {
        var run: Run
        var offset: Int64
        var body: Set<TrackResource>
        var route: Set<TrackResource>
        var directions: Set<Run>
    }
    struct StationMoveKey: Hashable { var service: Int; var visit: Int }

    /// Where `service` sets off from visit `k` standing at `run`/`offset`:
    /// turned round at a call marked to reverse, as `plannedVisits` drives it.
    func departing(_ service: PlannedService, _ k: Int, _ run: Run, _ offset: Int64) -> (run: Run, offset: Int64) {
        let visit = service.visits[k]
        guard visit.call, service.train.timetable[visit.stop].reverses else { return (run, offset) }
        let driver = turnedOnNetwork(standing(Train(id: service.train.id, name: service.train.name, position: .onEdge(run.traversal, offset: offset),
                                                    cars: service.train.cars, performance: service.train.performance)))
        guard case .onEdge(let traversal, let at)? = driver.position, let turned = Run(traversal) else { return (run, offset) }
        return (turned, at)
    }

    func stationMove(_ service: PlannedService, _ j: Int, _ run: Run, _ offset: Int64) -> StationMove? {
        let v = service.visits, length = Self.length(service.train)
        let position = TrainPosition.onEdge(run.traversal, offset: offset)
        var body = track(along: [run], from: offset - length, to: offset)
        if j == 0, service.train.position == position {
            var standing = service.train; standing.reservation = []
            body = held(standing)
        }
        var route = body, directions: Set<Run> = []
        var distance: Int64 = 0, normal: Int64 = 0
        func add(_ start: Run, _ at: Int64, _ path: TrainPath) {
            let runs = [start] + path.traversals.map { Run($0)! }
            route.formUnion(track(along: runs, from: at, to: at + path.distance))
            var covered: Int64 = -at
            for part in runs {
                let end = covered + networkEdges[part.edge]!.length
                if end > 0 && covered < path.distance { directions.insert(part) }
                covered = end
            }
            distance += path.distance
        }
        if j > 0 {
            let p = departing(service, j - 1, v[j - 1].run, v[j - 1].offset)
            guard let incoming = prescribedStationRoute(service, v[j], start: .onEdge(p.run.traversal, offset: p.offset), run: run, offset: offset) ?? networkPathToStation(from: .onEdge(p.run.traversal, offset: p.offset), station: v[j].station,
                                                      length: length, only: (run, offset)) else { return nil }
            add(p.run, p.offset, incoming); normal += v[j].distance
        }
        if j < v.count - 1 {
            let next = v[j + 1], leaving = departing(service, j, run, offset)
            let start = TrainPosition.onEdge(leaving.run.traversal, offset: leaving.offset)
            guard let outgoing = prescribedStationRoute(service, next, start: start, run: next.run, offset: next.offset) ?? networkPathToStation(from: start, station: next.station, length: length, only: (next.run, next.offset)) else { return nil }
            add(leaving.run, leaving.offset, outgoing); normal += next.distance
        }
        return distance - normal <= 25_600 ? StationMove(run: run, offset: offset, body: body, route: route, directions: directions) : nil
    }

    func stationMovements(_ plan: inout ScheduledPlan, _ s: Int, _ j: Int) -> [StationMove] {
        let key = StationMoveKey(service: s, visit: j)
        if let known = plan.movements[key] { return known }
        let v = plan.services[s].visits, p = v[j]
        let before = j == 0 ? nil : v[j - 1].station
        let after = j == v.count - 1 ? nil : v[j + 1].station
        var choices: [StationMove] = []
        for service in plan.services {
            for (k, visit) in service.visits.enumerated() {
                guard visit.station == p.station && visit.call == p.call,
                      (k == 0 ? nil : service.visits[k - 1].station) == before,
                      (k == service.visits.count - 1 ? nil : service.visits[k + 1].station) == after else { continue }
                var run = visit.run, offset = visit.offset
                if k == 0, service.train.service?.stop == 0, networkStops(of: service.train).contains(visit.station),
                   case .onEdge(let traversal, let at)? = service.train.position { run = Run(traversal)!; offset = at }
                if let choice = stationMove(service, k, run, offset), !choices.contains(where: { $0.route == choice.route }) { choices.append(choice) }
            }
        }
        plan.movements[key] = choices
        return choices
    }

    func overtakePlaces(_ plan: inout ScheduledPlan, _ s: Int, _ j: Int) -> [StationMove] {
        let key = StationMoveKey(service: s, visit: j)
        if let known = plan.places[key] { return known }
        let service = plan.services[s], point = service.visits[j]
        guard hasScheduledLoop(point, service.train) else { return [] }
        func nominal(_ sequence: PlannedService) -> Set<Run> {
            sequence.visits.indices.reduce(into: []) { found, k in
                let p = sequence.visits[k]
                found.formUnion(stationMove(sequence, k, p.run, p.offset)?.directions ?? [])
            }
        }
        let own = nominal(service)
        let opposite = plan.services.filter { $0.train.id != service.train.id }.reduce(into: Set<Run>()) {
            for run in nominal($1) { $0.insert(Run(edge: run.edge, forward: !run.forward)) }
        }.subtracting(own)
        var found: [StationMove] = []
        var prescribedLoop = false
        if point.stop > 0, j > 0, j + 1 < service.visits.count,
           let r = routePreference(service.train, from: point.stop - 1, to: point.stop),
           (r.platform.station == point.station && r.platform.edge.number == point.run.edge) || r.tracks.contains(point.run.traversal) {
            let corridor = [service.visits[j - 1].station, point.station, service.visits[j + 1].station]
            for peer in plan.services where peer.train.id != service.train.id {
                for k in 1..<max(1, peer.visits.count - 1) where peer.visits[k].run.edge != point.run.edge {
                    if [peer.visits[k - 1].station, peer.visits[k].station, peer.visits[k + 1].station] == corridor { prescribedLoop = true }
                }
            }
        }
        for platform in stations.first(where: { $0.id == point.station.rawValue })!.trackPlatforms where platform.length >= Self.length(service.train) {
            for forward in [true, false] {
                let run = Run(edge: platform.edge.number, forward: forward)
                let offset = forward ? platform.end : networkEdges[run.edge]!.length - platform.start
                if run.edge != point.run.edge || prescribedLoop, let choice = stationMove(service, j, run, offset), choice.directions.isDisjoint(with: opposite) { found.append(choice) }
            }
        }
        plan.places[key] = found
        return found
    }

    func freeOvertakeTrack(_ plan: inout ScheduledPlan, _ s: Int, _ j: Int, _ departure: Int64) -> Bool {
        let service = plan.services[s], p = service.visits[j]
        let choices = overtakePlaces(&plan, s, j)
        if choices.isEmpty || choices.count > 30 { return false }
        let low = p.arr - 30, high = Self.capped(departure, 30)
        let all = Set(choices.indices)
        var covered: Set<Set<Int>> = [[]]
        for (other, peer) in plan.services.enumerated() where other != s {
            for (k, v) in peer.visits.enumerated() where v.station == p.station && v.dep >= low && v.arr <= high {
                if plan.waits.contains(where: { $0.kind == .overtake && $0.train.rawValue == peer.train.id && $0.station == v.station && $0.stop == v.stop && $0.cycle == v.cycle }) {
                    if (v.arr, peer.train.id) < (p.arr, service.train.id) { return false }
                    continue
                }
                let movements = stationMovements(&plan, other, k)
                if movements.isEmpty { return false }
                covered = Set(movements.flatMap { movement in
                    let blocked = Set(choices.indices.filter { foul(choices[$0].body, movement.route) })
                    return covered.map { $0.union(blocked) }
                })
                if covered.contains(all) { return false }
            }
        }
        return !covered.contains(all)
    }
    func scheduledBerthRoute(_ train: Train, _ target: StationID, _ stop: Int, _ normal: TrainPath,
                             _ plan: ScheduledPlan, _ berthCosts: [Run: Int64], _ edgeCosts: [Int: Int64]) -> TrainPath? {
        guard let wait = plan.waits.first(where: { $0.kind == .overtake && $0.train.rawValue == train.id && $0.station == target && $0.stop == stop }),
              let s = plan.services.firstIndex(where: { $0.train.id == train.id }),
              let j = plan.services[s].visits.firstIndex(where: { $0.station == target && $0.stop == stop && $0.cycle == wait.cycle }) else {
            return networkPathToStation(from: train.position!, station: target, length: Self.length(train), berthCosts: berthCosts, edgeCosts: edgeCosts)
        }
        var local = plan
        let candidates = overtakePlaces(&local, s, j)
        let p = plan.services[s].visits[j]
        var avoid: Set<TrackResource> = []
        for peer in plan.services where peer.train.id != train.id {
            for (k, v) in peer.visits.enumerated() where v.station == target && v.dep >= p.arr - 30 && v.arr <= Self.capped(wait.departure.seconds, 30) {
                let planned = plan.waits.contains { $0.kind == .overtake && $0.train.rawValue == peer.train.id && $0.station == target && $0.stop == v.stop && $0.cycle == v.cycle }
                if planned && (v.arr, peer.train.id) > (p.arr, train.id) { continue }
                var run = v.run, offset = v.offset
                if k == 0, peer.train.service?.stop == 0, networkStops(of: peer.train).contains(target),
                   case .onEdge(let traversal, let at)? = peer.train.position { run = Run(traversal)!; offset = at }
                guard let move = stationMove(peer, k, run, offset) else { return nil }
                avoid.formUnion(move.route)
            }
        }
        var world = self
        let forbidden = world.contraryRuns(for: routed(train, normal))
        var destinations: [Run: [Int64]] = [:]
        for candidate in candidates where !foul(candidate.body, avoid) {
            destinations[candidate.run, default: []].append(candidate.offset)
        }
        destinations = destinations.mapValues { $0.sorted() }
        return networkPathToStation(from: train.position!, station: target, length: Self.length(train), forbidden: forbidden,
                                    berthCosts: berthCosts, edgeCosts: edgeCosts, eligible: destinations)
    }

}
