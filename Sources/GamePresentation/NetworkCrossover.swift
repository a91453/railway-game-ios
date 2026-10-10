import GameCore

// The X (scissors) crossover (the owner's play-test, 2026-10-06): between
// two tracks, two diagonals that cross at a diamond in the middle, so trains
// can change track either way. It is built from GameCore's own commands on
// a copy of the world: four splits (`GameWorld.splitTrackEdge(_:at:)`), the
// node in the middle and the four halves of the diagonals, each leaving its
// track along it. GameCore decides every piece; the diamond is a node where
// each diagonal runs straight through and joins only its own other half
// (the reference's crossing node, `canTurn`: "四叉交會仍不猜可轉線"). No
// reference has a tool to build one: this is native.

/// The four places and the middle of an X crossover, and the curves of its
/// four halves: from the first track's place out to the middle and on to
/// the second track's, then the mirrored diagonal.
struct ScissorsPlan {
    /// The places on the tracks: the picked ones, then each projected
    /// across onto the other track.
    let places: [(point: NetworkEdgePoint, position: WorldCoordinate)]
    let middle: WorldCoordinate
    /// The halves, as (from place, curve, to place), with the middle as
    /// place 4.
    let halves: [(from: Int, curve: TrackCurve, to: Int)]
}

extension GameSession {
    /// Whether the picked ends make a crossover: both on the track
    /// (``NetworkAnchor/track(_:)``), on two different edges. Building them
    /// makes one diagonal, or with ``networkBuildsScissors`` an X.
    public var networkPicksCrossover: Bool {
        guard networkMode == .build, case .track(let start)? = networkStart, case .track(let end)? = networkEnd else { return false }
        return start.edge != end.edge
    }

    /// The X crossover the picked ends make, or why not: `nil` unless
    /// ``networkPicksCrossover`` and ``networkBuildsScissors``.
    func scissorsPlan() -> Result<ScissorsPlan, ScissorsProblem>? {
        guard networkPicksCrossover, networkBuildsScissors,
              case .track(let start)? = networkStart, case .track(let end)? = networkEnd else { return nil }
        guard let p1 = world.position(of: .track(start), height: 0), let p2 = world.position(of: .track(end), height: 0),
              p1.z == p2.z else { return .failure(.notLevel) }
        // Each place projected across onto the other track.
        guard let q1 = world.nearestPoint(onEdge: start.edge, to: p2.plan), let q2 = world.nearestPoint(onEdge: end.edge, to: p1.plan),
              let q1Position = world.position(of: .track(q1), height: 0), let q2Position = world.position(of: .track(q2), height: 0)
        else { return .failure(.notAcross) }
        // Far enough apart along each track for a split at each end, and
        // never a place within reach of the end of its edge.
        func along(_ a: WorldCoordinate, _ b: WorldCoordinate) -> Int64 {
            let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
            return Int64((dx * dx + dy * dy).squareRoot())
        }
        guard along(p1, q1Position) >= 2 * NetworkBuilding.minimumSpacing, along(p2, q2Position) >= 2 * NetworkBuilding.minimumSpacing else {
            return .failure(.tooShort)
        }
        for place in [start, end, q1, q2] {
            guard let edge = world.network.edge(place.edge),
                  place.distance >= NetworkBuilding.minimumSpacing, edge.length - place.distance >= NetworkBuilding.minimumSpacing
            else { return .failure(.nearANode) }
        }
        let middle = WorldCoordinate(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2, z: p1.z)
        let places = [(start, p1), (end, p2), (q1, q1Position), (q2, q2Position)]
        // Each diagonal runs straight through the middle: its halves leave
        // the middle back toward their own track.
        func half(_ from: Int, to place: Int, through way: PlanVector) -> (from: Int, curve: TrackCurve, to: Int)? {
            let point = places[place]
            guard let leaving = world.joiningDirection(at: point.0, toward: middle.plan),
                  let curve = NetworkBuilding.curve(from: point.1.plan, leaving: leaving, to: middle.plan, leaving: way)
            else { return nil }
            return (from, curve, 4)
        }
        let first = PlanVector(dx: p2.x - p1.x, dy: p2.y - p1.y)
        let second = PlanVector(dx: q1Position.x - q2Position.x, dy: q1Position.y - q2Position.y)
        guard let a = half(0, to: 0, through: first.reversed), let b = half(1, to: 1, through: first),
              let c = half(3, to: 3, through: second.reversed), let d = half(2, to: 2, through: second)
        else { return .failure(.tooSharp) }
        return .success(ScissorsPlan(places: places.map { ($0.0, $0.1) }, middle: middle, halves: [a, b, c, d]))
    }

