import Foundation
import GameCore

// Decision 837: a station's freight yard (decision 155's facility) is seen
// in 3D (FREIGHT_DEEPENING F1). Beside the platforms, on the side away from
// the station's building, a paved yard 40 m along the line and 18 m deep:
// for goods a container yard (a gantry crane over a row of containers,
// stacks two high, the yard office, a flatbed lorry with a 20 ft box); for
// building materials a stone yard (a loading canopy, three concrete bays
// heaped with gravel and sand, a tipper and a mixer lorry). Its parts are
// the works kit's (``Map3DWorksKit``, until now on no map) and the freight
// trains' containers (``Map3DContainerWagon``, ``Map3DFreightWagons``), so
// the boxes in the yard are the ones the trains carry. Built with the
// scene, as a depot's shed is (decision 441): built again when a yard is
// built, taken down or switched to another kind
// (``signature(of:)``, the app's scene key).

public enum Map3DFreightYard {
    /// The yard's size: along the line, and from its back by the track
    /// to its front.
    public static let length: Float = 40
    public static let depth: Float = 18
    /// How far its back stands clear of the farthest platform or track.
    static let gap: Float = 2
    /// The paving's thickness: enough to hide a little slope under it.
    static let pad: Float = 0.3

    /// Where a yard stands: its station's, what it sends, its middle on
    /// the ground and the way its front faces (away from the track).
    public struct Place: Equatable, Sendable {
        public let station: StationID
        public let product: CargoKind
        public let centre: Map3DPoint
        public let forward: Map3DPoint
    }

    /// What tells one world's yards from another's: each yard's station
    /// and what it sends, in station order.
    public static func signature(of world: GameWorld) -> [Int] {
        (world.freight?.facilities ?? []).map { $0.station.rawValue * 2 + ($0.product == .materials ? 1 : 0) }
    }

    /// The yard sending `product`, built with +x its front (away from the
    /// track), +y up and +z along the line, its middle on the ground at the
    /// origin.
    public static func mesh(_ product: CargoKind) -> Map3DMesh {
        product == .materials ? stoneYard : containerYard
    }

    /// The same from far off: the paving and a box for each part.
    public static func farMesh(_ product: CargoKind) -> Map3DMesh {
        product == .materials ? stoneYardFar : containerYardFar
    }

    /// A works kit part as the builder makes it, +x its front.
    static func part(_ part: Map3DWorksKit.Part) -> Map3DMesh {
        var kit = StationKitBuilder()
        kit.works(part)
        return kit.mesh
    }

    /// Along the line: a part built facing +x laid facing +z.
    static let along = Map3DPoint(0, 0, 1)

    static let concrete = Map3DPalette.concrete
    static let gravel = Map3DPalette.ballast
    static let sand = Map3DPalette.plaza

    static func paving(_ kit: inout StationKitBuilder) {
        kit.box(0, -pad + 0.15, 0, depth, length, pad, concrete)
        // The kerb round it, a shade darker.
        for side: Float in [-1, 1] {
            kit.box(0, 0.15, side * (length / 2 - 0.15), depth, 0.3, 0.12, Map3DColor.shaded(concrete, 0.85))
            kit.box(side * (depth / 2 - 0.15), 0.15, 0, 0.3, length - 0.6, 0.12, Map3DColor.shaded(concrete, 0.85))
        }
    }

    /// Containers in a row along the line, from `from` (their first's
    /// back end) on, each its length, colour and how many high.
    static func row(_ mesh: inout Map3DMesh, x: Float, from: Float, _ boxes: [(length: Float, colour: UInt32, high: Int)]) {
        var at = from
        for box in boxes {
            var kit = StationKitBuilder()
            for level in 0..<box.high {
                // The wagon's container recipe, its doors at its back, on
                // the paving or on the one below.
                // The far recipe: no ribs, which do not show at a yard's
                // distance and would double its triangles.
                kit.container(x: 0, length: box.length, colour: level == 0 ? box.colour : Map3DColor.shaded(box.colour, 0.92), far: true,
                              deck: 0.15 + Float(level) * 2.6)
            }
            mesh.append(kit.mesh, at: Map3DPoint(x, 0, at + box.length / 2), forward: along)
            at += box.length + 0.4
        }
    }

