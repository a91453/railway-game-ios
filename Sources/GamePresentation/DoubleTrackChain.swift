import GameCore

// A second track beside a chain of edges (ARCHITECTURE decision 257): the
// track traced along a real line with double track on, and the select
// tool's "Make double track" on track already there. Both lay the same
// thing: a parallel chain ``DoubleTrack/spacing`` (5 m) to one side, its
// nodes beside the chain's, each leaving and arriving along the chain's own
// directions so the two stay 5 m apart round its curves; at a node where
// the chain bends, the offset is the miter (5 m / cos of half the bend), as
// the reference offsets a polyline
// (`Railway/location_modeler_reference_clean/source/js/app.js`,
// `offsetFn`). Then the platforms the chain's stations have, copied onto
// the second track for the same stations, and a crossover at each end from
// the second track over to the first, so trains reach the track beyond.
// All of it is one command (``PlayerCommand/buildDoubleTrackChain(main:parallel:platforms:crossovers:)``),
// built or refused as one, and undone as one.

/// One piece of a chain, as it runs: from, curve and to in the chain's
/// direction.
struct ChainSegment {
    let from: WorldCoordinate
    let to: WorldCoordinate
    let curve: TrackCurve
    let profile: TrackProfile
    let structure: TrackStructure

    var geometry: TrackGeometry? {
        TrackGeometry(from: from, to: to, curve: curve, profile: profile)
    }

    /// The stretch's own piece.
    init(_ stretch: PlayerCommand.TrackStretch) {
        self.init(from: stretch.from, to: stretch.to, curve: stretch.curve, profile: stretch.profile, structure: stretch.structure)
    }

    init(from: WorldCoordinate, to: WorldCoordinate, curve: TrackCurve, profile: TrackProfile, structure: TrackStructure) {
        self.from = from
        self.to = to
        self.curve = curve
        self.profile = profile
        self.structure = structure
    }

    /// Edge `edge` of `world`, run from its `to` end when `reversed`.
    init?(edge id: TrackEdgeID, reversed: Bool, in world: GameWorld) {
        guard let edge = world.network.edge(id), let from = world.network.node(edge.from), let to = world.network.node(edge.to) else { return nil }
        // A structure the edge's sections were worked out for is
        // `automatic`; the second track asks the ground the same way.
        if reversed {
            let curve: TrackCurve = if case .cubic(let a, let b) = edge.curve { .cubic(b, a) } else { .straight }
            self.init(
                from: to.position, to: from.position, curve: curve,
                profile: TrackProfile(startTransition: edge.profile.endTransition, endTransition: edge.profile.startTransition),
                structure: edge.structure
            )
        } else {
            self.init(from: from.position, to: to.position, curve: edge.curve, profile: edge.profile, structure: edge.structure)
        }
    }
}

/// A platform the second track gets: for `station`, on the second track's
/// `piece`th edge (counted from 0), from `start` to `end` along it.
public struct ChainPlatform: Hashable, Sendable, Codable {
    public let station: StationID
    public let piece: Int
    public let start: Int64
    public let end: Int64

    public init(station: StationID, piece: Int, start: Int64, end: Int64) {
        self.station = station
        self.piece = piece
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey { case station, piece, start, end }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            station: StationID(rawValue: try container.decode(Int.self, forKey: .station)),
            piece: try container.decode(Int.self, forKey: .piece),
            start: try container.decode(Int64.self, forKey: .start), end: try container.decode(Int64.self, forKey: .end)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station.rawValue, forKey: .station)
        try container.encode(piece, forKey: .piece)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}

/// A double-track chain as planned: the command, the world with it built
/// (for pricing, on a ``GameWorld/pricingCopy()``), and what became of
/// its crossovers.
struct DoubleChainPlan {
    let command: PlayerCommand
    let built: GameWorld
    let outcome: DoubleTrack.CrossoverOutcome
    /// The second track and the crossovers, for drawing.
    let parallelPoints: [WorldCoordinate]
    let crossoverPoints: [[WorldCoordinate]]
}

extension DoubleTrack {
    /// How far apart the places a crossover is tried at lie, moving in
    /// from the chain's end, and how many are tried: 8 m, up to 40.
    static let crossoverStep: Int64 = 8 * WorldCoordinate.unitsPerMetre
    static let crossoverTries = 40
}

