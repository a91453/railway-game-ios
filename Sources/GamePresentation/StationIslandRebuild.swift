import GameCore

// Decision 761: a station of two side platforms rebuilt as an island
// (decision 741's next ticket, `docs/handoff/ISLAND-PLATFORM.md`). A
// station on double track built with a platform on each track ("Double,
// two sides", decision 507), a bought line's station, and every station
// before decision 741 has its two tracks 5 m apart; the 3D map draws a
// platform outside each. Many real ones are islands. The station panel
// offers to rebuild it: one of the two tracks swings out round the
// station to stand an island's 11 m from the other (decision 507's
// "Double, island": a platform track 6 m outside it, joined by a turnout
// 88 m beyond each end, and its old stretch taken up), and the 3D map then
// draws one platform between them (decision 392). Nothing changes when a
// game is loaded and nothing is converted by itself: the panel offers,
// priced, and the player taps (a real side station would be converted
// wrongly, and a save is never changed when it is read, decision 315).
//
// The station's crossovers (decision 571) stand just past its platforms,
// where the new turnouts go: they are taken up first and laid again as
// they were, the near turnout on the same track, beyond the new turnouts.
// A line's chosen platforms (``LineRoutePreference``) are set aside while
// the track is cut and come back on the platforms laid in their place; a
// train in the way goes back to the start of its line, as the crossover
// button does (decision 572). No new GameCore rule and no new save field:
// it is the network tool's commands, logged as one (decision 193).
//
// No reference has a station rebuild (the earlier version's stations are
// data only); the steps are this project's own tools.

/// A station's side platforms rebuilt as an island (decision 761), as
/// planned on a copy of the world: the crossovers taken up, the moved
/// platform's track swung out (a platform track with its platform), its
/// old stretch taken up with its platform, and the crossovers laid again.
public struct StationIslandRebuild: Hashable, Sendable {
    let station: StationID
    /// The station's crossovers taken up first.
    let unjoined: [TrackEdgeID]
    /// The platform whose track swings out, as it stood.
    let moved: TrackPlatform
    /// The track it swings out to, and the platform on it.
    let track: PlatformTrackPlan
    /// The moved track's old stretch, taken up with its platform.
    let removed: [TrackEdgeID]
    /// The crossovers laid again beyond the new turnouts.
    let crossovers: [PlayerCommand.TrackStretch]
}

/// What the station panel offers to rebuild as an island (decision 761):
/// its price, or why it cannot be done.
public struct StationIslandOffer: Equatable, Sendable {
    public let cost: Money?
    public let problem: String?
}

/// ``GameSession/stationIslandOffer(for:)`` as last worked out.
struct StationIslandOfferMemo {
    let station: StationID
    let commandRevision: Int
    let cost: Money?
    let problem: String?
    let rebuild: StationIslandRebuild?
}

extension GameSession {
    /// The station panel's "Make it an island" (decision 761) for station
    /// `id`, priced, or why it cannot be done; `nil` when the station has
    /// no two side platforms 5 m apart. Worked out once for each station
    /// and command.
    public func stationIslandOffer(for id: StationID) -> StationIslandOffer? {
        let memo = stationIslandDraft(for: id)
        guard memo.cost != nil || memo.problem != nil else { return nil }
        if let cost = memo.cost, let rebuild = memo.rebuild {
            // The cash in hand now, as decision 572's offer (L9-3).
            return StationIslandOffer(cost: cost, problem: shortfallText(cost, doing: .rebuildStationAsIsland(rebuild)))
        }
        return StationIslandOffer(cost: nil, problem: memo.problem)
    }

    func stationIslandDraft(for id: StationID) -> StationIslandOfferMemo {
        if let memo = stationIslandOfferMemo, memo.station == id, memo.commandRevision == commandRevision { return memo }
        var memo = StationIslandOfferMemo(station: id, commandRevision: commandRevision, cost: nil, problem: nil, rebuild: nil)
        if allows(UnlockableTool.doubleTrack), world.station(id: id) != nil {
            switch stationIslandPlan(for: id) {
            case nil:
                break
            case .failure(let problem)?:
                memo = StationIslandOfferMemo(station: id, commandRevision: commandRevision, cost: nil, problem: problem.text(in: language), rebuild: nil)
            case .success(let rebuild)?:
                do throws(GameError) {
                    let cost = try priced { world throws(GameError) in try apply(.rebuildStationAsIsland(rebuild), to: &world) }.cost
                    memo = StationIslandOfferMemo(station: id, commandRevision: commandRevision, cost: cost, problem: nil, rebuild: rebuild)
                } catch {
                    memo = StationIslandOfferMemo(
                        station: id, commandRevision: commandRevision, cost: nil, problem: error.playerMessage(in: language), rebuild: nil
                    )
                }
            }
        }
        stationIslandOfferMemo = memo
        return memo
    }