    static let containerYard: Map3DMesh = {
        var kit = StationKitBuilder()
        paving(&kit)
        var mesh = kit.mesh
        let rust = Map3DContainerWagon.rust, green = Map3DContainerWagon.green, ochre = Map3DContainerWagon.ochre
        let blue = Map3DContainerWagon.blue, grey = Map3DContainerWagon.grey
        // Under the crane, by the track: one high, so its spreader clears
        // them.
        row(&mesh, x: -4, from: -18.5, [(12.192, ochre, 1), (6.058, blue, 1)])
        mesh.append(part(.gantryCrane), at: Map3DPoint(-4, 0.15, -12.4), forward: along)
        // The stacks beyond it, two high in places.
        row(&mesh, x: 1.6, from: -18.5, [(12.192, rust, 2), (6.058, grey, 1), (12.192, green, 2), (6.058, blue, 1)])
        row(&mesh, x: 4.3, from: -18.5, [(6.058, grey, 2), (12.192, rust, 1), (6.058, ochre, 1)])
        // The yard office at the far corner, and a lorry with a 20 ft box
        // waiting by it.
        mesh.append(part(.containerOffice), at: Map3DPoint(6.8, 0.15, 14), forward: along)
        var lorry = StationKitBuilder()
        lorry.works(.flatbedTruck)
        lorry.container(x: -1.05, length: 6.058, colour: rust, far: true, deck: 0.98)
        mesh.append(lorry.mesh, at: Map3DPoint(-4.2, 0.15, 10), forward: along)
        return mesh
    }()

    static let containerYardFar: Map3DMesh = {
        var kit = StationKitBuilder()
        kit.box(0, -pad + 0.15, 0, depth, length, pad, concrete)
        kit.box(-4, 0.15, -9.8, 2.44, 18.6, 2.6, Map3DContainerWagon.ochre)
        kit.box(1.6, 0.15, 0.25, 2.44, 37.5, 4.2, Map3DContainerWagon.rust)
        kit.box(4.3, 0.15, -5.9, 2.44, 25.5, 3.6, Map3DContainerWagon.grey)
        kit.box(-4, 5.8, -12.4, 6.8, 2.4, 0.5, StationKitBuilder.worksYellow)
        kit.box(6.8, 0.15, 14, 2.44, 6.1, 2.6, StationKitBuilder.white)
        return kit.mesh
    }()

    /// A heap `wide` across and `long` along, `high` at its ridge, on the
    /// paving at (`x`, `z`).
    static func heap(_ kit: inout StationKitBuilder, x: Float, z: Float, wide: Float, long: Float, high: Float, colour: UInt32) {
        let y: Float = 0.15, a = wide / 2, b = long / 2, ridge = max(b - a * 0.8, 0.4)
        let inside = Map3DPoint(x, y, z)
        for side: Float in [-1, 1] {
            kit.face([Map3DPoint(x + side * a, y, z - b), Map3DPoint(x + side * a, y, z + b),
                      Map3DPoint(x, y + high, z + ridge), Map3DPoint(x, y + high, z - ridge)],
                     inside: inside, color: Map3DColor.shaded(colour, side < 0 ? 0.9 : 1))
            kit.face([Map3DPoint(x - a, y, z + side * b), Map3DPoint(x + a, y, z + side * b), Map3DPoint(x, y + high, z + side * ridge)],
                     inside: inside, color: Map3DColor.shaded(colour, 0.82))
        }
    }

    /// The stone yard's three bays, from `-length / 2 + 18` on along the
    /// line, their back wall at the yard's front.
    static let bays: [(z: Float, colour: UInt32)] = [(-0.5, gravel), (6.5, sand), (13.5, gravel)]

    static let stoneYard: Map3DMesh = {
        var kit = StationKitBuilder()
        paving(&kit)
        // The bays: a back wall at the front of the yard and the walls
        // between them, 1.8 m of concrete, the heaps over them.
        let wall = Map3DColor.shaded(concrete, 0.9)
        kit.box(7.6, 0.15, 6.5, 0.5, 21.5, 1.8, wall)
        for z: Float in [-4, 3, 10, 17] { kit.box(4.6, 0.15, z, 6.5, 0.4, 1.8, wall) }
        for bay in bays { heap(&kit, x: 4.4, z: bay.z, wide: 5.6, long: 6.0, high: 3.2, colour: bay.colour) }
        var mesh = kit.mesh
        // The loading canopy by the track, a tipper under it, and a mixer
        // lorry by the bays.
        mesh.append(part(.loadingCanopy), at: Map3DPoint(-3.8, 0.05, -12), forward: along)
        mesh.append(part(.dumpTruck), at: Map3DPoint(-4.2, 0.15, -12.5), forward: along)
        mesh.append(part(.mixerTruck), at: Map3DPoint(-1.8, 0.15, 6), forward: Map3DPoint(0, 0, -1))
        // Two open-top boxes of stone waiting to go, the trains' own.
        var boxes = StationKitBuilder()
        boxes.openTop(x: 0, length: 6.058, colour: Map3DContainerWagon.rust, far: false, deck: 0.15)
        mesh.append(boxes.mesh, at: Map3DPoint(1.4, 0, -15.5), forward: along)
        mesh.append(boxes.mesh, at: Map3DPoint(4.2, 0, -15.5), forward: along)
        return mesh
    }()