extension GameSession {
    /// The second track beside `segments`, on `side` of the way they run,
    /// ``DoubleTrack/spacing`` from them: one stretch for each segment, the
    /// first and last joining a node within ``DoubleTrack/joinReach`` of
    /// their place; `nil` when a piece cannot be laid.
    func parallelChain(beside segments: [ChainSegment], side: PlatformTrackSide, in world: GameWorld) -> [PlayerCommand.TrackStretch]? {
        guard !segments.isEmpty else { return nil }
        var geometries: [TrackGeometry] = []
        for segment in segments {
            guard let geometry = segment.geometry else { return nil }
            geometries.append(geometry)
        }
        func unit(_ way: PlanVector) -> (x: Double, y: Double) {
            let length = (Double(way.dx) * Double(way.dx) + Double(way.dy) * Double(way.dy)).squareRoot()
            return length > 0 ? (Double(way.dx) / length, Double(way.dy) / length) : (0, 0)
        }
        let count = segments.count
        var places: [(anchor: NetworkAnchor, position: WorldCoordinate)] = []
        for index in 0...count {
            let arriving = index > 0 ? geometries[index - 1].location(at: geometries[index - 1].length).direction : nil
            let leaving = index < count ? geometries[index].location(at: 0).direction : nil
            let position = index < count ? segments[index].from : segments[count - 1].to
            var way = leaving ?? arriving ?? PlanVector(dx: 1, dy: 0)
            var distance = DoubleTrack.spacing
            if let arriving, let leaving {
                // The miter: the two ways' bisector, farther out by
                // 1 / cos of half the bend.
                let a = unit(arriving), b = unit(leaving)
                let sum = (x: a.x + b.x, y: a.y + b.y)
                let half = (sum.x * sum.x + sum.y * sum.y).squareRoot() / 2
                guard half > 0.5 else { return nil }
                way = PlanVector(dx: Int64((sum.x * 1_048_576).rounded()), dy: Int64((sum.y * 1_048_576).rounded()))
                distance = Int64((Double(DoubleTrack.spacing) / half).rounded())
            }
            let beside = DoubleTrack.beside(position, way: way, side: side, distance: distance)
            if index == 0 || index == count, let found = world.trackNode(near: beside.plan, within: DoubleTrack.joinReach) {
                places.append((.node(found.id), found.position))
            } else {
                places.append((.point(beside.plan), beside))
            }
        }
        var stretches: [PlayerCommand.TrackStretch] = []
        for index in 0..<count {
            let leaving = geometries[index].location(at: 0).direction
            let arriving = geometries[index].location(at: geometries[index].length).direction
            let from = places[index].position, to = places[index + 1].position
            guard from.plan != to.plan else { return nil }
            let curve: TrackCurve
            if case .straight = segments[index].curve, leaving == arriving,
               (to.x - from.x) * leaving.dy == (to.y - from.y) * leaving.dx {
                curve = .straight
            } else {
                guard let found = NetworkBuilding.curve(from: from.plan, leaving: leaving, to: to.plan, leaving: arriving.reversed) else { return nil }
                curve = found
            }
            let profile = segments[index].profile
            guard let geometry = TrackGeometry(from: from, to: to, curve: curve, profile: profile) else { return nil }
            stretches.append(PlayerCommand.TrackStretch(
                start: places[index].anchor, end: places[index + 1].anchor, from: from, to: to, curve: curve, profile: profile,
                structure: segments[index].structure, ground: [from.plan, to.plan] + NetworkBuilding.surveyedPoints(of: geometry)
            ))
        }
        return stretches
    }

    /// Plans the double-track chain on a pricing copy of `world`: `main`
    /// built first (a chain, as a traced stretch is), or none for track
    /// already there (`run`, the edges it runs along and whether each is
    /// run backward), then `parallel`, then `platforms`, then a crossover
    /// at each end the second track does not join and `wantsCrossover`
    /// says joins track. Throws what GameCore refused.
    func planDoubleChain(
        main: [PlayerCommand.TrackStretch], run: [(edge: TrackEdgeID, reversed: Bool)], parallel: [PlayerCommand.TrackStretch],
        platforms: [ChainPlatform], wantsCrossover: (start: Bool, end: Bool), in world: GameWorld
    ) throws(GameError) -> DoubleChainPlan {
        var draft = world.pricingCopy()
        let built = try buildDoubleChain(main: main, parallel: parallel, platforms: platforms, in: &draft)
        let mainRun = main.isEmpty ? run : built.main.map { (edge: $0, reversed: false) }
        let atStart = wantsCrossover.start && !(parallel.first?.start.isNode ?? true)
        let atEnd = wantsCrossover.end && !(parallel.last?.end.isNode ?? true)
        let found = chainCrossovers(
            main: mainRun, parallel: built.parallel.map { (edge: $0, reversed: false) }, atStart: atStart, atEnd: atEnd, in: &draft
        )
        let points = parallel.flatMap(\.geometryPoints)
        return DoubleChainPlan(
            command: .buildDoubleTrackChain(main: main, parallel: parallel, platforms: platforms, crossovers: found.stretches),
            built: draft, outcome: found.outcome, parallelPoints: points, crossoverPoints: found.stretches.map(\.geometryPoints)
        )
    }

