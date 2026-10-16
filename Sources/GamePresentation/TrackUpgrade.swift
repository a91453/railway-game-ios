import GameCore

// Upgrading the track the select tool picked (ARCHITECTURE decision 257,
// the author's report: "點選軌道有升級複線或加入 X 轉轍器的選項"). On single
// track, "Make double track" lays a second track 5 m beside it, from the
// switch or track end before it to the one after (or only the piece
// picked), with the platforms its stations have copied onto the second
// track for the same stations, and a crossover at each end joining the two
// (``planDoubleChain(main:run:parallel:platforms:wantsCrossover:in:)``).
// On double track (a second track about 5 m beside it), "Add X crossover"
// builds one where the track was tapped, as the network tool builds one
// between two picked places (``scissorsPlan(from:to:)``). Each is shown
// first, with its whole price (decision 245), and built with ✓ as one
// command that undo takes back. Drawing parallel track by hand stays.

/// What the select tool's track card is about to build on the picked
/// track.
public enum TrackUpgradeKind: Hashable, Sendable {
    /// A second track beside it.
    case doubleTrack
    /// An X crossover between it and the track beside it.
    case scissors
}

/// The upgrade drafted on the picked track: what it lays, what it costs or
/// why it cannot be built, and a note for the player.
public struct TrackUpgradePreview: Equatable, Sendable {
    /// The new track, piece by piece, for the map.
    public let track: [[WorldCoordinate]]
    public let cost: Money?
    public let problem: String?
    /// What it does besides, as the player reads it: how long, the
    /// crossovers and platforms.
    public let note: String?
}

/// The upgrade worked out for a draft and a world (``GameSession/trackUpgradePreview``).
struct TrackUpgradeMemo {
    struct Key: Equatable {
        let kind: TrackUpgradeKind
        let edge: TrackEdgeID
        let point: PlanPoint?
        let side: PlatformTrackSide
        let wholeRun: Bool
        let worldRevision: Int
    }

    let key: Key
    let preview: TrackUpgradePreview
    let command: PlayerCommand?
}

extension DoubleTrack {
    /// How far beside a track another is looked for, to call it double:
    /// 3 m to 6 m (``RailwayNetwork/trackSpacing`` is 4 m, the tool lays 5 m).
    static let besideProbe: Int64 = 288
    static let besideReach: Int64 = 96
    /// How long an X crossover the track card builds is along the track:
    /// as a single crossover's reach, 50 m.
    static let scissorsLength: Int64 = crossoverReach
    /// The most pieces of track a run to the switches takes in.
    static let longestRun = 400
}

extension GameSession {
    // MARK: - What the picked track offers

    /// The track beside the picked track where it was tapped (decision
    /// 247): a different edge about 5 m to one side, running along it.
    func trackBeside(_ id: TrackEdgeID, near point: PlanPoint?) -> (place: NetworkEdgePoint, beside: NetworkEdgePoint)? {
        guard let geometry = world.trackGeometry(of: id) else { return nil }
        let place = point.flatMap { world.nearestPoint(onEdge: id, to: $0) } ?? NetworkEdgePoint(edge: id, distance: geometry.length / 2)
        let location = geometry.location(at: min(max(0, place.distance), geometry.length))
        for side in PlatformTrackSide.allCases {
            let probe = DoubleTrack.beside(location.position, way: location.direction, side: side, distance: DoubleTrack.besideProbe)
            guard let found = world.trackEdgePoint(near: probe.plan, within: DoubleTrack.besideReach), found.edge != id,
                  let other = world.trackGeometry(of: found.edge) else { continue }
            let way = other.location(at: min(max(0, found.distance), other.length)).direction
            let a = location.direction, b = way
            let cross = Double(a.dx) * Double(b.dy) - Double(a.dy) * Double(b.dx)
            let lengths = (Double(a.dx) * Double(a.dx) + Double(a.dy) * Double(a.dy)).squareRoot()
                * (Double(b.dx) * Double(b.dx) + Double(b.dy) * Double(b.dy)).squareRoot()
            // Within about 15° of it.
            guard lengths > 0, abs(cross) / lengths < 0.26 else { continue }
            return (place, found)
        }
        return nil
    }

