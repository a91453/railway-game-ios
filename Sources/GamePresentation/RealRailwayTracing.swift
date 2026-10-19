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

/// Taiwan's real railways laid over a world's plan, as a network to trace
/// along: each line's centre line in world units, and where a line's end
/// meets another line of the same system (a branch leaving a main line, or
/// two pieces of one line).
struct RealRailwayTraces: Sendable {
    /// A real line in the world's plan.
    struct Line: Sendable {
        let id: Int
        let system: String
        let path: WorldPath
        /// Its box in plan, for finding the lines near a point quickly.
        let minX: Double, minY: Double, maxX: Double, maxY: Double
    }

    /// A place along a line: how far along it.
    struct Place: Hashable, Sendable {
        let line: Int
        let along: Double
    }

    /// A place on the network near a point, and how far the point is from
    /// it, in world units.
    struct Snap: Sendable {
        let place: Place
        let point: WorldVector
        let distance: Double
    }

    /// Where a line's end meets another line, and the gap between them.
    struct Link: Sendable {
        let a: Place
        let b: Place
        let gap: Double
    }

    let lines: [Line]
    /// Each line as the map draws it, in whole world units.
    let drawn: [[WorldCoordinate]]
    let links: [Link]
    /// Which lines connect to each other, by any number of links: each
    /// line's group.
    let groups: [Int]

    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How far a line's end may stand from another line and still join it:
    /// the bundled lines are drawn separately, and a branch's first point
    /// is a few metres off the main line's centre.
    static let joinReach = 60 * metre
    /// How far beyond the world's edge the lines are kept, so a line that
    /// leaves the map and comes back stays one.
    static let margin = 2_000 * metre

