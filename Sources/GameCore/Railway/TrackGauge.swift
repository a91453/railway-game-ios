// Track gauges and loading gauges (decision 970): how far apart ordinary
// track's rails are, and how big a train its clearances take. Each edge of
// ordinary track (decision 951's `TrackSystem.conventional`) has one; a
// guideway has none.
//
// - Rail gauges, millimetres between the rails' inner faces: 1,067 (the
//   Taiwan Railway's and Japan's conventional lines, the "Cape gauge"),
//   1,435 (standard gauge: Taiwan's high-speed railway and metros, Hong
//   Kong's MTR, Japan's Shinkansen and the Fukuoka Nanakuma Line), 762 (the
//   Alishan Forest Railway's) and 1,524 (Finland's).
// - Loading gauges, two classes: a conventional line's and the
//   Shinkansen's, whose cars are wider (3.38 m against about 2.9–2.95 m)
//   and taller. A mini-Shinkansen line (Yamagata, Akita) is a conventional
//   line regauged to 1,435 mm whose clearances stayed conventional, which
//   is why the mini-Shinkansen's trains are built narrow: they run on
//   it and, through it, on to the Shinkansen. A Shinkansen train is too big
//   for a conventional line.
// - Track may have more than one rail gauge (three rails, 三線軌): the
//   Seikan Tunnel's 1,067 and 1,435 mm at the Shinkansen's loading gauge,
//   the Ou Line's between Jingūji and Mineyoshikawa, Taiwan's sugar
//   railways' 762 mm beside the Taiwan Railway's 1,067. The game lays it
//   for a save from before version 114, where every train ran everywhere
//   (``GameWorld/layGauges()``); the track tool offers single gauges.
//
// Train types: each real model has the gauge and size of the real train
// (`TrainTypeCatalog.swift`); the reference's types (A, B, C, L, D, APM)
// and the standard car have no real train behind them and run on any
// ordinary track of 1,067, 1,435 or 1,524 mm (not the forest railway's
// 762, whose small coaches only it builds), as every train ran before.
//
// The owner's references have no rule for any of this: the rail reference
// draws its rails at one gauge (`rail-3d/garage-scenes/metro-kit.js`'s
// `GAUGE`) and the other references have no gauge at all, so the rules are
// this project's (gap); `docs/decisions/970.md` lists where each number
// comes from.

/// How far apart a track's rails are, millimetres (decision 970).
public enum RailGauge: Int, Hashable, Codable, CaseIterable, Comparable, Sendable {
    /// The Alishan Forest Railway's 762 mm.
    case forest = 762
    /// The Taiwan Railway's and Japan's conventional lines' 1,067 mm.
    case cape = 1_067
    /// Standard gauge, 1,435 mm.
    case standard = 1_435
    /// Finland's 1,524 mm.
    case broad = 1_524

    /// The gauge in millimetres.
    public var millimetres: Int { rawValue }

    public static func < (lhs: RailGauge, rhs: RailGauge) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How big a train a track's clearances take (decision 970): a
/// conventional line's, or the Shinkansen's, which takes the bigger
/// Shinkansen cars and every smaller one.
public enum LoadingGauge: String, Hashable, Codable, CaseIterable, Comparable, Sendable {
    case conventional
    case shinkansen

    public static func < (lhs: LoadingGauge, rhs: LoadingGauge) -> Bool {
        lhs == .conventional && rhs == .shinkansen
    }
}

/// The gauge of an edge of ordinary track (decision 970): its rail gauges
/// (one, or more on three-rail track) and its loading gauge.
public struct TrackGauge: Hashable, Sendable {
    /// Its rail gauges, never empty.
    public let rails: Set<RailGauge>
    /// How big a train its clearances take.
    public let loading: LoadingGauge

    /// Track of rail gauges `rails` (never empty) and loading gauge
    /// `loading`.
    public init(rails: Set<RailGauge>, loading: LoadingGauge = .conventional) {
        precondition(!rails.isEmpty, "A track has at least one rail gauge.")
        self.rails = rails
        self.loading = loading
    }

