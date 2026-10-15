import GameCore

// The double track's crossover where it joins the track already there
// (decision 204, later): a stretch drawn from a station's track or a
// turnout joins it, but its parallel ends beside it, joined to nothing. So
// at each such end a single crossover is built with the stretch, from the
// parallel over to the stretch just before the end, as the network tool
// builds one by hand (two places on two tracks, ``GameSession/networkPicksCrossover``):
// a turnout on each, the S-curve between them. Trains on the parallel then
// reach the track the stretch joined. It is part of the same command, so
// all of it is built or none.
//
// Where there is no room for one (the stretch too short, or steeper than a
// turnout may stand on, decision 233), the double track is built without it
// and the message says so. On a grade the crossover stands on the steady
// grade, past the vertical curve at that end. Neither reference has a tool that
// adds a crossover (`Simulator/` has crossover pieces to place by hand,
// `MapBuilder/` none): this is native.

extension DoubleTrack {
    /// How far from the joined end the crossover meets the stretch: a
    /// split must leave this much on each side
    /// (``NetworkBuilding/minimumSpacing``, 22 m).
    static let crossoverMargin: Int64 = NetworkBuilding.minimumSpacing
    /// How far along the crossover runs while it goes over the 5 m: as a
    /// side platform track's turnout (``PlatformTrackLayout/reach``, 50 m).
    static let crossoverReach: Int64 = PlatformTrackLayout.side.reach

    /// What became of the crossovers a double track wanted.
    public enum CrossoverOutcome: Hashable, Sendable {
        /// Neither end joins track already there: none needed.
        case none
        /// Built at this many ends.
        case built(Int)
        /// Wanted at an end but no room there (too short, too steep, or
        /// GameCore refused its way).
        case noRoom
        /// GameCore refused it for want of money: the double track is not
        /// built either.
        case refused(GameError)
    }
}

