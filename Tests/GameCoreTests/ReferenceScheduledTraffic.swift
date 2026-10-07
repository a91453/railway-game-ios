@testable import GameCore

/// V3 independent model: network runs are relaxed to each berth, station
/// visits are laid out by walking the resulting runs, profiles use native
/// UInt128 arithmetic, and pass time inversion brackets exponentially. No GameWorld,
/// RunningCurve or production planner/routing function is called here.
extension ReferenceWorld {
    struct PlannedVisit {
        var station: StationID
        var stop: Int
        var cycle: Int64
        var arr: Int64
        var dep: Int64
        var call: Bool
        var run: Run
        var offset: Int64
        var distance: Int64
    }
    struct PlannedService { var train: Train; var visits: [PlannedVisit] }
    struct ScheduledPlan {
        var services: [PlannedService] = []
        var waits: [ScheduledTrafficWait] = []
        var movements: [StationMoveKey: [StationMove]] = [:]
        var places: [StationMoveKey: [StationMove]] = [:]
    }

    func plannedVisits(_ train: Train, cycle: Int64) -> [PlannedVisit]? {
        guard let first = train.timetable.first else { return nil }
        var result: [PlannedVisit]?, least: Int64 = .max, mostMatched = -1
        let shift = cycle * (train.period ?? 0)
        for position in journeyStarts(onNetworkOf: first.station) {
            guard case .onEdge(let traversal, let offset) = position, let run = Run(traversal),
                  berthsForStation(first.station, length: Self.length(train))[run]?.contains(offset) == true else { continue }
            var driver = standing(Train(id: train.id, name: train.name, position: position, cars: train.cars, performance: train.performance))
            var visits = [PlannedVisit(station: first.station, stop: 0, cycle: cycle, arr: first.arrival.seconds + shift,
                                      dep: first.departure.seconds + shift, call: true, run: run, offset: offset, distance: 0)]
            var total: Int64 = 0, valid = true, matched = 0
            for stop in 1..<train.timetable.count {
                if train.timetable[stop - 1].reverses { driver = turnedOnNetwork(driver) }
                let target = train.timetable[stop].station
                guard let path = nominalRoute(train, start: driver.position!, from: stop - 1, to: stop),
                      case .onEdge(let firstRun, let at)? = driver.position else { valid = false; break }
                if let r = routePreference(train, from: stop - 1, to: stop), preferenceRoute(from: driver.position!, r, length: Self.length(train)) == path { matched += 1 }
                let seconds = train.timetable[stop].arrival.seconds - train.timetable[stop - 1].departure.seconds
                var passing: [(Int64, StationID, Run, Int64)] = []
                if let profile = ReferenceTrafficCurve.build(path.distance, seconds, train.performance) {
                    var before: Int64 = -at
                    let runs = [Run(firstRun)!] + path.traversals.map { Run($0)! }
                    for (i, part) in runs.enumerated() {
                        let end = i == runs.count - 1 ? path.end ?? networkEdges[part.edge]!.length : networkEdges[part.edge]!.length
                        for station in stations where station.id != visits.last!.station.rawValue && station.id != target.rawValue {
                            for berth in berthsForStation(StationID(rawValue: station.id), length: Self.length(train))[part] ?? [] {
                                let reach = before + berth
                                if reach > 0 && berth < end && (i > 0 || berth > at) {
                                    passing.append((reach, StationID(rawValue: station.id), part, berth))
                                }
                            }
                        }
                        before += networkEdges[part.edge]!.length
                    }
                    passing.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
                    var seen: Set<StationID> = [], previous: Int64 = 0
                    for (distance, station, run, offset) in passing where seen.insert(station).inserted {
                        let time = train.timetable[stop - 1].departure.seconds + shift + profile.firstSecond(at: distance)
                        visits.append(PlannedVisit(station: station, stop: stop, cycle: cycle, arr: time, dep: time,
                                                   call: false, run: run, offset: offset, distance: distance - previous))
                        previous = distance
                    }
                }
                driver = followed(driver, along: path)
                guard case .onEdge(let last, let end)? = driver.position else { valid = false; break }
                let previousDistance = passing.map { $0.0 }.max() ?? 0
                visits.append(PlannedVisit(station: target, stop: stop, cycle: cycle, arr: train.timetable[stop].arrival.seconds + shift,
                                           dep: train.timetable[stop].departure.seconds + shift, call: true,
                                           run: Run(last)!, offset: end, distance: path.distance - previousDistance))
                total += path.distance
            }
            if valid, matched > mostMatched || matched == mostMatched && total < least { least = total; result = visits; mostMatched = matched }
        }
        return result
    }

