// Track systems (decision 951): what a train runs on. Ordinary track (two
// steel rails) or the guideway of one of the three guideway trains of
// decision 930: the straddle monorail's concrete beam, the maglev's
// guideway and the suspended monorail's box beam. Each edge has one,
// chosen when it is built, and a guideway is its trains' alone: no other
// train runs on it, and it never joins track of another system at a node.
//
// The owner's references have no rule for any of this (their maglev,
// `OpenWorld/reference_snapshot/play/src/world/taiwan-maglev-data.js`, is
// a 1,000 km/h line of 2068 on its own path, with no track kinds; the
// rail reference's `rail-3d/garage-scenes/metro-kit.js` draws track kinds
// and has no rules), so the numbers are this project's, from what real
// systems publish (gap; `docs/decisions/951.md` lists them):
//
// - Speed, km/h, the fastest any train runs a guideway: 80 on a straddle
//   beam (Tokyo Monorail's top speed, as Hitachi Rail lists it; Naha's
//   is 65), 75 under a suspended beam (the Shonan Monorail's), 100 on an
//   urban maglev's guideway (Linimo's operating speed).
// - Cost, thousandths of what ordinary track carried the same way costs:
//   1,200 a straddle beam, 1,300 a suspended one, 1,600 a maglev
//   guideway. This project's own: no published figure compares a beam
//   with a railway viaduct on the same ground (Linimo's 8.9 km cost
//   about ¥60 billion without its trains; nothing as sure was found for
//   a monorail), so the order is the only claim: a guideway costs more
//   than rails on the same structure, the suspended beam's steel box
//   and frames a little over the concrete beam, the maglev's guideway
//   with its stators and reaction plates the most.

/// What a train runs on (decision 951).
public enum TrackSystem: String, Hashable, Codable, CaseIterable, Sendable {
    /// Two steel rails: every train but the three guideway trains.
    case conventional
    /// The straddle monorail's beam (`MONORAIL`).
    case straddle
    /// The maglev's guideway (`MAGLEV`).
    case maglev
    /// The suspended monorail's beam (`SKYRAIL`).
    case suspended

    /// Whether it is a guideway: anything but ordinary track.
    public var isGuideway: Bool { self != .conventional }

    /// The fastest any train runs on it, km/h; `nil` on ordinary track,
    /// which has no limit of its own.
    public var speedLimit: Int64? {
        switch self {
        case .conventional: nil
        case .straddle: 80
        case .maglev: 100
        case .suspended: 75
        }
    }

    /// What an edge of it costs, in thousandths of what ordinary track
    /// carried the same way over the same ground costs.
    public var costPermille: Int64 {
        switch self {
        case .conventional: 1_000
        case .straddle: 1_200
        case .maglev: 1_600
        case .suspended: 1_300
        }
    }

    /// What an edge of it costs when ordinary track there costs
    /// `ordinary`, rounded half up; and whether that overflowed.
    static func price(of ordinary: Int64, on system: TrackSystem) -> (value: Int64, overflow: Bool) {
        guard system.isGuideway else { return (ordinary, false) }
        return GameWorld.share(of: ordinary, system.costPermille, 1_000)
    }

    /// The speed limits along an edge of `geometry` shaped by `curve`: its
    /// curves' and its grade's (``MountainTrack/speedLimits(of:curve:mountain:)``)
    /// and, on a guideway, the guideway's over the whole of it, merged.
    static func speedLimits(of geometry: TrackGeometry, curve: TrackCurve, mountain: Bool, system: TrackSystem) -> [TrackSpeedLimit] {
        let limits = MountainTrack.speedLimits(of: geometry, curve: curve, mountain: mountain)
        guard let speed = system.speedLimit, geometry.length > 0 else { return limits }
        return CurveSpeedLimit.merged(limits + [TrackSpeedLimit(start: 0, end: geometry.length, speed: speed)], within: geometry.length)
    }
}

/// A row of the table of which train runs on which track (decision 951):
/// an edge's system, with mountain track (decision 515, ordinary track
/// steeper than the rest) a row of its own.
public enum TrackKind: String, Hashable, CaseIterable, Sendable {
    case conventional
    case mountain
    case straddle
    case maglev
    case suspended

    /// The kind of track of `system`, mountain track or not.
    public init(system: TrackSystem, mountain: Bool) {
        switch system {
        case .conventional: self = mountain ? .mountain : .conventional
        case .straddle: self = .straddle
        case .maglev: self = .maglev
        case .suspended: self = .suspended
        }
    }

