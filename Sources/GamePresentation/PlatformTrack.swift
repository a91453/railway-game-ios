import GameCore

// A platform track in one step (the owner's play-test, 2026-10-06): beside
// a station's platform, a parallel track joined to the platform's track by
// a turnout at each end, with a platform of its own, without drawing the
// parallel line first. Built from GameCore's own commands on a copy of the
// world: the turnouts split the track (`GameWorld.splitTrackEdge(_:at:)`)
// or are its nodes, two new nodes stand beside the platform's ends, and the
// three edges between are built as one (`GameWorld.buildTrackEdges(_:)`),
// each leaving the track along it. No reference has such a tool: native.
//
// An island platform stands between the two tracks, so the new track is
// farther out (``PlatformTrackLayout/island``); side platforms stand outside
// each track, the tracks at the usual spacing. The model keeps a platform
// on a track's centre line either way: the layout sets only the spacing.

/// How the station's platforms stand with a new platform track.
public enum PlatformTrackLayout: CaseIterable, Hashable, Sendable {
    /// One platform between the two tracks: they stand 11 m apart.
    case island
    /// A platform outside each track: they stand 5 m apart.
    case side

    /// The spacing of the two tracks, centre to centre, in world units.
    public var spacing: Int64 {
        switch self {
        case .island: 11 * WorldCoordinate.unitsPerMetre
        case .side: 5 * WorldCoordinate.unitsPerMetre
        }
    }

    /// How far along the track each turnout stands from the platform's end:
    /// the S-curve out to the new track, at least 50 m and eight times its
    /// spacing.
    public var reach: Int64 {
        max(50 * WorldCoordinate.unitsPerMetre, 8 * spacing)
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .island: language.text("Island platform", "島式月台")
        case .side: language.text("Side platform", "岸式月台")
        }
    }
}

/// Which side of a platform's track a new platform track goes: to the
/// left or the right of the way its edge runs.
public enum PlatformTrackSide: CaseIterable, Hashable, Sendable {
    case left
    case right
}

/// Why a platform track cannot go beside a platform, before any game rule.
enum PlatformTrackProblem: Error {
    /// The platform or its track is gone.
    case missing
    /// The track there climbs or falls.
    case notLevel
    /// The line does not run on far enough past the platform's ends, on
    /// level track without a junction, for the turnouts.
    case noRoom

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .missing:
            language.text("That platform is gone.", "那個月台已經不在了。")
        case .notLevel:
            language.text("A platform track goes beside level track only.", "只有平坦的軌道旁才能加月台軌道。")
        case .noRoom:
            language.text(
                "There is not enough track either side of the platform for the turnouts: the platform's track must run on past each end.",
                "月台兩端外的軌道不夠長，放不下轉轍器：月台所在的軌道要在兩端外再延伸一段。"
            )
        }
    }
}

/// Where a turnout of a platform track goes: an existing node, or a place
/// on an edge to split; with its position and the way the new track leaves
/// it along the line.
public struct PlatformTrackTurnout: Hashable, Sendable {
    let node: TrackNodeID?
    let point: NetworkEdgePoint?
    let position: WorldCoordinate
    let leaving: PlanVector
}

/// A platform track worked out from the world: its two turnouts, the new
/// nodes' positions beside the platform's ends and the three new edges'
/// curves.
public struct PlatformTrackPlan: Hashable, Sendable {
    let platform: TrackPlatform
    let near: PlatformTrackTurnout
    let far: PlatformTrackTurnout
    let beside: Beside
    let curves: Curves

    /// The new nodes' positions beside the platform's ends.
    struct Beside: Hashable, Sendable {
        let near: WorldCoordinate
        let far: WorldCoordinate
    }

    /// The new edges' curves: out from the near turnout, along the
    /// platform, back to the far one.
    struct Curves: Hashable, Sendable {
        let out: TrackCurve
        let along: TrackCurve
        let back: TrackCurve
    }
    /// What carries the platform's track, and so the new one.
    let structure: TrackStructure
}

extension GameSession {
    /// The compass side `side` of `platform`'s track faces, by the larger
    /// part of the way to it: "north", "south", "east" or "west".
    public func platformTrackSideText(_ side: PlatformTrackSide, of platform: TrackPlatform) -> String {
        edgeSideText(side, at: NetworkEdgePoint(edge: platform.edge, distance: (platform.start + platform.end) / 2))
    }

    /// The compass side `side` of the track at `point` faces (see
    /// ``platformTrackSideText(_:of:)``).
    public func edgeSideText(_ side: PlatformTrackSide, at point: NetworkEdgePoint) -> String {
        guard let geometry = world.trackGeometry(of: point.edge), point.distance >= 0, point.distance <= geometry.length else { return "" }
        return sideText(side, of: geometry.location(at: point.distance).direction)
    }

    /// The compass side `side` of a track running along `way` faces.
    func sideText(_ side: PlatformTrackSide, of way: PlanVector) -> String {
        // y grows south on the map.
        let normal = side == .left ? PlanVector(dx: way.dy, dy: -way.dx) : PlanVector(dx: -way.dy, dy: way.dx)
        if abs(normal.dx) >= abs(normal.dy) {
            return normal.dx >= 0 ? language.text("east side", "東側") : language.text("west side", "西側")
        }
        return normal.dy >= 0 ? language.text("south side", "南側") : language.text("north side", "北側")
    }

