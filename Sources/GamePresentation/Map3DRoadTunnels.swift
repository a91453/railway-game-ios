import GameCore

// Decision 611 (ROADTUNNEL): the real roads' tunnel portals in the 3D map.
// The base map leaves a tunnel's road out (decision 234), so the road on
// the ground stops where the tunnel opens; there the scene stands one of
// `Map3DRoadTunnelPortals`' portals, picked by the road's class and
// whether traffic takes it one way, its foot down to the drawn ground, the
// hillside laid over its top and a dark floor over the ground inside it.

extension Map3DScene.Builder {
    /// How much the drawn ground must rise over the first ``riseReach``
    /// metres into a tunnel for a portal to stand there, metres: a road
    /// into a hill. Less (a city's underpass, a covered street), none.
    static let roadTunnelRise: Float = 4
    static let riseReach: Float = 40
    /// Rising less than this over the first ``galleryReach`` metres, the
    /// hillside starts further in: a gallery (明隧道) reaches out to it.
    static let galleryRise: Float = 1.5
    static let galleryReach: Float = 12
    /// Where the ground inside rises this far over the road, the lining's
    /// dark cap stands (at least ``shallowestLining`` in): past it the
    /// drawn ground would show inside.
    static let liningRise: Float = 1.5
    static let shallowestLining: Float = 3
    /// The dark floor over the drawn ground inside, metres over it.
    static let liningFloorLift: Float = 0.06
    /// The deepest a portal's foot goes, metres under its road.
    static let roadPortalDeepest: Float = 30

    /// One portal: where its road enters (on the drawn ground), the level
    /// way in, which portal, and how deep its lining is.
    struct RoadPortal: Equatable {
        let point: Map3DPoint
        let into: Map3DPoint
        let style: Map3DRoadTunnelPortals.Style
        let width: Map3DRoadTunnelPortals.Width
        let depth: Float
        /// Its road's class: a gallery's road surface under its roof.
        var kind: Map3DBaseMap.RoadKind = .minor
    }

    /// Decision 611: the portal a road of `kind` takes. A freeway's two
    /// carriageways under one head wall (`paired`) the divided portal; a
    /// freeway, provincial or main road its named portal; a county road
    /// the arched; a township lane or service road the narrow one. Where
    /// the hillside starts further in (`gentle`), but for a pair, a gallery.
    /// One way (or a ramp) a two-lane bore; both ways the wider one.
    static func portalStyle(kind: Map3DBaseMap.RoadKind, oneway: Bool, ramp: Bool, paired: Bool, gentle: Bool)
        -> (style: Map3DRoadTunnelPortals.Style, width: Map3DRoadTunnelPortals.Width) {
        let width: Map3DRoadTunnelPortals.Width = oneway || ramp || paired ? .oneWay : .twoWay
        if paired { return (.dividedExpressway, .oneWay) }
        if gentle { return (.daylightGallery, width) }
        switch kind {
        case .motorway, .trunk, .primary: return (.nameplate, width)
        case .secondary, .tertiary: return (.mountainArch, width)
        case .minor, .service: return (.narrowLane, width)
        }
    }

