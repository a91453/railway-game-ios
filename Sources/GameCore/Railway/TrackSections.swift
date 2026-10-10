// Track over the ground (ARCHITECTURE decision 124, the design's second
// step, docs/research/TERRAIN_HEIGHT_DESIGN.md sections 5 and 6): what
// carries each 16 m of an edge, measured from the ground under it, and
// what it costs.
//
// An edge is priced and judged by its pricing lengths
// (``ConstructionCosts/trackPricingLength``, 1,024 units, 16 m; the last may
// be shorter), each at its middle: Δ, the rail's height there less the
// ground's (``GameWorld/groundHeight(at:)``), and whether the 64 m cell
// there is water. A world that has read no ground is flat at 0 m and, for
// these rules, has no water: its explicit structures are judged and
// priced exactly as Stage S4 judged them.
//
// The automatic structure (``TrackStructure/automatic``) leaves the choice to
// the ground: each length is a surface, embankment or cutting within a few
// metres of it, a viaduct above, a tunnel below, a bridge over water. Runs
// shorter than ``TrackSectionRules/shortestRun`` lengths join a neighbour,
// so the track does not flick between viaduct and embankment over every
// hump. Once built, an automatic edge keeps its sections: the ground never
// changes, but the water of a map read as it is needed may come in later.
//
// The references have no structure chosen by the ground, no earthwork and
// no water rule (gap, the design's section 10); the thresholds follow its
// rules of thumb: the `Railway/` site draws fill higher than 6 m as a
// viaduct (`VIADUCT_LIFT_M`), and engineering practice takes an embankment
// to some 8–10 m and a cutting to some 10–20 m.

/// What carries a stretch of track (decision 124).
public enum TrackSectionKind: String, Hashable, CaseIterable, Codable, Sendable {
    /// Within ``TrackSectionRules/level`` of the ground.
    case surface
    /// On a fill above the ground.
    case embankment
    /// In a cutting below the ground.
    case cutting
    /// On a viaduct over dry land.
    case viaduct
    /// On a bridge, over water or a valley.
    case bridge
    /// Underground.
    case tunnel

    /// The explicit structure that carries track alike: the three on the
    /// ground are ``TrackStructure/surface``.
    public var structure: TrackStructure {
        switch self {
        case .surface, .embankment, .cutting: .surface
        case .viaduct: .elevated
        case .bridge: .bridge
        case .tunnel: .tunnel
        }
    }

    /// Whether this is one of the kinds on the ground, which run into each
    /// other as the ground rises and falls.
    var isOnGround: Bool {
        structure == .surface
    }

    /// The kind an explicit structure's every length is.
    init(_ structure: TrackStructure) {
        switch structure {
        case .surface, .automatic: self = .surface
        case .elevated: self = .viaduct
        case .bridge: self = .bridge
        case .tunnel: self = .tunnel
        }
    }
}

/// A run of an automatic edge's pricing lengths carried alike (decision
/// 124), from where the run before it ends.
public struct TrackSection: Hashable, Codable, Sendable {
    public let kind: TrackSectionKind
    /// How many pricing lengths it covers; at least one.
    public let lengths: Int

    public init(kind: TrackSectionKind, lengths: Int) {
        self.kind = kind
        self.lengths = lengths
    }
}

/// A stretch of an edge carried alike, by distance from its `from` node.
public struct TrackSectionSpan: Hashable, Sendable {
    public let kind: TrackSectionKind
    public let start: Int64
    public let end: Int64
}

