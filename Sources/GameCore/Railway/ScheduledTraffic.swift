// Stage V3, decision 59. Port of inferMeetRun / planSameDirectionOvertakes
// / resolveTraTraffic in Railway/site_archive_clean/index.html. Distances
// are m × 64, times whole seconds; ID order replaces source roster order.

/// An actual visit, used to release a scheduled wait even after a delayed
/// train has moved into its next run. Plans are derived, never saved.
public struct TrafficVisit: Hashable, Sendable, Codable {
    public let station: StationID
    public let stop: Int
    public let cycle: Int64
    public let arrival: GameTime
    public internal(set) var departure: GameTime?
}

/// A derived instruction to wait at a station for another service.
public struct ScheduledTrafficWait: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case meet, overtake }
    public let train: TrainID
    public let station: StationID
    /// The call containing the visit (a passing station belongs to the
    /// call ahead of it), and the timetable cycle.
    public let stop: Int
    public let cycle: Int64
    public let other: TrainID
    public let otherStop: Int
    public let otherCycle: Int64
    public let kind: Kind
    public let departure: GameTime
    public let clearance: Int64
}

extension GameWorld {
    struct TrafficPoint: Hashable {
        var station: StationID
        var stop: Int
        var cycle: Int64
        var arrival: Int64
        var departure: Int64
        var calls: Bool
        var berth: Berth
        /// Distance from the previous point along the nominal corridor.
        var distance: Int64
        var onward: Int64
    }
    struct TrafficService {
        var train: Train
        var points: [TrafficPoint]
    }
    struct TrafficPlan {
        var services: [TrafficService] = []
        var waits: [ScheduledTrafficWait] = []
        /// `parallelTracks(between:and:)` for the stations next to each
        /// other on a service, kept as the plan is worked out (the network
        /// cannot change meanwhile).
        var tracks: [TrafficSection: Int] = [:]
    }
    struct TrafficSection: Hashable {
        var from: StationID
        var to: StationID
    }

    /// Scheduled meets and overtakes, including future visits, in train,
    /// cycle and station order. Without traffic control there is no plan.
    public func scheduledTrafficWaits() -> [ScheduledTrafficWait] {
        trafficPlan().waits
    }

    /// The scheduled wait currently keeping this train at its station.
    public func scheduledTrafficWait(of id: TrainID) -> ScheduledTrafficWait? {
        guard let train = train(id: id) else { return nil }
        var memo = DirectionMemo()
        return currentTrafficWait(train, plan: trafficPlan(memo: &memo), memo: &memo)
    }

    /// What the plan is derived from: which trains run or have run, and
    /// where in their timetables. Everything else it reads (timetables,
    /// the network, the trains' lengths) cannot change within an advance.
    struct TrafficPlanKey: Equatable {
        struct Entry: Equatable {
            var id: TrainID
            var execution: TimetableExecution?
            var visitedCycle: Int64?
        }
        var enabled: Bool
        var entries: [Entry]
    }

    func trafficPlanKey() -> TrafficPlanKey {
        TrafficPlanKey(enabled: isTrafficControlEnabled, entries: trains.compactMap { train in
            train.position == nil ? nil : .init(id: train.id, execution: train.execution, visitedCycle: train.trafficVisits.last?.cycle)
        })
    }

    /// The plan for the world as it is now, worked out again only when
    /// what it is derived from has changed since `memo` last kept one;
    /// within an advance's step, the plan the step started with.
    func trafficPlan(memo: inout DirectionMemo) -> TrafficPlan {
        if let step = memo.stepTraffic { return step }
        let key = trafficPlanKey()
        if let kept = memo.traffic, kept.key == key { return kept.plan }
        let plan = trafficPlan()
        memo.traffic = (key, plan)
        return plan
    }

