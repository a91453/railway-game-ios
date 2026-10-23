@testable import GameCore

/// Decision 366, written a second time for ``ReferenceWorld``: a train of a
/// line that runs at a headway stands aside for a faster one behind it,
/// from how late each actually is. Written from the decision's rules, not
/// from GameCore, and differently where it can be:
///
/// - a service's lateness is read from its stored fields, its timetable
///   shifted by hand;
/// - the stretch both run along is walked visit by visit as it is checked,
///   not collected first;
/// - the wait for the train that passes first is kept per slow train in a
///   dictionary keyed by visit.
extension ReferenceWorld {
    /// The visit `service` waits at or last left, whether it still waits,
    /// and how many seconds behind its timetable it is (none when early).
    func headwayLateness(_ service: PlannedService) -> (j: Int, waiting: Bool, late: Int64)? {
        let train = service.train
        guard let now = train.service else { return nil }
        let shift = now.cycle > 0 ? now.cycle * (train.period ?? 0) : 0
        let k = now.waiting ? now.stop : now.stop - 1
        guard k >= 0, let j = service.visits.firstIndex(where: { $0.call && $0.stop == k && $0.cycle == now.cycle }) else { return nil }
        if now.waiting { return (j, true, max(0, now.arrival - train.timetable[k].arrival.seconds - shift)) }
        guard let left = now.departure else { return nil }
        return (j, false, max(0, left - train.timetable[k].departure.seconds - shift))
    }

    func headwayOvertakes(_ plan: inout ScheduledPlan) {
        var rostered: Set<Int> = []
        for line in lines {
            for k in 0...line.patterns.count { rostered.formUnion(line.service(k).roster) }
        }
        let eligible = plan.services.indices.filter {
            rostered.contains(plan.services[$0].train.id) && plan.services[$0].train.period == nil && headwayLateness(plan.services[$0]) != nil
        }
        guard eligible.count > 1 else { return }
        var kept: [Int: [Int: (wait: ScheduledTrafficWait, pass: Int64)]] = [:]
        var order: [(Int, Int)] = []
        for s in eligible {
            for f in eligible where f != s {
                guard let found = headwayWait(&plan, slow: s, fast: f) else { continue }
                if let old = kept[s]?[found.j] {
                    if found.pass < old.pass { kept[s]![found.j] = (found.wait, found.pass) }
                } else {
                    kept[s, default: [:]][found.j] = (found.wait, found.pass)
                    order.append((s, found.j))
                }
            }
        }
        for (s, j) in order {
            let wait = kept[s]![j]!.wait
            if plan.waits.contains(where: { $0.train == wait.train && $0.station == wait.station && $0.stop == wait.stop && $0.cycle == wait.cycle }) { continue }
            plan.waits.append(wait)
        }
    }

    func headwayWait(_ plan: inout ScheduledPlan, slow s: Int, fast f: Int) -> (j: Int, wait: ScheduledTrafficWait, pass: Int64)? {
        let slow = plan.services[s], fast = plan.services[f]
        guard let a = headwayLateness(slow), let b = headwayLateness(fast), let mine = slow.train.service else { return nil }
        let here = slow.visits[a.j]
        guard let k = (b.j..<fast.visits.count).first(where: { fast.visits[$0].station == here.station }),
              fast.visits[k].run == here.run,
              !fast.train.trafficVisits.contains(where: { $0.station == here.station && $0.stop == fast.visits[k].stop && $0.cycle == fast.visits[k].cycle && $0.departure != nil })
        else { return nil }
        // Is the fast one behind?
        if k != b.j {
            guard fast.visits[k].arr + b.late >= mine.arrival else { return nil }
        } else if b.waiting {
            if a.waiting && here.dep + a.late >= fast.visits[k].dep + b.late { return nil }
        } else {
            guard !a.waiting, let mineLeft = mine.departure, let theirsLeft = fast.train.service?.departure, mineLeft < theirsLeft else { return nil }
        }
        // Walk the stretch both run along: where the fast one catches up.
        var stretch = [(a.j, k)], caught: Int?, run: Int64 = 0
        while true {
            let n = stretch.count - 1
            if n > 0 { run += slow.visits[stretch[n].0].distance }
            if run > 1_600_000 { break }
            if n > 0 || a.waiting, fast.visits[stretch[n].1].arr + b.late < slow.visits[stretch[n].0].dep + a.late { caught = n; break }
            let (i, m) = (stretch[n].0 + 1, stretch[n].1 + 1)
            guard i < slow.visits.count, m < fast.visits.count, slow.visits[i].station == fast.visits[m].station, slow.visits[i].run == fast.visits[m].run else { break }
            stretch.append((i, m))
        }
        guard let caught else { return nil }
        // The rest of the stretch, for standing aside beyond the catch.
        while let last = stretch.last, last.0 + 1 < slow.visits.count, last.1 + 1 < fast.visits.count,
              slow.visits[last.0 + 1].station == fast.visits[last.1 + 1].station, slow.visits[last.0 + 1].run == fast.visits[last.1 + 1].run {
            stretch.append((last.0 + 1, last.1 + 1))
        }
        func fits(_ n: Int) -> Bool {
            let (i, m) = stretch[n], v = slow.visits[i]
            if n == 0 {
                guard a.waiting, case .onEdge(let standing, _)? = slow.train.position, standing.edge.number != here.run.edge else { return false }
            } else if v.stop <= here.stop + (a.waiting ? 0 : 1) {
                return false
            }
            return hasScheduledLoop(v, slow.train) && freeOvertakeTrack(&plan, s, i, max(v.dep, fast.visits[m].dep + b.late - a.late + 30))
        }
        var chosen: Int?
        for n in (0...caught).reversed() where fits(n) { chosen = n; break }
        if chosen == nil {
            var beyond: Int64 = 0
            for n in (caught + 1)..<max(caught + 1, stretch.count) {
                beyond += slow.visits[stretch[n].0].distance
                if beyond > 1_600_000 { break }
                if fits(n) { chosen = n; break }
            }
        }
        guard let chosen else { return nil }
        let (i, m) = stretch[chosen], v = slow.visits[i], w = fast.visits[m]
        let wait = ScheduledTrafficWait(train: TrainID(rawValue: slow.train.id), station: v.station, stop: v.stop, cycle: v.cycle,
                                        other: TrainID(rawValue: fast.train.id), otherStop: w.stop, otherCycle: w.cycle,
                                        kind: .overtake, departure: GameTime(seconds: v.dep), clearance: 30, hold: 300)
        return (i, wait, w.arr + b.late)
    }
}