/// The thresholds and prices of track over the ground (decision 124), in
/// world units (64 a metre). Game parameters, to be tuned by measurement.
public enum TrackSectionRules {
    /// Within 2 m of the ground track is on its surface (Stage S4's
    /// ``TrackStructure/embankment``), and no earthwork is paid.
    public static let level: Int64 = TrackStructure.embankment
    /// Fill higher than 8 m becomes a viaduct.
    public static let highestFill: Int64 = 512
    /// A cutting deeper than 11 m becomes a tunnel.
    public static let deepestCutting: Int64 = 704
    /// Joining a neighbour, an embankment may reach 15 m and a cutting 20 m.
    public static let joinedFill: Int64 = 960
    public static let joinedCutting: Int64 = 1_280
    /// A viaduct or bridge stands at most 64 m above the ground.
    public static let highestDeck: Int64 = 4_096
    /// A bridge clears water by at least 4 m, and a tunnel under water runs
    /// at least 10 m below it.
    public static let waterClearance: Int64 = 256
    public static let underWater: Int64 = 640
    /// Above 15 m a viaduct's or bridge's piers cost one track price more
    /// for every 10 m.
    public static let tallPier: Int64 = 960
    public static let pierStep: Int64 = 640
    /// A run of fewer lengths (64 m) joins a neighbour.
    public static let shortestRun = 4

    /// What earthwork costs, as a fraction of the track price per pricing
    /// length: a trapezoid 10 m wide at the top with 1 : 1.5 sides, the
    /// height h (in units) past ``level``, 16 m long, is 16 · (h/64) · (10 +
    /// 1.5 h/64) m³, at track × 7 / 6400 a m³ ($1.75 at the new game's
    /// $1,600 a length): track × 7 h (1280 + 3 h) / 3,276,800. So 8 m of
    /// fill costs about as much as a viaduct's two prices more, and 11.4 m
    /// of cutting as a tunnel's four.
    static let earthworkDivisor: Int64 = 3_276_800

    static func earthwork(_ delta: Int64) -> Int64 {
        let h = abs(delta) - level
        return h > 0 ? 7 * h * (1_280 + 3 * h) : 0
    }
}

extension TrackEdge {
    /// The stretches of the edge carried alike, from its `from` node: an
    /// automatic edge's sections, or the whole edge for an explicit
    /// structure.
    public var sectionSpans: [TrackSectionSpan] {
        guard !sections.isEmpty else {
            return [TrackSectionSpan(kind: TrackSectionKind(structure), start: 0, end: length)]
        }
        var spans: [TrackSectionSpan] = []
        var lengths = 0
        for section in sections {
            let start = Int64(lengths) * ConstructionCosts.trackPricingLength
            lengths += section.lengths
            spans.append(TrackSectionSpan(kind: section.kind, start: start, end: min(length, Int64(lengths) * ConstructionCosts.trackPricingLength)))
        }
        return spans
    }

    /// What carries the edge where it meets `node` (its first or last
    /// stretch).
    func kind(at node: TrackNodeID) -> TrackSectionKind {
        let spans = sectionSpans
        return node == from ? spans[0].kind : spans[spans.count - 1].kind
    }
}

/// One pricing length of an edge, at its middle.
struct TrackPricedLength {
    let start: Int64
    let end: Int64
    /// The rail's height less the ground's at the middle.
    let delta: Int64
    /// Whether the middle is over water.
    let isWater: Bool
}

extension TrackPricedLength {
    /// Whether track of `kind` may be here when it joins a neighbour: the
    /// three on the ground alike.
    func allows(_ kind: TrackSectionKind) -> Bool {
        switch kind {
        case .surface, .embankment, .cutting:
            !isWater && -TrackSectionRules.joinedCutting <= delta && delta <= TrackSectionRules.joinedFill
        case .viaduct:
            !isWater && 0 <= delta && delta <= TrackSectionRules.highestDeck
        case .bridge:
            0 <= delta && delta <= TrackSectionRules.highestDeck && (!isWater || delta >= TrackSectionRules.waterClearance)
        case .tunnel:
            delta <= 0 && (!isWater || delta <= -TrackSectionRules.underWater)
        }
    }

    /// The kind on the ground this length's height makes it.
    var groundKind: TrackSectionKind {
        delta > TrackSectionRules.level ? .embankment : delta < -TrackSectionRules.level ? .cutting : .surface
    }
}

