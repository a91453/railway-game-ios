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
//
// Decision 467: a pair of post boxes, red and green, and a bus stop's sign
// on its own pole, the first of the owner's Meshy street props
// (`meshy-batch-2026-10`, text-to-3D, so the data-source page says they
// are generated), simplified and recoloured by `tools/meshy-props/`; the
// app bundles them as `Resources/Models/meshy-*.m3dmodel`, read as the
// Kenney ones.

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
    /// Decision 467: Taiwan's post boxes by a bus stop, red (prompt mail)
    /// and green (ordinary mail) side by side, their slots toward the road.
    case postBoxes
    /// Decision 467: a bus stop's sign on its own pole, where the pavement
    /// has no room for a shelter, its face along the street.
    case busStopPole
    /// Decision 767: the game author's elevated coal bunker, its brick bin
    /// on stone piers and its conveyor, in an old brick plant's yard.
    case coalBunker

    /// The conifers, for the woods (``Map3DScene/Builder/addConifers()``).
    public static let conifers: [Map3DSceneryProp] = [.pineTall, .pine, .pineYoung]
    /// The bush clumps.
    public static let bushClumps: [Map3DSceneryProp] = [.bushes, .bushesLarge]
    /// Decision 467: the small things by a bus stop.
    public static let streetFurniture: [Map3DSceneryProp] = [.postBoxes, .busStopPole]

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
        case .postBoxes: "meshy-post-boxes"
        case .busStopPole: "meshy-bus-stop-pole"
        case .coalBunker: "coal-bunker"
        }
    }

    public static let fileExtension = "m3dmodel"

    /// Its size, metres: along its +x, across (+y) and up, the size the
    /// file's model comes in (`tools/kenney-props/`, `tools/meshy-props/`),
    /// which both it and the stand-in are fitted to.
    public var size: (length: Float, width: Float, height: Float) {
        switch self {
        case .pineTall: (3.1, 3.14, 12.48)
        case .pine: (3.76, 3.98, 7.67)
        case .pineYoung: (2.26, 1.9, 5.02)
        case .bushes: (2.4, 1.7, 1.0)
        case .bushesLarge: (3.22, 2.68, 1.25)
        case .tank: (9.76, 4.4, 3.26)
        case .postBoxes: (1.04, 0.43, 1.15)
        case .busStopPole: (0.59, 0.58, 2.8)
        case .coalBunker: (31.51, 11.0, 8.91)
        }
    }

    /// Decision 467: the colours `tools/meshy-props/` writes and the
    /// stand-ins use (the post boxes' red and green, their slot and feet;
    /// the sign's face, frame and post).
    static let postRed = Map3DColor.rgb(0xC8382E)
    static let postGreen = Map3DColor.rgb(0x2E8B4E)
    static let postFoot = Map3DColor.rgb(0x4A4F57)
    static let signWhite = Map3DColor.rgb(0xF2F3F1)
    static let signFrame = Map3DColor.rgb(0x3F6FA8)
    static let poleSteel = Map3DColor.rgb(0x9AA0A8)
    /// Decision 767: the colours `tools/coal-bunker/` writes and the
    /// stand-in uses: the old plants' brick, granite piers, steel, coal and
    /// timber.
    static let bunkerBrick = Map3DPalette.brick
    static let bunkerStone = Map3DPalette.granite
    static let bunkerSteel = Map3DPalette.steel
    static let bunkerCoal = Map3DPalette.dark
    static let bunkerWood = Map3DColor.rgb(0x8E6E52)

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
        case .postBoxes:
            // Two pillars on dark feet, a dark slot on each one's front
            // (toward the road, scene −z).
            for (x, body) in [(Float(-0.3), Self.postRed), (0.3, Self.postGreen)] {
                mesh.addCylinder(base: Map3DPoint(x, 0, 0), radius: 0.21, height: 0.1, sides: 8, top: Self.postFoot, side: Self.postFoot)
                mesh.addCylinder(base: Map3DPoint(x, 0.1, 0), radius: 0.19, height: 1.05, sides: 8, top: body, side: body)
                mesh.addBox(base: Map3DPoint(x, 0.78, -0.19), forward: Map3DPoint(1, 0, 0), length: 0.2, width: 0.04, height: 0.04,
                            top: Self.postFoot, side: Self.postFoot)
            }
        case .busStopPole:
            // A post on a round foot, the tall board on it.
            mesh.addCylinder(base: .zero, radius: 0.29, height: 0.08, sides: 8, top: Self.poleSteel, side: Self.poleSteel)
            mesh.addCylinder(base: Map3DPoint(0, 0.08, 0), radius: 0.05, height: 0.5, sides: 6, top: Self.poleSteel, side: Self.poleSteel)
            mesh.addBox(base: Map3DPoint(0, 0.55, 0), forward: Map3DPoint(1, 0, 0), length: 0.12, width: 0.5, height: size.height - 0.55,
                        top: Self.signFrame, side: Self.signFrame)
            mesh.addBox(base: Map3DPoint(0, 0.65, 0), forward: Map3DPoint(1, 0, 0), length: 0.14, width: 0.42, height: size.height - 0.75,
                        top: Self.signFrame, side: Self.signWhite)
        case .coalBunker:
            // The file's parts (tools/coal-bunker/): the bin over the
            // last 25 m on two rows of piers, coal heaped in it, and the
            // conveyor rising to it from the ground at the other end.
            let along = Map3DPoint(1, 0, 0), bin: Float = 25.26, binMiddle = size.length / 2 - bin / 2, floor: Float = 5.8
            for index in 0..<6 {
                for z: Float in [-4.6, 4.6] {
                    let x = binMiddle - bin / 2 + 1 + Float(index) * (bin - 2) / 5
                    mesh.addBox(base: Map3DPoint(x, 0, z), forward: along, length: 0.9, width: 0.9, height: floor,
                                top: Self.bunkerStone, side: Self.bunkerStone)
                }
            }
            mesh.addBox(base: Map3DPoint(binMiddle, floor, 0), forward: along, length: bin, width: size.width, height: size.height - floor - 0.1,
                        top: Self.bunkerSteel, side: Self.bunkerBrick)
            mesh.addBox(base: Map3DPoint(binMiddle + 2, size.height - 0.4, 0), forward: along, length: bin * 0.6, width: size.width * 0.6, height: 0.4,
                        top: Self.bunkerCoal, side: Self.bunkerCoal)
            let foot = -size.length / 2, head = binMiddle - bin / 2 + 2, rise: Float = 6.8
            for (y, colour) in [(Float(0.5), Self.bunkerCoal), (0, Self.bunkerSteel)] {
                mesh.addQuad(Map3DPoint(foot, y, -1), Map3DPoint(foot, y, 1), Map3DPoint(head, rise + y, 1), Map3DPoint(head, rise + y, -1), color: colour)
                mesh.addQuad(Map3DPoint(foot, y, 1), Map3DPoint(foot, y, -1), Map3DPoint(head, rise + y, -1), Map3DPoint(head, rise + y, 1), color: colour)
            }
            mesh.addBox(base: Map3DPoint(head - 0.5, 0, 0), forward: along, length: 1, width: 2, height: rise, top: Self.bunkerWood, side: Self.bunkerWood)
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
    /// time, seeded by the world's cells. Decision 811: the spots below
    /// the conifers' share a broadleaf tree, so the woods of the foothills
    /// are no longer bare (``woodTree(seed:x:z:height:conifers:broadleaf:)``).
    mutating func addConifers(clearOf cleared: Set<Map3DScene.ChunkKey>) {
        guard !woodCells.isEmpty else { return }
        let models = Map3DSceneryProp.conifers.compactMap { Self.sceneryModels[$0] }
        guard models.count == Map3DSceneryProp.conifers.count else { return }
        let broadleaf = Self.propModels[.tree]
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
                    guard !Self.isNearRoad(x: x, z: z, pieces[key] ?? [], margin: 2),
                          let tree = woodTree(seed: seed, x: x, z: z, height: height, conifers: models, broadleaf: broadleaf)
                    else { continue }
                    props[self.key(of: Map3DPoint(x, height, z)), default: []].append(tree)
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

    /// Decision 767: whether an old brick plant's yard has room for the
    /// coal bunker beside the hall: `room` across, and along it the yard
    /// (`lot` and its metre of margin each end; the bunker takes the
    /// office's place), so the 34 m and 40 m lots (density 3 and 4).
    static func coalBunkerFits(room: Float, lot: Float) -> Bool {
        let size = Map3DSceneryProp.coalBunker.size
        return room >= size.width && lot + 2 >= size.length + 0.4
    }

    /// Decision 767: an old brick plant's coal bunker in its yard, along
    /// `forward` on the side the hall leaves free (`free`), close up only.
    mutating func addYardCoalBunker(base: Map3DPoint, forward: Map3DPoint, free across: Map3DPoint, room: Float, lot: Float) {
        guard target == .near, let model = Self.sceneryModels[.coalBunker], Self.coalBunkerFits(room: room, lot: lot) else { return }
        let size = Map3DSceneryProp.coalBunker.size
        // At the back of the yard, as the tanks, or in its middle where the
        // yard is only just long enough.
        let spot = base - forward * max(lot / 2 - size.length / 2 - 1, 0) + across * (lot / 2 - size.width / 2 - 1)
        props[key(of: spot), default: []].append(.prop(model, at: spot + Map3DPoint(0, 0.03, 0), forward: forward, scale: 1,
                                                       tint: Map3DColor.rgb(0xFFFFFF)))
    }

    /// Decision 767: the share of the factory cells the real buildings
    /// stand on that get a coal bunker, where one fits.
    static let realCoalBunkerShare: Float = 0.05

    /// Decision 767: whether industrial cell `cell` is one of the few that
    /// try for a coal bunker: drawn by its place on the map, and none
    /// within two cells before it in the map's order, so no two stand side
    /// by side.
    static func realCoalBunkerCell(_ cell: Map3DScene.ChunkKey) -> Bool {
        func drawn(_ column: Int, _ row: Int) -> Bool {
            map3DRandom(Int32(truncatingIfNeeded: column), Int32(truncatingIfNeeded: row), salt: 767) < realCoalBunkerShare
        }
        guard drawn(cell.column, cell.row) else { return false }
        for row in cell.row - 2...cell.row + 2 {
            for column in cell.column - 2...cell.column + 2 where (row, column) < (cell.row, cell.column) && drawn(column, row) {
                return false
            }
        }
        return true
    }

    /// Decision 767: on a real-world map, where the real buildings stand
    /// and the game draws no factory of its own, the coal bunker in the
    /// yard of an industrial cell (`key`), now and then: on the first
    /// spot of the cell clear of every real building, road, house and
    /// no-build land, along the map's east or its south. Laid in the near
    /// pass, so the far pass's houses (laid then too) keep off it.
    mutating func addRealYardCoalBunker(_ cellKey: Map3DScene.ChunkKey, blocked: Set<Map3DScene.ChunkKey>) {
        guard target == .near, let model = Self.sceneryModels[.coalBunker], Self.realCoalBunkerCell(cellKey) else { return }
        let size = Map3DSceneryProp.coalBunker.size
        let cell = Double(Land.cellLength)
        let centre = point(x: (Double(cellKey.column) + 0.5) * cell, y: (Double(cellKey.row) + 0.5) * cell, height: 0)
        var near = Set<Int>()
        for row in cellKey.row - 1...cellKey.row + 1 {
            for column in cellKey.column - 1...cellKey.column + 1 {
                near.formUnion(frontage.byCell[Map3DScene.ChunkKey(column: column, row: row)] ?? [])
            }
        }
        let pieces = near.sorted()
        let turn = map3DRandom(Int32(truncatingIfNeeded: cellKey.column), Int32(truncatingIfNeeded: cellKey.row), salt: 768) < 0.5
        for forward in turn ? [Map3DPoint(0, 0, 1), Map3DPoint(1, 0, 0)] : [Map3DPoint(1, 0, 0), Map3DPoint(0, 0, 1)] {
            let across = Map3DPoint(forward.z, 0, -forward.x)
            for along: Float in [0, -14, 14] {
                for aside: Float in [0, -12, 12, -24, 24] {
                    let middle = centre + forward * along + across * aside
                    let bunker = StreetHouse(middle: middle, front: across, along: forward, width: size.length, depth: size.width)
                    guard fits(bunker, near: pieces, blocked: blocked) else { continue }
                    frontage.houses[chunk(of: middle), default: []].append(bunker)
                    let foot = Map3DPoint(middle.x, bunker.corners.map { ground(at: $0) }.min() ?? 0, middle.z)
                    props[key(of: foot), default: []].append(.prop(model, at: foot + Map3DPoint(0, 0.03, 0), forward: forward, scale: 1,
                                                                   tint: Map3DColor.rgb(0xFFFFFF)))
                    return
                }
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
