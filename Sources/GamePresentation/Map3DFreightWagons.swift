import Foundation
import GameCore

/// Decision 837: what a freight line's train carries, as the 3D map draws
/// it (FREIGHT_DEEPENING F1): nothing (the bare flat wagons), goods (decision
/// 539's containers) or building materials (stone in half-height open-top
/// containers).
public enum Map3DFreightLoad: String, CaseIterable, Sendable {
    case empty
    case goods
    case materials

    /// The load of a train carrying `cargo`: the kind it carries most tons
    /// of (goods on a tie), nothing when it carries none.
    public static func of(_ cargo: TrainCargo?) -> Map3DFreightLoad {
        guard let cargo, cargo.tons > 0 else { return .empty }
        var tons: [CargoKind: Int64] = [:]
        for group in cargo.groups { tons[group.kind, default: 0] += group.tons }
        let goods = tons[.goods] ?? 0, materials = tons[.materials] ?? 0
        return materials > goods ? .materials : .goods
    }

    /// The load of each train with cargo in `world` (none without freight).
    public static func loads(in world: GameWorld) -> [TrainID: Map3DFreightLoad] {
        var loads: [TrainID: Map3DFreightLoad] = [:]
        for cargo in world.freight?.loads ?? [] { loads[cargo.train] = of(cargo) }
        return loads
    }

    /// The train set a freight train carrying this is drawn as.
    public var setKey: String {
        switch self {
        case .empty: Map3DFreightWagons.emptyKey
        case .goods: Map3DTrainSet.freightKey
        case .materials: Map3DFreightWagons.bulkKey
        }
    }
}

/// Decision 837: the freight wagons beside decision 539's container wagons
/// (``Map3DContainerWagon``): the same skeletal flat wagon bare, and the
/// same wagon carrying two 20 ft half-height open-top containers heaped with
/// stone, the box used for heavy bulk such as stone and ore (ISO 668's 1CC
/// half height, 6.058 × 2.438 × 1.295 m). Taiwan Railway's stone trains run
/// hopper wagons (石斗車, FREIGHT_DEEPENING §2.5); the hopper wagon is the
/// local studio's next model (`docs/handoff/FREIGHT-LOOK.md`), and these
/// stand in until it comes. No logos or lettering.
///
/// Metres, +X the front, +Y left, +Z up, the rail at 0 (``Map3DModelPack``);
/// the builder works in x front, y up, z right and turns once at the end.
public enum Map3DFreightWagons {
    /// The sets' keys: a freight train running empty and one carrying
    /// building materials (``Map3DFreightLoad/setKey``).
    public static let emptyKey = "FREIGHTEMPTY"
    public static let bulkKey = "FREIGHTBULK"

    public enum Wagon: String, CaseIterable, Sendable {
        /// The bare flat wagon.
        case empty
        /// The bare flat wagon with the red tail marker lamp.
        case emptyTail
        /// Two half-height open-top containers of stone, rust red.
        case stone
        /// The same, dark green.
        case stoneGreen
        /// The last wagon: ochre containers and the tail marker lamp.
        case stoneTail

        var isTail: Bool { self == .emptyTail || self == .stoneTail }
    }

    /// A half-height container's height, and how far under its rim the
    /// stone's sides start and over it its ridge stands.
    static let halfHeight: Float = 1.295
    static let stoneEdge: Float = 0.35
    static let stoneRidge: Float = 0.30
    /// The stone: the ballast's grey.
    static let stone = Map3DPalette.ballast

    public static func model(_ wagon: Wagon, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.containerWagon(far: far)
        switch wagon {
        case .empty, .emptyTail: break
        case .stone, .stoneGreen, .stoneTail:
            let colour = wagon == .stone ? Map3DContainerWagon.rust : wagon == .stoneGreen ? Map3DContainerWagon.green : Map3DContainerWagon.ochre
            for x: Float in [3.067, -3.067] { b.openTop(x: x, length: 6.058, colour: colour, far: far) }
        }
        if wagon.isTail {
            // The tail marker lamp, on the back end sill's left, as the
            // container wagon's.
            let half = Map3DContainerWagon.halfLength
            b.box(-half + 0.36, 1.20, -1.05, 0.06, 0.20, 0.20, Map3DContainerWagon.metal)
            let lens = b.mesh.vertices.count
            b.box(-half + 0.32, 1.22, -1.05, 0.02, 0.16, 0.16, Map3DPalette.lantern)
            b.mesh.makeGlowing(from: lens)
        }
        return .flat(named: "freight-wagon-\(wagon.rawValue)" + (far ? "-far" : ""), from: b.mesh)
    }