extension GameWorld {
    /// Edge `geometry`'s pricing lengths with the rail's height above the
    /// ground at each middle, and the height above it at both ends.
    ///
    /// - Throws: ``GameError/groundNotLoaded`` where the world has ground
    ///   but has not read it under the edge.
    func survey(_ geometry: TrackGeometry) throws(GameError) -> (lengths: [TrackPricedLength], start: Int64, end: Int64) {
        let priced = ConstructionCosts.trackPricingLength
        let count = max(1, (geometry.length + priced - 1) / priced)
        let mapped = ground.isMapped
        func delta(at distance: Int64) throws(GameError) -> (Int64, PlanPoint) {
            let point = geometry.location(at: distance).position
            guard let ground = groundHeight(at: point.plan) else { throw .groundNotLoaded }
            return (point.z - ground, point.plan)
        }
        var lengths: [TrackPricedLength] = []
        for index in 0..<count {
            let start = index * priced, end = min(geometry.length, (index + 1) * priced)
            let (delta, point) = try delta(at: (start + end) / 2)
            let isWater = mapped && terrain.isWater(row: Land.cellIndex(point.y), column: Land.cellIndex(point.x))
            lengths.append(TrackPricedLength(start: start, end: end, delta: delta, isWater: isWater))
        }
        return (lengths, try delta(at: 0).0, try delta(at: geometry.length).0)
    }

    /// The sections an edge of `geometry` carried by `structure` has, or why
    /// it cannot be built (decision 124): empty for an explicit structure,
    /// which must suit the ground at both ends and every length's middle;
    /// an automatic edge's runs, every length a kind the ground allows.
    ///
    /// - Throws, checked in this order: ``GameError/groundNotLoaded``;
    ///   ``GameError/invalidTrackStructure`` when an explicit structure does
    ///   not suit the height above the ground (surface within 2 m, a
    ///   viaduct or bridge at or above it, a tunnel at or below it);
    ///   ``GameError/structureTooHigh`` more than 64 m above it;
    ///   ``GameError/trackOverWater`` over water but on the surface or a
    ///   viaduct, a bridge lower than 4 m above it or a tunnel shallower
    ///   than 10 m below it.
    func sections(of geometry: TrackGeometry, structure: TrackStructure) throws(GameError) -> [TrackSection] {
        let survey = try survey(geometry)
        guard structure == .automatic else {
            let ends = [survey.start, survey.end] + survey.lengths.map(\.delta)
            guard ends.allSatisfy({ structure.allows(height: $0) }) else { throw .invalidTrackStructure }
            if structure == .elevated || structure == .bridge, ends.contains(where: { $0 > TrackSectionRules.highestDeck }) {
                throw .structureTooHigh
            }
            let kind = TrackSectionKind(structure)
            guard survey.lengths.allSatisfy({ !$0.isWater || $0.allows(kind) }) else {
                throw .trackOverWater
            }
            return []
        }
        return try Self.automaticSections(survey.lengths, price: economy.costs.track.amount)
    }