    /// Whether the select tool picked single track that "Make double
    /// track" can be offered on: track with none beside it.
    public var canDoubleSelectedTrack: Bool {
        guard tool == .select, let id = selectedTrackEdge, world.network.edge(id) != nil else { return false }
        return trackBeside(id, near: selectedPoint) == nil
    }

    /// Whether the select tool picked double track, for "Add X crossover".
    public var canAddScissorsOnSelectedTrack: Bool {
        guard tool == .select, let id = selectedTrackEdge else { return false }
        return trackBeside(id, near: selectedPoint) != nil
    }

    // MARK: - Drafting

    /// Starts drafting `kind` on the picked track: the card shows its
    /// preview until ✓ or ✗. Never changes the world.
    public func beginTrackUpgrade(_ kind: TrackUpgradeKind) {
        guard selectedTrackEdge != nil else { return }
        trackUpgrade = kind
        message = nil
    }

    /// Forgets the drafted upgrade. Never changes the world.
    public func cancelTrackUpgrade() {
        trackUpgrade = nil
    }

    /// The drafted upgrade on the picked track, worked out once for each
    /// draft and world; `nil` when none is drafted.
    public var trackUpgradePreview: TrackUpgradePreview? {
        trackUpgradeDraft?.preview
    }

    var trackUpgradeDraft: TrackUpgradeMemo? {
        guard tool == .select, let kind = trackUpgrade, let edge = selectedTrackEdge else { return nil }
        _ = world
        let key = TrackUpgradeMemo.Key(
            kind: kind, edge: edge, point: kind == .scissors ? selectedPoint : nil, side: trackUpgradeSide,
            wholeRun: trackUpgradeWholeRun, worldRevision: worldRevision
        )
        if let memo = trackUpgradeMemo, memo.key == key { return memo }
        let found = switch kind {
        case .doubleTrack: doubleTrackUpgrade(of: edge, key: key)
        case .scissors: scissorsUpgrade(on: edge, key: key)
        }
        trackUpgradeMemo = found
        return found
    }

    /// The compass side the second track goes on, for the card's picker.
    public func trackUpgradeSideText(_ side: PlatformTrackSide) -> String {
        guard let id = selectedTrackEdge, let run = trackRun(from: id, whole: trackUpgradeWholeRun).first,
              let segment = ChainSegment(edge: run.edge, reversed: run.reversed, in: world), let geometry = segment.geometry
        else { return "" }
        return sideText(side, of: geometry.location(at: geometry.length / 2).direction)
    }

    /// Builds the drafted upgrade, all or nothing, and forgets it.
    public func buildTrackUpgrade() {
        guard let draft = trackUpgradeDraft else { return }
        // Short of cash, GameCore refuses it and says so (decision 245).
        guard let command = draft.command else {
            message = StatusMessage(kind: .failure, text: draft.preview.problem ?? "")
            return
        }
        let note = draft.preview.note
        let done = perform(command) { _, before, world in
            let cost = Money(before.economy.balance.amount - world.economy.balance.amount)
            let what = switch command {
            case .buildCrossover: language.text("Built an X crossover", "已建造 X 型交叉渡線")
            default: language.text("Made the track double", "已升級為複線")
            }
            return language.text("\(what) for \(cost.moneyText).", "\(what)，花費 \(cost.moneyText)。") + (note.map { " " + $0 } ?? "")
        }
        if done != nil {
            trackUpgrade = nil
            playSound?(.track)
        }
    }

    // MARK: - Double track

