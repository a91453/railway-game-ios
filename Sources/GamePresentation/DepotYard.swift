import GameCore

// A depot's sidings in one step (decision 214, on decision 209's depots):
// tap the end of a track, and the track runs on straight from it as the
// first siding, with the others beside it, ``DepotYard/spacing`` (5 m)
// apart, each leaving the one inside it by a turnout and an S-curve, as a
// platform track leaves its track (``PlatformTrackLayout/side``): a ladder
// fanning out to one side. With them comes the depot, a station flagged as
// one (`GameWorld.setStationDepot`), with a platform along each siding, as
// long as the company's longest train, so a line given the depot keeps a
// train on each. One command (``PlayerCommand/buildDepotYard(_:)``), all
// or nothing.
//
// The parallels are the double-track tool's (``DoubleTrack/beside(_:way:side:distance:)``,
// the normal of the way out of the end); the S-curves are the platform
// track's (``NetworkBuilding/curve(from:leaving:to:leaving:)``). The
// reference has a yard only as a tag routes skip (`topology.js`
// `allowYard`, decision 209), no tool that lays one: native.

/// The depot tool's layout.
public enum DepotYard {
    /// Siding to siding, centre to centre: a double track's 5 m.
    public static let spacing = DoubleTrack.spacing
    /// How far along each S-curve out to the next siding runs: a side
    /// platform track's 50 m.
    public static let reach = PlatformTrackLayout.side.reach
    /// Straight track before a turnout, and between one siding's S-curve
    /// and the next turnout: the least a turnout may stand from a node.
    public static let straight = NetworkBuilding.minimumSpacing
    /// How many sidings the tool lays.
    public static let sidings = 1...6
    public static let defaultSidings = 3
}

/// A depot's sidings worked out from the world: where each track runs and
/// where its platform goes, and the depot's name and place.
public struct DepotYardPlan: Hashable, Sendable, Codable {
    /// The node at the end of the track the yard runs on from, and where
    /// it stands.
    let end: Int
    let origin: WorldCoordinate
    /// The far end of the first siding, straight on from `end`.
    let lead: WorldCoordinate
    /// Each other siding, from the inner one out.
    let branches: [Branch]
    /// Each siding's platform, from the inner one out: the near end and
    /// the far one.
    let platforms: [[WorldCoordinate]]
    let structure: TrackStructure
    let name: String
    let station: PlanPoint

    /// A siding leaving the one inside it: the turnout on it, where the
    /// S-curve (`curve`) comes out beside, and the siding's far end.
    struct Branch: Hashable, Sendable, Codable {
        let turnout: WorldCoordinate
        let bend: WorldCoordinate
        let curve: TrackCurve
        let end: WorldCoordinate
    }

    /// The centre lines, for the map's preview.
    var points: [[WorldCoordinate]] {
        [[origin, lead]] + branches.map { branch in
            (TrackGeometry(from: branch.turnout, to: branch.bend, curve: branch.curve)?.points ?? [branch.turnout, branch.bend]) + [branch.end]
        }
    }
}

/// Why the depot tool cannot lay sidings there, before any game rule.
enum DepotYardProblem: Error {
    /// The tap is not at the end of a track.
    case notAnEnd

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .notAnEnd:
            language.text("Tap the end of a track: the sidings run on from it.", "請點選軌道的盡頭：停車線從那裡接著鋪出去。")
        }
    }
}

extension DoubleTrack {
    /// `point` moved `distance` along `way`, rounded to whole units.
    static func ahead(_ point: WorldCoordinate, way: PlanVector, distance: Int64) -> WorldCoordinate {
        let dx = Double(way.dx), dy = Double(way.dy)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return point }
        let scale = Double(distance) / length
        return WorldCoordinate(x: point.x + Int64((dx * scale).rounded()), y: point.y + Int64((dy * scale).rounded()), z: point.z)
    }
}

