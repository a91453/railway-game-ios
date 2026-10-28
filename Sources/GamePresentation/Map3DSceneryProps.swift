import Foundation
import GameCore

// Decision 458: the conifers of the mountains, the bushes of the station
// plazas and the open ground beside the line, and the horizontal tanks of
// the factories' yards. Recombined from three Kenney models (CC0: Nature
// Kit's `tree_pineTallA` and `plant_bushLarge`, City Kit Industrial's
// `detail-tank`) by `tools/kenney-props/` and converted by
// `tools/glb-to-m3dmodel/`; the app bundles them as
// `Resources/Models/kenney-*.m3dmodel` and reads them once, as the city
// bus (``Map3DCityBus``). Each has a code-made stand-in of the same size
// in ``Map3DModelPack/standard``, drawn where its file cannot be read;
// both are drawn as instances near the camera, as the street furniture
// (``Map3DProp``).

/// A piece of scenery and its model.
public enum Map3DSceneryProp: String, CaseIterable, Sendable {
    /// A slender cedar or fir of the plantations (柳杉, 杉木): five tiers.
    case pineTall
    /// A broader pine (台灣二葉松): three wide tiers.
    case pine
    /// A young conifer: two tiers on a short trunk.
    case pineYoung
    /// Two bushes, a clump about a metre high.
    case bushes
    /// Three bushes, a bigger clump.
    case bushesLarge
    /// A horizontal storage tank on its saddles and pad.
    case tank

    /// The conifers, for the woods (``Map3DScene/Builder/addConifers()``).
    public static let conifers: [Map3DSceneryProp] = [.pineTall, .pine, .pineYoung]
    /// The bush clumps.
    public static let bushClumps: [Map3DSceneryProp] = [.bushes, .bushesLarge]

    /// The model's name in ``Map3DModelPack``.
    public var modelName: String { "scenery-" + rawValue }

    /// The file's name (and ``fileExtension``) in the app's resources.
    public var fileName: String {
        switch self {
        case .pineTall: "kenney-pine-tall"
        case .pine: "kenney-pine"
        case .pineYoung: "kenney-pine-young"
        case .bushes: "kenney-bushes"
        case .bushesLarge: "kenney-bushes-large"
        case .tank: "kenney-tank"
        }
    }

    public static let fileExtension = "m3dmodel"

    /// Its size, metres: along its +x, across (+y) and up, the size the
    /// file's model comes in (`tools/kenney-props/`), which both it and
    /// the stand-in are fitted to.
    public var size: (length: Float, width: Float, height: Float) {
        switch self {
        case .pineTall: (3.1, 3.14, 12.48)
        case .pine: (3.76, 3.98, 7.67)
        case .pineYoung: (2.26, 1.9, 5.02)
        case .bushes: (2.4, 1.7, 1.0)
        case .bushesLarge: (3.22, 2.68, 1.25)
        case .tank: (9.76, 4.4, 3.26)
        }
    }

    /// The colour of the file's leaves, which takes the instance's colour
    /// (alpha 0), so each tree and clump is its own green: the conifers'
    /// crown and the bushes' embankment green, as `tools/kenney-props/`
    /// writes them.
    static let leaves: Set<UInt32> = [Map3DPalette.crown, Map3DPalette.embankment]

    /// The conifers' greens, one picked for each tree: deeper and bluer
    /// than the street trees' (``Map3DProp/greens``), as a hillside of
    /// cedars is, in the model look.
    public static let coniferGreens: [UInt32] = [0x3F7D4A, 0x4A8752, 0x357244, 0x56905A].map { Map3DLook.colour(Map3DColor.rgb($0)) }
    /// The bushes' greens: the street trees' with a deeper one.
    public static let bushGreens: [UInt32] = [0x5C9A48, 0x4E8C40, 0x6AA650].map { Map3DLook.colour(Map3DColor.rgb($0)) }