    /// The run of track from `id` through each node where it runs straight
    /// on (two edges end there, each the other's way on), to the switch,
    /// track end or crossing at each end; only `id` unless `whole`. In
    /// order, each edge with whether it is run from its `to` end.
    func trackRun(from id: TrackEdgeID, whole: Bool) -> [(edge: TrackEdgeID, reversed: Bool)] {
        guard let first = world.network.edge(id) else { return [] }
        var run: [(edge: TrackEdgeID, reversed: Bool)] = [(id, false)]
        guard whole else { return run }
        var seen: Set<TrackEdgeID> = [id]
        // The next edge on from `node`, reached along `edge`.
        func next(from node: TrackNodeID, along edge: TrackEdgeID) -> TrackEdge? {
            guard let here = world.network.node(node), here.ends.count == 2,
                  let other = here.ends.first(where: { $0.edge != edge }), here.end(of: edge)?.exits.contains(other.edge) == true,
                  !seen.contains(other.edge), run.count < DoubleTrack.longestRun
            else { return nil }
            return world.network.edge(other.edge)
        }
        var node = first.to, edge = id
        while let found = next(from: node, along: edge) {
            seen.insert(found.id)
            let reversed = found.to == node
            run.append((found.id, reversed))
            node = reversed ? found.from : found.to
            edge = found.id
        }
        node = first.from
        edge = id
        while let found = next(from: node, along: edge) {
            seen.insert(found.id)
            // Run toward `node`: forward when it ends there.
            let reversed = found.from == node
            run.insert((found.id, reversed), at: 0)
            node = reversed ? found.to : found.from
            edge = found.id
        }
        return run
    }

    private func doubleTrackUpgrade(of id: TrackEdgeID, key: TrackUpgradeMemo.Key) -> TrackUpgradeMemo {
        func refused(_ problem: String) -> TrackUpgradeMemo {
            TrackUpgradeMemo(key: key, preview: TrackUpgradePreview(track: [], cost: nil, problem: problem, note: nil), command: nil)
        }
        let run = trackRun(from: id, whole: trackUpgradeWholeRun)
        let segments = run.compactMap { ChainSegment(edge: $0.edge, reversed: $0.reversed, in: world) }
        guard !run.isEmpty, segments.count == run.count else { return refused(language.text("This track is gone.", "這段軌道已經不在了。")) }
        guard let parallel = parallelChain(beside: segments, side: trackUpgradeSide, in: world) else {
            return refused(language.text(
                "There is no room for the second track 5 m beside this track. Try the other side.",
                "這段旁邊 5 公尺放不下第二條軌道。請換另一側。"
            ))
        }
        // The stations' platforms, on the second track for the same
        // stations, where they lie along the first.
        var platforms: [ChainPlatform] = []
        var stations: Set<StationID> = []
        for (index, piece) in run.enumerated() {
            guard let main = segments[index].geometry, let beside = ChainSegment(parallel[index]).geometry, main.length > 0 else { continue }
            for platform in world.network.platforms(on: piece.edge) {
                let start = piece.reversed ? main.length - platform.end : platform.start
                let end = piece.reversed ? main.length - platform.start : platform.end
                func scaled(_ distance: Int64) -> Int64 {
                    min(beside.length, max(0, Int64((Double(distance) * Double(beside.length) / Double(main.length)).rounded())))
                }
                platforms.append(ChainPlatform(station: platform.station, piece: index, start: scaled(start), end: scaled(end)))
                stations.insert(platform.station)
            }
        }
        let length = segments.compactMap { $0.geometry?.length }.reduce(0, +)
        let plan: DoubleChainPlan
        do throws(GameError) {
            plan = try planDoubleChain(main: [], run: run, parallel: parallel, platforms: platforms, wantsCrossover: (true, true), in: world)
        } catch {
            return TrackUpgradeMemo(key: key, preview: TrackUpgradePreview(
                track: parallel.map(\.geometryPoints), cost: nil, problem: error.playerMessage(in: language), note: nil
            ), command: nil)
        }
        let cost = Money(GameWorld.pricingBalance.amount - plan.built.economy.balance.amount)
        var note = language.text(
            "\(NetworkBuilding.distanceText(length, in: language)) of second track.",
            "第二條軌道 \(NetworkBuilding.distanceText(length, in: language))。"
        )
        switch plan.outcome {
        case .built(let count):
            note += count == 2
                ? language.text(" Crossovers join the two tracks at both ends.", "兩端都有渡線連接兩條軌道。")
                : language.text(" A crossover joins the two tracks at one end.", "一端有渡線連接兩條軌道。")
        case .noRoom:
            note += language.text(
                " No room for a crossover at an end (too short, too steep, or trains in the way): add one by hand.",
                "有一端放不下渡線（太短、太陡或有列車擋住），請手動加渡線。"
            )
        case .none, .refused:
            break
        }
        if !stations.isEmpty {
            note += language.text(
                stations.count == 1 ? " Its station gets a platform on the second track." : " Its \(stations.count) stations get platforms on the second track.",
                "經過的 \(stations.count) 個車站在第二條軌道也加月台。"
            )
        }
        return TrackUpgradeMemo(key: key, preview: TrackUpgradePreview(
            track: [plan.parallelPoints] + plan.crossoverPoints, cost: cost,
            problem: shortfallText(cost, doing: plan.command), note: note
        ), command: plan.command)
    }