extension GameSession {
    /// The yard of `sidings` sidings running on from node `id`, a track's
    /// end, fanning out to `side` of the way out of it.
    func depotYardPlan(from id: TrackNodeID, sidings: Int, side: PlatformTrackSide) -> Result<DepotYardPlan, DepotYardProblem> {
        guard let node = world.network.node(id), node.ends.count == 1, let edge = world.network.edge(node.ends[0].edge) else {
            return .failure(.notAnEnd)
        }
        let count = min(max(sidings, DepotYard.sidings.lowerBound), DepotYard.sidings.upperBound)
        let way = node.ends[0].direction.reversed
        let origin = node.position
        func at(_ along: Int64, siding: Int) -> WorldCoordinate {
            DoubleTrack.beside(DoubleTrack.ahead(origin, way: way, distance: along), way: way, side: side, distance: Int64(siding) * DepotYard.spacing)
        }
        // Siding k (from 1) leaves siding k − 1 at `turnout(k)`, and is
        // beside it a reach on; the platforms all start where the outer
        // one's S-curve ends, and are as long as the longest train.
        func turnout(_ k: Int) -> Int64 {
            DepotYard.straight + Int64(k - 1) * (DepotYard.reach + DepotYard.straight)
        }
        let start = count > 1 ? turnout(count - 1) + DepotYard.reach : DepotYard.straight
        let far = start + passingLoopLength
        var branches: [DepotYardPlan.Branch] = []
        for k in 1..<max(count, 1) {
            let from = at(turnout(k), siding: k - 1), bend = at(turnout(k) + DepotYard.reach, siding: k)
            guard let curve = NetworkBuilding.curve(from: from.plan, leaving: way, to: bend.plan, leaving: way.reversed) else {
                return .failure(.notAnEnd)
            }
            branches.append(.init(turnout: from, bend: bend, curve: curve, end: at(far, siding: k)))
        }
        let middle = at((start + far) / 2, siding: 0)
        let across = DoubleTrack.beside(middle, way: way, side: side, distance: Int64(count - 1) * DepotYard.spacing / 2)
        return .success(DepotYardPlan(
            end: node.id.number, origin: origin, lead: at(far, siding: 0), branches: branches,
            platforms: (0..<count).map { [at(start, siding: $0), at(far, siding: $0)] },
            structure: edge.structure, name: depotName(), station: across.plan
        ))
    }

    /// The compass side `side` of the way out of ``networkDepotEnd`` faces
    /// ("north side"), or `nil` with no end picked.
    public func depotSideText(_ side: PlatformTrackSide) -> String? {
        guard let end = networkDepotEnd, let node = world.network.node(end), node.ends.count == 1 else { return nil }
        return sideText(side, of: node.ends[0].direction.reversed)
    }

    /// "Depot 1", "機廠 1": the next number after the depots'.
    func depotName() -> String {
        let depots = world.stations.filter(\.isDepot).count
        return language.text("Depot \(depots + 1)", "機廠 \(depots + 1)")
    }

    /// Builds `plan` in `world`: the first siding on from the end, each
    /// other one off the siding inside it (splitting it for the turnout),
    /// then the depot with a platform along each. Returns the depot.
    func build(_ plan: DepotYardPlan, in world: inout GameWorld) throws(GameError) -> Station {
        let end = TrackNodeID.node(plan.end)
        guard let origin = world.network.node(end)?.position else { throw .unknownTrackNode(end) }
        // Decision 124: the ground under the new track read in first.
        let legs = [TrackGeometry(from: origin, to: plan.lead, curve: .straight)]
            + plan.branches.flatMap { [TrackGeometry(from: $0.turnout, to: $0.bend, curve: $0.curve), TrackGeometry(from: $0.bend, to: $0.end, curve: .straight)] }
        try world.readGround(under: [origin.plan, plan.lead.plan] + plan.branches.flatMap { [$0.turnout.plan, $0.bend.plan, $0.end.plan] }
            + legs.compactMap(\.self).flatMap(NetworkBuilding.surveyedPoints(of:)), from: heights)
        let lead = try world.buildTrackNode(at: plan.lead)
        _ = try world.buildTrackEdge(from: end, to: lead, structure: plan.structure)
        for branch in plan.branches {
            guard let point = world.trackEdgePoint(near: branch.turnout.plan, within: 16) else { throw .invalidTrackGeometry }
            let turnout = try world.splitTrackEdge(point.edge, at: point.distance)
            let bend = try world.buildTrackNode(at: branch.bend)
            let far = try world.buildTrackNode(at: branch.end)
            _ = try world.buildTrackEdges([
                TrackEdgePlan(from: turnout, to: bend, curve: branch.curve, structure: plan.structure),
                TrackEdgePlan(from: bend, to: far, structure: plan.structure),
            ])
        }
        let station = try world.buildStation(named: plan.name, at: plan.station)
        for platform in plan.platforms {
            guard platform.count == 2,
                  let near = world.trackEdgePoint(near: DoubleTrack.middle(platform[0], platform[1]).plan, within: 16),
                  let geometry = world.trackGeometry(of: near.edge)
            else { throw .invalidTrackGeometry }
            let ends = platform.map { geometry.distance(alongTo: $0.plan) }.sorted()
            try world.addTrackPlatform(station.id, on: near.edge, from: ends[0], to: ends[1])
        }
        try world.setStationDepot(station.id, to: true)
        return world.station(id: station.id) ?? station
    }