    /// The automatic structure's sections over `lengths` (decision 124).
    static func automaticSections(_ lengths: [TrackPricedLength], price: Int64) throws(GameError) -> [TrackSection] {
        // Each length's own kind.
        var kinds: [TrackSectionKind] = []
        for length in lengths {
            let delta = length.delta
            if length.isWater {
                if delta >= TrackSectionRules.waterClearance, delta <= TrackSectionRules.highestDeck {
                    kinds.append(.bridge)
                } else if delta <= -TrackSectionRules.underWater {
                    kinds.append(.tunnel)
                } else {
                    throw delta > TrackSectionRules.highestDeck ? .structureTooHigh : .trackOverWater
                }
            } else if delta > TrackSectionRules.highestFill {
                guard delta <= TrackSectionRules.highestDeck else { throw .structureTooHigh }
                kinds.append(.viaduct)
            } else if delta < -TrackSectionRules.deepestCutting {
                kinds.append(.tunnel)
            } else {
                kinds.append(length.groundKind)
            }
        }
        // Short runs join a neighbour, the first such run first, the dearer
        // of the neighbours they may join (the one before on a tie); the
        // three kinds on the ground are one run here.
        func family(_ kind: TrackSectionKind) -> TrackSectionKind {
            kind.isOnGround ? .surface : kind
        }
        func runs() -> [Range<Int>] {
            var runs: [Range<Int>] = []
            var start = 0
            for index in 1...kinds.count where index == kinds.count || family(kinds[index]) != family(kinds[start]) {
                runs.append(start..<index)
                start = index
            }
            return runs
        }
        func cost(_ range: Range<Int>, as kind: TrackSectionKind) -> Int64 {
            let pieces = range.map { index -> TrackSectionKind in kind.isOnGround ? lengths[index].groundKind : kind }
            return Self.price(of: zip(range, pieces).map { (lengths[$0], $1) }, track: price, extras: true).exact
        }
        var stuck: Set<Int> = []
        while let (index, run) = runs().enumerated().first(where: { $1.count < TrackSectionRules.shortestRun && !stuck.contains($1.lowerBound) }) {
            let all = runs()
            guard all.count > 1 else { break }
            var choices: [TrackSectionKind] = []
            if index > 0 { choices.append(family(kinds[all[index - 1].lowerBound])) }
            if index < all.count - 1 { choices.append(family(kinds[all[index + 1].lowerBound])) }
            let legal = choices.filter { kind in run.allSatisfy { lengths[$0].allows(kind) } }
            guard let dearest = legal.map({ cost(run, as: $0) }).max() else {
                stuck.insert(run.lowerBound)
                continue
            }
            // The one before wins a tie.
            guard let chosen = legal.first(where: { cost(run, as: $0) == dearest }) else { continue }
            for index in run {
                kinds[index] = chosen.isOnGround ? lengths[index].groundKind : chosen
            }
            stuck = []
        }
        var sections: [TrackSection] = []
        for kind in kinds {
            if let last = sections.last, last.kind == kind {
                sections[sections.count - 1] = TrackSection(kind: kind, lengths: last.lengths + 1)
            } else {
                sections.append(TrackSection(kind: kind, lengths: 1))
            }
        }
        return sections
    }

    /// What `pieces` cost at `track` a pricing length: each the track price
    /// times its structure's ``TrackStructure/costFactor``; with `extras`,
    /// earthwork on the ground past ``TrackSectionRules/level`` and piers
    /// past ``TrackSectionRules/tallPier``, each rounded half up once.
    /// `exact` is `nil` when it does not fit in a whole number.
    static func price(of pieces: [(TrackPricedLength, TrackSectionKind)], track: Int64, extras: Bool) -> (exact: Int64, overflow: Bool) {
        var base: Int64 = 0, earth: Int64 = 0, piers: Int64 = 0, overflow = false
        func add(_ value: Int64, to total: inout Int64) {
            let (sum, carry) = total.addingReportingOverflow(value)
            overflow = overflow || carry
            total = sum
        }
        for (length, kind) in pieces {
            add(kind.structure.costFactor, to: &base)
            guard extras else { continue }
            if kind.isOnGround {
                add(TrackSectionRules.earthwork(length.delta), to: &earth)
            } else if kind == .viaduct || kind == .bridge, length.delta > TrackSectionRules.tallPier {
                add(length.delta - TrackSectionRules.tallPier, to: &piers)
            }
        }
        func share(_ numerator: Int64, _ divisor: Int64) -> Int64 {
            let (value, carry) = Self.share(of: track, numerator, divisor)
            overflow = overflow || carry
            return value
        }
        var total: Int64 = 0
        let (main, overflowMain) = track.multipliedReportingOverflow(by: base)
        overflow = overflow || overflowMain
        add(main, to: &total)
        add(share(earth, TrackSectionRules.earthworkDivisor), to: &total)
        add(share(piers, TrackSectionRules.pierStep), to: &total)
        return (total, overflow)
    }

    /// `track` × `numerator` / `divisor`, rounded half up, without
    /// multiplying the whole numerator; and whether it overflowed.
    static func share(of track: Int64, _ numerator: Int64, _ divisor: Int64) -> (value: Int64, overflow: Bool) {
        let (whole, rest) = numerator.quotientAndRemainder(dividingBy: divisor)
        let (a, overflowA) = track.multipliedReportingOverflow(by: whole)
        let (b, overflowB) = track.multipliedReportingOverflow(by: rest)
        return (a &+ (b + divisor / 2) / divisor, overflowA || overflowB)
    }

