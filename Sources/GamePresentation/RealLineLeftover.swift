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
// keeps to, a station a train calls at on a timetable of its own, the
// way between two of its stops). Old saves kept no track, so nothing is
// taken up there. The track the line sharing its first stations left is
// taken up only where the line laid again comes onto it.

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
    /// Whether some of it is track the line sharing its first stations
    /// left (`ntdlrt:V` for `ntdlrt:VB`), only the part the line laid
    /// again comes onto, which the card says; `nil` for none (and in
    /// the logs of before).
    public let shared: Bool?

    init(platforms: [Platform], edges: [Int], nodes: [Int], stations: [StationID], shared: Bool? = nil) {
        self.platforms = platforms
        self.edges = edges
        self.nodes = nodes
        self.stations = stations
        self.shared = shared
    }

    /// The real lines sharing their first stations with `line`, either
    /// way (`ntdlrt:V` and `ntdlrt:VB`): their track lies on the same
    /// ground where they share it.
    static func sharingLines(of line: RealBranchLine) -> [String] {
        var names: [String] = []
        for rail in RealBranchLine.urbanLines {
            guard let shared = rail.shares else { continue }
            let one = "\(RealBranchLine.dataSystem(of: rail.system)):\(rail.network)"
            if one == line.id, shared != line.id, !names.contains(shared) { names.append(shared) }
            if shared == line.id, one != line.id, !names.contains(one) { names.append(one) }
        }
        return names
    }

    /// The stations some line or train calls at in `world`: each line's
    /// stops and depots, and the stations of each train's timetable, a
    /// line's or its own (``GameWorld/setTrainTimetable(_:to:repeatingEvery:)``).
    static func stationsCalledAt(in world: GameWorld) -> Set<StationID> {
        Set(world.lines.flatMap { $0.stops + $0.depots } + world.trains.flatMap { $0.timetable.map(\.station) })
    }

    /// The edges some line or train runs over in `world`: those holding
    /// a platform of a station a line or a train's timetable calls at,
    /// the ways between each line's consecutive stops (and its patterns'
    /// calls) and to and from its depots, the routes lines keep to, and
    /// the ways between each train's consecutive timetable stops (back to
    /// the first of a timetable that repeats), whether or not it runs
    /// for a line (#1636 second review, P2).
    static func edgesInUse(in world: GameWorld) -> Set<TrackEdgeID> {
        var used: Set<TrackEdgeID> = []
        let called = stationsCalledAt(in: world)
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
        for train in world.trains {
            var stops = train.timetable.map(\.station)
            if train.timetablePeriod != nil, let first = stops.first, stops.count > 1 { stops.append(first) }
            for (from, to) in zip(stops, stops.dropFirst()) where from != to {
                connect(from, to)
                connect(to, from)
            }
        }
        return used
    }

    /// The track `line` (`own`) and the lines sharing its first stations
    /// (`shared`) left when they were removed, but for the edges a line
    /// or train runs over; `nil` for none.
    static func left(in world: GameWorld, for line: RealBranchLine) -> (own: [TrackEdgeID], shared: [TrackEdgeID])? {
        let used = edgesInUse(in: world)
        let own = world.trackLeft(by: line.id).filter { !used.contains($0) }
        var shared: [TrackEdgeID] = []
        for name in sharingLines(of: line) {
            for edge in world.trackLeft(by: name) where !used.contains(edge) && !own.contains(edge) && !shared.contains(edge) {
                shared.append(edge)
            }
        }
        return own.isEmpty && shared.isEmpty ? nil : (own, shared)
    }

    /// What buying `line` in `world` takes up at most: all the track
    /// ``left(in:for:)`` finds. The offer takes up only the part of the
    /// sharing lines' that is in the way (``RealLineLaying/offer(for:)``).
    static func clearing(in world: GameWorld, for line: RealBranchLine) -> RealLineClearing? {
        guard let left = left(in: world, for: line) else { return nil }
        return clearing(in: world, taking: left.own + left.shared, shared: !left.shared.isEmpty)
    }

    /// Taking up `edges` in `world`, with their platforms, the nodes only
    /// they end at and the depots they empty; `nil` for none.
    static func clearing(in world: GameWorld, taking edges: [TrackEdgeID], shared: Bool) -> RealLineClearing? {
        guard !edges.isEmpty else { return nil }
        let platforms = edges.flatMap { edge in
            world.network.platforms(on: edge).map { Platform(station: $0.station, edge: $0.edge.number, start: $0.start) }
        }
        let taken = Set(edges)
        let nodes = world.network.nodes.filter { node in
            !node.ends.isEmpty && node.ends.allSatisfy { taken.contains($0.edge) }
        }.map(\.id)
        let called = stationsCalledAt(in: world)
        let emptied = Set(platforms.map(\.station))
        let stations = world.stations.filter { station in
            station.isDepot && emptied.contains(station.id) && !called.contains(station.id)
                && world.network.platforms.allSatisfy { $0.station != station.id || taken.contains($0.edge) }
        }.map(\.id)
        return RealLineClearing(
            platforms: platforms, edges: edges.map(\.number), nodes: nodes.map(\.number), stations: stations, shared: shared ? true : nil
        )
    }

    /// Which of `candidates` lie within ``overlapReach`` of the track
    /// `laid` has besides the edges `before` (each compared by its
    /// sampled centre lines, in plan and height): the track the line
    /// laid again comes onto.
    static func overlapping(_ candidates: [TrackEdgeID], in world: GameWorld, laid: GameWorld, besides before: Set<TrackEdgeID>) -> [TrackEdgeID] {
        let reach = overlapReach, cell = Double(reach)
        func key(_ point: WorldCoordinate) -> SIMD2<Int64> {
            SIMD2(Int64((Double(point.x) / cell).rounded(.down)), Int64((Double(point.y) / cell).rounded(.down)))
        }
        var grid: [SIMD2<Int64>: [WorldCoordinate]] = [:]
        for edge in laid.network.edges where !before.contains(edge.id) {
            for point in points(of: edge.id, in: laid) {
                grid[key(point), default: []].append(point)
            }
        }
        guard !grid.isEmpty else { return [] }
        func near(_ point: WorldCoordinate) -> Bool {
            let centre = key(point)
            for dx in -1...1 {
                for dy in -1...1 {
                    for other in grid[centre &+ SIMD2(Int64(dx), Int64(dy))] ?? [] {
                        let x = other.x - point.x, y = other.y - point.y
                        if x * x + y * y <= reach * reach, abs(other.z - point.z) <= overlapRise { return true }
                    }
                }
            }
            return false
        }
        return candidates.filter { points(of: $0, in: world).contains(where: near) }
    }

    /// How near the track laid again a sharing line's track counts as
    /// in its way: twice ``RailwayNetwork/trackSpacing`` (8 m), track
    /// closer than that at one level is refused.
    static let overlapReach = 2 * RailwayNetwork.trackSpacing
    /// How far above or below it still counts (6 m): a viaduct over it
    /// does not.
    static let overlapRise: Int64 = 6 * WorldCoordinate.unitsPerMetre

    /// Edge `id`'s sampled centre line in `world`, its ends for one
    /// whose geometry cannot be worked out.
    static func points(of id: TrackEdgeID, in world: GameWorld) -> [WorldCoordinate] {
        guard let edge = world.network.edge(id), let from = world.network.node(edge.from)?.position,
              let to = world.network.node(edge.to)?.position else { return [] }
        return TrackGeometry(from: from, to: to, curve: edge.curve, profile: edge.profile)?.points ?? [from, to]
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

    /// What the offer card says it takes up, in a sentence: the pieces
    /// of track, the platforms on them and the depots, and whose they
    /// were.
    func text(in language: DisplayLanguage) -> String {
        let pieces = edges.count, stands = platforms.count, depots = stations.count
        var english = ["\(pieces) \(pieces == 1 ? "piece" : "pieces") of track"]
        var chinese = ["\(pieces) 段軌道"]
        if stands > 0 {
            english.append("\(stands) \(stands == 1 ? "platform" : "platforms")")
            chinese.append("\(stands) 個月台")
        }
        if depots > 0 {
            english.append("\(depots) \(depots == 1 ? "depot" : "depots")")
            chinese.append("\(depots) 座機廠")
        }
        let englishList = english.count == 1 ? english[0] : english.dropLast().joined(separator: ", ") + " and " + english[english.count - 1]
        let chineseList = chinese.count == 1 ? chinese[0] : chinese.dropLast().joined(separator: "、") + "與" + chinese[chinese.count - 1]
        if shared == true {
            return language.text(
                "Buying it first takes up \(englishList) that lines removed before left.",
                "收購時會先拆掉之前刪掉的路線留下的 \(chineseList)。"
            )
        }
        return language.text(
            "Buying it first takes up \(englishList) the line left when it was removed.",
            "收購時會先拆掉這條線刪掉時留下的 \(chineseList)。"
        )
    }
}
