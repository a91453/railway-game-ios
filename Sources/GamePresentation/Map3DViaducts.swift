import Foundation
import GameCore

// Decision 407: the 3D map's viaducts as each kind of railway builds them.
// Before, every viaduct was the owner's site's one (rail-3d
// `rail-structures.js`: a 5 m deck on a 1.8 m girder, a 1.6 × 2.2 m pier
// every 32 m), each track on its own; the bridges only changed colour.
// Now:
//
// - the Taiwan Railway's (and the forest railway's) double-track girder on
//   one wall pier a span under a cap across both tracks, the site's sizes;
// - the High Speed Rail's 13 m box girder, 3.25 m deep, on one tall
//   column every 35 m;
// - a metro's (the Wenhu and Circular Lines', the other metros' and light
//   rails') twin girders on one round column under a T-shaped cap every
//   30 m;
// - a steel truss where the Taiwan Railway crosses a river.
//
// The tracks of a pair are laid one by one, so the viaducts are drawn
// together once all are laid (``Map3DScene/Builder/addViaducts()``): a pier
// of one track with one of the track beside it (as the site's
// `rail-structures.js` finds a parallel track for its parapets: within
// 2–6.5 m across and 10 m along, the same way) stands once, under their
// middle, and a parapet or a truss's side stands only where no track runs
// beside it.

/// Decision 407: the kinds of viaduct.
enum Map3DViaduct: Sendable, Hashable {
    /// The Taiwan Railway's double-track girder.
    case railway
    /// The High Speed Rail's box girder.
    case highSpeed
    /// A metro's or light rail's twin girders.
    case metro

    /// The kind the system with site id `system` (`rail_tracks.json`'s
    /// `systems`) builds.
    init(system: String) {
        switch system {
        case "thsr_sched": self = .highSpeed
        case "tra_sched", "afr_sched": self = .railway
        default: self = .metro
        }
    }

    /// How its pier stands.
    enum Pier: Sendable, Hashable {
        /// A wall `along` thick, `across` wide plus the tracks' spacing,
        /// under a cap `cap` wide plus the spacing (the Taiwan Railway).
        case wall(along: Float, across: Float, cap: Float)
        /// One column `along` by `across` under a head `head` wide (the
        /// High Speed Rail).
        case column(along: Float, across: Float, head: Float)
        /// One round column under a cap `cap` wide plus the spacing (a
        /// metro).
        case round(radius: Float, cap: Float)
    }

    struct Look: Sendable {
        /// The deck each track is laid on, metres across; a pair's
        /// together, apart by their spacing, are the real deck.
        let deckWidth: Float
        /// The slab on top, metres deep.
        let slabDepth: Float
        /// The girder under it, metres across at each track.
        let girderWidth: Float
        /// From the deck's top to the girder's bottom, metres.
        let girderDepth: Float
        /// A pier every `span` metres.
        let span: Float
        let pier: Pier
        /// The cap or head on the pier, metres deep, and along the line.
        let capDepth: Float
        let capAlong: Float
        /// Whether the deck is bare concrete (slab track) or ballasted.
        let ballasted: Bool
    }

    /// Its look; over the water (`kind` ``TrackSectionKind/bridge``) the
    /// railway's is a truss (``Map3DViaduct/truss``).
    func look(over kind: TrackSectionKind = .viaduct) -> Look {
        switch self {
        case .railway where kind == .bridge: Self.truss
        case .railway: Self.railwayLook
        case .highSpeed: Self.highSpeedLook
        case .metro: Self.metroLook
        }
    }

