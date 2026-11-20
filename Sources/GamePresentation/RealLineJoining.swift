import GameCore

// SHALUN-ONE-ISLAND (2026-11-19, the owner on 140: 「濱海沙崙實際好像只有
// 一島」, and the choice 「照真實共用一座島」): the real Blue Coast Line's
// trains run from Hongshulin over the Green Mountain Line's track and leave
// it just west of Binhai Shalun, whose one island platform the two lines
// share. Bought after the Green Mountain Line (as the two are sold together,
// decision 862), the Blue Coast Line was laid from Binhai Shalun with an end
// of its own there, four platform tracks 10 m beside the Green Mountain
// Line's island, and its trains turned back there.
//
// Now it is laid from the far ends of the Green Mountain Line's platform
// tracks at Binhai Shalun, and its trains run the whole real timetable from
// Hongshulin, calling at the Green Mountain Line's platforms: Binhai Shalun
// has the one island. GRADE-CROSSING-SHALUN (decision 885, later): as the
// real ones, its trains toward Fisherman's Wharf stop on the island's north
// face and run straight on west, over the Green Mountain Line's track to
// Hongshulin where it turns north, on the flat (a diamond, decision 887's
// way, GameCore's since decisions 26 and 29); those coming back come in on
// its second track to the south face. Before, the game had no way to lay
// the diamond: both ways took the south face, the trains toward the wharf
// crossed to it over a crossover east of the station, and there they
// waited for the Green Mountain Line's trains toward Hongshulin
// (SHALUN-WAIT). Its trains stand overnight two at Hongshulin and the rest
// on its own track (``overnightOnOwnTrack(_:stops:tracks:elsewhere:)``).
// Where it cannot join the track so, it is laid as before it joined
// (its own end beside the island).
//
// Neither reference lays a bought line onto another's track: native.

extension RealLineAcquisition {
    /// SHALUN-ONE-ISLAND: how far the track of a line leaving another's
    /// runs on along that track's way before it turns onto its own
    /// drawing.
    static let joinLead = 30 * metre
}

extension RealLineLaying {
    /// SHALUN-ONE-ISLAND: where a line leaves the company's station
    /// nearest `point` toward `next`: the far end of one of its platform
    /// tracks there, the one on the side the line leaves toward from the
    /// way that track runs on (GRADE-CROSSING-SHALUN: and `across`, the
    /// far end of the one across the station, with the edges each runs on
    /// along), so the line's second track crosses none of the
    /// station's others. Its station, the node, and the way the track runs
    /// out of the station there. `nil` where the station has no two
    /// platform tracks running on toward `next` from a plain node each.
    static func leavingNode(
        at point: WorldVector, toward next: WorldVector, in world: GameWorld
    ) -> (station: StationID, node: WorldCoordinate, way: WorldVector, across: (node: WorldCoordinate, way: WorldVector, onward: TrackEdgeID), onward: TrackEdgeID)? {
        guard let station = world.stations
            .filter({ !$0.isDepot && (WorldVector($0.location) - point).length <= RealLineAcquisition.junctionReach })
            .min(by: { (WorldVector($0.location) - point).length < (WorldVector($1.location) - point).length })
        else { return nil }
        let centre = WorldVector(station.location)
        var candidates: [(node: WorldCoordinate, way: WorldVector, onward: WorldVector, edge: TrackEdgeID)] = []
        for platform in world.network.platforms(of: station.id) {
            guard let edge = world.network.edge(platform.edge), let geometry = world.trackGeometry(of: platform.edge) else { continue }
            for atEnd in [true, false] {
                let id = atEnd ? edge.to : edge.from
                guard let node = world.network.node(id) else { continue }
                let direction = geometry.location(at: atEnd ? geometry.length : 0).direction
                let along = WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit
                let way = atEnd ? along : along.reversed
                let position = WorldVector(node.position.plan)
                guard way.dot(next - position) > 0 else { continue }
                let others = world.network.edges.filter { $0.id != edge.id && ($0.from == id || $0.to == id) }
                guard others.count == 1, let other = others.first,
                      let far = world.network.node(other.from == id ? other.to : other.from) else { continue }
                candidates.append((node.position, way, (WorldVector(far.position.plan) - position).unit, other.id))
            }
        }
        guard candidates.count > 1 else { return nil }
        let zero = WorldVector(x: 0, y: 0)
        let way = candidates.reduce(zero) { $0 + $1.way }.unit, onward = candidates.reduce(zero) { $0 + $1.onward }.unit
        let lateral = way.normal
        // Positive where the line leaves to the lateral's side of the way
        // the station's track runs on.
        let leaves = ((next - centre).unit - onward).dot(lateral)
        let side = { (candidate: (node: WorldCoordinate, way: WorldVector, onward: WorldVector, edge: TrackEdgeID)) in
            (WorldVector(candidate.node.plan) - centre).dot(lateral) * leaves
        }
        guard leaves != 0, let best = candidates.max(by: { side($0) < side($1) }),
              let far = candidates.min(by: { side($0) < side($1) }), far.node != best.node else { return nil }
        return (station.id, best.node, best.way, (far.node, far.way, far.edge), best.edge)
    }