    // MARK: - X crossover

    private func scissorsUpgrade(on id: TrackEdgeID, key: TrackUpgradeMemo.Key) -> TrackUpgradeMemo {
        func refused(_ problem: String) -> TrackUpgradeMemo {
            TrackUpgradeMemo(key: key, preview: TrackUpgradePreview(track: [], cost: nil, problem: problem, note: nil), command: nil)
        }
        guard let pair = trackBeside(id, near: selectedPoint), let geometry = world.trackGeometry(of: id) else {
            return refused(language.text("An X crossover needs a second track beside this one.", "X 渡線要建在兩條並行的軌道之間。"))
        }
        // Centred where the track was tapped, moved along to keep clear of
        // the ends of the track picked.
        let half = DoubleTrack.scissorsLength / 2
        let low = NetworkBuilding.minimumSpacing + half, high = geometry.length - NetworkBuilding.minimumSpacing - half
        guard low <= high else { return refused(ScissorsProblem.nearANode.text(in: language)) }
        let centre = min(max(pair.place.distance, low), high)
        let start = NetworkEdgePoint(edge: id, distance: centre - half)
        let across = geometry.location(at: centre + half).position
        guard let end = world.nearestPoint(onEdge: pair.beside.edge, to: across.plan) else {
            return refused(ScissorsProblem.notAcross.text(in: language))
        }
        let plan: ScissorsPlan
        switch scissorsPlan(from: start, to: end) {
        case .success(let found): plan = found
        case .failure(.notLevel):
            // Decision 257: as the network tool's, on level track only.
            return refused(language.text("An X crossover can only go where the track is level.", "X 渡線只能建在平坦的路段。"))
        case .failure(let problem): return refused(problem.text(in: language))
        }
        var draft = world.pricingCopy()
        do throws(GameError) {
            guard let edges = try build(plan, in: &draft, structure: .automatic) else {
                return refused(ScissorsProblem.tooShallow.text(in: language))
            }
            let command = PlayerCommand.buildCrossover(plan, structure: .automatic)
            let cost = Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
            let track = edges.compactMap { draft.trackGeometry(of: $0)?.points }
            return TrackUpgradeMemo(key: key, preview: TrackUpgradePreview(
                track: track, cost: cost, problem: shortfallText(cost, doing: command),
                note: language.text("Trains can change track here either way.", "列車在這裡可以雙向換線。")
            ), command: command)
        } catch {
            return refused(error.playerMessage(in: language))
        }
    }
}