    /// The lines of `railways` that reach the world `frame` and `bounds`
    /// make, projected as the map projects them.
    init(railways: RealRailways, frame: RealWorldFrame, bounds: WorldBounds) {
        let region = WorldRegion(bounds: bounds)
        var lines: [Line] = []
        for line in railways.lines {
            let points = line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            guard points.count > 1 else { continue }
            let xs = points.map(\.x), ys = points.map(\.y)
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            guard maxX >= region.minX - Self.margin, minX <= region.maxX + Self.margin,
                  maxY >= region.minY - Self.margin, minY <= region.maxY + Self.margin else { continue }
            let path = WorldPath(points)
            guard path.points.count > 1 else { continue }
            lines.append(Line(id: lines.count, system: line.system.id, path: path, minX: minX, minY: minY, maxX: maxX, maxY: maxY))
        }
        self.lines = lines
        drawn = lines.map { line in line.path.points.map { WorldCoordinate(x: Int64($0.x.rounded()), y: Int64($0.y.rounded()), z: 0) } }

        // Each line's two ends, joined to the nearest place on another line
        // of its system within reach.
        var links: [Link] = []
        for line in lines {
            for along in [0, line.path.length] {
                let end = line.path.point(at: along)
                var best: (place: Place, gap: Double)?
                for other in lines where other.id != line.id && other.system == line.system {
                    guard let found = Self.nearest(to: end, on: other, within: Self.joinReach) else { continue }
                    if best == nil || found.distance < best!.gap {
                        best = (Place(line: other.id, along: found.along), found.distance)
                    }
                }
                if let best {
                    links.append(Link(a: Place(line: line.id, along: along), b: best.place, gap: best.gap))
                }
            }
        }
        self.links = links

        var groups = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while groups[index] != index { index = groups[index] }
            return index
        }
        for link in links {
            let a = root(link.a.line), b = root(link.b.line)
            if a != b { groups[max(a, b)] = min(a, b) }
        }
        self.groups = lines.indices.map(root)
    }

    /// The place on any line nearest `point` within `reach` world units,
    /// on a line of group `group` when one is given.
    func snap(_ point: WorldVector, within reach: Double, group: Int? = nil) -> Snap? {
        var best: Snap?
        for line in lines where group == nil || groups[line.id] == group {
            guard point.x >= line.minX - reach, point.x <= line.maxX + reach,
                  point.y >= line.minY - reach, point.y <= line.maxY + reach else { continue }
            guard let found = Self.nearest(to: point, on: line, within: best?.distance ?? reach) else { continue }
            if best == nil || found.distance < best!.distance {
                best = Snap(place: Place(line: line.id, along: found.along), point: line.path.point(at: found.along), distance: found.distance)
            }
        }
        return best
    }

    /// The way along the lines from `start` to `end`: the shortest, along
    /// lines and across the links between them; `nil` where no way joins
    /// them.
    func path(from start: Place, to end: Place) -> [WorldVector]? {
        // The places the way may turn at: each line's ends, the links'
        // places and the two ends asked for.
        var stops: [Place] = [start, end]
        for line in lines { stops += [Place(line: line.id, along: 0), Place(line: line.id, along: line.path.length)] }
        for link in links { stops += [link.a, link.b] }
        var index: [Place: Int] = [:]
        var unique: [Place] = []
        for stop in stops where index[stop] == nil {
            index[stop] = unique.count
            unique.append(stop)
        }
        var neighbours = [[(stop: Int, cost: Double)]](repeating: [], count: unique.count)
        var byLine: [Int: [Int]] = [:]
        for (number, stop) in unique.enumerated() { byLine[stop.line, default: []].append(number) }
        for (_, numbers) in byLine {
            let sorted = numbers.sorted { unique[$0].along < unique[$1].along }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let cost = unique[b].along - unique[a].along
                neighbours[a].append((b, cost))
                neighbours[b].append((a, cost))
            }
        }
        for link in links {
            guard let a = index[link.a], let b = index[link.b] else { continue }
            neighbours[a].append((b, link.gap))
            neighbours[b].append((a, link.gap))
        }

        // Dijkstra's shortest path; the stops are a few hundred at most.
        guard let from = index[start], let to = index[end] else { return nil }
        var distance = [Double](repeating: .infinity, count: unique.count)
        var previous = [Int?](repeating: nil, count: unique.count)
        var done = [Bool](repeating: false, count: unique.count)
        distance[from] = 0
        while true {
            var next: Int?
            for stop in unique.indices where !done[stop] && distance[stop] < .infinity {
                if next == nil || distance[stop] < distance[next!] { next = stop }
            }
            guard let current = next else { break }
            if current == to { break }
            done[current] = true
            for (stop, cost) in neighbours[current] where distance[current] + cost < distance[stop] {
                distance[stop] = distance[current] + cost
                previous[stop] = current
            }
        }
        guard distance[to] < .infinity else { return nil }
        var route = [to]
        while let before = previous[route[route.count - 1]] { route.append(before) }
        route.reverse()

        var points: [WorldVector] = [lines[start.line].path.point(at: start.along)]
        for (a, b) in zip(route, route.dropFirst()) {
            let p = unique[a], q = unique[b]
            if p.line == q.line {
                let line = lines[p.line].path
                let along = line.points(from: min(p.along, q.along), to: max(p.along, q.along))
                points += p.along <= q.along ? along : along.reversed()
            } else {
                points.append(lines[q.line].path.point(at: q.along))
            }
        }
        return points
    }

    /// How far along `line` its point nearest `point` is, if it is within
    /// `reach`.
    private static func nearest(to point: WorldVector, on line: Line, within reach: Double) -> (along: Double, distance: Double)? {
        let path = line.path
        var best: (along: Double, distance: Double)?
        for index in path.points.indices.dropLast() {
            let a = path.points[index], b = path.points[index + 1]
            guard point.x >= min(a.x, b.x) - reach, point.x <= max(a.x, b.x) + reach,
                  point.y >= min(a.y, b.y) - reach, point.y <= max(a.y, b.y) + reach else { continue }
            let along = b - a
            let squared = along.dot(along)
            let t = squared > 0 ? max(0, min(1, (point - a).dot(along) / squared)) : 0
            let away = (a + along * t - point).length
            if away <= (best?.distance ?? reach) {
                best = (path.distances[index] + t * (path.distances[index + 1] - path.distances[index]), away)
            }
        }
        return best
    }
}

/// A stretch of track traced along a real line: the edges to build, one
/// after another, and how far along they get before GameCore refuses one.
struct TracePlan {
    /// Every edge of the traced stretch, the first from the picked start
    /// and the last to the picked end.
    let stretches: [PlayerCommand.TrackStretch]
    /// The edges GameCore builds before it refuses one: all of them, or
    /// those before the one it refuses.
    let buildable: Int
    /// Why GameCore refuses the edge after ``buildable``, as the player
    /// reads it.
    let problem: String?