    func trafficPlan() -> TrafficPlan {
        guard isTrafficControlEnabled else { return TrafficPlan() }
        var plan = TrafficPlan()
        // Running services, and finished ones whose visits a waiting train
        // may still need. No hypothetical trips: the plan depends on the
        // trains' state alone, never on the clock (decision 59, point 6).
        for source in trains where source.position != nil && (source.execution != nil || !source.trafficVisits.isEmpty) {
            guard source.timetable.count >= 2 else { continue }
            let cycle = source.execution?.cycle ?? source.trafficVisits.last?.cycle ?? 0
            if let points = trafficPoints(of: source, cycle: cycle), points.count >= 2 {
                plan.services.append(TrafficService(train: source, points: points))
            }
        }
        guard plan.services.count >= 2 else { return plan }
        inferTrafficMeets(&plan)
        // resolveTraTraffic: one meet pass, up to eight overtaking passes;
        // each accepted overtake rebuilds that train's meets immediately.
        for _ in 0..<8 {
            if !planTrafficOvertakes(&plan) { break }
        }
        plan.waits.sort {
            if $0.train != $1.train { return $0.train < $1.train }
            if $0.cycle != $1.cycle { return $0.cycle < $1.cycle }
            if $0.stop != $1.stop { return $0.stop < $1.stop }
            if $0.station != $1.station { return $0.station < $1.station }
            return $0.other < $1.other
        }
        return plan
    }

