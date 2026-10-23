// Decision 366: a train of a line that runs at a headway stands aside for a
// faster one behind it. Each trip's times are worked out when it is sent out
// and drift from what happens, and an express sent out just behind a stopping
// train meets it within a call that has no siding, where decision 59's
// overtake (two points with the order swapped) finds nothing to plan.

extension GameWorld {
    /// Decision 366: for two services each a trip of a line without runs,
    /// running the same way along the same track, the overtake their trips'
    /// actual progress calls for. A service is later than its trip by what
    /// it last did (its arrival at the call it waits at, or its departure
    /// from the call it left), and runs to time from there; trains on one
    /// track keep their order until a siding. When the one behind would
    /// reach a point before the one ahead has left it, the one ahead waits
    /// at the last point with a siding before then, or else the first after
    /// within 25 km, until the other has actually passed and 30 seconds
    /// more (decision 59's release), and at most
    /// ``timetabledOvertakeHold`` past when it would have left. The
    /// siding is decision 60's, so it never borrows a track a service runs
    /// the other way. Trip times are not changed, and a point a decision 59
    /// wait already holds is left to it.
    func planHeadwayOvertakes(_ plan: inout TrafficPlan) {
        var headway: Set<TrainID> = []
        for line in lines where !line.hasRuns {
            for service in 0..<line.serviceCount { headway.formUnion(line.trains(ofService: service)) }
        }
        let eligible = plan.services.indices.filter { s in
            let train = plan.services[s].train
            return headway.contains(train.id) && train.timetablePeriod == nil && !train.isDeadheading && progress(of: plan.services[s]) != nil
        }
        guard eligible.count >= 2 else { return }
        var proposals: [(slow: Int, point: Int, wait: ScheduledTrafficWait, pass: Int64)] = []
        for slow in eligible {
            for fast in eligible where fast != slow {
                guard let proposal = headwayOvertake(&plan, slow: slow, fast: fast) else { continue }
                // One wait at a point: for the train that comes first.
                if let old = proposals.firstIndex(where: { $0.slow == slow && $0.point == proposal.point }) {
                    if proposal.pass < proposals[old].pass { proposals[old] = (slow, proposal.point, proposal.wait, proposal.pass) }
                } else {
                    proposals.append((slow, proposal.point, proposal.wait, proposal.pass))
                }
            }
        }
        for proposal in proposals {
            let wait = proposal.wait
            guard !plan.waits.contains(where: { $0.train == wait.train && $0.station == wait.station && $0.stop == wait.stop && $0.cycle == wait.cycle }) else { continue }
            plan.waits.append(wait)
        }
    }

    /// Where `service` is along its points, from what it last did: the
    /// point of the call it waits at or last left, whether it still waits
    /// there, and how many seconds later than its trip it is (none when
    /// early). `nil` without a call to place it at.
    func progress(of service: TrafficService) -> (point: Int, waiting: Bool, late: Int64)? {
        let train = service.train
        guard let execution = train.execution, let times = train.times else { return nil }
        switch execution {
        case .waitingAtStop(let stop, let cycle):
            guard let point = service.points.firstIndex(where: { $0.calls && $0.stop == stop && $0.cycle == cycle }) else { return nil }
            return (point, true, max(0, times.arrival.seconds - train.scheduledArrival(of: stop, cycle: cycle).seconds))
        case .travellingToStop(let stop, let cycle):
            guard stop > 0, let departure = times.departure,
                  let point = service.points.firstIndex(where: { $0.calls && $0.stop == stop - 1 && $0.cycle == cycle }) else { return nil }
            return (point, false, max(0, departure.seconds - train.scheduledDeparture(of: stop - 1, cycle: cycle).seconds))
        }
    }