    func hasScheduledLoop(_ p: PlannedVisit, _ train: Train) -> Bool {
        let next = p.call ? p.stop + 1 : p.stop
        guard train.timetable.indices.contains(next) else { return false }
        if p.call, p.stop == 0, train.service?.stop == 0,
           networkStops(of: train).contains(p.station),
           case .onEdge(let traversal, _)? = train.position, traversal.edge.number == p.run.edge { return false }
        let edge = networkEdges[p.run.edge]!
        let incoming = p.run.forward ? edge.from : edge.to
        let outgoing = p.run.forward ? edge.to : edge.from
        for (run, offsets) in berthsForStation(p.station, length: Self.length(train)) where run.edge != p.run.edge {
            let e = networkEdges[run.edge]!
            guard (run.forward ? e.to : e.from) != incoming else { continue }
            for offset in offsets {
                if networkPathToStation(from: .onEdge(run.traversal, offset: offset), station: train.timetable[next].station, length: Self.length(train)) != nil
                    || runs(after: run).contains(where: { networkEdges[$0.edge]?.to == outgoing }) { return true }
            }
        }
        return false
    }

    func buildsScheduledStop(_ service: PlannedService, _ j: Int, _ departure: Int64) -> Bool {
        let v = service.visits
        let a = (0..<j).reversed().first { v[$0].call || v[$0].arr != v[$0].dep } ?? 0
        let b = ((j + 1)..<v.count).first { v[$0].call || v[$0].arr != v[$0].dep } ?? v.count - 1
        let incoming = j == 0 ? 0 : v[(a + 1)...j].reduce(Int64(0)) { $0 + $1.distance }
        let outgoing = v[(j + 1)...b].reduce(Int64(0)) { $0 + $1.distance }
        return (j == 0 || ReferenceTrafficCurve.build(incoming, v[j].arr - v[a].dep, service.train.performance) != nil)
            && ReferenceTrafficCurve.build(outgoing, v[b].arr - departure, service.train.performance) != nil
    }

    func anchorScheduled(_ service: inout PlannedService, _ j: Int, _ departure: Int64) {
        service.visits[j].dep = max(service.visits[j].dep, departure)
        let b = ((j + 1)..<service.visits.count).first { service.visits[$0].call || service.visits[$0].arr != service.visits[$0].dep } ?? service.visits.count - 1
        let length = service.visits[(j + 1)...b].reduce(Int64(0)) { $0 + $1.distance }
        guard let curve = ReferenceTrafficCurve.build(length, service.visits[b].arr - service.visits[j].dep, service.train.performance) else { return }
        var distance: Int64 = 0
        for i in (j + 1)..<b {
            distance += service.visits[i].distance
            let time = service.visits[j].dep + curve.firstSecond(at: distance)
            service.visits[i].arr = time; service.visits[i].dep = time
        }
    }