    var stopped: Bool { buildable < stretches.count }
}

extension GameSession {
    /// The steepest grade a traced stretch is laid at: a little under the
    /// game's 40 in 1,000 (``TrackProfile/maximumGrade``), so an edge
    /// between two of its heights, rounded to whole units, never exceeds
    /// it.
    static let traceGrade = 0.038

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
    func tracedWay(from start: WorldCoordinate, to end: WorldCoordinate, reach: Double) -> [WorldVector]? {
        guard let traces = realRailwayTraces else { return nil }
        let from = WorldVector(start.plan), to = WorldVector(end.plan)
        guard let first = traces.snap(from, within: reach),
              let last = traces.snap(to, within: reach, group: traces.groups[first.place.line]),
              let way = traces.path(from: first.place, to: last.place) else { return nil }
        return [from] + way + [to]
    }

    /// The traced stretch from `start` to `end` (decision 213): `nil`
    /// unless the tool traces and both ends are on real lines that join.
    /// On a copy of the world, with the ground read under the way; GameCore
    /// builds its edges one by one there to find the first it refuses.
    func tracePlan(from start: NetworkAnchor, to end: NetworkAnchor) -> TracePlan? {
        guard tracesRealRailway, var from = world.position(of: start, height: networkHeight),
              var to = world.position(of: end, height: networkHeight) else { return nil }
        // Generous: an end on existing track is up to a tap's reach from
        // the real line, and the way joins it there.
        let reach = Self.traceReach(NetworkBuilding.minimumSpacing * 2)
        guard let way = tracedWay(from: from, to: to, reach: reach) else { return nil }
        let path = WorldPath(way).smoothed()
        guard path.points.count > 1, path.length >= Double(NetworkBuilding.minimumSpacing) else { return nil }

        // The ground under the way, every 32 m: the tool's ground (decision
        // 124) for a new end, and the track's heights between.
        var draft = world
        let step = 32 * RealRailwayTraces.metre
        let samples = (0...Int((path.length / step).rounded(.up))).map { path.point(at: min(path.length, Double($0) * step)).plan }
        try? draft.readGround(under: samples, from: heights)
        if case .point = start, let position = draft.position(of: start, height: networkHeight) { from = position }
        if case .point = end, let position = draft.position(of: end, height: networkHeight) { to = position }

        let mapped = draft.ground.isMapped
        let height = Double(networkHeight)
        let planning = draft
        func ground(_ point: WorldVector) -> Double {
            Double(planning.groundHeight(at: point.plan) ?? 0) + height
        }
        func water(_ point: WorldVector) -> Bool {
            guard mapped else { return false }
            let plan = point.plan
            return planning.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }
        // An end on track keeps that track's height; a new end stands on
        // the ground, or as the tool sets it above.
        var levels: [TrackRise.Level] = []
        if case .point = start {} else { levels.append(TrackRise.Level(0...0, at: Double(from.z))) }
        if case .point = end {} else { levels.append(TrackRise.Level(path.length...path.length, at: Double(to.z))) }
        // Decision 279: along a real line over real ground, with the tool's
        // own choices (what the ground asks for, nothing raised), up on the
        // real line's viaducts and down in its tunnels: the TRA's, the High
        // Speed Rail's and the Alishan Forest Railway's.
        var carried: [TrackRise.Carried] = []
        if mapped, networkStructure == .automatic, networkHeight == 0, let traces = realRailwayTraces, let frame = RealWorldFrame(world: draft),
           let snap = traces.snap(WorldVector(from.plan), within: reach), let structures = railways?.structures {
            carried = structures.stretches(along: path, frame: frame, system: traces.lines[snap.place.line].system)
            // A new end stands where the tool puts it, and the track climbs
            // or falls from it to the real line's viaduct or tunnel.
            if !carried.isEmpty {
                if case .point = start { levels.append(TrackRise.Level(0...0, at: Double(from.z))) }
                if case .point = end { levels.append(TrackRise.Level(path.length...path.length, at: Double(to.z))) }
            }
        }
        guard let rise = TrackRise(path: path, ground: ground, water: water, levels: levels, grade: Self.traceGrade, carried: carried) else {
            return TracePlan(stretches: [], buildable: 0, problem: language.text(
                "The track cannot climb from one end to the other along this line within the steepest grade, 40‰.",
                "沿這段真實鐵路，從一端到另一端的高低差超過遊戲的坡度上限 40‰，鋪不上去。"
            ))
        }

        // Each end leaves the track there along it, where the tool joins
        // track (as one stretch does, decision 103).
        let ahead = path.point(at: min(path.length, 50 * RealRailwayTraces.metre)).plan
        let behind = path.point(at: max(0, path.length - 50 * RealRailwayTraces.metre)).plan
        var startDirection = path.tangent(at: 0)
        var endDirection = path.tangent(at: path.length)
        if networkFollowsTrack {
            if case .node(let id) = start, !draft.joiningDirections(at: id).isEmpty, let direction = draft.joiningDirection(at: id, toward: ahead) {
                startDirection = WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit
            }
            if case .track(let point) = start, let direction = draft.joiningDirection(at: point, toward: ahead) {
                startDirection = WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit
            }
            if case .node(let id) = end, !draft.joiningDirections(at: id).isEmpty, let direction = draft.joiningDirection(at: id, toward: behind) {
                endDirection = WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit.reversed
            }
            if case .track(let point) = end, let direction = draft.joiningDirection(at: point, toward: behind) {
                endDirection = WorldVector(x: Double(direction.dx), y: Double(direction.dy)).unit.reversed
            }
        }
        let plan = RealWorldDemo.TrackPlan(
            path, forced: [0, path.length], avoiding: [],
            start: (from.plan, startDirection), end: (to.plan, endDirection),
            rise: rise, structure: networkStructure
        )
        let last = plan.nodes.count - 1
        var stretches: [PlayerCommand.TrackStretch] = []
        for (index, curve) in plan.curves.enumerated() {
            let a = index == 0 ? from : WorldCoordinate(x: plan.nodes[index].point.x, y: plan.nodes[index].point.y, z: plan.heights[index])
            let b = index + 1 == last ? to : WorldCoordinate(x: plan.nodes[index + 1].point.x, y: plan.nodes[index + 1].point.y, z: plan.heights[index + 1])
            let surveyed = TrackGeometry(from: a, to: b, curve: curve).map(NetworkBuilding.surveyedPoints(of:)) ?? []
            stretches.append(PlayerCommand.TrackStretch(
                start: index == 0 ? start : .point(a.plan), end: index + 1 == last ? end : .point(b.plan),
                from: a, to: b, curve: curve, profile: .uniform, structure: networkStructure,
                ground: [a.plan, b.plan] + surveyed
            ))
        }

        // GameCore's answer, edge by edge, on the copy; an edge whose curve
        // turns tighter than the tool lays stops it first. Cash does not
        // stop it (decision 245): the preview weighs the whole price.
        draft = draft.pricingCopy()
        var built = 0
        var problem: String?
        var previous: TrackNodeID?
        for stretch in stretches {
            if let radius = Self.tightestRadius(of: stretch), radius < Self.traceMinimumRadius {
                problem = language.text(
                    "The real line turns too tightly here for the track (a curve of about \(Int((radius / RealRailwayTraces.metre).rounded())) m; the tool lays \(Int(Self.traceMinimumRadius / RealRailwayTraces.metre)) m or more).",
                    "這裡真實鐵路彎得太急（半徑約 \(Int((radius / RealRailwayTraces.metre).rounded())) 公尺，描線最小 \(Int(Self.traceMinimumRadius / RealRailwayTraces.metre)) 公尺），鋪不過去。"
                )
                break
            }
            do throws(GameError) {
                previous = try stretch.starting(at: previous).build(in: &draft, heights: heights).to
                built += 1
            } catch {
                problem = error.playerMessage(in: language)
                break
            }
        }
        return TracePlan(stretches: stretches, buildable: built, problem: problem)
    }
}

