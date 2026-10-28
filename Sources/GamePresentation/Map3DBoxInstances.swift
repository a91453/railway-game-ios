import GameCore

// Decision 455: the simplified city's boxes (decision 238's `.far`: row
// houses, blocks of flats, offices, the houses along the real roads) kept
// as instances of one box rather than as vertices of their own, as
// mrdoob/slop-newyork (MIT) draws its city: each box is an instance of one
// 1 × 1 × 1 box (`js/buildings.js`). A box of ``Map3DMesh/addBox(base:forward:length:width:height:top:side:topPaint:frontPaint:flankPaint:capped:)``
// took 16–20 vertices of 40 bytes and 24–30 indices of 4 (736–920 bytes);
// an instance takes 88. The app's shader (`map3dBoxVertex`) makes the same
// corners, colours and texture places out of it that `addBox` laid, as
// ``vertices`` does here, where the tests compare them.

/// One box of the simplified city, as ``Map3DMesh/addBox(base:forward:length:width:height:top:side:topPaint:frontPaint:flankPaint:capped:)``
/// would lay it. Laid out as the app's shader reads it (`Map3DBoxInstance`
/// in `Map3DShaders.metal`): fourteen floats, five colours, six shorts,
/// 88 bytes.
public struct Map3DBoxInstance: Hashable, Sendable {
    /// The middle of its floor.
    public var x: Float
    public var y: Float
    public var z: Float
    /// The level way its front faces, one metre long.
    public var alongX: Float
    public var alongZ: Float
    /// Along its front's way, across it and up, in metres.
    public var length: Float
    public var width: Float
    public var height: Float
    /// The metres one repeat of its top's paint covers east and south;
    /// 0 with no paint (its texture places all 0).
    public var topWidth: Float
    public var topHeight: Float
    /// Where the right-hand corners (`u`) and the top corners (`v`) of
    /// its front and back fall in their layer; the left-hand and the
    /// ground corners at 0.
    public var frontU: Float
    public var frontV: Float
    /// The same of its two flanks.
    public var flankU: Float
    public var flankV: Float
    /// Each face's colour, in the look (decision 370) once its chunk is
    /// built: its top, then the sides in `addBox`'s order (front, right
    /// flank, back, left flank), each side shaded by the way it faces.
    public var topColor: UInt32
    public var frontColor: UInt32
    public var rightColor: UInt32
    public var backColor: UInt32
    public var leftColor: UInt32
    /// Each face's ``Map3DVertex/layer``, in the same order.
    public var topLayer: Int16
    public var frontLayer: Int16
    public var rightLayer: Int16
    public var backLayer: Int16
    public var leftLayer: Int16
    /// 1 when it has a top, 0 when another box stands on it.
    public var capped: Int16

    /// How much each side is shaded, in `addBox`'s order.
    static let shades: [Float] = [0.92, 0.80, 0.70, 0.86]

