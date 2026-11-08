import GameCore

// Decision 629 (TRACKHEIGHT, a player's report from 115.1 in Yilan): a
// stretch of track refused because it crosses water too low, climbs too
// steeply or stands too high left the player nothing to do but tap the map
// again. GameCore has always taken the heights the network tool gives a new
// point (decision 124: ``GameSession/networkHeight``, folded among the
// advanced options); this is the build card's own control of the heights
// of the stretch drawn, and the fix it offers for the refusal: the
// smallest raise or lowering of a new end that GameCore would build.
//
// Presentation only: each height is tried with GameCore's read-only price
// of the edge (`GameWorld.trackEdgePrice`), which runs the grade and the
// ground's rules (water, the highest deck) without copying the world; the
// one offered is then built on a copy as the preview is, so what the card
// offers is what ✓ builds. The references have no height fix (the
// owner's `Simulator/` layout planner has start and end heights and a
// "smooth grade" button, the idea of the +/- here; OpenTTD and Simutrans,
// ideas only, name what to change but not by how much): the search is this
// project's own.

/// How much a stretch's new start and end are raised (below 0, lowered)
/// past ``GameSession/networkHeight``, in world units (decision 629).
public struct NetworkRaises: Hashable, Sendable {
    public var start: Int64
    public var end: Int64

    public init(start: Int64 = 0, end: Int64 = 0) {
        self.start = start
        self.end = end
    }
}

/// A height the build card offers that gets round a refusal (decision
/// 629): the raises to set, and what the stretch then costs and is.
public struct NetworkHeightFix: Hashable, Sendable {
    /// Which ends it moves.
    public enum Ends: Hashable, Sendable { case end, start, both }
    /// What the stretch becomes where it did not get through.
    public enum Kind: Hashable, Sendable { case bridge, tunnel, viaduct, raised, lowered }

    public let ends: Ends
    /// How far it moves them from where they are now, in world units.
    public let change: Int64
    public let raises: NetworkRaises
    /// What carries the stretch: the ground's choice when the player had
    /// forced one that cannot carry it.
    public let structure: TrackStructure
    public let kind: Kind
    public let cost: Money

    /// The button's words: "Raise the end 6 m: bridge".
    public func title(in language: DisplayLanguage) -> String {
        let metres = NetworkBuilding.lengthText(abs(change), in: language)
        let up = change > 0
        let which: (String, String) = switch ends {
        case .end: ("the end", "終點")
        case .start: ("the start", "起點")
        case .both: ("both ends", "兩端")
        }
        let verb = up ? language.text("Raise \(which.0) \(metres)", "\(which.1)架高 \(metres)")
            : language.text("Lower \(which.0) \(metres)", "\(which.1)降低 \(metres)")
        let what: String? = switch kind {
        case .bridge: language.text("bridge", "用橋")
        case .tunnel: language.text("tunnel", "走隧道")
        case .viaduct: language.text("viaduct", "走高架")
        case .raised, .lowered: nil
        }
        guard let what else { return verb }
        return language.text("\(verb): \(what)", "\(verb)，\(what)")
    }

    /// The button's words where the two full ones do not fit side by side
    /// (a phone on its side): its arrow says up or down, so "4 m, bridge".
    public func shortTitle(in language: DisplayLanguage) -> String {
        let metres = NetworkBuilding.lengthText(abs(change), in: language)
        let what: String? = switch kind {
        case .bridge: language.text("bridge", "用橋")
        case .tunnel: language.text("tunnel", "走隧道")
        case .viaduct: language.text("viaduct", "走高架")
        case .raised, .lowered: nil
        }
        guard let what else { return metres }
        return language.text("\(metres), \(what)", "\(metres)，\(what)")
    }
}

/// The build card's heights (decision 629): the new end the player moves
/// up and down, how high it stands, and the fixes for a refusal.
public struct NetworkHeightCard: Hashable, Sendable {
    /// Which end the +/- moves: the end, or the start where only it is a
    /// new point.
    public let adjusts: NetworkHeightFix.Ends
    /// "End 6 m above the ground".
    public let label: String
    public let canRaise: Bool
    public let canLower: Bool
    /// At most one up and one down, the nearer first.
    public let fixes: [NetworkHeightFix]
    /// For a refusal the heights may get round with no fix offered: that
    /// one is being looked for, what to do instead, or that no end can
    /// move; `nil` otherwise.
    public let note: String?
    /// Decision 646: how high the moved end stands over the ground now, in
    /// world units (negative underground), and how many 1 m steps it may
    /// still go up and down.
    public let aboveGround: Int64
    public let stepsUp: Int
    public let stepsDown: Int

