// Empty runs a waiting point at a time (decision 666). Under traffic
// control without block sections a train takes its route whole, or
// follows a train ahead that it can be sure leads the way (Stage U2). An
// empty run out of a depot (decision 221) often has a long way to go,
// past several stations, and on a line with trains every few minutes the
// whole of it is never free at once: on the Taoyuan Airport MRT the run
// from the Luzhu depot to Huanbei, thirteen minutes, waited from 14:00
// to 15:44 on the second day and the evening's shuttles went without a
// train (TYMC-AFTERNOON).
//
// A real railway sends such a train on a station at a time. So an empty
// run that cannot take its whole route takes it as far as the farthest
// station platform on its way, short of its end, whose way is free: a
// place it may stand and wait, not between stations. It takes the rest
// the same way, a waiting point at a time or all of it, as track falls
// free. Derived from the train and the network, never saved; with block
// sections (whose own rules already take a route a block at a time) or
// traffic control off, and for a train with passengers, nothing changes.

extension GameWorld {
    /// Decision 666: whether `train` takes its route a waiting point at a
    /// time when it cannot take it whole: an empty run under traffic
    /// control without block sections.
    func takesRouteByWaitingPoints(_ train: Train) -> Bool {
        guard isTrafficControlEnabled, !blockSections, train.isDeadheading, let first = train.timetable.first else { return false }
        return station(id: first.station)?.isDepot == true
    }

    /// How far along its route (see ``AuthorityEnvelopes``) `train`'s
    /// head stands at the end of a platform of a station that is not a
    /// depot, its whole length on the platform, in ascending order: every
    /// such place beyond its head and short of the route's end.
    func waitingPoints(of train: Train, _ envelopes: AuthorityEnvelopes) -> [Int64] {
        guard !envelopes.stretches.isEmpty else { return [] }
        var ends: [TrackTraversal: [Int64]] = [:]
        var fitting: [StationID: Int] = [:]
        for platform in network.platforms where platform.length >= train.length { fitting[platform.station, default: 0] += 1 }
        for platform in network.platforms where platform.length >= train.length {
            guard fitting[platform.station, default: 0] >= 3, station(id: platform.station)?.isDepot == false,
                  !train.timetable.contains(where: { $0.station == platform.station }), let edge = network.edge(platform.edge) else { continue }
            ends[TrackTraversal(edge: platform.edge, direction: .forward), default: []].append(platform.end)
            ends[TrackTraversal(edge: platform.edge, direction: .backward), default: []].append(edge.length - platform.start)
        }
        var points: [Int64] = []
        var start: Int64 = 0
        for (stretch, end) in zip(envelopes.stretches, envelopes.ends) {
            defer { start = end }
            guard end < .max else { break }
            for offset in ends[stretch.traversal] ?? [] where offset > stretch.from && offset <= stretch.to {
                let point = start + offset - stretch.from
                if point > 0, point < envelopes.length { points.append(point) }
            }
        }
        return points.sorted()
    }

    /// Decision 666: `candidate`, an empty run about to set off (see
    /// ``takesRouteByWaitingPoints(_:)``) whose whole route another train
    /// holds, with its route reserved as far as its farthest waiting point
    /// (see ``waitingPoints(of:_:)``) whose track no other train keeps it
    /// from; `nil` when there is none.
    func waitingPointAuthority(of candidate: Train, memo: inout DirectionMemo) -> Train? {
        let envelopes = authorityEnvelopes(of: candidate)
        let points = waitingPoints(of: candidate, envelopes)
        guard !points.isEmpty else { return nil }
        let clear = clearOfBlocked(blockedTrack(except: candidate.id, holders: trackHolders(memo: &memo)))
        let free = longestAuthority(envelopes, from: 0, clearBase: clear.base(envelopes.base), clear: clear.stretch)
        guard let point = points.last(where: { $0 <= free }) else { return nil }
        var train = candidate
        train.reservation = authorityEnvelope(envelopes, to: point).sorted()
        return train
    }

    /// Decision 666: how far an empty run taking its route a waiting point
    /// at a time, holding it `held` along `envelopes`, may hold it now,
    /// with track clear of others as far as `free`: its farthest waiting
    /// point beyond `held` within that, or `nil`.
    func nextWaitingPoint(of train: Train, _ envelopes: AuthorityEnvelopes, held: Int64, free: Int64) -> Int64? {
        waitingPoints(of: train, envelopes).last { $0 > held && $0 <= free }
    }
}