    /// The box `addBox` lays with these arguments (`along` its level front
    /// way, one metre long), or `nil` where it would lay none or where its
    /// front and back (or its flanks) would not take the same texture
    /// places (a count of bays rounding apart): that box stays vertices.
    init?(base: Map3DPoint, along: Map3DPoint, length: Float, width: Float, height: Float, top: UInt32, side: UInt32,
          topPaint: Map3DPaint?, frontPaint: Map3DPaint?, flankPaint: Map3DPaint?, capped: Bool, shaded: Bool = true) {
        guard length > 0, width > 0, height > 0, along.y == 0 else { return nil }
        let (corners, up) = Self.corners(base: base, along: along, length: length, width: width, height: height)
        // Each side's texture places as addQuad works them out: (0, 0) at
        // its first corner, (u, 0) at its second, (u, v) and (0, v) above.
        func places(_ from: Int, _ to: Int, _ paint: Map3DPaint?) -> (u: Float, v: Float)? {
            guard let paint else { return (0, 0) }
            let quad = [corners[from], corners[to], up[to], up[from]]
            guard let normal = Map3DMesh.normal(of: quad) else { return nil }
            let texture = paint.coordinates(quad, normal: normal)
            let (u, v) = (texture[1].u, texture[2].v)
            guard texture[0] == (0, 0), texture[1].v == 0, texture[2].u == u, texture[3] == (0, v) else { return nil }
            return (u, v)
        }
        func alike(_ a: (u: Float, v: Float), _ b: (u: Float, v: Float)) -> Bool {
            abs(a.u - b.u) <= 1e-4 * max(1, abs(a.u)) && abs(a.v - b.v) <= 1e-4 * max(1, abs(a.v))
        }
        guard let front = places(1, 0, frontPaint), let back = places(3, 2, frontPaint), alike(front, back),
              let right = places(2, 1, flankPaint), let left = places(0, 3, flankPaint), alike(right, left) else { return nil }
        x = base.x
        y = base.y
        z = base.z
        alongX = along.x
        alongZ = along.z
        self.length = length
        self.width = width
        self.height = height
        switch topPaint?.fit {
        case let .tile(width, height): (topWidth, topHeight) = (width, height)
        case let .bays(bay, _): (topWidth, topHeight) = (bay, bay)
        case nil: (topWidth, topHeight) = (0, 0)
        }
        (frontU, frontV) = front
        (flankU, flankV) = right
        topColor = top
        let shades = shaded ? Self.shades : [1, 1, 1, 1]
        frontColor = Map3DColor.shaded(side, shades[0])
        rightColor = Map3DColor.shaded(side, shades[1])
        backColor = Map3DColor.shaded(side, shades[2])
        leftColor = Map3DColor.shaded(side, shades[3])
        func layer(_ paint: Map3DPaint?) -> Int16 { Int16(paint?.layer ?? Map3DVertex.plain) }
        topLayer = layer(topPaint)
        frontLayer = layer(frontPaint)
        rightLayer = layer(flankPaint)
        backLayer = layer(frontPaint)
        leftLayer = layer(flankPaint)
        self.capped = capped ? 1 : 0
    }

    public var base: Map3DPoint { Map3DPoint(x, y, z) }
    public var along: Map3DPoint { Map3DPoint(alongX, 0, alongZ) }
    /// The triangles `addBox` laid for it: two to a face, the top only
    /// when ``capped``.
    public var triangleCount: Int { capped == 1 ? 10 : 8 }

    /// Its floor's corners and its top's, as `addBox` works them out: front
    /// left, front right, back right, back left.
    static func corners(base: Map3DPoint, along: Map3DPoint, length: Float, width: Float, height: Float)
        -> (ground: [Map3DPoint], up: [Map3DPoint]) {
        let across = Map3DPoint(-along.z, 0, along.x)
        let f = along * (length / 2), r = across * (width / 2), h = Map3DPoint(0, height, 0)
        let ground = [base + f - r, base + f + r, base - f + r, base - f - r]
        return (ground, ground.map { $0 + h })
    }

    /// Its top's corners, where decision 342's cones look for the city's
    /// tops (``Map3DSeeThrough/tops(column:row:of:boxes:)``).
    var topCorners: [Map3DPoint] {
        Self.corners(base: base, along: along, length: length, width: width, height: height).up
    }

    /// The smallest box holding it.
    var bounds: (min: Map3DPoint, max: Map3DPoint) {
        let (ground, up) = Self.corners(base: base, along: along, length: length, width: width, height: height)
        let all = ground + up
        return (all.dropFirst().reduce(all[0]) { Map3DPoint(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) },
                all.dropFirst().reduce(all[0]) { Map3DPoint(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) })
    }

    /// Each face's colour and layer changed by `change` (decision 370's
    /// look, ``Map3DLook/restyle(_:keeping:strength:)``).
    mutating func restyle(_ change: (UInt32, Int16) -> (UInt32, Int16)) {
        (topColor, topLayer) = change(topColor, topLayer)
        (frontColor, frontLayer) = change(frontColor, frontLayer)
        (rightColor, rightLayer) = change(rightColor, rightLayer)
        (backColor, backLayer) = change(backColor, backLayer)
        (leftColor, leftLayer) = change(leftColor, leftLayer)
    }

