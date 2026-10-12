import Foundation
import GameCore

// The section flow ("載客量") layer (ARCHITECTURE decision 178), ported from
// the `Ci/` reference's section flow overlay
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
// `metroComputeSectionFlowEdgeLoads` adds every origin-destination pair's
// trips of an hour along the path steps it takes,
// `metroAllocateSectionFlowOnLineLeg` gives a line leg's passengers to each
// stop-to-stop section it runs over (in the direction it runs),
// `metroSectionFlowColor` shades a section by its load against the busiest
// (`pow(ratio, 0.72)`, rgb(227,242,253) to rgb(13,71,161)) and
// `metroBuildSectionFlowTooltipRows` words a tapped section.
//
// The reference shades against the busiest section of the hour; here the
// game has a real capacity (trains an hour × the train's capacity), so a
// section is shaded by its load against its capacity and turns red above
// 100%, which tells the player which section needs another train, faster
// trains or a parallel line. The loads are the world's own passenger plan
// (``GameWorld/plannedPassengerLegFlows()``), read, never worked out again.
//
// Presentation only: worked out off the main thread when the plan or the
// lines change, never stored.

/// The planned passengers of every section of track, each way, in each hour,
/// against what the lines' trains can carry.
public struct SectionFlow: Equatable, Sendable {
    /// A stretch of one track edge, the way the passengers ride it.
    public struct Piece: Hashable, Sendable {
        public let edge: TrackEdgeID
        /// Where it starts and ends along the edge, from the edge's `from`
        /// node (`start < end`).
        public let start: Int64
        public let end: Int64
        /// Whether it is ridden from the edge's `from` node to its `to` node.
        public let forward: Bool
    }

    /// One stop-to-stop section ridden one way (lines over the same track
    /// share it, as the reference's edge loads add up lines).
    public struct Section: Equatable, Sendable {
        public let pieces: [Piece]
        /// The stations it runs from and to.
        public let from: StationID
        public let to: StationID
        /// The lines that run over it, by ID.
        public let lines: [LineID]
        /// Passengers in each hour of the day (24 entries).
        public let loads: [Int64]
        /// Passengers its trains can carry in each hour (24 entries).
        public let capacities: [Int64]

        /// Load against capacity in `hour`: `nil` with no capacity and no
        /// load, a ratio above 1 for any load that runs without trains.
        public func ratio(at hour: Int) -> Double? {
            let hour = SectionFlow.clamped(hour)
            if capacities[hour] > 0 { return Double(loads[hour]) / Double(capacities[hour]) }
            return loads[hour] > 0 ? .infinity : nil
        }
    }

    /// What one section carries in one hour, for the tooltip.
    public struct Reading: Equatable, Sendable {
        public let hour: Int
        public let load: Int64
        public let capacity: Int64
        /// Load as a whole percent of capacity, or `nil` with no capacity.
        public let percent: Int?
    }

    /// One section as the map draws it in one hour.
    public struct Stroke: Equatable, Sendable {
        public let section: Int
        public let pieces: [Piece]
        public let color: PopTravel.RGB
        /// Line width in points, 2 to 10 by the square root of the load.
        public let width: Double
        /// Whether the load is over the capacity (drawn red).
        public let isOverloaded: Bool
    }

    /// Whether the world keeps a passenger plan; without one (before the
    /// first minute of play) nothing is shown.
    public let hasPlan: Bool
    public let sections: [Section]
    /// The largest load of any section in any hour; the widths' scale.
    public let busiest: Int64

    public init(sections: [Section] = [], hasPlan: Bool = false) {
        self.sections = sections
        self.hasPlan = hasPlan
        busiest = sections.lazy.flatMap(\.loads).max() ?? 0
    }

    static func clamped(_ hour: Int) -> Int { min(max(hour, 0), 23) }

    // MARK: - Colour and width

    /// Over this ratio a section is red.
    public static let overloadedColor = PopTravel.RGB(red: 0xD3, green: 0x2F, blue: 0x2F)
    private static let lightest = PopTravel.RGB(red: 227, green: 242, blue: 253)
    private static let darkest = PopTravel.RGB(red: 13, green: 71, blue: 161)

    /// The colour of a section carrying `ratio` of its capacity
    /// (`metroSectionFlowColor`: the ratio to the power .72 between the two
    /// blues), red above 100%.
    public static func color(ratio: Double) -> PopTravel.RGB {
        if ratio > 1 { return overloadedColor }
        let clamped = ratio.isNaN ? 0 : max(0, ratio)
        return PopTravel.mix(lightest, darkest, pow(clamped, 0.72))
    }