    /// `steps` held to what the range allows (up is positive).
    public func clamped(steps: Int) -> Int {
        min(max(steps, -stepsDown), stepsUp)
    }

    /// The height cell's words after `steps` more metres: "On the ground",
    /// "6 m above the ground", "6 m underground" (decision 646: the same
    /// meaning as the pill's, how high the end stands over the ground).
    public func readout(steps: Int = 0, in language: DisplayLanguage) -> String {
        let above = aboveGround + Int64(clamped(steps: steps)) * WorldCoordinate.unitsPerMetre
        let height = NetworkBuilding.lengthText(abs(above), in: language)
        if above >= WorldCoordinate.unitsPerMetre / 2 {
            return language.text("\(height) above ground", "離地 \(height)")
        } else if above <= -WorldCoordinate.unitsPerMetre / 2 {
            return language.text("\(height) underground", "地下 \(height)")
        }
        return language.text("On the ground", "地面")
    }
}

/// Decision 646: the height cell of the construction HUD, held and slid
/// up and down: how far a finger has moved, in whole metres.
public enum TrackHeightDrag {
    /// A finger's travel for one metre, in points.
    public static let pointsPerMetre: Double = 14
    /// How long the cell is held before a slide counts, in seconds (a
    /// quicker touch is a tap).
    public static let holdSeconds: Double = 0.25

    /// Whole metres for a vertical `translation` (points, down positive as
    /// SwiftUI gives it): up is higher, one per ``pointsPerMetre``, kept
    /// within what `card` allows.
    public static func steps(forTranslation translation: Double, card: NetworkHeightCard) -> Int {
        card.clamped(steps: Int((-translation / pointsPerMetre).rounded(.towardZero)))
    }
}

/// What ``GameSession/networkHeightCard``'s fixes were found for.
struct NetworkHeightFixKey: Equatable {
    let preview: NetworkPreviewMemo.Key
}

extension GameSession {
    /// Decision 646: the build card's "the first stretch is straight" line
    /// is said once, while nothing is built yet; afterwards the player
    /// knows.
    public var networkOffersFreeFirstHint: Bool {
        world.network.edges.isEmpty
    }

    /// The step of the height cell's slide and +/-: 1 m.
    public static let networkRaiseStep: Int64 = WorldCoordinate.unitsPerMetre

    /// The refusals a height can get round (decision 629).
    static func heightCanFix(_ error: GameError?) -> Bool {
        switch error {
        case .trackOverWater?, .trackTooSteep?, .structureTooHigh?, .invalidTrackStructure?, .invalidTrackGeometry?: true
        default: false
        }
    }

    /// The new ends of the stretch drawn, which the heights may move.
    private var networkMovableEnds: (start: Bool, end: Bool) {
        func isPoint(_ anchor: NetworkAnchor?) -> Bool {
            if case .point? = anchor { true } else { false }
        }
        return (isPoint(networkStart), isPoint(networkEnd))
    }

