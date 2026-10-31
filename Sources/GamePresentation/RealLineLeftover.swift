import GameCore

// Decision 528: a real line bought and then removed is on sale again, but
// its track, platforms and depot stay where they were, on the very place
// the line is laid again, so GameCore refuses the new track beside them.
// The purchase takes them up first: every edge whose whole centre line
// lies on the track laid again, with the platforms on it of stations no
// line calls at, then the nodes left with no edge and a depot left with no
// platform. Track of a line still running (a platform of a station a line
// calls at), crossing the way, or beside it farther off than a few metres
// is not the line's and stays; where it is in the way, the purchase is
// refused as before. Track joined to what is taken up goes with it while
// none of that joined track has a platform of a station a line calls at:
// what the old line left past where the new one parts from it.

/// What a purchase takes up before it lays its track (decision 528): the
/// track left by the same line bought and removed before.
public struct RealLineClearing: Hashable, Sendable, Codable {
    /// A platform taken up: its station, edge (by number, as a log
    /// writes it) and start.
    public struct Platform: Hashable, Sendable, Codable {
        public let station: StationID
        public let edge: Int
        public let start: Int64
    }

    public let platforms: [Platform]
    /// The edges and nodes, by number.
    public let edges: [Int]
    public let nodes: [Int]
    /// Depots left with no platform and no line.
    public let stations: [StationID]

    /// How near the track laid again every point of an edge lies for it to
    /// be that track: the same layout lays it within centimetres, and the
    /// nearest other track a train may run beside is 4 m off.
    static let reach = 2 * RealLineAcquisition.metre
    /// How far apart the points of the track laid again are looked at.
    static let step = 2 * RealLineAcquisition.metre

    /// What lies in the way of `pieces` in `world` and is the old line's,
    /// or `nil` for nothing.
    static func clearing(in world: GameWorld, under pieces: [RealLineAcquisition.Piece]) -> RealLineClearing? {
        // The track to be laid, as points 2 m apart, in 4 m squares.
        let cell = 2 * reach
        func key(_ x: Double, _ y: Double) -> GridKey { GridKey(x: Int64((x / cell).rounded(.down)), y: Int64((y / cell).rounded(.down))) }
        var laid: [GridKey: [WorldVector]] = [:]
        for piece in pieces {
            for index in piece.curves.indices {
                guard let geometry = TrackGeometry(from: piece.nodes[index], to: piece.nodes[index + 1], curve: piece.curves[index]) else { continue }
                let points = geometry.points.map { WorldVector($0.plan) }
                for (a, b) in zip(points, points.dropFirst()) {
                    let count = max(1, Int(((b - a).length / step).rounded(.up)))
                    for part in 0...count {
                        let point = a + (b - a) * (Double(part) / Double(count))
                        laid[key(point.x, point.y), default: []].append(point)
                    }
                }
            }
        }
        guard !laid.isEmpty else { return nil }
        func onTheWay(_ point: WorldVector) -> Bool {
            let x = Int64((point.x / cell).rounded(.down)), y = Int64((point.y / cell).rounded(.down))
            for dx: Int64 in -1...1 {
                for dy: Int64 in -1...1 {
                    if laid[GridKey(x: x + dx, y: y + dy)]?.contains(where: { ($0 - point).length <= reach }) == true { return true }
                }
            }
            return false
        }

        let called = Set(world.lines.flatMap { $0.stops + $0.depots })
        var edges: [TrackEdgeID] = []
        var platforms: [Platform] = []
        for edge in world.network.edges {
            guard let from = world.network.node(edge.from), let to = world.network.node(edge.to),
                  onTheWay(WorldVector(from.position.plan)), onTheWay(WorldVector(to.position.plan)),
                  let geometry = TrackGeometry(from: from.position, to: to.position, curve: edge.curve) else { continue }
            let points = geometry.points.map { WorldVector($0.plan) }
            guard zip(points, points.dropFirst()).allSatisfy({ a, b in
                let count = max(1, Int(((b - a).length / step).rounded(.up)))
                return (0...count).allSatisfy { onTheWay(a + (b - a) * (Double($0) / Double(count))) }
            }) else { continue }
            let on = world.network.platforms(on: edge.id)
            guard on.allSatisfy({ !called.contains($0.station) }) else { continue }
            edges.append(edge.id)
            platforms += on.map { Platform(station: $0.station, edge: $0.edge.number, start: $0.start) }
        }
        guard !edges.isEmpty else { return nil }
        // The rest of the track joined to it, where none of it is a
        // station's that a line calls at: what is left of the old line
        // past where the new one parts from it (the Green Mountain Line's
        // way to Kanding and its depot, under the Blue Coast Line bought
        // after it was removed). Joined to a line still running (a branch
        // line's junction on the main line), only what lies on the way.
        var joined = Set(edges), queue = edges
        var dead = true
        while dead, let next = queue.popLast() {
            guard let edge = world.network.edge(next) else { continue }
            for node in [edge.from, edge.to] {
                for end in world.network.node(node)?.ends ?? [] where !joined.contains(end.edge) {
                    if world.network.platforms(on: end.edge).contains(where: { called.contains($0.station) }) {
                        dead = false
                        break
                    }
                    joined.insert(end.edge)
                    queue.append(end.edge)
                }
            }
        }
        if dead {
            let matched = Set(edges)
            for id in joined.sorted() where !matched.contains(id) {
                edges.append(id)
                platforms += world.network.platforms(on: id).map { Platform(station: $0.station, edge: $0.edge.number, start: $0.start) }
            }
        }
        let taken = Set(edges)
        let nodes = world.network.nodes.filter { node in
            !node.ends.isEmpty && node.ends.allSatisfy { taken.contains($0.edge) }
        }.map(\.id)
        let emptied = Set(platforms.map(\.station))
        let stations = world.stations.filter { station in
            station.isDepot && emptied.contains(station.id) && !called.contains(station.id)
                && world.network.platforms.allSatisfy { $0.station != station.id || taken.contains($0.edge) }
        }.map(\.id)
        return RealLineClearing(platforms: platforms, edges: edges.map(\.number), nodes: nodes.map(\.number), stations: stations)
    }

    /// Takes it up in `world`: the platforms, then the edges (over again
    /// while one more comes up: an edge may hold two others apart until
    /// they go too), the nodes and the depots. Free, as taking track up
    /// is; throwing, the caller's copy is dropped.
    func apply(to world: inout GameWorld) throws(GameError) {
        for platform in platforms {
            try world.removeTrackPlatform(platform.station, on: .edge(platform.edge), from: platform.start)
        }
        var left = edges.map { TrackEdgeID.edge($0) }
        while !left.isEmpty {
            var failure: GameError?
            var kept: [TrackEdgeID] = []
            for edge in left {
                do throws(GameError) {
                    try world.removeTrackEdge(edge)
                } catch {
                    failure = failure ?? error
                    kept.append(edge)
                }
            }
            if let failure, kept.count == left.count { throw failure }
            left = kept
        }
        for node in nodes {
            try world.removeTrackNode(.node(node))
        }
        for station in stations {
            try world.removeStation(station)
        }
    }
}

/// A square of ``RealLineClearing``'s grid.
private struct GridKey: Hashable {
    let x: Int64
    let y: Int64
}
