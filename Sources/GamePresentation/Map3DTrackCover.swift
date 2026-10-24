import GameCore

/// Decision 359: the player's track in a scene's space, where it runs in a
/// tunnel, and the ground the scene draws over or under it.
///
/// The scene draws nothing of a tunnel (no bed, rails, walls or roof), so a
/// train in one stood on nothing, and where the tunnel is shallow (near a
/// portal, or a tunnel the player laid only a few metres down) its roof
/// stood out of the ground. Its cars are not drawn there, as the real
/// trains' are not (decision 339), and the camera following it stays over
/// the ground (``Map3DFollow``), in a tunnel and in a cutting the 64 m
/// ground squares cover.
///
/// All of the network's track, not only the scene's region's: a train
/// is drawn wherever it runs, and a streamed chunk (decision 358) has no
/// scene of its own.
public struct Map3DTrackCover: Sendable {
    /// A piece of track between two samples of its centre line, at the
    /// rails' height (``Map3DScene/railLift`` over the track's), with the
    /// drawn ground at both ends. `opensBefore` and `opensAfter` mark an
    /// end where what carries it changes (at a portal) or the track ends:
    /// nothing past it is on this piece.
    struct Piece: Sendable {
        let a: Map3DPoint
        let b: Map3DPoint
        let groundA: Float
        let groundB: Float
        let opensBefore: Bool
        let opensAfter: Bool
        let isTunnel: Bool
        /// Decision 391: on a viaduct or bridge, which a road may pass
        /// under.
        var isViaduct = false
    }

    let pieces: [Piece]
    /// The pieces by the ``cell`` squares their boxes touch.
    let cells: [Map3DScene.ChunkKey: [Int]]
    /// Decision 375: the trenches of the track below the drawn ground.
    let trenches: Map3DTrenches
    /// Decision 394: where each tunnel opens to the open air, on the rails
    /// (``Map3DScene/Builder/portalEnds(_:)``), for the cab view in a
    /// tunnel (``Map3DUnderground``).
    public let openings: [Map3DPoint]

    /// The squares the pieces are found by, in metres.
    static let cell: Float = 32
    /// How far from the centre line, seen from above, a point on the rails
    /// is on it, in metres: under half a track's spacing (4 m), so a
    /// surface track beside a portal is not in the tunnel.
    static let reach: Float = 1.5
    /// How far above or below the tunnel's rails a point is still on them,
    /// in metres: under the 8 m two tracks crossing stand apart
    /// (``TrackStructure/clearance``).
    static let rise: Float = 2

    /// No track.
    public init() {
        pieces = []
        cells = [:]
        trenches = Map3DTrenches()
        openings = []
    }

    /// `snapshot`'s track, laid out as `builder` lays it.
    init(_ snapshot: RailwaySnapshot, builder: inout Map3DScene.Builder) {
        var pieces: [Piece] = []
        let portals = Set(snapshot.nodes.filter(\.isTunnelPortal).map(\.id))
        var trenchLines: [(line: [Map3DPoint], runs: [ClosedRange<Int>], opens: (first: Bool, last: Bool))] = []
        for alignment in snapshot.edges {
            let spans = alignment.edge.sectionSpans
            for (number, span) in spans.enumerated() where span.end > span.start {
                let line = builder.sample(alignment.geometry, from: span.start, to: span.end).map { builder.point($0) + Map3DScene.Builder.lifted }
                guard line.count > 1 else { continue }
                var grounds = line.map { builder.drawnGround(x: $0.x, z: $0.z) }
                // Decision 375: where the track runs in a trench, its
                // floor is the ground the camera stays over.
                if span.kind != .tunnel {
                    let runs = Self.trenchRuns(line, grounds: grounds)
                    if !runs.isEmpty {
                        // Where it opens into a tunnel, as `portalEnds` finds.
                        let first = number == 0 ? portals.contains(alignment.edge.from) : spans[number - 1].kind == .tunnel
                        let last = number == spans.count - 1 ? portals.contains(alignment.edge.to) : spans[number + 1].kind == .tunnel
                        trenchLines.append((line, runs, (first, last)))
                        for run in runs {
                            for index in run { grounds[index] = min(grounds[index], line[index].y - Map3DScene.Builder.bedDrop) }
                        }
                    }
                }
                for index in 1..<line.count {
                    pieces.append(Piece(a: line[index - 1], b: line[index], groundA: grounds[index - 1], groundB: grounds[index],
                                        opensBefore: index == 1, opensAfter: index == line.count - 1, isTunnel: span.kind == .tunnel,
                                        isViaduct: span.kind == .viaduct || span.kind == .bridge))
                }
            }
        }
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        for (index, piece) in pieces.enumerated() {
            let pad = Self.reach
            let low = Self.key(x: min(piece.a.x, piece.b.x) - pad, z: min(piece.a.z, piece.b.z) - pad)
            let high = Self.key(x: max(piece.a.x, piece.b.x) + pad, z: max(piece.a.z, piece.b.z) + pad)
            for row in low.row...high.row {
                for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(index) }
            }
        }
        self.pieces = pieces
        self.cells = cells
        trenches = Self.trenches(trenchLines, builder: &builder)
        openings = builder.portalEnds(snapshot).map(\.point)
    }

    static func key(x: Float, z: Float) -> Map3DScene.ChunkKey {
        Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((z / cell).rounded(.down)))
    }

    public var isEmpty: Bool { pieces.isEmpty }

    /// The drawn ground's height at `point` on the rails, in metres, and
    /// whether it is in a tunnel; `nil` if it is on none of the track.
    public func ground(at point: Map3DPoint) -> (height: Float, inTunnel: Bool)? {
        guard let near = cells[Self.key(x: point.x, z: point.z)] else { return nil }
        var best: (distance: Float, ground: Float, inTunnel: Bool)?
        for index in near {
            let piece = pieces[index]
            let along = Map3DPoint(piece.b.x - piece.a.x, 0, piece.b.z - piece.a.z)
            let squared = along.dot(along)
            guard squared > 0 else { continue }
            var share = Map3DPoint(point.x - piece.a.x, 0, point.z - piece.a.z).dot(along) / squared
            // Past an end where it stops is off it; past one where the
            // next piece goes on (the outside of a bend), at it.
            if share < 0 { if piece.opensBefore { continue } else { share = 0 } }
            if share > 1 { if piece.opensAfter { continue } else { share = 1 } }
            let on = piece.a + (piece.b - piece.a) * share
            let distance = Map3DPoint(point.x - on.x, 0, point.z - on.z).length
            guard distance <= Self.reach, abs(point.y - on.y) <= Self.rise else { continue }
            if best.map({ distance < $0.distance }) ?? true {
                best = (distance, piece.groundA + (piece.groundB - piece.groundA) * share, piece.isTunnel)
            }
        }
        return best.map { ($0.ground, $0.inTunnel) }
    }

    /// Whether `point` on the rails is in a tunnel.
    public func isInTunnel(_ point: Map3DPoint) -> Bool {
        ground(at: point)?.inTunnel ?? false
    }
}