    /// The portals of `ends` the scene stands: an end whose ground rises
    /// into a hill, two freeway carriageways side by side (facing the same
    /// way within 10°, 6 to 14 m apart across, 12 m along) as one pair.
    mutating func roadPortals(_ ends: [Map3DBaseMap.TunnelEnd]) -> [RoadPortal] {
        struct Found { let end: Map3DBaseMap.TunnelEnd; let point: Map3DPoint; let into: Map3DPoint; let rise: (Float) -> Float }
        var found: [Found] = []
        for end in ends {
            let start = Map3DPoint(Float(end.point.x), 0, Float(end.point.z))
            let line = end.inward.map { Map3DPoint(Float($0.x), 0, Float($0.z)) }
            // The way in: toward the line's point 6 m or more in.
            guard let ahead = line.first(where: { ($0 - start).length >= 6 }) ?? line.last,
                  let into = (ahead - start).normalized else { continue }
            let ground = drawnGround(x: start.x, z: start.z)
            let path = Map3DStreetLife.Path(line)
            var samples: [(Float, Float)] = []
            for step in stride(from: Float(4), through: Self.riseReach, by: 4) {
                let at = path.map { $0.length >= step ? $0.at(step).point : start + into * step } ?? start + into * step
                samples.append((step, drawnGround(x: at.x, z: at.z) - ground))
            }
            func rise(_ within: Float) -> Float { samples.filter { $0.0 <= within }.map(\.1).max() ?? 0 }
            guard rise(Self.riseReach) >= Self.roadTunnelRise else { continue }
            found.append(Found(end: end, point: Map3DPoint(start.x, ground, start.z), into: into, rise: rise))
        }
        // Decision 661 (review L13-7): the ends in an order of their own
        // (by place), and the pairs closest first, so that the portals do
        // not depend on the order the tiles gave the ends: a chunk built
        // apart (its tiles and an apron) pairs as the whole scene does.
        found.sort { (one, other) in
            (one.point.x, one.point.z, one.into.x, one.into.z) < (other.point.x, other.point.z, other.into.x, other.into.z)
        }
        let partner = Self.pairedCarriageways(found.map { (paired: $0.end.kind == .motorway && !$0.end.isRamp, point: $0.point, into: $0.into) })
        var portals: [RoadPortal] = []
        for (index, one) in found.enumerated() {
            var point = one.point, into = one.into, paired = false
            if let other = partner[index] {
                // Each pair once, at the first of its two.
                guard other > index else { continue }
                paired = true
                let a = one.point, b = found[other].point
                into = (one.into + found[other].into).normalized ?? one.into
                // Between the two, on the nearer end's line across.
                let middle = a + (b - a) * 0.5
                let back = (middle - a).dot(into) - min(0, (b - a).dot(into))
                point = Map3DPoint(middle.x - into.x * back, min(a.y, b.y), middle.z - into.z * back)
            }
            let gentle = one.rise(Self.galleryReach) < Self.galleryRise
            let (style, width) = Self.portalStyle(kind: one.end.kind, oneway: one.end.oneway, ramp: one.end.isRamp, paired: paired, gentle: gentle)
            // The lining's depth: where the ground inside first rises
            // ``liningRise`` over the road.
            let inside = style == .daylightGallery ? Map3DRoadTunnelPortals.galleryLength : 0
            var depth = Map3DRoadTunnelPortals.liningDepth
            for step in stride(from: Float(1), through: Map3DRoadTunnelPortals.liningDepth, by: 1) {
                let at = point + into * (inside + Map3DRoadTunnelPortals.wallThickness + step)
                if drawnGround(x: at.x, z: at.z) - point.y >= Self.liningRise { depth = max(step, Self.shallowestLining); break }
            }
            portals.append(RoadPortal(point: point, into: into, style: style, width: width, depth: depth, kind: one.end.kind))
        }
        return portals
    }

    /// Decision 661 (review L13-7): which of `ends` are two freeway
    /// carriageways side by side (both `paired`, facing the same way within
    /// 10°, 6 to 14 m apart across, 12 m along), each end's partner by
    /// index or `nil`. The closest such pairs are taken first (ties by
    /// index), so that three or more ends crowded together pair the same
    /// whichever order they come in, given the same order of `ends`.
    static func pairedCarriageways(_ ends: [(paired: Bool, point: Map3DPoint, into: Map3DPoint)]) -> [Int?] {
        var candidates: [(gap: Float, a: Int, b: Int)] = []
        for a in ends.indices where ends[a].paired {
            for b in ends.indices where b > a && ends[b].paired {
                func fits(_ one: Int, _ other: Int) -> Bool {
                    guard ends[one].into.dot(ends[other].into) >= 0.985 else { return false }
                    let gap = ends[other].point - ends[one].point, sideways = Map3DPoint(-ends[one].into.z, 0, ends[one].into.x)
                    return abs(gap.dot(ends[one].into)) < 12 && (6...14).contains(abs(gap.dot(sideways)))
                }
                // Either way round, as the earlier pairing tried from
                // whichever came first.
                guard fits(a, b) || fits(b, a) else { continue }
                candidates.append(((ends[b].point - ends[a].point).length, a, b))
            }
        }
        candidates.sort { ($0.gap, $0.a, $0.b) < ($1.gap, $1.a, $1.b) }
        var partner = [Int?](repeating: nil, count: ends.count)
        for pair in candidates where partner[pair.a] == nil && partner[pair.b] == nil {
            partner[pair.a] = pair.b
            partner[pair.b] = pair.a
        }
        return partner
    }