    // MARK: What the shader makes of it

    /// The vertices of one box face by face, as `map3dBoxVertex` makes
    /// them: four to a face, its top (only when ``capped``), then its
    /// sides in `addBox`'s order, each counter-clockwise from outside.
    /// The template the app draws every box with is ``faceCorners`` and
    /// ``indices``: a vertex's number tells its face and corner.
    public var vertices: [Map3DVertex] {
        (capped == 0 ? 1..<5 : 0..<5).flatMap { face in (0..<4).map { vertex(face: face, corner: $0) } }
    }

    /// The template's corners, four to a face (top, front, right, back,
    /// left): which end (+1 front, −1 back), which side (+1 right, −1
    /// left) and whether at the top (1) or on the ground (0); its texture
    /// place's `u` and `v` as 0 or 1 of the face's.
    static let faceCorners: [(end: Float, side: Float, up: Float, u: Float, v: Float)] = [
        // Top: front left, back left, back right, front right.
        (1, -1, 1, 0, 0), (-1, -1, 1, 0, 0), (-1, 1, 1, 0, 0), (1, 1, 1, 0, 0),
        // Front: front right, front left, then above them.
        (1, 1, 0, 0, 0), (1, -1, 0, 1, 0), (1, -1, 1, 1, 1), (1, 1, 1, 0, 1),
        // Right: back right, front right.
        (-1, 1, 0, 0, 0), (1, 1, 0, 1, 0), (1, 1, 1, 1, 1), (-1, 1, 1, 0, 1),
        // Back: back left, back right.
        (-1, -1, 0, 0, 0), (-1, 1, 0, 1, 0), (-1, 1, 1, 1, 1), (-1, -1, 1, 0, 1),
        // Left: front left, back left.
        (1, -1, 0, 0, 0), (-1, -1, 0, 1, 0), (-1, -1, 1, 1, 1), (1, -1, 1, 0, 1),
    ]

    /// The template's triangles: two to a face, as `addQuad` lays them.
    public static let indices: [UInt16] = (0..<5).flatMap { face -> [UInt16] in
        let base = UInt16(face * 4)
        return [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// Corner `corner` (0–3) of face `face` (0 its top, then front, right,
    /// back, left), as the shader works it out.
    func vertex(face: Int, corner: Int) -> Map3DVertex {
        let template = Self.faceCorners[face * 4 + corner]
        let along = along, across = Map3DPoint(-alongZ, 0, alongX)
        let position = base + along * (template.end * length * 0.5) + across * (template.side * width * 0.5) + Map3DPoint(0, template.up * height, 0)
        let normals = [Map3DPoint.up, along, across, -along, -across]
        let colors = [topColor, frontColor, rightColor, backColor, leftColor]
        let layers = [topLayer, frontLayer, rightLayer, backLayer, leftLayer]
        let place: (u: Float, v: Float)
        switch face {
        case 0: place = topWidth > 0 ? (position.x / topWidth, position.z / topHeight) : (0, 0)
        case 1, 3: place = (template.u * frontU, template.v * frontV)
        default: place = (template.u * flankU, template.v * flankV)
        }
        return Map3DVertex(position, normal: normals[face], color: colors[face], u: place.u, v: place.v, layer: Float(layers[face]))
    }

    /// The boxes as one mesh, as the shader draws them (the app before
    /// it drew instances, and the previews).
    public static func mesh(_ boxes: [Map3DBoxInstance]) -> Map3DMesh {
        var vertices: [Map3DVertex] = [], indices: [UInt32] = []
        vertices.reserveCapacity(boxes.count * 20)
        indices.reserveCapacity(boxes.count * 30)
        for box in boxes {
            let first = UInt32(vertices.count)
            let drawn = box.vertices
            vertices += drawn
            for face in 0..<UInt32(drawn.count / 4) {
                let base = first + face * 4
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            }
        }
        return Map3DMesh(vertices: vertices, indices: indices)
    }
}