    /// The panel's button.
    public func stationIslandButtonText(_ offer: StationIslandOffer) -> String {
        if let cost = offer.cost {
            return language.text("Make it an island platform (\(cost.moneyText))", "改成島式月台（\(cost.moneyText)）")
        }
        return language.text("Make it an island platform", "改成島式月台")
    }

    /// What the panel says under the button.
    public var stationIslandHelp: String {
        language.text(
            "One track swings out round the station so the two tracks share one platform between them. Lines keep their platforms; a train in the way goes back to the start of its line.",
            "其中一股軌道在站內往外移，兩股中間共用一座月台。路線指定的月台會跟著換過去；擋在軌道上的列車會回到路線起點。"
        )
    }

    /// Rebuilds station `id` as ``stationIslandOffer(for:)`` offers, as
    /// one command that undo takes back.
    public func rebuildStationAsIsland(_ id: StationID) {
        guard let rebuild = stationIslandDraft(for: id).rebuild else { return }
        let name = world.station(id: id)?.name ?? ""
        let done = perform(.rebuildStationAsIsland(rebuild)) { outcome, before, world in
            let cost = Money(before.economy.balance.amount - world.economy.balance.amount)
            return language.text(
                "\(name) now has an island platform between its two tracks, for \(cost.moneyText).",
                "\(name)已改成島式月台，兩股軌道共用中間一座月台，花費 \(cost.moneyText)。"
            ) + Self.liftedText(outcome, in: language)
        }
        if done != nil { playSound?(.track) }
    }

    // MARK: - Planning

    /// Station `id`'s rebuild as an island, planned on a copy of the world,
    /// or why it cannot be laid; `nil` when it has no two side platforms.
    /// Each pair is tried with either track swinging out.
    func stationIslandPlan(for id: StationID) -> Result<StationIslandRebuild, StationLayoutProblem>? {
        let pairs = sidePlatformPairs(of: id, in: world)
        guard !pairs.isEmpty else { return nil }
        var last = StationLayoutProblem.track(.noRoom)
        for (kept, moved) in pairs {
            var planned: StationIslandRebuild?
            var problem: StationLayoutProblem?
            var probe = world.pricingCopy()
            do throws(GameError) {
                _ = try withRoutesAndTrainsAside(at: id, moved: moved, in: &probe) { world throws(GameError) in
                    planned = nil
                    problem = nil
                    switch planIsland(id, kept: kept, moved: moved, in: &world) {
                    case .success(let found):
                        planned = found.rebuild
                        return found.platform
                    case .failure(.refused(let error)):
                        // A train in the way is lifted and it is tried again.
                        problem = .refused(error)
                        throw error
                    case .failure(let found):
                        problem = found
                        throw GameError.invalidTrackGeometry
                    }
                }
            } catch {
                last = problem ?? .refused(error)
                continue
            }
            if let planned { return .success(planned) }
        }
        return .failure(last)
    }

    /// The station's pairs of platforms on two tracks 5 m apart, each with
    /// none other within an island's spacing (one in an island already),
    /// as (kept, moved): the later one moved first, then the other.
    func sidePlatformPairs(of id: StationID, in world: GameWorld) -> [(kept: TrackPlatform, moved: TrackPlatform)] {
        let platforms = world.trackPlatforms(of: id)
        let middles = platforms.map { middle(of: ($0.edge, $0.start, $0.end), in: world) }
        let island = PlatformTrackLayout.island.spacing
        let near = DoubleTrack.spacing + WorldCoordinate.unitsPerMetre
        func inIsland(_ index: Int) -> Bool {
            middles.indices.contains { other in
                guard other != index else { return false }
                let distance = Self.squaredDistance(middles[index], middles[other])
                return distance > near * near && distance < (island + 4 * WorldCoordinate.unitsPerMetre) * (island + 4 * WorldCoordinate.unitsPerMetre)
                    && platforms[other].edge != platforms[index].edge
            }
        }
        var pairs: [(kept: TrackPlatform, moved: TrackPlatform)] = []
        for (index, platform) in platforms.enumerated() where !inIsland(index) {
            guard let beside = trackBeside(platform.edge, near: middles[index], in: world)?.beside,
                  let other = platforms.firstIndex(where: {
                      $0.edge == beside.edge && $0.start - DoubleTrack.besideInset <= beside.distance && beside.distance <= $0.end + DoubleTrack.besideInset
                  }),
                  other > index, !inIsland(other) else { continue }
            pairs.append((platform, platforms[other]))
            pairs.append((platforms[other], platform))
        }
        return pairs
    }

