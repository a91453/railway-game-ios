import GameCore

/// Decision 359 (續): the tunnel drawn, its bore along the track and its
/// portals, in the game's flat low-poly look rather than the reference's
/// round arch (`Railway/taiwan-rail-reference-clean/source/rail-3d/integration/tunnel-portals.js`,
/// `rail-structures.js`, whose sizes it keeps).
extension Map3DScene.Builder {
    // The bore, in metres from the rails' middle (rail-structures.js
    // `BORE_R`, `BORE_FLOOR`, its spring and its arch's rise): walls
    // 3.2 m either side up to 2.8 m over the rails, one slope in to a
    // flat roof 6 m over them, the floor 1.2 m under them.
    static let boreHalfWidth: Float = 3.2
    static let boreSpring: Float = 2.8
    static let boreCrown: Float = 6
    /// How far in from the walls the roof's flat reaches each way.
    static let boreSlope: Float = 1.4
    static let boreFloor: Float = 1.2
    /// The earth over a bore too shallow for the drawn ground to cover (a
    /// cut-and-cover tunnel's backfill), metres over its roof and past
    /// its walls; its sides fall 1 : 1 to the ground, as an embankment's.
    static let coverThickness: Float = 0.6
    /// How far apart two tunnel tracks may run and still share one bore,
    /// in metres: closer, their covers would cross.
    static let sharedBore: Float = 2 * (boreHalfWidth + coverThickness)
    /// A lamp on a wall every so many metres, on the two walls in turn.
    static let lampSpacing: Float = 24
    static let lampHeight: Float = 2.2
    // The portal (tunnel-portals.js `PORTAL_HALF_CLEAR`, `PORTAL_WING`;
    // rail-structures.js `PORTAL_T`, `PORTAL_EMBED`, `PORTAL_DROP_MAX`):
    // a head wall 1.2 m thick reaching 2 m past the opening and 1.3 m
    // over the roof, its foot 0.8 m in the ground, wings splaying 2 m out
    // over 8 m.
    static let portalThickness: Float = 1.2
    static let portalShoulder: Float = 2
    static let portalOverRoof: Float = 1.3
    static let portalEmbed: Float = 0.8
    static let portalDeepest: Float = 45
    static let portalWing: Float = 8
    static let portalSplay: Float = 2
    static let wingThickness: Float = 0.45
    /// The band round the opening, as wide and as far proud.
    static let portalRing: Float = 0.6
    static let portalRingProud: Float = 0.2

    /// The face through `corners`, turned to face `facing` (seen from that
    /// side its corners run counter-clockwise).
    private static func face(_ mesh: inout Map3DMesh, _ corners: [Map3DPoint], facing: Map3DPoint, color: UInt32, paint: Map3DPaint? = nil) {
        guard corners.count >= 3, let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized
                ?? (corners.count > 3 ? (corners[2] - corners[0]).cross(corners[3] - corners[0]).normalized : nil) else { return }
        let turned = normal.dot(facing) < 0 ? Array(corners.reversed()) : corners
        if turned.count == 4 {
            mesh.addQuad(turned[0], turned[1], turned[2], turned[3], color: color, paint: paint)
        } else {
            mesh.addFacet(turned, color: color, paint: paint)
        }
    }

    // MARK: The bore