    func scheduledMeets(_ plan: inout ScheduledPlan, only: Int? = nil) {
        for i in plan.services.indices where only == nil || plan.services[i].train.id == only {
            guard plan.services[i].train.service != nil else { continue }
            var loops = [Bool?](repeating: nil, count: plan.services[i].visits.count)
            for _ in 0..<8 {
                let x = plan.services[i]
                var choices: [(Int64, Int, Int, Int, Int64, Int64)] = []
                for j in 0..<(x.visits.count - 1) {
                    let p = x.visits[j], n = x.visits[j + 1]
                    for y in plan.services.indices where y != i {
                        for k in 1..<plan.services[y].visits.count {
                            let q = plan.services[y].visits[k], previous = plan.services[y].visits[k - 1]
                            let dwell = q.dep - q.arr, terminal = k == plan.services[y].visits.count - 1
                            guard q.call, q.station == p.station, previous.station == n.station, terminal || dwell >= 30,
                                  min(Self.scheduledGap(p.arr, q.arr), Self.scheduledGap(p.arr, q.dep)) <= 1800 else { continue }
                            if loops[j] == nil { loops[j] = hasScheduledLoop(p, x.train) }
                            guard loops[j] == true else { continue }
                            let m: Int64 = terminal ? 30 : min(30, dwell / 3)
                            guard let call = (0..<k).reversed().first(where: { plan.services[y].visits[$0].call }) else { continue }
                            let end = ((j + 1)..<x.visits.count).first { x.visits[$0].station == plan.services[y].visits[call].station }
                            guard p.arr < Self.capped(q.arr, m), scheduledConflict(x.visits, j, end ?? x.visits.count - 1,
                                q.arr, plan.services[y].visits[call].dep, end != nil) else { continue }
                            let to = Self.capped(q.arr, m), difference = to - p.dep
                            guard difference > 0 && difference <= 300 else { continue }
                            let peer = plan.services[y].train.id
                            guard !plan.waits.contains(where: { w in
                                w.station == p.station && ((w.train.rawValue == x.train.id && w.stop == p.stop && w.cycle == p.cycle && w.other.rawValue == peer)
                                                           || (w.train.rawValue == peer && w.other.rawValue == x.train.id))
                            }) else { continue }
                            choices.append((difference, j, y, k, to, m))
                        }
                    }
                }
                choices.sort { a, b in
                    a.0 != b.0 ? a.0 < b.0 : a.1 != b.1 ? a.1 < b.1 : plan.services[a.2].train.id < plan.services[b.2].train.id
                }
                guard let (_, j, y, k, time, margin) = choices.first(where: { buildsScheduledStop(x, $0.1, $0.4) }) else { break }
                let p = x.visits[j], q = plan.services[y].visits[k]
                plan.waits.append(ScheduledTrafficWait(train: TrainID(rawValue: x.train.id), station: p.station, stop: p.stop, cycle: p.cycle,
                                                       other: TrainID(rawValue: plan.services[y].train.id), otherStop: q.stop, otherCycle: q.cycle,
                                                       kind: .meet, departure: GameTime(seconds: time), clearance: margin))
                anchorScheduled(&plan.services[i], j, time)
            }
        }
        scheduledDepartureMeets(&plan, only: only)
    }

    func scheduledDepartureMeets(_ plan: inout ScheduledPlan, only: Int?) {
        for x in plan.services where only == nil || x.train.id == only {
            for j in 1..<x.visits.count where !x.visits[j].call {
                let p = x.visits[j], before = x.visits[j - 1]
                for y in plan.services.indices where plan.services[y].train.id != x.train.id && plan.services[y].train.service != nil {
                    let peer = plan.services[y]
                    for k in 1..<(peer.visits.count - 1) {
                        let q = peer.visits[k], n = peer.visits[k + 1], dwell = q.dep - q.arr
                        if !q.call || q.station != p.station || n.station != before.station || dwell < 30 { continue }
                        if !hasScheduledLoop(q, peer.train) { continue }
                        if min(Self.scheduledGap(p.arr, q.arr), Self.scheduledGap(p.arr, q.dep)) > 1800 { continue }
                        let margin = min(30, dwell / 3), target = Self.capped(p.arr, min(30, dwell / 3))
                        guard let call = ((k + 1)..<peer.visits.count).first(where: { peer.visits[$0].call }), p.arr > q.dep - margin else { continue }
                        let start = (0..<j).reversed().first { x.visits[$0].station == peer.visits[call].station }
                        guard scheduledConflict(x.visits, start ?? 0, j, peer.visits[call].arr, q.dep, start != nil), buildsScheduledStop(peer, k, target) else { continue }
                        if target - q.dep > 300 || plan.waits.contains(where: { $0.station == p.station && ($0.train.rawValue == x.train.id || $0.train.rawValue == peer.train.id) }) { continue }
                        plan.waits.append(ScheduledTrafficWait(train: TrainID(rawValue: peer.train.id), station: p.station, stop: q.stop, cycle: q.cycle,
                                                               other: TrainID(rawValue: x.train.id), otherStop: p.stop, otherCycle: p.cycle, kind: .meet,
                                                               departure: GameTime(seconds: target), clearance: margin))
                        anchorScheduled(&plan.services[y], k, target)
                    }
                }
            }
        }
    }