    /// Complete nominal directional runs. Virtual pass times come from
    /// the same W1 curve as assignRunProfiles/profProgToTime. A reversal
    /// splits the run; no shunting or new reversal is introduced.
    func trafficPoints(of train: Train, cycle: Int64) -> [TrafficPoint]? {
        let first = train.timetable[0]
        var best: (points: [TrafficPoint], distance: Int64)?
        for berth in berths(of: first.station, length: train.length) {
            var placement = TrainPlacement(position: .onEdge(berth.traversal, offset: berth.offset), trailEdges: [], length: train.length)
            // The first platform contains the whole body.
            var points = [TrafficPoint(station: first.station, stop: 0, cycle: cycle,
                                       arrival: train.scheduledArrival(of: 0, cycle: cycle).seconds,
                                       departure: train.scheduledDeparture(of: 0, cycle: cycle).seconds,
                                       calls: true, berth: berth, distance: 0, onward: 0)]
            var total: Int64 = 0
            var valid = true
            for stop in 1..<train.timetable.count {
                if train.timetable[stop - 1].reverses { placement = turnedRound(placement) }
                let target = train.timetable[stop].station
                guard let path = path(from: placement.position, toStation: target, length: train.length) else { valid = false; break }
                let duration = train.scheduledArrival(of: stop, cycle: cycle).seconds - train.scheduledDeparture(of: stop - 1, cycle: cycle).seconds
                // No interpolated points without a physically buildable run.
                let curve = duration > 0 && duration <= RunningCurve.maximumSeconds
                    ? RunningCurve(length: path.distance, duration: duration * 1000, performance: train.performance) : nil
                let stretches = trafficStretches(from: placement.position, along: path)
                var pass: [(distance: Int64, station: StationID, berth: Berth)] = []
                if let curve, path.distance > 0 {
                    for station in stations where station.id != points.last!.station && station.id != target {
                        for place in berths(of: station.id, length: train.length) {
                            var before: Int64 = 0
                            for stretch in stretches {
                                if stretch.traversal == place.traversal, place.offset > stretch.from, place.offset < stretch.to {
                                    pass.append((before + place.offset - stretch.from, station.id, place))
                                }
                                before += stretch.to - stretch.from
                            }
                        }
                    }
                    pass.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.station < $1.station }
                    var seen: Set<StationID> = []
                    var previous: Int64 = 0
                    for p in pass where seen.insert(p.station).inserted {
                        let time = train.scheduledDeparture(of: stop - 1, cycle: cycle).seconds + trafficTime(on: curve, distance: p.distance)
                        points.append(TrafficPoint(station: p.station, stop: stop, cycle: cycle, arrival: time, departure: time,
                                                   calls: false, berth: p.berth, distance: p.distance - previous, onward: path.distance - p.distance))
                        previous = p.distance
                    }
                }
                let there = self.placement(placement, after: path)
                guard case .onEdge(let last, let offset) = there.position else { valid = false; break }
                let part = pass.first.map { _ in path.distance - (points.last!.calls ? 0 : path.distance - points.last!.onward) } ?? path.distance
                points.append(TrafficPoint(station: target, stop: stop, cycle: cycle,
                                           arrival: train.scheduledArrival(of: stop, cycle: cycle).seconds,
                                           departure: train.scheduledDeparture(of: stop, cycle: cycle).seconds,
                                           calls: true, berth: Berth(traversal: last, offset: offset), distance: part, onward: 0))
                placement = there
                let (sum, overflow) = total.addingReportingOverflow(path.distance)
                guard !overflow else { valid = false; break }
                total = sum
            }
            if valid, total < best?.distance ?? .max { best = (points, total) }
        }
        return best?.points
    }

    func trafficStretches(from position: TrainPosition, along path: TrainPath) -> [TrackStretch] {
        guard case .onEdge(let first, let offset) = position else { return [] }
        let traversals = [first] + path.traversals
        return traversals.enumerated().map { i, traversal in
            TrackStretch(traversal: traversal, from: i == 0 ? offset : 0,
                         to: i == traversals.count - 1 ? path.end ?? network.edge(traversal.edge)!.length : network.edge(traversal.edge)!.length)
        }
    }

    /// profProgToTime: first whole second at which the fixed-point curve
    /// reaches the requested distance (binary search, rather than floats).
    func trafficTime(on curve: RunningCurve, distance: Int64) -> Int64 {
        var (low, high): (Int64, Int64) = (0, curve.duration / 1000)
        while low < high {
            let middle = low + (high - low) / 2
            if curve.distance(at: middle * 1000) >= distance { high = middle } else { low = middle + 1 }
        }
        return low
    }

    /// inferMeetRun's overlap test and arrival/departure anchors. Stopping
    /// calls already meeting the anchor need no extra wait. The advance
    /// anchor (趕它開) makes the other train wait for our actual arrival;
    /// it cannot make a service leave before its timetable (decision 20).
    func inferTrafficMeets(_ plan: inout TrafficPlan, only id: TrainID? = nil) {
        for index in plan.services.indices where id == nil || plan.services[index].train.id == id {
            // sections[tracks === 1], derived from the graph: asked only of
            // a point another service calls at, and once, since it walks the
            // network (anchoring moves the times, never the points).
            var sidings = [Bool?](repeating: nil, count: plan.services[index].points.count)
            for _ in 0..<8 {
                let x = plan.services[index]
                guard x.train.execution != nil else { break }
                var candidates: [(point: Int, peer: Int, peerPoint: Int, time: Int64, shift: Int64, clearance: Int64)] = []
                for j in 0..<(x.points.count - 1) {
                    let p = x.points[j], next = x.points[j + 1]
                    for peer in plan.services.indices where peer != index {
                        let y = plan.services[peer]
                        for k in 1..<y.points.count {
                            let q = y.points[k], previous = y.points[k - 1]
                            guard q.station == p.station, previous.station == next.station, q.calls else { continue }
                            let dwell = q.departure - q.arrival
                            let terminal = k == 0 || k == y.points.count - 1
                            guard terminal || dwell >= 30 else { continue }
                            let margin: Int64 = terminal ? 30 : min(30, dwell / 3)
                            let near = min(Self.trafficDifference(p.arrival, q.arrival), Self.trafficDifference(p.arrival, q.departure))
                            let previousCall = (0..<k).reversed().first { y.points[$0].calls }
                            guard let previousCall, near <= 1800 else { continue }
                            if sidings[j] == nil { sidings[j] = trafficHasSiding(at: p, train: x.train) }
                            guard sidings[j] == true else { continue }
                            let end = ((j + 1)..<x.points.count).first { x.points[$0].station == y.points[previousCall].station }
                            guard p.arrival < Self.saturating(GameTime(seconds: q.arrival), plus: margin).seconds,
                                  trafficConflict(x.points, from: j, to: end ?? x.points.count - 1,
                                                  otherFrom: q.arrival, otherTo: y.points[previousCall].departure, exact: end != nil,
                                                  tracks: &plan.tracks) else { continue }
                            let target = Self.saturating(GameTime(seconds: q.arrival), plus: margin).seconds
                            let shift = target - p.departure
                            guard shift > 0, shift <= 300,
                                  !plan.waits.contains(where: { $0.train == x.train.id && $0.station == p.station && $0.stop == p.stop && $0.cycle == p.cycle && $0.other == y.train.id })
                            else { continue }
                            // Do not introduce mutually dependent waits at the
                            // same station. The first smaller shift / ID wins.
                            guard !plan.waits.contains(where: { $0.train == y.train.id && $0.other == x.train.id && $0.station == p.station }) else { continue }
                            candidates.append((j, peer, k, target, shift, margin))
                        }
                    }
                }
                candidates.sort {
                    if $0.shift != $1.shift { return $0.shift < $1.shift }
                    if $0.point != $1.point { return $0.point < $1.point }
                    return plan.services[$0.peer].train.id < plan.services[$1.peer].train.id
                }
                guard let c = candidates.first(where: { trafficStopBuildable(x, at: $0.point, departure: $0.time) }) else { break }
                let p = x.points[c.point], y = plan.services[c.peer], q = y.points[c.peerPoint]
                plan.waits.append(ScheduledTrafficWait(train: x.train.id, station: p.station, stop: p.stop, cycle: p.cycle,
                                                       other: y.train.id, otherStop: q.stop, otherCycle: q.cycle, kind: .meet,
                                                       departure: GameTime(seconds: c.time), clearance: c.clearance))
                applyTrafficAnchor(&plan.services[index], at: c.point, departure: c.time)
            }
        }
        inferTrafficDepartureMeets(&plan, only: id)
    }

    /// inferMeetRun's hiMeet / 交會(趕它開) constraint. The sampling
    /// reference advances the passing train's profile; an authoritative
    /// game cannot promise an early arrival. Bind the opposing departure
    /// to that train's actual passage instead (decision 59).
    func inferTrafficDepartureMeets(_ plan: inout TrafficPlan, only id: TrainID?) {
        for x in plan.services where id == nil || x.train.id == id {
            for j in 1..<x.points.count where !x.points[j].calls {
                let p = x.points[j], previous = x.points[j - 1]
                for y in plan.services.indices where plan.services[y].train.id != x.train.id {
                    let peer = plan.services[y]
                    guard peer.train.execution != nil else { continue }
                    for k in 1..<(peer.points.count - 1) {
                        let q = peer.points[k], next = peer.points[k + 1]
                        let dwell = q.departure - q.arrival
                        guard q.calls, q.station == p.station, next.station == previous.station, dwell >= 30,
                              trafficHasSiding(at: q, train: peer.train),
                              min(Self.trafficDifference(p.arrival, q.arrival), Self.trafficDifference(p.arrival, q.departure)) <= 1800 else { continue }
                        let margin = min(30, dwell / 3)
                        let nextCall = ((k + 1)..<peer.points.count).first { peer.points[$0].calls }
                        guard let nextCall, p.arrival > q.departure - margin else { continue }
                        let start = (0..<j).reversed().first { x.points[$0].station == peer.points[nextCall].station }
                        guard trafficConflict(x.points, from: start ?? 0, to: j,
                                              otherFrom: peer.points[nextCall].arrival, otherTo: q.departure, exact: start != nil,
                                              tracks: &plan.tracks) else { continue }
                        let target = Self.saturating(GameTime(seconds: p.arrival), plus: margin).seconds
                        guard target - q.departure <= 300,
                              !plan.waits.contains(where: { $0.station == p.station && ($0.train == x.train.id || $0.train == peer.train.id) }),
                              trafficStopBuildable(peer, at: k, departure: target) else { continue }
                        plan.waits.append(ScheduledTrafficWait(train: peer.train.id, station: p.station, stop: q.stop, cycle: q.cycle,
                                                               other: x.train.id, otherStop: p.stop, otherCycle: p.cycle, kind: .meet,
                                                               departure: GameTime(seconds: target), clearance: margin))
                        applyTrafficAnchor(&plan.services[y], at: k, departure: target)
                    }
                }
            }
        }
    }

    /// inferMeetRun/conflictOn: inspect every single-track interval in
    /// the common run. Exact common endpoints use distance interpolation;
    /// an unmatched endpoint uses the source's conservative time envelope.
    func trafficConflict(_ points: [TrafficPoint], from a: Int, to b: Int, otherFrom: Int64, otherTo: Int64, exact: Bool,
                         tracks: inout [TrafficSection: Int]) -> Bool {
        guard a < b else { return false }
        let length = points[(a + 1)...b].reduce(Int64(0)) { $0 + $1.distance }
        var distance: Int64 = 0
        for i in a..<b {
            let nextDistance = distance + points[i + 1].distance
            defer { distance = nextDistance }
            let section = TrafficSection(from: points[i].station, to: points[i + 1].station)
            let count = tracks[section] ?? parallelTracks(between: section.from, and: section.to)
            tracks[section] = count
            guard count == 1 else { continue }
            let y0 = exact && length > 0 ? Self.trafficInterpolate(otherFrom, otherTo, nextDistance, length) : min(otherFrom, otherTo)
            let y1 = exact && length > 0 ? Self.trafficInterpolate(otherFrom, otherTo, distance, length) : max(otherFrom, otherTo)
            if (i == a ? points[a].departure : points[i].arrival) < y1 && y0 < points[i + 1].arrival { return true }
        }
        return false
    }

    static func trafficInterpolate(_ a: Int64, _ b: Int64, _ numerator: Int64, _ denominator: Int64) -> Int64 {
        let low = min(a, b), high = max(a, b)
        let width = UInt64(bitPattern: high) &- UInt64(bitPattern: low)
        let n = UInt64(a <= b ? numerator : denominator - numerator)
        let part = UInt64(denominator).dividingFullWidth(width.multipliedFullWidth(by: n)).quotient
        return Int64(bitPattern: UInt64(bitPattern: low) &+ part)
    }

    static func trafficDifference(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = max(a, b).subtractingReportingOverflow(min(a, b))
        return overflow ? .max : value
    }

    /// overtakeRunBuildable: both new stopping runs must fit, with the W1
    /// alternatives tried by RunningCurve. Existing calls are boundaries.
    func trafficStopBuildable(_ service: TrafficService, at j: Int, departure: Int64) -> Bool {
        let points = service.points
        var a = j - 1, b = j + 1
        while a > 0 && !points[a].calls && points[a].departure == points[a].arrival { a -= 1 }
        while b < points.count - 1 && !points[b].calls && points[b].departure == points[b].arrival { b += 1 }
        func can(_ from: Int, _ to: Int, _ seconds: Int64) -> Bool {
            let distance = points[(from + 1)...to].reduce(Int64(0)) { $0 + $1.distance }
            return distance > 0 && seconds > 0 && seconds <= RunningCurve.maximumSeconds
                && RunningCurve(length: distance, duration: seconds * 1000, performance: service.train.performance) != nil
        }
        return (j == 0 || can(a, j, points[j].arrival - points[a].departure)) && can(j, b, points[b].arrival - departure)
    }

    /// reanchorRunProfile/applyRunProfile adapted to an actual station
    /// stop: rebuild the outgoing W1 profile while keeping the next call's
    /// time fixed. Never propagate an arbitrary shift through the timetable.
    func applyTrafficAnchor(_ service: inout TrafficService, at j: Int, departure: Int64) {
        service.points[j].departure = max(service.points[j].departure, departure)
        var b = j + 1
        while b < service.points.count - 1 && !service.points[b].calls && service.points[b].arrival == service.points[b].departure { b += 1 }
        let distance = service.points[(j + 1)...b].reduce(Int64(0)) { $0 + $1.distance }
        let seconds = service.points[b].arrival - service.points[j].departure
        guard distance > 0, seconds > 0, seconds <= RunningCurve.maximumSeconds,
              let curve = RunningCurve(length: distance, duration: seconds * 1000, performance: service.train.performance)
        else { return }
        var covered: Int64 = 0
        for i in (j + 1)..<b {
            covered += service.points[i].distance
            let time = service.points[j].departure + trafficTime(on: curve, distance: covered)
            service.points[i].arrival = time
            service.points[i].departure = time
        }
    }

    /// Direct translation of proposal, rebuild and relied-on ordering.
    /// The game's slow trains may also use their existing dwell at a call.
    func planTrafficOvertakes(_ plan: inout TrafficPlan) -> Bool {
        struct Proposal { var slow: Int; var fast: Int; var point: Int; var fastPoint: Int; var departure: Int64; var need: Int64 }
        var proposals: [Proposal] = []
        for ia in plan.services.indices {
            for ib in plan.services.indices where ib > ia {
                let a = plan.services[ia], b = plan.services[ib]
                var common: [(ai: Int, bi: Int)] = []
                for (j, p) in b.points.enumerated() {
                    if let i = a.points.firstIndex(where: { $0.station == p.station }) { common.append((i, j)) }
                }
                guard common.count >= 2, zip(common, common.dropFirst()).allSatisfy({ $0.ai < $1.ai }) else { continue }
                for n in 0..<(common.count - 1) {
                    let p = common[n], q = common[n + 1]
                    guard q.ai == p.ai + 1, q.bi == p.bi + 1 else { continue }
                    let d0 = a.points[p.ai].departure - b.points[p.bi].departure
                    let d1 = a.points[q.ai].arrival - b.points[q.bi].arrival
                    guard d0 != 0, d1 != 0, (d0 < 0) != (d1 < 0) else { continue }
                    // Same physical corridor, in the same direction.
                    guard a.points[p.ai].berth.traversal == b.points[p.bi].berth.traversal,
                          a.points[q.ai].berth.traversal == b.points[q.bi].berth.traversal else { continue }
                    let slow = d0 < 0 ? ia : ib, fast = d0 < 0 ? ib : ia
                    let l = plan.services[slow], f = plan.services[fast]
                    guard l.train.execution != nil else { continue }
                    let perf = l.train.performance
                    let need = 30 + (perf.topSpeed * 1000 + perf.braking - 1) / perf.braking
                    var look: Int64 = 0
                    for c in stride(from: n, through: 0, by: -1) {
                        let lc = d0 < 0 ? common[c].ai : common[c].bi, fc = d0 < 0 ? common[c].bi : common[c].ai
                        if c < n, (common[c + 1].ai != common[c].ai + 1 || common[c + 1].bi != common[c].bi + 1) { break }
                        look += l.points[lc + 1].distance
                        if look > 25 * 64_000 { break }
                        let st = l.points[lc], fst = f.points[fc]
                        let dep = Self.saturating(GameTime(seconds: fst.departure), plus: 30).seconds
                        guard fst.arrival - st.arrival >= need, dep - st.arrival <= 600,
                              dep > st.departure, trafficHasSiding(at: st, train: l.train),
                              !plan.waits.contains(where: { $0.train == l.train.id && $0.station == st.station && $0.stop == st.stop && $0.cycle == st.cycle && $0.departure.seconds >= dep })
                        else { continue }
                        let proposal = Proposal(slow: slow, fast: fast, point: lc, fastPoint: fc, departure: dep, need: need)
                        if let old = proposals.firstIndex(where: { $0.slow == slow && $0.point == lc }) {
                            if proposals[old].departure < dep { proposals[old] = proposal }
                        } else { proposals.append(proposal) }
                        break
                    }
                }
            }
        }
        proposals.sort { $0.slow != $1.slow ? $0.slow < $1.slow : $0.point < $1.point }
        var rebuilt: Set<Int> = [], relied: Set<Int> = []
        var changed = false
        for p in proposals {
            let l = plan.services[p.slow], f = plan.services[p.fast]
            let st = l.points[p.point], fst = f.points[p.fastPoint]
            guard !rebuilt.contains(p.fast), !relied.contains(p.slow),
                  (!rebuilt.contains(p.slow) || (p.departure - st.arrival <= 600 && fst.arrival - st.arrival >= p.need)),
                  trafficStopBuildable(l, at: p.point, departure: p.departure)
            else { continue }
            plan.waits.removeAll { $0.train == l.train.id && $0.station == st.station && $0.stop == st.stop && $0.cycle == st.cycle }
            plan.waits.append(ScheduledTrafficWait(train: l.train.id, station: st.station, stop: st.stop, cycle: st.cycle,
                                                   other: f.train.id, otherStop: fst.stop, otherCycle: fst.cycle,
                                                   kind: .overtake, departure: GameTime(seconds: p.departure), clearance: 30))
            applyTrafficAnchor(&plan.services[p.slow], at: p.point, departure: p.departure)
            rebuilt.insert(p.slow); relied.insert(p.fast); changed = true
            inferTrafficMeets(&plan, only: l.train.id)
        }
        return changed
    }

    func trafficHasSiding(at point: TrafficPoint, train: Train) -> Bool {
        let next = point.calls ? point.stop + 1 : point.stop
        guard train.timetable.indices.contains(next) else { return false }
        let main = point.berth
        // A service already placed at its first call on the main cannot
        // change berth before waiting without an extra shunting movement.
        // Leave this case to V1/V2 instead of blocking a passing express.
        if point.calls, point.stop == 0, train.execution?.stop == 0,
           isStopped(train, at: point.station),
           case .onEdge(let actual, _)? = train.position, actual.edge == main.traversal.edge { return false }
        let direction = network.edge(main.traversal.edge)!
        let outgoing = main.traversal.direction == .forward ? direction.to : direction.from
        return berths(of: point.station, length: train.length).contains { berth in
            guard berth.traversal.edge != main.traversal.edge, let edge = network.edge(berth.traversal.edge),
                  (berth.traversal.direction == .forward ? edge.to : edge.from) != (main.traversal.direction == .forward ? direction.from : direction.to)
            else { return false }
            let position = TrainPosition.onEdge(berth.traversal, offset: berth.offset)
            return path(from: position, toStation: train.timetable[next].station, length: train.length) != nil
                || transitions(after: berth.traversal).contains(where: { network.edge($0.edge)?.to == outgoing })
        }
    }

    func trafficReleased(_ wait: ScheduledTrafficWait) -> GameTime? {
        guard let peer = train(id: wait.other) else { return clock.now }
        if let visit = peer.trafficVisits.first(where: { $0.station == wait.station && $0.stop == wait.otherStop && $0.cycle == wait.otherCycle }) {
            let event = wait.kind == .meet ? visit.arrival : visit.departure
            if let event { return Self.saturating(event, plus: wait.clearance) }
            // Its service ended there: it never leaves.
            return peer.execution == nil ? clock.now : nil
        }
        // Services already beyond a call in an older save have no visit
        // history: wait conservatively from their last actual arrival.
        if let execution = peer.execution,
           execution.cycle > wait.otherCycle || (execution.cycle == wait.otherCycle && execution.stop > wait.otherStop),
           let times = peer.times { return Self.saturating(times.arrival, plus: wait.clearance) }
        // A service that has ended (or stopped) will not come.
        return peer.execution == nil ? clock.now : nil
    }

    /// The scheduled wait keeping `train` at its station, as the plan and
    /// the actual visits have it, before asking whether the train waited
    /// for can come at all (see ``currentTrafficWait(_:plan:memo:)``).
    func pendingTrafficWait(_ train: Train, plan: TrafficPlan) -> ScheduledTrafficWait? {
        guard isTrafficControlEnabled, let execution = train.execution, standingPoint(of: train) != nil else { return nil }
        return plan.waits.first { wait in
            guard wait.train == train.id, wait.stop == execution.stop, wait.cycle == execution.cycle,
                  isStopped(train, at: wait.station) else { return false }
            let released = trafficReleased(wait)
            return released == nil || clock.now < max(wait.departure, released!)
        }
    }

    /// The scheduled wait keeping `train` at its station (decision 59). A
    /// wait is only worth keeping for a train that is on its way: follow
    /// who waits for whom from `train`, and drop the wait when that comes
    /// back to a train already met (they would wait for each other for
    /// ever), or ends at a train that itself waits for a route (see
    /// ``waitingRoute(of:memo:)``). Traffic control then works as it does
    /// without a plan (decisions 57 and 58), and a deadlock among them is
    /// found and reported as any other.
    func currentTrafficWait(_ train: Train, plan: TrafficPlan, memo: inout DirectionMemo) -> ScheduledTrafficWait? {
        guard let wait = pendingTrafficWait(train, plan: plan) else { return nil }
        var met: Set<TrainID> = [train.id]
        var other = wait.other
        while let next = self.train(id: other) {
            guard met.insert(other).inserted else { return nil }
            if let further = pendingTrafficWait(next, plan: plan) {
                other = further.other
                continue
            }
            return waitingRoute(of: next, memo: &memo) == nil ? wait : nil
        }
        return wait
    }
}

