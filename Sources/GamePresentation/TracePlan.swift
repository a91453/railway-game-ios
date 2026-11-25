import Foundation
import GameCore

// Planning a traced stretch edge by edge (decision 213): what GameCore
// builds along the real line and where it stops.

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
    /// ``problem`` in the pill's one short line (decision 803, continued).
    var brief: String? = nil
    /// For each platform span asked for, the index of its stretch: one
    /// edge from one end of the span to the other (decision 351); `nil`
    /// where the span is not one edge.
    var platformStretches: [Int?] = []
    /// Decision 468: the track already laid along the way that the trace
    /// skips, each with the number of stretches before it, and its centre
    /// line.
    var existing: [(after: Int, points: [WorldCoordinate])] = []
    /// How long that track is, in world units.
    var existingLength = 0.0
    /// The node the trace ends at where it ends on track already laid.
    var endNode: TrackNodeID?
    /// Decision 468: the trace stops after all its stretches, where track
    /// already laid leaves no room to go on.
    var stopsAfter = false
    /// Decision 513: where no grade reaches from one end to the other
    /// (``TrackRise`` finds none, so there are no stretches), the way
    /// along the real line, each point at the height the tool would lay
    /// it on the ground, for the card to show.
    var refusedWay: [WorldCoordinate] = []
    /// Decision 521's second sequel: the preview copy with exactly the
    /// first ``buildable`` stretches built on it, as the trace found them,
    /// for the preview to price instead of building the chain again; `nil`
    /// where GameCore refused an edge (a refused edge may leave its first
    /// node in the copy). Decision 521's fourth sequel: a trace put
    /// together from pieces builds them all on one copy, so it has one too.
    var built: GameWorld?
    /// The edges of those stretches on ``built``, in order; empty where it
    /// is `nil`.
    var builtEdges: [TrackEdgeID] = []

    var stopped: Bool { buildable < stretches.count || stopsAfter }
}