extension GameSession {
    /// The tightest curve a traced edge may have: 40 m, the Alishan Forest
    /// Railway's tightest (the sharpest real line the app has). GameCore
    /// has no curve radius (a stretch may turn up to 90° where it joins,
    /// decision 103); this only stops a trace where a kink in the real
    /// line's drawing, or a link between two lines, would bend the track
    /// into a hairpin. Measured as the reference's `radiusAtPoint` does
    /// (`Ci/`), at sixteenths along the edge.
    static let traceMinimumRadius = 40 * RealRailwayTraces.metre

    /// The tightest radius along `stretch`'s curve in world units; `nil`
    /// for a straight edge.
    static func tightestRadius(of stretch: PlayerCommand.TrackStretch) -> Double? {
        guard case .cubic(let c1, let c2) = stretch.curve else { return nil }
        let p0 = WorldVector(stretch.from.plan), p1 = WorldVector(c1), p2 = WorldVector(c2), p3 = WorldVector(stretch.to.plan)
        func point(_ t: Double) -> WorldVector {
            let u = 1 - t
            return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
        }
        var tightest = Double.infinity
        for step in 1..<16 {
            let a = point(Double(step - 1) / 16), b = point(Double(step) / 16), c = point(Double(step + 1) / 16)
            // The circle through three points: abc / 4·area (Heron).
            let ab = (b - a).length, bc = (c - b).length, ca = (a - c).length
            let twiceArea = abs((b - a).x * (c - a).y - (b - a).y * (c - a).x)
            guard twiceArea > 1e-9 else { continue }
            tightest = min(tightest, ab * bc * ca / (2 * twiceArea))
        }
        return tightest.isFinite ? tightest : nil
    }

