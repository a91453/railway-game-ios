import Foundation
import GameCore

// Tracing the real railway (ARCHITECTURE decision 213, NEXT_PRIORITIES §13
// second): with the network tool's "Trace real railway" on, on a real-world
// or whole-Taiwan map, a drag or a tap near one of Taiwan's real lines (the
// lines the app bundles and draws under the map, ``RealRailways``) snaps to
// it, and the stretch between the two ends follows the real line rather than
// one curve: the line's centre, smoothed, fitted with the real-world demo's
// cubic edges (``RealWorldDemo/TrackPlan``) and heights (``TrackRise``), as
// one command of the player's (``PlayerCommand/buildTrackChain(_:)``) that
// GameCore checks edge by edge like any other track. Where GameCore refuses
// an edge (too steep, too close to other track, land not bought, money), the
// trace stops before it and says why: what comes before it can be built.
//
// None of it is the game's: the real lines are presentation data, and what
// is built is ordinary track, made by the network tool's commands.

extension GameSession {
    /// The steepest grade a traced stretch is laid at: a little under the
    /// game's 40 in 1,000 (``TrackProfile/maximumGrade``), so an edge
    /// between two of its heights, rounded to whole units, never exceeds
    /// it.
    static let traceGrade = 0.038

    /// Decision 515: the steepest grade a stretch of a real mountain line
    /// (``mountainSystems``) is laid at, a little under mountain track's 70
    /// in 1,000 (``TrackProfile/maximumMountainGrade``) for the same
    /// reason, and by as much as ``traceGrade`` is under 40: at 68 the
    /// Alishan line's curves, each a little shorter than the traced way
    /// under it, came out at 70.8.
    static let mountainTraceGrade = 0.066

    /// Decision 515: the real railways whose lines climb more steeply than
    /// the game's 40 in 1,000, which a trace lays as mountain track where
    /// it must: the Alishan Forest Railway, whose ruling grade is 62.5 in
    /// 1,000 (the Forestry and Nature Conservation Agency's 林業軌道 page,
    /// recreation.forest.gov.tw/Railway/Introduce, which the Railway
    /// reference's `docs/afr-push-pull-0913.md` cites for its switchbacks).
    /// The other real lines of the map (the TRA's 25 in 1,000 at most, the
    /// High Speed Rail's, the metros') climb no more than the game's
    /// grade.
    static let mountainSystems: Set<String> = ["afr_sched"]

    /// The steepest grade a trace of a real line of `system` is laid at:
    /// ``mountainTraceGrade`` for a mountain line, else ``traceGrade``.
    static func traceGrade(ofSystem system: String?) -> Double {
        system.map(mountainSystems.contains) ?? false ? mountainTraceGrade : traceGrade
    }

    /// Whether the network tool can trace the real railway here: on a
    /// real-world map whose real railways are loaded.
    public var canTraceRealRailway: Bool {
        realRailwayTraces != nil
    }

    /// Whether the next stretch is traced along the real railway: the
    /// option is on and the map has real lines to trace.
    var tracesRealRailway: Bool {
        networkTracesRealRailway && canTraceRealRailway
    }

    /// The real lines of this map, worked out once for each map and kept
    /// (``realRailwayTracesMemo``); `nil` on a blank map or without the
    /// real railways.
    var realRailwayTraces: RealRailwayTraces? {
        guard let railways, let frame = RealWorldFrame(world: world) else { return nil }
        let key = RealRailwayTracesKey(frame: frame, bounds: world.bounds)
        if let memo = realRailwayTracesMemo, memo.key == key { return memo.traces }
        let traces = RealRailwayTraces(railways: railways, frame: frame, bounds: world.bounds)
        realRailwayTracesMemo = (key, traces)
        return traces
    }

    /// How near a real line a tap or a drag snaps to it: the tap's reach,
    /// or 30 m where that is less.
    static func traceReach(_ reach: Int64) -> Double {
        max(Double(reach), 30 * RealRailwayTraces.metre)
    }