    /// Decision 837: the registered sets (decision 782), each the R200 of
    /// decision 539's set (``Map3DTrainSet/headOf``) and its wagons.
    static let registration = Map3DTrainRegistration(
        id: "freightWagons",
        sets: [Map3DTrainSet.freightEmpty(), .freightEmpty(far: true), .freightBulk(), .freightBulk(far: true)],
        showcase: [],
        triangles: 300...4_100, length: 14.1...14.3)
}

extension Map3DTrainSet {
    /// Decision 837: a freight train running empty: the R200 and the bare
    /// flat wagons, the last one with the tail lamp.
    static func freightEmpty(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DFreightWagons.emptyKey
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, far: far ? nil : key + "Far",
                             headOf: far ? "R200CKFar" : "R200CK") {
            Cars(head: litLenses(Map3DR200.model(far: far), front: true), middle: Map3DFreightWagons.model(.empty, far: far),
                 tail: Map3DFreightWagons.model(.emptyTail, far: far), single: nil)
        }
    }

    /// Decision 837: a freight train carrying building materials: the R200
    /// and the wagons of stone, rust and green from each end inward, the
    /// last one ochre with the tail lamp.
    static func freightBulk(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DFreightWagons.bulkKey
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.middle, .centre], ownLengths: true, far: far ? nil : key + "Far",
                             headOf: far ? "R200CKFar" : "R200CK") {
            Cars(head: litLenses(Map3DR200.model(far: far), front: true), middle: Map3DFreightWagons.model(.stone, far: far),
                 tail: Map3DFreightWagons.model(.stoneTail, far: far), single: nil,
                 centre: Map3DFreightWagons.model(.stoneGreen, far: far))
        }
    }
}

extension StationKitBuilder {
    /// A half-height open-top container centred at `x` on the wagon's
    /// floor (or `deck`): its floor, four walls a wall's thickness thick,
    /// the corner posts, the top rail and, heaped over the rim, the stone.
    mutating func openTop(x centre: Float, length: Float, colour: UInt32, far: Bool, deck: Float = Map3DContainerWagon.deck) {
        let width: Float = 2.438, height = Map3DFreightWagons.halfHeight, wall: Float = 0.06
        let half = length / 2, post = Map3DColor.shaded(colour, 0.80), frame = Map3DContainerWagon.frame
        box(centre, deck, 0, length - 0.02, width - 0.04, 0.12, frame)
        for side: Float in [-1, 1] {
            box(centre, deck + 0.12, side * (width / 2 - wall / 2 - 0.02), length - 0.02, wall, height - 0.12, colour)
            box(centre + side * (half - wall / 2 - 0.01), deck + 0.12, 0, wall, width - 0.04 - 2 * wall, height - 0.12, colour)
            // The top rail along each side, standing a little proud.
            box(centre, deck + height - 0.10, side * (width / 2 - 0.02), length - 0.30, 0.06, 0.10, post)
        }
        for sx: Float in [-1, 1] {
            for side: Float in [-1, 1] {
                box(centre + sx * (half - 0.08), deck, side * (width / 2 - 0.08), 0.17, 0.17, height, post)
                box(centre + sx * (half - 0.09), deck, side * (width / 2 - 0.09), 0.19, 0.19, 0.12, frame)
            }
        }
        if !far {
            // The side ribs and the door end's locking bars.
            for side: Float in [-1, 1] {
                for x in stride(from: centre - half + 0.50, through: centre + half - 0.50, by: Float(0.56)) {
                    box(x, deck + 0.14, side * (width / 2 + 0.005), 0.10, 0.03, height - 0.30, post)
                }
            }
            for z: Float in [-0.6, 0.6] {
                beam(Map3DPoint(centre - half - 0.03, deck + 0.14, z), Map3DPoint(centre - half - 0.03, deck + height - 0.14, z), 0.04,
                     Map3DContainerWagon.metal)
            }
        }
        // The stone: a low heap from under the rim to a ridge along the
        // container, its two slopes and its two ends.
        let inner = width / 2 - wall - 0.03, ends = half - wall - 0.03
        let low = deck + height - Map3DFreightWagons.stoneEdge, top = deck + height + Map3DFreightWagons.stoneRidge
        let ridge = ends - 0.6
        let inside = Map3DPoint(centre, low, 0), stone = Map3DFreightWagons.stone
        for side: Float in [-1, 1] {
            face([Map3DPoint(centre - ends, low, side * inner), Map3DPoint(centre + ends, low, side * inner),
                  Map3DPoint(centre + ridge, top, 0), Map3DPoint(centre - ridge, top, 0)],
                 inside: inside, color: Map3DColor.shaded(stone, side < 0 ? 0.92 : 1))
            face([Map3DPoint(centre + side * ends, low, -inner), Map3DPoint(centre + side * ends, low, inner),
                  Map3DPoint(centre + side * ridge, top, 0)],
                 inside: inside, color: Map3DColor.shaded(stone, 0.85))
        }
    }
}