    /// The bore round `line` (a piece of a tunnel at the rails' height):
    /// its floor, walls, roof and lamps; where another tunnel track runs
    /// beside it, no wall between them but the roof to halfway; where the
    /// drawn ground does not cover it, a bank of earth over it.
    mutating func addBore(_ line: [Map3DPoint], into mesh: inout Map3DMesh) {
        let across = Map3DMesh.acrossDirections(line)
        // How far each side the bore reaches at each point: halfway to a
        // tunnel beside it, or `nil` for its own wall.
        let beside = line.indices.map { trackCover.tunnelsBeside(line[$0], across: across[$0], within: Self.sharedBore) }
        let grounds = line.map { drawnGround(x: $0.x, z: $0.z) }
        let hw = Self.boreHalfWidth, crown = Self.boreCrown, floor = -Self.boreFloor, roofEdge = hw - Self.boreSlope
        let top = crown + Self.coverThickness, outer = hw + Self.coverThickness
        var travelled: Float = 0, nextLamp: Float = Self.lampSpacing / 2, lampSide: Float = -1
        for index in 1..<line.count {
            let a = line[index - 1], b = line[index]
            let step = Map3DPoint(b.x - a.x, 0, b.z - a.z).length
            guard step > 0 else { continue }
            func at(_ end: Int, _ u: Float, _ y: Float) -> Map3DPoint { line[end] + across[end] * u + Map3DPoint(0, y, 0) }
            let ends = [index - 1, index]
            let covered = ends.allSatisfy { line[$0].y + top <= grounds[$0] }
            for side: Float in [-1, 1] {
                // Shared on this side where either end has a tunnel beside.
                let shared = ends.map { side < 0 ? beside[$0].minus : beside[$0].plus }
                let reach = shared.compactMap { $0 }.map { $0 / 2 }
                let inward = across[index] * -side
                func strip(_ p: (Float, Float), _ q: (Float, Float), facing: Map3DPoint, color: UInt32, paint: Map3DPaint? = nil) {
                    Self.face(&mesh, [at(ends[0], side * p.0, p.1), at(ends[0], side * q.0, q.1), at(ends[1], side * q.0, q.1), at(ends[1], side * p.0, p.1)],
                              facing: facing, color: color, paint: paint)
                }
                if let far = reach.max() {
                    strip((0, floor), (far, floor), facing: Map3DPoint.up, color: Map3DPalette.tunnelLining)
                    strip((0, crown), (far, crown), facing: Map3DPoint.up * -1, color: Map3DPalette.tunnelLining)
                    if !covered { strip((0, top), (far, top), facing: Map3DPoint.up, color: Map3DPalette.embankment, paint: Self.bank) }
                    continue
                }
                strip((0, floor), (hw, floor), facing: Map3DPoint.up, color: Map3DPalette.tunnelLining)
                strip((hw, floor), (hw, Self.boreSpring), facing: inward, color: Map3DPalette.tunnelWall, paint: Self.concrete)
                strip((hw, Self.boreSpring), (roofEdge, crown), facing: inward + Map3DPoint.up * -1, color: Map3DPalette.tunnelWall, paint: Self.concrete)
                strip((roofEdge, crown), (0, crown), facing: Map3DPoint.up * -1, color: Map3DPalette.tunnelLining)
                if !covered {
                    strip((0, top), (outer, top), facing: Map3DPoint.up, color: Map3DPalette.embankment, paint: Self.bank)
                    // Its side down to a little under the ground.
                    let feet = ends.map { end in
                        let foot = max(min(grounds[end] - line[end].y - 0.3, top), floor - Self.coverThickness)
                        return at(end, side * (outer + top - foot), foot)
                    }
                    Self.face(&mesh, [at(ends[0], side * outer, top), feet[0], feet[1], at(ends[1], side * outer, top)],
                              facing: inward * -1 + Map3DPoint.up, color: Map3DPalette.embankment, paint: Self.bank)
                }
            }
            // The lamps, on the walls in turn, where a wall stands.
            while nextLamp <= travelled + step {
                let share = (nextLamp - travelled) / step
                let along = Map3DPoint(b.x - a.x, 0, b.z - a.z) * (1 / step)
                let side = lampSide, sideways = across[index - 1] + (across[index] - across[index - 1]) * share
                let open = side < 0 ? beside[index - 1].minus == nil && beside[index].minus == nil
                    : beside[index - 1].plus == nil && beside[index].plus == nil
                if open {
                    let base = a + (b - a) * share + sideways * (side * (hw - 0.06)) + Map3DPoint(0, Self.lampHeight, 0)
                    let start = mesh.vertices.count
                    mesh.addBox(base: base, forward: along, length: 1.2, width: 0.16, height: 0.14, top: Map3DPalette.tunnelLamp,
                                side: Map3DPalette.tunnelLamp)
                    mesh.makeGlowing(from: start)
                }
                lampSide = -lampSide
                nextLamp += Self.lampSpacing / 2
            }
            travelled += step
        }
    }