    /// The stand-in, in the pack's space (+x along, +y left, +z up, its
    /// foot at the origin), the size of the file's.
    func model() -> Map3DModelPack.Model {
        var mesh = Map3DMesh()
        // Built in the scene's axes (x, y up, z).
        switch self {
        case .pineTall, .pine, .pineYoung:
            let tiers = self == .pineTall ? 5 : self == .pine ? 3 : 2
            let trunk: Float = self == .pineTall ? 3.2 : self == .pine ? 2.0 : 0.9
            mesh.addCylinder(base: .zero, radius: 0.2, height: trunk + 0.6, sides: 6, top: Map3DPalette.trunk, side: Map3DPalette.trunk)
            let crown = size.height - trunk, step = crown / Float(tiers + 1)
            for tier in 0..<tiers {
                let share = 1 - Float(tier) / Float(tiers + 1)
                let base = trunk + step * Float(tier), top = tier == tiers - 1 ? size.height : base + step * 1.6
                Self.addCone(&mesh, base: base, top: top, radius: size.length / 2 * share)
            }
        case .bushes, .bushesLarge:
            let two: [(Map3DPoint, Float)] = [(Map3DPoint(-0.4, 0.4, 0), 0.6), (Map3DPoint(0.6, 0.3, 0.2), 0.45)]
            let three: [(Map3DPoint, Float)] = [(Map3DPoint(-0.5, 0.5, -0.3), 0.75), (Map3DPoint(0.8, 0.4, 0.3), 0.6), (Map3DPoint(-0.4, 0.35, 0.8), 0.5)]
            let lumps = self == .bushes ? two : three
            for (centre, radius) in lumps { Map3DProp.addLump(&mesh, centre: centre, radius: radius) }
        case .tank:
            let size = size
            mesh.addBox(base: .zero, forward: Map3DPoint(1, 0, 0), length: size.length, width: size.width, height: 0.15,
                        top: Map3DPalette.concrete, side: Map3DPalette.concrete)
            for x: Float in [-0.35, 0, 0.35] {
                mesh.addBox(base: Map3DPoint(x * size.length, 0.15, 0), forward: Map3DPoint(1, 0, 0), length: 0.5, width: 2.2, height: 0.8,
                            top: Map3DPalette.tankStand, side: Map3DPalette.tankStand)
            }
            mesh.addBox(base: Map3DPoint(0, 0.5, 0), forward: Map3DPoint(1, 0, 0), length: size.length * 0.85, width: 2.8, height: size.height - 0.5,
                        top: Map3DPalette.tankWhite, side: Map3DPalette.tankWhite)
        }
        return Self.fitted(Map3DModelPack.Model.flat(named: modelName, from: mesh), to: size, named: modelName)
    }

    /// A six-sided cone from `base` to `top` (scene y), its colour the
    /// instance's.
    static func addCone(_ mesh: inout Map3DMesh, base: Float, top: Float, radius: Float) {
        let leaf = Map3DPalette.crown & 0x00FF_FFFF
        let apex = Map3DPoint(0, top, 0), middle = Map3DPoint(0, base, 0)
        let ring = (0..<6).map { index -> Map3DPoint in
            let angle = Float(index) * 2 * Float.pi / 6
            return Map3DPoint(cosf(angle) * radius, base, sinf(angle) * radius)
        }
        for index in 0..<6 {
            let next = (index + 1) % 6
            mesh.addFacet([apex, ring[next], ring[index]], color: leaf)
            mesh.addFacet([middle, ring[index], ring[next]], color: leaf)
        }
    }

    /// The model from `file`, fitted to ``size``, its leaves the
    /// instance's colour and its other colours in the model look, as the
    /// street furniture's (``Map3DLook/restyle(_:)``).
    func model(from file: Map3DModelFile) -> Map3DModelPack.Model {
        let fitted = Self.fitted(file.model, to: size, named: modelName)
        return Map3DModelPack.Model(name: modelName, vertices: fitted.vertices.map { vertex in
            var vertex = vertex
            vertex.color = Self.leaves.contains(vertex.color | 0xFF00_0000) ? vertex.color & 0x00FF_FFFF : Map3DLook.colour(vertex.color)
            return vertex
        }, minimum: fitted.minimum, maximum: fitted.maximum)
    }

    /// `model` stretched to `size` (as ``Map3DCityBus/model(from:)``
    /// fits the bus), its middle over the origin and its foot on it.
    static func fitted(_ model: Map3DModelPack.Model, to size: (length: Float, width: Float, height: Float), named name: String) -> Map3DModelPack.Model {
        let extent = model.maximum - model.minimum
        let scale = Map3DPoint(size.length / extent.x, size.width / extent.y, size.height / extent.z)
        let middle = Map3DPoint((model.minimum.x + model.maximum.x) / 2, (model.minimum.y + model.maximum.y) / 2, model.minimum.z)
        let vertices = model.vertices.map { vertex in
            let p = vertex.position - middle
            let normal = Map3DPoint(vertex.nx / scale.x, vertex.ny / scale.y, vertex.nz / scale.z).normalized ?? Map3DPoint(0, 0, 1)
            return Map3DVertex(Map3DPoint(p.x * scale.x, p.y * scale.y, p.z * scale.z), normal: normal, color: vertex.color, layer: vertex.layer)
        }
        let half = Map3DPoint(size.length / 2, size.width / 2, 0)
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: Map3DPoint(-half.x, -half.y, 0),
                                    maximum: Map3DPoint(half.x, half.y, size.height))
    }

    /// `pack` with each piece read from `files` in place of its stand-in,
    /// where its file can be read and has some size; the stand-in stays
    /// where it cannot.
    public static func pack(_ pack: Map3DModelPack, files: [Map3DSceneryProp: URL]) -> Map3DModelPack {
        var pack = pack
        for (prop, url) in files.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let data = try? Data(contentsOf: url), let file = try? Map3DModelFile(decoding: data, named: prop.fileName),
                  Map3DCityBus.canFit(file.model) else { continue }
            pack = pack.replacing(prop.model(from: file))
        }
        return pack
    }
}

