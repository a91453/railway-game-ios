import GameCore

// Decision 62's second implementation. Components are flooded, not unioned;
// utilization is divided by repeated integer remainder accumulation, not
// full-width multiplication. No production capacity helper is called.
extension ReferenceWorld {
    struct CapacityTopology {
        var groups: [Set<Int>]
        var meets: Set<Int>
    }

    struct Capacity {
        var seconds: [Int64]
        var gap: Int64
        var single: Bool

        func maximum(_ minutes: Int64, ring: Bool) -> Int {
            let share = minutes / gap
            let each = Int(clamping: ring && single ? share : max(1, share))
            return (ring ? 2 : 1) * each
        }

        static func occupied(_ seconds: Int64, gap: Int64) -> Int64 {
            guard seconds > 0 else { return 0 }
            let whole = seconds / gap, part = seconds % gap
            guard whole <= Int64.max / 1440 else { return .max }
            var result = whole * 1440
            if part == 0 { return result }
            var carry: Int64 = 0
            for _ in 0..<1440 {
                if carry >= gap - part {
                    guard result < .max else { return .max }
                    result += 1
                    carry -= gap - part
                } else { carry += part }
            }
            return carry == 0 ? result : result == .max ? .max : result + 1
        }
    }

    func capacityTopology(_ line: Line) -> CapacityTopology {
        guard trafficControl else { return .init(groups: [], meets: []) }
        let count = Self.segments(line)
        let roster = Set(line.roster + line.patterns.flatMap(\.roster))
        let length = trains.filter { roster.contains($0.id) }.map(Self.length).max() ?? 0
        var meets: Set<Int> = []
        for i in line.stops.indices {
            let neighbors = [i > 0 ? i - 1 : line.ring ? line.stops.count - 1 : 1,
                             i + 1 < line.stops.count ? i + 1 : line.ring ? 0 : i - 1]
            let berths = berthsForStation(line.stops[i], length: length)
            var sides: [Set<Int>] = []
            for neighbor in neighbors {
                var edges: Set<Int> = []
                for (run, offsets) in berths {
                    for offset in offsets {
                        let place = TrainPosition.onEdge(run.traversal, offset: offset)
                        if pathToStation(from: place, station: line.stops[neighbor], length: length) != nil { edges.insert(run.edge) }
                    }
                }
                sides.append(edges)
            }
            if sides[0].intersection(sides[1]).count >= 2 { meets.insert(i) }
        }
        let sharedRing = line.ring ? ringSharedCapacity(line) : []
        let singles = Set((0..<count).filter {
            sharedRing.contains($0) ||
            parallelTracks(between: line.stops[$0], and: line.stops[($0 + 1) % line.stops.count]) == 1
        })
        var left = singles, groups: [Set<Int>] = []
        while let first = left.min() {
            var component: Set<Int> = [], pending = [first]
            while let i = pending.popLast() {
                guard left.remove(i) != nil else { continue }
                component.insert(i)
                if i > 0 && !meets.contains(i) { pending.append(i - 1) }
                if i + 1 < count && !meets.contains(i + 1) { pending.append(i + 1) }
                if line.ring && !meets.contains(0) {
                    if i == 0 { pending.append(count - 1) }
                    if i == count - 1 { pending.append(0) }
                }
            }
            groups.append(component)
        }
        return .init(groups: groups, meets: meets)
    }

    private func ringSharedCapacity(_ line: Line) -> Set<Int> {
        guard let clockwise = serviceJourney(line, 0), let counter = serviceJourney(line, 0, outer: true) else {
            return Set(line.stops.indices)
        }
        func cover(_ lap: LineJourney, counter: Bool) -> [Int: [Int: [(Int64, Int64)]]] {
            var cover: [Int: [Int: [(Int64, Int64)]]] = [:]
            var position = lap.start
            for leg in lap.legs {
                guard case .onEdge(let traversal, let offset) = position else { continue }
                let runs = [Run(traversal)!] + leg.path.traversals.map { Run($0)! }
                let segment = counter ? leg.to : leg.from
                for (i, run) in runs.enumerated() {
                    let length = networkEdges[run.edge]!.length
                    let low = i == 0 ? offset : 0
                    let high = i == runs.count - 1 ? leg.path.end ?? length : length
                    if low < high {
                        let interval = run.forward ? (low, high) : (length - high, length - low)
                        cover[segment, default: [:]][run.edge, default: []].append(interval)
                    }
                }
                let last = runs.last!
                position = .onEdge(last.traversal, offset: leg.path.end ?? networkEdges[last.edge]!.length)
            }
            return cover
        }
        let a = cover(clockwise, counter: false), b = cover(counter, counter: true)
        var shared: Set<Int> = []
        for (segment, edges) in a {
            for (edge, intervals) in edges {
                for (low, high) in intervals {
                    if (b[segment]?[edge] ?? []).contains(where: { max(low, $0.0) < min(high, $0.1) }) {
                        shared.insert(segment)
                    }
                }
            }
        }
        return shared
    }

    func capacity(_ line: Line, _ service: Int, _ journey: LineJourney,
                  topology: CapacityTopology, outer: LineJourney?) -> Capacity {
        let count = Self.segments(line)
        var seconds = Array(repeating: Int64(0), count: count)
        func crosses(_ leg: LineLeg, _ group: Set<Int>, outer: Bool) -> Bool {
            if line.ring { return group.contains(outer ? (leg.from + count - 1) % count : leg.from) }
            return group.contains { min(leg.from, leg.to) <= $0 && $0 < max(leg.from, leg.to) }
        }
        for group in topology.groups {
            var terms: [Int64] = []
            let calls = line.service(service).calls
            for meet in topology.meets where line.ring || (calls.first!...calls.last!).contains(meet) {
                let touching = line.ring ? group.contains((meet + count - 1) % count) || group.contains(meet % count)
                    : (meet != 0 && group.contains(meet - 1)) || (meet < count && group.contains(meet))
                if touching { terms.append(30) }
            }
            terms += journey.legs.filter { crosses($0, group, outer: false) }.map(\.seconds)
            if line.ring {
                if let outer { terms += outer.legs.filter { crosses($0, group, outer: true) }.map(\.seconds) }
                else { terms.append(.max) }
            }
            for call in calls where !topology.meets.contains(call) {
                let touching = line.ring ? group.contains((call + count - 1) % count) || group.contains(call % count)
                    : (call != 0 && group.contains(call - 1)) || (call < count && group.contains(call))
                if touching {
                    // Endpoints dwell once for 120 s; other calls twice for
                    // 60 s. The paired ring dwells once per direction.
                    terms.append(120)
                }
            }
            guard journey.legs.contains(where: { crosses($0, group, outer: false) }) else { continue }
            var total: Int64 = 0
            for term in terms {
                if term > Int64.max - total { total = .max; break }
                total += term
            }
            for segment in group { seconds[segment] = total }
        }
        let most = seconds.max() ?? 0
        let gap = most == 0 ? 2 : (most - 1) / 60 + 1
        return .init(seconds: seconds, gap: max(2, gap), single: most > 0)
    }

    func capacities(_ line: Line, _ journeys: [LineJourney?]) -> [Capacity?] {
        let topology = capacityTopology(line)
        guard !topology.groups.isEmpty else { return Array(repeating: nil, count: journeys.count) }
        let outer = line.ring ? serviceJourney(line, 0, outer: true) : nil
        return journeys.enumerated().map { index, journey in
            journey.map { capacity(line, index, $0, topology: topology, outer: outer) }
        }
    }
}
