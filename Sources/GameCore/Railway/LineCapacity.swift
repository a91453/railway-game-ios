// Stage V4c: a derived planning bound, never saved. Single track is a
// meet-to-meet resource, not a separate independent lane in each direction.
// Decision 62 documents the conservative nominal-window formula and gaps.

struct LineCapacityLayout: Sendable {
    let blocks: [[Int]]
    let passing: Set<Int>
}

struct ServiceCapacityProfile: Sendable {
    /// Seconds one complete nominal round trip occupies each single-track
    /// block; identical on that block's segments. Zero on double track.
    let work: [Int64]
    let minimumHeadway: Int64
    let hasSingleTrack: Bool

    func maximum(roundTrip: Int64, ring: Bool) -> Int {
        let quotient = roundTrip / minimumHeadway
        let each = Int(clamping: ring && hasSingleTrack ? quotient : max(1, quotient))
        return ring ? each * 2 : each
    }

    /// ceil(work * minutesPerDay / headway), without a narrow product.
    /// A day's resource seconds, not a rounded count of daily departures:
    /// a departure crossing midnight must not consume its whole trip twice.
    static func usage(_ work: Int64, headway: Int64) -> Int64 {
        guard work > 0 else { return 0 }
        let product = UInt64(work).multipliedFullWidth(by: UInt64(GameTime.minutesPerDay))
        let divisor = UInt64(headway)
        guard product.high < divisor else { return .max }
        let answer = divisor.dividingFullWidth(product)
        guard answer.quotient < UInt64(Int64.max) else { return .max }
        let rounded = answer.quotient + (answer.remainder == 0 ? 0 : 1)
        return Int64(clamping: rounded)
    }
}