    /// The site's (rail-3d `rail-structures.js`): `DECK_W` 5,
    /// `GIRDER_BOTTOM_W` 2.8, `GIRDER_DEPTH` 1.8, `PIER_ALONG` 1.6,
    /// `PIER_ACROSS` 2.2, `CAP_ACROSS` 5, `CAP_ALONG` 1.6, `CAP_DEPTH` 1.2,
    /// `PIER_M` 32.
    static let railwayLook = Look(deckWidth: 5, slabDepth: 0.5, girderWidth: 2.8, girderDepth: 1.8, span: 32,
                                  pier: .wall(along: 1.6, across: 2.2, cap: 5), capDepth: 1.2, capAlong: 1.6, ballasted: true)
    /// The High Speed Rail's: simple spans of 35 m (and 30 m) of precast
    /// box girders (Fischer et al., "Design Concept for High Speed Railway
    /// Bridges in Regions with High Seismic Activity and Soft Soil", 2001),
    /// 3.25 m deep (contracts C260/C270, Railway Technology); 13 m across
    /// both tracks, 4.5 m apart (estimated: no source found), so 8.5 m at
    /// each; the column and its head estimated from photographs.
    static let highSpeedLook = Look(deckWidth: 8.5, slabDepth: 0.45, girderWidth: 2.6, girderDepth: 3.25, span: 35,
                                    pier: .column(along: 3, across: 4.4, head: 6.4), capDepth: 1.6, capAlong: 3, ballasted: false)
    /// A metro's: twin narrow girders on one column under a T cap, as the
    /// Wenhu and Circular Lines (sizes estimated from photographs: no
    /// source found).
    static let metroLook = Look(deckWidth: 4.4, slabDepth: 0.4, girderWidth: 2.2, girderDepth: 1.8, span: 30,
                                pier: .round(radius: 0.9, cap: 3.6), capDepth: 1.6, capAlong: 2, ballasted: false)
    /// The truss bridge's deck and piers: spans of about 63 m (the old
    /// Lower Tamsui River Bridge's 24 spans over 1,526 m), the deck on
    /// floor beams 1.2 m deep, a wall pier each span.
    static let truss = Look(deckWidth: 5, slabDepth: 0.4, girderWidth: 4.6, girderDepth: 1.2, span: 63,
                            pier: .wall(along: 2.4, across: 3.2, cap: 0), capDepth: 0, capAlong: 0, ballasted: true)
    /// The truss's sides: metres over the rails, out from the track's
    /// middle, between its panel points, and its members' thickness
    /// (estimated: a Warren truss of 8 panels a span).
    static let trussHeight: Float = 6.5
    static let trussOffset: Float = 2.55
    static let trussMember: Float = 0.45
    static let trussPanels = 8
    /// A parapet's height over the deck and its thickness (the site's
    /// `PARAPET_H`, `PARAPET_W`).
    static let parapetHeight: Float = 0.9
    static let parapetWidth: Float = 0.35
    /// The site's `NEIGHBOR_M`, widened for the High Speed Rail's 4.5 m:
    /// a track this far beside another is its pair.
    static let neighbourReach: Float = 7
}

/// Decision 407: the viaducts laid, waiting to be drawn.
struct Map3DViaducts: Sendable {
    struct Piece: Sendable {
        let line: [Map3DPoint]
        let kind: TrackSectionKind
        let viaduct: Map3DViaduct
    }

    struct Pier: Sendable {
        /// On the track's middle, at the girder's bottom.
        let top: Map3DPoint
        let foot: Float
        let forward: Map3DPoint
        let kind: TrackSectionKind
        let viaduct: Map3DViaduct
    }

    var pieces: [Piece] = []
    var piers: [Pier] = []
    /// Where the last piece ended and how far on its next pier stands.
    var last: (end: Map3DPoint, next: Float, kind: TrackSectionKind, viaduct: Map3DViaduct)?

    var isEmpty: Bool { pieces.isEmpty && piers.isEmpty }