    // MARK: Portals

    /// Where a tunnel opens: the rails' middle there and the level way
    /// into the tunnel.
    struct PortalEnd {
        let point: Map3DPoint
        let into: Map3DPoint
    }

    /// Every end of a tunnel where the track goes on in the open, in the
    /// whole network: where an edge's sections change, and at a node
    /// that is a tunnel portal (``RailwaySnapshot/Node/isTunnelPortal``).
    func portalEnds(_ snapshot: RailwaySnapshot) -> [PortalEnd] {
        let portals = Set(snapshot.nodes.filter(\.isTunnelPortal).map(\.id))
        var ends: [PortalEnd] = []
        for alignment in snapshot.edges {
            let spans = alignment.edge.sectionSpans
            for (index, span) in spans.enumerated() where span.kind == .tunnel && span.end > span.start {
                let opensAtStart = index == 0 ? portals.contains(alignment.edge.from) : spans[index - 1].kind != .tunnel
                let opensAtEnd = index == spans.count - 1 ? portals.contains(alignment.edge.to) : spans[index + 1].kind != .tunnel
                for (opens, distance, sign) in [(opensAtStart, span.start, Float(1)), (opensAtEnd, span.end, Float(-1))] where opens {
                    let location = alignment.geometry.location(at: distance)
                    guard let into = (Map3DPoint(Float(location.direction.dx), 0, Float(location.direction.dy)) * sign).normalized else { continue }
                    ends.append(PortalEnd(point: point(location.position) + Self.lifted, into: into))
                }
            }
        }
        return ends
    }

    /// A portal of tracks side by side: the middle of their opening on
    /// the rails, the way in, and the opening's half width.
    struct Portal {
        let point: Map3DPoint
        let into: Map3DPoint
        let halfWidth: Float
    }

    /// `ends` grouped as the reference's `groupTunnelPortals`: facing the
    /// same way (within 10°), less than 12 m apart along it, 11 m across
    /// it and 2 m in height, under one wider opening.
    static func portals(_ ends: [PortalEnd]) -> [Portal] {
        var groups: [[PortalEnd]] = []
        for end in ends {
            func fits(_ other: PortalEnd) -> Bool {
                let gap = other.point - end.point
                let sideways = Map3DPoint(-end.into.z, 0, end.into.x)
                return end.into.dot(other.into) >= 0.985 && abs(gap.dot(end.into)) < 12 && abs(gap.dot(sideways)) < 11 && abs(gap.y) < 2
            }
            if let index = groups.firstIndex(where: { $0.allSatisfy(fits) }) { groups[index].append(end) } else { groups.append([end]) }
        }
        return groups.compactMap { members in
            guard let first = members.first,
                  let into = members.reduce(Map3DPoint(0, 0, 0), { $0 + $1.into }).normalized else { return nil }
            let sideways = Map3DPoint(-into.z, 0, into.x)
            let offsets = members.map { ($0.point - first.point).dot(sideways) }
            let low = offsets.min() ?? 0, high = offsets.max() ?? 0
            let front = members.map { ($0.point - first.point).dot(into) }.min() ?? 0
            let base = members.map(\.point.y).min() ?? first.point.y
            let middle = first.point + sideways * ((low + high) / 2) + into * front
            return Portal(point: Map3DPoint(middle.x, base, middle.z), into: into, halfWidth: boreHalfWidth + (high - low) / 2)
        }
    }

    /// Each tunnel's portal in the region: a head wall with a band round
    /// the opening, and wing walls splaying out of it, all down into the
    /// drawn ground.
    mutating func addPortals(_ snapshot: RailwaySnapshot) {
        for portal in Self.portals(portalEnds(snapshot)) {
            let worldX = originX + Double(portal.point.x) * Self.metre, worldY = originY + Double(portal.point.z) * Self.metre
            guard contains(x: worldX, y: worldY) else { continue }
            var built = Map3DMesh()
            addPortal(portal, into: &built)
            mesh(at: portal.point) { $0.append(built) }
        }
    }