    /// Where a tap or a drag at `point` picks an end while tracing, with no
    /// track within reach: the nearest place on a real line within reach
    /// (``traceReach(_:)``); `nil` where no real line is that near.
    func tracedPoint(near point: PlanPoint, reach: Int64) -> PlanPoint? {
        guard tracesRealRailway, let traces = realRailwayTraces,
              let snap = traces.snap(WorldVector(point), within: Self.traceReach(reach)) else { return nil }
        let snapped = snap.point.plan
        return world.bounds.contains(snapped) ? snapped : nil
    }

    /// The real line's way from `start` to `end`, both within reach of
    /// real lines that join, as plan points from one end to the other;
    /// `nil` where either is too far from a real line or no line joins
    /// them.
    ///
    /// Decision 972: `leaving` and `arriving` are the ends where they are
    /// on track: the way leaves the track there, and reaches it, along it.
    func tracedWay(
        from start: WorldCoordinate, to end: WorldCoordinate, reach: Double, leaving: NetworkAnchor? = nil, arriving: NetworkAnchor? = nil
    ) -> [WorldVector]? {
        guard let best = tracedRoute(from: start.plan, to: end.plan, reach: reach) else { return nil }
        // And each step from one line to the one beside it slanting, as a
        // crossover is.
        let way = RealRailwayTraces.eased(best.points, hops: best.hops)
        guard networkFollowsTrack, leaving != nil || arriving != nil else { return way }
        let path = WorldPath(way)
        guard path.points.count > 1 else { return way }
        let ahead = path.point(at: min(path.length, 50 * RealRailwayTraces.metre)).plan
        let behind = path.point(at: max(0, path.length - 50 * RealRailwayTraces.metre)).plan
        let away = leaving.flatMap { Self.joiningDirection(of: $0, toward: ahead, in: world) }
        let toward = arriving.flatMap { Self.joiningDirection(of: $0, toward: behind, in: world) }?.reversed
        guard away != nil || toward != nil else { return way }
        return RealRailwayTraces.eased(best.points, hops: best.hops, leaving: away, arriving: toward)
    }

    /// The shortest way along the real lines from `start` to `end` that
    /// ``tracedWay(from:to:reach:leaving:arriving:)`` eases, with its
    /// hops; `nil` where either is too far from a real line or no line
    /// joins them. Worked out once for each pair of points and kept
    /// (``tracedRouteMemo``): in one move of a drag the map's lit line,
    /// the preview and the track it joins each ask for it.
    func tracedRoute(from start: PlanPoint, to end: PlanPoint, reach: Double) -> (points: [WorldVector], hops: [Int])? {
        guard let traces = realRailwayTraces, let frame = RealWorldFrame(world: world) else { return nil }
        let key = TracedRouteKey(lines: RealRailwayTracesKey(frame: frame, bounds: world.bounds), from: start, to: end, reach: reach)
        if let memo = tracedRouteMemo, memo.key == key { return memo.route }
        tracedRoutesWorkedOut += 1
        let from = WorldVector(start), to = WorldVector(end)
        guard let nearest = traces.snap(from, within: reach) else {
            tracedRouteMemo = (key, nil)
            return nil
        }
        // Decision 972: where lines of the system are drawn side by side
        // (the North-Link Line beside the Yilan Line through Su'aoxin's
        // yard, 9 to 14 m apart for 450 m), each end may be on any of them
        // within reach, and the way is the shortest of those, an end's
        // distance from its line counted twice; the nearest line at each
        // end where none is shorter. Held to the nearest, a trace from
        // beside the junction to Su'ao ran up the North-Link Line to its
        // end in the station, stepped 12.7 m across and came back.
        var best: (points: [WorldVector], hops: [Int], cost: Double)?
        for first in traces.snaps(from, within: reach, system: traces.lines[nearest.place.line].system) {
            for last in traces.snaps(to, within: reach, group: traces.groups[first.place.line]) {
                guard let route = traces.route(from: first.place, to: last.place) else { continue }
                let points = [from] + route.points + [to]
                let cost = zip(points, points.dropFirst()).reduce(first.distance + last.distance) { $0 + ($1.1 - $1.0).length }
                if best.map({ cost < $0.cost - RealRailwayTraces.metre }) ?? true {
                    best = (points, [0] + route.hops.map { $0 + 1 } + [points.count - 2], cost)
                }
            }
        }
        let route = best.map { (points: $0.points, hops: $0.hops) }
        tracedRouteMemo = (key, route)
        return route
    }