    /// Lays `line` (its rails' middle) on its viaduct, and a pier every
    /// span along it where the girder stands over the ground (`grounds`)
    /// by half a metre; the first half a span on, or a span on from the
    /// last pier of the piece it goes on from.
    mutating func add(_ line: [Map3DPoint], grounds: [Float], kind: TrackSectionKind, viaduct: Map3DViaduct) {
        guard line.count > 1 else { return }
        let look = viaduct.look(over: kind)
        pieces.append(Piece(line: line, kind: kind, viaduct: viaduct))
        var travelled: Float = 0
        var next = look.span / 2
        if let last, last.kind == kind, last.viaduct == viaduct, (last.end - line[0]).length < 0.01 { next = last.next }
        for index in 1..<line.count {
            let a = line[index - 1], b = line[index], step = (b - a).length
            guard step > 0 else { continue }
            while next <= travelled + step {
                let share = (next - travelled) / step
                let top = a + (b - a) * share + Map3DPoint(0, -Map3DScene.Builder.bedDrop - look.girderDepth, 0)
                let foot = grounds[index - 1] + (grounds[index] - grounds[index - 1]) * share
                if top.y - foot > 0.5 { piers.append(Pier(top: top, foot: foot, forward: b - a, kind: kind, viaduct: viaduct)) }
                next += look.span
            }
            travelled += step
        }
        last = (line[line.count - 1], next - travelled, kind, viaduct)
    }

    /// The segments of every piece by the 12 m square of their middles
    /// (the site's `CELL`): the piece and the segment's index.
    func segmentCells() -> [Map3DScene.ChunkKey: [(piece: Int, segment: Int)]] {
        var cells: [Map3DScene.ChunkKey: [(piece: Int, segment: Int)]] = [:]
        for (number, piece) in pieces.enumerated() {
            for index in 1..<piece.line.count {
                let middle = (piece.line[index - 1] + piece.line[index]) * 0.5
                cells[Self.cell(middle), default: []].append((number, index))
            }
        }
        return cells
    }

    static func cell(_ p: Map3DPoint) -> Map3DScene.ChunkKey {
        Map3DScene.ChunkKey(column: Int((p.x / 12).rounded(.down)), row: Int((p.z / 12).rounded(.down)))
    }

    /// How far across (along `across`) the nearest track running the same
    /// way within ``Map3DViaduct/neighbourReach`` lies of `middle` on the
    /// side `side` (+1 or −1): the site's `neighbor`. `nil` for none.
    static func neighbour(of middle: Map3DPoint, along forward: Map3DPoint, across: Map3DPoint, side: Float, skipping piece: Int,
                          in pieces: [Piece], cells: [Map3DScene.ChunkKey: [(piece: Int, segment: Int)]]) -> Float? {
        let home = cell(middle)
        var nearest: Float?
        for dc in -1...1 {
            for dr in -1...1 {
                for (other, segment) in cells[Map3DScene.ChunkKey(column: home.column + dc, row: home.row + dr)] ?? [] where other != piece {
                    let a = pieces[other].line[segment - 1], b = pieces[other].line[segment]
                    let offset = (a + b) * 0.5 - middle
                    let lateral = (offset.x * across.x + offset.z * across.z) * side
                    let ahead = offset.x * forward.x + offset.z * forward.z
                    guard lateral >= 2, lateral <= Map3DViaduct.neighbourReach, abs(ahead) <= 10,
                          let way = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized,
                          abs(way.x * forward.x + way.z * forward.z) >= 0.9 else { continue }
                    nearest = min(nearest ?? lateral, lateral)
                }
            }
        }
        return nearest
    }
}

extension Map3DScene.Builder {
    /// Decision 407: the player's track high-speed lines run on.
    mutating func highSpeedTrack() -> Set<TrackEdgeID> {
        if let highSpeedEdges { return highSpeedEdges }
        var edges = Set<TrackEdgeID>()
        for line in world.lines where line.isHighSpeed {
            guard let journey = world.lineJourney(line.id) else { continue }
            for (traversal, _, _) in LineMap.pieces(of: journey, in: world.network) { edges.insert(traversal.edge) }
        }
        highSpeedEdges = edges
        return edges
    }

