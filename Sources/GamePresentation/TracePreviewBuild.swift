import Foundation
import GameCore

// The traced stretch as the network tool shows and builds it (decision
// 213), and the real line it lights up on the map.

extension GameSession {
    /// The traced stretch's preview (decision 213): the edges GameCore
    /// builds, their length and cost, and why the trace stops where it
    /// does; `nil` when the ends are not both on real lines that join, so
    /// the tool lays one stretch as usual.
    func tracePreview(from start: NetworkAnchor, to end: NetworkAnchor) -> (NetworkPreview, [WorldCoordinate])? {
        guard let plan = traceAlong(from: start, to: end) else { return nil }
        let points = plan.stretches.map { stretch in
            TrackGeometry(from: stretch.from, to: stretch.to, curve: stretch.curve)?.points ?? [stretch.from, stretch.to]
        }
        let built = Array(plan.stretches.prefix(plan.buildable))
        var draft = world.trackPreviewCopy()
        var cost: Money?
        var command = PlayerCommand.buildTrackChain(built)
        // Decision 247: with double track on, the second track beside it;
        // its later: or where the real line is double. Decision 468: single
        // where the trace joins track already laid.
        lazy var wanted = tracedDouble(built)
        let decided = plan.existing.isEmpty ? wanted : (double: false, real: nil)
        var double: Result<DoubleChainPlan, TraceDoubleProblem>?
        if decided.double, !built.isEmpty {
            double = tracedDoublePlan(built, from: start, to: end, reachesEnd: !plan.stopped, traced: plan)
        }
        switch double {
        case .success(let found)?:
            draft = found.built
            command = found.command
            cost = Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
        case .failure?:
            break
        case nil:
            // Decision 521's second sequel: the copy the trace built the
            // same chain on, not the chain built again.
            if !built.isEmpty, let traced = plan.built {
                draft = traced
                cost = Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
            } else if !built.isEmpty, (try? apply(command, to: &draft)) != nil {
                cost = Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
            }
        }
        var shortfall = cost.flatMap { shortfallText($0, doing: command) }
        var shortfallBrief = shortfall == nil ? nil : GameError.shortOfCashBrief(in: language)
        if case .failure(let problem)? = double {
            shortfall = problem.text
            shortfallBrief = problem.brief
        }
        let length = built.compactMap { TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve)?.length }.reduce(0, +)
        // Decision 468: the track already laid that it joins, in its place
        // along the way.
        var shown: [WorldCoordinate] = []
        var pieces: [[WorldCoordinate]] = []
        if built.isEmpty {
            shown = points.flatMap { $0 }
        } else {
            var piece: [WorldCoordinate] = []
            for index in 0...plan.buildable {
                for run in plan.existing where run.after == index {
                    shown += run.points
                    if !piece.isEmpty { pieces.append(piece) }
                    piece = []
                }
                if index < plan.buildable {
                    shown += points[index]
                    piece += points[index]
                }
            }
            if !piece.isEmpty { pieces.append(piece) }
        }
        // Decision 513: refused from its first edge, the whole way and its
        // far end, as drawn, not 0 m and the first edge's end; with no
        // stretch at all (no grade reaches), the real line's way.
        let first = plan.stretches.first, last = built.isEmpty ? plan.stretches.last : built.last
        if plan.stretches.isEmpty { shown = plan.refusedWay }
        let wayLength = plan.stretches.isEmpty ? Self.drawnLength(of: [plan.refusedWay]) : built.isEmpty ? Self.drawnLength(of: points) : length
        let isJoined: (NetworkAnchor) -> Bool = { if case .point = $0 { false } else { true } }
        var preview = NetworkPreview(
            curve: first?.curve ?? .straight, profile: .uniform, points: shown, length: wayLength,
            startHeight: first?.from.z ?? plan.refusedWay.first?.z ?? 0, endHeight: last?.to.z ?? plan.refusedWay.last?.z ?? 0,
            joinsStart: isJoined(start), joinsEnd: !plan.stopped && isJoined(end),
            cost: built.isEmpty ? nil : cost,
            problem: built.isEmpty ? (plan.problem ?? language.text("This stretch cannot be traced.", "這段無法描線。")) : shortfall,
            problemBrief: built.isEmpty ? (plan.problem == nil ? language.text("Can't trace this stretch", "這段無法描線") : plan.brief) : shortfallBrief,
            cleared: built.isEmpty ? [] : world.placedBuildings(clearedIn: draft)
        )
        preview.traced = built.count
        preview.tracedDouble = decided.real
        preview.existing = built.isEmpty ? [] : plan.existing.map(\.points)
        preview.newPieces = preview.existing.isEmpty ? [] : pieces
        preview.forSale = tracedSaleLine(from: start, to: end)
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
        if !preview.existing.isEmpty {
            preview.traceNote = [Self.joinedText(plan, wantedDouble: networkBuildsDouble || wanted.double, in: language), preview.traceNote]
                .compactMap { $0 }.joined(separator: " ")
        }
        return (preview, second)
    }

    /// The length in plan of the centre lines `pieces`, one after another
    /// (decision 513).
    static func drawnLength(of pieces: [[WorldCoordinate]]) -> Int64 {
        var total = 0.0
        for piece in pieces {
            for (a, b) in zip(piece, piece.dropFirst()) {
                let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                total += (dx * dx + dy * dy).squareRoot()
            }
        }
        return Int64(total.rounded())
    }

    /// What a trace that joins track already laid says (decision 468):
    /// "Joins the track already laid for 1.2 km, at no cost.", and where
    /// the player wanted double track, that it is single here.
    static func joinedText(_ plan: TracePlan, wantedDouble: Bool, in language: DisplayLanguage) -> String {
        let distance = NetworkBuilding.distanceText(Int64(plan.existingLength.rounded()), in: language)
        var text = language.text(
            "Joins the track already laid for \(distance), at no cost.",
            "接上已經鋪好的軌道 \(distance)，這段不用錢。"
        )
        if wantedDouble {
            text += language.text(
                " Laid single where it joins; add the second track with Upgrade to double track.",
                "接上的這次鋪成單線，第二條可以用「升級為複線」加。"
            )
        }
        return text
    }

    /// The traced stretch's `built` edges with a second track beside them
    /// (decision 247), on ``networkDoubleSide``, and a crossover at each
    /// end that joins track (the far end only when the trace gets there);
    /// or why not, as the player reads it.
    ///
    /// Decision 521's fourth sequel: on the copy `traced` built `built` on
    /// where it has one (``TracePlan/built``), not built again.
    func tracedDoublePlan(
        _ built: [PlayerCommand.TrackStretch], from start: NetworkAnchor, to end: NetworkAnchor, reachesEnd: Bool, traced: TracePlan? = nil
    ) -> Result<DoubleChainPlan, TraceDoubleProblem> {
        guard let parallel = parallelChain(beside: built.map(ChainSegment.init), side: networkDoubleSide, in: world) else {
            return .failure(TraceDoubleProblem(text: Self.noParallelText(in: language), brief: Self.noParallelBrief(in: language)))
        }
        do throws(GameError) {
            return .success(try planDoubleChain(
                main: built, run: [], parallel: parallel, platforms: [],
                wantsCrossover: (needsCrossover(start, in: world), reachesEnd && needsCrossover(end, in: world)), in: world,
                mainBuilt: traced.flatMap { plan in plan.built.map { (world: $0, edges: plan.builtEdges) } }
            ))
        } catch {
            return .failure(TraceDoubleProblem(text: error.playerMessage(in: language), brief: error.trackBrief(in: language)))
        }
    }

    /// Builds the traced stretch (decision 213), as far as GameCore builds
    /// it, as one command: all of it or none. Its end becomes the start of
    /// the next stretch.
    func buildTracedTrack(from start: NetworkAnchor, to end: NetworkAnchor) -> Bool {
        guard let plan = traceAlong(from: start, to: end) else { return false }
        guard plan.buildable > 0 else {
            message = StatusMessage(kind: .failure, text: plan.problem ?? language.text("This stretch cannot be traced.", "這段無法描線。"))
            return true
        }
        let stretches = Array(plan.stretches.prefix(plan.buildable))
        var command = PlayerCommand.buildTrackChain(stretches)
        var crossovers = DoubleTrack.CrossoverOutcome.none
        let decided = plan.existing.isEmpty ? tracedDouble(stretches) : (double: false, real: nil)
        if decided.double {
            switch tracedDoublePlan(stretches, from: start, to: end, reachesEnd: !plan.stopped, traced: plan) {
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
            if !plan.existing.isEmpty {
                text += " " + Self.joinedText(plan, wantedDouble: false, in: language)
            }
            if plan.stopped, let problem = plan.problem {
                text += language.text(" It stops there: \(problem)", "在那裡停下：\(problem)")
            }
            return text
        }
        if let track = built?.track {
            networkStart = .node(plan.endNode ?? track.to)
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
            $0.dropFirst().dropLast().map { $0.coordinate() }
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

extension PlayerCommand.TrackStretch {
    /// The stretch, starting at node `node` when one is given: an edge of a
    /// chain (``PlayerCommand/buildTrackChain(_:)``) starts at the node the
    /// edge before ended at. Decision 468: unless it starts at a node of its
    /// own, as a trace goes on beyond track already laid from that track's
    /// far end.
    func starting(at node: TrackNodeID?) -> PlayerCommand.TrackStretch {
        guard let node else { return self }
        if case .node = start { return self }
        return PlayerCommand.TrackStretch(
            start: .node(node), end: end, from: from, to: to, curve: curve, profile: profile, structure: structure, ground: ground,
            mountain: mountain, system: system, gauge: gauge
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
