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
// on the edge, an outer edge steeper than 40‰, too little money).
// GameCore's split (`GameWorld.split`) is internal and splits level edges
// only, so a curve is cut here by de Casteljau's rule; neither reference
// has such a tool: native.
//
// TestFlight 70.1: the edge often has platforms on it already (a line laid
// end to end, a station at each end, then one between), which GameCore
// will not lay again (`trackEdgeHasPlatform`). They are taken off first
// (`GameWorld.removeTrackPlatform`), the edge is cut at their ends too, each
// laid level at the height it stood at, and they are put back on their
// edges at their own stations, in the same edit.

/// A stretch of an edge a platform would take, levelled: the edge laid again
/// in up to three edges, the middle one level, and one more level edge for
/// each platform already on it.
public struct PlatformLevelling: Hashable, Sendable {
    /// The edge as it is, and the stretch the platform would take, moved
    /// to an end of the edge where it came within a split's least piece of
    /// it.
    let edge: TrackEdgeID
    let start: Int64
    let end: Int64
    /// The edges to build in order along the old one, cut at the ends of
    /// the stretch and of every platform on it, but at its own ends.
    let legs: [Leg]
    /// The new nodes between the legs, one fewer than the legs.
    let nodes: [WorldCoordinate]
    let structure: TrackStructure
    /// Which of ``legs`` is the level one.
    let levelLeg: Int
    /// The platforms on the edge as it is, taken off and put back, each on
    /// a level leg of its own, the whole of it.
    let kept: [KeptPlatform]