    /// Builds `plan` in `world`: the four splits, the middle and the four
    /// halves. Returns the halves' edges in plan order, or throws what
    /// GameCore refused; `nil` when the diagonals came out joined at the
    /// middle (crossing too shallowly to tell apart).
    func build(_ plan: ScissorsPlan, in world: inout GameWorld, structure: TrackStructure) throws(GameError) -> [TrackEdgeID]? {
        // Decision 124: the ground under the places, the middle and halfway
        // between them, read in first.
        let places = plan.places.map(\.position.plan)
        let halfways = places.map { PlanPoint(x: ($0.x + plan.middle.x) / 2, y: ($0.y + plan.middle.y) / 2) }
        try world.readGround(under: places + [plan.middle.plan] + halfways, from: heights)
        var nodes: [TrackNodeID] = []
        for place in plan.places {
            // An earlier split may have cut the same edge: find the place
            // again where it lies now.
            let now = world.network.edge(place.point.edge) != nil ? place.point : world.trackEdgePoint(near: place.position.plan, within: 16)
            guard let now else { throw .unknownTrackEdge(place.point.edge) }
            nodes.append(try world.splitTrackEdge(now.edge, at: now.distance))
        }
        nodes.append(try world.buildTrackNode(at: plan.middle))
        // As one: each half parts from the other track only by way of the
        // others.
        let edges = try world.buildTrackEdges(plan.halves.map {
            TrackEdgePlan(from: nodes[$0.from], to: nodes[$0.to], curve: $0.curve, structure: structure)
        })
        // A diamond: each half joins only its own diagonal's other half.
        let middle = world.network.node(nodes[4])
        func exits(_ edge: TrackEdgeID) -> [TrackEdgeID] { middle?.end(of: edge)?.exits ?? [] }
        guard exits(edges[0]) == [edges[1]], exits(edges[1]) == [edges[0]],
              exits(edges[2]) == [edges[3]], exits(edges[3]) == [edges[2]] else { return nil }
        return edges
    }

    /// The preview of the X crossover: both diagonals, what they cost, or
    /// why they cannot be built.
    func scissorsPreview() -> (preview: NetworkPreview, crossing: [WorldCoordinate])? {
        guard let result = scissorsPlan() else { return nil }
        switch result {
        case .failure(let problem):
            guard case .track(let start)? = networkStart, case .track(let end)? = networkEnd,
                  let from = world.position(of: .track(start), height: 0), let to = world.position(of: .track(end), height: 0) else { return nil }
            return (NetworkPreview(curve: .straight, profile: .uniform, points: [from, to], length: 0, startHeight: from.z, endHeight: to.z,
                                   joinsStart: false, joinsEnd: false, cost: nil, problem: problem.text(in: language)), [])
        case .success(let plan):
            var draft = world
            var cost: Money?
            var problem: String?
            var edges: [TrackEdgeID] = []
            do throws(GameError) {
                if let built = try build(plan, in: &draft, structure: networkStructure) {
                    edges = built
                    cost = Money(world.economy.balance.amount - draft.economy.balance.amount)
                } else {
                    problem = ScissorsProblem.tooShallow.text(in: language)
                }
            } catch {
                problem = error.playerMessage(in: language)
            }
            let geometries = edges.compactMap { draft.trackGeometry(of: $0) }
            // Every half runs from its track to the middle: a diagonal's
            // second half is drawn back out of it.
            let first = geometries.count == 4 ? geometries[0].points + geometries[1].points.reversed().dropFirst() : [plan.places[0].position, plan.middle, plan.places[1].position]
            let second = geometries.count == 4 ? geometries[2].points + geometries[3].points.reversed().dropFirst() : [plan.places[3].position, plan.middle, plan.places[2].position]
            let length = geometries.reduce(0) { $0 + $1.length }
            // Decision 124, H3: its four halves' parts, and what pulling
            // down the buildings in their way costs.
            let sections = edges.compactMap { draft.longSection(of: $0) }
            let cleared = cost == nil ? [] : world.placedBuildings(clearedIn: draft)
            let parts = cost == nil || sections.count != edges.count ? nil : NetworkCostParts(
                track: sections.reduce(.zero) { $0 + $1.cost }, demolition: world.clearingCost(of: cleared)
            )
            return (NetworkPreview(curve: .straight, profile: .uniform, points: first, length: length, startHeight: plan.middle.z,
                                   endHeight: plan.middle.z, joinsStart: true, joinsEnd: true, cost: cost, problem: problem,
                                   costParts: parts), second)
        }
    }

