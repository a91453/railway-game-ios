import GameCore

// A platform on a grade, levelled (ARCHITECTURE decision 190). A platform
// stands on level track only (decision 164), and on a real-world map the
// ground (Copernicus DSM, to the metre, buildings and all) makes most
// stretches of an ordinary station spacing climb or fall a little: 2 to 5 m
// over 500 m, a grade of a few per mille. The player who taps such track
// for a platform has it levelled: the edge is laid again as three, from its
// ends to the ends of the platform's stretch and between them level, at the
// track's height at the middle of the stretch, the two outer edges taking
// the grade up (eased, as the network tool eases it). Built from GameCore's
// own commands on a copy of the world, as the platform track is
// (`PlatformTrack.swift`): the old edge removed
// (`GameWorld.removeTrackEdge(_:)`), a node at each end of the stretch, the
// edges built as one (`GameWorld.buildTrackEdges(_:)`); so the player pays
// the new edges' price and GameCore refuses what it always refuses (a train
// on the edge, another platform on it, an outer edge steeper than 40‰, too
// little money). GameCore's split (`GameWorld.split`) is internal and splits
// level edges only, so a curve is cut here by de Casteljau's rule; neither
// reference has such a tool: native.

/// A stretch of an edge a platform would take, levelled: the edge laid again
/// in up to three edges, the middle one level.
public struct PlatformLevelling: Hashable, Sendable {
    /// The edge as it is, and the stretch the platform would take, moved
    /// to an end of the edge where it came within a split's least piece of
    /// it.
    let edge: TrackEdgeID
    let start: Int64
    let end: Int64
    /// The edges to build in order: before the stretch (if it does not
    /// start at the edge's start), the stretch, after it (if it does not
    /// end at the edge's end).
    let legs: [Leg]
    /// The new nodes at the stretch's ends; `nil` where it reaches an end
    /// of the edge, whose node it uses.
    let stretchStart: WorldCoordinate?
    let stretchEnd: WorldCoordinate?
    let structure: TrackStructure
    /// Which of ``legs`` is the level one.
    let levelLeg: Int

    struct Leg: Hashable, Sendable {
        let from: WorldCoordinate
        let to: WorldCoordinate
        let curve: TrackCurve
        let profile: TrackProfile
    }
}

/// Why a stretch cannot be levelled before any game rule.
enum PlatformLevellingProblem: Error {
    /// The edge is gone.
    case missing
    /// The platform takes the whole edge, so no level stretch can be cut
    /// from it without moving its end nodes.
    case wholeEdge
    /// A curve too short or too sharp to cut.
    case cannotCut

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .missing:
            language.text("That track is gone. Tap the track again.", "那段軌道已經不在了。請重新點選軌道。")
        case .wholeEdge:
            language.text(
                "This track is too short to level a platform's length of it: lay a longer stretch, or lay this one level.",
                "這段軌道太短，無法把月台那一段整平：請鋪長一點的軌道，或把這段鋪成水平。"
            )
        case .cannotCut:
            language.text(
                "This curve cannot be cut there to level the platform's stretch: try a straighter place.",
                "這段彎道無法在那裡切開整平：請換一個比較直的地方。"
            )
        }
    }
}

extension PlatformLevelling {
    /// The cubic from `p0` to `p3` pulled by `c1` and `c2`, cut at `t`:
    /// the two parts' control points and the point between them, by de
    /// Casteljau's rule.
    static func cut(
        _ p0: (Double, Double), _ c1: (Double, Double), _ c2: (Double, Double), _ p3: (Double, Double), at t: Double
    ) -> (first: [(Double, Double)], second: [(Double, Double)]) {
        func lerp(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
        }
        let a = lerp(p0, c1), b = lerp(c1, c2), c = lerp(c2, p3)
        let d = lerp(a, b), e = lerp(b, c)
        let m = lerp(d, e)
        return ([p0, a, d, m], [m, e, c, p3])
    }