    /// The build card's heights for the stretch drawn (decision 629);
    /// `nil` when it has no new end, is traced along a real line or is an
    /// X crossover, or a finger is still drawing it.
    public var networkHeightCard: NetworkHeightCard? {
        guard networkMode == .build, networkDragFinger == nil, let preview = networkPreview, preview.traced == nil,
              scissorsPlan() == nil else { return nil }
        let movable = networkMovableEnds
        let canFix = Self.heightCanFix(preview.refusal)
        guard movable.start || movable.end else {
            guard canFix, let start = networkStart, let end = networkEnd, case .node = start, case .node = end else { return nil }
            return NetworkHeightCard(
                adjusts: .end, label: "", canRaise: false, canLower: false, fixes: [],
                note: language.text(
                    "Both ends are on track already, so their height cannot change. Tap a new point on each side and raise the stretch between them.",
                    "兩端都接在已有的軌道上，高度不能改。請在兩側各點一個新點，再調高中間那一段。"
                ),
                aboveGround: 0, stepsUp: 0, stepsDown: 0
            )
        }
        let adjusts: NetworkHeightFix.Ends = movable.end ? .end : .start
        let fixes = canFix ? (networkHeightFixes ?? []) : []
        let note: String? = if !canFix {
            nil
        } else if isWaiting(for: .networkHeightFixes) || networkHeightFixes == nil {
            language.text("Looking for a height that works…", "正在找可以鋪的高度…")
        } else if fixes.isEmpty {
            language.text(
                "No height of these ends gets through. Try a shorter stretch, or a point on each side of the water.",
                "這兩端怎麼調高度都過不去。請把這段鋪短一點，或在水的兩岸各點一個點。"
            )
        } else {
            // The fixes' own words say what each does.
            nil
        }
        let raise = adjusts == .end ? networkEndRaise : networkStartRaise
        let limit = RailwayNetwork.heightRange
        let step = Self.networkRaiseStep
        let stepsUp = max(0, Int((limit.upperBound - networkHeight - raise) / step))
        let stepsDown = max(0, Int((networkHeight + raise - limit.lowerBound) / step))
        return NetworkHeightCard(
            adjusts: adjusts, label: networkEndHeightText(adjusts), canRaise: stepsUp > 0,
            canLower: stepsDown > 0, fixes: fixes, note: note,
            aboveGround: networkEndAboveGround(adjusts) ?? 0, stepsUp: stepsUp, stepsDown: stepsDown
        )
    }

    /// How high the end the card moves stands over the ground, in world units.
    private func networkEndAboveGround(_ ends: NetworkHeightFix.Ends) -> Int64? {
        guard let start = networkStart, let end = networkEnd, let (from, to) = endPositions(from: start, to: end, in: world) else { return nil }
        let position = ends == .end ? to : from
        return position.z - (world.groundHeight(at: position.plan) ?? 0)
    }

    /// "End 6 m above the ground", for the end the card moves.
    private func networkEndHeightText(_ ends: NetworkHeightFix.Ends) -> String {
        guard let above = networkEndAboveGround(ends) else { return "" }
        let height = NetworkBuilding.lengthText(abs(above), in: language)
        let which = ends == .end ? language.text("End", "終點") : language.text("Start", "起點")
        if above >= WorldCoordinate.unitsPerMetre / 2 {
            return language.text("\(which) \(height) above the ground", "\(which)離地 \(height)")
        } else if above <= -WorldCoordinate.unitsPerMetre / 2 {
            return language.text("\(which) \(height) underground", "\(which)在地下 \(height)")
        }
        return language.text("\(which) on the ground", "\(which)在地面")
    }

    /// Moves the end the build card moves by `steps` of
    /// ``networkRaiseStep`` (decision 629); the preview, its long section
    /// and its cost follow.
    public func raiseNetworkEnd(by steps: Int) {
        guard let card = networkHeightCard else { return }
        let limit = RailwayNetwork.heightRange
        func moved(_ raise: Int64) -> Int64 {
            let target = raise + Int64(steps) * Self.networkRaiseStep
            return min(max(target, limit.lowerBound - networkHeight), limit.upperBound - networkHeight)
        }
        if card.adjusts == .end { networkEndRaise = moved(networkEndRaise) } else { networkStartRaise = moved(networkStartRaise) }
    }

    /// Sets the heights (and the structure) `fix` names.
    public func applyNetworkHeightFix(_ fix: NetworkHeightFix) {
        networkStartRaise = fix.raises.start
        networkEndRaise = fix.raises.end
        if networkStructure != fix.structure { networkStructure = fix.structure }
    }

    /// The fixes for the stretch drawn, kept for its draft; `nil` while they
    /// wait for the main actor's next turn (decision 590).
    var networkHeightFixes: [NetworkHeightFix]? {
        networkHeightFixes(now: false)
    }