    /// The traced stretch's preview (decision 213): the edges GameCore
    /// builds, their length and cost, and why the trace stops where it
    /// does; `nil` when the ends are not both on real lines that join, so
    /// the tool lays one stretch as usual.
    func tracePreview(from start: NetworkAnchor, to end: NetworkAnchor) -> (NetworkPreview, [WorldCoordinate])? {
        guard let plan = tracePlan(from: start, to: end) else { return nil }
        let points = plan.stretches.map { stretch in
            TrackGeometry(from: stretch.from, to: stretch.to, curve: stretch.curve)?.points ?? [stretch.from, stretch.to]
        }
        let built = Array(plan.stretches.prefix(plan.buildable))
        var draft = world.pricingCopy()
        var cost: Money?
        var command = PlayerCommand.buildTrackChain(built)
        // Decision 247: with double track on, the second track beside it;
        // its later: or where the real line is double.
        let decided = tracedDouble(built)
        var double: Result<DoubleChainPlan, TraceDoubleProblem>?
        if decided.double, !built.isEmpty {
            double = tracedDoublePlan(built, from: start, to: end, reachesEnd: !plan.stopped)
        }
        switch double {
        case .success(let found)?:
            draft = found.built
            command = found.command
            cost = Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
        case .failure?:
            break
        case nil:
            if !built.isEmpty, (try? apply(command, to: &draft)) != nil {
                cost = Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
            }
        }
        var shortfall = cost.flatMap { shortfallText($0, doing: command) }
        if case .failure(let problem)? = double { shortfall = problem.text }
        let length = built.compactMap { TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve)?.length }.reduce(0, +)
        let shown = built.isEmpty ? points.flatMap { $0 } : points.prefix(plan.buildable).flatMap { $0 }
        let first = plan.stretches.first, last = built.last
        let isJoined: (NetworkAnchor) -> Bool = { if case .point = $0 { false } else { true } }
        var preview = NetworkPreview(
            curve: first?.curve ?? .straight, profile: .uniform, points: shown, length: length,
            startHeight: first?.from.z ?? 0, endHeight: (last ?? first)?.to.z ?? 0,
            joinsStart: isJoined(start), joinsEnd: !plan.stopped && isJoined(end),
            cost: built.isEmpty ? nil : cost,
            problem: built.isEmpty ? (plan.problem ?? language.text("This stretch cannot be traced.", "這段無法描線。")) : shortfall,
            cleared: built.isEmpty ? [] : world.placedBuildings(clearedIn: draft)
        )
        preview.traced = built.count
        preview.tracedDouble = decided.real
        var second: [WorldCoordinate] = []
        if case .success(let found)? = double {
            second = found.parallelPoints
            preview.crossovers = found.crossoverPoints
            if shortfall == nil, found.outcome != .none {
                preview.crossoverNote = String(Self.crossoverText(found.outcome, in: language).drop { $0 == " " })
            }
        }
        if let real = decided.real, shortfall == nil {
            preview.crossoverNote = [Self.realTrackCountText(double: real, in: language), preview.crossoverNote].compactMap { $0 }.joined(separator: " ")
        }
        if plan.stopped, !built.isEmpty {
            preview.unbuilt = points.dropFirst(plan.buildable).flatMap { $0 }
            let stop = NetworkBuilding.distanceText(length, in: language)
            preview.traceNote = language.text(
                "The trace stops after \(stop): \(plan.problem ?? "")",
                "描到 \(stop) 處停下：\(plan.problem ?? "")"
            )
        }
        return (preview, second)
    }

    /// The traced stretch's `built` edges with a second track beside them
    /// (decision 247), on ``networkDoubleSide``, and a crossover at each
    /// end that joins track (the far end only when the trace gets there);
    /// or why not, as the player reads it.
    func tracedDoublePlan(
        _ built: [PlayerCommand.TrackStretch], from start: NetworkAnchor, to end: NetworkAnchor, reachesEnd: Bool
    ) -> Result<DoubleChainPlan, TraceDoubleProblem> {
        guard let parallel = parallelChain(beside: built.map(ChainSegment.init), side: networkDoubleSide, in: world) else {
            return .failure(TraceDoubleProblem(text: Self.noParallelText(in: language)))
        }
        do throws(GameError) {
            return .success(try planDoubleChain(
                main: built, run: [], parallel: parallel, platforms: [],
                wantsCrossover: (needsCrossover(start, in: world), reachesEnd && needsCrossover(end, in: world)), in: world
            ))
        } catch {
            return .failure(TraceDoubleProblem(text: error.playerMessage(in: language)))
        }
    }

    /// Builds the traced stretch (decision 213), as far as GameCore builds
    /// it, as one command: all of it or none. Its end becomes the start of
    /// the next stretch.
    func buildTracedTrack(from start: NetworkAnchor, to end: NetworkAnchor) -> Bool {
        guard let plan = tracePlan(from: start, to: end) else { return false }
        guard plan.buildable > 0 else {
            message = StatusMessage(kind: .failure, text: plan.problem ?? language.text("This stretch cannot be traced.", "這段無法描線。"))
            return true
        }
        let stretches = Array(plan.stretches.prefix(plan.buildable))
        var command = PlayerCommand.buildTrackChain(stretches)
        var crossovers = DoubleTrack.CrossoverOutcome.none
        let decided = tracedDouble(stretches)
        if decided.double {
            switch tracedDoublePlan(stretches, from: start, to: end, reachesEnd: !plan.stopped) {
            case .success(let found):
                command = found.command
                crossovers = found.outcome
            case .failure(let problem):
                message = StatusMessage(kind: .failure, text: problem.text)
                return true
            }
        }
        let built = perform(command) { _, before, world in
            let cost = Money(before.economy.balance.amount - world.economy.balance.amount)
            let length = stretches.compactMap { TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve)?.length }.reduce(0, +)
            let distance = NetworkBuilding.distanceText(length, in: language)
            var text = language.text(
                "Traced the real railway for \(distance) (\(stretches.count) pieces of track) for \(cost.moneyText).",
                "沿真實鐵路鋪了 \(distance)（\(stretches.count) 段），花費 \(cost.moneyText)。"
            )
            if let real = decided.real {
                text += " " + Self.realTrackCountText(double: real, in: language)
            }
            if case .buildDoubleTrackChain = command {
                text += language.text(" With a second track beside it.", "旁邊也鋪了第二條。") + Self.crossoverText(crossovers, in: language)
            }
            if plan.stopped, let problem = plan.problem {
                text += language.text(" It stops there: \(problem)", "在那裡停下：\(problem)")
            }
            return text
        }
        if let track = built?.track {
            networkStart = .node(track.to)
            networkEnd = nil
            playSound?(.track)
        }
        return true
    }

    /// The real line the tool would trace from the picked start to the
    /// picked end, or to the finger (decision 213): for the map to light
    /// up under the preview; empty when it does not trace.
    public var networkTracedWay: [WorldCoordinate] {
        guard tool == .network, networkMode == .build, tracesRealRailway, let start = networkStart,
              let from = world.position(of: start, height: networkHeight) else { return [] }
        let to: WorldCoordinate?
        if let end = networkEnd {
            to = world.position(of: end, height: networkHeight)
        } else {
            to = networkDragFinger.map { WorldCoordinate(x: $0.x, y: $0.y, z: 0) }
        }
        guard let to, let frame = RealWorldFrame(world: world) else { return [] }
        // Worked out once for each pair of points: the map reads it at
        // every redraw, and it is a shortest path along the real lines.
        let key = TracedWayKey(lines: RealRailwayTracesKey(frame: frame, bounds: world.bounds), from: from, to: to)
        if let memo = tracedWayMemo, memo.key == key { return memo.way }
        tracedWaysWorkedOut += 1
        let way = tracedWay(from: from, to: to, reach: Self.traceReach(NetworkBuilding.minimumSpacing * 2)).map {
            $0.dropFirst().dropLast().map { WorldCoordinate(x: Int64($0.x.rounded()), y: Int64($0.y.rounded()), z: 0) }
        } ?? []
        tracedWayMemo = (key, way)
        return way
    }

    /// Every real line on the map that the tool can trace, in world
    /// coordinates (decision 213), for the map's faint layer under the
    /// track; empty unless the tool traces.
    public var traceableRealLines: [[WorldCoordinate]] {
        guard tool == .network, networkMode == .build, tracesRealRailway, let traces = realRailwayTraces else { return [] }
        return traces.drawn
    }
}