    /// The parameter of the cubic at `distance` along it, of `length` as
    /// GameCore measures it, by the curve's own length sampled finely.
    static func parameter(
        _ p0: (Double, Double), _ c1: (Double, Double), _ c2: (Double, Double), _ p3: (Double, Double),
        at distance: Int64, of length: Int64
    ) -> Double {
        let samples = 1_024
        func point(_ t: Double) -> (Double, Double) {
            let u = 1 - t
            let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
            return (w0 * p0.0 + w1 * c1.0 + w2 * c2.0 + w3 * p3.0, w0 * p0.1 + w1 * c1.1 + w2 * c2.1 + w3 * p3.1)
        }
        var lengths = [0.0]
        var previous = p0
        for step in 1...samples {
            let here = point(Double(step) / Double(samples))
            let dx = here.0 - previous.0, dy = here.1 - previous.1
            lengths.append(lengths[lengths.count - 1] + (dx * dx + dy * dy).squareRoot())
            previous = here
        }
        let target = lengths[samples] * Double(distance) / Double(max(1, length))
        var low = 0, high = samples
        while high - low > 1 {
            let middle = (low + high) / 2
            if lengths[middle] < target { low = middle } else { high = middle }
        }
        let span = lengths[high] - lengths[low]
        let fraction = span > 0 ? (target - lengths[low]) / span : 0
        return (Double(low) + fraction) / Double(samples)
    }
}