    /// The turnout `reach` along the line from `offset` on edge `edge`, going
    /// along it (`forward`) or back: through each node where the line runs
    /// straight on (one way on), to a place on an edge, or to a node when
    /// the place is nearer it than a split may be. `nil` where the line
    /// ends, branches or climbs first. The new track leaves the turnout back
    /// toward the platform.
    func platformTrackTurnout(from edge: TrackEdgeID, at offset: Int64, forward: Bool, reach: Int64) -> PlatformTrackTurnout? {
        var edge = edge, offset = offset, forward = forward, left = reach
        let spacing = NetworkBuilding.minimumSpacing
        for _ in 0..<64 {
            guard let current = world.network.edge(edge), let geometry = world.trackGeometry(of: edge),
                  geometry.startHeight == geometry.endHeight, current.profile == .uniform else { return nil }
            let room = forward ? current.length - offset : offset
            if left <= room {
                let distance = forward ? offset + left : offset - left
                let location = geometry.location(at: distance)
                let back = forward ? location.direction.reversed : location.direction
                // At a node, the way along the edge toward the platform:
                // into the edge from its `from` node, back along it from its
                // `to` node, the other way round going forward.
                if distance < spacing, let node = world.network.node(current.from) {
                    let leaving = forward ? geometry.startDirection.reversed : geometry.startDirection
                    return PlatformTrackTurnout(node: node.id, point: nil, position: node.position, leaving: leaving)
                }
                if current.length - distance < spacing, let node = world.network.node(current.to) {
                    let leaving = forward ? geometry.endDirection : geometry.endDirection.reversed
                    return PlatformTrackTurnout(node: node.id, point: nil, position: node.position, leaving: leaving)
                }
                return PlatformTrackTurnout(node: nil, point: NetworkEdgePoint(edge: edge, distance: distance), position: location.position, leaving: back)
            }
            left -= room
            // On through the node at this end, if the line runs straight on.
            let nodeID = forward ? current.to : current.from
            guard let node = world.network.node(nodeID), let end = node.end(of: edge), end.exits.count == 1,
                  let next = world.network.edge(end.exits[0]) else { return nil }
            forward = next.from == nodeID && next.to != nodeID
            edge = next.id
            offset = forward ? 0 : next.length
        }
        return nil
    }

    func platformTrackPlan(beside platform: TrackPlatform, layout: PlatformTrackLayout, side: PlatformTrackSide)
        -> Result<PlatformTrackPlan, PlatformTrackProblem>
    {
        guard world.trackPlatforms(of: platform.station).contains(platform) else { return .failure(.missing) }
        return sidingPlan(on: platform.edge, from: platform.start, to: platform.end, spacing: layout.spacing, reach: layout.reach, side: side).map {
            PlatformTrackPlan(platform: platform, near: $0.near, far: $0.far, beside: $0.beside, curves: $0.curves, structure: $0.structure)
        }
    }

    /// A track beside `edge` from `start` to `end`, `spacing` to the `side`,
    /// joined to it by a turnout `reach` beyond each end: a platform track's
    /// (above) or a passing loop's (decision 204).
    func sidingPlan(on edgeID: TrackEdgeID, from start: Int64, to end: Int64, spacing: Int64, reach: Int64, side: PlatformTrackSide)
        -> Result<Siding, PlatformTrackProblem>
    {
        guard let edge = world.network.edge(edgeID), let geometry = world.trackGeometry(of: edgeID),
              start >= 0, start < end, end <= geometry.length else { return .failure(.missing) }
        guard geometry.startHeight == geometry.endHeight, edge.profile == .uniform else { return .failure(.notLevel) }
        guard let near = platformTrackTurnout(from: edgeID, at: start, forward: false, reach: reach),
              let far = platformTrackTurnout(from: edgeID, at: end, forward: true, reach: reach)
        else { return .failure(.noRoom) }
        func besides(_ distance: Int64) -> (position: WorldCoordinate, way: PlanVector) {
            // The same parallel as a double track's and a depot's sidings.
            let location = geometry.location(at: distance)
            return (DoubleTrack.beside(location.position, way: location.direction, side: side, distance: spacing), location.direction)
        }
        let first = besides(start), last = besides(end)
        // The near turnout's track leaves toward the stretch; at the far
        // one, the new track arrives from it, leaving back toward it.
        guard let out = NetworkBuilding.curve(from: near.position.plan, leaving: near.leaving, to: first.position.plan, leaving: first.way.reversed),
              let along = NetworkBuilding.curve(from: first.position.plan, leaving: first.way, to: last.position.plan, leaving: last.way.reversed),
              let back = NetworkBuilding.curve(from: last.position.plan, leaving: last.way, to: far.position.plan, leaving: far.leaving)
        else { return .failure(.noRoom) }
        return .success(Siding(
            near: near, far: far, beside: .init(near: first.position, far: last.position), curves: .init(out: out, along: along, back: back),
            structure: edge.structure
        ))
    }