    /// Decision 366: the wait of `slow` for `fast` behind it (see
    /// ``planHeadwayOvertakes(_:)``), the point it is at, and when `fast`
    /// is expected to pass there; `nil` when there is none.
    func headwayOvertake(_ plan: inout TrafficPlan, slow s: Int, fast f: Int) -> (point: Int, wait: ScheduledTrafficWait, pass: Int64)? {
        let l = plan.services[s], x = plan.services[f]
        guard let lp = progress(of: l), let fp = progress(of: x), let arrived = l.train.times?.arrival else { return nil }
        let at = l.points[lp.point]
        // The fast one's point at the slow one's call, on the same track,
        // not yet passed.
        guard let start = x.points.indices.first(where: { $0 >= fp.point && x.points[$0].station == at.station }),
              x.points[start].berth.traversal == at.berth.traversal,
              !x.train.trafficVisits.contains(where: { $0.station == at.station && $0.stop == x.points[start].stop && $0.cycle == x.points[start].cycle && $0.departure != nil })
        else { return nil }
        // Behind: it cannot come past the call while the slow one stands
        // on the track there, so it comes after the slow one arrived. Two
        // waiting at one call leave in their trips' order; of two that have
        // left it, the later is behind.
        if start == fp.point, fp.waiting {
            guard !lp.waiting || at.departure + lp.late < x.points[start].departure + fp.late else { return nil }
        } else if start == fp.point {
            guard !lp.waiting, let left = l.train.times?.departure, let followed = x.train.times?.departure, left < followed else { return nil }
        } else {
            guard start > fp.point, x.points[start].arrival + fp.late >= arrived.seconds else { return nil }
        }
        // The points both run through next, along the same track.
        var common: [(l: Int, x: Int)] = [(lp.point, start)]
        while let last = common.last, last.l + 1 < l.points.count, last.x + 1 < x.points.count,
              l.points[last.l + 1].station == x.points[last.x + 1].station,
              l.points[last.l + 1].berth.traversal == x.points[last.x + 1].berth.traversal {
            common.append((last.l + 1, last.x + 1))
        }
        // The first point the fast one would reach before the slow one has
        // left it, within 25 km.
        var caught: Int?
        var look: Int64 = 0
        for (n, c) in common.enumerated() {
            if n > 0 { look += l.points[c.l].distance }
            if look > 25 * 64_000 { break }
            if n == 0, !lp.waiting { continue }
            if x.points[c.x].arrival + fp.late < l.points[c.l].departure + lp.late { caught = n; break }
        }
        guard let caught else { return nil }
        // The slow one's route is chosen as it leaves a call, so it can
        // stand aside only beyond the call it waits at or left, or at that
        // call if it already stands on a siding there.
        func choosable(_ n: Int) -> Bool {
            let p = l.points[common[n].l]
            guard n == 0 else { return p.stop > (lp.waiting ? at.stop : at.stop + 1) }
            guard lp.waiting, case .onEdge(let standing, _)? = l.train.position else { return false }
            return standing.edge != at.berth.traversal.edge
        }
        func usable(_ n: Int) -> Bool {
            let c = common[n]
            return choosable(n) && trafficHasSiding(at: l.points[c.l], train: l.train, known: &plan.hasSiding)
                && overtakeTrackFree(&plan, service: s, at: c.l, departure: max(l.points[c.l].departure, x.points[c.x].departure + fp.late - lp.late + 30))
        }
        var chosen = stride(from: caught, through: 0, by: -1).first(where: usable)
        if chosen == nil {
            var ahead: Int64 = 0
            for n in common.indices where n > caught {
                ahead += l.points[common[n].l].distance
                if ahead > 25 * 64_000 { break }
                if usable(n) { chosen = n; break }
            }
        }
        guard let chosen else { return nil }
        let c = common[chosen], p = l.points[c.l], q = x.points[c.x]
        let wait = ScheduledTrafficWait(train: l.train.id, station: p.station, stop: p.stop, cycle: p.cycle,
                                        other: x.train.id, otherStop: q.stop, otherCycle: q.cycle,
                                        kind: .overtake, departure: GameTime(seconds: p.departure), clearance: 30,
                                        hold: Self.timetabledOvertakeHold)
        return (c.l, wait, q.arrival + fp.late)
    }
}