extension Map3DScene.Builder {
    /// Decision 458: the models' places in ``Map3DModelPack/standard``.
    static let sceneryModels: [Map3DSceneryProp: Int] = Dictionary(uniqueKeysWithValues: Map3DSceneryProp.allCases.compactMap { prop in
        Map3DModelPack.standard.index(of: prop.modelName).map { (prop, $0) }
    })

    /// Decision 458: how many of the base map's woods' spots have a
    /// conifer at ground `height` metres: none up to 400 m (the broadleaf
    /// and bamboo of Taiwan's foothills), more higher up, most from
    /// 1,400 m (the cedar plantations and the pines of the high
    /// mountains).
    static func coniferShare(atHeight height: Float) -> Float {
        min(max((height - 400) / 1000, 0), 1) * 0.85
    }

    /// Whether scene point (`x`, `z`) is within `margin` metres of a road's
    /// carriageway or pavement in `pieces`.
    static func isNearRoad(x: Float, z: Float, _ pieces: [(a: Map3DPoint, b: Map3DPoint, half: Float)], margin: Float) -> Bool {
        pieces.contains { piece in
            let dx = piece.b.x - piece.a.x, dz = piece.b.z - piece.a.z, length = dx * dx + dz * dz
            let t = length > 0 ? min(max(((x - piece.a.x) * dx + (z - piece.a.z) * dz) / length, 0), 1) : 0
            let ex = piece.a.x + dx * t - x, ez = piece.a.z + dz * t - z
            return (ex * ex + ez * ez).squareRoot() < piece.half + margin
        }
    }

    /// Decision 458: conifers in the base map's woods, two by two on each
    /// 64 m cell (a hashed spot in each quarter: about 220 on a wooded
    /// 512 m chunk high up, some 25,000 triangles), more of them the
    /// higher the ground (``coniferShare(atHeight:)``); none on water,
    /// within 2 m of a road or on the cells in `cleared`. The same every
    /// time, seeded by the world's cells.
    mutating func addConifers(clearOf cleared: Set<Map3DScene.ChunkKey>) {
        guard !woodCells.isEmpty else { return }
        let models = Map3DSceneryProp.conifers.compactMap { Self.sceneryModels[$0] }
        guard models.count == Map3DSceneryProp.conifers.count else { return }
        let cells = Set(woodCells.keys).subtracting(cleared)
        let pieces = roadPieces(near: cells)
        let side = Float(Double(Land.cellLength) / Self.metre), quarter = side / 2
        for key in cells.sorted() {
            let west = Float(gridLine(key.column, origin: originX)), north = Float(gridLine(key.row, origin: originY))
            for i in 0..<2 {
                for j in 0..<2 {
                    let seed = (Int32(truncatingIfNeeded: key.column &* 2 &+ i), Int32(truncatingIfNeeded: key.row &* 2 &+ j))
                    func r(_ salt: Int32) -> Float { map3DRandom(seed.0, seed.1, salt: salt) }
                    let x = west + quarter * (Float(i) + 0.1 + 0.8 * r(80)), z = north + quarter * (Float(j) + 0.1 + 0.8 * r(81))
                    let spot = Map3DPoint(x, 0, z)
                    guard isInside(spot, woodCells), !isOverWater(spot) else { continue }
                    let height = drawnGround(x: x, z: z)
                    guard r(82) < Self.coniferShare(atHeight: height), !Self.isNearRoad(x: x, z: z, pieces[key] ?? [], margin: 2) else { continue }
                    // Most of them tall, the young ones fewest.
                    let pick = r(83), model = models[pick < 0.45 ? 0 : pick < 0.8 ? 1 : 2]
                    let angle = r(84) * 2 * Float.pi
                    let foot = Map3DPoint(x, height, z)
                    props[self.key(of: foot), default: []].append(.prop(model, at: foot, forward: Map3DPoint(cosf(angle), 0, sinf(angle)),
                                                                        scale: 0.8 + 0.45 * r(85),
                                                                        tint: Self.pick(Map3DSceneryProp.coniferGreens, r(86))))
                }
            }
        }
    }