extension GameSession {
    /// Decision 400 A.8: `onGround`, all of it on the ground, as the game's
    /// stations are (decision 132), whatever the tool's height and
    /// structure and the real line's tunnels and viaducts. Decision 856:
    /// with `onRealViaduct` too, up on the real line's long viaducts
    /// (still never in its tunnels), and `nil` unless each of `platforms`
    /// stands on one: a real station bought where the real one is
    /// elevated (Jiantan) stands on the viaduct, as a traced one does.
    ///
    /// Decision 401's sequel: `system`, the real line's system, sets the
    /// tightest curve (``traceMinimumRadius(ofSystem:)``; the line at the
    /// start's where none is given).
    ///
    /// Decision 521's fourth sequel: GameCore builds the edges on `base`
    /// where one is given (a preview copy with the pieces of the trace
    /// before this one built on it, ``traceAlong(from:to:)``), else on a
    /// preview copy of the world; the way is planned on the world either
    /// way.
    func tracePlan(
        from start: NetworkAnchor, to end: NetworkAnchor, along given: [WorldVector]? = nil, platforms: [(WorldVector, WorldVector)] = [],
        onGround: Bool = false, onRealViaduct: Bool = false, system: String? = nil, buildingOn base: GameWorld? = nil
    ) -> TracePlan? {
        let followsViaducts = onGround && onRealViaduct
        let networkHeight = onGround ? 0 : self.networkHeight
        let networkStructure = onGround ? TrackStructure.automatic : self.networkStructure
        guard given != nil || tracesRealRailway, var from = world.position(of: start, height: networkHeight),
              var to = world.position(of: end, height: networkHeight) else { return nil }
        // Generous: an end on existing track is up to a tap's reach from
        // the real line, and the way joins it there.
        let reach = Self.traceReach(NetworkBuilding.minimumSpacing * 2)
        guard let way = given ?? tracedWay(from: from, to: to, reach: reach, leaving: start, arriving: end) else { return nil }
        let path = WorldPath(way).smoothed()
        guard path.points.count > 1, path.length >= Double(NetworkBuilding.minimumSpacing) else { return nil }
        let spans = platforms.map { span -> ClosedRange<Double> in
            let a = path.project(span.0), b = path.project(span.1)
            return min(a, b)...max(a, b)
        }

        // The ground under the way, every 32 m: the tool's ground (decision
        // 124) for a new end, and the track's heights between.
        var draft = world
        let step = 32 * RealRailwayTraces.metre
        let samples = (0...Int((path.length / step).rounded(.up))).map { path.point(at: min(path.length, Double($0) * step)).plan }
        try? draft.readGround(under: samples, from: heights)
        if case .point = start, let position = draft.position(of: start, height: networkHeight) { from = position }
        if case .point = end, let position = draft.position(of: end, height: networkHeight) { to = position }

        let mapped = draft.ground.isMapped
        // Decision 974: on flat ground (decision 198) the track the tool
        // lays itself still goes over the map's rivers, lakes and sea on a
        // bridge, level everywhere else.
        let bridgesWater = !mapped && networkStructure == .automatic
        let height = Double(networkHeight)
        let planning = draft
        func ground(_ point: WorldVector) -> Double {
            Double(planning.groundHeight(at: point.plan) ?? 0) + height
        }
        func cell(_ point: WorldVector) -> CellPosition {
            let plan = point.plan
            return CellPosition(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }
        // Decision 974: the whole of each of the real line's bridges that
        // crosses the map's water, which marks only the river's channel
        // (a 64 m cell of the Lanyang River's kilometre).
        var bridgedCells: Set<CellPosition> = []
        if bridgesWater, let traces = realRailwayTraces, let frame = RealWorldFrame(world: draft),
           let snap = traces.snap(WorldVector(from.plan), within: reach), let structures = railways?.structures {
            for stretch in structures.stretches(along: path, frame: frame, system: traces.lines[snap.place.line].system) where stretch.kind == .bridge {
                let along = Array(stride(from: max(0, stretch.range.lowerBound), through: min(path.length, stretch.range.upperBound), by: TrackRise.spacing))
                let cells = along.map { cell(path.point(at: $0)) }
                if cells.contains(where: { planning.terrain.isWater(row: $0.row, column: $0.column) }) { bridgedCells.formUnion(cells) }
            }
        }
        func water(_ point: WorldVector) -> Bool {
            guard mapped || bridgesWater else { return false }
            let at = cell(point)
            return planning.terrain.isWater(row: at.row, column: at.column) || bridgedCells.contains(at)
        }
        // An end on track keeps that track's height; a new end stands near
        // the ground, or as the tool sets it above.
        var levels: [TrackRise.Level] = []
        if case .point = start {} else { levels.append(TrackRise.Level(0...0, at: Double(from.z))) }
        if case .point = end {} else { levels.append(TrackRise.Level(path.length...path.length, at: Double(to.z))) }
        // Decision 279: along a real line over real ground, with the tool's
        // own choices (what the ground asks for, nothing raised), up on the
        // real line's viaducts and down in its tunnels: the TRA's, the High
        // Speed Rail's, the Alishan Forest Railway's and the metros' and
        // light rails'.
        var carried: [TrackRise.Carried] = []
        var carriedEnds = (start: false, end: false)
        var looseEnds = (start: false, end: false)
        if mapped, followsViaducts || (!onGround && networkStructure == .automatic && (networkHeight == 0 || demoKeepsRealStructures)),
           let traces = realRailwayTraces, let frame = RealWorldFrame(world: draft),
           let snap = traces.snap(WorldVector(from.plan), within: reach), let structures = railways?.structures {
            carried = structures.stretches(along: path, frame: frame, system: traces.lines[snap.place.line].system)
            if followsViaducts {
                // Decision 856: only the long viaducts, each platform on one.
                carried = carried.filter { $0.kind == .bridge && $0.isLong }
                guard !spans.isEmpty, spans.allSatisfy({ span in
                    carried.contains { $0.range.contains(span.lowerBound) && $0.range.contains(span.upperBound) }
                }) else { return nil }
            }
            // A new end on a long viaduct or in a long tunnel (a metro's
            // station over the street or under it, laid a station at a
            // time) stands on it, as the real line does, the structure
            // reaching past it; elsewhere it stands where the tool puts it,
            // and the track climbs or falls from it to the real line's
            // viaduct or tunnel.
            // Decision 513: how long the real structure is, not the part
            // of it along the way (a short trace ends in a long tunnel).
            let on = RealRailStructures.sampleSpacing
            for (index, stretch) in carried.enumerated() where stretch.isLong {
                var range = stretch.range
                if case .point = start, range.lowerBound <= on {
                    range = -TrackRise.carriedInset...range.upperBound
                    carriedEnds.start = true
                }
                if case .point = end, range.upperBound >= path.length - on {
                    range = range.lowerBound...path.length + TrackRise.carriedInset
                    carriedEnds.end = true
                }
                carried[index] = TrackRise.Carried(range: range, kind: stretch.kind, length: stretch.length)
            }
        }
        // Decision 513: a new end elsewhere stands near where the tool puts
        // it, on an embankment or in a cutting as the track between does
        // (``TrackRise/surfaceBand``), at the height the grade lays it:
        // the ground the game reads beside a real tunnel's mouth or a
        // bridge's end is the hillside or the bank, steeper than the real
        // line, and an end held to it left the track no grade to it. On
        // the ground (decision 400 A.8), as before.
        if !onGround {
            let band = TrackRise.surfaceBand
            if case .point = start, !carriedEnds.start {
                levels.append(TrackRise.Level(0...0, from: Double(from.z) + band.low, to: Double(from.z) + band.high))
                looseEnds.start = true
            }
            if case .point = end, !carriedEnds.end {
                levels.append(TrackRise.Level(path.length...path.length, from: Double(to.z) + band.low, to: Double(to.z) + band.high))
                looseEnds.end = true
            }
        }
        // Decision 513: the player's trace level at the real line's
        // stations, as the demo's platforms are; a station on a real
        // viaduct or in a real tunnel stands on it or in it, as above.
        // Decision 752: one on a long real viaduct or in a long real
        // tunnel is laid level too, at a height the structure allows
        // (``tracedStationLevel``): left out, the track over it climbed and
        // fell with the ground in short edges, and no platform could be
        // put there (Qiyan on the Tamsui Line).
        let levelSpans = !platforms.isEmpty ? spans : tracedStationSpans(along: path, system: system)
        // Decision 515: a real mountain line climbs as steeply as mountain
        // track may.
        let lineSystem = system ?? realRailwayTraces.flatMap { traces in
            traces.snap(WorldVector(from.plan), within: reach).map { traces.lines[$0.place.line].system }
        }
        let grade = Self.traceGrade(ofSystem: lineSystem)
        let climbs = grade > Self.traceGrade
        // Decision 974: on flat ground, over the water or, where no grade
        // reaches a bridge (an end on track at the water's edge), level
        // as before; never under it, as flat ground has no tunnels.
        func rising(_ levels: [TrackRise.Level]) -> TrackRise? {
            let over = TrackRise(path: path, ground: ground, water: water, levels: levels, grade: grade, carried: carried)
            guard bridgesWater else { return over }
            if let over, !zip(over.heights, over.ground).contains(where: { $0 < $1 }) { return over }
            return TrackRise(path: path, ground: ground, water: { _ in false }, levels: levels, grade: grade, carried: carried)
        }
        guard var rise = rising(levels) else {
            var refused = TracePlan(stretches: [], buildable: 0, problem: climbs ? language.text(
                "The track cannot climb from one end to the other along this line within the steepest grade of mountain track, 70‰.",
                "沿這段真實鐵路，從一端到另一端的高低差超過登山軌道的坡度上限 70‰，鋪不上去。"
            ) : language.text(
                "The track cannot climb from one end to the other along this line within the steepest grade, 40‰.",
                "沿這段真實鐵路，從一端到另一端的高低差超過遊戲的坡度上限 40‰，鋪不上去。"
            ))
            refused.brief = language.text("Too steep along this line", "沿線太陡，鋪不上去")
            refused.refusedWay = [from] + path.points.dropFirst().dropLast().map {
                WorldCoordinate(x: Int64($0.x.rounded()), y: Int64($0.y.rounded()), z: Int64(ground($0).rounded()))
            } + [to]
            return refused
        }
        // Decision 351: each platform level, between the heights the track
        // would have along it.
        if !levelSpans.isEmpty {
            let flat = levelSpans.map { span in
                let along = Array(stride(from: span.lowerBound, through: span.upperBound, by: TrackRise.spacing)) + [span.upperBound]
                let heights = along.map { rise.height(at: $0) }
                let level = TrackRise.Level(span, from: heights.min() ?? 0, to: heights.max() ?? 0)
                guard platforms.isEmpty, let structure = carried.first(where: { $0.isLong && $0.range.overlaps(span) }) else { return level }
                return Self.tracedStationLevel(
                    level, on: structure, ground: along.filter { structure.range.contains($0) }.map { ground(path.point(at: $0)) }
                )
            }
            if let levelled = rising(levels + flat) {
                rise = levelled
            }
        }
        if carriedEnds.start || looseEnds.start { from = WorldCoordinate(x: from.x, y: from.y, z: rise.node(at: 0)) }
        if carriedEnds.end || looseEnds.end { to = WorldCoordinate(x: to.x, y: to.y, z: rise.node(at: path.length)) }

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
        let forced: [Double] = [0, path.length] + levelSpans.flatMap { span -> [Double] in [span.lowerBound, span.upperBound] }
        // Decision 974: each bridge over water on flat ground, a node at
        // each end.
        let bridges: [ClosedRange<Double>] = bridgesWater ? Self.flatWaterBridges(rise, along: path, water: water, forced: forced, keepOut: levelSpans) : []
        let bridgeEnds: [Double] = bridges.flatMap { bridge -> [Double] in [bridge.lowerBound, bridge.upperBound] }
        let plan = RealWorldDemo.TrackPlan(
            path, forced: forced + bridgeEnds, avoiding: levelSpans,
            start: (from.plan, startDirection), end: (to.plan, endDirection),
            rise: rise, structure: networkStructure
        )
        let last = plan.nodes.count - 1
        // Decision 970: the real line's own gauge (the forest railway's
        // 762 mm, the high-speed railway's 1,435), unless the player chose
        // one.
        let gauge = networkGauge ?? lineSystem.flatMap(TrackGauge.ofRealLine)
        var stretches: [PlayerCommand.TrackStretch] = []
        // Decision 973: on a mountain line the heights are laid at
        // ``mountainTraceGrade`` along the way, but an edge's curve is a
        // little shorter than its piece of the way (it cuts the drawing's
        // wiggles), and one that came out over GameCore's 70‰ stopped the
        // trace as too steep. Such an edge's far node is lowered (or
        // raised) to what its own length climbs, and the next edges make
        // it up.
        var lifted: Int64?
        for (index, curve) in plan.curves.enumerated() {
            let a = index == 0 ? from : WorldCoordinate(x: plan.nodes[index].point.x, y: plan.nodes[index].point.y, z: lifted ?? plan.heights[index])
            var b = index + 1 == last ? to : WorldCoordinate(x: plan.nodes[index + 1].point.x, y: plan.nodes[index + 1].point.y, z: plan.heights[index + 1])
            lifted = nil
            if climbs, index + 1 != last, index > 0, plan.heights[index] == plan.heights[index + 1] {
                // A level stretch (a station's) stays level.
                b = WorldCoordinate(x: b.x, y: b.y, z: a.z)
                if b.z != plan.heights[index + 1] { lifted = b.z }
            } else if climbs, index + 1 != last, let steepest = TrackGeometry(from: a, to: b, curve: curve)?.steepestGrade, steepest.run > 0 {
                let ratio = abs(Double(steepest.rise)) / Double(steepest.run)
                if ratio > Self.mountainEdgeGrade {
                    let rise = Double(b.z - a.z) * Self.mountainEdgeGrade / ratio
                    b = WorldCoordinate(x: b.x, y: b.y, z: a.z + Int64(rise.rounded(.towardZero)))
                    lifted = b.z
                }
            }
            let geometry = TrackGeometry(from: a, to: b, curve: curve)
            let surveyed = geometry.map(NetworkBuilding.surveyedPoints(of:)) ?? []
            // Decision 515: on a mountain line, only what is steeper than
            // the game's grade is mountain track.
            let steep = climbs && geometry.map { !$0.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) } ?? false
            // Decision 974: a bridge within one over water on flat ground,
            // both ends above the ground (a bridge stands at or above it,
            // and the grade between them is straight).
            let bridged = !bridges.isEmpty && Self.bridgesFlatWater(
                from: plan.distances[index], to: plan.distances[index + 1], heights: (a, b), bridges: bridges, in: planning
            )
            stretches.append(PlayerCommand.TrackStretch(
                start: index == 0 ? start : .point(a.plan), end: index + 1 == last ? end : .point(b.plan),
                from: a, to: b, curve: curve, profile: .uniform, structure: bridged ? .bridge : networkStructure,
                ground: [a.plan, b.plan] + surveyed, mountain: steep, gauge: gauge
            ))
        }

        // GameCore's answer, edge by edge, on the copy; an edge whose curve
        // turns tighter than the tool lays stops it first. Cash does not
        // stop it (decision 245): the preview weighs the whole price.
        var copy: GameWorld
        if var base {
            // The same ground read in as on the draft, all at once: read a
            // stretch at a time, it took longer to build on.
            try? base.readGround(under: samples, from: heights)
            copy = base
        } else {
            copy = draft.trackPreviewCopy()
        }
        var built = 0
        var builtEdges: [TrackEdgeID] = []
        var problem: String?
        var brief: String?
        var previous: TrackNodeID?
        var refused = false
        let tightest = Self.traceMinimumRadius(ofSystem: lineSystem)
        for (index, stretch) in stretches.enumerated() {
            if let radius = Self.tightestRadius(of: stretch), radius < tightest {
                // Decision 972: where the way turns back on itself (two
                // real lines that meet facing the same way, as the
                // North-Link Line and the Su'ao branch do at Su'aoxin),
                // said as that.
                let reach = 30 * RealRailwayTraces.metre
                let turnsBack = stride(from: plan.distances[index], through: plan.distances[index + 1], by: 10 * RealRailwayTraces.metre).contains { along in
                    path.tangent(at: max(0, along - reach)).angle(to: path.tangent(at: min(path.length, along + reach))) > 2 * Double.pi / 3
                }
                if radius < Self.reversalRadius, turnsBack {
                    problem = language.text(
                        "The real line turns back here: trains reverse at this place, and one stretch of track cannot. Trace it as two stretches: first to the station where it turns back, then on from that station.",
                        "真實鐵路在這裡要折返，列車是在這裡調頭的，一段軌道描不過去。請分兩段描：先描到折返處的車站，再從那個車站往下描。"
                    )
                    brief = language.text("The real line turns back here", "真實鐵路在這裡要折返")
                    break
                }
                problem = language.text(
                    "The real line turns too tightly here for the track (a curve of about \(Int((radius / RealRailwayTraces.metre).rounded())) m; the tool lays \(Int(tightest / RealRailwayTraces.metre)) m or more).",
                    "這裡真實鐵路彎得太急（半徑約 \(Int((radius / RealRailwayTraces.metre).rounded())) 公尺，描線最小 \(Int(tightest / RealRailwayTraces.metre)) 公尺），鋪不過去。"
                )
                brief = language.text("The real line bends too tightly here", "真實鐵路在這裡彎太急")
                break
            }
            let next = stretch.starting(at: previous)
            do throws(GameError) {
                let edge = try next.build(in: &copy, heights: heights)
                previous = edge.to
                builtEdges.append(edge.edge)
                built += 1
            } catch {
                // Decision 513: which check, where GameCore's error covers
                // several; asked of the world before the trace, as a
                // refused stretch may leave its first node in the copy.
                // Decision 515: mountain track's own limit.
                problem = stretch.mountain && error == .trackTooSteep ? language.text(
                    "That track would be too steep. Mountain track may climb or fall at most 70 in 1000.",
                    "這段軌道太陡了。登山軌道的坡度最多 70‰。"
                ) : error.playerMessage(building: next, in: planning, heights: heights, language: language)
                brief = stretch.mountain && error == .trackTooSteep ? GameError.trackTooSteep.trackBrief(in: language)
                    : error.trackBrief(building: next, in: planning, heights: heights, language: language)
                refused = true
                break
            }
        }
        var found = TracePlan(stretches: stretches, buildable: built, problem: problem, brief: brief)
        if !refused {
            found.built = copy
            found.builtEdges = builtEdges
        }
        found.platformStretches = spans.map { span in
            plan.distances.indices.dropLast().first {
                abs(plan.distances[$0] - span.lowerBound) < 1 && abs(plan.distances[$0 + 1] - span.upperBound) < 1
            }
        }
        return found
    }
}
