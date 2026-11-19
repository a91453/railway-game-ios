import GameCore

// Decision 887 (GRADE-CROSSING-TOOL): a stretch of track drawn across the
// company's track at one level crosses it on the flat, as a diamond, instead
// of being refused for want of 8 m between them. GameCore has had diamonds
// since Stage S1 (decisions 26 and 29): a node where four edges end, each
// joining only the one that leaves the node the opposite way, so trains go
// only straight across; reservation, approach locking and the deadlock
// dispatcher already treat the node as the one place both lines share
// (`RouteReservation.isFoulingEnd`). Only a way to draw one was missing,
// short of the X crossover's middle (NetworkCrossover.swift).
//
// The stretch is laid as a chain (``PlayerCommand/buildTrackChain(_:)``):
// cut where it meets each track it is refused for, its piece ending on that
// track (``NetworkAnchor/track(_:)``, which splits it there) and the next
// piece going on from the node. A cubic is cut by de Casteljau's rule, so
// the two pieces leave the node in opposite directions and join each
// other, and the two halves of the crossed track do too: a diamond, not a
// junction. No reference has a tool for it (the reference's `canTurn` only
// reads crossings from OSM): this is the game's own.

/// Where a stretch meets a track it crosses.
struct NetworkDiamondCut: Hashable, Sendable {
    /// The stretch's curve parameter there, 0 at its start, 1 at its end.
    let parameter: Double
    /// The place on the crossed track.
    let place: NetworkEdgePoint
    /// The crossing point, at the crossed track's height there.
    let position: WorldCoordinate
}

enum NetworkDiamond {
    /// The steepest angle two tracks may cross at, as the sine: 1 in 4,
    /// some 14.5°. Real diamonds on main lines are seldom flatter than 1 in
    /// 8, but a game's tracks are drawn by finger; flatter than this, the
    /// crossing's frog would run longer than the 22 m the tool keeps clear
    /// of other switches (``NetworkBuilding/minimumSpacing``).
    static let minimumSine = 0.25

    /// The most tracks one stretch crosses on the flat: a double line and
    /// a siding beside it, twice over.
    static let maximumCrossings = 6

    /// `stretch` as a chain crossing each track of the company's it meets
    /// at one level on the flat, built in `world` (a copy, which this
    /// changes); `nil` unless GameCore refuses `stretch` for crossing
    /// track (``GameError/trackConflict(_:)``) and every such track can be
    /// crossed on the flat: across it at 1 in 4 or more, 22 m from its
    /// ends and the stretch's own, on no platform, and the chain then built
    /// as diamonds.
    static func chain(
        for stretch: PlayerCommand.TrackStretch, in world: inout GameWorld, heights: HeightGrid?
    ) -> (pieces: [PlayerCommand.TrackStretch], nodes: [TrackNodeID])? {
        let start = world
        var pieces = [stretch]
        for _ in 0...maximumCrossings {
            var draft = start
            var previous: TrackNodeID?
            var ends: [TrackNodeID] = []
            var crossed: (index: Int, edge: TrackEdgeID)?
            for (index, piece) in pieces.enumerated() {
                do throws(GameError) {
                    previous = try piece.starting(at: previous).build(in: &draft, heights: heights).to
                    if let previous { ends.append(previous) }
                } catch {
                    guard case .trackConflict(let edge) = error, pieces.count <= maximumCrossings else { return nil }
                    crossed = (index, edge)
                    break
                }
            }
            guard let crossed else {
                // Every piece built: each crossing is a diamond, or none of it.
                guard pieces.count > 1 else { return nil }
                let nodes = Array(ends.dropLast())
                guard nodes.allSatisfy({ isDiamond($0, in: draft) }) else { return nil }
                world = draft
                return (pieces, nodes)
            }
            // Cut the refused piece where it meets the track, on the world
            // as it stood before that piece.
            var before = start
            var node: TrackNodeID?
            for piece in pieces[..<crossed.index] {
                guard let built = try? piece.starting(at: node).build(in: &before, heights: heights) else { return nil }
                node = built.to
            }
            let piece = pieces[crossed.index]
            let from = node.flatMap { before.network.node($0)?.position } ?? piece.from
            guard let cut = cut(of: piece, from: from, afterADiamond: crossed.index > 0, across: crossed.edge, in: before) else { return nil }
            let (first, second) = piece.cut(cut, from: from)
            pieces.replaceSubrange(crossed.index...crossed.index, with: [first, second])
        }
        return nil
    }

