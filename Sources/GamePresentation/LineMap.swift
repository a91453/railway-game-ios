import GameCore

// What the map draws of the lines and transfer groups (ARCHITECTURE
// decision 84), ported from MapBuilder's map
// (`MapBuilder/reference_snapshot/_next/static/chunks/352-*.js`, layers
// `js-Map-segments--solid` and `js-Map-interchanges--*`, with the
// interline segments and their offsets built in `pages/_app-*.js`).
// MapBuilder draws a line straight from station to station; a line here
// runs on the track, so it is drawn along the track its trains take.

/// The lines as the map draws them (decision 84): each line along the
/// track its trains take, side by side where lines share track (MapBuilder's
/// interline segments), and each transfer group as a link through its
/// stations (MapBuilder's interchanges). Derived from the world, never
/// saved.
public struct LineMap: Equatable, Sendable {
    /// A stretch of one edge that one line runs along.
    public struct Stretch: Equatable, Sendable {
        public let line: LineID
        /// The colour the player chose for the line, or `nil` (see
        /// ``ServiceLine/color``).
        public let color: LineColor?
        /// Whether the line is a high-speed line (decision 168): the map
        /// draws it differently.
        public let isHighSpeed: Bool
        public let edge: TrackEdgeID
        /// Where the stretch starts and ends along the edge, from its
        /// `from` node: `0 <= start < end <=` the edge's length.
        public let start: Int64
        public let end: Int64
        /// How far beside the track the line is drawn, in line widths, to
        /// the left of the way the edge goes from its `from` node to its
        /// `to` node: 0 on the track, and a negative number to the right
        /// (MapBuilder's `offsets`, in its 8 px line widths).
        public let offset: Double
        /// Which way the line's trains run along it (decision 201): the map
        /// draws arrows on a stretch ridden one way only, so a double line
        /// shows which track each way takes.
        public let way: Way

        public init(
            line: LineID, color: LineColor?, isHighSpeed: Bool = false, edge: TrackEdgeID, start: Int64, end: Int64, offset: Double,
            way: Way = .both
        ) {
            self.line = line
            self.color = color
            self.isHighSpeed = isHighSpeed
            self.edge = edge
            self.start = start
            self.end = end
            self.offset = offset
            self.way = way
        }
    }

    /// Which way a line's trains run along a stretch of an edge (decision
    /// 201), as the edge goes from its `from` node to its `to` node.
    public enum Way: Hashable, Sendable {
        /// From the edge's `from` node towards its `to` node only.
        case forward
        /// From its `to` node towards its `from` node only.
        case backward
        /// Both ways: out and back on the same track.
        case both
    }

    /// Every line's stretches, by edge, then line, then start.
    public let stretches: [Stretch]
    /// Each transfer group's stations, where they stand, in the group's
    /// order: MapBuilder links an interchange's stations in its order.
    public let transfers: [[PlanPoint]]

    public init(stretches: [Stretch] = [], transfers: [[PlanPoint]] = []) {
        self.stretches = stretches
        self.transfers = transfers
    }

    /// The map of `world`'s lines and transfer groups.
    ///
    /// A line runs along the track its own service's round trip takes
    /// (``GameWorld/lineJourney(_:pattern:)``; a ring's lap), from its
    /// first call's berth to where it comes back, and since decision 201
    /// along its patterns' round trips too, each with its own physical
    /// paths. A stretch ridden one way only says which way
    /// (``Stretch/way``), except in a platform of a station the line calls
    /// at, where a train turns round. Where lines share a stretch
    /// of track, the lines over it are ordered by ID and drawn side by side,
    /// as MapBuilder offsets the lines of an interline segment. A line whose
    /// journey cannot be driven is not drawn.
    ///
    /// Costs one ``GameWorld/lineJourney(_:pattern:)`` a service.
    public init(world: GameWorld) {
        var ranges: [TrackEdgeID: [LineID: [ClosedRange<Int64>]]] = [:]
        // The same, each way the edge is driven: `true` forward.
        var driven: [TrackEdgeID: [LineID: [Bool: [ClosedRange<Int64>]]]] = [:]
        // Where the line's trains turn round: its stations' platforms.
        var turns: [LineID: Set<StationID>] = [:]
        var colors: [LineID: LineColor?] = [:]
        var fast = Set<LineID>()
        for line in world.lines {
            guard let journey = world.lineJourney(line.id) else { continue }
            colors[line.id] = line.color
            turns[line.id] = Set(line.stops)
            if line.isHighSpeed { fast.insert(line.id) }
            let patterns = line.patterns.indices.compactMap { world.lineJourney(line.id, pattern: $0) }
            for journey in [journey] + patterns {
                for (traversal, a, b) in Self.pieces(of: journey, in: world.network) {
                    let length = world.network.edge(traversal.edge)?.length ?? 0
                    let forward = traversal.direction == .forward
                    let range = forward ? a...b : (length - b)...(length - a)
                    ranges[traversal.edge, default: [:]][line.id, default: []].append(range)
                    driven[traversal.edge, default: [:]][line.id, default: [:]][forward, default: []].append(range)
                }
            }
        }
        let platforms = Dictionary(grouping: world.network.platforms, by: \.edge)
        var stretches: [Stretch] = []
        for edge in ranges.keys.sorted() {
            guard let lines = ranges[edge] else { continue }
            let merged = lines.mapValues(Self.merged)
            let ways = (driven[edge] ?? [:]).mapValues { $0.mapValues(Self.merged) }
            // Where the lines over the edge change, the offsets do; where
            // the way a line runs changes, its arrows do.
            let cuts = Set(
                merged.values.flatMap { $0.flatMap { [$0.lowerBound, $0.upperBound] } }
                    + ways.values.flatMap { $0.values.flatMap { $0.flatMap { [$0.lowerBound, $0.upperBound] } } }
            ).sorted()
            var open: [LineID: Stretch] = [:]
            var done: [Stretch] = []
            for (start, end) in zip(cuts, cuts.dropFirst()) {
                let over = merged.filter { $0.value.contains { $0.lowerBound <= start && end <= $0.upperBound } }.keys.sorted()
                let offsets = Self.offsets(count: over.count)
                for (line, offset) in zip(over, offsets) {
                    func runs(_ forward: Bool) -> Bool {
                        ways[line]?[forward]?.contains { $0.lowerBound <= start && end <= $0.upperBound } ?? false
                    }
                    let turning = platforms[edge]?.contains {
                        turns[line]?.contains($0.station) == true && $0.start <= start && end <= $0.end
                    } ?? false
                    let way: Way = turning || runs(true) == runs(false) ? .both : runs(true) ? .forward : .backward
                    if let last = open[line], last.end == start, last.offset == offset, last.way == way {
                        open[line] = Stretch(
                            line: line, color: last.color, isHighSpeed: last.isHighSpeed, edge: edge, start: last.start, end: end, offset: offset,
                            way: way
                        )
                    } else {
                        if let last = open[line] { done.append(last) }
                        open[line] = Stretch(
                            line: line, color: colors[line] ?? nil, isHighSpeed: fast.contains(line), edge: edge, start: start, end: end, offset: offset,
                            way: way
                        )
                    }
                }
            }
            done.append(contentsOf: open.values)
            stretches += done.sorted { ($0.line, $0.start) < ($1.line, $1.start) }
        }
        self.stretches = stretches
        self.transfers = world.transferGroups.map { group in
            group.stations.compactMap { world.station(id: $0)?.location }
        }.filter { $0.count > 1 }
    }