    /// The depot's sidings at ``networkDepotEnd`` (``networkDepotSidings``
    /// of them, on ``networkDepotSide``): what they cost or why they cannot
    /// be built, and where they run; worked out once for each end, choice
    /// and world, as the track preview is.
    public var networkDepotPreview: DepotYardPreview? {
        guard networkMode == .depot, let end = networkDepotEnd else { return nil }
        _ = world
        let key = DepotYardMemo.Key(end: end, sidings: networkDepotSidings, side: networkDepotSide, worldRevision: worldRevision)
        if let memo = depotYardMemo, memo.key == key { return memo.preview }
        let preview = depotYardPreview(from: end, sidings: networkDepotSidings, side: networkDepotSide)
        depotYardMemo = DepotYardMemo(key: key, preview: preview)
        return preview
    }

    func depotYardPreview(from end: TrackNodeID, sidings: Int, side: PlatformTrackSide) -> DepotYardPreview {
        switch depotYardPlan(from: end, sidings: sidings, side: side) {
        case .failure(let problem):
            return DepotYardPreview(cost: nil, problem: problem.text(in: language), tracks: [])
        case .success(let plan):
            var draft = world
            do throws(GameError) {
                _ = try build(plan, in: &draft)
                return DepotYardPreview(cost: Money(world.economy.balance.amount - draft.economy.balance.amount), problem: nil, tracks: plan.points)
            } catch {
                return DepotYardPreview(cost: nil, problem: error.playerMessage(in: language), tracks: plan.points)
            }
        }
    }

    /// Lays the depot's sidings at ``networkDepotEnd`` (see the file's
    /// header), all or nothing.
    public func addDepotYard() {
        guard let end = networkDepotEnd else {
            message = StatusMessage(kind: .failure, text: DepotYardProblem.notAnEnd.text(in: language))
            return
        }
        let plan: DepotYardPlan
        switch depotYardPlan(from: end, sidings: networkDepotSidings, side: networkDepotSide) {
        case .success(let found): plan = found
        case .failure(let problem):
            message = StatusMessage(kind: .failure, text: problem.text(in: language))
            return
        }
        let balance = world.economy.balance
        let count = plan.platforms.count
        let built = perform(.buildDepotYard(plan)) { _, _, world in
            let cost = Money(balance.amount - world.economy.balance.amount)
            return language.text(
                "\(plan.name): \(count) \(count == 1 ? "siding" : "sidings"), for \(cost.moneyText). Choose it as a line's depot on the line panel.",
                "\(plan.name)：鋪好 \(count) 股停車線，花費 \(cost.moneyText)。到路線面板替路線選這個機廠。"
            )
        }
        if built != nil {
            networkDepotEnd = nil
            playSound?(.track)
        }
    }
}

extension TrackGeometry {
    /// How far along the centre line the place nearest `point` lies.
    func distance(alongTo point: PlanPoint) -> Int64 {
        let px = Double(point.x), py = Double(point.y)
        var best: (distance: Int64, squared: Double)?
        for index in points.indices.dropLast() {
            let a = points[index], b = points[index + 1]
            let ax = Double(a.x), ay = Double(a.y)
            let dx = Double(b.x) - ax, dy = Double(b.y) - ay
            let span = dx * dx + dy * dy
            let t = span > 0 ? min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / span)) : 0
            let ex = ax + t * dx - px, ey = ay + t * dy - py
            let squared = ex * ex + ey * ey
            guard best == nil || squared < best!.squared else { continue }
            best = (distances[index] + Int64((Double(distances[index + 1] - distances[index]) * t).rounded()), squared)
        }
        return best?.distance ?? 0
    }
}

extension DoubleTrack {
    /// Halfway between `a` and `b`.
    static func middle(_ a: WorldCoordinate, _ b: WorldCoordinate) -> WorldCoordinate {
        WorldCoordinate(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2)
    }
}

/// What the depot mode shows: the cost or why not, and each siding's line
/// on the map.
public struct DepotYardPreview: Sendable {
    public let cost: Money?
    public let problem: String?
    public let tracks: [[WorldCoordinate]]
}

struct DepotYardMemo {
    struct Key: Equatable {
        let end: TrackNodeID
        let sidings: Int
        let side: PlatformTrackSide
        let worldRevision: Int
    }

    let key: Key
    let preview: DepotYardPreview
}

extension GameSession {
    static func squaredDistance(_ a: PlanPoint, _ b: PlanPoint) -> Int64 {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

extension TrackNodeID {
    /// The node's number, as a log writes it.
    var number: Int {
        switch self {
        case .node(let number): number
        }
    }
}