    /// Where `piece` (from `from`) crosses edge `edge` of `world`, if it
    /// may cross there on the flat. A piece going on from a diamond of its
    /// own chain (`afterADiamond`) may cross the next track 4 m on, as a
    /// double line's two diamonds lie; 22 m from any other end.
    static func cut(
        of piece: PlayerCommand.TrackStretch, from: WorldCoordinate, afterADiamond: Bool, across edge: TrackEdgeID, in world: GameWorld
    ) -> NetworkDiamondCut? {
        guard let track = world.trackGeometry(of: edge), let crossedEdge = world.network.edge(edge),
              world.network.platforms(on: edge).isEmpty else { return nil }
        let samples = 64
        let way = (0...samples).map { point(of: piece, from: from, at: Double($0) / Double(samples)) }
        let length = zip(way, way.dropFirst()).reduce(0.0) { $0 + distance($1.0, $1.1) }
        let minimum = Double(NetworkBuilding.minimumSpacing)
        var found: NetworkDiamondCut?
        var along = 0.0
        for index in 0..<samples {
            let a = way[index], b = way[index + 1]
            let step = distance(a, b)
            defer { along += step }
            for segment in track.points.indices.dropLast() {
                let c = track.points[segment], d = track.points[segment + 1]
                let cx = Double(c.x), cy = Double(c.y)
                let r = (x: b.x - a.x, y: b.y - a.y)
                let s = (x: Double(d.x) - cx, y: Double(d.y) - cy)
                let denominator = r.x * s.y - r.y * s.x
                let rs = (r.x * r.x + r.y * r.y).squareRoot() * (s.x * s.x + s.y * s.y).squareRoot()
                guard rs > 0, abs(denominator) >= minimumSine * rs else {
                    // Parallel, or too flat a crossing where they do meet.
                    if rs > 0, abs(denominator) > 0 { if meets(a, b, c, d) { return nil } }
                    continue
                }
                let u = ((cx - a.x) * s.y - (cy - a.y) * s.x) / denominator
                let v = ((cx - a.x) * r.y - (cy - a.y) * r.x) / denominator
                guard (0...1).contains(u), (0...1).contains(v) else { continue }
                let start = Double(track.distances[segment]), end = Double(track.distances[segment + 1])
                let chainage = Int64((start + v * (end - start)).rounded())
                let onPiece = along + u * step
                guard found == nil else { continue }
                guard Double(chainage) >= minimum, Double(crossedEdge.length - chainage) >= minimum,
                      onPiece >= (afterADiamond ? Double(4 * WorldCoordinate.unitsPerMetre) : minimum), length - onPiece >= minimum else { return nil }
                let x = Int64((cx + v * s.x).rounded()), y = Int64((cy + v * s.y).rounded())
                found = NetworkDiamondCut(
                    parameter: (Double(index) + u) / Double(samples), place: NetworkEdgePoint(edge: edge, distance: chainage),
                    position: WorldCoordinate(x: x, y: y, z: track.height(at: chainage))
                )
            }
        }
        return found
    }

    /// Whether node `id` is a diamond: four edges end there and each
    /// joins only one other.
    static func isDiamond(_ id: TrackNodeID, in world: GameWorld) -> Bool {
        guard let node = world.network.node(id) else { return false }
        return node.ends.count == 4 && node.ends.allSatisfy { $0.exits.count == 1 }
    }