    static let stoneYardFar: Map3DMesh = {
        var kit = StationKitBuilder()
        kit.box(0, -pad + 0.15, 0, depth, length, pad, concrete)
        kit.box(7.6, 0.15, 6.5, 0.5, 21.5, 1.8, Map3DColor.shaded(concrete, 0.9))
        for bay in bays { heap(&kit, x: 4.4, z: bay.z, wide: 5.6, long: 6.0, high: 3.2, colour: bay.colour) }
        kit.box(-3.8, 0.15, -12, 7, 10, 4.3, Map3DPalette.canopy)
        kit.box(2.8, 0.15, -15.5, 5.2, 6.1, 1.4, Map3DContainerWagon.rust)
        return kit.mesh
    }()
}

extension Map3DScene.Builder {
    /// Decision 837: the yards (``Map3DFreightYard``) of the world's
    /// freight facilities, by station.
    var freightYards: [StationID: CargoKind] {
        Dictionary((world.freight?.facilities ?? []).map { ($0.station, $0.product) }, uniquingKeysWith: { first, _ in first })
    }

    /// Decision 837: `station`'s yard sending `product` beside `platforms` (as a station's
    /// building stands, ``besidePlatforms(depth:wide:platforms:middle:sides:)``),
    /// on the side away from the station's building (`house`, the way it
    /// faces out, when it has one) if it fits there, else the other; none
    /// where a road, the station's building or another yard would be under
    /// it. Close up the yard, far off its boxes. The cells it stands on.
    mutating func addFreightYard(_ product: CargoKind, at station: StationID, platforms: [LaidPlatform], house: Map3DPoint?,
                                 middle: (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint)) -> Set<Map3DScene.ChunkKey> {
        typealias Yard = Map3DFreightYard
        let away: Float = house.map { $0.dot(middle.right) >= 0 ? -1 : 1 } ?? 1
        for side in [away, -away] {
            let (out, back) = besidePlatforms(depth: Yard.depth + Yard.gap, wide: Yard.length, platforms: platforms, middle: middle, sides: [side])
            let centre = back + out * (Yard.gap + Yard.depth / 2)
            let corners = Map3DMesh.footprint(centre: centre, forward: out, length: Yard.depth, width: Yard.length)
            guard !Self.overlaps(corners, houseFootprints), isClearOfRoads(corners) else { continue }
            let foot = Map3DPoint(centre.x, corners.map { drawnGround(x: $0.x, z: $0.z) }.max() ?? 0, centre.z)
            let saved = target
            defer { target = saved }
            target = .near
            mesh(at: foot) { $0.append(Yard.mesh(product), at: foot, forward: out) }
            target = .far
            mesh(at: foot) { $0.append(Yard.farMesh(product), at: foot, forward: out) }
            houseFootprints.append(corners)
            freightYardPlaces.append(Map3DFreightYard.Place(station: station, product: product, centre: foot, forward: out))
            return cells(under: corners)
        }
        return []
    }

    /// Whether no road or its pavement comes within a metre of `footprint`
    /// (``isClear(_:facing:)``'s roads, without its track).
    func isClearOfRoads(_ footprint: [Map3DPoint]) -> Bool {
        let middle = footprint.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * 0.25
        guard let facing = (footprint[0] - footprint[3]).normalized else { return true }
        let side = facing.cross(.up)
        let length = (footprint[0] - footprint[3]).length / 2, width = (footprint[1] - footprint[0]).length / 2
        func near(_ p: Map3DPoint, _ margin: Float) -> Bool {
            let d = p - middle
            return abs(d.dot(facing)) < length + margin && abs(d.dot(side)) < width + margin
        }
        let reach = length + width
        for road in roadLines {
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let span = Map3DPoint(b.x - a.x, 0, b.z - a.z), steps = max(1, Int((span.length / 2).rounded(.up)))
                guard (a - middle).length < span.length + reach + road.half + 4 else { continue }
                for step in 0...steps where near(a + span * (Float(step) / Float(steps)), road.half + 1) { return false }
            }
        }
        return true
    }
}