    /// The line width, in points, of a section carrying `load` when the
    /// busiest carries `busiest`: 2 to 10 by the square root.
    public static func width(load: Int64, busiest: Int64) -> Double {
        guard load > 0, busiest > 0 else { return 2 }
        return 2 + 8 * (Double(min(load, busiest)) / Double(busiest)).squareRoot()
    }

    // MARK: - Reading

    public func reading(of section: Int, at hour: Int) -> Reading? {
        guard sections.indices.contains(section) else { return nil }
        let hour = Self.clamped(hour)
        let load = sections[section].loads[hour], capacity = sections[section].capacities[hour]
        return Reading(hour: hour, load: load, capacity: capacity,
                       percent: capacity > 0 ? Int((load * 100 + capacity / 2) / capacity) : nil)
    }

    /// The sections to draw in `hour`, lightest first so the heavy ones lie
    /// on top; a section with nothing to carry and no trains is left out.
    public func strokes(at hour: Int) -> [Stroke] {
        let hour = Self.clamped(hour)
        var strokes: [(ratio: Double, load: Int64, stroke: Stroke)] = []
        for (index, section) in sections.enumerated() {
            guard let ratio = section.ratio(at: hour) else { continue }
            let load = section.loads[hour]
            strokes.append((ratio, load, Stroke(
                section: index, pieces: section.pieces, color: Self.color(ratio: ratio),
                width: Self.width(load: load, busiest: busiest), isOverloaded: ratio > 1)))
        }
        strokes.sort { ($0.ratio, $0.load) < ($1.ratio, $1.load) }
        return strokes.map(\.stroke)
    }

    /// The text of a tapped section (`metroBuildSectionFlowTooltipRows`):
    /// "08:00–09:00 往 X：3,240 人／運能 2,800（116%）· 紅線、藍線".
    public func tooltip(of section: Int, at hour: Int, world: GameWorld, language: DisplayLanguage) -> String? {
        guard let reading = reading(of: section, at: hour) else { return nil }
        let section = sections[section]
        let name = world.station(id: section.to)?.name ?? ""
        let start = Self.hourText(reading.hour), end = Self.hourText((reading.hour + 1) % 24)
        let load = Money(reading.load).displayText
        let capacity = reading.capacity > 0 ? Money(reading.capacity).displayText : language.text("none", "無")
        let percent = reading.percent.map { "（\($0)%）" } ?? ""
        let lines = section.lines.compactMap { world.line(id: $0)?.name }.joined(separator: language.text(", ", "、"))
        let body = language.text(
            "\(start)–\(end) to \(name): \(load) riders / capacity \(capacity)\(percent)",
            "\(start)–\(end) 往 \(name)：\(load) 人／運能 \(capacity)\(percent)"
        )
        return lines.isEmpty ? body : body + " · " + lines
    }

    static func hourText(_ hour: Int) -> String {
        (hour < 10 ? "0" : "") + String(hour) + ":00"
    }

    // MARK: - Picking

    /// The section nearest the world point `(x, y)` that has something to
    /// show in `hour`, within `maximum` world units, or `nil`
    /// (`metroPickNearestSectionFlowAtLatLng`).
    public func nearestSection(toX x: Int64, y: Int64, at hour: Int, within maximum: Double, in world: GameWorld) -> Int? {
        var geometry: [TrackEdgeID: TrackGeometry?] = [:]
        var best: (index: Int, distance: Double)?
        for stroke in strokes(at: hour) {
            for piece in stroke.pieces {
                if geometry[piece.edge] == nil { geometry[piece.edge] = .some(world.trackGeometry(of: piece.edge)) }
                guard let track = geometry[piece.edge] ?? nil else { continue }
                let end = min(piece.end, track.length)
                guard piece.start < end else { continue }
                let points = track.points(from: piece.start, to: end)
                let distance = Self.distance(fromX: Double(x), y: Double(y), toPolyline: points)
                if distance <= maximum, distance < (best?.distance ?? .infinity) {
                    best = (stroke.section, distance)
                }
            }
        }
        return best?.index
    }

    private static func distance(fromX px: Double, y py: Double, toPolyline points: [WorldCoordinate]) -> Double {
        var nearest = Double.infinity
        for (a, b) in zip(points, points.dropFirst()) {
            let ax = Double(a.x), ay = Double(a.y), dx = Double(b.x) - ax, dy = Double(b.y) - ay
            let squared = dx * dx + dy * dy
            let t = squared == 0 ? 0 : min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / squared))
            let ex = px - (ax + t * dx), ey = py - (ay + t * dy)
            nearest = min(nearest, (ex * ex + ey * ey).squareRoot())
        }
        if points.count == 1, let only = points.first {
            nearest = ((px - Double(only.x)) * (px - Double(only.x)) + (py - Double(only.y)) * (py - Double(only.y))).squareRoot()
        }
        return nearest
    }
}