    /// Decision 611: each real road tunnel's portal in the region, in the
    /// city's full detail (``Target/near``): not drawn from afar, where the
    /// chunk's simplified city stands, as decision 460's levels draw the
    /// city.
    mutating func addRoadTunnels(_ ends: [Map3DBaseMap.TunnelEnd], areas: [Map3DBaseMap.Area] = []) {
        let kept = target
        target = .near
        defer { target = kept }
        let portals = roadPortals(ends)
        let zones = portals.map(Self.clearZone)
        for (index, portal) in portals.enumerated() {
            var built = Map3DMesh()
            let others = zones.indices.filter { $0 != index }.map { zones[$0] }
            addRoadPortal(portal, cover: Self.cover(at: portal.point, in: areas), clear: others, into: &built)
            mesh(at: portal.point) { $0.append(built) }
        }
    }

    /// Decision 611 (#1925's review, 1): the hillside's colour and paint, as
    /// the drawn ground's under the portal (the cover drawn on top there,
    /// else the plain ground), so the hill reads as the land it rises from.
    static func cover(at point: Map3DPoint, in areas: [Map3DBaseMap.Area]) -> (color: UInt32, paint: Map3DPaint?) {
        let x = Double(point.x), z = Double(point.z)
        var best: Map3DBaseMap.Cover?
        for area in areas where area.cover != .water && (best.map { area.cover.rawValue > $0.rawValue } ?? true) {
            guard area.bounds.minX <= x, x <= area.bounds.maxX, area.bounds.minZ <= z, z <= area.bounds.maxZ else { continue }
            let inside = area.rings.reduce(0) { count, ring in count + (Self.contains(ring, x: x, z: z) ? 1 : 0) }
            if inside % 2 == 1 { best = area.cover }
        }
        guard let cover = best else { return (Map3DPalette.ground, nil) }
        return (Map3DPalette.cover(cover), Self.grass)
    }