    func scheduledConflict(_ visits: [PlannedVisit], _ a: Int, _ b: Int, _ yA: Int64, _ yB: Int64, _ exact: Bool) -> Bool {
        guard a < b else { return false }
        let distances = visits[(a + 1)...b].map(\.distance)
        let length = distances.reduce(Int64(0), +)
        var offsets = [Int64(0)]
        for distance in distances { offsets.append(offsets.last! + distance) }
        func at(_ n: Int64) -> Int64 {
            let lo = Int128(min(yA, yB)), width = Int128(max(yA, yB)) - lo
            return Int64(lo + width * Int128(yA <= yB ? n : length - n) / Int128(length))
        }
        return (a..<b).contains { i in
            guard parallelTracks(between: visits[i].station, and: visits[i + 1].station) == 1 else { return false }
            let lower = exact && length > 0 ? at(offsets[i - a + 1]) : min(yA, yB)
            let upper = exact && length > 0 ? at(offsets[i - a]) : max(yA, yB)
            return (i == a ? visits[i].dep : visits[i].arr) < upper && lower < visits[i + 1].arr
        }
    }

    static func scheduledGap(_ a: Int64, _ b: Int64) -> Int64 {
        let (gap, overflow) = max(a, b).subtractingReportingOverflow(min(a, b))
        return overflow ? .max : gap
    }

    func scheduledOvertakes(_ plan: inout ScheduledPlan) -> Bool {
        var proposed: [(slow: Int, fast: Int, j: Int, fj: Int, dep: Int64, need: Int64)] = []
        for a in plan.services.indices {
            for b in plan.services.indices where b > a {
                let A = plan.services[a].visits, B = plan.services[b].visits
                let common = B.enumerated().compactMap { j, p -> (Int, Int)? in A.firstIndex { $0.station == p.station }.map { ($0, j) } }
                let physical = hasRoutes(plan.services[a].train) || hasRoutes(plan.services[b].train)
                for common in physical ? prescribedCommon(plan.services[a], plan.services[b]) : [common] {
                    guard common.count >= 2, zip(common, common.dropFirst()).allSatisfy({ $0.0 < $1.0 }) else { continue }
                    for n in 0..<(common.count - 1) {
                        let p = common[n], q = common[n + 1]
                        guard q.0 == p.0 + 1, q.1 == p.1 + 1 else { continue }
                        if physical {
                            guard prescribedCorridor(plan.services[a], p.0, q.0, plan.services[b], p.1, q.1) else { continue }
                        } else {
                            guard A[p.0].run == B[p.1].run, A[q.0].run == B[q.1].run else { continue }
                        }
                        let d = A[p.0].dep - B[p.1].dep, e = A[q.0].arr - B[q.1].arr
                        guard d != 0, e != 0, (d < 0) != (e < 0) else { continue }
                        let slow = d < 0 ? a : b, fast = d < 0 ? b : a
                        let l = plan.services[slow], f = plan.services[fast]
                        guard l.train.service != nil else { continue }
                        let perf = l.train.performance
                        let need = 30 + (perf.topSpeed * 1000 - 1) / perf.braking + 1
                        var distance: Int64 = 0
                        for c in (0...n).reversed() {
                            if c < n, (common[c + 1].0 != common[c].0 + 1 || common[c + 1].1 != common[c].1 + 1) { break }
                            let j = d < 0 ? common[c].0 : common[c].1, fj = d < 0 ? common[c].1 : common[c].0
                            distance += l.visits[j + 1].distance
                            if distance > 1_600_000 { break }
                            let st = l.visits[j], ft = f.visits[fj], dep = Self.capped(f.visits[fj].dep, 30)
                            guard ft.arr - st.arr >= need, dep - st.arr <= 600, dep > st.dep, hasScheduledLoop(st, l.train),
                                  !plan.waits.contains(where: { $0.train.rawValue == l.train.id && $0.station == st.station && $0.stop == st.stop && $0.cycle == st.cycle && $0.departure.seconds >= dep }) else { continue }
                            guard freeOvertakeTrack(&plan, slow, j, dep) else { continue }
                            if let old = proposed.firstIndex(where: { $0.slow == slow && $0.j == j }) {
                                if proposed[old].dep < dep { proposed[old] = (slow, fast, j, fj, dep, need) }
                            } else { proposed.append((slow, fast, j, fj, dep, need)) }
                            break
                        }
                    }
                }
            }
        }
        proposed.sort { $0.slow != $1.slow ? $0.slow < $1.slow : $0.j < $1.j }
        var rebuilt: [Int] = [], relied: [Int] = []
        for p in proposed {
            let l = plan.services[p.slow], f = plan.services[p.fast], st = l.visits[p.j], ft = f.visits[p.fj]
            guard !rebuilt.contains(p.fast), !relied.contains(p.slow),
                  (!rebuilt.contains(p.slow) || (p.dep - st.arr <= 600 && ft.arr - st.arr >= p.need)), freeOvertakeTrack(&plan, p.slow, p.j, p.dep), buildsScheduledStop(l, p.j, p.dep) else { continue }
            plan.waits.removeAll { $0.train.rawValue == l.train.id && $0.station == st.station && $0.stop == st.stop && $0.cycle == st.cycle }
            plan.waits.append(ScheduledTrafficWait(train: TrainID(rawValue: l.train.id), station: st.station, stop: st.stop, cycle: st.cycle,
                                                   other: TrainID(rawValue: f.train.id), otherStop: ft.stop, otherCycle: ft.cycle,
                                                   kind: .overtake, departure: GameTime(seconds: p.dep), clearance: 30))
            anchorScheduled(&plan.services[p.slow], p.j, p.dep)
            rebuilt.append(p.slow); relied.append(p.fast)
            scheduledMeets(&plan, only: l.train.id)
        }
        return !rebuilt.isEmpty
    }

