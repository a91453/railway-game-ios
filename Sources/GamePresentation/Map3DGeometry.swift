import GameCore

// The native 3D map's geometry (ARCHITECTURE decision 229): plain arrays of
// vertices and triangles worked out from the world, which the app hands to
// Metal as they are. Nothing here draws or touches a GPU, so it runs and is
// tested on Linux; nothing is saved or written back.
//
// Space: metres, x east, y up, z south (the world's y), measured from an
// origin the scene picks (``Map3DScene/origin``) so a map 500 km wide keeps
// its precision in `Float`. Right-handed: x × y = z.

/// One corner of a triangle: where it is, which way its face looks, its
/// colour and its texture. Laid out as Metal reads it: 40 bytes, three
/// floats of position at 0, three of normal at 12, four bytes of colour
/// (red first) at 24, and three floats of texture at 28: where in its
/// layer (`u`, `v`, in repeats) and the layer (decision 231).
public struct Map3DVertex: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var nx: Float
    public var ny: Float
    public var nz: Float
    /// Red in the low byte, then green, blue and alpha.
    public var color: UInt32
    public var u: Float
    public var v: Float
    /// The ``Map3DSurface`` layer, or ``Map3DVertex/plain`` for the
    /// colour alone. Decision 242: plus 64 × (its material's layer + 1)
    /// when the face has a material (``Map3DPaint/detail``).
    public var layer: Float

    /// No texture: the colour alone.
    public static let plain: Float = -1
    /// No texture, and lit from within at night (a street light's head):
    /// the shader adds its colour as light, as much as the city's lights
    /// are on (``Map3DLighting/lights``).
    public static let glowing: Float = -2
    /// Decision 356: no texture, and water: the shader tilts it with
    /// ripples and mirrors the sky in it (``Map3DReflection``).
    public static let water: Float = -3
    /// Decision 370: no texture, and a road's carriageway: the shader lights
    /// it with its street lights once the sky is dark (``Map3DLook``).
    public static let road: Float = -11
    /// Decision 370 (step 2): the landmarks' line patterns, drawn by the
    /// shader along the vertex's `u`, `v` (in metres): a curtain wall's
    /// mullions and floors,
    public static let curtainGlass: Float = -5
    /// a roof's tile rows,
    public static let roofTiles: Float = -8
    /// and a wall's floor lines (none on a roof).
    public static let floorLines: Float = -9
    /// Taipei 101's glass: floor lines as ``floorLines`` by day; after
    /// dark an even glow, brighter up to the top of each section, its `v`
    /// the metres below that top (none of the city's random windows).
    public static let towerGlass: Float = -10
    /// No texture, and lit warm after dark as a floodlit ledge is.
    public static let floodlit: Float = -12
    /// Decision 450: a train's window glass, which mirrors the sky and
    /// glints in the sun (``Map3DTrainMaterial``); its `u` the shade
    /// decision 439 baked into it (a shut-in pane mirrors less).
    public static let trainGlass: Float = -13
    /// Decision 450: a stainless train's body, its sheen and a soft mirror
    /// of the sky tinted by its own colour; `u` as ``trainGlass``.
    public static let trainSteel: Float = -14
    /// Decision 450: a train's window glass that is also lit from within at
    /// night (``glowing`` and ``trainGlass`` at once).
    public static let trainGlassLit: Float = -15

    /// Whether the vertex is lit from within at night.
    public var glows: Bool { (layer < -1.5 && layer > -2.5) || (layer < -14.5 && layer > -15.5) }
    /// Decision 450: whether the vertex is a train's glass or stainless body.
    public var isTrainMaterial: Bool { layer < -12.5 && layer > -15.5 }
    /// Decision 356: whether the vertex is water.
    public var isWater: Bool { layer < -2.5 && layer > -3.5 }

    public init(_ position: Map3DPoint, normal: Map3DPoint, color: UInt32, u: Float = 0, v: Float = 0, layer: Float = Map3DVertex.plain) {
        x = position.x
        y = position.y
        z = position.z
        nx = normal.x
        ny = normal.y
        nz = normal.z
        self.color = color
        self.u = u
        self.v = v
        self.layer = layer
    }

    public var position: Map3DPoint { Map3DPoint(x, y, z) }

    /// The surface it is painted with, or `nil` for the colour alone.
    public var surface: Map3DSurface? { layer < 0 ? nil : Map3DSurface(rawValue: Int(layer) % Map3DPaint.detailStep) }

    /// Decision 242: the material under its surface, or `nil`.
    public var detail: Map3DSurface? {
        layer < 0 ? nil : Map3DSurface(rawValue: Int(layer) / Map3DPaint.detailStep - 1)
    }
}