    /// SHALUN-ONE-ISLAND: where the trains of a line laid only from where
    /// it leaves the other line's track stand overnight, by its stops'
    /// names (`stops`, the stretch laid): as many as the whole line's
    /// real timetable (`full`) leaves anywhere but the `elsewhere` standing at
    /// the other line's platforms, at its far end while its
    /// tracks there have room, then one at each station before it.
    static func overnightOnOwnTrack(_ full: RealLineRuns, stops: [String], tracks: [String: Int], elsewhere: Int = 0) -> [String: Int] {
        var left = full.overnight.values.reduce(0, +) - elsewhere
        guard let last = stops.last else { return [:] }
        var standing: [String: Int] = [:]
        let atEnd = min(left, tracks[last] ?? 1)
        standing[last] = atEnd
        left -= atEnd
        for name in stops.dropFirst().dropLast().reversed() where left > 0 {
            standing[name] = 1
            left -= 1
        }
        return standing.filter { $0.value > 0 }
    }
}

extension RealLineLaying {
    /// SHALUN-ONE-ISLAND: the platforms a line on the track of the line
    /// it joins (``RealLineAcquisition/Joining``) takes at that line's
    /// stations, by the line's stops (`stations`, the first line's own
    /// order; its route runs them the other way round): at the station
    /// it leaves the track past, the platform track it leaves, both ways;
    /// at those before it, the platforms the other line's trains take
    /// between the same two stations.
    static func routesOnTrack(of joins: RealLineAcquisition.Joining, stations: [StationID], in world: GameWorld) throws(GameError) -> [LineRoutePreference] {
        func platform(at node: WorldCoordinate) -> TrackPlatform? {
            world.network.platforms(of: stations[joins.stop]).first { platform in
                world.network.edge(platform.edge).map { edge in
                    [edge.from, edge.to].contains { world.network.node($0)?.position == node }
                } ?? false
            }
        }
        guard stations.indices.contains(joins.stop),
              let other = world.acquisition(of: joins.line)?.line.flatMap({ world.line(id: $0) }),
              let outbound = platform(at: joins.at), let inbound = joins.inbound.map(platform(at:)) ?? outbound
        else { throw .invalidTrackGeometry }
        let lineStops = Array(stations.reversed())
        let leaving = lineStops.count - 1 - joins.stop
        // GRADE-CROSSING-SHALUN: coming back from its terminal's side
        // (`leaving - 1`), the near platform track; toward it, the one
        // across the station.
        var routes = [leaving - 1, leaving + 1].filter { lineStops.indices.contains($0) }.map {
            LineRoutePreference(from: $0, to: leaving, platform: $0 < leaving ? inbound : outbound)
        }
        let before = Set(stations.prefix(joins.stop))
        for route in other.routePreferences where other.stops.indices.contains(route.from) && other.stops.indices.contains(route.to) {
            let to = other.stops[route.to]
            guard before.contains(to), let i = lineStops.firstIndex(of: other.stops[route.from]), let j = lineStops.firstIndex(of: to), abs(i - j) == 1
            else { continue }
            routes.append(LineRoutePreference(from: i, to: j, tracks: route.tracks, platform: route.platform, alternates: route.alternates))
        }
        return routes
    }
}

extension RealLineLaying {
    /// SHALUN-ONE-ISLAND: another line whose trains stop at a platform on
    /// the track bought with line `id` (the Blue Coast Line's at the Green
    /// Mountain Line's stations), if any.
    static func lineRunning(onTrackOf id: LineID, in world: GameWorld) -> ServiceLine? {
        guard let track = world.acquisitions.first(where: { $0.line == id })?.track.map(Set.init), !track.isEmpty else { return nil }
        return world.lines.first { other in
            other.id != id && (other.routePreferences + other.patterns.flatMap(\.routePreferences)).contains { route in
                track.contains(route.platform.edge)
            }
        }
    }
}

extension RealLineLaying {
    /// GRADE-CROSSING-SHALUN: where `path` (a line's first track, from the
    /// platform track across the station it leaves) first crosses edge
    /// `crossed` (the other line's track turning off from the near platform
    /// track): how far along `path`, and the point on the edge, at its
    /// height there. `nil` where it does not cross it, or crosses it flatter
    /// than a diamond may be laid (``NetworkDiamond/minimumSine``) or too
    /// near either of the edge's ends to split it there.
    static func flatCrossing(of path: WorldPath, with crossed: TrackEdgeID, in world: GameWorld) -> (along: Double, at: WorldCoordinate)? {
        // The line bought again after it was removed: its diamond's node
        // stays on the other line's track, a plain node joining two
        // edges, where it crosses again.
        guard let edge = world.network.edge(crossed) else { return nil }
        var edges = [crossed]
        if let far = world.network.node(edge.to), far.ends.count == 2, let next = far.ends.map(\.edge).first(where: { $0 != crossed }) {
            edges.append(next)
        }
        for index in path.points.indices.dropLast() {
            for edge in edges {
                // Where it meets the track, the crossing, or `nil` where it
                // may not cross there.
                if let found = crossing(of: path, segment: index, with: edge, in: world) { return found }
            }
        }
        return nil
    }