    func scheduledPlan() -> ScheduledPlan {
        guard trafficControl else { return ScheduledPlan() }
        var plan = ScheduledPlan()
        // Running services and finished ones that left visits; nothing a
        // line has yet to send out, so nothing that moves with the clock.
        for source in trains where source.position != nil && (source.service != nil || !source.trafficVisits.isEmpty) {
            let cycle = source.service?.cycle ?? source.trafficVisits.last?.cycle ?? 0
            if let visits = plannedVisits(source, cycle: cycle), visits.count >= 2 { plan.services.append(PlannedService(train: source, visits: visits)) }
        }
        scheduledMeets(&plan)
        for _ in 0..<8 { if !scheduledOvertakes(&plan) { break } }
        plan.waits.sort {
            if $0.train != $1.train { return $0.train < $1.train }
            if $0.cycle != $1.cycle { return $0.cycle < $1.cycle }
            if $0.stop != $1.stop { return $0.stop < $1.stop }
            if $0.station != $1.station { return $0.station < $1.station }
            return $0.other < $1.other
        }
        return plan
    }

    /// What a plan is worked out from that can change within one advance
    /// (the network cannot): each placed train's service, timetable and
    /// last visited cycle, and, while at its first stop, where it stands.
    struct ScheduledKey: Equatable {
        struct Entry: Equatable {
            var id: Int
            var service: Service?
            var timetable: [ScheduledStop]
            var period: Int64?
            var visitedCycle: Int64?
            var standing: [StationID]
            var edge: Int?
        }
        var trafficControl: Bool
        var entries: [Entry]
    }

    func scheduledKey() -> ScheduledKey {
        ScheduledKey(trafficControl: trafficControl, entries: trains.compactMap { train in
            guard let position = train.position else { return nil }
            let first = train.service?.stop == 0
            var edge: Int?
            if first, case .onEdge(let traversal, _) = position { edge = traversal.edge.number }
            return .init(id: train.id, service: train.service, timetable: train.timetable, period: train.period,
                         visitedCycle: train.trafficVisits.last?.cycle, standing: first ? networkStops(of: train) : [], edge: edge)
        })
    }

    /// `scheduledPlan()`, worked out again only when its key differs from
    /// the one the plan kept this advance was worked out from.
    mutating func keptScheduledPlan() -> ScheduledPlan {
        let key = scheduledKey()
        if let kept = routeMemo.scheduledFrom, kept.key == key { return kept.plan }
        let plan = scheduledPlan()
        routeMemo.scheduledFrom = (key, plan)
        return plan
    }