/// Decision 231: the textures of the 3D map, one layer each of the app's
/// `Map3DSurfaces.png`, in this order. Each is made from the reference
/// asset library's images, changed and mixed (the owner, 2026-10-15), and
/// tints with the vertex's colour where its mask says so: walls keep the
/// palette's colours, glass and shutters keep their own.
public enum Map3DSurface: Int, CaseIterable, Sendable {
    /// Soft spots on the ground and in parks.
    case grass
    /// Platforms and plazas: square pavers.
    case paving
    /// Track bed: gravel, a concrete sleeper every 0.6 m, made for a 5 m
    /// bed (the sleepers 2.1 m long in its middle).
    case ballast
    /// Viaducts, piers, portals, platform walls: formwork joints.
    case concrete
    /// Flat roofs.
    case roof
    /// Blank walls: the sides of row houses.
    case plaster
    /// A 透天厝 floor: a window behind an iron grille, an awning, an air
    /// conditioner.
    case homeWindows
    /// A 透天厝 floor with a balcony.
    case homeBalcony
    /// A shop's ground floor: signboard, glass, goods.
    case shopfront
    /// A ground floor closed by a rolling shutter (鐵捲門).
    case shutter
    /// A bay of a block of flats: one window.
    case flatWindows
    /// A bay of an office's curtain wall.
    case officeGlass
    /// Corrugated metal: sheds and canopies.
    case metalSheet
    /// Shops of four trades (decision 231, continued, the library's second
    /// batch): a glasses shop, a phone shop, an eatery, a tea shop, each
    /// with its own interior and awning.
    case shopOptical
    case shopPhone
    case shopEatery
    case shopTea
    /// A bay of a block of flats with its blinds half down.
    case flatBlinds
    /// Decision 242: the materials, each a fine pattern in grey around
    /// mid grey that the shader lays over a wall in the scene's metres
    /// (``Map3DSurface/detailRepeat``) and fades out with distance.
    /// 清水模: fair-faced concrete, 1.8 × 0.9 m panels with six tie holes.
    case formConcrete
    /// 二丁掛: Taiwan's long facing tiles in running bond.
    case brickTile
    /// 馬賽克磚: small square tiles, each its own shade.
    case mosaicTile
    /// 洗石子: washed grit, a dividing groove every 0.9 m.
    case terrazzo
    /// Decision 355: the road's paint, on asphalt that takes the road's
    /// colour. A zebra crossing (斑馬線): one bar and its gap, as wide
    /// as each other, across `u`, the bars running along the traffic
    /// (`v`); decision 447 lays a repeat on 0.8 m (355: 0.9 m).
    case crosswalk
    /// Decision 355: two lane arrows on 1.7 × 5 m, the far end (the way
    /// the traffic goes) at `v` 0: through in `u` 0–0.5, through and left
    /// in 0.5–1.
    case laneArrows

    /// The shops a ground floor may be, and the windows a block of flats
    /// may have; one is picked by where it stands.
    public static let shops: [Map3DSurface] = [.shopfront, .shopOptical, .shopPhone, .shopEatery, .shopTea]
    public static let flats: [Map3DSurface] = [.flatWindows, .flatBlinds]

    /// The side of each layer in the texture, in pixels.
    public static let side = 256

    /// Decision 242: the materials, in the order the shader's
    /// `detailRepeat` lists them.
    public static let materials: [Map3DSurface] = [.formConcrete, .brickTile, .mosaicTile, .terrazzo]

    /// How many metres one repeat of a material covers: the concrete's
    /// panels 1.8 × 0.9 m, the tiles at their real size.
    public var detailRepeat: Float {
        self == .formConcrete ? 3.6 : 1.8
    }
}

/// How a face takes its ``Map3DSurface``: how many metres one repeat
/// covers, or how many whole bays and floors the face holds.
public struct Map3DPaint: Hashable, Sendable {
    public enum Fit: Hashable, Sendable {
        /// One repeat every `width` metres across and `height` up. A face
        /// looking up repeats over the map's east and south, so tops side
        /// by side run on without a seam.
        case tile(width: Float, height: Float)
        /// Whole bays across the face, as many `bay`-metre bays as fit and
        /// at least one, and `floors` up it: windows meet the corners and
        /// the floors.
        case bays(bay: Float, floors: Int)
    }

