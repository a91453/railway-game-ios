import GameCore

/// The track networks the kernel's campaign family generates (Stage F3b,
/// ARCHITECTURE decision 51), in place of the grid's ``NetworkShape``s:
/// nodes at tile centres (`1024 x + 512`, `1024 y + 512`), straight edges
/// of 1024 along rows and columns, and curves where the grid turned. Each
/// shape keeps what its grid shape was for (see ``Shape``); the network's
/// own rules decide the rest: edges join at a node only when they leave it
/// in opposite ways within 1 in 16, so a corner is a curve and a junction
/// is a turnout whose branches leave the same way.
///
/// Stations stand at points. Most stand beside a node, with a platform on
/// the half tile of each edge at that node (as `TestLine` does), so a train
/// stops at the node going either way; some have none.
struct KernelNetwork: Equatable {
    enum Shape: CaseIterable {
        /// One straight line, east or south, dead ends at both ends; now
        /// and then an edge two or three tiles long, where a longer train
        /// fits a platform.
        case line
        /// A loop of two straight sides and curved ends, with tails leaving
        /// its corners at turnouts.
        case loopWithTails
        /// Two parallel lines joined by S-shaped rungs at turnouts:
        /// alternatives of equal length.
        case ladder
        /// Lines that cross at shared nodes without joining there, as level
        /// crossings: many nodes a train passes straight over.
        case crossings
        /// Two lines that never meet.
        case twoLines
        /// A line with a balloon loop at each end, both branches of each
        /// loop leaving the line's last node the same way: a train turns
        /// round by going round a loop, so it can reach every station
        /// either way, as on the grid's loops.
        case balloons
    }

    struct Edge: Equatable {
        var from: Int
        var to: Int
        var curve: TrackCurve
    }

    struct Platform: Equatable {
        enum Stretch: Equatable {
            /// The first half of the edge, at most two tiles: half a tile
            /// on an edge a tile long, room for two cars on one of four.
            case first
            /// The last half of the edge, at most two tiles.
            case last
            case whole
        }

        /// The edge's index in ``KernelNetwork/edges``.
        var edge: Int
        var stretch: Stretch

        /// Where it starts and ends along an edge `length` long.
        func span(length: Int64) -> (start: Int64, end: Int64) {
            let half = min(length / 2, 2 * KernelNetwork.tile)
            return switch stretch {
            case .first: (0, half)
            case .last: (length - half, length)
            case .whole: (0, length)
            }
        }
    }

    struct StationSpec: Equatable {
        var name: String
        var point: PlanPoint
        var platforms: [Platform]
    }

    var width: Int
    var height: Int
    var nodes: [WorldCoordinate]
    var edges: [Edge]
    var stations: [StationSpec]

    static let tile = WorldCoordinate.tileSize

    static func centre(_ x: Int, _ y: Int) -> WorldCoordinate {
        WorldCoordinate(x: Int64(x) * tile + tile / 2, y: Int64(y) * tile + tile / 2)
    }

    /// The handle of a quarter turn of radius 1024: the curve stays within
    /// the square its ends span, so a straight edge beside it at a turnout
    /// never crosses it.
    static let quarter: Int64 = 563

