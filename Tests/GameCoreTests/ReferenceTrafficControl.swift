import GameCore

/// Decision 28, written a second time for ``ReferenceWorld``: traffic
/// control and route reservation. Written from the rules, and differently
/// where it can be: a train's track is its occupied resources plus the
/// path ahead walked as pairs of nodes; a holder is found by testing each
/// resource against every other train in turn; shared track is looked for
/// pair by pair.
extension ReferenceWorld {
    /// What a train at `position` with `body` and `ahead` still to run
    /// holds: where it stands, the node ahead, and the path's links and
    /// nodes.
    func held(_ position: TrainPosition, _ body: [GridPosition], length: Int64, ahead: [GridPosition]) -> Set<TrackResource> {
        var probe = Train(id: 0, name: "", position: position)
        probe.trail = body
        probe.cars = Int(length / Self.carUnits) + 1
        var result = Set(occupied(probe))
        let path = [Self.ahead(position).0] + ahead
        result.formUnion(path.map { TrackResource.node($0) })
        for (p, q) in zip(path, path.dropFirst()) {
            result.insert((p.y, p.x) < (q.y, q.x) ? .link(p, q) : .link(q, p))
        }
        return result
    }

    func reservedResources(of id: TrainID) -> [TrackResource] {
        guard let train = trains.first(where: { $0.id == id.rawValue }), let position = train.position else { return [] }
        return held(position, train.trail, length: Self.length(train), ahead: Array(train.continuation[train.cursor...])).sorted()
    }

    /// Under traffic control, the lowest ID of another train holding any
    /// of `resources`.
    func holder(of resources: Set<TrackResource>, except id: Int) -> Int? {
        guard trafficControl else { return nil }
        return trains.filter { $0.id != id }.map(\.id).sorted().first { other in
            let theirs = Set(reservedResources(of: TrainID(rawValue: other)))
            return resources.contains(where: theirs.contains)
        }
    }

    /// Decision 28: a service still waiting after its departure time,
    /// whose route to its next stop is held.
    func trainHoldingRoute(of id: TrainID) -> TrainID? {
        guard trafficControl, let train = trains.first(where: { $0.id == id.rawValue }), let position = train.position,
              let service = train.service, service.waiting,
              let departure = Self.departure(train, stop: service.stop, cycle: service.cycle), departure < minutes
        else { return nil }
        var next = (stop: service.stop + 1, cycle: service.cycle)
        if next.stop == train.timetable.count {
            next = (0, service.cycle + 1)
            guard train.period != nil, Self.fits(train, cycle: next.cycle) else { return nil }
        }
        let length = Self.length(train)
        let (start, body) = train.timetable[service.stop].reverses
            ? Self.turnedWithBody(position, train.trail, length: length)
            : (position, train.trail)
        guard let route = route(from: start, toStation: train.timetable[next.stop].station, length: length) else { return nil }
        return holder(of: held(start, body, length: length, ahead: route), except: train.id).map(TrainID.init(rawValue:))
    }

    mutating func setTrafficControl(_ enabled: Bool) -> GameError? {
        if enabled {
            let ids = trains.map(\.id).sorted()
            for (j, later) in ids.enumerated() {
                let theirs = Set(reservedResources(of: TrainID(rawValue: later)))
                for earlier in ids[..<j] where !theirs.isDisjoint(with: reservedResources(of: TrainID(rawValue: earlier))) {
                    return .trainsShareTrack(TrainID(rawValue: earlier), TrainID(rawValue: later))
                }
            }
        }
        trafficControl = enabled
        return nil
    }
}