    /// Track of one rail gauge.
    public init(_ rail: RailGauge, loading: LoadingGauge = .conventional) {
        self.init(rails: [rail], loading: loading)
    }

    /// 1,067 mm at a conventional loading gauge: the Taiwan Railway's,
    /// Japan's conventional lines'; the gauge of track nothing else sets.
    public static let cape = TrackGauge(.cape)
    /// 1,435 mm at a conventional loading gauge: a metro's, Hong Kong's
    /// MTR, a mini-Shinkansen line's.
    public static let standard = TrackGauge(.standard)
    /// 1,435 mm at the Shinkansen's loading gauge: Taiwan's high-speed
    /// railway, the Shinkansen.
    public static let shinkansen = TrackGauge(.standard, loading: .shinkansen)
    /// The Alishan Forest Railway's 762 mm.
    public static let forest = TrackGauge(.forest)
    /// Finland's 1,524 mm.
    public static let broad = TrackGauge(.broad)

    /// The gauge of track built where nothing sets one: the Taiwan
    /// Railway's 1,067 mm (``TrackEdge/gauge``).
    public static let `default` = cape

    /// The gauges the track tool offers, in its order.
    public static let offered: [TrackGauge] = [.cape, .standard, .shinkansen, .forest, .broad]

    /// Its rail gauges, narrowest first.
    public var sortedRails: [RailGauge] { rails.sorted() }

    /// A short name for it, for a command log: its rail gauges in
    /// millimetres, narrowest first and joined by `+`, then `s` for the
    /// Shinkansen's loading gauge (`1067`, `1435s`, `1067+1435s`).
    public var code: String {
        sortedRails.map { String($0.millimetres) }.joined(separator: "+") + (loading == .shinkansen ? "s" : "")
    }

    /// The gauge ``code`` names; `nil` for a name that names none.
    public init?(code: String) {
        var text = Substring(code)
        let loading: LoadingGauge = text.hasSuffix("s") ? .shinkansen : .conventional
        if loading == .shinkansen { text = text.dropLast() }
        let rails = text.split(separator: "+", omittingEmptySubsequences: false).map { Int($0).flatMap(RailGauge.init(rawValue:)) }
        guard !rails.isEmpty, !rails.contains(nil) else { return nil }
        let gauges = rails.compactMap { $0 }
        guard Set(gauges).count == gauges.count, gauges == gauges.sorted() else { return nil }
        self.init(rails: Set(gauges), loading: loading)
    }

    /// Its widest rail gauge.
    public var widest: RailGauge { rails.max() ?? .cape }

    /// Track that takes what this and `other` take: both one's rails and
    /// the bigger loading gauge.
    public func merged(with other: TrackGauge) -> TrackGauge {
        TrackGauge(rails: rails.union(other.rails), loading: max(loading, other.loading))
    }

    /// The gauge a bought real line is laid at (decision 970), by its name
    /// in the app's data (``LineAcquisition/realLine``, `tra:PINGXI`,
    /// `hkmtr:TCL`): the Taiwan Railway's 1,067 mm; the high-speed
    /// railway's 1,435 mm at the Shinkansen's loading gauge; the forest
    /// railway's 762; standard gauge for Taiwan's metros and light rails
    /// and Hong Kong's MTR (1,432 mm, 3 mm under standard gauge; the game
    /// lays it at 1,435); Finland's 1,524; the Fukuoka City Subway's
    /// Kūkō and Hakozaki Lines 1,067 and its Nanakuma Line 1,435. `nil`
    /// for a name of a system the game does not know.
    public static func ofRealLine(_ name: String) -> TrackGauge? {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard let system = parts.first else { return nil }
        switch system {
        case "tra", "tra_sched": return .cape
        case "thsr", "thsr_sched": return .shinkansen
        case "afr", "afr_sched": return .forest
        case "trtc", "mrt", "tmrt", "krtc", "tymc", "ntdlrt", "ntalrt", "sanying", "hkmtr": return .standard
        case "vr": return .broad
        case "fksubway": return parts.count > 1 && parts[1] == "N" ? .standard : .cape
        default: return nil
        }
    }
}

extension TrackGauge: Codable {
    private enum CodingKeys: String, CodingKey {
        case rails, loading
    }