extension GameWorld {
    /// §7 generalized costs. No defaults were readable in the binary.
    /// 400 m station cost; 800 m berth mismatch dominates a local turnout
    /// but never authorizes a route beyond V1's 400 m detour allowance.
    static let trafficStationPenalty: Int64 = 25_600
    static let trafficMismatchPenalty: Int64 = 51_200

    func scheduledPath(for train: Train, from start: TrainPosition, to call: StationID, plan: TrafficPlan) -> (path: TrainPath, seconds: Int64?)? {
        // Without a wait nothing is costed or retimed, so there is no
        // scheduled way to work out.
        guard !plan.waits.isEmpty, let execution = train.execution, let service = plan.services.first(where: { $0.train.id == train.id }),
              let normal = path(from: start, toStation: call, length: train.length) else { return nil }
        let stop: Int
        if case .waitingAtStop = execution { stop = train.call(after: execution.stop, cycle: execution.cycle)?.stop ?? execution.stop }
        else { stop = execution.stop }
        let waits = plan.waits.filter { $0.train == train.id && $0.stop == stop && $0.cycle == execution.cycle && $0.station != call }
        var target = call
        var targetPoint = service.points.first { $0.stop == stop && $0.calls }
        var bestDistance: Int64 = .max
        for wait in waits {
            if train.trafficVisits.contains(where: { $0.station == wait.station && $0.stop == stop && $0.cycle == wait.cycle && $0.departure != nil }) { continue }
            guard let to = path(from: start, toStation: wait.station, length: train.length), to.distance > 0,
                  to.distance < normal.distance, to.distance < bestDistance else { continue }
            bestDistance = to.distance
            target = wait.station
            targetPoint = service.points.first { $0.station == target && $0.stop == stop }
        }
        var berthPenalty: [Berth: Int64] = [:]
        var edgePenalty: [TrackEdgeID: Int64] = [:]
        // Only stations with a scheduled conflict activate these costs.
        for station in Set(plan.waits.map(\.station)).sorted() {
            guard let point = service.points.first(where: { $0.station == station && ($0.stop == stop || $0.station == target) }) else { continue }
            let stopsHere = point.calls || plan.waits.contains(where: { $0.train == train.id && $0.station == station && $0.stop == point.stop })
            for platform in network.platforms(of: station) {
                // The shortest nominal corridor is the main line;
                // a parallel platform edge is a loop, independent of ID.
                if platform.edge != point.berth.traversal.edge {
                    edgePenalty[platform.edge] = Self.trafficStationPenalty + (stopsHere ? 0 : Self.trafficMismatchPenalty)
                }
            }
            if station == target, stopsHere, trafficHasSiding(at: point, train: train) {
                for berth in berths(of: station, length: train.length) where berth.traversal.edge == point.berth.traversal.edge {
                    berthPenalty[berth] = Self.trafficMismatchPenalty
                }
            }
        }
        let timingChanged = service.points.contains { p in
            p.calls && p.stop == execution.stop && p.departure != train.scheduledDeparture(of: p.stop, cycle: p.cycle).seconds
        }
        guard timingChanged || !berthPenalty.isEmpty || !edgePenalty.isEmpty || target != call,
              let chosen = trafficPath(from: start, toStation: target, length: train.length, berthPenalty: berthPenalty, edgePenalty: edgePenalty)
        else { return nil }
        let there = placement(TrainPlacement(position: start, trailEdges: train.trailEdges, length: train.length), after: chosen)
        let onward = target == call ? 0 : path(from: there.position, toStation: call, length: train.length)?.distance
        guard let onward, chosen.distance <= normal.distance + Self.detourAllowance - onward else { return nil }
        let seconds: Int64?
        if let point = targetPoint {
            let departure: Int64
            if case .waitingAtStop = execution {
                departure = service.points.first(where: { $0.calls && $0.stop == execution.stop })?.departure
                    ?? train.scheduledDeparture(of: execution.stop, cycle: execution.cycle).seconds
            } else if let last = service.points.first(where: { p in
                train.trafficVisits.contains(where: { $0.station == p.station && $0.stop == p.stop && $0.cycle == p.cycle && $0.departure != nil }) && isStopped(train, at: p.station)
            }) { departure = last.departure }
            else { departure = clock.now.seconds }
            seconds = max(0, point.arrival - departure)
        } else { seconds = nil }
        return (chosen, seconds)
    }

}