    /// What an edge of `geometry` carried by `structure` with `sections`
    /// costs (decision 124): the track price times each length's
    /// structure, and, for an automatic edge or in a world with ground,
    /// earthwork and tall piers. For an explicit structure in a world
    /// without ground this is Stage S3's price, the track price times the
    /// structure for every pricing length, rounded up, at least one.
    ///
    /// - Throws: ``GameError/insufficientFunds(required:available:)`` when
    ///   the price does not fit in a ``Money``.
    func edgeCost(of geometry: TrackGeometry, structure: TrackStructure, sections: [TrackSection]) throws(GameError) -> Money {
        let pieces = try pricedPieces(of: geometry, structure: structure, sections: sections)
        let extras = structure == .automatic || ground.isMapped
        let (price, overflow) = Self.price(of: pieces, track: economy.costs.track.amount, extras: extras)
        guard !overflow, price >= 0 else { throw .insufficientFunds(required: Money(.max), available: economy.balance) }
        return Money(price)
    }

    /// Each pricing length of an edge of `geometry` carried by `structure`
    /// with `sections`, and the kind that carries it.
    func pricedPieces(
        of geometry: TrackGeometry, structure: TrackStructure, sections: [TrackSection]
    ) throws(GameError) -> [(TrackPricedLength, TrackSectionKind)] {
        let survey = try survey(geometry)
        let edge = TrackEdge(id: .edge(0), from: .node(0), to: .node(0), curve: .straight, length: geometry.length, structure: structure, sections: sections)
        let spans = edge.sectionSpans
        return survey.lengths.map { length in
            (length, spans.first { $0.start <= length.start && length.start < $0.end }?.kind ?? TrackSectionKind(structure))
        }
    }
}

extension TrackEdge {
    /// The stretches of `geometry`, this edge's centre line, that are not
    /// in a tunnel, each as its points: where its track comes down on what
    /// stands in its way (decision 95; decision 124 for an automatic edge's
    /// tunnel sections). None for a tunnel edge.
    func openStretches(of geometry: TrackGeometry) -> [[PlanPoint]] {
        guard !sections.isEmpty else { return structure == .tunnel ? [] : [geometry.points.map(\.plan)] }
        var stretches: [[PlanPoint]] = []
        for span in sectionSpans where span.kind != .tunnel {
            let points = geometry.points(from: span.start, to: span.end).map(\.plan)
            if !points.isEmpty { stretches.append(points) }
        }
        return stretches
    }
}

extension GameWorld {
    /// Why `edge`'s structure does not suit its heights in a world as
    /// loaded, or `nil` (decision 124): in a world without ground Stage
    /// S4's rule at both ends; with ground, an explicit structure against
    /// the ground at both ends and every length's middle, and an automatic
    /// edge's every section a kind its lengths allow. Water is not checked
    /// again: a map read as it is needed may have read water under track
    /// since it was built.
    func structureProblem(of edge: TrackEdge, geometry: TrackGeometry) -> String? {
        if !ground.isMapped, edge.structure != .automatic {
            guard edge.structure.allows(height: geometry.startHeight), edge.structure.allows(height: geometry.endHeight) else {
                return "Track edge \(edge.id)'s structure cannot carry it at its heights."
            }
            return nil
        }
        let survey: (lengths: [TrackPricedLength], start: Int64, end: Int64)
        do {
            survey = try self.survey(geometry)
        } catch {
            return "Track edge \(edge.id) runs where the world has not read the ground."
        }
        let dry = survey.lengths.map { TrackPricedLength(start: $0.start, end: $0.end, delta: $0.delta, isWater: false) }
        if edge.structure == .automatic {
            let spans = edge.sectionSpans
            guard dry.allSatisfy({ length in
                spans.first { $0.start <= length.start && length.start < $0.end }.map { length.allows($0.kind) } ?? false
            }) else {
                return "Track edge \(edge.id)'s sections do not suit the ground under it."
            }
            return nil
        }
        let heights = [survey.start, survey.end] + dry.map(\.delta)
        guard heights.allSatisfy({ edge.structure.allows(height: $0) }),
              edge.structure == .surface || edge.structure == .tunnel || heights.allSatisfy({ $0 <= TrackSectionRules.highestDeck })
        else {
            return "Track edge \(edge.id)'s structure cannot carry it at its heights above the ground."
        }
        return nil
    }
}