    /// Where segment `index` of `path` meets edge `crossed`: `nil` where
    /// it does not, `.some(nil)` where it meets it but may not cross it
    /// there, else the crossing.
    private static func crossing(
        of path: WorldPath, segment index: Int, with crossed: TrackEdgeID, in world: GameWorld
    ) -> (along: Double, at: WorldCoordinate)?? {
        guard let track = world.trackGeometry(of: crossed), let edge = world.network.edge(crossed) else { return nil }
        let a = path.points[index], b = path.points[index + 1]
        let r = b - a
        for segment in track.points.indices.dropLast() {
            let c = WorldVector(track.points[segment].plan), d = WorldVector(track.points[segment + 1].plan)
            let s = d - c
            let denominator = r.x * s.y - r.y * s.x
            let lengths = r.length * s.length
            guard lengths > 0, denominator != 0 else { continue }
            let u = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
            let v = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
            guard (0...1).contains(u), (0...1).contains(v) else { continue }
            let start = Double(track.distances[segment]), end = Double(track.distances[segment + 1])
            let chainage = Int64((start + v * (end - start)).rounded())
            guard abs(denominator) >= NetworkDiamond.minimumSine * lengths else { return .some(nil) }
            let point = c + s * v
            let along = path.distances[index] + u * r.length
            // At a plain node of the track's already (bought again).
            for (end, id) in [(Int64(0), edge.from), (track.length, edge.to)] where abs(chainage - end) < GameWorld.minimumSplitPiece {
                guard let node = world.network.node(id), node.ends.count == 2,
                      (WorldVector(node.position.plan) - point).length <= RealLineAcquisition.metre else { return .some(nil) }
                return (along, node.position)
            }
            return (along, WorldCoordinate(x: Int64(point.x.rounded()), y: Int64(point.y.rounded()), z: track.height(at: chainage)))
        }
        return nil
    }

    /// GRADE-CROSSING-SHALUN: the edge of `world` that a node of a piece
    /// at `position` (``RealLineAcquisition/Piece/crossings``) stands on,
    /// and how far along it: the one passing nearest, within a metre.
    static func edge(under position: WorldCoordinate, in world: GameWorld) -> (edge: TrackEdgeID, distance: Int64)? {
        let point = WorldVector(position.plan)
        var best: (edge: TrackEdgeID, distance: Int64, away: Double)?
        for edge in world.network.edges {
            guard let track = world.trackGeometry(of: edge.id) else { continue }
            for segment in track.points.indices.dropLast() {
                let c = WorldVector(track.points[segment].plan), d = WorldVector(track.points[segment + 1].plan)
                let s = d - c, length = s.length
                guard length > 0 else { continue }
                let t = min(1, max(0, (point - c).dot(s) / (length * length)))
                let away = (c + s * t - point).length
                guard away <= RealLineAcquisition.metre, away < best?.away ?? .infinity else { continue }
                let start = Double(track.distances[segment]), end = Double(track.distances[segment + 1])
                best = (edge.id, Int64((start + t * (end - start)).rounded()), away)
            }
        }
        return best.map { ($0.edge, $0.distance) }
    }
}

extension RealBranchLine {
    /// HONGSHULIN-TURN: `runs` with more tracks at an end of this line
    /// that a line bought after it runs on to over its track
    /// (``leavesAt``): enough for both lines' trains the real timetables
    /// leave there at midnight, as many as the end can be laid with. The
    /// Green Mountain Line's Hongshulin: 6 tracks for its own 4 trains
    /// and its turns, 7 with the Blue Coast Line's 3. With 6, only two of
    /// the Blue Coast Line's stood there and the third at Tamsui
    /// Fisherman's Wharf, so Hongshulin was a train short all day and its
    /// runs from there left up to 20 minutes late. `runs` as it is for
    /// any other line, and for a line laid after another.
    func joinedTracks(_ runs: RealLineRuns, in railways: RealRailways) -> RealLineRuns {
        guard isUrban, after == nil, let first = runs.stops.first, let last = runs.stops.last else { return runs }
        var joined = runs
        let layout = cars > RealLineLayout.lightRailCars ? RealLineLayout.metro : .lightRail
        for other in Self.urbanLines where other.shares == id && Self.leavesAt(system: other.system, network: other.network) != nil {
            guard let full = Self.metroRuns(of: "\(Self.dataSystem(of: other.system)):\(other.network)", after: nil, in: railways) else { continue }
            for name in Set([first, last]) {
                guard let theirs = full.overnight[name], theirs > 0 else { continue }
                let most = 1 + RealLineLaying.endStationSides(of: self, name: name, loops: 0, layout: layout).count
                let wanted = min(most, (runs.overnight[name] ?? 0) + theirs)
                joined.tracks[name] = max(runs.tracks[name] ?? 1, wanted)
            }
        }
        return joined
    }
}
