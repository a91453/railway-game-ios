import GameCore

// A second track beside a chain of edges (ARCHITECTURE decision 247): the
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
    /// their place, across and in height (decision 401's sequel: a node of
    /// a track on another level, under or over it, is not joined); `nil`
    /// when a piece cannot be laid.
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
            if index == 0 || index == count, let found = world.trackNode(at: beside, within: DoubleTrack.joinReach) {
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
            } else if case .cubic(let c1, let c2) = segments[index].curve {
                // The chain's own curve moved out by the spacing, each
                // control point beside its end: a new curve fitted to the
                // ends' directions alone bends differently along a long
                // traced edge and comes closer than the spacing midway.
                // The miter at a node lies along the edge from the plain
                // offset, so the curve still leaves and arrives along it.
                func beside(_ point: PlanPoint, _ way: PlanVector) -> PlanPoint {
                    DoubleTrack.beside(WorldCoordinate(x: point.x, y: point.y, z: 0), way: way, side: side, distance: DoubleTrack.spacing).plan
                }
                curve = .cubic(beside(c1, leaving), beside(c2, arriving))
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
                // Decision 378: a place where either track would not be cut
                // (a train or a line on it, a platform there) is passed by
                // before cutting the second track, which on a long one
                // works its fouling out again: a run of such places held
                // the preview most of a second. Building it would have been
                // refused the same way, so the same place is found.
                guard ![stretch.start, stretch.end].contains(where: { anchor in
                    if case .track(let point) = anchor { world.trackEdgeSplitRefusal(point.edge, at: point.distance) != nil } else { false }
                }) else { continue }
                crossoverTrials += 1
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

/// A piece of a chain's segment the second track runs beside
/// (``GameSession/offsetPieces(of:side:keepWhole:)``): the whole segment,
/// or part of a long curve.
struct OffsetPiece {
    let segment: ChainSegment
    /// Which of the chain's segments it is part of.
    let index: Int
    /// Where along that segment it starts and ends.
    let start: Int64
    let end: Int64
}

extension DoubleTrack {
    /// How far the second track beside a curve, its control points moved
    /// out by ``spacing``, may stray from the spacing before the curve is
    /// halved for it (decision 378): 0.5 m, so it stays well clear of the
    /// 4 m the network keeps and is still found beside it.
    static let offsetTolerance: Int64 = WorldCoordinate.unitsPerMetre / 2
    /// How many times a curve is halved at most: into 16 pieces.
    static let offsetHalvings = 4
}

extension GameSession {
    /// `segments` in pieces for the second track beside them on `side`
    /// (decision 378): a curve's control points moved out by the spacing
    /// make a curve that strays from it along a long one with a sharp turn
    /// (lesson 5's track to the third town came within 3.8 m and was
    /// refused), so such a curve is halved, each half its own cubic, until
    /// no piece strays more than ``DoubleTrack/offsetTolerance``. A
    /// straight segment, one whose second track keeps the spacing, and one
    /// that cannot be cut cleanly stay whole, as before. Never cut inside
    /// `keepWhole[i]` (stretches along segment `i`, its platforms).
    func offsetPieces(of segments: [ChainSegment], side: PlatformTrackSide, keepWhole: [[ClosedRange<Int64>]] = []) -> [OffsetPiece] {
        segments.enumerated().flatMap { index, segment in
            let whole = [OffsetPiece(segment: segment, index: index, start: 0, end: segment.geometry?.length ?? 0)]
            guard case .cubic(let c1, let c2) = segment.curve, let geometry = segment.geometry, geometry.length > 0 else { return whole }
            let curve = OffsetCubic(segment.from.plan, c1, c2, segment.to.plan)
            let keep = index < keepWhole.count ? keepWhole[index] : []
            // Where along the segment parameter `t` lies: its samples are
            // evenly apart in `t`.
            let steps = Double(geometry.distances.count - 1)
            func chainage(_ t: Double) -> Int64 { geometry.distances[Int((t * steps).rounded())] }
            func parameter(_ distance: Int64) -> Double {
                var (low, high) = (0, geometry.distances.count - 1)
                while low < high {
                    let middle = (low + high) / 2
                    if geometry.distances[middle] < distance { low = middle + 1 } else { high = middle }
                }
                return Double(low) / steps
            }
            func cuts(_ a: Double, _ b: Double, depth: Int) -> [Double] {
                guard depth < DoubleTrack.offsetHalvings, curve.part(a, b).strays(side: side) > Double(DoubleTrack.offsetTolerance) else { return [] }
                var middle = (a + b) / 2
                // Off a platform, 8 m past its nearer end, when that is still
                // well inside the part.
                if let platform = keep.first(where: { $0.contains(chainage(middle)) }) {
                    let ends = [parameter(platform.lowerBound - DoubleTrack.crossoverStep), parameter(platform.upperBound + DoubleTrack.crossoverStep)]
                    guard let end = ends.filter({ $0 > a + (b - a) / 4 && $0 < b - (b - a) / 4 }).min(by: { abs($0 - middle) < abs($1 - middle) })
                    else { return [] }
                    middle = end
                }
                return cuts(a, middle, depth: depth + 1) + [middle] + cuts(middle, b, depth: depth + 1)
            }
            let inner = cuts(0, 1, depth: 0)
            guard !inner.isEmpty else { return whole }
            let bounds = [0.0] + inner + [1.0]
            var pieces: [OffsetPiece] = []
            for part in 0..<(bounds.count - 1) {
                let (a, b) = (bounds[part], bounds[part + 1])
                let cubic = curve.part(a, b).rounded
                let first = part == 0, last = part == bounds.count - 2
                let start = first ? 0 : chainage(a), end = last ? geometry.length : chainage(b)
                let from = first ? segment.from : WorldCoordinate(x: cubic.p0.x, y: cubic.p0.y, z: geometry.location(at: start).position.z)
                let to = last ? segment.to : WorldCoordinate(x: cubic.p3.x, y: cubic.p3.y, z: geometry.location(at: end).position.z)
                let piece = ChainSegment(
                    from: from, to: to, curve: .cubic(cubic.c1, cubic.c2),
                    profile: TrackProfile(startTransition: first ? segment.profile.startTransition : 0, endTransition: last ? segment.profile.endTransition : 0),
                    structure: segment.structure
                )
                guard start < end, piece.geometry != nil else { return whole }
                pieces.append(OffsetPiece(segment: piece, index: index, start: start, end: end))
            }
            return pieces
        }
    }
}

/// A cubic Bézier in plan, in floating point, for working out where to
/// cut a curve (``GameSession/offsetPieces(of:side:keepWhole:)``).
private struct OffsetCubic {
    typealias Point = (x: Double, y: Double)
    let p: [Point]

    init(_ p0: PlanPoint, _ c1: PlanPoint, _ c2: PlanPoint, _ p3: PlanPoint) {
        p = [p0, c1, c2, p3].map { (Double($0.x), Double($0.y)) }
    }

    private init(_ points: [Point]) {
        p = points
    }

    private static func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point {
        (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    /// Where it is at `t` (de Casteljau), and its halves there.
    private func split(_ t: Double) -> (OffsetCubic, OffsetCubic) {
        let a = Self.lerp(p[0], p[1], t), b = Self.lerp(p[1], p[2], t), c = Self.lerp(p[2], p[3], t)
        let ab = Self.lerp(a, b, t), bc = Self.lerp(b, c, t), m = Self.lerp(ab, bc, t)
        return (OffsetCubic([p[0], a, ab, m]), OffsetCubic([m, bc, c, p[3]]))
    }

    /// The same curve from `a` to `b` (0 ≤ a < b ≤ 1).
    func part(_ a: Double, _ b: Double) -> OffsetCubic {
        let left = b < 1 ? split(b).0 : self
        return a > 0 ? left.split(a / b).1 : left
    }

    var rounded: (p0: PlanPoint, c1: PlanPoint, c2: PlanPoint, p3: PlanPoint) {
        let q = p.map { PlanPoint(x: Int64($0.x.rounded()), y: Int64($0.y.rounded())) }
        return (q[0], q[1], q[2], q[3])
    }

    private func point(_ t: Double, of q: [Point]) -> Point {
        let u = 1 - t
        let (w0, w1, w2, w3) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
        return (w0 * q[0].x + w1 * q[1].x + w2 * q[2].x + w3 * q[3].x, w0 * q[0].y + w1 * q[1].y + w2 * q[2].y + w3 * q[3].y)
    }

    private func tangent(_ t: Double) -> Point {
        let u = 1 - t
        let (w0, w1, w2) = (3 * u * u, 6 * u * t, 3 * t * t)
        return (w0 * (p[1].x - p[0].x) + w1 * (p[2].x - p[1].x) + w2 * (p[3].x - p[2].x),
                w0 * (p[1].y - p[0].y) + w1 * (p[2].y - p[1].y) + w2 * (p[3].y - p[2].y))
    }

    private func bend(_ t: Double) -> Point {
        let u = 1 - t
        return (6 * (u * (p[2].x - 2 * p[1].x + p[0].x) + t * (p[3].x - 2 * p[2].x + p[1].x)),
                6 * (u * (p[2].y - 2 * p[1].y + p[0].y) + t * (p[3].y - 2 * p[2].y + p[1].y)))
    }

    /// How far, at most, the curve beside it on `side` that
    /// ``GameSession/parallelChain(beside:side:in:)`` lays (each control
    /// point moved out by the spacing beside its end) strays from the
    /// spacing: looked at 15 places along it, each against the nearest
    /// point of this curve.
    func strays(side: PlatformTrackSide) -> Double {
        let spacing = Double(DoubleTrack.spacing)
        func out(_ way: Point) -> Point {
            let length = (way.x * way.x + way.y * way.y).squareRoot()
            guard length > 0 else { return (0, 0) }
            let scale = (side == .left ? 1 : -1) * spacing / length
            return (way.y * scale, -way.x * scale)
        }
        let start = out((p[1].x - p[0].x, p[1].y - p[0].y)), end = out((p[3].x - p[2].x, p[3].y - p[2].y))
        let beside: [Point] = [
            (p[0].x + start.x, p[0].y + start.y), (p[1].x + start.x, p[1].y + start.y),
            (p[2].x + end.x, p[2].y + end.y), (p[3].x + end.x, p[3].y + end.y),
        ]
        var most = 0.0
        for step in 1..<16 {
            let t = Double(step) / 16
            let o = point(t, of: beside)
            // The nearest point of this curve, by Newton's method from `t`.
            var s = t
            for _ in 0..<6 {
                let q = point(s, of: p), d = tangent(s), dd = bend(s)
                let (rx, ry) = (q.x - o.x, q.y - o.y)
                let slope = d.x * d.x + d.y * d.y + rx * dd.x + ry * dd.y
                guard slope > 0 else { break }
                s = min(1, max(0, s - (rx * d.x + ry * d.y) / slope))
            }
            let q = point(s, of: p)
            let distance = ((q.x - o.x) * (q.x - o.x) + (q.y - o.y) * (q.y - o.y)).squareRoot()
            most = max(most, abs(distance - spacing))
        }
        return most
    }
}