    /// Its system: mountain track is ordinary track.
    public var system: TrackSystem {
        switch self {
        case .conventional, .mountain: .conventional
        case .straddle: .straddle
        case .maglev: .maglev
        case .suspended: .suspended
        }
    }
}

extension TrackEdge {
    /// Its row of the table (decision 951).
    public var kind: TrackKind { TrackKind(system: system, mountain: mountain) }
}

/// Which train runs on which track (decision 951).
///
/// | train                      | conventional | mountain | straddle | maglev | suspended |
/// | -------------------------- | :----------: | :------: | :------: | :----: | :-------: |
/// | the standard car, any other type | yes    | no       | no       | no     | no        |
/// | a mountain train (`ALISHAN`)     | yes    | yes      | no       | no     | no        |
/// | `MONORAIL`                 | no           | no       | yes      | no     | no        |
/// | `MAGLEV`                   | no           | no       | no       | yes    | no        |
/// | `SKYRAIL`                  | no           | no       | no       | no     | yes       |
///
/// A mountain train on ordinary track is decision 515's, kept (gauges are
/// not modelled). A guideway train a save from before version 112 has on
/// a line that runs on ordinary track stays on it (``GameWorld/layGuideways()``
/// says when); no command puts one there.
public enum TrackCompatibility {
    /// Whether a train of `type` (`nil`, the standard car) runs on track
    /// of `kind`.
    public static func runs(_ type: TrainType?, on kind: TrackKind) -> Bool {
        let system = type?.trackSystem ?? .conventional
        switch kind {
        case .conventional: return system == .conventional
        case .mountain: return system == .conventional && (type?.climbsMountains ?? false)
        case .straddle, .maglev, .suspended: return system == kind.system
        }
    }
}

extension Train {
    /// The track system it runs on (decision 951): its type's; the
    /// standard car runs on ordinary track.
    public var trackSystem: TrackSystem {
        type?.trackSystem ?? .conventional
    }
}

extension GameWorld {
    /// The edges `journey` starts on and runs along.
    static func edges(of journey: LineJourney) -> Set<TrackEdgeID> {
        var edges = Set<TrackEdgeID>()
        if case .onEdge(let traversal, _) = journey.start { edges.insert(traversal.edge) }
        for leg in journey.legs {
            for traversal in leg.path.traversals { edges.insert(traversal.edge) }
        }
        return edges
    }

    /// The kinds of track `line` runs on (decision 951): those of the
    /// edges its services' journeys (each way round a ring) start on, run
    /// along or stop on. Empty for a line with no way through. Pure.
    func trackKinds(of line: ServiceLine) -> Set<TrackKind> {
        var kinds = Set<TrackKind>()
        let directions: [RingDirection] = line.isRing ? RingDirection.allCases : [.inner]
        for service in 0..<line.serviceCount {
            for direction in directions {
                guard let journey = journey(of: line, service: service, direction: direction) else { continue }
                for edge in Self.edges(of: journey) {
                    if let kind = network.edge(edge)?.kind { kinds.insert(kind) }
                }
            }
        }
        return kinds
    }

    /// The kinds of track line `id` runs on (decision 951), so that only
    /// a train that runs on all of them (``TrackCompatibility``) may be
    /// assigned to it; empty for a line the world does not have or one
    /// with no way through. Pure.
    public func trackKinds(ofLine id: LineID) -> Set<TrackKind> {
        line(id: id).map(trackKinds) ?? []
    }

    /// Whether the network has any guideway (decision 951): a world with
    /// none answers every guideway rule at once.
    var hasGuideways: Bool {
        network.edges.contains { $0.system.isGuideway }
    }

    /// Whether a train of `type` may be put on `line` (decision 951): it
    /// runs on every kind of track the line runs on. Mountain track is
    /// left to decision 515's own rule (``runsOnMountainTrack(_:)``), which
    /// answers first with its own error.
    func runs(_ type: TrainType?, on line: ServiceLine) -> Bool {
        let system = type?.trackSystem ?? .conventional
        guard system.isGuideway || hasGuideways else { return true }
        return trackKinds(of: line).allSatisfy { $0 == .mountain || TrackCompatibility.runs(type, on: $0) }
    }

    /// Whether train `train` may stand on or run over `edges` by hand
    /// (decision 951): each is of its system. A guideway train a line
    /// that runs on ordinary track still holds from before version 112
    /// may also be on ordinary track.
    func runs(_ train: Train, over edges: some Sequence<TrackEdgeID>) -> Bool {
        let system = train.trackSystem
        guard system.isGuideway || hasGuideways else { return true }
        let others = Set(edges.compactMap { network.edge($0)?.system }).subtracting([system])
        guard !others.isEmpty else { return true }
        guard system.isGuideway, others == [.conventional], let line = assignedLine(of: train.id).flatMap({ self.line(id: $0) }) else {
            return false
        }
        return trackKinds(of: line).contains(.conventional)
    }