    func scheduledRelease(_ wait: ScheduledTrafficWait) -> Int64? {
        guard let train = trains.first(where: { $0.id == wait.other.rawValue }) else { return clockSeconds }
        if let visit = train.trafficVisits.first(where: { $0.station == wait.station && $0.stop == wait.otherStop && $0.cycle == wait.otherCycle }) {
            if let seen = wait.kind == .meet ? Optional(visit.arrival.seconds) : visit.departure?.seconds { return Self.capped(seen, wait.clearance) }
            return train.service == nil ? clockSeconds : nil
        }
        if let service = train.service, service.cycle > wait.otherCycle || (service.cycle == wait.otherCycle && service.stop > wait.otherStop) {
            return Self.capped(service.arrival, wait.clearance)
        }
        return train.service == nil ? clockSeconds : nil
    }

    /// The wait the plan and the visits give `train`, whether or not the
    /// train it waits for can come.
    func pendingScheduled(_ train: Train, plan: ScheduledPlan) -> ScheduledTrafficWait? {
        guard trafficControl, let service = train.service, isStanding(train) else { return nil }
        return plan.waits.first {
            guard $0.train.rawValue == train.id && $0.stop == service.stop && $0.cycle == service.cycle && networkStops(of: train).contains($0.station) else { return false }
            let wait = $0
            return scheduledRelease(wait).map { clockSeconds < max($0, wait.departure.seconds) } ?? true
        }
    }

    /// The wait keeping `train` where it is: none when the chain of trains
    /// waited for runs into itself, or ends at a train waiting for a route
    /// (decision 58's `waitingFor`), asked of a copy of the world.
    func waitingScheduled(_ train: Train, plan: ScheduledPlan) -> ScheduledTrafficWait? {
        guard let wait = pendingScheduled(train, plan: plan) else { return nil }
        var chain = [train.id], next = wait.other.rawValue
        while let other = trains.first(where: { $0.id == next }) {
            if chain.contains(next) { return nil }
            chain.append(next)
            if let further = pendingScheduled(other, plan: plan) { next = further.other.rawValue; continue }
            var copy = self
            return copy.waitingFor(other) == nil ? wait : nil
        }
        return wait
    }
}

extension ReferenceWorld {
    /// Costed berth selection using the independent reverse relaxation.
    /// Costs enter only at the berth or when leaving a platform edge.
    func scheduledRoute(_ train: Train, target call: StationID, plan: ScheduledPlan) -> (path: TrainPath, seconds: Int64?)? {
        guard !plan.waits.isEmpty, let service = train.service, let sequence = plan.services.first(where: { $0.train.id == train.id }),
              let position = train.position,
              let normal = networkPathToStation(from: position, station: call, length: Self.length(train)) else { return nil }
        let stop = service.waiting ? (service.stop + 1 < train.timetable.count ? service.stop + 1 : 0) : service.stop
        var target = call, least: Int64 = .max
        for wait in plan.waits where wait.train.rawValue == train.id && wait.stop == stop && wait.cycle == service.cycle && wait.station != call {
            if train.trafficVisits.contains(where: { $0.station == wait.station && $0.stop == stop && $0.cycle == wait.cycle && $0.departure != nil }) { continue }
            if let way = networkPathToStation(from: position, station: wait.station, length: Self.length(train)), way.distance > 0 && way.distance < normal.distance && way.distance < least {
                least = way.distance; target = wait.station
            }
        }
        var berthCosts: [Run: Int64] = [:], edgeCosts: [Int: Int64] = [:]
        for station in Set(plan.waits.map(\.station)).sorted() {
            guard let p = sequence.visits.first(where: { $0.station == station && ($0.stop == stop || $0.station == target) }),
                  let platforms = stations.first(where: { $0.id == station.rawValue })?.trackPlatforms else { continue }
            let stops = p.call || plan.waits.contains(where: { $0.train.rawValue == train.id && $0.station == station && $0.stop == p.stop })
            for platform in platforms where platform.edge.number != p.run.edge { edgeCosts[platform.edge.number] = 25_600 + (stops ? 0 : 51_200) }
            if station == target, stops, hasScheduledLoop(p, train) {
                for run in berthsForStation(station, length: Self.length(train)).keys where run.edge == p.run.edge { berthCosts[run] = 51_200 }
            }
        }
        let timingChanged = sequence.visits.contains { $0.call && $0.stop == service.stop && $0.dep != train.timetable[$0.stop].departure.seconds + $0.cycle * (train.period ?? 0) }
        guard timingChanged || target != call || !berthCosts.isEmpty || !edgeCosts.isEmpty,
              let way = scheduledBerthRoute(train, target, stop, normal, plan, berthCosts, edgeCosts) else { return nil }
        let there = followed(train, along: way)
        let onward = target == call ? 0 : networkPathToStation(from: there.position!, station: call, length: Self.length(train))?.distance
        guard let onward, way.distance + onward <= normal.distance + 25_600 else { return nil }
        let point = sequence.visits.first { $0.station == target && $0.stop == stop }
        let departed: Int64
        if service.waiting { departed = sequence.visits.first { $0.call && $0.stop == service.stop }?.dep ?? train.timetable[service.stop].departure.seconds + service.cycle * (train.period ?? 0) }
        else if let p = sequence.visits.first(where: { p in
            train.trafficVisits.contains(where: { $0.station == p.station && $0.stop == p.stop && $0.cycle == p.cycle && $0.departure != nil }) && networkStops(of: train).contains(p.station)
        }) { departed = p.dep }
        else { departed = clockSeconds }
        return (way, point.map { max(0, $0.arr - departed) })
    }

