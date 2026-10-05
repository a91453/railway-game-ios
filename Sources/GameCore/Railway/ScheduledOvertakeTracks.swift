// Stage V4a, decision 60. overtakeTrackFree / motion.sidingsFor at
// railway-reference-private 25229af. Station names and dispatch path IDs
// become directional berths and span/fouling resources on the player's map.
extension GameWorld {
    struct TrafficTrack {
        var berth: Berth
        var body: Set<TrackResource>
        var route: Set<TrackResource>
    }
    struct TrafficMoveKey: Hashable {
        var service: Int
        var point: Int
    }

    /// Local arrival/departure routes through a specific physical berth.
    /// A platform contains the whole body; no reversal or invented track
    /// is allowed. The existing 400 m allowance also bounds this detour.
    func trafficTrack(_ service: TrafficService, at j: Int, berth: Berth) -> TrafficTrack? {
        let points = service.points, point = points[j], length = service.train.length
        let position = TrainPosition.onEdge(berth.traversal, offset: berth.offset)
        let body = j == 0 && service.train.position == position
            ? bodyStretches(of: service.train)
            : [TrackStretch(traversal: berth.traversal, from: berth.offset - length, to: berth.offset)]
        var stretches = body
        var distance: Int64 = 0, normal: Int64 = 0
        if j > 0 {
            let previous = points[j - 1]
            let start = TrainPosition.onEdge(previous.berth.traversal, offset: previous.berth.offset)
            guard let path = trafficPath(from: start, toStation: point.station, length: length,
                                         berthPenalty: [:], edgePenalty: [:], only: berth) else { return nil }
            stretches += trafficStretches(from: start, along: path)
            distance += path.distance; normal += point.distance
        }
        if j + 1 < points.count {
            let next = points[j + 1]
            guard let path = trafficPath(from: position, toStation: next.station, length: length,
                                         berthPenalty: [:], edgePenalty: [:], only: next.berth) else { return nil }
            stretches += trafficStretches(from: position, along: path)
            distance += path.distance; normal += next.distance
        }
        guard distance <= normal + Self.detourAllowance else { return nil }
        return TrafficTrack(berth: berth,
                            body: Set(resources(covering: body)).union(foulingNodes(covering: body)),
                            route: Set(resources(covering: stretches)).union(foulingNodes(covering: stretches)))
    }

    /// The dispatch-table equivalent: routes actually used by nominal
    /// services with the same previous/next stations and stop/pass kind.
    /// Keep every possibility, rather than picking a convenient one.
    func trafficMoves(_ plan: inout TrafficPlan, service s: Int, at j: Int) -> [TrafficTrack] {
        let key = TrafficMoveKey(service: s, point: j)
        if let kept = plan.moves[key] { return kept }
        let points = plan.services[s].points, point = points[j]
        let before = j > 0 ? points[j - 1].station : nil
        let after = j + 1 < points.count ? points[j + 1].station : nil
        var moves: [TrafficTrack] = []
        for source in plan.services {
            for k in source.points.indices {
                let p = source.points[k]
                guard p.station == point.station, p.calls == point.calls,
                      (k > 0 ? source.points[k - 1].station : nil) == before,
                      (k + 1 < source.points.count ? source.points[k + 1].station : nil) == after else { continue }
                var berth = p.berth
                // A train already standing at its first call uses that
                // physical track, as the bound dispatch route does.
                if k == 0, source.train.execution?.stop == 0, isStopped(source.train, at: p.station),
                   case .onEdge(let run, let offset)? = source.train.position {
                    berth = Berth(traversal: run, offset: offset)
                }
                if let move = trafficTrack(source, at: k, berth: berth),
                   !moves.contains(where: { $0.route == move.route }) { moves.append(move) }
            }
        }
        plan.moves[key] = moves
        return moves
    }

    func trafficOvertakeTracks(_ plan: inout TrafficPlan, service s: Int, at j: Int) -> [TrafficTrack] {
        let key = TrafficMoveKey(service: s, point: j)
        if let kept = plan.sidings[key] { return kept }
        let service = plan.services[s], point = service.points[j]
        guard trafficHasSiding(at: point, train: service.train) else { return [] }
        let own = trafficNominalDirections(service)
        let opposite = Set(plan.services.filter { $0.train.id != service.train.id }
            .flatMap { trafficNominalDirections($0).map(\.reversed) }).subtracting(own)
        let tracks = berths(of: point.station, length: service.train.length).compactMap { berth -> TrafficTrack? in
            guard berth.traversal.edge != point.berth.traversal.edge,
                  let track = trafficTrack(service, at: j, berth: berth),
                  // Resource sets carry no direction, so check both local
                  // paths too before admitting a newly borrowed main line.
                  trafficTrackDirections(service, at: j, berth: berth).isDisjoint(with: opposite) else { return nil }
            return track
        }
        plan.sidings[key] = tracks
        return tracks
    }

    func trafficTrackDirections(_ service: TrafficService, at j: Int, berth: Berth) -> Set<TrackTraversal> {
        var directions: Set<TrackTraversal> = []
        let points = service.points, position = TrainPosition.onEdge(berth.traversal, offset: berth.offset)
        if j > 0 {
            let p = points[j - 1], start = TrainPosition.onEdge(p.berth.traversal, offset: p.berth.offset)
            if let path = trafficPath(from: start, toStation: points[j].station, length: service.train.length,
                                      berthPenalty: [:], edgePenalty: [:], only: berth) {
                directions.formUnion(trafficStretches(from: start, along: path).filter { $0.to > $0.from }.map(\.traversal))
            }
        }
        if j + 1 < points.count, let path = trafficPath(from: position, toStation: points[j + 1].station, length: service.train.length,
                                                       berthPenalty: [:], edgePenalty: [:], only: points[j + 1].berth) {
            directions.formUnion(trafficStretches(from: position, along: path).filter { $0.to > $0.from }.map(\.traversal))
        }
        return directions
    }