    /// Plans and builds the rebuild in `world`: the station's crossovers
    /// between `kept` and `moved` taken up, `moved`'s track swung out
    /// from `kept`'s to an island's spacing, its old stretch taken up, and
    /// the crossovers laid again beyond the new turnouts. Returns the plan
    /// and the new platform.
    private func planIsland(_ id: StationID, kept: TrackPlatform, moved: TrackPlatform, in world: inout GameWorld)
        -> Result<(rebuild: StationIslandRebuild, platform: TrackPlatform), StationLayoutProblem>
    {
        let island = PlatformTrackLayout.island
        let chains = stationCrossoverChains(between: kept, and: moved, in: world)
        let unjoined = chains.flatMap(\.edges)
        do throws(GameError) {
            for edge in unjoined {
                _ = try apply(.removeTrack(edge), to: &world)
            }
        } catch {
            return .failure(.refused(error))
        }
        guard let away = side(of: moved, awayFrom: kept, in: world) else { return .failure(.track(.missing)) }
        let old = middle(of: (moved.edge, moved.start, moved.end), in: world)
        let plan: PlatformTrackPlan
        switch sidingPlan(
            on: moved.edge, from: moved.start, to: moved.end, spacing: island.spacing - DoubleTrack.spacing, reach: island.reach, side: away,
            in: world
        ) {
        case .failure(let problem): return .failure(.track(problem))
        case .success(let siding):
            plan = PlatformTrackPlan(
                platform: moved, near: siding.near, far: siding.far, beside: siding.beside, curves: siding.curves, structure: siding.structure
            )
        }
        let platform: TrackPlatform
        do throws(GameError) {
            platform = try build(plan, in: &world)
        } catch {
            return .failure(.refused(error))
        }
        guard let taken = stretchBetween(plan.near.position.plan, plan.far.position.plan, through: old, in: world) else {
            return .failure(.track(.noRoom))
        }
        do throws(GameError) {
            try takeUp(taken, of: id, in: &world)
        } catch {
            return .failure(.refused(error))
        }
        // The crossovers again, each beyond the new turnout on its side:
        // one that no longer fits is left out (the panel's crossover
        // button, decision 572, offers it).
        var crossovers: [PlayerCommand.TrackStretch] = []
        for chain in chains {
            guard let crossover = relaidCrossover(kept: kept, forward: chain.forward, nearOnKept: chain.nearOnKept, in: world) else { continue }
            var draft = world
            guard (try? crossover.build(in: &draft, heights: heights)) != nil else { continue }
            world = draft
            crossovers.append(crossover)
        }
        let rebuild = StationIslandRebuild(station: id, unjoined: unjoined, moved: moved, track: plan, removed: taken, crossovers: crossovers)
        return .success((rebuild, platform))
    }

    /// Takes up `edges` and station `id`'s platforms on them.
    private func takeUp(_ edges: [TrackEdgeID], of id: StationID, in world: inout GameWorld) throws(GameError) {
        for platform in world.trackPlatforms(of: id) where edges.contains(platform.edge) {
            try world.removeTrackPlatform(id, on: platform.edge, from: platform.start)
        }
        for edge in edges {
            _ = try apply(.removeTrack(edge), to: &world)
        }
    }

    /// The crossovers between the tracks of `a` and `b` (decision 571): from
    /// the first turnout past each end of `a`'s track, within a station's
    /// throat, to the first past the same end of `b`'s. `forward`: past
    /// the end of `a` along its edge; `nearOnKept`: the turnout nearer the
    /// station is on `a`'s track.
    func stationCrossoverChains(between a: TrackPlatform, and b: TrackPlatform, in world: GameWorld)
        -> [(edges: [TrackEdgeID], forward: Bool, nearOnKept: Bool)]
    {
        let fromB = [false, true].compactMap { firstTurnout(from: b, forward: $0, in: world) }
        var chains: [(edges: [TrackEdgeID], forward: Bool, nearOnKept: Bool)] = []
        for forward in [false, true] {
            guard let turnout = firstTurnout(from: a, forward: forward, in: world),
                  let exits = world.network.node(turnout.node)?.end(of: turnout.came)?.exits else { continue }
            for exit in exits {
                guard let walked = plainChain(from: turnout.node, along: exit, in: world),
                      let other = fromB.first(where: { $0.node == walked.end }) else { continue }
                chains.append((walked.edges, forward, turnout.travelled <= other.travelled))
                break
            }
        }
        return chains
    }