extension GameSession {
    /// The crossovers a double track needs, built in `world` after the
    /// stretch (`main`, edge `mainEdge`) and its parallel (edge
    /// `parallelEdge`): one at each end where `main` joins the track
    /// already there (``needsCrossover(_:in:)``, read in `before`, the world
    /// before either was built) and the parallel does not. Returns them as
    /// the command builds them, in order, and what became of them.
    func doubleTrackCrossovers(
        main: EdgePlan, parallel: EdgePlan, mainEdge: TrackEdgeID, parallelEdge: TrackEdgeID,
        before: GameWorld, in world: inout GameWorld
    ) -> (stretches: [PlayerCommand.TrackStretch], outcome: DoubleTrack.CrossoverOutcome) {
        let atStart = needsCrossover(main.start, in: before) && !parallel.start.isNode
        let atEnd = needsCrossover(main.end, in: before) && !parallel.end.isNode
        guard atStart || atEnd else { return ([], .none) }
        // Decision 233: a turnout stands on a slope no steeper than
        // GameCore allows it, on the steady grade past any vertical curve.
        guard let mainGeometry = world.trackGeometry(of: mainEdge), let parallelGeometry = world.trackGeometry(of: parallelEdge),
              let mainProfile = world.network.edge(mainEdge)?.profile, let parallelProfile = world.network.edge(parallelEdge)?.profile,
              mainGeometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumTurnoutGrade),
              parallelGeometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumTurnoutGrade)
        else { return ([], .noRoom) }
        // Where each crossover meets each track, as positions: the first one
        // built splits the edges, so the second finds its places again.
        // Each is `margin` in from the end, or from where the vertical curve
        // there ends if that is farther.
        let reach = DoubleTrack.crossoverReach
        let startMargin = max(DoubleTrack.crossoverMargin, mainProfile.startTransition, parallelProfile.startTransition)
        let endMargin = max(DoubleTrack.crossoverMargin, mainProfile.endTransition, parallelProfile.endTransition)
        let wanted = (atStart ? startMargin + reach : 0) + (atEnd ? endMargin + reach : 0)
        guard parallelGeometry.length >= wanted + NetworkBuilding.minimumSpacing,
              mainGeometry.length >= wanted + NetworkBuilding.minimumSpacing
        else { return ([], .noRoom) }
        var pairs: [(onParallel: WorldCoordinate, onMain: WorldCoordinate)] = []
        if atStart {
            pairs.append((parallelGeometry.location(at: startMargin + reach).position, mainGeometry.location(at: startMargin).position))
        }
        if atEnd {
            pairs.append((parallelGeometry.location(at: parallelGeometry.length - endMargin - reach).position,
                          mainGeometry.location(at: mainGeometry.length - endMargin).position))
        }
        var draft = world
        var stretches: [PlayerCommand.TrackStretch] = []
        for pair in pairs {
            guard let stretch = crossoverStretch(from: pair.onParallel, to: pair.onMain, in: draft) else { return ([], .noRoom) }
            do throws(GameError) {
                _ = try stretch.build(in: &draft, heights: heights)
            } catch {
                // Short of money: the crossover is part of the double
                // track, so the command keeps it and all of it is refused.
                if case .insufficientFunds = error { return (stretches + [stretch], .refused(error)) }
                return ([], .noRoom)
            }
            stretches.append(stretch)
        }
        world = draft
        return (stretches, .built(stretches.count))
    }

    /// Whether a double track's stretch ending at `anchor` joins the track
    /// already there: a node some edge ends at, or a place on an edge.
    func needsCrossover(_ anchor: NetworkAnchor, in world: GameWorld) -> Bool {
        switch anchor {
        case .node(let id): !(world.network.node(id)?.ends.isEmpty ?? true)
        case .track: true
        case .point: false
        }
    }

    /// A single crossover from the track at `from` to the track at `to`,
    /// leaving each along it toward the other: the curve the network tool
    /// lays between two places on two tracks.
    private func crossoverStretch(from: WorldCoordinate, to: WorldCoordinate, in world: GameWorld) -> PlayerCommand.TrackStretch? {
        guard let start = world.trackEdgePoint(near: from.plan, within: 16), let end = world.trackEdgePoint(near: to.plan, within: 16),
              start.edge != end.edge,
              let first = world.position(of: .track(start), height: 0), let last = world.position(of: .track(end), height: 0),
              let leaving = world.joiningDirection(at: start, toward: last.plan),
              let arriving = world.joiningDirection(at: end, toward: first.plan),
              let curve = NetworkBuilding.curve(from: first.plan, leaving: leaving, to: last.plan, leaving: arriving),
              let geometry = TrackGeometry(from: first, to: last, curve: curve)
        else { return nil }
        return PlayerCommand.TrackStretch(
            start: .track(start), end: .track(end), from: first, to: last, curve: curve, profile: .uniform,
            structure: networkStructure, ground: [first.plan, last.plan] + NetworkBuilding.surveyedPoints(of: geometry)
        )
    }

    /// What the network tool's message adds for a double track's
    /// crossovers.
    static func crossoverText(_ outcome: DoubleTrack.CrossoverOutcome, in language: DisplayLanguage) -> String {
        switch outcome {
        case .none: ""
        case .built(let count):
            count == 1
                ? language.text(" A crossover joins the second track to the track it meets.", "第二條在接上既有軌道的一端加了渡線。")
                : language.text(" Crossovers join the second track to the track at both ends.", "第二條在兩端都加了渡線，接上既有軌道。")
        case .refused: ""
        case .noRoom:
            language.text(
                " The second track is not joined to the track it meets: no room for a crossover (too short, or too steep). Add one by hand.",
                "第二條沒有接上既有軌道：放不下渡線（太短或太陡），請手動加渡線。"
            )
        }
    }
}

extension PlayerCommand.TrackStretch {
    /// Its centre line, for drawing.
    var geometryPoints: [WorldCoordinate] {
        TrackGeometry(from: from, to: to, curve: curve, profile: profile)?.points ?? [from, to]
    }
}

extension NetworkAnchor {
    /// Whether it is a node already there.
    var isNode: Bool {
        if case .node = self { true } else { false }
    }
}