// MARK: - What the build card shows (decision 124, H3)

/// What an edge's price is made of (decision 124, the design's third
/// step): the four parts add up to what ``GameWorld`` charges for it,
/// rounded as it is. Read only; it charges nothing.
public struct TrackCostParts: Hashable, Sendable {
    /// The track price for every pricing length, as on the ground.
    public let track: Money
    /// Earthwork past ``TrackSectionRules/level`` on the ground.
    public let earthwork: Money
    /// What viaducts and bridges cost past the track price: their
    /// structures and tall piers.
    public let viaductsAndBridges: Money
    /// What tunnels cost past the track price.
    public let tunnels: Money

    public init(track: Money, earthwork: Money, viaductsAndBridges: Money, tunnels: Money) {
        self.track = track
        self.earthwork = earthwork
        self.viaductsAndBridges = viaductsAndBridges
        self.tunnels = tunnels
    }

    public static let zero = TrackCostParts(track: .zero, earthwork: .zero, viaductsAndBridges: .zero, tunnels: .zero)

    /// What the edge costs.
    public var total: Money {
        track + earthwork + viaductsAndBridges + tunnels
    }

    public static func + (lhs: TrackCostParts, rhs: TrackCostParts) -> TrackCostParts {
        TrackCostParts(
            track: lhs.track + rhs.track, earthwork: lhs.earthwork + rhs.earthwork,
            viaductsAndBridges: lhs.viaductsAndBridges + rhs.viaductsAndBridges, tunnels: lhs.tunnels + rhs.tunnels
        )
    }
}

/// A point of an edge's long section (decision 124, H3): how high the rail
/// and the ground under it are, in world units above the sea, at `distance`
/// from its `from` node, and what carries the track there.
public struct TrackGroundSample: Hashable, Sendable {
    public let distance: Int64
    public let rail: Int64
    public let ground: Int64
    public let kind: TrackSectionKind
    /// Whether the 64 m cell there is water (only in a world with ground).
    public let isWater: Bool

    public init(distance: Int64, rail: Int64, ground: Int64, kind: TrackSectionKind, isWater: Bool) {
        self.distance = distance
        self.rail = rail
        self.ground = ground
        self.kind = kind
        self.isWater = isWater
    }

    /// The rail's height above the ground (Δ), negative below it.
    public var height: Int64 {
        rail - ground
    }
}

/// An edge over the ground (decision 124, H3), as the build card draws it:
/// the rail and the ground at the `from` node, at the middle of every
/// pricing length (where the rules measure them) and at the `to` node; the
/// stretches carried alike; and what it costs, part by part.
public struct TrackLongSection: Hashable, Sendable {
    public let length: Int64
    public let samples: [TrackGroundSample]
    public let spans: [TrackSectionSpan]
    public let cost: TrackCostParts
}