    /// Reads `{"rails": [1067, 1435], "loading": "shinkansen"}`, `"loading"`
    /// written only for the Shinkansen's.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rails = try container.decode([RailGauge].self, forKey: .rails)
        guard !rails.isEmpty, Set(rails).count == rails.count, rails == rails.sorted() else {
            throw DecodingError.dataCorruptedError(
                forKey: .rails, in: container, debugDescription: "A track's rail gauges are at least one, each once, narrowest first."
            )
        }
        let loading = container.contains(.loading) ? try container.decode(LoadingGauge.self, forKey: .loading) : .conventional
        guard loading != .conventional || !container.contains(.loading) else {
            throw DecodingError.dataCorruptedError(
                forKey: .loading, in: container, debugDescription: "A conventional loading gauge is not written."
            )
        }
        self.init(rails: Set(rails), loading: loading)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sortedRails, forKey: .rails)
        if loading != .conventional {
            try container.encode(loading, forKey: .loading)
        }
    }
}

/// The wheels and body of a real train (decision 970): the rail gauge it
/// runs on and how big it is.
public struct TrainGauge: Hashable, Sendable {
    /// The rail gauge of its wheels.
    public let rail: RailGauge
    /// How big it is: a Shinkansen car needs the Shinkansen's loading
    /// gauge; a conventional one (a mini-Shinkansen's too) fits either.
    public let loading: LoadingGauge

    public init(_ rail: RailGauge, loading: LoadingGauge = .conventional) {
        self.rail = rail
        self.loading = loading
    }

    /// A Taiwan Railway train's, a Japanese conventional line's.
    public static let cape = TrainGauge(.cape)
    /// A standard-gauge train of conventional size: Taipei Metro's C381,
    /// a mini-Shinkansen train.
    public static let standard = TrainGauge(.standard)
    /// A Shinkansen-size train: the high-speed set (decision 168, the
    /// 700T).
    public static let shinkansen = TrainGauge(.standard, loading: .shinkansen)
    /// The Alishan Forest Railway's.
    public static let forest = TrainGauge(.forest)

    /// Whether it runs on track of `gauge`: one of its rail gauges is the
    /// train's, and its clearances take a train this big.
    public func runs(on gauge: TrackGauge) -> Bool {
        gauge.rails.contains(rail) && loading <= gauge.loading
    }
}

extension TrackCompatibility {
    /// The rail gauges a train of no real model runs on (decision 970):
    /// the reference's types and the standard car.
    public static let anyModelRails: Set<RailGauge> = [.cape, .standard, .broad]

    /// Whether a train of `type` (`nil`, the standard car) runs on
    /// ordinary track of `gauge` (decision 970): a real model where
    /// ``TrainGauge/runs(on:)`` says so; a type of no real model on any
    /// track with a rail gauge of 1,067, 1,435 or 1,524 mm. A guideway
    /// train's type has no gauge: its rule is the guideway's
    /// (``runs(_:on:)``).
    public static func runs(_ type: TrainType?, onGauge gauge: TrackGauge) -> Bool {
        guard let wheels = type?.gauge else { return !gauge.rails.isDisjoint(with: anyModelRails) }
        return wheels.runs(on: gauge)
    }
}

extension Train {
    /// Its wheels and body (decision 970): its type's; `nil` for a type of
    /// no real model and the standard car.
    public var gauge: TrainGauge? { type?.gauge }
}

extension GameWorld {
    /// The gauges of the ordinary track `line` runs on (decision 970):
    /// those of the edges its services' journeys (each way round a ring)
    /// start on, run along or stop on. Empty for a line with no way
    /// through or one only on guideways. Pure.
    func trackGauges(of line: ServiceLine) -> Set<TrackGauge> {
        var gauges = Set<TrackGauge>()
        let directions: [RingDirection] = line.isRing ? RingDirection.allCases : [.inner]
        for service in 0..<line.serviceCount {
            for direction in directions {
                guard let journey = journey(of: line, service: service, direction: direction) else { continue }
                for edge in Self.edges(of: journey) {
                    if let edge = network.edge(edge), !edge.system.isGuideway { gauges.insert(edge.gauge) }
                }
            }
        }
        return gauges
    }