/// What the real lines of a map were worked out for: where the map is and
/// how far it reaches (``GameSession/realRailwayTraces``).
struct RealRailwayTracesKey: Equatable {
    let frame: RealWorldFrame
    let bounds: WorldBounds
}

/// What ``GameSession/networkTracedWay`` was worked out for.
struct TracedWayKey: Equatable {
    let lines: RealRailwayTracesKey
    let from: WorldCoordinate
    let to: WorldCoordinate
}

extension PlayerCommand.TrackStretch {
    /// The stretch, starting at node `node` when one is given: an edge of a
    /// chain (``PlayerCommand/buildTrackChain(_:)``) starts at the node the
    /// edge before ended at.
    func starting(at node: TrackNodeID?) -> PlayerCommand.TrackStretch {
        guard let node else { return self }
        return PlayerCommand.TrackStretch(
            start: .node(node), end: end, from: from, to: to, curve: curve, profile: profile, structure: structure, ground: ground
        )
    }
}

extension NetworkBuilding {
    /// A traced length (decision 213): "850 m" under a kilometre, "12.3 km"
    /// from one.
    static func distanceText(_ units: Int64, in language: DisplayLanguage) -> String {
        let metres = Double(units) / Double(WorldCoordinate.unitsPerMetre)
        guard metres >= 1_000 else { return lengthText(units, in: language) }
        let tenths = Int((metres / 100).rounded())
        let text = "\(tenths / 10).\(tenths % 10)"
        return language.text("\(text) km", "\(text) 公里")
    }
}