    struct KeptPlatform: Hashable, Sendable {
        let station: StationID
        /// Where it starts on the old edge.
        let start: Int64
        let leg: Int
    }

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
    /// The stretch runs into a platform already on the edge.
    case platformInTheWay
    /// The stretch or a platform on the edge comes within a split's least
    /// piece of another's end, too near to cut between.
    case tooNearAPlatform

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
        case .platformInTheWay:
            language.text(
                "A platform already stands on part of this stretch: tap the track beside it.",
                "這一段已經有月台了：請點選旁邊沒有月台的軌道。"
            )
        case .tooNearAPlatform:
            language.text(
                "This is too near the end of another platform to level the track between them: tap a little further from it.",
                "這裡離另一座月台的端點太近，兩者之間的軌道無法整平：請點選離它遠一點的地方。"
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
        // nearer an end of the edge, or of a platform on it, than that moves
        // to it, its length kept.
        let piece = GameWorld.minimumSplitPiece
        let length = end - start
        let platforms = world.network.platforms(on: edge).sorted { $0.start < $1.start }
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
        // Moved against a platform before it or after it, the nearer one.
        if start > 0, let before = platforms.last(where: { $0.end <= start + piece / 2 }), start - before.end < piece {
            start = before.end
            end = min(current.length, start + length)
        } else if end < current.length, let after = platforms.first(where: { $0.start >= end - piece / 2 }), after.start - end < piece {
            end = after.start
            start = max(0, end - length)
        }
        guard !platforms.contains(where: { start < $0.end && $0.start < end }) else { return .failure(.platformInTheWay) }

        // The height each cut stands at: a platform's the height it stands
        // at now (it is level), the stretch's the edge's end it reaches, a
        // platform it meets, or else the track's at its middle.
        var heights: [Int64: Int64] = [0: a.z, current.length: b.z]
        func require(_ height: Int64, at distance: Int64) -> Bool {
            if let found = heights[distance] { return found == height }
            heights[distance] = height
            return true
        }
        for platform in platforms {
            let height = geometry.height(at: platform.start)
            guard require(height, at: platform.start), require(height, at: platform.end) else { return .failure(.cannotCut) }
        }
        let height = heights[start] ?? heights[end] ?? geometry.height(at: (start + end) / 2)
        // Between two at different heights it cannot be level.
        guard require(height, at: start), require(height, at: end) else { return .failure(.tooNearAPlatform) }
        let cuts = heights.keys.sorted()
        guard zip(cuts, cuts.dropFirst()).allSatisfy({ $1 - $0 >= piece }) else { return .failure(.tooNearAPlatform) }

        // The plan points of the cuts, and each leg's curve.
        let inner = cuts.dropFirst().dropLast()
        var plans: [(from: PlanPoint, to: PlanPoint, curve: TrackCurve)] = []
        switch current.curve {
        case .straight:
            let points = [a.plan] + inner.map { geometry.location(at: $0).position.plan } + [b.plan]
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
            for distance in inner {
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
        guard let levelLeg = cuts.firstIndex(of: start) else { return .failure(.cannotCut) }
        var legs: [PlatformLevelling.Leg] = []
        for (index, plan) in plans.enumerated() {
            let fromZ = heights[cuts[index]] ?? a.z
            let toZ = heights[cuts[index + 1]] ?? b.z
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
        let kept = platforms.compactMap { platform in
            cuts.firstIndex(of: platform.start).map { PlatformLevelling.KeptPlatform(station: platform.station, start: platform.start, leg: $0) }
        }
        return .success(PlatformLevelling(
            edge: edge, start: start, end: end, legs: legs,
            nodes: legs.dropLast().map(\.to),
            // Track on the ground takes what the ground asks for once its
            // height changes (decision 124); one carried keeps its carrier.
            structure: current.structure == .surface ? .automatic : current.structure,
            levelLeg: levelLeg, kept: kept
        ))
    }

    /// Lays `levelling` in `world`: the platforms on the old edge taken
    /// off, the old edge removed, the new nodes and edges built as one, the
    /// platforms put back. Returns the level edge. All or nothing in the
    /// caller's copy.
    func build(_ levelling: PlatformLevelling, in world: inout GameWorld) throws(GameError) -> TrackEdgeID {
        guard let old = world.network.edge(levelling.edge) else { throw .unknownTrackEdge(levelling.edge) }
        // What the old edge joined at its ends, to check the new ones join
        // the same.
        let fromExits = Set(world.network.node(old.from)?.end(of: old.id)?.exits ?? [])
        let toExits = Set(world.network.node(old.to)?.end(of: old.id)?.exits ?? [])
        // A train on it, or whose way runs along it, would lose it: refused
        // as a split refuses it, a train standing on it said as such (70.1:
        // a train waiting at a platform there has nothing to pass).
        if world.trains.contains(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == old.id { return true }
            return train.trailEdges.contains(old.id)
        }) {
            throw .trackEdgeInUse(old.id)
        }
        if let train = world.trains.first(where: { train in
            train.movement.remainingEdges.contains(old.id)
                || train.reservation.contains { if case .span(let span) = $0 { span.edge == old.id } else { false } }
        }) {
            throw .trackReserved(train.id)
        }
        // The lines' chosen paths along it, laid again along the new edges
        // once they are built (70.1; a split refuses them).
        let chosen = world.lines.flatMap { line in
            ([nil] + line.patterns.indices.map(Optional.some)).compactMap { pattern -> (LineID, Int?, [LineRoutePreference])? in
                let routes = pattern.map { line.patterns[$0].routePreferences } ?? line.routePreferences
                let touched = routes.contains { route in
                    route.platform.edge == old.id || route.tracks.contains { $0.edge == old.id }
                }
                return touched ? (line.id, pattern, routes) : nil
            }
        }
        // Decision 124: the ground under the new track read in first.
        let surveyed = levelling.legs.compactMap { TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve, profile: $0.profile) }
            .flatMap(NetworkBuilding.surveyedPoints(of:))
        // Decision 275: one edit for the passengers, so those changing
        // trains onto this track are not sent away while it is out.
        return try world.editTrackAsOne { (world: inout GameWorld) throws(GameError) -> TrackEdgeID in
            try world.readGround(under: levelling.legs.flatMap { [$0.from.plan, $0.to.plan] } + surveyed, from: heights)
            for platform in levelling.kept {
                try world.removeTrackPlatform(platform.station, on: old.id, from: platform.start)
            }
            try world.removeTrackEdge(old.id)
            var nodes = [old.from]
            for node in levelling.nodes {
                nodes.append(try world.buildTrackNode(at: node))
            }
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
            for platform in levelling.kept {
                let edge = edges[platform.leg]
                try world.addTrackPlatform(platform.station, on: edge, from: 0, to: world.network.edge(edge)?.length ?? 0)
            }
            for (line, pattern, routes) in chosen {
                guard let stops = world.lines.first(where: { $0.id == line })?.stops else { continue }
                let moved = routes.map { Self.route($0, from: old.id, along: edges, kept: levelling.kept, stops: stops, in: world) }
                try world.setLineRoutePreferences(line, to: moved, pattern: pattern)
            }
            return edges[levelling.levelLeg]
        }
    }

    /// `route` with old edge `old` laid again as `edges` (in order along
    /// it): a walk along it runs along them all, its first from the leg of
    /// the platform it leaves and its last to the leg of the platform it
    /// ends at, and a kept platform is the one on its leg. A platform on
    /// `old` that was not kept is left as it was, as GameCore leaves a
    /// chosen path whose track is gone (the automatic path until it is
    /// back).
    static func route(
        _ route: LineRoutePreference, from old: TrackEdgeID, along edges: [TrackEdgeID], kept: [PlatformLevelling.KeptPlatform],
        stops: [StationID], in world: GameWorld
    ) -> LineRoutePreference {
        func leg(of station: StationID, start: Int64? = nil) -> Int? {
            let found = kept.filter { $0.station == station && (start == nil || $0.start == start) }
            return found.count == 1 ? found[0].leg : nil
        }
        var platform = route.platform
        var arrival: Int?
        if platform.edge == old {
            guard let index = leg(of: platform.station, start: platform.start),
                  let length = world.network.edge(edges[index])?.length else { return route }
            platform = TrackPlatform(station: platform.station, edge: edges[index], start: 0, end: length)
            arrival = index
        }
        let departure = stops.indices.contains(route.from) ? leg(of: stops[route.from]) : nil
        var tracks: [TrackTraversal] = []
        for (index, traversal) in route.tracks.enumerated() {
            guard traversal.edge == old else {
                tracks.append(traversal)
                continue
            }
            var legs = Array(edges.indices)
            if index == 0, let departure {
                legs = traversal.direction == .forward ? Array(legs[departure...]) : Array(legs[...departure])
            }
            if index == route.tracks.count - 1, let arrival {
                legs = legs.filter { traversal.direction == .forward ? $0 <= arrival : $0 >= arrival }
            }
            if traversal.direction == .backward { legs.reverse() }
            tracks += legs.map { TrackTraversal(edge: edges[$0], direction: traversal.direction) }
        }
        // A walk that no longer ends on its platform: left as it was.
        guard route.tracks.isEmpty || tracks.last?.edge == platform.edge else { return route }
        return LineRoutePreference(from: route.from, to: route.to, tracks: tracks, platform: platform)
    }

    /// Where ``addNetworkPlatform()`` puts a new station on the stretch
    /// `levelling` lays: the middle of its level leg.
    static func platformMiddle(_ levelling: PlatformLevelling) -> PlanPoint? {
        levelling.legs.dropFirst(levelling.levelLeg).first.map { PlanPoint(x: ($0.from.x + $0.to.x) / 2, y: ($0.from.y + $0.to.y) / 2) }
    }

    /// The level stretch ``networkPlatformStretch`` would become, built on
    /// a copy, with what levelling it costs, or why it cannot be levelled.
    /// `nil` where the stretch is level already or nothing is picked. The
    /// map's pill reads it every frame, so it is kept for the stretch and
    /// command it was worked out for, as ``networkPreview`` is.
    public var networkPlatformLevelling: PlatformLevellingPreview? {
        guard let grade = networkPlatformGrade, let stretch = networkPlatformStretch else { return nil }
        _ = world
        let key = PlatformLevellingMemo.Key(
            edge: stretch.edge, start: stretch.start, end: stretch.end, easesGrade: networkEasesGrade,
            language: language, commandRevision: commandRevision
        )
        if let memo = platformLevellingMemo, memo.key == key { return memo.preview }
        var draft = world
        let preview: PlatformLevellingPreview
        switch platformLevelling(of: stretch.edge, from: stretch.start, to: stretch.end, in: draft) {
        case .failure(let problem):
            preview = PlatformLevellingPreview(grade: grade, length: stretch.end - stretch.start, cost: nil, problem: problem.text(in: language))
        case .success(let levelling):
            // Decision 245: what it costs even where the cash would not
            // pay for it; ✓'s price says so with the station's.
            draft = draft.pricingCopy()
            do throws(GameError) {
                _ = try build(levelling, in: &draft)
                let site = Self.platformMiddle(levelling)
                preview = PlatformLevellingPreview(
                    grade: grade, length: levelling.end - levelling.start,
                    cost: Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount), problem: nil,
                    stationClearing: site.map { draft.clearingCost(of: draft.placedBuildings(inTheWayOf: [$0])) }
                )
            } catch {
                preview = PlatformLevellingPreview(
                    grade: grade, length: levelling.end - levelling.start, cost: nil, problem: error.playerMessage(in: language)
                )
            }
        }
        platformLevellingMemo = PlatformLevellingMemo(key: key, preview: preview)
        buildPreviewsWorkedOut += 1
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
    /// What clearing a new station's place on the level stretch costs,
    /// once levelled (decision 245, ``GameSession/networkPlatformCost``).
    var stationClearing: Money? = nil
}

struct PlatformLevellingMemo {
    struct Key: Equatable {
        let edge: TrackEdgeID
        let start: Int64
        let end: Int64
        let easesGrade: Bool
        let language: DisplayLanguage
        let commandRevision: Int
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