    /// Builds a double-track chain's track and platforms in `world` (not
    /// its crossovers): the edges of the main chain and of the second
    /// track, in order.
    func buildDoubleChain(
        main: [PlayerCommand.TrackStretch], parallel: [PlayerCommand.TrackStretch], platforms: [ChainPlatform], in world: inout GameWorld
    ) throws(GameError) -> (main: [TrackEdgeID], parallel: [TrackEdgeID], last: (edge: TrackEdgeID, to: TrackNodeID)?) {
        func chain(_ stretches: [PlayerCommand.TrackStretch]) throws(GameError) -> (edges: [TrackEdgeID], last: (edge: TrackEdgeID, to: TrackNodeID)?) {
            var previous: TrackNodeID?
            var edges: [TrackEdgeID] = []
            var last: (edge: TrackEdgeID, to: TrackNodeID)?
            for stretch in stretches {
                let built = try stretch.starting(at: previous).build(in: &world, heights: heights)
                edges.append(built.edge)
                previous = built.to
                last = built
            }
            return (edges, last)
        }
        guard !parallel.isEmpty else { throw .invalidTrackGeometry }
        let first = try chain(main)
        let second = try chain(parallel)
        for platform in platforms {
            guard second.edges.indices.contains(platform.piece) else { throw .invalidTrackGeometry }
            try world.addTrackPlatform(platform.station, on: second.edges[platform.piece], from: platform.start, to: platform.end)
        }
        return (first.edges, second.edges, first.last)
    }

    /// The crossovers from the second track (`parallel`) over to the chain
    /// (`main`), each a list of edges in the way they run: at the start
    /// and the end, each as near the end as GameCore builds one, trying
    /// places ``DoubleTrack/crossoverStep`` apart moving in, each first
    /// ``DoubleTrack/crossoverMargin`` in from the end (so a turnout, a
    /// platform, a vertical curve or a slope too steep near the end only
    /// moves it in). Built in `world` as they are found.
    func chainCrossovers(
        main: [(edge: TrackEdgeID, reversed: Bool)], parallel: [(edge: TrackEdgeID, reversed: Bool)],
        atStart: Bool, atEnd: Bool, in world: inout GameWorld
    ) -> (stretches: [PlayerCommand.TrackStretch], outcome: DoubleTrack.CrossoverOutcome) {
        guard atStart || atEnd else { return ([], .none) }
        // The chains' geometry before any split: a split keeps the way, so
        // a place found on it is found again on the parts.
        func pieces(_ run: [(edge: TrackEdgeID, reversed: Bool)]) -> [(geometry: TrackGeometry, reversed: Bool)] {
            run.compactMap { piece in world.trackGeometry(of: piece.edge).map { ($0, piece.reversed) } }
        }
        let first = pieces(main), second = pieces(parallel)
        guard first.count == main.count, second.count == parallel.count else { return ([], .noRoom) }
        func length(_ chain: [(geometry: TrackGeometry, reversed: Bool)]) -> Int64 { chain.reduce(0) { $0 + $1.geometry.length } }
        func position(_ chain: [(geometry: TrackGeometry, reversed: Bool)], at distance: Int64) -> WorldCoordinate? {
            var left = distance
            for piece in chain {
                if left <= piece.geometry.length {
                    return piece.geometry.location(at: piece.reversed ? piece.geometry.length - left : left).position
                }
                left -= piece.geometry.length
            }
            return nil
        }
        let mainLength = length(first), parallelLength = length(second)
        let reach = DoubleTrack.crossoverReach, margin = DoubleTrack.crossoverMargin
        var stretches: [PlayerCommand.TrackStretch] = []
        var wanted = 0
        for fromStart in [true, false] where fromStart ? atStart : atEnd {
            wanted += 1
            for step in 0..<DoubleTrack.crossoverTries {
                let inward = margin + Int64(step) * DoubleTrack.crossoverStep
                // Each end's crossover keeps to its own half.
                guard inward + reach <= min(mainLength, parallelLength) / 2 else { break }
                let onMain = fromStart ? inward : mainLength - inward
                let onParallel = fromStart ? inward + reach : parallelLength - inward - reach
                guard let to = position(first, at: onMain), let from = position(second, at: onParallel),
                      let stretch = crossoverStretch(from: from, to: to, in: world) else { continue }
                var trial = world
                guard (try? stretch.build(in: &trial, heights: heights)) != nil else { continue }
                world = trial
                stretches.append(stretch)
                break
            }
        }
        return (stretches, stretches.count == wanted ? .built(wanted) : .noRoom)
    }
}