    mutating func recordScheduledVisits(_ plan: ScheduledPlan, before: [Train]?) {
        guard !plan.waits.isEmpty else { return }
        for i in trains.indices {
            let train = trains[i]
            guard let sequence = plan.services.first(where: { $0.train.id == train.id }) else { continue }
            for p in sequence.visits {
                guard plan.waits.contains(where: { w in
                    w.station == p.station && ((w.train.rawValue == train.id && w.stop == p.stop && w.cycle == p.cycle)
                                               || (w.other.rawValue == train.id && w.otherStop == p.stop && w.otherCycle == p.cycle))
                }) else { continue }
                var arrived: Int64?, left: Int64?
                if let s = train.service, s.stop == p.stop, s.cycle == p.cycle, networkStops(of: train).contains(p.station) {
                    arrived = p.call ? s.arrival : clockSeconds
                }
                if let old = before?.first(where: { $0.id == train.id }), let s = old.service,
                   s.cycle == p.cycle, (s.stop == p.stop || (p.call && s.stop + 1 == p.stop)), let window = routeWindow(old) {
                    let moved = max(0, wayLeft(old) - wayLeft(train))
                    for (run, span) in zip(window.path, spans(window.path)) {
                        for berth in berthsForStation(p.station, length: Self.length(train))[run] ?? [] {
                            let coordinate = span.start + berth
                            if coordinate > window.head && coordinate <= min(window.finish, window.head + moved) {
                                arrived = clockSeconds
                                if !networkStops(of: train).contains(p.station) { left = clockSeconds }
                            }
                        }
                    }
                }
                if let j = trains[i].trafficVisits.firstIndex(where: { $0.station == p.station && $0.stop == p.stop && $0.cycle == p.cycle }) {
                    if let left { trains[i].trafficVisits[j].departure = GameTime(seconds: left) }
                } else if let arrived {
                    trains[i].trafficVisits.append(TrafficVisit(station: p.station, stop: p.stop, cycle: p.cycle, arrival: GameTime(seconds: arrived), departure: left.map(GameTime.init(seconds:))))
                }
            }
            trains[i].trafficVisits.sort {
                $0.cycle != $1.cycle ? $0.cycle < $1.cycle : $0.stop != $1.stop ? $0.stop < $1.stop : $0.station < $1.station
            }
            // Only the current cycle and the one before are ever read.
            if let latest = trains[i].service?.cycle ?? trains[i].trafficVisits.last?.cycle {
                trains[i].trafficVisits.removeAll { $0.cycle < latest - 1 }
            }
        }
    }

    func scheduledDepartureHistory(_ train: Train) -> [TrafficVisit] {
        var history = train.trafficVisits
        for j in history.indices {
            if let s = train.service, s.stop == history[j].stop && s.cycle == history[j].cycle,
               history[j].departure == nil && networkStops(of: train).contains(history[j].station) {
                history[j].departure = GameTime(seconds: clockSeconds)
            }
        }
        return history
    }
}