    /// Decision 407: the viaducts laid since the last call, each on its
    /// girder; their piers, one under each pair; their parapets and a
    /// truss's sides where no track runs beside them.
    mutating func addViaducts() {
        guard !viaducts.isEmpty else { return }
        let laid = viaducts
        viaducts = Map3DViaducts()
        let cells = laid.segmentCells()
        for (number, piece) in laid.pieces.enumerated() {
            let line = piece.line, look = piece.viaduct.look(over: piece.kind)
            let across = Map3DMesh.acrossDirections(line)
            // Which side of each segment has a track beside it, and how far.
            var beside: [[Float?]] = [[], []]
            for index in 1..<line.count {
                let middle = (line[index - 1] + line[index]) * 0.5
                let forward = Map3DPoint(line[index].x - line[index - 1].x, 0, line[index].z - line[index - 1].z).normalized ?? Map3DPoint(1, 0, 0)
                let side = (across[index - 1] + across[index]).normalized ?? across[index]
                for (slot, sign) in [Float(-1), 1].enumerated() {
                    beside[slot].append(Map3DViaducts.neighbour(of: middle, along: forward, across: side, side: sign, skipping: number,
                                                                in: laid.pieces, cells: cells))
                }
            }
            let truss = piece.kind == .bridge && piece.viaduct == .railway
            let concrete = piece.kind == .bridge && !truss ? Map3DPalette.bridge : Map3DPalette.concrete
            mesh(at: line[line.count / 2]) { mesh in
                // The slab (ballasted or bare) and the girder.
                mesh.addRibbon(along: line, width: look.deckWidth, lift: -Self.bedDrop, depth: look.slabDepth,
                               top: look.ballasted ? Map3DPalette.ballast : concrete, side: concrete,
                               topPaint: look.ballasted ? Self.ballast : Self.concrete, sidePaint: Self.concrete)
                mesh.addRibbon(along: line, width: look.girderWidth, lift: -Self.bedDrop - look.slabDepth, depth: look.girderDepth - look.slabDepth,
                               top: concrete, side: concrete, sidePaint: Self.concrete)
                if truss { Self.addTrussChords(&mesh, line: line, across: across, beside: beside) }
            }
            let saved = target
            // The slab track's concrete bed on the deck, near (decision 238).
            if !look.ballasted {
                target = .near
                mesh(at: line[line.count / 2]) { mesh in
                    mesh.addRibbon(along: line, width: 2.6, lift: -0.2, depth: 0.15, top: Map3DPalette.ballast, side: Map3DPalette.ballast)
                }
            }
            // The parapets, or a truss's members, close up.
            target = .wires
            mesh(at: line[line.count / 2]) { mesh in
                if truss {
                    Self.addTrussMembers(&mesh, line: line, across: across, beside: beside, span: look.span)
                } else {
                    for (slot, sign) in [Float(-1), 1].enumerated() {
                        for run in Self.runs(of: line, where: beside[slot].map { $0 == nil }) {
                            mesh.addRibbon(along: run, width: Map3DViaduct.parapetWidth,
                                           offset: sign * (look.deckWidth - Map3DViaduct.parapetWidth) / 2,
                                           lift: -Self.bedDrop + Map3DViaduct.parapetHeight, depth: Map3DViaduct.parapetHeight,
                                           top: concrete, side: concrete)
                        }
                    }
                }
            }
            target = saved
        }
        addPiers(laid.piers)
    }