// MARK: - From the world

extension SectionFlow {
    /// The section flow of `world`'s kept passenger plan: no sections, and
    /// `hasPlan` false, when it keeps none.
    ///
    /// Each line's flows are given to the stop-to-stop sections the leg
    /// runs over (`metroAllocateSectionFlowOnLineLeg`); each section is
    /// the track its line's own round trip drives between the two stops
    /// (``GameWorld/lineJourney(_:pattern:)``), so lines over the same track
    /// add up. A line's capacity in an hour is, for every service that runs
    /// the section (its own and its patterns'), the trains an hour at the
    /// service level then (``GameWorld/lineHeadway(_:at:pattern:)``) times
    /// the train's capacity (the average of the service's trains).
    ///
    /// Costs a journey and a few headways a line: run it off the main thread.
    public init(world: GameWorld) {
        guard let flows = world.plannedPassengerLegFlows() else {
            self.init()
            return
        }
        var byLine: [LineID: [PassengerLegFlow]] = [:]
        for flow in flows { byLine[flow.line, default: []].append(flow) }

        struct Accumulator {
            var from: StationID
            var to: StationID
            var lines: Set<LineID> = []
            var loads = Array(repeating: Int64(0), count: 24)
            var capacities = Array(repeating: Int64(0), count: 24)
        }
        var merged: [[Piece]: Accumulator] = [:]
        var order: [[Piece]] = []

        for line in world.lines where byLine[line.id] != nil {
            guard let journey = world.lineJourney(line.id) else { continue }
            let stopCount = line.stops.count
            guard stopCount >= 2 else { continue }
            let segmentCount = line.isRing ? stopCount : stopCount - 1
            let legPieces = Self.piecesByLeg(of: journey, in: world.network)

            // The pieces of segment k ridden each way.
            var pieces: [LineDirection: [Int: [Piece]]] = [.outbound: [:], .inbound: [:]]
            for (index, leg) in journey.legs.enumerated() {
                let outbound = line.isRing || leg.from < leg.to
                let segment: Int
                if line.isRing { segment = leg.from } else { segment = min(leg.from, leg.to) }
                guard line.isRing ? true : abs(leg.from - leg.to) == 1 else { continue }
                pieces[outbound ? .outbound : .inbound]![segment] = legPieces[index]
            }
            // A ring has one lap: riders of the other way use the same track.
            if line.isRing { pieces[.inbound] = pieces[.outbound] }

            // Loads.
            var loads: [LineDirection: [Int: [Int64]]] = [.outbound: [:], .inbound: [:]]
            for flow in byLine[line.id] ?? [] {
                for segment in Self.segments(of: line, from: flow.from, to: flow.to, direction: flow.direction) {
                    var hours = loads[flow.direction]![segment] ?? Array(repeating: 0, count: 24)
                    for hour in 0..<24 { hours[hour] += flow.hourly[hour] }
                    loads[flow.direction]![segment] = hours
                }
            }

            let capacity = Self.capacities(of: line, in: world, segmentCount: segmentCount)
            for direction in LineDirection.allCases {
                for segment in 0..<segmentCount {
                    guard let track = pieces[direction]?[segment], !track.isEmpty else { continue }
                    let ends = Self.stations(of: line, segment: segment, direction: direction)
                    var entry = merged[track] ?? Accumulator(from: ends.from, to: ends.to)
                    if merged[track] == nil { order.append(track) }
                    entry.lines.insert(line.id)
                    if let hours = loads[direction]?[segment] {
                        for hour in 0..<24 { entry.loads[hour] += hours[hour] }
                    }
                    for hour in 0..<24 { entry.capacities[hour] += capacity[segment][hour] }
                    merged[track] = entry
                }
            }
        }

        self.init(sections: order.map { track in
            let entry = merged[track]!
            return Section(pieces: track, from: entry.from, to: entry.to, lines: entry.lines.sorted(),
                           loads: entry.loads, capacities: entry.capacities)
        }, hasPlan: true)
    }

    /// The stations segment `segment` of `line` runs from and to, riding
    /// `direction`.
    static func stations(of line: ServiceLine, segment: Int, direction: LineDirection) -> (from: StationID, to: StationID) {
        let next = (segment + 1) % line.stops.count
        let a = line.stops[segment], b = line.stops[next]
        return direction == .outbound ? (a, b) : (b, a)
    }