    /// ``networkHeightFixes``; `now` works them out at once, even in the app.
    func networkHeightFixes(now: Bool) -> [NetworkHeightFix]? {
        guard let start = networkStart, let end = networkEnd else { return nil }
        let key = NetworkHeightFixKey(preview: NetworkPreviewMemo.Key(
            start: start, end: end, structure: networkStructure, height: networkHeight,
            startRaise: networkStartRaise, endRaise: networkEndRaise, followsTrack: networkFollowsTrack,
            buildsScissors: networkBuildsScissors, easesGrade: networkEasesGrade,
            buildsDouble: networkBuildsDouble, doubleChosen: networkDoubleChosen, doubleSide: networkDoubleSide,
            traces: tracesRealRailway, commandRevision: commandRevision
        ))
        if let memo = networkHeightFixMemo, memo.key == key { return memo.fixes }
        if !now, waits(for: .networkHeightFixes, workOut: { _ = $0.networkHeightFixes(now: true) }) { return nil }
        let fixes = workOutNetworkHeightFixes(from: start, to: end)
        networkHeightFixMemo = (key, fixes)
        return fixes
    }

    /// The nearest height up and the nearest down, for the end, both ends
    /// or the start in that order, that GameCore would build. Never
    /// inlined: the copies of the world are its own (decision 590).
    @inline(never)
    func workOutNetworkHeightFixes(from start: NetworkAnchor, to end: NetworkAnchor) -> [NetworkHeightFix] {
        let movable = networkMovableEnds
        var sets: [NetworkHeightFix.Ends] = []
        if movable.end { sets.append(.end) }
        if movable.start && movable.end { sets.append(.both) }
        if movable.start { sets.append(.start) }
        guard !sets.isEmpty else { return [] }
        // The ground under the whole way, read once: the heights change
        // the stretch's rise, not where it runs.
        var draft = world
        try? draft.readGround(under: [start, end].compactMap(planPoint(of:)), from: heights)
        let current = NetworkRaises(start: networkStartRaise, end: networkEndRaise)
        guard case .success(let base) = edgePlan(from: start, to: end, in: draft, raises: current) else { return [] }
        try? draft.readGround(under: base.stretch(structure: .automatic).ground, from: heights)
        let structure: TrackStructure = .automatic
        let limit = RailwayNetwork.heightRange
        let step = Self.networkRaiseStep
        var fixes: [NetworkHeightFix] = []
        for up in [true, false] {
            // Each set's nearest height that builds, then the cheapest of
            // them (the earlier set on a tie).
            var best: NetworkHeightFix?
            for ends in sets {
                for steps in 1...Int(limit.upperBound / step) {
                    let change = (up ? 1 : -1) * Int64(steps) * step
                    var raises = current
                    if ends != .start { raises.end += change }
                    if ends != .end { raises.start += change }
                    guard [raises.start, raises.end].allSatisfy({ limit.contains(networkHeight + $0) }) else { break }
                    guard case .success(let plan) = edgePlan(from: start, to: end, in: draft, raises: raises),
                          [(start, plan.from), (end, plan.to)].allSatisfy({ anchor, position in
                              guard case .point = anchor, let ground = draft.groundHeight(at: position.plan) else { return true }
                              return limit.contains(position.z - ground)
                          }),
                          (try? draft.trackEdgePrice(from: plan.from, to: plan.to, curve: plan.curve, profile: plan.profile, structure: structure)) != nil
                    else { continue }
                    // What ✓ would build: the whole preview, on a copy.
                    guard let found = preview(from: start, to: end, raises: raises, structure: structure)?.0, let cost = found.cost else { continue }
                    if best == nil || cost.amount < best!.cost.amount {
                        best = NetworkHeightFix(
                            ends: ends, change: change, raises: raises, structure: structure,
                            kind: Self.fixKind(of: found, up: up), cost: cost
                        )
                    }
                    break
                }
            }
            if let best { fixes.append(best) }
        }
        // The smaller change first.
        return fixes.sorted { abs($0.change) < abs($1.change) }
    }

    /// What carries a fixed stretch: a bridge or tunnel where it has one,
    /// else a viaduct, else just higher or lower.
    static func fixKind(of preview: NetworkPreview, up: Bool) -> NetworkHeightFix.Kind {
        let kinds = Set(preview.longSection?.spans.map(\.kind) ?? [])
        if up {
            if kinds.contains(.bridge) { return .bridge }
            if kinds.contains(.viaduct) { return .viaduct }
            return .raised
        }
        return kinds.contains(.tunnel) ? .tunnel : .lowered
    }
}