/// Why a traced stretch's second track cannot be laid (decision 247), as
/// the player reads it.
struct TraceDoubleProblem: Error {
    let text: String
}

// MARK: - Single or double, as the real line is

// Decision 247, later: traced along the TRA, the stretch is single or
// double as the real line is there, from `tra_track_sections.json` (each
// section between two adjacent stations, `tracks` 1 or 2), unless the
// player chose with the "Double" switch. The whole stretch is one or the
// other (one command, one second track), double where half its length or
// more runs through double sections: the same half the source draws its
// own line between single and double with (`parallelFrac` ≥ 0.5).

extension GameSession {
    /// How near a traced stretch a TRA station stands for its sections to
    /// be looked at: 150 m.
    static let tracedStationReach = 150 * RealRailwayTraces.metre
    /// How far apart the places along a traced stretch lie that each find
    /// the section they are in: 100 m.
    static let tracedSectionStep = 100 * RealRailwayTraces.metre

    /// Whether the traced `built` edges get a second track beside them
    /// (`double`): as the player set the "Double" switch, once they have;
    /// until then as the real line is (``realDoubleTrack(along:)``,
    /// `real` is its answer), or as the switch is where the data says
    /// nothing.
    func tracedDouble(_ built: [PlayerCommand.TrackStretch]) -> (double: Bool, real: Bool?) {
        guard !networkDoubleChosen, !built.isEmpty, let real = realDoubleTrack(along: built) else { return (networkBuildsDouble, nil) }
        return (real, real)
    }