    /// A network of `shape`, drawn with `random`.
    static func generate(_ shape: Shape, using random: inout SplitMix64) -> KernelNetwork {
        var network = KernelNetwork(width: 0, height: 0, nodes: [], edges: [], stations: [])
        switch shape {
        case .line:
            let count = 3 + random.below(7)
            let vertical = random.chance(1, in: 2)
            var along = [0]
            while along.count < count {
                along.append(along[along.count - 1] + (random.chance(1, in: 3) ? 2 + random.below(2) : 1))
            }
            let length = along[along.count - 1] + 1
            network.width = vertical ? 3 : length
            network.height = vertical ? length : 3
            network.line(along.map { vertical ? (1, $0) : ($0, 1) })
        case .loopWithTails:
            // Straight sides on rows 1 and 3 from column 3 to `east`, a
            // curved end at each side through the nodes on row 2.
            let west = 3
            let east = west + 1 + random.below(3)
            network.width = east + 4
            network.height = 5
            network.line((west...east).map { ($0, 1) })
            network.line((west...east).reversed().map { ($0, 3) })
            let topEast = network.index(east, 1)
            let bottomEast = network.index(east, 3)
            let topWest = network.index(west, 1)
            let bottomWest = network.index(west, 3)
            let eastEnd = network.add(east + 1, 2)
            let westEnd = network.add(west - 1, 2)
            network.curve(from: topEast, to: eastEnd, leaving: (1, 0), arriving: (0, 1))
            network.curve(from: eastEnd, to: bottomEast, leaving: (0, 1), arriving: (-1, 0))
            network.curve(from: bottomWest, to: westEnd, leaving: (-1, 0), arriving: (0, -1))
            network.curve(from: westEnd, to: topWest, leaving: (0, -1), arriving: (1, 0))
            // Tails on along the sides past the corners, which leave the
            // corner nodes the way the curves do: turnouts.
            for (x, y, step) in [(east, 1, 1), (east, 3, 1), (west, 1, -1), (west, 3, -1)] where random.chance(1, in: 2) {
                let length = 1 + random.below(2)
                network.line((0...length).map { (x + step * $0, y) })
            }
        case .ladder:
            let length = 4 + random.below(5)
            network.width = length
            network.height = 5
            network.line((0..<length).map { ($0, 1) })
            network.line((0..<length).map { ($0, 3) })
            // Rungs from the upper line down to the lower, two columns on,
            // all the same way so that none crosses another.
            var columns = Array(0..<(length - 2))
            for _ in 0..<(1 + random.below(3)) where !columns.isEmpty {
                let x = random.element(of: columns)
                columns.removeAll { $0 == x }
                network.curve(from: network.index(x, 1), to: network.index(x + 2, 3), leaving: (1, 0), arriving: (1, 0), handle: tile)
            }
        case .crossings:
            // A line along row 2 crossed by one or two lines down columns.
            let length = 5 + random.below(3)
            network.width = length
            network.height = 5
            network.line((0..<length).map { ($0, 2) })
            var columns = Array(1..<(length - 1))
            for _ in 0..<(1 + random.below(2)) {
                let x = random.element(of: columns)
                columns.removeAll { abs($0 - x) < 2 }
                network.line((0..<5).map { (x, $0) })
                if columns.isEmpty { break }
            }
        case .twoLines:
            let upper = 2 + random.below(5)
            let lower = 2 + random.below(5)
            network.width = max(upper, lower)
            network.height = 5
            network.line((0..<upper).map { ($0, 1) })
            network.line((0..<lower).map { ($0, 3) })
        case .balloons:
            // The line along row 2 from column 4 to `east`, its edges two
            // tiles long (a platform at a node holds two cars), a loop
            // beyond each end.
            let west = 4
            let east = west + 2 * (1 + random.below(3))
            network.width = east + 5
            network.height = 5
            network.line(stride(from: west, through: east, by: 2).map { ($0, 2) })
            network.balloon(at: east, step: 1)
            network.balloon(at: west, step: -1)
        }
        network.addStations(using: &random)
        return network
    }

    // MARK: - Building the layout

    func index(_ x: Int, _ y: Int) -> Int {
        nodes.firstIndex(of: Self.centre(x, y))!
    }

    /// The node at the centre of tile (`x`, `y`), added if there is none.
    @discardableResult
    mutating func add(_ x: Int, _ y: Int) -> Int {
        let point = Self.centre(x, y)
        if let existing = nodes.firstIndex(of: point) { return existing }
        nodes.append(point)
        return nodes.count - 1
    }

    /// Nodes at `tiles` in order, each joined to the one before by a
    /// straight edge.
    mutating func line(_ tiles: [(Int, Int)]) {
        var previous: Int?
        for (x, y) in tiles {
            let node = add(x, y)
            if let previous { edges.append(Edge(from: previous, to: node, curve: .straight)) }
            previous = node
        }
    }

    /// A loop beyond the line's end at column `x` of row 2, on the side
    /// `step` points to: an S-curve out to row 1, a tile of straight, a
    /// curved end through row 2, a tile back along row 3 and an S-curve
    /// back to the line's end, which both S-curves leave the same way.
    mutating func balloon(at x: Int, step: Int) {
        let end = index(x, 2)
        let way = Int64(step)
        let upperNear = add(x + 2 * step, 1)
        curve(from: end, to: upperNear, leaving: (way, 0), arriving: (way, 0), handle: Self.tile)
        line([(x + 2 * step, 1), (x + 3 * step, 1)])
        let upperFar = index(x + 3 * step, 1)
        let tip = add(x + 4 * step, 2)
        curve(from: upperFar, to: tip, leaving: (way, 0), arriving: (0, 1))
        let lowerFar = add(x + 3 * step, 3)
        curve(from: tip, to: lowerFar, leaving: (0, 1), arriving: (-way, 0))
        line([(x + 3 * step, 3), (x + 2 * step, 3)])
        curve(from: index(x + 2 * step, 3), to: end, leaving: (-way, 0), arriving: (-way, 0), handle: Self.tile)
    }

    /// A cubic edge from node `from` to node `to`, leaving the first and
    /// arriving at the second along the given ways.
    mutating func curve(from: Int, to: Int, leaving: (Int64, Int64), arriving: (Int64, Int64), handle: Int64 = quarter) {
        let a = nodes[from].plan
        let b = nodes[to].plan
        edges.append(Edge(
            from: from, to: to,
            curve: .cubic(PlanPoint(x: a.x + leaving.0 * handle, y: a.y + leaving.1 * handle), PlanPoint(x: b.x - arriving.0 * handle, y: b.y - arriving.1 * handle))
        ))
    }