    /// `line`'s stretches whose segments `keep` (one for each), each of
    /// at least one segment.
    static func runs(of line: [Map3DPoint], where keep: [Bool]) -> [[Map3DPoint]] {
        var runs: [[Map3DPoint]] = []
        var current: [Map3DPoint] = []
        for index in 1..<line.count {
            if keep[index - 1] {
                if current.isEmpty { current.append(line[index - 1]) }
                current.append(line[index])
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// The truss's top chords, seen from afar: one each side with no
    /// track beside it, ``Map3DViaduct/trussHeight`` over the rails.
    static func addTrussChords(_ mesh: inout Map3DMesh, line: [Map3DPoint], across: [Map3DPoint], beside: [[Float?]]) {
        let member = Map3DViaduct.trussMember
        for (slot, sign) in [Float(-1), 1].enumerated() {
            for run in runs(of: line, where: beside[slot].map { $0 == nil }) {
                mesh.addRibbon(along: run, width: member, offset: sign * Map3DViaduct.trussOffset, lift: Map3DViaduct.trussHeight, depth: member,
                               top: Map3DPalette.bridge, side: Map3DPalette.bridge)
                mesh.addRibbon(along: run, width: member, offset: sign * Map3DViaduct.trussOffset, lift: -Self.bedDrop + member, depth: member,
                               top: Map3DPalette.bridge, side: Map3DPalette.bridge)
            }
        }
    }

    /// The truss's diagonals (a Warren truss, ``Map3DViaduct/trussPanels``
    /// panels a span) on each side with no track beside it, and the
    /// beams across its top at each panel point, out to the middle
    /// between the tracks where one runs beside it.
    static func addTrussMembers(_ mesh: inout Map3DMesh, line: [Map3DPoint], across: [Map3DPoint], beside: [[Float?]], span: Float) {
        // Each point along the line every half a panel: where, and on
        // which segment.
        var travelled: [Float] = [0]
        for index in 1..<line.count { travelled.append(travelled[index - 1] + Map3DPoint(line[index].x - line[index - 1].x, 0, line[index].z - line[index - 1].z).length) }
        let total = travelled[travelled.count - 1], half = span / Float(Map3DViaduct.trussPanels) / 2
        guard total > half else { return }
        func at(_ distance: Float) -> (point: Map3DPoint, across: Map3DPoint, segment: Int) {
            var index = 1
            while index < line.count - 1, travelled[index] < distance { index += 1 }
            let share = travelled[index] > travelled[index - 1] ? (distance - travelled[index - 1]) / (travelled[index] - travelled[index - 1]) : 0
            let side = (across[index - 1] * (1 - share) + across[index] * share).normalized ?? across[index]
            return (line[index - 1] + (line[index] - line[index - 1]) * share, side, index - 1)
        }
        let low = -Self.bedDrop + Map3DViaduct.trussMember / 2, high = Map3DViaduct.trussHeight - Map3DViaduct.trussMember / 2
        let steps = Int((total / half).rounded(.down))
        for step in 0..<steps {
            let a = at(Float(step) * half), b = at(Float(step + 1) * half)
            // Bottom at the even points, top at the odd: up then down.
            let (fromLift, toLift) = step % 2 == 0 ? (low, high) : (high, low)
            for (slot, sign) in [Float(-1), 1].enumerated() where beside[slot][a.segment] == nil {
                let offset = sign * Map3DViaduct.trussOffset
                mesh.addBeam(from: a.point + a.across * offset + Map3DPoint(0, fromLift, 0), to: b.point + b.across * offset + Map3DPoint(0, toLift, 0),
                             width: Map3DViaduct.trussMember, color: Map3DPalette.bridge)
            }
            // A beam across the top at each top panel point.
            if step % 2 == 0 {
                let reach = [Float(-1), 1].enumerated().map { slot, sign in
                    sign * (beside[slot][b.segment].map { $0 / 2 } ?? Map3DViaduct.trussOffset)
                }
                mesh.addBeam(from: b.point + b.across * reach[0] + Map3DPoint(0, high, 0), to: b.point + b.across * reach[1] + Map3DPoint(0, high, 0),
                             width: Map3DViaduct.trussMember * 0.8, color: Map3DPalette.bridge)
            }
        }
    }

    /// Decision 407: `requests`' piers, each with the one of the track
    /// beside it (the same kind, running the same way, within
    /// ``Map3DViaduct/neighbourReach`` across and half a span along) as
    /// one pier under their middle; each as its kind of viaduct stands.
    mutating func addPiers(_ requests: [Map3DViaducts.Pier]) {
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        for (index, request) in requests.enumerated() { cells[Map3DViaducts.cell(request.top), default: []].append(index) }
        var used = [Bool](repeating: false, count: requests.count)
        for (index, request) in requests.enumerated() where !used[index] {
            used[index] = true
            let look = request.viaduct.look(over: request.kind)
            guard let forward = Map3DPoint(request.forward.x, 0, request.forward.z).normalized else { continue }
            let across = Map3DPoint(-forward.z, 0, forward.x)
            // Its pair: the nearest along.
            var pair: (index: Int, ahead: Float)?
            let home = Map3DViaducts.cell(request.top)
            for dc in -1...1 {
                for dr in -1...1 {
                    for other in cells[Map3DScene.ChunkKey(column: home.column + dc, row: home.row + dr)] ?? [] where !used[other] {
                        let candidate = requests[other]
                        guard candidate.viaduct == request.viaduct, candidate.kind == request.kind,
                              let way = Map3DPoint(candidate.forward.x, 0, candidate.forward.z).normalized,
                              abs(way.x * forward.x + way.z * forward.z) >= 0.9 else { continue }
                        let offset = candidate.top - request.top
                        let lateral = abs(offset.x * across.x + offset.z * across.z), ahead = abs(offset.x * forward.x + offset.z * forward.z)
                        guard lateral >= 1.5, lateral <= Map3DViaduct.neighbourReach, ahead <= look.span / 2,
                              ahead < (pair?.ahead ?? .infinity) else { continue }
                        pair = (other, ahead)
                    }
                }
            }
            var top = request.top, foot = request.foot, spread: Float = 0
            if let pair {
                used[pair.index] = true
                let other = requests[pair.index]
                let offset = other.top - request.top
                spread = abs(offset.x * across.x + offset.z * across.z)
                top = Map3DPoint((top.x + other.top.x) / 2, min(top.y, other.top.y), (top.z + other.top.z) / 2)
                foot = (foot + other.foot) / 2
            }
            guard top.y - foot > 0.5 else { continue }
            let base = Map3DPoint(top.x, foot, top.z), capFoot = top.y - look.capDepth
            piers.append(base)
            mesh(at: base) { mesh in
                switch look.pier {
                case let .wall(along, wide, cap):
                    mesh.addBox(base: base, forward: forward, length: along, width: wide + spread, height: max(capFoot - foot, 0.1),
                                top: Map3DPalette.concrete, side: Map3DPalette.concrete, frontPaint: Self.concrete, flankPaint: Self.concrete)
                    if cap > 0 {
                        mesh.addBox(base: Map3DPoint(top.x, capFoot, top.z), forward: forward, length: look.capAlong, width: cap + spread,
                                    height: look.capDepth, top: Map3DPalette.concrete, side: Map3DPalette.concrete,
                                    frontPaint: Self.concrete, flankPaint: Self.concrete)
                    }
                case let .column(along, wide, head):
                    mesh.addBox(base: base, forward: forward, length: along, width: wide, height: max(capFoot - foot, 0.1),
                                top: Map3DPalette.concrete, side: Map3DPalette.concrete, frontPaint: Self.concrete, flankPaint: Self.concrete)
                    mesh.addBox(base: Map3DPoint(top.x, capFoot, top.z), forward: forward, length: look.capAlong, width: head,
                                height: look.capDepth, top: Map3DPalette.concrete, side: Map3DPalette.concrete,
                                frontPaint: Self.concrete, flankPaint: Self.concrete)
                case let .round(radius, cap):
                    mesh.addCylinder(base: base, radius: radius, height: max(capFoot - foot, 0.1), sides: 8,
                                     top: Map3DPalette.concrete, side: Map3DPalette.concrete, paint: Self.concrete, capped: false)
                    mesh.addBox(base: Map3DPoint(top.x, capFoot, top.z), forward: forward, length: look.capAlong, width: cap + spread,
                                height: look.capDepth, top: Map3DPalette.concrete, side: Map3DPalette.concrete,
                                frontPaint: Self.concrete, flankPaint: Self.concrete)
                }
            }
        }
    }
}

extension Map3DMesh {
    /// Decision 407: a square beam `width` thick from `a` to `b`, its
    /// four sides (a truss's member).
    mutating func addBeam(from a: Map3DPoint, to b: Map3DPoint, width: Float, color: UInt32) {
        guard let along = (b - a).normalized else { return }
        let up = abs(along.y) > 0.95 ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 1, 0)
        guard let side = along.cross(up).normalized, let over = side.cross(along).normalized else { return }
        let s = side * (width / 2), o = over * (width / 2)
        let ring = [s + o, o - s, Map3DPoint(0, 0, 0) - s - o, s - o]
        for index in 0..<4 {
            let p = ring[index], q = ring[(index + 1) % 4]
            addQuad(a + p, b + p, b + q, a + q, color: color)
        }
    }
}