    private mutating func addPortal(_ portal: Portal, into mesh: inout Map3DMesh) {
        let t = portal.into, u = Map3DPoint(-t.z, 0, t.x), origin = portal.point
        func at(_ across: Float, _ y: Float, _ d: Float = 0) -> Map3DPoint { origin + u * across + t * d + Map3DPoint(0, y, 0) }
        func ground(_ across: Float, _ d: Float = 0) -> Float {
            let p = at(across, 0, d)
            return drawnGround(x: p.x, z: p.z) - origin.y
        }
        func foot(_ across: Float, _ d: Float = 0) -> Float {
            max(-Self.portalDeepest, min(-Self.boreFloor, ground(across, d) - Self.portalEmbed))
        }
        let hw = portal.halfWidth, outer = hw + Self.portalShoulder, spring = Self.boreSpring, crown = Self.boreCrown
        let roofEdge = hw - Self.boreSlope, floor = -Self.boreFloor, thick = Self.portalThickness
        // 1.3 m over the roof. Not up to the ground behind it: where that
        // is higher, the portal stands in a cutting the 64 m ground
        // squares still cover, and a wall raised to them showed as a bar
        // on the hillside.
        let top = crown + Self.portalOverRoof
        let wall = Map3DPalette.concrete, trim = Map3DPalette.portal
        let out = t * -1
        // The head wall's two faces: either side of the opening, and over it.
        for (d, facing) in [(Float(0), out), (thick, t)] {
            for side: Float in [-1, 1] {
                Self.face(&mesh, [at(side * outer, foot(side * outer), d), at(side * hw, foot(side * hw), d), at(side * hw, spring, d),
                                  at(side * outer, spring, d)], facing: facing, color: wall, paint: Self.concrete)
                Self.face(&mesh, [at(side * outer, spring, d), at(side * hw, spring, d), at(side * roofEdge, crown, d), at(side * roofEdge, top, d),
                                  at(side * outer, top, d)], facing: facing, color: wall, paint: Self.concrete)
            }
            Self.face(&mesh, [at(-roofEdge, crown, d), at(roofEdge, crown, d), at(roofEdge, top, d), at(-roofEdge, top, d)], facing: facing,
                      color: wall, paint: Self.concrete)
        }
        // Its ends, and a coping along its top.
        for side: Float in [-1, 1] {
            Self.face(&mesh, [at(side * outer, foot(side * outer), 0), at(side * outer, foot(side * outer, thick), thick), at(side * outer, top, thick),
                              at(side * outer, top, 0)], facing: u * side, color: wall, paint: Self.concrete)
        }
        mesh.addBox(base: at(0, top - 0.2, thick / 2), forward: t, length: thick + 0.36, width: 2 * outer + 0.36, height: 0.4, top: trim, side: trim)
        // The band round the opening, a little proud of the wall: the
        // opening's outline and the same moved out by the band's width.
        let outline: [(Float, Float)] = [(-hw, floor), (-hw, spring), (-roofEdge, crown), (roofEdge, crown), (hw, spring), (hw, floor)]
        let band = Self.offsetOutline(outline, by: Self.portalRing)
        let proud = -Self.portalRingProud
        for index in 1..<outline.count {
            let corners = [at(outline[index - 1].0, outline[index - 1].1, proud), at(outline[index].0, outline[index].1, proud),
                           at(band[index].0, band[index].1, proud), at(band[index - 1].0, band[index - 1].1, proud)]
            Self.face(&mesh, corners, facing: out, color: trim)
            // Its outer edge, back to the wall.
            Self.face(&mesh, [at(band[index - 1].0, band[index - 1].1, proud), at(band[index].0, band[index].1, proud),
                              at(band[index].0, band[index].1, 0), at(band[index - 1].0, band[index - 1].1, 0)],
                      facing: at(band[index - 1].0 + band[index].0, band[index - 1].1 + band[index].1) - at(0, spring * 2), color: trim)
        }
        // The wings: from the head wall's shoulders out and down, 2 m wider
        // over 8 m, to 0.6 m over the rails.
        let wingTop = top - 0.22, tip: Float = 0.6, reach = outer + Self.portalSplay, length = -Self.portalWing
        for side: Float in [-1, 1] {
            let th = Self.wingThickness * side
            let inner = [at(side * outer, foot(side * outer), 0), at(side * outer, wingTop, 0), at(side * reach, tip, length),
                         at(side * reach, foot(side * reach, length), length)]
            let outerFace = [at(side * outer + th, foot(side * outer + th), 0), at(side * outer + th, wingTop, 0),
                             at(side * reach + th, tip, length), at(side * reach + th, foot(side * reach + th, length), length)]
            let sideways = (inner[2] - inner[1]).cross(Map3DPoint(0, 1, 0)).normalized ?? u * side
            let toTrack = sideways.dot(u * side) > 0 ? sideways * -1 : sideways
            Self.face(&mesh, inner, facing: toTrack, color: wall, paint: Self.concrete)
            Self.face(&mesh, outerFace, facing: toTrack * -1, color: wall, paint: Self.concrete)
            Self.face(&mesh, [inner[1], outerFace[1], outerFace[2], inner[2]], facing: Map3DPoint.up, color: trim)
            Self.face(&mesh, [inner[2], outerFace[2], outerFace[3], inner[3]], facing: out, color: wall, paint: Self.concrete)
        }
    }