extension GameWorld {
    /// What ``buildTrackEdge(from:to:curve:profile:structure:)`` would
    /// charge for an edge between nodes at `from` and `to` (decision 132),
    /// shaped by `curve` and `profile` and carried by `structure`: its
    /// sections measured from the ground and priced the same way, without
    /// building anything, so a layout planned ahead (the real-world demo)
    /// knows what it costs. The nodes need not be built. Read only.
    ///
    /// - Throws: ``GameError/invalidTrackGeometry``,
    ///   ``GameError/trackTooSteep``, and what the ground's rules throw,
    ///   as building the edge would; nothing about the network, trains or
    ///   money.
    public func trackEdgePrice(
        from: WorldCoordinate, to: WorldCoordinate, curve: TrackCurve = .straight, profile: TrackProfile = .uniform,
        structure: TrackStructure = .surface
    ) throws(GameError) -> Money {
        guard from != to, curve.controlPoints.allSatisfy(bounds.contains),
              let geometry = TrackGeometry(from: from, to: to, curve: curve, profile: profile)
        else { throw .invalidTrackGeometry }
        guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) else { throw .trackTooSteep }
        return try edgeCost(of: geometry, structure: structure, sections: sections(of: geometry, structure: structure))
    }

    /// Edge `id`'s long section and its price in parts (decision 124, H3),
    /// measured as ``buildTrackEdge(from:to:curve:profile:structure:)``
    /// measured and charged it; `nil` for an edge the network does not
    /// have, or one over ground the world has not read. Read only.
    public func longSection(of id: TrackEdgeID) -> TrackLongSection? {
        guard let edge = network.edge(id), let geometry = trackGeometry(of: id),
              let pieces = try? pricedPieces(of: geometry, structure: edge.structure, sections: edge.sections),
              let cost = costParts(of: pieces, extras: edge.structure == .automatic || ground.isMapped)
        else { return nil }
        let spans = edge.sectionSpans
        func sample(at distance: Int64, kind: TrackSectionKind) -> TrackGroundSample? {
            let point = geometry.location(at: distance).position
            guard let ground = groundHeight(at: point.plan) else { return nil }
            let isWater = self.ground.isMapped && terrain.isWater(row: Land.cellIndex(point.y), column: Land.cellIndex(point.x))
            return TrackGroundSample(distance: distance, rail: point.z, ground: ground, kind: kind, isWater: isWater)
        }
        var samples: [TrackGroundSample] = []
        guard let first = sample(at: 0, kind: spans[0].kind) else { return nil }
        samples.append(first)
        for (length, kind) in pieces {
            let middle = (length.start + length.end) / 2
            samples.append(TrackGroundSample(
                distance: middle, rail: geometry.height(at: middle), ground: geometry.height(at: middle) - length.delta, kind: kind, isWater: length.isWater
            ))
        }
        guard let last = sample(at: geometry.length, kind: spans[spans.count - 1].kind) else { return nil }
        samples.append(last)
        return TrackLongSection(length: geometry.length, samples: samples, spans: spans, cost: cost)
    }

    /// What `pieces` cost in parts at this world's track price, as
    /// ``price(of:track:extras:)`` adds them up (``edgeCost(of:structure:sections:)``
    /// says when it takes the `extras`); `nil` when they do not fit in a
    /// whole number.
    func costParts(of pieces: [(TrackPricedLength, TrackSectionKind)], extras: Bool) -> TrackCostParts? {
        let track = economy.costs.track.amount
        var lengths: Int64 = 0, structures: Int64 = 0, tunnels: Int64 = 0, earth: Int64 = 0, piers: Int64 = 0
        var overflow = false
        func add(_ value: Int64, to total: inout Int64) {
            let (sum, carry) = total.addingReportingOverflow(value)
            overflow = overflow || carry
            total = sum
        }
        for (length, kind) in pieces {
            add(1, to: &lengths)
            let past = kind.structure.costFactor - 1
            if kind == .tunnel { add(past, to: &tunnels) } else { add(past, to: &structures) }
            guard extras else { continue }
            if kind.isOnGround {
                add(TrackSectionRules.earthwork(length.delta), to: &earth)
            } else if kind == .viaduct || kind == .bridge, length.delta > TrackSectionRules.tallPier {
                add(length.delta - TrackSectionRules.tallPier, to: &piers)
            }
        }
        func times(_ count: Int64) -> Int64 {
            let (value, carry) = track.multipliedReportingOverflow(by: count)
            overflow = overflow || carry
            return value
        }
        func share(_ numerator: Int64, _ divisor: Int64) -> Int64 {
            let (value, carry) = Self.share(of: track, numerator, divisor)
            overflow = overflow || carry
            return value
        }
        var bridges = times(structures)
        add(share(piers, TrackSectionRules.pierStep), to: &bridges)
        let parts = TrackCostParts(
            track: Money(times(lengths)), earthwork: Money(share(earth, TrackSectionRules.earthworkDivisor)),
            viaductsAndBridges: Money(bridges), tunnels: Money(times(tunnels))
        )
        var total: Int64 = 0
        for part in [parts.track, parts.earthwork, parts.viaductsAndBridges, parts.tunnels] {
            add(part.amount, to: &total)
        }
        return overflow ? nil : parts
    }
}