extension GameWorld {
    func capacityProfiles(of line: ServiceLine, journeys: [LineJourney?]) -> [ServiceCapacityProfile?] {
        let layout = capacityLayout(of: line)
        guard !layout.blocks.isEmpty else { return Array(repeating: nil, count: journeys.count) }
        let outer = line.isRing ? journey(of: line, service: 0, direction: .outer) : nil
        return journeys.enumerated().map { service, journey in
            journey.map { capacityProfile(of: line, service: service, journey: $0, layout: layout, outer: outer) }
        }
    }
    /// Cut at double track or a usable passing station. On a ring the
    /// first/last single segments join when stop 0 cannot pass trains.
    func capacityLayout(of line: ServiceLine) -> LineCapacityLayout {
        let n = line.isRing ? line.stops.count : line.stops.count - 1
        guard isTrafficControlEnabled else { return .init(blocks: [], passing: []) }
        let length = (line.trains + line.patterns.flatMap(\.trains)).compactMap { train(id: $0)?.length }.max() ?? 0
        var passing: Set<Int> = []
        for i in line.stops.indices {
            let previous = i > 0 ? i - 1 : line.isRing ? line.stops.count - 1 : 1
            let next = i + 1 < line.stops.count ? i + 1 : line.isRing ? 0 : i - 1
            let berths = berths(of: line.stops[i], length: length)
            func reaches(_ neighbor: Int) -> Set<TrackEdgeID> {
                Set(berths.compactMap { berth -> TrackEdgeID? in
                    let position = TrainPosition.onEdge(berth.traversal, offset: berth.offset)
                    return path(from: position, toStation: line.stops[neighbor], length: length) == nil ? nil : berth.traversal.edge
                })
            }
            let usable = reaches(previous).intersection(reaches(next))
            // Two stop points on the same physical edge cannot pass.
            if usable.count >= 2 { passing.insert(i) }
        }
        var single: [Bool] = []
        // Two disjoint arcs around one physical ring are not two parallel
        // tracks for its opposing laps. Inspect positive physical head spans.
        let sharedRing = line.isRing ? ringSharedCapacitySegments(line) : []
        for i in 0..<n {
            single.append(sharedRing.contains(i) || parallelTracks(between: line.stops[i], and: line.stops[(i + 1) % line.stops.count]) == 1)
        }
        var parent = Array(0..<n)
        func root(_ start: Int) -> Int {
            var i = start
            while parent[i] != i { i = parent[i] }
            return i
        }
        for i in 1..<n where single[i - 1] && single[i] && !passing.contains(i) {
            parent[root(i)] = root(i - 1)
        }
        if line.isRing, single[0], single[n - 1], !passing.contains(0) {
            parent[root(n - 1)] = root(0)
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<n where single[i] { groups[root(i), default: []].append(i) }
        return .init(blocks: groups.values.sorted { $0[0] < $1[0] }, passing: passing)
    }

    private func ringSharedCapacitySegments(_ line: ServiceLine) -> Set<Int> {
        guard let inner = journey(of: line, service: 0),
              let outer = journey(of: line, service: 0, direction: .outer) else {
            // An unknown direction cannot establish paired capacity.
            return Set(line.stops.indices)
        }
        func ranges(_ lap: LineJourney, outer: Bool) -> [Int: [(TrackEdgeID, Int64, Int64)]] {
            var result: [Int: [(TrackEdgeID, Int64, Int64)]] = [:]
            var place = TrainPlacement(position: lap.start, trailEdges: [], length: 0)
            for leg in lap.legs {
                let index = outer ? leg.to : leg.from
                result[index] = trafficStretches(from: place.position, along: leg.path).compactMap { stretch in
                    guard stretch.to > stretch.from else { return nil }
                    let length = network.edge(stretch.traversal.edge)!.length
                    return stretch.traversal.direction == .forward
                        ? (stretch.traversal.edge, stretch.from, stretch.to)
                        : (stretch.traversal.edge, length - stretch.to, length - stretch.from)
                }
                place = placement(place, after: leg.path)
            }
            return result
        }
        let a = ranges(inner, outer: false), b = ranges(outer, outer: true)
        return Set(line.stops.indices.filter { index in
            (a[index] ?? []).contains { x in
                (b[index] ?? []).contains { y in x.0 == y.0 && x.1 < y.2 && y.1 < x.2 }
            }
        })
    }

    /// A leg skipping a possible meet is charged wholly to every block it
    /// crosses: its nominal running curve has no stop there. Dispatcher
    /// waits may recover capacity, but are not assumed in this plan bound.
    func capacityProfile(of line: ServiceLine, service: Int, journey: LineJourney,
                         layout: LineCapacityLayout, outer: LineJourney? = nil) -> ServiceCapacityProfile {
        let n = line.isRing ? line.stops.count : line.stops.count - 1
        var work = Array(repeating: Int64(0), count: n)
        let calls = line.calls(ofService: service)
        func segments(of leg: LineLeg, outer: Bool) -> [Int] {
            if !line.isRing { return Array(min(leg.from, leg.to)..<max(leg.from, leg.to)) }
            if outer { return [(leg.from - 1 + n) % n] }
            return [leg.from]
        }
        func add(_ a: Int64, _ b: Int64) -> Int64 {
            let (value, overflow) = a.addingReportingOverflow(b)
            return overflow ? .max : value
        }
        for block in layout.blocks {
            let set = Set(block)
            var seconds: Int64 = 0
            for call in layout.passing where line.isRing || (calls.first!...calls.last!).contains(call) {
                let touches = line.isRing ? set.contains((call - 1 + n) % n) || set.contains(call % n)
                    : (call > 0 && set.contains(call - 1)) || (call < n && set.contains(call))
                if touches { seconds = add(seconds, 30) } // source meet clearance at a reached passing endpoint
            }
            for leg in journey.legs where segments(of: leg, outer: false).contains(where: set.contains) {
                seconds = add(seconds, leg.seconds)
            }
            if line.isRing {
                if let outer {
                    for leg in outer.legs where segments(of: leg, outer: true).contains(where: set.contains) {
                        seconds = add(seconds, leg.seconds)
                    }
                } else {
                    // An undriveable paired direction cannot provide a ring service.
                    seconds = .max
                }
            }
            for call in calls where !layout.passing.contains(call) {
                let before = (call - 1 + n) % n
                let after = call % n
                let touches = line.isRing ? set.contains(before) || set.contains(after)
                    : (call > 0 && set.contains(call - 1)) || (call < n && set.contains(call))
                guard touches else { continue }
                let terminal = !line.isRing && (call == calls.first || call == calls.last)
                // Once at each terminal; twice at a non-passing intermediate
                // call (or once each way on a ring).
                let dwell = terminal ? ServiceLine.terminalDwellMinutes : 2 * ServiceLine.dwellMinutes
                seconds = add(seconds, dwell * GameTime.secondsPerMinute)
            }
            let crossed = journey.legs.contains { segments(of: $0, outer: false).contains(where: set.contains) }
            guard crossed else { continue }
            for segment in block { work[segment] = seconds }
        }
        let longest = work.max() ?? 0
        let minutes = longest / 60 + (longest % 60 == 0 ? 0 : 1)
        return .init(work: work, minimumHeadway: max(ServiceLine.minimumHeadwayMinutes, minutes), hasSingleTrack: longest > 0)
    }
}