    /// The first node where track branches along the track from the
    /// `forward` end of `platform` (its `end`, else its `start`), within
    /// ``DoubleTrack/stationThroat``: the node, the edge it was reached by
    /// and how far it is.
    private func firstTurnout(from platform: TrackPlatform, forward: Bool, in world: GameWorld)
        -> (node: TrackNodeID, came: TrackEdgeID, travelled: Int64)?
    {
        guard let edge = world.network.edge(platform.edge) else { return nil }
        var travelled = forward ? edge.length - platform.end : platform.start
        var node = forward ? edge.to : edge.from
        var came = platform.edge
        for _ in 0..<64 {
            guard travelled <= DoubleTrack.stationThroat, let ends = world.network.node(node)?.ends else { return nil }
            if ends.count >= 3 { return (node, came, travelled) }
            guard ends.count == 2, let next = ends.first(where: { $0.edge != came }), let nextEdge = world.network.edge(next.edge) else { return nil }
            travelled += nextEdge.length
            node = nextEdge.from == node ? nextEdge.to : nextEdge.from
            came = next.edge
        }
        return nil
    }

    /// The edges from `start` along `first` through plain joints to the
    /// next node where track branches, and that node.
    private func plainChain(from start: TrackNodeID, along first: TrackEdgeID, in world: GameWorld) -> (edges: [TrackEdgeID], end: TrackNodeID)? {
        var edges: [TrackEdgeID] = [], node = start, edgeID = first
        for _ in 0..<16 {
            guard let edge = world.network.edge(edgeID) else { return nil }
            edges.append(edgeID)
            node = edge.from == node ? edge.to : edge.from
            guard let ends = world.network.node(node)?.ends else { return nil }
            if ends.count != 2 { return ends.count >= 3 ? (edges, node) : nil }
            guard let next = ends.first(where: { $0.edge != edgeID }) else { return nil }
            edgeID = next.edge
        }
        return nil
    }

    /// A crossover between `kept`'s track and the track beside it past the
    /// `forward` end of `kept`, beyond the new track's turnout there: its
    /// near turnout an island's reach and two margins out, on `kept`'s
    /// track where `nearOnKept`, else on the other; its far one a
    /// crossover's reach further, on the other track.
    private func relaidCrossover(kept: TrackPlatform, forward: Bool, nearOnKept: Bool, in world: GameWorld) -> PlayerCommand.TrackStretch? {
        let near = PlatformTrackLayout.island.reach + 2 * DoubleTrack.crossoverMargin
        let far = near + DoubleTrack.crossoverReach
        func onKept(_ reach: Int64) -> WorldCoordinate? {
            platformTrackTurnout(from: kept.edge, at: forward ? kept.end : kept.start, forward: forward, reach: reach, in: world)?.position
        }
        func beside(_ point: WorldCoordinate) -> WorldCoordinate? {
            guard let edge = world.trackEdgePoint(near: point.plan, within: 16),
                  let found = trackBeside(edge.edge, near: point.plan, in: world)?.beside,
                  let geometry = world.trackGeometry(of: found.edge) else { return nil }
            return geometry.location(at: min(max(0, found.distance), geometry.length)).position
        }
        guard let keptNear = onKept(near), let keptFar = onKept(far) else { return nil }
        if nearOnKept {
            guard let other = beside(keptFar) else { return nil }
            return crossoverStretch(from: other, to: keptNear, in: world)
        }
        guard let other = beside(keptNear) else { return nil }
        return crossoverStretch(from: keptFar, to: other, in: world)
    }

    // MARK: - Building

    /// Builds `rebuild` in `world` (``PlayerCommand/rebuildStationAsIsland(_:)``).
    func build(_ rebuild: StationIslandRebuild, in world: inout GameWorld) throws(GameError) -> PlayerCommand.Outcome {
        guard world.station(id: rebuild.station) != nil else { throw .unknownStation(rebuild.station) }
        guard rebuild.track.platform.station == rebuild.station, rebuild.moved.station == rebuild.station else { throw .invalidPlatform }
        var outcome = PlayerCommand.Outcome()
        outcome.left = try withRoutesAndTrainsAside(at: rebuild.station, moved: rebuild.moved, in: &world) { world throws(GameError) in
            for edge in rebuild.unjoined {
                _ = try apply(.removeTrack(edge), to: &world)
            }
            let platform = try build(rebuild.track, in: &world)
            try takeUp(rebuild.removed, of: rebuild.station, in: &world)
            for crossover in rebuild.crossovers {
                _ = try crossover.build(in: &world, heights: heights)
            }
            return platform
        }
        outcome.station = world.station(id: rebuild.station)
        return outcome
    }