    /// The segments (segment `k` runs from stop `k` to stop `k + 1`, on a
    /// ring the last back to stop 0) a leg from station `from` to `to`
    /// riding `direction` runs over; none when the stations are not the
    /// line's stops in that order. Where a station is a stop twice, the
    /// nearest pair.
    static func segments(of line: ServiceLine, from: StationID, to: StationID, direction: LineDirection) -> [Int] {
        let stops = line.stops, count = stops.count
        let starts = stops.indices.filter { stops[$0] == from }
        let ends = stops.indices.filter { stops[$0] == to }
        var best: [Int]?
        for i in starts {
            for j in ends where i != j {
                var run: [Int] = []
                if line.isRing {
                    var k = i
                    if direction == .outbound {
                        while k != j { run.append(k); k = (k + 1) % count }
                    } else {
                        while k != j { k = (k - 1 + count) % count; run.append(k) }
                    }
                } else if direction == .outbound, i < j {
                    run = Array(i..<j)
                } else if direction == .inbound, i > j {
                    run = Array(j..<i)
                } else {
                    continue
                }
                if best == nil || run.count < best!.count { best = run }
            }
        }
        return best ?? []
    }

    /// Passengers each segment's trains can carry in each hour.
    static func capacities(of line: ServiceLine, in world: GameWorld, segmentCount: Int) -> [[Int64]] {
        var result = Array(repeating: Array(repeating: Int64(0), count: 24), count: segmentCount)
        // Services: the line's own, then each pattern.
        var services: [(pattern: Int?, trains: [TrainID], covers: ClosedRange<Int>)] = [(nil, line.trains, 0...max(0, segmentCount - 1))]
        for (index, pattern) in line.patterns.enumerated() {
            guard let first = pattern.calls.min(), let last = pattern.calls.max(), first < last else { continue }
            services.append((index, pattern.trains, first...(last - 1)))
        }
        // A level's headway is the same all day: work out three, not 24.
        let levels = ServiceLevel.allCases
        for service in services {
            let capacities = service.trains.compactMap { world.train(id: $0)?.capacity }
            guard !capacities.isEmpty else { continue }
            let perTrain = capacities.reduce(0, +) / Int64(capacities.count)
            var perHour: [ServiceLevel: Int64] = [:]
            for level in levels {
                if let headway = world.lineHeadway(line.id, at: level, pattern: service.pattern), headway > 0 {
                    perHour[level] = 60 * perTrain / headway
                }
            }
            for hour in 0..<24 {
                guard let level = world.serviceLevel(of: line.id, at: GameTime(seconds: Int64(hour) * 3600 + 1800)),
                      let carried = perHour[level] else { continue }
                for segment in service.covers where segment < segmentCount { result[segment][hour] += carried }
            }
        }
        return result
    }

    /// The pieces of track each leg of `journey` drives, by leg index, as
    /// ``LineMap`` works them out for the line's colour (the same walk of
    /// the legs' paths), here kept apart by leg.
    static func piecesByLeg(of journey: LineJourney, in network: RailwayNetwork) -> [[Piece]] {
        guard case .onEdge(var traversal, var offset) = journey.start else { return journey.legs.map { _ in [] } }
        func length(_ traversal: TrackTraversal) -> Int64 { network.edge(traversal.edge)?.length ?? 0 }
        func node(_ traversal: TrackTraversal, atEnd: Bool) -> TrackNodeID? {
            guard let edge = network.edge(traversal.edge) else { return nil }
            return (traversal.direction == .forward) == atEnd ? edge.to : edge.from
        }
        var result: [[Piece]] = []
        for leg in journey.legs {
            var pieces: [Piece] = []
            func add(_ traversal: TrackTraversal, _ a: Int64, _ b: Int64) {
                guard a != b else { return }
                let low = min(a, b), high = max(a, b)
                let size = length(traversal)
                let (from, to) = traversal.direction == .forward ? (low, high) : (size - low, size - high)
                // A leg with no further edge can run back along the edge it
                // stands on (a terminus's return trip): the piece's way is
                // the way it is driven, not the traversal's.
                let drivenForward = (traversal.direction == .forward) == (a < b)
                pieces.append(Piece(edge: traversal.edge, start: min(from, to), end: max(from, to), forward: drivenForward))
            }
            if let first = leg.path.traversals.first, node(first, atEnd: false) != node(traversal, atEnd: true) {
                offset = length(traversal) - offset
                traversal = traversal.reversed
            }
            if let last = leg.path.traversals.last {
                add(traversal, offset, length(traversal))
                for between in leg.path.traversals.dropLast() { add(between, 0, length(between)) }
                let end = leg.path.end ?? length(last)
                add(last, 0, end)
                traversal = last
                offset = end
            } else {
                let end = leg.path.end ?? length(traversal)
                add(traversal, offset, end)
                offset = end
            }
            result.append(pieces)
        }
        return result
    }
}