    /// The gauges of the ordinary track line `id` runs on (decision 970),
    /// so that only a train that runs on all of them
    /// (``TrackCompatibility/runs(_:onGauge:)``) may be assigned to it;
    /// empty for a line the world does not have or one with no way
    /// through. Pure.
    public func trackGauges(ofLine id: LineID) -> Set<TrackGauge> {
        line(id: id).map(trackGauges) ?? []
    }

    /// Whether every train of no real model runs on every ordinary edge
    /// (decision 970): no edge is of the forest railway's gauge alone, so
    /// a world without one answers their rule at once.
    var anyModelRunsEverywhere: Bool {
        !network.edges.contains { !$0.system.isGuideway && $0.gauge.rails.isDisjoint(with: TrackCompatibility.anyModelRails) }
    }

    /// Whether a train of `type` may be put on `line` as far as gauges go
    /// (decision 970): it runs on the gauge of every edge of ordinary track
    /// the line runs on.
    func fitsGauge(_ type: TrainType?, on line: ServiceLine) -> Bool {
        if type?.gauge == nil, anyModelRunsEverywhere { return true }
        return trackGauges(of: line).allSatisfy { TrackCompatibility.runs(type, onGauge: $0) }
    }

    /// ``fitsGauge(_:on:)`` of line `id`; `true` for a line it does not
    /// have.
    public func fitsGauge(_ type: TrainType?, ofLine id: LineID) -> Bool {
        line(id: id).map { fitsGauge(type, on: $0) } ?? true
    }

    /// Whether train `train` may stand on or run over `edges` by hand as
    /// far as gauges go (decision 970): it runs on each ordinary edge's
    /// gauge.
    func fitsGauge(_ train: Train, over edges: some Sequence<TrackEdgeID>) -> Bool {
        if train.gauge == nil, anyModelRunsEverywhere { return true }
        return edges.allSatisfy { id in
            guard let edge = network.edge(id), !edge.system.isGuideway else { return true }
            return TrackCompatibility.runs(train.type, onGauge: edge.gauge)
        }
    }

    /// Takes off each line every train that does not run on the gauge of
    /// the track its way now runs on (decision 970): after an edit moved
    /// the line's way onto track of another gauge, as
    /// ``releaseTrainsOffTheirSystem()`` does for guideways, and called
    /// with it. A guideway train is left to that rule. A world whose
    /// trains are all of no real model and that has no forest track
    /// changes nothing and answers at once.
    mutating func releaseTrainsOffTheirGauge() {
        let real = trains.filter { $0.gauge != nil && !$0.trackSystem.isGuideway }
        guard !real.isEmpty || !anyModelRunsEverywhere else { return }
        var types: [TrainID: TrainType?] = [:]
        for train in trains where !train.trackSystem.isGuideway { types[train.id] = .some(train.type) }
        for index in lines.indices {
            let assigned = (lines[index].trains + lines[index].patterns.flatMap(\.trains)).filter { types[$0] != nil }
            guard !assigned.isEmpty else { continue }
            let gauges = trackGauges(of: lines[index])
            guard !gauges.isEmpty else { continue }
            func stays(_ id: TrainID) -> Bool {
                guard let type = types[id] else { return true }
                return gauges.allSatisfy { TrackCompatibility.runs(type, onGauge: $0) }
            }
            guard !assigned.allSatisfy(stays) else { continue }
            lines[index].trains.removeAll { !stays($0) }
            for pattern in lines[index].patterns.indices {
                lines[index].patterns[pattern].trains.removeAll { !stays($0) }
            }
        }
    }

    /// The gauge a new edge of ordinary track between `from` and `to` takes
    /// when none is asked for (decision 970): the forest railway's for
    /// mountain track (only its trains climb); for the rest, that of the
    /// ordinary track it joins at `from`, else at `to` (the lowest
    /// numbered edge's), and ``TrackGauge/default`` where it joins none.
    func joinedGauge(from: TrackNodeID, to: TrackNodeID, mountain: Bool) -> TrackGauge {
        guard !mountain else { return .forest }
        for node in [from, to] {
            if let gauge = network.gauge(at: node) { return gauge }
        }
        return .default
    }