    private static func contains(_ ring: [Map3DBaseMap.Point], x: Double, z: Double) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.z > z) != (b.z > z), x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// The portal `portal`, its foot down to the drawn ground, the hillside
    /// over its top (in `cover`'s colour) and the dark floor inside, in
    /// scene metres.
    mutating func addRoadPortal(_ portal: RoadPortal, cover: (color: UInt32, paint: Map3DPaint?) = (Map3DPalette.ground, nil),
                                clear: [ClearZone] = [], into mesh: inout Map3DMesh) {
        let part = Map3DRoadTunnelPortals.make(portal.style, width: portal.width, depth: portal.depth)
        let along = portal.into, right = along.cross(.up)
        // The road's end at the outer entrance: the part's own origin
        // stands `front` along from it (a gallery 12 m in).
        let origin = portal.point + along * -part.front
        func world(_ x: Float, _ y: Float, _ z: Float) -> Map3DPoint { origin + along * x + right * z + Map3DPoint(0, y, 0) }
        func ground(_ x: Float, _ z: Float) -> Float {
            let p = world(x, 0, z)
            return drawnGround(x: p.x, z: p.z) - origin.y
        }
        // Its foot down to the ground, as decision 359's portal's.
        var local = part.mesh
        local.restyleVertices { vertex in
            guard abs(vertex.y - part.floor) < 1e-3 else { return }
            vertex.y = max(-Self.roadPortalDeepest, min(part.floor, ground(vertex.x, vertex.z) - Map3DRoadTunnelPortals.embed))
        }
        mesh.append(local, at: origin, forward: along)
        Self.addPortalHillside(part, gallery: portal.style == .daylightGallery, color: cover.color, paint: cover.paint,
                               ground: ground, world: world, clear: { p in clear.contains { $0.contains(p) } }, into: &mesh)
        // The floor over the drawn ground, which would show through the
        // opening (the road's own surface stops at the entrance): under a
        // gallery's open roof the road, lit; inside each bore dark.
        let half = part.clearWidth / 2
        var lit = Map3DMesh(), dark = Map3DMesh()
        var x = part.front + (part.front < 0 ? 0 : Map3DRoadTunnelPortals.wallThickness)
        while x < part.innerEnd - 1e-3 {
            let open = x < 0
            let next = min(x + 1, open ? 0 : part.innerEnd)
            let lift = open ? Self.lift(of: portal.kind) : Self.liningFloorLift
            for centre in part.centres {
                let corners = [(x, centre - half), (x, centre + half), (next, centre + half), (next, centre - half)].map { x, z in
                    world(x, max(ground(x, z), 0) + lift, z)
                }
                if open { Self.addFace(&lit, corners, facing: .up, color: Map3DPalette.road(portal.kind)) }
                else { Self.addFace(&dark, corners, facing: .up, color: Map3DRoadTunnelPortals.liningShades[3]) }
            }
            x = next
        }
        dark.restyleVertices { ($0.nx, $0.ny, $0.nz) = (0, -1, 0) }
        mesh.append(lit)
        mesh.append(dark)
    }

    /// Decision 611 (#1925's review, 1): the ground in front of a portal
    /// that another portal's hillside keeps out of: its road's way in
    /// between its wings (a gallery's whole open length), so a pair of
    /// bores side by side each keep their opening and road in the clear.
    struct ClearZone {
        let origin: Map3DPoint, along: Map3DPoint, right: Map3DPoint
        let start: Float, end: Float, half: Float, splay: Float

        func contains(_ p: Map3DPoint) -> Bool {
            let d = p - origin
            let x = d.dot(along), z = abs(d.dot(right))
            guard x >= start, x <= end else { return false }
            return z <= half + splay * min(max((end - x) / Map3DRoadTunnelPortals.wingLength, 0), 1)
        }
    }

    static func clearZone(of portal: RoadPortal) -> ClearZone {
        let part = Map3DRoadTunnelPortals.make(portal.style, width: portal.width, depth: portal.depth)
        let gallery = portal.style == .daylightGallery
        let along = portal.into
        return ClearZone(origin: portal.point + along * -part.front, along: along, right: along.cross(.up),
                         start: part.front - Map3DRoadTunnelPortals.wingLength - 9, end: gallery ? 0.5 : part.front + 0.5,
                         half: part.outerHalfWidth + 1, splay: gallery ? 2 : Map3DRoadTunnelPortals.wingSplay)
    }

    /// Decision 611: how gently the hillside falls away from the portal,
    /// metres out for each metre down (1 : 3), and how far out it reaches
    /// beside it, metres.
    static let hillsideFall: Float = 3
    static let hillsideReach: [Float] = [0, 1.5, 3, 5, 8, 12, 16, 21, 27]

    /// Decision 611 (#1885's review, 1; #1925's review, 1): the hillside
    /// over the portal: from the head wall's top edge it climbs a metre
    /// and a little more over the bores, runs back past the lining and
    /// falls gently (``hillsideFall``) to the ground behind and beside,
    /// and in front beside the wings from their tops; on a hill the drawn
    /// ground covers it, on level ground it is a wide, low hill whose
    /// edges go into the ground. A gallery's hill starts at its inner head
    /// wall, where the bore goes in, leaving the gallery's open sides in
    /// the clear.
    private static func addPortalHillside(_ part: Map3DRoadTunnelPortals.Part, gallery: Bool, color: UInt32, paint: Map3DPaint?,
                                          ground: (Float, Float) -> Float, world: (Float, Float, Float) -> Map3DPoint,
                                          clear: (Map3DPoint) -> Bool, into mesh: inout Map3DMesh) {
        let fall = hillsideFall, top = part.top
        let front: Float = gallery ? 0 : part.front
        // In front: beside the wings, falling from their tops; beside a
        // gallery, a cut face 1 : 1, a little out from its sides.
        let wing = gallery ? top : Map3DRoadTunnelPortals.wingLength
        let splay: Float = gallery ? 2 : Map3DRoadTunnelPortals.wingSplay
        let foot: Float = gallery ? 0 : 0.6
        let edge = part.outerHalfWidth + 0.45
        let back = part.innerEnd + 2, crest: Float = 1.2
        // The hill's height at `x` along over the head wall's line across.
        func ridge(_ x: Float) -> Float {
            if x < front - wing { return foot - (front - wing - x) / fall }
            if x < front { return top - 0.2 + (foot - (top - 0.2)) * (front - x) / wing }
            if x <= back { return top + crest * min((x - front) / 2, 1) }
            return top + crest - (x - back) / fall
        }
        var rows: [Float] = [front - wing - 9, front - wing - 4.5, front - wing, front - wing / 2, front]
        rows += stride(from: front + 2, to: back, by: 2).map { $0 }
        rows += stride(from: back, through: back + (top + crest) * fall + 3, by: 3).map { $0 }
        let reach = hillsideReach
        // Each corner's height, and whether it is under the ground.
        func height(_ x: Float, _ z: Float, _ y: Float, last: Bool) -> (point: Map3DPoint, buried: Bool) {
            let g = ground(x, z)
            if last || clear(world(x, 0, z)) { return (world(x, g - 0.5, z), true) }
            return (world(x, max(y, g - 0.3), z), y <= g - 0.3)
        }
        func quad(_ a: (point: Map3DPoint, buried: Bool), _ b: (point: Map3DPoint, buried: Bool),
                  _ c: (point: Map3DPoint, buried: Bool), _ d: (point: Map3DPoint, buried: Bool)) {
            // All four under the ground: hidden, not drawn.
            guard !(a.buried && b.buried && c.buried && d.buried) else { return }
            Self.addFace(&mesh, [a.point, b.point, c.point, d.point], facing: .up, color: color, paint: paint)
        }
        // Beside: each side's strip, out from the wing's or the hood's edge.
        for side: Float in [-1, 1] {
            func line(_ x: Float, _ row: Int) -> [(point: Map3DPoint, buried: Bool)] {
                let out = edge + splay * min(max((front - x) / wing, 0), 1)
                return reach.enumerated().map { k, d in
                    let z = side * (out + d)
                    let last = k == reach.count - 1 || row == 0 || row == rows.count - 1
                    return height(x, z, ridge(x) - d / fall, last: last)
                }
            }
            for row in 1..<rows.count {
                let a = line(rows[row - 1], row - 1), b = line(rows[row], row)
                for k in 1..<reach.count { quad(a[k - 1], a[k], b[k], b[k - 1]) }
            }
        }
        // Over: from the head wall's top back, a little crest over the bores.
        let across = stride(from: -edge, through: edge + 1e-3, by: max(edge / 4, 1)).map { $0 }
        let overRows = rows.filter { $0 >= front }
        for row in 1..<overRows.count {
            func line(_ x: Float, last: Bool) -> [(point: Map3DPoint, buried: Bool)] {
                across.map { z in
                    let bump = 0.5 * (1 - (z / edge) * (z / edge)) * min((x - front) / 2, 1)
                    return height(x, z, ridge(x) + bump, last: last)
                }
            }
            let a = line(overRows[row - 1], last: false), b = line(overRows[row], last: row == overRows.count - 1)
            for k in 1..<across.count { quad(a[k - 1], a[k], b[k], b[k - 1]) }
        }
    }

    /// The face through `corners`, turned to look toward `facing`.
    static func addFace(_ mesh: inout Map3DMesh, _ corners: [Map3DPoint], facing: Map3DPoint, color: UInt32, paint: Map3DPaint? = nil) {
        guard let normal = Map3DMesh.normal(of: corners) ?? Map3DMesh.normal(of: Array(corners.reversed())) else { return }
        let turned = normal.dot(facing) < 0 ? Array(corners.reversed()) : corners
        mesh.addQuad(turned[0], turned[1], turned[2], turned[3], color: color, paint: paint)
    }
}