extension GameSession {
    /// How the stretch from `start` to `end` of edge `edge` would be
    /// levelled for a platform (see the file's header), or why it cannot.
    func platformLevelling(of edge: TrackEdgeID, from start: Int64, to end: Int64, in world: GameWorld)
        -> Result<PlatformLevelling, PlatformLevellingProblem>
    {
        guard let current = world.network.edge(edge), let geometry = world.trackGeometry(of: edge),
              let a = world.network.node(current.from)?.position, let b = world.network.node(current.to)?.position
        else { return .failure(.missing) }
        // Each new piece at least a split's least piece long: a stretch
        // nearer an end than that moves to it, its length kept.
        let piece = GameWorld.minimumSplitPiece
        let length = end - start
        var start = start, end = end
        if start < piece {
            start = 0
            end = min(length, current.length)
        }
        if current.length - end < piece {
            end = current.length
            start = max(0, end - length)
            if start < piece { start = 0 }
        }
        guard start > 0 || end < current.length else { return .failure(.wholeEdge) }
        // The level: the track's height at the middle of the stretch, or
        // the height of the edge's end it reaches.
        let height = start == 0 ? a.z : end == current.length ? b.z : geometry.height(at: (start + end) / 2)

        // The plan points of the cut, and each leg's curve.
        var plans: [(from: PlanPoint, to: PlanPoint, curve: TrackCurve)] = []
        switch current.curve {
        case .straight:
            var points = [a.plan]
            if start > 0 { points.append(geometry.location(at: start).position.plan) }
            if end < current.length { points.append(geometry.location(at: end).position.plan) }
            points.append(b.plan)
            for index in 1..<points.count {
                plans.append((points[index - 1], points[index], .straight))
            }
        case .cubic(let c1, let c2):
            func double(_ point: PlanPoint) -> (Double, Double) { (Double(point.x), Double(point.y)) }
            func plan(_ point: (Double, Double)) -> PlanPoint {
                PlanPoint(x: Int64(point.0.rounded()), y: Int64(point.1.rounded()))
            }
            let p0 = double(a.plan), q1 = double(c1), q2 = double(c2), p3 = double(b.plan)
            var pieces: [[(Double, Double)]] = []
            var rest = [p0, q1, q2, p3]
            var done = 0.0
            for (distance, cuts) in [(start, start > 0), (end, end < current.length)] where cuts {
                let t = PlatformLevelling.parameter(p0, q1, q2, p3, at: distance, of: current.length)
                let local = (t - done) / (1 - done)
                guard local > 0, local < 1 else { return .failure(.cannotCut) }
                let parts = PlatformLevelling.cut(rest[0], rest[1], rest[2], rest[3], at: local)
                pieces.append(parts.first)
                rest = parts.second
                done = t
            }
            pieces.append(rest)
            for piece in pieces {
                plans.append((plan(piece[0]), plan(piece[3]), .cubic(plan(piece[1]), plan(piece[2]))))
            }
        }
        let levelLeg = start > 0 ? 1 : 0
        var legs: [PlatformLevelling.Leg] = []
        for (index, plan) in plans.enumerated() {
            let fromZ = index == 0 ? a.z : height
            let toZ = index == plans.count - 1 ? b.z : height
            let from = WorldCoordinate(x: plan.from.x, y: plan.from.y, z: fromZ)
            let to = WorldCoordinate(x: plan.to.x, y: plan.to.y, z: toZ)
            var profile = TrackProfile.uniform
            // The grade eased into and out of, as the network tool eases it
            // (decision 164), where that keeps it within the steepest.
            if networkEasesGrade, fromZ != toZ, let length = TrackGeometry(from: from, to: to, curve: plan.curve)?.length {
                let eased = TrackProfile(startTransition: length / 4, endTransition: length / 4)
                if let easedGeometry = TrackGeometry(from: from, to: to, curve: plan.curve, profile: eased),
                   easedGeometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) {
                    profile = eased
                }
            }
            legs.append(PlatformLevelling.Leg(from: from, to: to, curve: plan.curve, profile: profile))
        }
        guard legs.allSatisfy({ $0.from.plan != $0.to.plan }) else { return .failure(.cannotCut) }
        return .success(PlatformLevelling(
            edge: edge, start: start, end: end, legs: legs,
            stretchStart: start > 0 ? legs[levelLeg].from : nil,
            stretchEnd: end < current.length ? legs[levelLeg].to : nil,
            // Track on the ground takes what the ground asks for once its
            // height changes (decision 124); one carried keeps its carrier.
            structure: current.structure == .surface ? .automatic : current.structure,
            levelLeg: levelLeg
        ))
    }

    /// Lays `levelling` in `world`: the old edge removed, the new nodes and
    /// edges built as one. Returns the level edge. All or nothing in the
    /// caller's copy.
    func build(_ levelling: PlatformLevelling, in world: inout GameWorld) throws(GameError) -> TrackEdgeID {
        guard let old = world.network.edge(levelling.edge) else { throw .unknownTrackEdge(levelling.edge) }
        // What the old edge joined at its ends, to check the new ones join
        // the same.
        let fromExits = Set(world.network.node(old.from)?.end(of: old.id)?.exits ?? [])
        let toExits = Set(world.network.node(old.to)?.end(of: old.id)?.exits ?? [])
        // A train whose way runs along it, or a line's chosen path along it,
        // would lose it: refused as a split refuses them.
        if let train = world.trains.first(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == old.id { return true }
            return train.trailEdges.contains(old.id) || train.movement.remainingEdges.contains(old.id)
                || train.reservation.contains { if case .span(let span) = $0 { span.edge == old.id } else { false } }
        }) {
            throw .trackReserved(train.id)
        }
        if let line = world.lines.first(where: { line in
            ([line.routePreferences] + line.patterns.map(\.routePreferences)).joined().contains { route in
                route.platform.edge == old.id || route.tracks.contains { $0.edge == old.id }
            }
        }) {
            throw .trackEdgeInLineRoute(line.id)
        }
        // Decision 124: the ground under the new track read in first.
        let surveyed = levelling.legs.compactMap { TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve, profile: $0.profile) }
            .flatMap(NetworkBuilding.surveyedPoints(of:))
        try world.readGround(under: levelling.legs.flatMap { [$0.from.plan, $0.to.plan] } + surveyed, from: heights)
        try world.removeTrackEdge(old.id)
        var nodes = [old.from]
        if let start = levelling.stretchStart { nodes.append(try world.buildTrackNode(at: start)) }
        if let end = levelling.stretchEnd { nodes.append(try world.buildTrackNode(at: end)) }
        nodes.append(old.to)
        let plans = levelling.legs.indices.map { index in
            TrackEdgePlan(
                from: nodes[index], to: nodes[index + 1], curve: levelling.legs[index].curve,
                profile: levelling.legs[index].profile, structure: levelling.structure
            )
        }
        let edges = try world.buildTrackEdges(plans)
        // The new track joins what the old did at its ends, and runs on
        // through the new nodes.
        func exits(_ edge: TrackEdgeID, at node: TrackNodeID) -> Set<TrackEdgeID> {
            Set(world.network.node(node)?.end(of: edge)?.exits ?? [])
        }
        guard let first = edges.first, let last = edges.last,
              exits(first, at: old.from) == fromExits, exits(last, at: old.to) == toExits,
              edges.indices.dropFirst().allSatisfy({ exits(edges[$0], at: nodes[$0]) == [edges[$0 - 1]] })
        else { throw .invalidTrackGeometry }
        return edges[levelling.levelLeg]
    }

    /// The level stretch ``networkPlatformStretch`` would become, built on
    /// a copy, with what levelling it costs, or why it cannot be levelled.
    /// `nil` where the stretch is level already or nothing is picked. The
    /// map's pill reads it every frame, so it is kept for the stretch and
    /// world it was worked out for, as ``networkPreview`` is.
    public var networkPlatformLevelling: PlatformLevellingPreview? {
        guard let grade = networkPlatformGrade, let stretch = networkPlatformStretch else { return nil }
        _ = world
        let key = PlatformLevellingMemo.Key(
            edge: stretch.edge, start: stretch.start, end: stretch.end, easesGrade: networkEasesGrade,
            language: language, worldRevision: worldRevision
        )
        if let memo = platformLevellingMemo, memo.key == key { return memo.preview }
        var draft = world
        let preview: PlatformLevellingPreview
        switch platformLevelling(of: stretch.edge, from: stretch.start, to: stretch.end, in: draft) {
        case .failure(let problem):
            preview = PlatformLevellingPreview(grade: grade, length: stretch.end - stretch.start, cost: nil, problem: problem.text(in: language))
        case .success(let levelling):
            do throws(GameError) {
                _ = try build(levelling, in: &draft)
                preview = PlatformLevellingPreview(
                    grade: grade, length: levelling.end - levelling.start,
                    cost: Money(world.economy.balance.amount - draft.economy.balance.amount), problem: nil
                )
            } catch {
                preview = PlatformLevellingPreview(
                    grade: grade, length: levelling.end - levelling.start, cost: nil, problem: error.playerMessage(in: language)
                )
            }
        }
        platformLevellingMemo = PlatformLevellingMemo(key: key, preview: preview)
        return preview
    }
}