    // MARK: - Saves from before version 114

    /// Lays every edge of ordinary track at a gauge (decision 970), for a
    /// save from before version 114, where every edge is of the default
    /// gauge and every train ran on all of them, so that every train still
    /// runs where it ran.
    ///
    /// What each edge must carry: the gauge of each real model whose train
    /// runs along it on a line, or stands on it (a type of no real model
    /// asks for none), and the real line's gauge (``TrackGauge/ofRealLine(_:)``)
    /// for the track a bought line laid. An edge that must carry one
    /// gauge is laid at it; one that must carry two or more, at all of
    /// them (three-rail track, the bigger loading gauge). An edge that must
    /// carry nothing takes what the edges joined to it (its piece of the
    /// network) carry together, and ``TrackGauge/default`` where they carry
    /// nothing either, or the forest railway's for mountain track. Nothing
    /// is charged, and the track's book value stays.
    mutating func layGauges() {
        var needs: [TrackEdgeID: TrackGauge] = [:]
        func note(_ gauge: TrackGauge, on id: TrackEdgeID) {
            guard let edge = network.edge(id), !edge.system.isGuideway else { return }
            needs[id] = needs[id].map { $0.merged(with: gauge) } ?? gauge
        }
        func gauge(of wheels: TrainGauge) -> TrackGauge { TrackGauge(wheels.rail, loading: wheels.loading) }

        for acquisition in acquisitions {
            guard let track = acquisition.track, let real = TrackGauge.ofRealLine(acquisition.realLine) else { continue }
            for edge in track { note(real, on: edge) }
        }
        var wheels: [TrainID: TrainGauge] = [:]
        for train in trains where !train.trackSystem.isGuideway {
            guard let gauge = train.gauge else { continue }
            wheels[train.id] = gauge
            guard case .onEdge(let traversal, _)? = train.position else { continue }
            for edge in [traversal.edge] + train.trailEdges { note(TrackGauge(gauge.rail, loading: gauge.loading), on: edge) }
        }
        if !wheels.isEmpty {
            for line in lines {
                let directions: [RingDirection] = line.isRing ? RingDirection.allCases : [.inner]
                for service in 0..<line.serviceCount {
                    let running = Set(line.trains(ofService: service).compactMap { wheels[$0] })
                    guard !running.isEmpty else { continue }
                    for direction in directions {
                        guard let journey = journey(of: line, service: service, direction: direction) else { continue }
                        for edge in Self.edges(of: journey) {
                            for train in running { note(gauge(of: train), on: edge) }
                        }
                    }
                }
            }
        }
        guard !needs.isEmpty || network.edges.contains(where: \.mountain) else { return }

        // Each piece of the network, by its lowest node's place in the list.
        var piece = Array(network.nodes.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while piece[index] != index { index = piece[index] }
            return index
        }
        var place: [TrackNodeID: Int] = [:]
        for (index, node) in network.nodes.enumerated() { place[node.id] = index }
        for edge in network.edges where !edge.system.isGuideway {
            guard let from = place[edge.from], let to = place[edge.to] else { continue }
            let a = root(from), b = root(to)
            if a != b { piece[max(a, b)] = min(a, b) }
        }
        var pieces: [Int: TrackGauge] = [:]
        for edge in network.edges {
            guard let need = needs[edge.id], let node = place[edge.from] else { continue }
            let key = root(node)
            pieces[key] = pieces[key].map { $0.merged(with: need) } ?? need
        }

        var laid: [TrackEdgeID: TrackGauge] = [:]
        for edge in network.edges where !edge.system.isGuideway {
            let gauge = needs[edge.id]
                ?? place[edge.from].flatMap { pieces[root($0)] }
                ?? (edge.mountain ? .forest : .default)
            if gauge != edge.gauge { laid[edge.id] = gauge }
        }
        setTrackGauges(laid)
    }
}
