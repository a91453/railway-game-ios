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
        var portals: [RoadPortal] = []
        var taken = Set<Int>()
        for (index, one) in found.enumerated() where !taken.contains(index) {
            taken.insert(index)
            var point = one.point, into = one.into, paired = false
            if one.end.kind == .motorway, !one.end.isRamp,
               let other = found.indices.first(where: { other in
                   guard !taken.contains(other), found[other].end.kind == .motorway, !found[other].end.isRamp,
                         one.into.dot(found[other].into) >= 0.985 else { return false }
                   let gap = found[other].point - one.point, sideways = Map3DPoint(-one.into.z, 0, one.into.x)
                   return abs(gap.dot(one.into)) < 12 && (6...14).contains(abs(gap.dot(sideways)))
               }) {
                taken.insert(other)
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
            portals.append(RoadPortal(point: point, into: into, style: style, width: width, depth: depth))
        }
        return portals
    }

    /// Decision 611: each real road tunnel's portal in the region, in the
    /// city's full detail (``Target/near``): not drawn from afar, where the
    /// chunk's simplified city stands, as decision 460's levels draw the
    /// city.
    mutating func addRoadTunnels(_ ends: [Map3DBaseMap.TunnelEnd]) {
        let kept = target
        target = .near
        defer { target = kept }
        for portal in roadPortals(ends) {
            var built = Map3DMesh()
            addRoadPortal(portal, into: &built)
            mesh(at: portal.point) { $0.append(built) }
        }
    }

    /// The portal `portal`, its foot down to the drawn ground, the hillside
    /// over its top and the dark floor inside, in scene metres.
    mutating func addRoadPortal(_ portal: RoadPortal, into mesh: inout Map3DMesh) {
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
        Self.addPortalHillside(part, ground: ground, world: world, into: &mesh)
        // The dark floor over the drawn ground inside each bore, which
        // would show through the opening (the road's own surface stops at
        // the entrance).
        let start = part.front + (part.front < 0 ? 0 : Map3DRoadTunnelPortals.wallThickness)
        let floorColor = Map3DRoadTunnelPortals.liningShades[3]
        var floorMesh = Map3DMesh()
        let half = part.clearWidth / 2
        var x = start
        while x < part.innerEnd - 1e-3 {
            let next = min(x + 1, part.innerEnd)
            for centre in part.centres {
                let corners = [(x, centre - half), (x, centre + half), (next, centre + half), (next, centre - half)].map { x, z in
                    world(x, max(ground(x, z), 0) + Self.liningFloorLift, z)
                }
                Self.addFace(&floorMesh, corners, facing: .up, color: floorColor)
            }
            x = next
        }
        floorMesh.restyleVertices { ($0.nx, $0.ny, $0.nz) = (0, -1, 0) }
        mesh.append(floorMesh)
    }

    /// Decision 611 (#1885's review, 1): the hillside over the portal: from
    /// the head wall's top edge it climbs a metre and a little more over
    /// the bores, runs back past the lining and falls 1 : 1 to the ground
    /// behind and beside; beside the wings it falls from their tops. Under
    /// the drawn ground it sinks out of sight; its edges go into it.
    private static func addPortalHillside(_ part: Map3DRoadTunnelPortals.Part, ground: (Float, Float) -> Float,
                                   world: (Float, Float, Float) -> Map3DPoint, into mesh: inout Map3DMesh) {
        let front = part.front, top = part.top, wing = Map3DRoadTunnelPortals.wingLength
        let edge = part.outerHalfWidth + 0.45
        let back = part.innerEnd + 2, crest: Float = 1.2
        // The hill's height at `x` along over the head wall's line across.
        func ridge(_ x: Float) -> Float {
            if x < front { return top - 0.2 + (0.6 - (top - 0.2)) * min((front - x) / wing, 1) }
            if x <= back { return top + crest * min((x - front) / 2, 1) }
            return top + crest - (x - back)
        }
        let rows: [Float] = [front - wing, front - wing / 2, front] + stride(from: front + 2, through: back + top + crest + 1, by: 2).map { $0 }
        let reach: [Float] = [0, 1.5, 3, 5, 7.5, 10]
        func height(_ x: Float, _ z: Float, _ y: Float, last: Bool) -> Float {
            let g = ground(x, z)
            return last ? g - 0.5 : max(y, g - 0.3)
        }
        // Beside: each side's strip, out from the wing's or the hood's edge.
        for side: Float in [-1, 1] {
            func line(_ x: Float, _ row: Int) -> [Map3DPoint] {
                let out = x < front ? edge + Map3DRoadTunnelPortals.wingSplay * min((front - x) / wing, 1) : edge
                return reach.enumerated().map { k, d in
                    let z = side * (out + d)
                    let last = k == reach.count - 1 || row == 0 || row == rows.count - 1
                    return world(x, height(x, z, ridge(x) - d, last: last), z)
                }
            }
            for row in 1..<rows.count {
                let a = line(rows[row - 1], row - 1), b = line(rows[row], row)
                for k in 1..<reach.count {
                    Self.addFace(&mesh, [a[k - 1], a[k], b[k], b[k - 1]], facing: .up, color: Map3DPalette.embankment, paint: Self.bank)
                }
            }
        }
        // Over: from the head wall's top back, a little crest over the bores.
        let across = stride(from: -edge, through: edge + 1e-3, by: max(edge / 4, 1)).map { $0 }
        let overRows = rows.filter { $0 >= front }
        for row in 1..<overRows.count {
            func line(_ x: Float, last: Bool) -> [Map3DPoint] {
                across.map { z in
                    let bump = x >= front ? 0.5 * (1 - (z / edge) * (z / edge)) * min((x - front) / 2, 1) : 0
                    return world(x, height(x, z, ridge(x) + bump, last: last), z)
                }
            }
            let a = line(overRows[row - 1], last: false), b = line(overRows[row], last: row == overRows.count - 1)
            for k in 1..<across.count {
                Self.addFace(&mesh, [a[k - 1], a[k], b[k], b[k - 1]], facing: .up, color: Map3DPalette.embankment, paint: Self.bank)
            }
        }
    }

    /// The face through `corners`, turned to look toward `facing`.
    static func addFace(_ mesh: inout Map3DMesh, _ corners: [Map3DPoint], facing: Map3DPoint, color: UInt32, paint: Map3DPaint? = nil) {
        guard let normal = Map3DMesh.normal(of: corners) ?? Map3DMesh.normal(of: Array(corners.reversed())) else { return }
        let turned = normal.dot(facing) < 0 ? Array(corners.reversed()) : corners
        mesh.addQuad(turned[0], turned[1], turned[2], turned[3], color: color, paint: paint)
    }
}