    /// The offsets of `count` lines side by side, in line widths, in their
    /// order: MapBuilder's `offsets`, which puts an odd number's first line
    /// on the track and the rest out either side in turn (0, −1, 1, −2, 2,
    /// …), and an even number's half a width out either side (0.5, −0.5,
    /// 1.5, −1.5, …), so they touch and none overlap.
    public static func offsets(count: Int) -> [Double] {
        (0..<max(0, count)).map { index in
            let distance = count % 2 == 1 ? Double((index + 1) / 2) : 0.5 + Double(index / 2)
            return index % 2 == 0 ? distance : -distance
        }
    }

    /// The pieces of track `journey` drives, in order: each the way it is
    /// driven along an edge, and where on it the piece starts and ends,
    /// measured along that way (`a < b`). A leg that leaves from the other
    /// end of the edge it reached turned round there.
    static func pieces(of journey: LineJourney, in network: RailwayNetwork) -> [(TrackTraversal, Int64, Int64)] {
        legPieces(of: journey, in: network).flatMap(\.self)
    }

    /// ``pieces(of:in:)`` leg by leg: element `i` is what leg `i` of
    /// `journey` drives (decision 201's preview of one leg).
    static func legPieces(of journey: LineJourney, in network: RailwayNetwork) -> [[(TrackTraversal, Int64, Int64)]] {
        guard case .onEdge(var traversal, var offset) = journey.start else { return [] }
        var legs: [[(TrackTraversal, Int64, Int64)]] = []
        var pieces: [(TrackTraversal, Int64, Int64)] = []
        func length(_ traversal: TrackTraversal) -> Int64 { network.edge(traversal.edge)?.length ?? 0 }
        func add(_ traversal: TrackTraversal, _ a: Int64, _ b: Int64) {
            if a != b { pieces.append((traversal, min(a, b), max(a, b))) }
        }
        func node(_ traversal: TrackTraversal, atEnd: Bool) -> TrackNodeID? {
            guard let edge = network.edge(traversal.edge) else { return nil }
            return (traversal.direction == .forward) == atEnd ? edge.to : edge.from
        }
        for (index, leg) in journey.legs.enumerated() {
            if index > 0 {
                legs.append(pieces)
                pieces = []
            }
            // A leg that leaves from the other end of the edge turned round
            // where the last one stopped.
            if let first = leg.path.traversals.first, node(first, atEnd: false) != node(traversal, atEnd: true) {
                offset = length(traversal) - offset
                traversal = traversal.reversed
            }
            guard let last = leg.path.traversals.last else {
                let end = leg.path.end ?? length(traversal)
                add(traversal, offset, end)
                offset = end
                continue
            }
            add(traversal, offset, length(traversal))
            for between in leg.path.traversals.dropLast() {
                add(between, 0, length(between))
            }
            let end = leg.path.end ?? length(last)
            add(last, 0, end)
            traversal = last
            offset = end
        }
        if !journey.legs.isEmpty { legs.append(pieces) }
        return legs
    }

    /// `ranges` joined where they meet or overlap, in order.
    static func merged(_ ranges: [ClosedRange<Int64>]) -> [ClosedRange<Int64>] {
        var merged: [ClosedRange<Int64>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