    /// Whether the TRA's real track is double along the traced `built`
    /// edges: each place ``tracedSectionStep`` apart is in the section
    /// whose two stations it lies most nearly between (the least detour
    /// from one station through it to the other); double where half the
    /// places or more are in double sections, single where half or more
    /// are in single ones. `nil` off the TRA, without the data, or where
    /// it knows too little of the stretch.
    func realDoubleTrack(along built: [PlayerCommand.TrackStretch]) -> Bool? {
        guard let railways, let data = railways.stationData, let frame = RealWorldFrame(world: world),
              let traces = realRailwayTraces else { return nil }
        let path = WorldPath(built.flatMap(\.geometryPoints).map { WorldVector($0.plan) })
        guard path.points.count > 1, path.length > 0,
              let snap = traces.snap(path.point(at: path.length / 2), within: RealRailwayTraces.joinReach),
              traces.lines[snap.place.line].system == Self.traSystem else { return nil }

        func key(_ name: String) -> String { name.replacingOccurrences(of: "台", with: "臺") }
        var stations: [String: WorldVector] = [:]
        for station in railways.stations where station.system.id == Self.traSystem {
            let point = WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude))
            if stations[key(station.chinese)] == nil { stations[key(station.chinese)] = point }
        }
        var sections: [(a: String, b: String, from: WorldVector, to: WorldVector, double: Bool)] = []
        for (pair, section) in data.trackSections.sorted(by: { $0.key < $1.key }) {
            let names = pair.split(separator: "|").map { key(String($0)) }
            guard names.count == 2, let from = stations[names[0]], let to = stations[names[1]] else { continue }
            sections.append((names[0], names[1], from, to, section.isDoubleTrack))
        }
        // The sections of the stations the stretch passes, or every
        // section for a stretch between two stations.
        let reach = Self.tracedStationReach
        let xs = path.points.map(\.x), ys = path.points.map(\.y)
        let near = Set(stations.compactMap { name, point -> String? in
            guard point.x >= (xs.min() ?? 0) - reach, point.x <= (xs.max() ?? 0) + reach,
                  point.y >= (ys.min() ?? 0) - reach, point.y <= (ys.max() ?? 0) + reach,
                  path.nearest(point).away <= reach else { return nil }
            return name
        })
        let candidates = near.isEmpty ? sections : sections.filter { near.contains($0.a) || near.contains($0.b) }

        let count = max(1, Int((path.length / Self.tracedSectionStep).rounded()))
        var double = 0, single = 0
        for index in 0..<count {
            let point = path.point(at: path.length * (Double(index) + 0.5) / Double(count))
            var best: (detour: Double, double: Bool)?
            for section in candidates {
                let span = (section.to - section.from).length
                let detour = (point - section.from).length + (point - section.to).length - span
                // Not beyond either station by more than the span itself.
                guard detour <= span, best == nil || detour < best!.detour else { continue }
                best = (detour, section.double)
            }
            switch best?.double {
            case true?: double += 1
            case false?: single += 1
            case nil: break
            }
        }
        if double * 2 >= count { return true }
        if single * 2 >= count { return false }
        return nil
    }

    /// The TRA's system in the bundled lines and stations.
    static let traSystem = "tra_sched"

    /// What the preview and the message say when the real line decided:
    /// "Double track, as the real railway is here."
    static func realTrackCountText(double: Bool, in language: DisplayLanguage) -> String {
        double
            ? language.text("Double track, as the real railway is here.", "照真實鐵路鋪成複線。")
            : language.text("Single track, as the real railway is here.", "照真實鐵路鋪成單線。")
    }
}