    /// Takes off each line that runs on a guideway every train of another
    /// system (decision 951): after an edit moved the line's way onto it,
    /// as ``releaseTrainsThatCannotClimb()`` does for mountain track, and
    /// called with it. A guideway train on a line that runs on ordinary
    /// track only is left (a save from before version 112 may hold one). A
    /// world with no guideway changes nothing and answers at once.
    mutating func releaseTrainsOffTheirSystem() {
        guard hasGuideways else { return }
        var systems: [TrainID: TrackSystem] = [:]
        for train in trains { systems[train.id] = train.trackSystem }
        for index in lines.indices {
            let assigned = lines[index].trains + lines[index].patterns.flatMap(\.trains)
            guard !assigned.isEmpty else { continue }
            let guideways = Set(trackKinds(of: lines[index]).map(\.system).filter(\.isGuideway))
            guard !guideways.isEmpty else { continue }
            func stays(_ id: TrainID) -> Bool { guideways == [systems[id] ?? .conventional] }
            guard !assigned.allSatisfy(stays) else { continue }
            lines[index].trains.removeAll { !stays($0) }
            for pattern in lines[index].patterns.indices {
                lines[index].patterns[pattern].trains.removeAll { !stays($0) }
            }
        }
    }

    // MARK: - Saves from before version 112

    /// Turns the track only guideway trains run on into their guideway
    /// (decision 951), for a save from before version 112, where every
    /// edge is ordinary track: decision 947's rule (the presentation's
    /// `Map3DGuideway.edges(in:)`, which drew those edges as beams), taken
    /// to whole pieces of the network, because a guideway never joins
    /// other track.
    ///
    /// A piece of the network (the edges joined to each other through
    /// their nodes) becomes the guideway of one system when a line whose
    /// trains are all of that system runs on it, and nothing else does: no
    /// line with a train of another system, no train of another system
    /// standing on it, and no mountain track in it. Any other piece stays
    /// ordinary track, and the guideway trains on it stay on their lines
    /// (``TrackCompatibility``). A line with no train decides nothing.
    /// Nothing is charged, and the track's book value stays.
    mutating func layGuideways() {
        var systems: [TrainID: TrackSystem] = [:]
        for train in trains { systems[train.id] = train.trackSystem }
        guard systems.values.contains(where: \.isGuideway) else { return }

        // Each piece of the network, by its lowest node's place in the list.
        var piece = Array(network.nodes.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while piece[index] != index { index = piece[index] }
            return index
        }
        var place: [TrackNodeID: Int] = [:]
        for (index, node) in network.nodes.enumerated() { place[node.id] = index }
        for edge in network.edges {
            guard let from = place[edge.from], let to = place[edge.to] else { continue }
            let a = root(from), b = root(to)
            if a != b { piece[max(a, b)] = min(a, b) }
        }
        func pieceOf(_ id: TrackEdgeID) -> Int? {
            network.edge(id).flatMap { place[$0.from] }.map(root)
        }

        // What runs on each piece: `nil` once two systems do.
        var found: [Int: TrackSystem?] = [:]
        func note(_ system: TrackSystem, on edge: TrackEdgeID) {
            guard let piece = pieceOf(edge) else { return }
            if let known = found[piece] {
                if known != system { found[piece] = .some(nil) }
            } else {
                found[piece] = .some(system)
            }
        }
        for edge in network.edges where edge.mountain { note(.conventional, on: edge.id) }
        for train in trains {
            guard case .onEdge(let traversal, _)? = train.position else { continue }
            for edge in [traversal.edge] + train.trailEdges { note(train.trackSystem, on: edge) }
        }
        for line in lines {
            let directions: [RingDirection] = line.isRing ? RingDirection.allCases : [.inner]
            for service in 0..<line.serviceCount {
                let running = Set(line.trains(ofService: service).map { systems[$0] ?? .conventional })
                guard !running.isEmpty else { continue }
                for direction in directions {
                    guard let journey = journey(of: line, service: service, direction: direction) else { continue }
                    for edge in Self.edges(of: journey) {
                        for system in running { note(system, on: edge) }
                    }
                }
            }
        }

        var laid: [TrackEdgeID: TrackSystem] = [:]
        for edge in network.edges {
            guard let piece = pieceOf(edge.id), case .some(.some(let system)) = found[piece], system.isGuideway else { continue }
            laid[edge.id] = system
        }
        setTrackSystems(laid)
    }
}
