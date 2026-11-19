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
// Now it is laid from the far end of the Green Mountain Line's platform
// track at Binhai Shalun, on the side it leaves toward (the second track,
// the trains toward Hongshulin's), and its trains run the whole real
// timetable from Hongshulin, calling at the Green Mountain Line's
// platforms: Binhai Shalun has the one island. The game has no crossing of
// two tracks at one level, so the trains toward Fisherman's Wharf cross to
// that track before the station, over a crossover the Green Mountain Line
// is laid with on its Hongshulin side (``RealBranchLine/leavingStations``),
// and stop on the island's south face, not its north face as the real ones
// do. Its trains stand overnight on its own track, at its own stations, and
// not the real ones' three at Hongshulin, whose platforms the Green Mountain
// Line's trains fill; its empty runs taking them there are left out.
// Where the Green Mountain Line was laid without the crossover (a game
// saved before), or the line cannot join its track, it is laid as before.
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
    /// way that track runs on, so the line's track crosses none of the
    /// station's others. Its station, the node, and the way the track runs
    /// out of the station there. `nil` where the station has no two
    /// platform tracks running on toward `next` from a plain node each.
    static func leavingNode(at point: WorldVector, toward next: WorldVector, in world: GameWorld) -> (station: StationID, node: WorldCoordinate, way: WorldVector)? {
        guard let station = world.stations
            .filter({ !$0.isDepot && (WorldVector($0.location) - point).length <= RealLineAcquisition.junctionReach })
            .min(by: { (WorldVector($0.location) - point).length < (WorldVector($1.location) - point).length })
        else { return nil }
        let centre = WorldVector(station.location)
        var candidates: [(node: WorldCoordinate, way: WorldVector, onward: WorldVector)] = []
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
                candidates.append((node.position, way, (WorldVector(far.position.plan) - position).unit))
            }
        }
        guard candidates.count > 1 else { return nil }
        let zero = WorldVector(x: 0, y: 0)
        let way = candidates.reduce(zero) { $0 + $1.way }.unit, onward = candidates.reduce(zero) { $0 + $1.onward }.unit
        let lateral = way.normal
        // Positive where the line leaves to the lateral's side of the way
        // the station's track runs on.
        let leaves = ((next - centre).unit - onward).dot(lateral)
        guard leaves != 0, let best = candidates.max(by: {
            (WorldVector($0.node.plan) - centre).dot(lateral) * leaves < (WorldVector($1.node.plan) - centre).dot(lateral) * leaves
        }) else { return nil }
        return (station.id, best.node, best.way)
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
        guard stations.indices.contains(joins.stop),
              let other = world.acquisition(of: joins.line)?.line.flatMap({ world.line(id: $0) }),
              let platform = world.network.platforms(of: stations[joins.stop]).first(where: { platform in
                  world.network.edge(platform.edge).map { edge in
                      [edge.from, edge.to].contains { world.network.node($0)?.position == joins.at }
                  } ?? false
              })
        else { throw .invalidTrackGeometry }
        let lineStops = Array(stations.reversed())
        let leaving = lineStops.count - 1 - joins.stop
        var routes = [leaving - 1, leaving + 1].filter { lineStops.indices.contains($0) }.map {
            LineRoutePreference(from: $0, to: leaving, platform: platform)
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
    /// SHALUN-ONE-ISLAND: the leg of line `line` into the station it
    /// leaves the joined line's track past, from the station before it,
    /// as a whole walk from the platform it arrives at there to the
    /// platform track it leaves from: a train toward its own track takes
    /// the crossover to it, never the other platform track, from which
    /// there is no way on. `nil` where the world gives no such walk.
    static func walkOntoLeavingTrack(
        of joins: RealLineAcquisition.Joining, line: LineID, stations: [StationID], in world: GameWorld
    ) -> LineRoutePreference? {
        guard let routes = world.line(id: line)?.routePreferences else { return nil }
        let leaving = stations.count - 1 - joins.stop, before = leaving + 1
        guard let into = routes.first(where: { $0.from == before && $0.to == leaving })?.platform,
              let arriving = routes.first(where: { $0.from == before + 1 && $0.to == before })?.platform else { return nil }
        return world.lineRouteChoices(line, from: before, to: leaving).first {
            !$0.tracks.isEmpty && $0.platform == into && $0.tracks.first?.edge == arriving.edge
        }
    }
}