    /// `outline` (across, up; an open line round the opening's inside)
    /// moved out by `width`: each corner where its two sides, moved out,
    /// meet; the two ends straight out.
    static func offsetOutline(_ outline: [(Float, Float)], by width: Float) -> [(Float, Float)] {
        // Each side's outward normal: the opening is inside, to the left
        // of a side walked from the first point to the last.
        let normals: [(Float, Float)] = (1..<outline.count).map { index in
            let dx = outline[index].0 - outline[index - 1].0, dy = outline[index].1 - outline[index - 1].1
            let length = (dx * dx + dy * dy).squareRoot()
            return (-dy / length, dx / length)
        }
        return outline.indices.map { index in
            let before = normals[max(index - 1, 0)], after = normals[min(index, normals.count - 1)]
            let sum = (before.0 + after.0, before.1 + after.1)
            let along = sum.0 * after.0 + sum.1 * after.1
            let scale = along > 0.01 ? width / along : width
            return (outline[index].0 + sum.0 * scale, outline[index].1 + sum.1 * scale)
        }
    }
}

extension Map3DTrackCover {
    /// Decision 359 (續): how far across from `point` on the rails the
    /// nearest other tunnel track runs within `within` metres, along
    /// `across` (level, one metre long; `plus`) and against it (`minus`);
    /// `nil` on a side with none.
    func tunnelsBeside(_ point: Map3DPoint, across: Map3DPoint, within: Float) -> (minus: Float?, plus: Float?) {
        let low = Self.key(x: point.x - within, z: point.z - within), high = Self.key(x: point.x + within, z: point.z + within)
        var minus: Float?, plus: Float?
        var seen = Set<Int>()
        for row in low.row...high.row {
            for column in low.column...high.column {
                for index in cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] where seen.insert(index).inserted {
                    let piece = pieces[index]
                    guard piece.isTunnel else { continue }
                    let along = Map3DPoint(piece.b.x - piece.a.x, 0, piece.b.z - piece.a.z)
                    let squared = along.dot(along)
                    guard squared > 0 else { continue }
                    let share = min(max(Map3DPoint(point.x - piece.a.x, 0, point.z - piece.a.z).dot(along) / squared, 0), 1)
                    let on = piece.a + (piece.b - piece.a) * share
                    guard abs(point.y - on.y) <= Self.rise else { continue }
                    let gap = Map3DPoint(on.x - point.x, 0, on.z - point.z)
                    let distance = gap.length, sideways = gap.dot(across)
                    // Beside it, not on it nor ahead of it.
                    guard distance > Self.reach, distance <= within, abs(sideways) >= distance * 0.9 else { continue }
                    if sideways > 0 { plus = min(plus ?? within, sideways) } else { minus = min(minus ?? within, -sideways) }
                }
            }
        }
        return (minus, plus)
    }
}