    /// Stations beside about half of the nodes, each with a platform on
    /// the half of every edge at its node nearest it (see
    /// ``Platform/Stretch``; the whole edge now and then, or none at all),
    /// standing a tile off the node; and now and then one away from the
    /// track.
    mutating func addStations(using random: inout SplitMix64) {
        for (index, node) in nodes.enumerated() where random.chance(1, in: 2) {
            let x = Int(node.x / Self.tile)
            let y = Int(node.y / Self.tile)
            let beside = y >= 1 ? (x, y - 1) : (x, y + 1)
            var platforms: [Platform] = []
            if !random.chance(1, in: 8) {
                for (number, edge) in edges.enumerated() where edge.from == index || edge.to == index {
                    // Platforms of two stations never overlap: an edge with
                    // a whole platform has no other, and the halves at its
                    // two ends at most touch.
                    let taken = stations.flatMap(\.platforms).filter { $0.edge == number }
                    guard !taken.contains(where: { $0.stretch == .whole }) else { continue }
                    if taken.isEmpty, random.chance(1, in: 6) {
                        platforms.append(Platform(edge: number, stretch: .whole))
                    } else {
                        platforms.append(Platform(edge: number, stretch: edge.from == index ? .first : .last))
                    }
                }
            }
            stations.append(StationSpec(name: "S\(stations.count + 1)", point: Self.centre(beside.0, beside.1).plan, platforms: platforms))
        }
        if random.chance(1, in: 4) {
            let point = Self.centre(random.below(width), random.below(height)).plan
            stations.append(StationSpec(name: "S\(stations.count + 1)", point: point, platforms: []))
        }
    }
}

// MARK: - Where trains stand

extension KernelNetwork {
    /// Where a train stops for any of `stations` (every station when
    /// `nil`) at the end of an edge, each way: the berths of their platforms
    /// that end at a node (Stage S5: forward at a platform's end, backward
    /// at its start). A train placed there stands there with no path, as a
    /// grid train placed at a node beside a station did.
    static func endBerths(in world: GameWorld, of stations: [StationID]? = nil) -> [TrainPosition] {
        world.network.platforms.filter { stations?.contains($0.station) ?? true }.flatMap { platform -> [TrainPosition] in
            guard let length = world.trackEdge(platform.edge)?.length else { return [] }
            var berths: [TrainPosition] = []
            if platform.end == length { berths.append(.onEdge(TrackTraversal(edge: platform.edge, direction: .forward), offset: length)) }
            if platform.start == 0 { berths.append(.onEdge(TrackTraversal(edge: platform.edge, direction: .backward), offset: length)) }
            return berths
        }
    }

    /// `position` turned round where it stands, for a train of one car.
    static func turned(_ position: TrainPosition, in world: GameWorld) -> TrainPosition {
        guard case .onEdge(let traversal, let offset) = position, let length = world.trackEdge(traversal.edge)?.length else { return position }
        return .onEdge(TrackTraversal(edge: traversal.edge, direction: traversal.direction == .forward ? .backward : .forward), offset: length - offset)
    }

    /// Where a train at `start` stands after following `path` to its end.
    static func end(of path: TrainPath, from start: TrainPosition, in world: GameWorld) -> TrainPosition {
        guard case .onEdge(let traversal, _) = start else { return start }
        let last = path.traversals.last ?? traversal
        return .onEdge(last, offset: path.end ?? world.trackEdge(last.edge)?.length ?? 0)
    }

    /// Stops for a line that starts at `first`, its train standing at
    /// `start`: up to `count` more, each mostly a station the train reaches
    /// from where it arrives at the stop before, since a line turns round
    /// only at its ends; now and then any of `served`.
    static func drivableStops(
        from first: StationID, at start: TrainPosition, count: Int, among served: [StationID], in world: GameWorld, using random: inout SplitMix64
    ) -> [StationID] {
        var stops = [first]
        var at: TrainPosition? = start
        for _ in 0..<count {
            let journeys = at.map { at in
                served.filter { $0 != stops.last }.compactMap { station in
                    world.path(from: at, toStation: station).flatMap { $0.distance > 0 ? (station, $0) : nil }
                }
            } ?? []
            if let from = at, !journeys.isEmpty, random.chance(5, in: 6) {
                let (next, path) = random.element(of: journeys)
                stops.append(next)
                at = end(of: path, from: from, in: world)
            } else {
                let next = random.element(of: served)
                if next != stops.last { stops.append(next) }
                at = nil
            }
        }
        return stops
    }
}