    public var surface: Map3DSurface
    public var fit: Fit
    /// Decision 242: the material the wall is made of, under its windows
    /// and doors (where the surface's mask tints), or `nil`.
    public var detail: Map3DSurface?

    public init(_ surface: Map3DSurface, _ fit: Fit, detail: Map3DSurface? = nil) {
        self.surface = surface
        self.fit = fit
        self.detail = detail
    }

    /// The same paint over `material`.
    public func on(_ material: Map3DSurface?) -> Map3DPaint {
        Map3DPaint(surface, fit, detail: material)
    }

    /// What a vertex's ``Map3DVertex/layer`` holds: the surface, and the
    /// material in steps of ``detailStep``.
    public var layer: Float {
        Float(surface.rawValue + (detail.map { ($0.rawValue + 1) * Self.detailStep } ?? 0))
    }

    /// Decision 242: the material's place in a vertex's layer.
    public static let detailStep = 64

    public static func tile(_ surface: Map3DSurface, _ size: Float) -> Map3DPaint {
        Map3DPaint(surface, .tile(width: size, height: size))
    }

    public static func bays(_ surface: Map3DSurface, bay: Float, floors: Int) -> Map3DPaint {
        Map3DPaint(surface, .bays(bay: bay, floors: max(1, floors)))
    }

    /// Where each of `corners` (one flat face, facing `normal`) falls in
    /// the layer.
    func coordinates(_ corners: [Map3DPoint], normal: Map3DPoint) -> [(u: Float, v: Float)] {
        if abs(normal.y) > 0.7 {
            let (width, height): (Float, Float)
            switch fit {
            case let .tile(w, h): (width, height) = (w, h)
            case let .bays(bay, _): (width, height) = (bay, bay)
            }
            return corners.map { ($0.x / width, $0.z / height) }
        }
        // A wall: across it to the right as seen from outside, and up.
        let right = Map3DPoint.up.cross(normal).normalized ?? Map3DPoint(1, 0, 0)
        let across = corners.map { $0.dot(right) }
        let low = across.min() ?? 0, bottom = corners.map(\.y).min() ?? 0
        switch fit {
        case let .tile(width, height):
            return zip(across, corners).map { (($0 - low) / width, ($1.y - bottom) / height) }
        case let .bays(bay, floors):
            let wide = (across.max() ?? 0) - low, high = (corners.map(\.y).max() ?? 0) - bottom
            let count = max(1, (wide / bay).rounded())
            return zip(across, corners).map {
                (wide > 0 ? ($0 - low) / wide * count : 0, high > 0 ? ($1.y - bottom) / high * Float(floors) : 0)
            }
        }
    }
}

/// A point or direction in the 3D map's space, in metres.
public struct Map3DPoint: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Map3DPoint(0, 0, 0)
    public static let up = Map3DPoint(0, 1, 0)

    public static func + (a: Map3DPoint, b: Map3DPoint) -> Map3DPoint { Map3DPoint(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Map3DPoint, b: Map3DPoint) -> Map3DPoint { Map3DPoint(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Map3DPoint, s: Float) -> Map3DPoint { Map3DPoint(a.x * s, a.y * s, a.z * s) }
    public static prefix func - (a: Map3DPoint) -> Map3DPoint { Map3DPoint(-a.x, -a.y, -a.z) }

    public func dot(_ b: Map3DPoint) -> Float { x * b.x + y * b.y + z * b.z }

    public func cross(_ b: Map3DPoint) -> Map3DPoint {
        Map3DPoint(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }

    public var length: Float { dot(self).squareRoot() }

    /// The same direction one metre long, or `nil` for no direction.
    public var normalized: Map3DPoint? {
        let size = length
        return size > 0 && size.isFinite ? self * (1 / size) : nil
    }
}

/// A colour as the vertices carry it.
public enum Map3DColor {
    /// `0xRRGGBB`, opaque.
    public static func rgb(_ hex: UInt32) -> UInt32 {
        let red = (hex >> 16) & 0xFF, green = (hex >> 8) & 0xFF, blue = hex & 0xFF
        return red | green << 8 | blue << 16 | 0xFF << 24
    }

    public static func rgb(_ color: PopTravel.RGB) -> UInt32 {
        UInt32(color.red) | UInt32(color.green) << 8 | UInt32(color.blue) << 16 | 0xFF << 24
    }

    /// `color` with each channel times `factor` (0–1): a darker side.
    public static func shaded(_ color: UInt32, _ factor: Float) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let value = Float((color >> shift) & 0xFF) * min(max(factor, 0), 1)
            return UInt32(value.rounded()) << shift
        }
        return channel(0) | channel(8) | channel(16) | (color & 0xFF00_0000)
    }
}