    /// The parts of a siding (``sidingPlan(on:from:to:spacing:reach:side:)``).
    struct Siding {
        let near: PlatformTrackTurnout
        let far: PlatformTrackTurnout
        let beside: PlatformTrackPlan.Beside
        let curves: PlatformTrackPlan.Curves
        let structure: TrackStructure
    }

    /// Builds the siding in `world`: the turnouts (splitting the track, the
    /// far one first), the two nodes beside, and the three edges as one.
    /// Returns the three edges: out, along, back.
    func buildSiding(
        near nearTurnout: PlatformTrackTurnout, far farTurnout: PlatformTrackTurnout, beside: PlatformTrackPlan.Beside,
        curves: PlatformTrackPlan.Curves, structure: TrackStructure, in world: inout GameWorld
    ) throws(GameError) -> [TrackEdgeID] {
        // Decision 124: the ground under the new track read in first, as the
        // track and crossover tools do. Beside the line it may lie in a
        // block the line's own track never reached.
        let ends = [nearTurnout.position, beside.near, beside.far, farTurnout.position]
        let legs = [(ends[0], ends[1], curves.out), (ends[1], ends[2], curves.along), (ends[2], ends[3], curves.back)]
        let surveyed = legs.compactMap { TrackGeometry(from: $0.0, to: $0.1, curve: $0.2) }.flatMap(NetworkBuilding.surveyedPoints(of:))
        try world.readGround(under: ends.map(\.plan) + surveyed, from: heights)
        func node(_ turnout: PlatformTrackTurnout) throws(GameError) -> TrackNodeID {
            if let node = turnout.node { return node }
            guard let point = turnout.point else { throw .invalidTrackGeometry }
            // The other turnout may have split the same edge: find the
            // place again where it lies now.
            let now = world.network.edge(point.edge) != nil ? point : world.trackEdgePoint(near: turnout.position.plan, within: 16)
            guard let now else { throw .unknownTrackEdge(point.edge) }
            return try world.splitTrackEdge(now.edge, at: now.distance)
        }
        let far = try node(farTurnout)
        let near = try node(nearTurnout)
        let start = try world.buildTrackNode(at: beside.near)
        let end = try world.buildTrackNode(at: beside.far)
        return try world.buildTrackEdges([
            TrackEdgePlan(from: near, to: start, curve: curves.out, structure: structure),
            TrackEdgePlan(from: start, to: end, curve: curves.along, structure: structure),
            TrackEdgePlan(from: end, to: far, curve: curves.back, structure: structure),
        ])
    }

    /// Builds `plan` in `world`: the turnouts, the new nodes, the three
    /// edges as one and the new platform along the middle one, for the same
    /// station. Returns the new platform.
    func build(_ plan: PlatformTrackPlan, in world: inout GameWorld) throws(GameError) -> TrackPlatform {
        let edges = try buildSiding(near: plan.near, far: plan.far, beside: plan.beside, curves: plan.curves, structure: plan.structure, in: &world)
        let length = world.network.edge(edges[1])?.length ?? 0
        try world.addTrackPlatform(plan.platform.station, on: edges[1], from: 0, to: length)
        return TrackPlatform(station: plan.platform.station, edge: edges[1], start: 0, end: length)
    }

    /// What a platform track beside `platform` would cost, or why it cannot
    /// be built: GameCore's answer on a copy of the world.
    public func platformTrackPreview(beside platform: TrackPlatform, layout: PlatformTrackLayout, side: PlatformTrackSide)
        -> (cost: Money?, problem: String?)
    {
        switch platformTrackPlan(beside: platform, layout: layout, side: side) {
        case .failure(let problem):
            return (nil, problem.text(in: language))
        case .success(let plan):
            var draft = world
            do throws(GameError) {
                _ = try build(plan, in: &draft)
                return (Money(world.economy.balance.amount - draft.economy.balance.amount), nil)
            } catch {
                return (nil, error.playerMessage(in: language))
            }
        }
    }

    /// Builds a platform track beside `platform` (see the file's header),
    /// all or nothing.
    public func addPlatformTrack(beside platform: TrackPlatform, layout: PlatformTrackLayout, side: PlatformTrackSide) {
        let plan: PlatformTrackPlan
        switch platformTrackPlan(beside: platform, layout: layout, side: side) {
        case .success(let found): plan = found
        case .failure(let problem):
            message = StatusMessage(kind: .failure, text: problem.text(in: language))
            return
        }
        let balance = world.economy.balance
        let station = world.station(id: platform.station)?.name ?? ""
        let sideText = platformTrackSideText(side, of: platform)
        perform(.addPlatformTrack(plan)) { _, _, world in
            let cost = Money(balance.amount - world.economy.balance.amount)
            return language.text(
                "\(station): \(layout.title(in: language).lowercased()) track on the \(sideText), for \(cost.moneyText).",
                "\(station)：已在\(sideText)加上\(layout.title(in: language))軌道，花費 \(cost.moneyText)。"
            )
        }
    }
}
