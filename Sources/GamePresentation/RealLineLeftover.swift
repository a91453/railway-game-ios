import GameCore

// Decision 528: a real line bought and then removed is on sale again, but
// its track, platforms and depot stay where they were, on the very place
// the line is laid again, so GameCore refuses the new track beside them.
// GameCore keeps what each purchase laid and, the line removed, what of it
// still stands (``GameWorld/trackLeft(by:)``). Bought again, and only when
// the plain layout is refused, the purchase takes that track up first, and
// nothing else: not track the player laid, not another line's, and not an
// edge any line still runs over (a platform of a station a line calls at,
// the way between two of a line's stops, the way to its depot, a route it
// keeps to). Old saves kept no track, so nothing is taken up there.

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

    /// The real lines whose track buying `line` takes up: its own, and
    /// that of the line it shares its first stations with, either way
    /// (`ntdlrt:V` and `ntdlrt:VB`), which lies on the same ground.
    static func realLines(of line: RealBranchLine) -> [String] {
        let shares = RealBranchLine.urbanLines.compactMap { rail -> (String, String)? in
            guard let shared = rail.shares else { return nil }
            return ("\(RealBranchLine.dataSystem(of: rail.system)):\(rail.network)", shared)
        }
        var names = [line.id]
        for (one, other) in shares {
            if one == line.id, !names.contains(other) { names.append(other) }
            if other == line.id, !names.contains(one) { names.append(one) }
        }
        return names
    }

    /// The edges some line runs over in `world`: those holding a platform
    /// of a station a line calls at, the ways between each line's
    /// consecutive stops (and its patterns' calls) and to and from its
    /// depots, and the routes lines keep to.
    static func edgesInUse(in world: GameWorld) -> Set<TrackEdgeID> {
        var used: Set<TrackEdgeID> = []
        let called = Set(world.lines.flatMap { $0.stops + $0.depots })
        for platform in world.network.platforms where called.contains(platform.station) {
            used.insert(platform.edge)
        }
        func connect(_ from: StationID, _ to: StationID) {
            for platform in world.network.platforms where platform.station == from {
                for direction in [TrackEdgeDirection.forward, .backward] {
                    let offset = direction == .forward ? platform.end : (world.network.edge(platform.edge)?.length ?? 0) - platform.start
                    let start = TrainPosition.onEdge(TrackTraversal(edge: platform.edge, direction: direction), offset: offset)
                    for traversal in world.path(from: start, toStation: to)?.traversals ?? [] {
                        used.insert(traversal.edge)
                    }
                }
            }
        }
        for line in world.lines {
            for (from, to) in zip(line.stops, line.stops.dropFirst()) {
                connect(from, to)
                connect(to, from)
            }
            for pattern in line.patterns {
                let calls = pattern.calls.compactMap { line.stops.indices.contains($0) ? line.stops[$0] : nil }
                for (from, to) in zip(calls, calls.dropFirst()) {
                    connect(from, to)
                    connect(to, from)
                }
                for route in pattern.routePreferences {
                    used.formUnion(route.tracks.map(\.edge))
                }
            }
            for route in line.routePreferences {
                used.formUnion(route.tracks.map(\.edge))
            }
            for depot in line.depots {
                for end in [line.stops.first, line.stops.last].compactMap({ $0 }) {
                    connect(depot, end)
                    connect(end, depot)
                }
            }
        }
        return used
    }

    /// What buying `line` in `world` takes up: the track it (or the line
    /// sharing its first stations) left when it was removed, but for the
    /// edges a line runs over; `nil` for none.
    static func clearing(in world: GameWorld, for line: RealBranchLine) -> RealLineClearing? {
        var left: [TrackEdgeID] = []
        for name in realLines(of: line) {
            for edge in world.trackLeft(by: name) where !left.contains(edge) {
                left.append(edge)
            }
        }
        guard !left.isEmpty else { return nil }
        let used = edgesInUse(in: world)
        let edges = left.filter { !used.contains($0) }
        guard !edges.isEmpty else { return nil }
        let platforms = edges.flatMap { edge in
            world.network.platforms(on: edge).map { Platform(station: $0.station, edge: $0.edge.number, start: $0.start) }
        }
        let taken = Set(edges)
        let nodes = world.network.nodes.filter { node in
            !node.ends.isEmpty && node.ends.allSatisfy { taken.contains($0.edge) }
        }.map(\.id)
        let called = Set(world.lines.flatMap { $0.stops + $0.depots })
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

    /// What the offer card says it takes up, in a sentence.
    func text(in language: DisplayLanguage) -> String {
        let pieces = edges.count, depots = stations.count
        if depots == 0 {
            return language.text(
                "Buying it first takes up \(pieces) \(pieces == 1 ? "piece" : "pieces") of track the line left when it was removed.",
                "收購時會先拆掉這條線刪掉時留下的 \(pieces) 段軌道。"
            )
        }
        return language.text(
            "Buying it first takes up \(pieces) \(pieces == 1 ? "piece" : "pieces") of track and \(depots) \(depots == 1 ? "depot" : "depots") the line left when it was removed.",
            "收購時會先拆掉這條線刪掉時留下的 \(pieces) 段軌道與 \(depots) 座機廠。"
        )
    }
}