/// Triangles in one buffer: what one draw call draws.
public struct Map3DMesh: Sendable {
    public private(set) var vertices: [Map3DVertex] = []
    /// Three to a triangle, counter-clockwise seen from outside.
    public private(set) var indices: [UInt32] = []
    /// Decision 455: the boxes ``addBox(base:forward:length:width:height:top:side:topPaint:frontPaint:flankPaint:capped:)``
    /// kept as instances of one box instead of as vertices, while
    /// ``collectsBoxes`` (the simplified city's, ``Map3DScene/Chunk/farBoxes``).
    var boxes: [Map3DBoxInstance] = []
    var collectsBoxes = false

    public init() {}

    /// The vertices and their triangles as they are (decision 370's
    /// landmarks, built in their own metres and then stood in place).
    init(vertices: [Map3DVertex], indices: [UInt32]) {
        precondition(indices.allSatisfy { Int($0) < vertices.count })
        self.vertices = vertices
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    /// The smallest box holding every vertex, or `nil` when empty.
    public var bounds: (min: Map3DPoint, max: Map3DPoint)? {
        guard let first = vertices.first else { return nil }
        var low = first.position, high = first.position
        for vertex in vertices {
            low = Map3DPoint(min(low.x, vertex.x), min(low.y, vertex.y), min(low.z, vertex.z))
            high = Map3DPoint(max(high.x, vertex.x), max(high.y, vertex.y), max(high.z, vertex.z))
        }
        return (low, high)
    }

    /// One triangle of the three vertices as they are, each keeping its own
    /// colour.
    public mutating func appendTriangle(_ corners: [Map3DVertex]) {
        precondition(corners.count == 3)
        let base = UInt32(vertices.count)
        vertices += corners
        indices += [base, base + 1, base + 2]
    }

    /// Decision 370: each vertex changed in place by `change`, the
    /// triangles as they are (``Map3DLook``).
    mutating func restyleVertices(_ change: (inout Map3DVertex) -> Void) {
        for index in vertices.indices { change(&vertices[index]) }
    }

    public mutating func append(_ other: Map3DMesh) {
        let base = UInt32(vertices.count)
        vertices += other.vertices
        indices += other.indices.map { $0 + base }
        boxes += other.boxes
    }

    /// Decision 321: `other` built with +x its front, +y up and +z its
    /// right, stood on `base` with its front along level `forward`.
    mutating func append(_ other: Map3DMesh, at base: Map3DPoint, forward: Map3DPoint) {
        let along = Map3DPoint(forward.x, 0, forward.z).normalized ?? Map3DPoint(1, 0, 0)
        let right = along.cross(.up)
        func turned(_ p: Map3DPoint) -> Map3DPoint { along * p.x + Map3DPoint(0, p.y, 0) + right * p.z }
        let start = UInt32(vertices.count)
        vertices += other.vertices.map { v in
            Map3DVertex(base + turned(v.position), normal: turned(Map3DPoint(v.nx, v.ny, v.nz)), color: v.color, u: v.u, v: v.v, layer: v.layer)
        }
        indices += other.indices.map { $0 + start }
    }

    /// A flat four-cornered face, `a b c d` counter-clockwise seen from
    /// the side it faces, painted with `paint` when there is one.
    public mutating func addQuad(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint, _ d: Map3DPoint, color: UInt32, paint: Map3DPaint? = nil) {
        let corners = [a, b, c, d]
        guard let normal = Self.normal(of: corners) else { return }
        addQuad(corners, normal: normal, color: color, layer: paint.map { $0.layer },
                texture: paint?.coordinates(corners, normal: normal))
    }

    /// Decision 375: a convex polygon as a fan round its first corner,
    /// lit as facing `normal`.
    public mutating func addFan(_ corners: [Map3DPoint], normal: Map3DPoint, color: UInt32) {
        guard corners.count >= 3 else { return }
        let base = UInt32(vertices.count)
        for corner in corners { vertices.append(Map3DVertex(corner, normal: normal, color: color, u: 0, v: 0, layer: Map3DVertex.plain)) }
        for index in 1..<UInt32(corners.count - 1) { indices += [base, base + index, base + index + 1] }
    }

    /// Triangles lying on the ground (decision 234): `triangles` index
    /// `points`, three to a triangle in either turn, each turned to face up
    /// and painted with `paint` as a top is.
    public mutating func addFlat(_ points: [Map3DPoint], triangles: [Int], color: UInt32, paint: Map3DPaint? = nil) {
        let layer = paint.map { $0.layer } ?? Map3DVertex.plain
        var index = 0
        while index + 2 < triangles.count {
            var a = points[triangles[index]], b = points[triangles[index + 1]], c = points[triangles[index + 2]]
            index += 3
            guard var normal = (b - a).cross(c - a).normalized else { continue }
            if normal.y < 0 {
                swap(&b, &c)
                normal = normal * -1
            }
            let corners = [a, b, c]
            let texture = paint?.coordinates(corners, normal: normal)
            let base = UInt32(vertices.count)
            for (at, corner) in corners.enumerated() {
                let place: (u: Float, v: Float) = texture?[at] ?? (0, 0)
                vertices.append(Map3DVertex(corner, normal: normal, color: color, u: place.u, v: place.v, layer: layer))
            }
            indices += [base, base + 1, base + 2]
        }
    }

    /// Decision 235: a flat face through `corners` (three or more, counter-clockwise seen
    /// from the side it faces), cut as a fan from the first.
    public mutating func addFacet(_ corners: [Map3DPoint], color: UInt32, paint: Map3DPaint? = nil) {
        guard corners.count >= 3, let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { return }
        let layer = paint.map { $0.layer } ?? Map3DVertex.plain
        let texture = paint?.coordinates(corners, normal: normal)
        let base = UInt32(vertices.count)
        for (index, corner) in corners.enumerated() {
            let place: (u: Float, v: Float) = texture?[index] ?? (0, 0)
            vertices.append(Map3DVertex(corner, normal: normal, color: color, u: place.u, v: place.v, layer: layer))
        }
        for index in 1..<UInt32(corners.count - 1) {
            indices += [base, base + index, base + index + 1]
        }
    }

    /// The way a flat face `a b c d` (counter-clockwise seen from outside)
    /// looks, or `nil` when it has no area.
    static func normal(of corners: [Map3DPoint]) -> Map3DPoint? {
        (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized
            ?? (corners[2] - corners[1]).cross(corners[0] - corners[1]).normalized
    }

    private mutating func addQuad(_ corners: [Map3DPoint], normal: Map3DPoint, color: UInt32, layer: Float?, texture: [(u: Float, v: Float)]?) {
        let base = UInt32(vertices.count)
        for (index, corner) in corners.enumerated() {
            let place: (u: Float, v: Float) = texture?[index] ?? (0, 0)
            vertices.append(Map3DVertex(corner, normal: normal, color: color, u: place.u, v: place.v, layer: layer ?? Map3DVertex.plain))
        }
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// A box standing on `base` (the middle of its floor), `length` along
    /// `forward` (a level direction), `width` across it and `height` up;
    /// the top in `top`, the sides in `side` shaded by the way they face.
    /// No floor: nothing looks at it from below; no top either when it is
    /// not `capped` (a lower part another box stands on). Decision 231:
    /// painted on top with `topPaint`, on the front and back (facing along
    /// `forward`) with `frontPaint`, and on the two flanks with
    /// `flankPaint`. Decision 455: every side in `side` itself when not
    /// `shaded` (a real building's walls).
    public mutating func addBox(
        base: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float, height: Float,
        top: UInt32, side: UInt32, topPaint: Map3DPaint? = nil, frontPaint: Map3DPaint? = nil, flankPaint: Map3DPaint? = nil,
        capped: Bool = true, shaded: Bool = true
    ) {
        guard length > 0, width > 0, height > 0,
              let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
        if collectsBoxes, let box = Map3DBoxInstance(base: base, along: along, length: length, width: width, height: height, top: top, side: side,
                                                     topPaint: topPaint, frontPaint: frontPaint, flankPaint: flankPaint, capped: capped,
                                                     shaded: shaded) {
            boxes.append(box)
            return
        }
        let across = Map3DPoint(-along.z, 0, along.x) // to the right of `along`, seen from above
        let f = along * (length / 2), r = across * (width / 2), h = Map3DPoint(0, height, 0)
        let corners = [base + f - r, base + f + r, base - f + r, base - f - r] // front left, front right, back right, back left
        let up = corners.map { $0 + h }
        if capped { addQuad(up[0], up[3], up[2], up[1], color: top, paint: topPaint) }
        // Each side, counter-clockwise from outside: ground, ground, top, top.
        let sides: [(Int, Int, Float)] = [(1, 0, 0.92), (2, 1, 0.80), (3, 2, 0.70), (0, 3, 0.86)]
        for (index, (from, to, shade)) in sides.enumerated() {
            addQuad(corners[from], corners[to], up[to], up[from], color: shaded ? Map3DColor.shaded(side, shade) : side,
                    paint: index.isMultiple(of: 2) ? frontPaint : flankPaint)
        }
    }

    /// A strip `width` wide following `line` at its heights plus `lift`,
    /// facing up: ballast, a rail, a deck. Its sides along the line hang
    /// `depth` down when `depth` is more than 0. Decision 231: the top
    /// painted with `topPaint` along the line, the middle of its width
    /// at the middle of the layer (so a 3.4 m bed shows the middle of the
    /// ballast's 5 m), and the sides with `sidePaint`.
    public mutating func addRibbon(
        along line: [Map3DPoint], width: Float, offset: Float = 0, lift: Float = 0, depth: Float = 0, top: UInt32, side: UInt32? = nil,
        topPaint: Map3DPaint? = nil, sidePaint: Map3DPaint? = nil
    ) {
        guard line.count > 1 else { return }
        let across = Self.acrossDirections(line)
        let half = width / 2
        let left = line.indices.map { line[$0] + across[$0] * (offset - half) + Map3DPoint(0, lift, 0) }
        let right = line.indices.map { line[$0] + across[$0] * (offset + half) + Map3DPoint(0, lift, 0) }
        // How far along the line each point is, in metres.
        var travelled: [Float] = [0]
        for index in 1..<line.count {
            let step = line[index] - line[index - 1]
            travelled.append(travelled[index - 1] + Map3DPoint(step.x, 0, step.z).length)
        }
        func repeats(_ paint: Map3DPaint) -> (across: Float, along: Float) {
            switch paint.fit {
            case let .tile(width, height): (width, height)
            case let .bays(bay, _): (bay, bay)
            }
        }
        let topLayer = topPaint.map { $0.layer }, sideLayer = sidePaint.map { $0.layer }
        for index in 0..<(line.count - 1) {
            let corners = [left[index], right[index], right[index + 1], left[index + 1]]
            if let normal = Self.normal(of: corners) {
                var texture: [(u: Float, v: Float)]?
                if let topPaint {
                    let size = repeats(topPaint)
                    let low = 0.5 - half / size.across, high = 0.5 + half / size.across
                    let start = travelled[index] / size.along, end = travelled[index + 1] / size.along
                    texture = [(low, start), (high, start), (high, end), (low, end)]
                }
                addQuad(corners, normal: normal, color: top, layer: topLayer, texture: texture)
            }
            if depth > 0, let side {
                let drop = Map3DPoint(0, -depth, 0)
                var rightTexture: [(u: Float, v: Float)]?, leftTexture: [(u: Float, v: Float)]?
                if let sidePaint {
                    let size = repeats(sidePaint)
                    let start = travelled[index] / size.across, end = travelled[index + 1] / size.across, up = depth / size.along
                    rightTexture = [(end, up), (start, up), (start, 0), (end, 0)]
                    leftTexture = [(start, up), (end, up), (end, 0), (start, 0)]
                }
                let rightSide = [corners[2], corners[1], corners[1] + drop, corners[2] + drop]
                let leftSide = [corners[0], corners[3], corners[3] + drop, corners[0] + drop]
                if let normal = Self.normal(of: rightSide) {
                    addQuad(rightSide, normal: normal, color: Map3DColor.shaded(side, 0.82), layer: sideLayer, texture: rightTexture)
                }
                if let normal = Self.normal(of: leftSide) {
                    addQuad(leftSide, normal: normal, color: Map3DColor.shaded(side, 0.72), layer: sideLayer, texture: leftTexture)
                }
            }
        }
    }

    // MARK: Ground shadows (decision 232)

    /// The four corners, seen from above, of a footprint standing on
    /// `centre`, `length` along `forward` and `width` across it, in
    /// ``addBox(base:forward:length:width:height:top:side:topPaint:frontPaint:flankPaint:capped:)``'s
    /// order (front left, front right, back right, back left), at
    /// `centre`'s height.
    public static func footprint(centre: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float) -> [Map3DPoint] {
        let along = Map3DPoint(forward.x, 0, forward.z).normalized ?? Map3DPoint(0, 0, -1)
        let across = Map3DPoint(-along.z, 0, along.x)
        let f = along * (length / 2), r = across * (width / 2)
        return [centre + f - r, centre + f + r, centre - f + r, centre - f - r]
    }

    /// A soft shadow on the ground: `darkness` (0–1) over the four
    /// `inner` corners, fading to nothing at the four `outer` ones (the
    /// same corners pushed out). Black, its darkness in the colour's
    /// alpha: the app draws it over what is already drawn.
    public mutating func addShadow(inner: [Map3DPoint], outer: [Map3DPoint], darkness: Float) {
        precondition(inner.count == 4 && outer.count == 4)
        let base = UInt32(vertices.count)
        let dark = Map3DShadow.color(darkness), clear = Map3DShadow.color(0)
        for corner in inner { vertices.append(Map3DVertex(corner, normal: .up, color: dark)) }
        for corner in outer { vertices.append(Map3DVertex(corner, normal: .up, color: clear)) }
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        for i in UInt32(0)..<4 {
            let j = (i + 1) % 4
            indices += [base + i, base + 4 + i, base + 4 + j, base + i, base + 4 + j, base + j]
        }
    }

    /// Decision 334: a flat band round a train standing along `line` (its
    /// rails, front to back): beside it on both sides and across both
    /// ends, ``Map3DTrains/ringGap`` clear of its cars, lit from within at
    /// night.
    public mutating func addRing(round line: [Map3DPoint]) {
        guard line.count > 1, let front = (line[0] - line[1]).normalized,
              let back = (line[line.count - 1] - line[line.count - 2]).normalized else { return }
        let start = vertices.count
        let width = Map3DTrains.ringWidth
        let out = Map3DTrains.carWidth / 2 + Map3DTrains.ringGap + width / 2
        let colour = Map3DColor.rgb(Map3DTrains.ringColour)
        let lift = Map3DTrains.ringLift
        // The sides run on past the ends to meet the end bands.
        let reach = Map3DTrains.ringGap + width
        let stretched = [line[0] + front * reach] + line + [line[line.count - 1] + back * reach]
        addRibbon(along: stretched, width: width, offset: out, lift: lift, top: colour)
        addRibbon(along: stretched, width: width, offset: -out, lift: lift, top: colour)
        for (end, away) in [(line[0], front), (line[line.count - 1], back)] {
            let across = Map3DPoint(-away.z, 0, away.x)
            let middle = end + away * (Map3DTrains.ringGap + width / 2)
            addRibbon(along: [middle - across * out, middle + across * out], width: width, lift: lift, top: colour)
        }
        makeGlowing(from: start)
    }

    /// The vertices added since `start` lit from within at night
    /// (``Map3DVertex/glowing``), keeping their colour.
    public mutating func makeGlowing(from start: Int) {
        for index in start..<vertices.count { vertices[index].layer = Map3DVertex.glowing }
    }

    /// Decision 356: the vertices added since `start` water
    /// (``Map3DVertex/water``), keeping their colour.
    public mutating func makeWater(from start: Int) {
        for index in start..<vertices.count { vertices[index].layer = Map3DVertex.water }
    }

    /// Night light on the ground (a street light's pool): `colour` at
    /// `strength` (0–1) at `centre`, fading to nothing at the `ring`
    /// round it. Drawn with the shadows: a colour in a shadow vertex is
    /// light, shown as much as the city's lights are on, where a shadow
    /// is black.
    public mutating func addPool(centre: Map3DPoint, ring: [Map3DPoint], colour: UInt32, strength: Float) {
        guard ring.count >= 3 else { return }
        let base = UInt32(vertices.count)
        let rgb = colour & 0x00FF_FFFF
        vertices.append(Map3DVertex(centre, normal: .up, color: rgb | UInt32((min(max(strength, 0), 1) * 255).rounded()) << 24))
        for point in ring { vertices.append(Map3DVertex(point, normal: .up, color: rgb)) }
        let count = UInt32(ring.count)
        for index in UInt32(0)..<count {
            indices += [base, base + 1 + (index + 1) % count, base + 1 + index]
        }
    }

    /// A soft shadow along a line: each of `rows` is four points across
    /// it (the outer left, the left, the right, the outer right), the
    /// middle two `darkness`, the outer two clear.
    public mutating func addShadowStrip(_ rows: [[Map3DPoint]], darkness: Float) {
        guard rows.count > 1 else { return }
        let dark = Map3DShadow.color(darkness), clear = Map3DShadow.color(0)
        let base = UInt32(vertices.count)
        for row in rows {
            precondition(row.count == 4)
            for (index, point) in row.enumerated() {
                vertices.append(Map3DVertex(point, normal: .up, color: index == 0 || index == 3 ? clear : dark))
            }
        }
        for row in UInt32(0)..<UInt32(rows.count - 1) {
            for strip in UInt32(0)..<3 {
                let a = base + row * 4 + strip, b = a + 1, c = a + 5, d = a + 4
                indices += [a, b, c, a, c, d]
            }
        }
    }

    /// The level direction to the right of `line` at each point, averaged
    /// over the pieces on either side (a mitre, without lengthening it).
    static func acrossDirections(_ line: [Map3DPoint]) -> [Map3DPoint] {
        func level(_ a: Map3DPoint, _ b: Map3DPoint) -> Map3DPoint? {
            Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized
        }
        var pieces: [Map3DPoint?] = []
        for index in 0..<(line.count - 1) { pieces.append(level(line[index], line[index + 1])) }
        var fallback = pieces.compactMap { $0 }.first ?? Map3DPoint(0, 0, -1)
        return line.indices.map { index in
            let before = index > 0 ? pieces[index - 1] : nil, after = index < pieces.count ? pieces[index] : nil
            let direction = ((before ?? after ?? fallback) + (after ?? before ?? fallback)).normalized ?? fallback
            fallback = direction
            return Map3DPoint(-direction.z, 0, direction.x)
        }
    }
}

/// Decision 232: the soft shadows on the ground under what stands on it,
/// so buildings, trees, viaducts and trains sit on the map instead of
/// floating over it. They are drawn after everything else, darkening it
/// by their alpha; no shadow map, and the sun's way does not move them.
public enum Map3DShadow {
    /// How far over the ground a shadow lies, in metres: clear of the
    /// ground (and the plazas 0.03 over it) at the farthest the camera
    /// goes, and over the real map's cover and roads (0.04–0.36,
    /// decision 234), under the track's bed (``Map3DScene/railLift``).
    public static let lift: Float = 0.4

    /// Black with `darkness` (0–1) as its alpha.
    public static func color(_ darkness: Float) -> UInt32 {
        UInt32((min(max(darkness, 0), 1) * 255).rounded()) << 24
    }

    /// How dark shadows are under `lighting`, as a share of their own
    /// darkness: full by day, fainter at night when there is no sun to
    /// cast them.
    public static func strength(_ lighting: Map3DLighting) -> Float {
        1 - 0.6 * min(max(lighting.night, 0), 1)
    }
}

/// A 4 × 4 matrix in Metal's order: column by column.
public struct Map3DMatrix: Hashable, Sendable {
    public var columns: [Float]

    public init(columns: [Float]) {
        precondition(columns.count == 16)
        self.columns = columns
    }

    public static let identity = Map3DMatrix(columns: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    public subscript(row: Int, column: Int) -> Float {
        get { columns[column * 4 + row] }
        set { columns[column * 4 + row] = newValue }
    }

    public static func * (a: Map3DMatrix, b: Map3DMatrix) -> Map3DMatrix {
        var result = [Float](repeating: 0, count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a[row, k] * b[k, column] }
                result[column * 4 + row] = sum
            }
        }
        return Map3DMatrix(columns: result)
    }

    /// `point` taken through the matrix, divided by its w: in clip space,
    /// x and y from −1 to 1 across the view and depth from 0 to 1. `nil`
    /// behind the eye.
    public func project(_ point: Map3DPoint) -> Map3DPoint? {
        let v = [point.x, point.y, point.z, 1]
        var out = [Float](repeating: 0, count: 4)
        for row in 0..<4 {
            for k in 0..<4 { out[row] += self[row, k] * v[k] }
        }
        guard out[3] > 0 else { return nil }
        return Map3DPoint(out[0] / out[3], out[1] / out[3], out[2] / out[3])
    }
}

/// `Railway/` rail-3d's `randomAt` (`geo.js`): the same 32-bit hash of a
/// whole-number point and a salt, from 0 up to 1. Decoration chosen by it
/// stays where it is from frame to frame and game to game, unlike the
/// references' `Math.random()`.
public func map3DRandom(_ x: Int32, _ y: Int32, salt: Int32 = 0) -> Float {
    var h = x &* 374_761_393 ^ y &* 668_265_263 ^ (salt &+ 1) &* 1_274_126_177
    h = (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 13)) &* 1_274_126_177
    let mixed = UInt32(bitPattern: h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16))
    return Float(Double(mixed) / 4_294_967_296)
}