    func trafficNominalDirections(_ service: TrafficService) -> Set<TrackTraversal> {
        service.points.indices.reduce(into: []) { $0.formUnion(trafficTrackDirections(service, at: $1, berth: service.points[$1].berth)) }
    }

    /// Source reachability of blocked-track masks. Reject if *any* choice
    /// of the peers' known routes can cover all candidates. Bounds are
    /// inclusive; earlier planned dwell wins (arrival, then train ID).
    func overtakeTrackFree(_ plan: inout TrafficPlan, service s: Int, at j: Int, departure: Int64) -> Bool {
        let service = plan.services[s], point = service.points[j]
        let tracks = trafficOvertakeTracks(&plan, service: s, at: j)
        guard !tracks.isEmpty, tracks.count <= 30 else { return false }
        let lo = Self.saturating(GameTime(seconds: point.arrival), plus: -30).seconds
        let hi = Self.saturating(GameTime(seconds: departure), plus: 30).seconds
        var reach: Set<UInt32> = [0]
        let full = (UInt32(1) << tracks.count) - 1
        for other in plan.services.indices where other != s {
            for k in plan.services[other].points.indices {
                let peer = plan.services[other], p = peer.points[k]
                guard p.station == point.station, p.departure >= lo, p.arrival <= hi else { continue }
                if plan.waits.contains(where: { $0.kind == .overtake && $0.train == peer.train.id && $0.station == p.station && $0.stop == p.stop && $0.cycle == p.cycle }) {
                    if p.arrival < point.arrival || (p.arrival == point.arrival && peer.train.id < service.train.id) { return false }
                    continue
                }
                let moves = trafficMoves(&plan, service: other, at: k)
                guard !moves.isEmpty else { return false }
                var next: Set<UInt32> = []
                for move in moves {
                    var mask: UInt32 = 0
                    for i in tracks.indices where network.fouls(tracks[i].body, move.route) { mask |= UInt32(1) << i }
                    for prior in reach { next.insert(prior | mask) }
                }
                reach = next
                if reach.contains(full) { return false }
            }
        }
        return !reach.contains(full)
    }
    /// motion.sidingsFor / attachOvertakePeers: use a stop whose entire
    /// body clears every peer's bound station route in the padded window.
    /// This is a preference: inability to take it returns to V1/V2.
    func scheduledBerthPath(_ train: Train, from start: TrainPosition, target: StationID, stop: Int,
                            normal: TrainPath, plan: TrafficPlan,
                            berthPenalty: [Berth: Int64], edgePenalty: [TrackEdgeID: Int64]) -> TrainPath? {
        guard let wait = plan.waits.first(where: { $0.kind == .overtake && $0.train == train.id && $0.station == target && $0.stop == stop }),
              let s = plan.services.firstIndex(where: { $0.train.id == train.id }),
              let j = plan.services[s].points.firstIndex(where: { $0.station == target && $0.stop == stop && $0.cycle == wait.cycle }) else {
            return trafficPath(from: start, toStation: target, length: train.length, berthPenalty: berthPenalty, edgePenalty: edgePenalty)
        }
        var local = plan
        let tracks = trafficOvertakeTracks(&local, service: s, at: j)
        let p = plan.services[s].points[j]
        let lo = Self.saturating(GameTime(seconds: p.arrival), plus: -30).seconds
        let hi = Self.saturating(wait.departure, plus: 30).seconds
        var avoid: Set<TrackResource> = []
        for peer in plan.services where peer.train.id != train.id {
            for k in peer.points.indices {
                let v = peer.points[k]
                guard v.station == target, v.departure >= lo, v.arrival <= hi else { continue }
                // motion.servedFirst: an earlier dwell selects first;
                // considering a later dwell's route would make them wait
                // for each other's choice of siding.
                if plan.waits.contains(where: { $0.kind == .overtake && $0.train == peer.train.id && $0.station == target && $0.stop == v.stop && $0.cycle == v.cycle }),
                   v.arrival > p.arrival || (v.arrival == p.arrival && peer.train.id > train.id) { continue }
                var berth = v.berth
                if k == 0, peer.train.execution?.stop == 0, isStopped(peer.train, at: target),
                   case .onEdge(let run, let offset)? = peer.train.position { berth = Berth(traversal: run, offset: offset) }
                guard let move = trafficTrack(peer, at: k, berth: berth) else { return nil }
                avoid.formUnion(move.route)
            }
        }
        var memo = DirectionMemo(), candidate = train
        follow(normal, &candidate)
        let forbidden = opposingServiceTraversals(for: candidate, memo: &memo)
        let eligible = Set(tracks.filter { !network.fouls($0.body, avoid) }.map(\.berth))
        // One search across all safe berths retains V3's generalized costs
        // and route-level tie order; geometric distance alone is insufficient.
        return trafficPath(from: start, toStation: target, length: train.length,
                           berthPenalty: berthPenalty, edgePenalty: edgePenalty,
                           eligible: eligible, forbidden: forbidden)
    }

}