    private static func point(of piece: PlayerCommand.TrackStretch, from: WorldCoordinate, at t: Double) -> (x: Double, y: Double) {
        let p0 = (x: Double(from.x), y: Double(from.y)), p3 = (x: Double(piece.to.x), y: Double(piece.to.y))
        switch piece.curve {
        case .straight:
            return (p0.x + t * (p3.x - p0.x), p0.y + t * (p3.y - p0.y))
        case .cubic(let c1, let c2):
            let p1 = (x: Double(c1.x), y: Double(c1.y)), p2 = (x: Double(c2.x), y: Double(c2.y))
            let m = 1 - t
            let a = m * m * m, b = 3 * m * m * t, c = 3 * m * t * t, d = t * t * t
            return (a * p0.x + b * p1.x + c * p2.x + d * p3.x, a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
    }

    private static func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }

    /// Whether segment `a`–`b` meets segment `c`–`d` (not parallel).
    private static func meets(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ c: WorldCoordinate, _ d: WorldCoordinate) -> Bool {
        let r = (x: b.x - a.x, y: b.y - a.y), s = (x: Double(d.x - c.x), y: Double(d.y - c.y))
        let denominator = r.x * s.y - r.y * s.x
        let u = ((Double(c.x) - a.x) * s.y - (Double(c.y) - a.y) * s.x) / denominator
        let v = ((Double(c.x) - a.x) * r.y - (Double(c.y) - a.y) * r.x) / denominator
        return (0...1).contains(u) && (0...1).contains(v)
    }
}

extension PlayerCommand.TrackStretch {
    /// It cut at `cut` (``NetworkDiamond/chain(for:in:heights:)``), from
    /// `from` (where the piece before it ended): a piece ending on the
    /// crossed track there, and one going on from the node to its end.
    /// Each keeps the vertical curve at its own outer end, as
    /// `GameWorld.splitTrackEdge(_:at:)` keeps an edge's.
    func cut(_ cut: NetworkDiamondCut, from: WorldCoordinate) -> (PlayerCommand.TrackStretch, PlayerCommand.TrackStretch) {
        let middle = cut.position
        let curves: (TrackCurve, TrackCurve)
        switch curve {
        case .straight:
            curves = (.straight, .straight)
        case .cubic(let c1, let c2):
            // De Casteljau: the first piece's second control point and the
            // second's first lie on one line through the cut, so the
            // pieces leave it in opposite directions.
            let t = cut.parameter
            func lerp(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) { (a.0 + t * (b.0 - a.0), a.1 + t * (b.1 - a.1)) }
            let p0 = (Double(from.x), Double(from.y)), p1 = (Double(c1.x), Double(c1.y))
            let p2 = (Double(c2.x), Double(c2.y)), p3 = (Double(to.x), Double(to.y))
            let p01 = lerp(p0, p1), p12 = lerp(p1, p2), p23 = lerp(p2, p3)
            let p012 = lerp(p01, p12), p123 = lerp(p12, p23)
            func plan(_ p: (Double, Double)) -> PlanPoint { PlanPoint(x: Int64(p.0.rounded()), y: Int64(p.1.rounded())) }
            curves = (.cubic(plan(p01), plan(p012)), .cubic(plan(p123), plan(p23)))
        }
        let first = PlayerCommand.TrackStretch(
            start: start, end: .track(cut.place), from: from, to: middle, curve: curves.0,
            profile: from.z == middle.z ? .uniform : TrackProfile(startTransition: profile.startTransition),
            structure: structure, ground: ground, mountain: mountain
        )
        let second = PlayerCommand.TrackStretch(
            start: .track(cut.place), end: end, from: middle, to: to, curve: curves.1,
            profile: middle.z == to.z ? .uniform : TrackProfile(endTransition: profile.endTransition),
            structure: structure, ground: [middle.plan, to.plan], mountain: mountain
        )
        return (first, second)
    }
}
