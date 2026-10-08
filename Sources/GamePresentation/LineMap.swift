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

        public init(line: LineID, color: LineColor?, edge: TrackEdgeID, start: Int64, end: Int64, offset: Double) {
            self.line = line
            self.color = color
            self.edge = edge
            self.start = start
            self.end = end
            self.offset = offset
        }
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
    /// first call's berth to where it comes back. Where lines share a stretch
    /// of track, the lines over it are ordered by ID and drawn side by side,
    /// as MapBuilder offsets the lines of an interline segment. A line whose
    /// journey cannot be driven is not drawn.
    ///
    /// Costs one ``GameWorld/lineJourney(_:pattern:)`` a line.
    public init(world: GameWorld) {
        var ranges: [TrackEdgeID: [LineID: [ClosedRange<Int64>]]] = [:]
        var colors: [LineID: LineColor?] = [:]
        for line in world.lines {
            guard let journey = world.lineJourney(line.id) else { continue }
            colors[line.id] = line.color
            for (edge, range) in Self.ranges(of: journey, in: world.network) {
                ranges[edge, default: [:]][line.id, default: []].append(range)
            }
        }
        var stretches: [Stretch] = []
        for edge in ranges.keys.sorted() {
            guard let lines = ranges[edge] else { continue }
            let merged = lines.mapValues(Self.merged)
            // Where the lines over the edge change, the offsets do.
            let cuts = Set(merged.values.flatMap { $0.flatMap { [$0.lowerBound, $0.upperBound] } }).sorted()
            var open: [LineID: Stretch] = [:]
            var done: [Stretch] = []
            for (start, end) in zip(cuts, cuts.dropFirst()) {
                let over = merged.filter { $0.value.contains { $0.lowerBound <= start && end <= $0.upperBound } }.keys.sorted()
                let offsets = Self.offsets(count: over.count)
                for (line, offset) in zip(over, offsets) {
                    if let last = open[line], last.end == start, last.offset == offset {
                        open[line] = Stretch(line: line, color: last.color, edge: edge, start: last.start, end: end, offset: offset)
                    } else {
                        if let last = open[line] { done.append(last) }
                        open[line] = Stretch(line: line, color: colors[line] ?? nil, edge: edge, start: start, end: end, offset: offset)
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

    /// The stretches of each edge `journey` runs along, from the edge's
    /// `from` node, in the order it drives them.
    static func ranges(of journey: LineJourney, in network: RailwayNetwork) -> [(TrackEdgeID, ClosedRange<Int64>)] {
        guard case .onEdge(var traversal, var offset) = journey.start else { return [] }
        var ranges: [(TrackEdgeID, ClosedRange<Int64>)] = []
        func length(_ traversal: TrackTraversal) -> Int64 { network.edge(traversal.edge)?.length ?? 0 }
        func add(_ traversal: TrackTraversal, _ a: Int64, _ b: Int64) {
            let length = length(traversal)
            let (from, to) = traversal.direction == .forward ? (a, b) : (length - a, length - b)
            if from != to { ranges.append((traversal.edge, min(from, to)...max(from, to))) }
        }
        func node(_ traversal: TrackTraversal, atEnd: Bool) -> TrackNodeID? {
            guard let edge = network.edge(traversal.edge) else { return nil }
            return (traversal.direction == .forward) == atEnd ? edge.to : edge.from
        }
        for leg in journey.legs {
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
        return ranges
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