    /// A bush clump on `foot`, turned by `turn` (0–1), its size and green
    /// from `share`, `size` (0–1).
    private mutating func addBushClump(at foot: Map3DPoint, turn: Float, size: Float, large: Bool) {
        guard let model = Self.sceneryModels[large ? .bushesLarge : .bushes] else { return }
        let angle = turn * 2 * Float.pi
        props[key(of: foot), default: []].append(.prop(model, at: foot, forward: Map3DPoint(cosf(angle), 0, sinf(angle)), scale: 0.85 + 0.35 * size,
                                                    tint: Self.pick(Map3DSceneryProp.bushGreens, size)))
    }

    /// Decision 458: bush clumps on each station building's plaza, four
    /// metres out from its front, two by its corners and two farther out,
    /// where no track, platform or road is near (``isClear(_:facing:)``).
    mutating func addStationBushes() {
        for (index, front) in stationFronts.enumerated() {
            let right = front.forward.cross(.up), entrance = front.centre + front.forward * (front.depth / 2 + 4)
            for (number, out) in [front.wide / 2 - 1.5, -(front.wide / 2 - 1.5), front.wide / 2 + 4, -(front.wide / 2 + 4)].enumerated() {
                let spot = entrance + right * out
                let corners: [(Float, Float)] = [(-1.7, -1.7), (1.7, -1.7), (1.7, 1.7), (-1.7, 1.7)]
                let footprint = corners.map { spot + front.forward * $0.0 + right * $0.1 }
                guard isClear(footprint, facing: front.forward) else { continue }
                let r = { (salt: Int32) in map3DRandom(Int32(index), Int32(number), salt: salt) }
                addBushClump(at: Map3DPoint(spot.x, drawnGround(x: spot.x, z: spot.z) + 0.05, spot.z), turn: r(90), size: r(91), large: number < 2)
            }
        }
    }

    /// Decision 458: bush clumps on the base map's grass in the cells next
    /// to the track's (`track`), up to two a cell, none on the track's
    /// cells or those in `cleared`, on water or within 3 m of a road.
    mutating func addBushesBesideTrack(_ track: Set<Map3DScene.ChunkKey>, clearOf cleared: Set<Map3DScene.ChunkKey>) {
        guard !grassCells.isEmpty, !track.isEmpty else { return }
        var beside = Set<Map3DScene.ChunkKey>()
        for cell in track {
            for dr in -1...1 {
                for dc in -1...1 {
                    let key = Map3DScene.ChunkKey(column: cell.column + dc, row: cell.row + dr)
                    if grassCells[key] != nil { beside.insert(key) }
                }
            }
        }
        beside.subtract(track)
        beside.subtract(cleared)
        let pieces = roadPieces(near: beside)
        let side = Float(Double(Land.cellLength) / Self.metre)
        for key in beside.sorted() {
            let west = Float(gridLine(key.column, origin: originX)), north = Float(gridLine(key.row, origin: originY))
            for index in Int32(0)..<2 {
                let seed = (Int32(truncatingIfNeeded: key.column), Int32(truncatingIfNeeded: key.row))
                func r(_ salt: Int32) -> Float { map3DRandom(seed.0, seed.1, salt: salt + index * 10) }
                let x = west + side * (0.1 + 0.8 * r(100)), z = north + side * (0.1 + 0.8 * r(101))
                let spot = Map3DPoint(x, 0, z)
                guard r(102) < 0.7, isInside(spot, grassCells), !isOverWater(spot),
                      !Self.isNearRoad(x: x, z: z, pieces[key] ?? [], margin: 3) else { continue }
                addBushClump(at: Map3DPoint(x, drawnGround(x: x, z: z), z), turn: r(103), size: r(104), large: r(105) < 0.4)
            }
        }
    }

    /// Decision 458: one or two horizontal tanks in a factory's yard,
    /// along `forward` on the side the hall leaves free (`free`, the
    /// yard's side across from the hall), close up only.
    mutating func addYardTanks(base: Map3DPoint, forward: Map3DPoint, free across: Map3DPoint, room: Float, lot: Float, share: Float) {
        guard target == .near, let model = Self.sceneryModels[.tank] else { return }
        let size = Map3DSceneryProp.tank.size
        // Clear of the office at the front (9 m deep) too.
        guard room >= size.width + 1, lot >= size.length + 11 else { return }
        let count = room >= size.width * 2 + 2 ? 2 : 1
        for index in 0..<(share < 0.5 ? count : 1) {
            let spot = base - forward * (lot / 2 - size.length / 2 - 1) + across * (lot / 2 - size.width / 2 - 1 - Float(index) * (size.width + 1))
            props[key(of: spot), default: []].append(.prop(model, at: spot + Map3DPoint(0, 0.03, 0), forward: forward, scale: 1,
                                                           tint: Map3DColor.rgb(0xFFFFFF)))
        }
    }
}