/// What levelling a platform's stretch would do (decision 190): the grade
/// it has now, how much track is laid level, and what relaying it costs,
/// or why it cannot be levelled.
public struct PlatformLevellingPreview: Hashable, Sendable {
    /// In whole per mille, at least 1.
    public let grade: Int64
    /// In world units.
    public let length: Int64
    public let cost: Money?
    public let problem: String?
}

struct PlatformLevellingMemo {
    struct Key: Equatable {
        let edge: TrackEdgeID
        let start: Int64
        let end: Int64
        let easesGrade: Bool
        let language: DisplayLanguage
        let worldRevision: Int
    }

    let key: Key
    let preview: PlatformLevellingPreview
}

extension PlatformLevellingPreview {
    /// "climbs 7‰: ✓ levels these 64 m (relaying the track $ 1,200)", or
    /// why it cannot.
    public func text(in language: DisplayLanguage) -> String {
        let length = NetworkBuilding.lengthText(length, in: language)
        if let cost {
            return language.text(
                "climbs \(grade)‰: ✓ levels these \(length) (relaying the track \(cost.moneyText))",
                "坡度 \(grade)‰：按 ✓ 會把這 \(length)整平（重鋪這段軌道 \(cost.moneyText)）"
            )
        }
        return language.text(
            "climbs \(grade)‰ and cannot be levelled: \(problem ?? "")",
            "坡度 \(grade)‰，無法整平：\(problem ?? "")"
        )
    }

    /// The short line over the map's ✓: "Levels 64 m · 7‰".
    public func caption(in language: DisplayLanguage) -> String {
        let length = NetworkBuilding.lengthText(length, in: language)
        guard cost != nil else {
            return language.text("Climbs \(grade)‰: cannot be levelled", "坡度 \(grade)‰：無法整平")
        }
        return language.text("Climbs \(grade)‰: levels \(length)", "坡度 \(grade)‰：整平 \(length)")
    }
}