    /// Builds the X crossover the picked ends make, all or nothing.
    func buildNetworkScissors() {
        guard let result = scissorsPlan() else { return }
        let plan: ScissorsPlan
        switch result {
        case .success(let found): plan = found
        case .failure(let problem):
            message = StatusMessage(kind: .failure, text: problem.text(in: language))
            return
        }
        let balance = world.economy.balance
        var draft = world
        do throws(GameError) {
            guard try build(plan, in: &draft, structure: networkStructure) != nil else {
                message = StatusMessage(kind: .failure, text: ScissorsProblem.tooShallow.text(in: language))
                return
            }
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            return
        }
        let built = draft
        let done = perform { world throws(GameError) in
            world = built
            let cost = Money(balance.amount - world.economy.balance.amount)
            return language.text("Built an X crossover for \(cost.moneyText).", "已建造 X 型交叉渡線，花費 \(cost.moneyText)。")
        }
        if done {
            networkStart = nil
            networkEnd = nil
            playSound?(.track)
        }
    }
}

/// Why the network tool will not build an X crossover between the picked
/// places, before any game rule.
enum ScissorsProblem: Error {
    /// The places are at different heights.
    case notLevel
    /// A place does not lie across from the other track.
    case notAcross
    /// The places are less than twice ``NetworkBuilding/minimumSpacing``
    /// apart along a track.
    case tooShort
    /// A place, or its projection, is within reach of the end of its edge.
    case nearANode
    /// A half would turn more than 90° from its track.
    case tooSharp
    /// The diagonals cross so shallowly that they join at the middle.
    case tooShallow

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .notLevel:
            language.text("An X crossover joins two tracks at one level.", "X 型交叉渡線只能連接同一高度的兩條軌道。")
        case .notAcross:
            language.text("Tap two tracks side by side: the second across from and along the first.", "請點兩條並行的軌道：第二點在第一條軌道的對面、往前一段。")
        case .tooShort:
            language.text("Make the crossover longer: at least 44 m along the tracks.", "交叉渡線要再長一點：沿軌道至少 44 公尺。")
        case .nearANode:
            language.text(
                "An X crossover needs 22 m of track beyond each of its four ends: tap farther from the nodes.",
                "X 型交叉渡線的四個端點外都需要 22 公尺的軌道：請點離節點遠一點的位置。"
            )
        case .tooSharp:
            language.text("The tracks turn too sharply for an X crossover there.", "那裡的軌道彎曲太大，無法設 X 型交叉渡線。")
        case .tooShallow:
            language.text(
                "The two diagonals would cross too shallowly to tell apart: make the crossover shorter.",
                "兩條斜線交叉的角度太小：請把交叉渡線縮短。"
            )
        }
    }
}

extension GameWorld {
    /// The place on edge `id` nearest `point` in plan, or `nil` for no such
    /// edge or when the nearest is one of its ends (the point is not across
    /// from it).
    func nearestPoint(onEdge id: TrackEdgeID, to point: PlanPoint) -> NetworkEdgePoint? {
        guard let geometry = trackGeometry(of: id) else { return nil }
        let px = Double(point.x), py = Double(point.y)
        var best: (distance: Int64, squared: Double)?
        for index in geometry.points.indices.dropLast() {
            let a = geometry.points[index], b = geometry.points[index + 1]
            let ax = Double(a.x), ay = Double(a.y)
            let dx = Double(b.x) - ax, dy = Double(b.y) - ay
            let span = dx * dx + dy * dy
            let t = span > 0 ? min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / span)) : 0
            let ex = ax + t * dx - px, ey = ay + t * dy - py
            let squared = ex * ex + ey * ey
            guard best == nil || squared < best!.squared else { continue }
            let start = geometry.distances[index], end = geometry.distances[index + 1]
            best = (start + Int64((Double(end - start) * t).rounded()), squared)
        }
        guard let best, best.distance > 0, best.distance < geometry.length else { return nil }
        return NetworkEdgePoint(edge: id, distance: best.distance)
    }
}