    /// The way track joining `anchor` runs from it toward `point`, where
    /// the anchor is on track that track may join (decision 103).
    static func joiningDirection(of anchor: NetworkAnchor, toward point: PlanPoint, in world: GameWorld) -> WorldVector? {
        switch anchor {
        case .node(let id):
            guard !world.joiningDirections(at: id).isEmpty, let direction = world.joiningDirection(at: id, toward: point) else { return nil }
            return WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit
        case .track(let place):
            return world.joiningDirection(at: place, toward: point).map { WorldVector(x: Double($0.dx), y: Double($0.dy)).unit }
        case .point:
            return nil
        }
    }

    /// The traced stretch from `start` to `end` (decision 213): `nil`
    /// unless the tool traces and both ends are on real lines that join.
    /// On a copy of the world, with the ground read under the way; GameCore
    /// builds its edges one by one there to find the first it refuses.
    ///
    /// Decision 351: the demo mode's real lines give the way themselves
    /// (`given`, from `start` to `end`, whether or not the tool traces),
    /// and the `platforms` to lay along it, each from one point of the way
    /// to another: each becomes one level edge, its ends nodes.
    ///
    /// Decision 513: the real stations of `system` (the line's at the
    /// start's where none is given) along `path`, each with the longest
    /// platform's length of the path about it, an end near the path's end
    /// drawn to it: where the player's trace lays its track level, as the
    /// real station stands.
    func tracedStationSpans(along path: WorldPath, system: String?) -> [ClosedRange<Double>] {
        let reach = Self.traceReach(NetworkBuilding.minimumSpacing * 2)
        guard let railways, let frame = RealWorldFrame(world: world), let first = path.points.first,
              let system = system ?? realRailwayTraces.flatMap({ traces in traces.snap(first, within: reach).map { traces.lines[$0.place.line].system } })
        else { return [] }
        let platform = Double(Int64(Train.maximumCars) * world.platformCarLength)
        // Decision 752: and room past each end of the longest platform for
        // an island platform track's turnouts (``PlatformTrackLayout/reach``),
        // so a platform track can be added there however long the platform;
        // without it where two stations stand too near for both.
        // Decision 943: and a few metres more, as the level edge laid over
        // the span is a curve a little shorter than the traced path (at
        // Qipan 495.6 m for 496 m, which left 87.6 m past one end for a
        // reach of 88 m; the old ground's gentler grade beyond had hidden
        // it).
        let turnouts = Double(2 * PlatformTrackLayout.island.reach + 8 * WorldCoordinate.unitsPerMetre)
        let margin = Double(NetworkBuilding.minimumSpacing)
        var spans: [ClosedRange<Double>] = []
        for station in railways.stations where station.system.id == system {
            let near = path.nearest(WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)))
            guard near.away <= DemoRealLines.stationReach else { continue }
            for length in [platform + turnouts, platform] {
                var low = max(0, near.along - length / 2), high = min(path.length, near.along + length / 2)
                if low < margin { low = 0 }
                if path.length - high < margin { high = path.length }
                guard high - low >= margin, !spans.contains(where: { $0.overlaps(low...high) }) else { continue }
                spans.append(low...high)
                break
            }
        }
        return spans.sorted { $0.lowerBound < $1.lowerBound }
    }
}