    /// Runs `steps` on `world` with the lines' chosen platforms and walks
    /// set aside (GameCore cuts no track a line's chosen way runs along)
    /// and each train in the way taken off its line and the track; then
    /// puts the chosen platforms back, `moved` and any other of station
    /// `id`'s platforms gone as the nearest one left (`moved` as the one
    /// `steps` returns), the walks where their track still stands, and
    /// the trains back on their lines. Returns the names of the trains
    /// moved. All or nothing.
    private func withRoutesAndTrainsAside(
        at id: StationID, moved: TrackPlatform, in world: inout GameWorld,
        _ steps: (inout GameWorld) throws(GameError) -> TrackPlatform
    ) throws(GameError) -> [String] {
        let original = world
        var base = world
        for line in original.lines {
            for service in 0...line.patterns.count {
                let routes = service == 0 ? line.routePreferences : line.patterns[service - 1].routePreferences
                guard !routes.isEmpty else { continue }
                let aside = routes.compactMap { route -> LineRoutePreference? in
                    let platforms = [route.platform] + route.alternates
                    if platforms.contains(where: { $0.station == id }) { return nil }
                    return LineRoutePreference(from: route.from, to: route.to, platform: route.platform, alternates: route.alternates)
                }
                guard aside != routes else { continue }
                try base.setLineRoutePreferences(line.id, to: aside, pattern: service == 0 ? nil : service - 1)
            }
        }
        var lifted: [(train: TrainID, line: LineID, pattern: Int?)] = []
        var platform: TrackPlatform
        while true {
            var attempt = base
            do throws(GameError) {
                platform = try steps(&attempt)
                base = attempt
                break
            } catch {
                let train: TrainID?
                switch error {
                case .trackReserved(let id), .trainServiceActive(let id): train = id
                case .trackEdgeInUse(let edge):
                    train = base.trains.first { train in
                        if case .onEdge(let traversal, _)? = train.position, traversal.edge == edge { return true }
                        return train.trailEdges.contains(edge)
                    }?.id
                default: train = nil
                }
                guard let train, !lifted.contains(where: { $0.train == train }), let line = base.assignedLine(of: train) else { throw error }
                let pattern = base.assignedPattern(of: train)
                try base.unassignTrain(train)
                if base.train(id: train)?.execution != nil { try base.stopTrainService(train) }
                if base.train(id: train)?.position != nil { try base.unplaceTrain(train) }
                lifted.append((train, line, pattern))
            }
        }
        // The chosen platforms back, on the platforms laid in their place.
        let left = base.trackPlatforms(of: id).filter { $0 != platform }
        func placed(_ old: TrackPlatform) -> TrackPlatform {
            if old == moved { return platform }
            if old.station != id || base.trackPlatforms(of: id).contains(old) { return old }
            let point = middle(of: (old.edge, old.start, old.end), in: original)
            return left.min { Self.squaredDistance(middle(of: ($0.edge, $0.start, $0.end), in: base), point)
                < Self.squaredDistance(middle(of: ($1.edge, $1.start, $1.end), in: base), point) } ?? old
        }
        for line in original.lines {
            for service in 0...line.patterns.count {
                let routes = service == 0 ? line.routePreferences : line.patterns[service - 1].routePreferences
                guard !routes.isEmpty else { continue }
                let back = routes.map { route -> LineRoutePreference in
                    let first = placed(route.platform)
                    var alternates: [TrackPlatform] = []
                    for alternate in route.alternates.map(placed) where alternate != first && !alternates.contains(alternate) {
                        alternates.append(alternate)
                    }
                    let kept = first == route.platform && route.tracks.allSatisfy { base.network.edge($0.edge) != nil }
                    return LineRoutePreference(from: route.from, to: route.to, tracks: kept ? route.tracks : [], platform: first, alternates: alternates)
                }
                let pattern = service == 0 ? nil : service - 1
                do throws(GameError) {
                    try base.setLineRoutePreferences(line.id, to: back, pattern: pattern)
                } catch {
                    // A walk the track no longer takes: the platforms alone.
                    try base.setLineRoutePreferences(
                        line.id, to: back.map { LineRoutePreference(from: $0.from, to: $0.to, platform: $0.platform, alternates: $0.alternates) },
                        pattern: pattern
                    )
                }
            }
        }
        let names = try putBack(lifted, in: &base)
        world = base
        return names
    }
}
