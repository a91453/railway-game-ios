import Foundation
import GameCore

/// The 3D map's trains that had no model of their own (decision 318): the
/// locomotive-hauled sets (Chu-Kuang, the Blue Train, the push-pull
/// Tze-Chiang), the Puyuma and Taroko, the EMU800 and the diesel railcars,
/// built from the scene kit's train recipes (`Map3DSceneKit`, #900) as one
/// model per car: the head, the middle cars and, where it differs from the
/// head turned round, the tail; a one-car railcar has its own model with a
/// cab at each end.
///
/// Their colours are their own (``TrainLivery``, the reference's garage
/// models for the locomotives and the railcars), baked in, so they do not
/// take the line's colour.
public struct Map3DTrainSet: Sendable {
    /// The type's code (``TrainTypeSpec/code``) or, for a train whose type
    /// has no style, its performance's (``TrainPerformanceSpec/code``).
    public let key: String
    let build: @Sendable () -> Cars

    struct Cars {
        var head: Map3DModelPack.Model
        var middle: Map3DModelPack.Model
        var tail: Map3DModelPack.Model?
        var single: Map3DModelPack.Model?
    }

    /// The models' names in the pack.
    var headName: String { "set-\(key)-head" }
    var middleName: String { "set-\(key)-car" }
    var tailName: String { "set-\(key)-tail" }
    var singleName: String { "set-\(key)-single" }

    /// The four model names and their models, in the pack's order.
    func models() -> [Map3DModelPack.Model] {
        let cars = build()
        func named(_ model: Map3DModelPack.Model, _ name: String) -> Map3DModelPack.Model {
            Map3DModelPack.Model(name: name, vertices: model.vertices, minimum: model.minimum, maximum: model.maximum)
        }
        var models = [named(cars.head, headName), named(cars.middle, middleName)]
        if let tail = cars.tail { models.append(named(tail, tailName)) }
        if let single = cars.single { models.append(named(single, singleName)) }
        return models
    }

    /// Every set.
    public static let all: [Map3DTrainSet] = {
        let chuKuang = coach(TrainLivery.e200ChuKuang)
        return [
            // The locomotive-hauled sets (decision 252): the coaches behind
            // their locomotive, the last coach's end lit red.
            hauled("E200CK", locomotive: .init(modern: true, variant: 5, color: 0xE57939, accent: 0xE8DFB9), coach: chuKuang),
            hauled("E500CK", locomotive: .init(modern: true, variant: 5, color: 0xF07532, accent: 0x333F42), coach: chuKuang),
            hauled("R100CK", locomotive: .init(modern: false, variant: 4, color: 0xDF753B, accent: 0xEAE6D3), coach: chuKuang),
            hauled("R200CK", locomotive: .init(modern: true, variant: 5, color: 0xEBEDEA, accent: 0x283944), coach: chuKuang),
            // Decision 286: the Blue Train's R135 and its old blue coaches.
            hauled("BLUE", locomotive: .init(modern: false, variant: 4, color: 0x232E48, accent: 0xEEEDE4),
                   coach: coach(TrainLivery.blueTrain, band: 0.38...0.43)),
            // The push-pull Tze-Chiang: an E1000 power car at each end.
            hauled("pushPull", locomotive: .init(modern: true, variant: 5, color: 0xD8DDDB, accent: 0xE66D2F),
                   coach: coach(body: 0xC9CECC, band: 0xED822A), lastIsLocomotive: true),
            // The multiple units, by their performance (decision 237).
            multipleUnit("puyuma", asset: "01_TRA_modern_3x2-02", livery: TrainLivery.puyuma),
            multipleUnit("taroko", asset: "01_TRA_modern_3x2-03", livery: TrainLivery.taroko),
            multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", livery: TrainLivery.emu800),
            // The DR1000 railcar and the DR3100 diesel express: silver,
            // yellow-orange ends (the reference's `dr1000`, `dr3100`).
            multipleUnit("dieselRailcar", asset: "05_TRA_classic_3x2-03", body: 0xBFC8C9, band: 0xE89A27, single: true),
            multipleUnit("dieselExpress", asset: "05_TRA_classic_3x2-04", body: 0xBFC8C9, band: 0xE89A27),
        ]
    }()

    static let byKey: [String: Map3DTrainSet] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// The set of a `count`-car train of `key`: the diesel railcar's
    /// performance runs as the diesel express's (the same curves, so a
    /// train's key is always the express's), and one or two cars are a
    /// DR1000 railcar, more a DR3100 set.
    static func set(forKey key: String, count: Int) -> Map3DTrainSet? {
        if key == "dieselExpress", count <= 2 { return byKey["dieselRailcar"] }
        return byKey[key]
    }

    /// The performances that are the same trains as a type with a set
    /// (decision 252: the Chu-Kuang presets).
    static let aliases: [String: String] = [
        "e200ChuKuang": "E200CK", "e500ChuKuang": "E500CK", "r100ChuKuang": "R100CK", "r200ChuKuang": "R200CK",
    ]

    /// The key of a train of `type` with `performance`: its type's code
    /// when that type has a style or a set, else its performance's when
    /// that has a set, else its type's.
    public static func key(type: TrainType?, performance: TrainPerformance) -> String {
        let code = type?.spec.code ?? ""
        if Map3DModelPack.styleByType[code] != nil, code != "" { return code }
        if byKey[code] != nil { return code }
        if let preset = PerformancePreset(matching: performance) {
            let wanted = aliases[preset.code] ?? preset.code
            if byKey[wanted] != nil { return wanted }
        }
        return code
    }

    // MARK: Building

    struct Locomotive {
        var modern: Bool
        var variant: Int
        var color: UInt32
        var accent: UInt32
    }

    static func hauled(_ key: String, locomotive: Locomotive, coach: Coach, lastIsLocomotive: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            var engine = SceneKitBuilder()
            engine.locomotive(variant: locomotive.variant, modern: locomotive.modern,
                              color: Map3DColor.rgb(locomotive.color), accent: Map3DColor.rgb(locomotive.accent),
                              roof: Map3DTrainStyle.roofColour)
            engine.locomotiveSides(locomotive)
            let head = Map3DModelPack.Model.flat(named: key, from: engine.mesh)
            let middle = baked(SceneKitCab.coach(style: coach.style, named: key), tint: coach.tint)
            return Cars(head: head, middle: middle, tail: lastIsLocomotive ? nil : tailCoach(coach, named: key), single: nil)
        }
    }

    static func multipleUnit(_ key: String, asset id: String, livery: TrainLivery? = nil, body: Int? = nil, band: Int? = nil,
                             single: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            guard let asset = Map3DSceneKit.asset(id: id) else { preconditionFailure("No scene-kit subject \(id).") }
            var recipe = SceneKitBuilder.trainRecipe(asset)
            if let colour = livery?.body ?? body { recipe.style.body = Map3DColor.rgb(UInt32(colour)) }
            if let colour = livery?.stripe ?? band { recipe.tint = Map3DColor.rgb(UInt32(colour)) }
            let head = baked(SceneKitCab(style: recipe.style, asset: asset, tail: false, tint: recipe.tint).model(), tint: recipe.tint)
            let tail = baked(SceneKitCab(style: recipe.style, asset: asset, tail: true, tint: recipe.tint).model(), tint: recipe.tint)
            let middle = baked(Map3DTrainBuilder(style: recipe.style, cab: false).model(named: key), tint: recipe.tint)
            var one: Map3DModelPack.Model?
            if single {
                // The scene kit's railbus: the front halves of a head and a
                // tail cab car, back to back.
                var builder = SceneKitBuilder()
                builder.addModel(SceneKitCab.clipped(head, maximumX: 0, keepFront: true), tint: recipe.tint)
                builder.addModel(SceneKitCab.clipped(tail, maximumX: 0, keepFront: true), angle: .pi, tint: recipe.tint)
                one = .flat(named: key, from: builder.mesh)
            }
            return Cars(head: head, middle: middle, tail: tail.turned, single: one)
        }
    }

    /// A coach of the scene kit's locomotive-hauled subjects in `livery`'s
    /// colours: its body below and above, the stripe across the windows.
    struct Coach {
        var style: Map3DTrainStyle
        var tint: UInt32
    }

    static func coach(_ livery: TrainLivery, band: ClosedRange<Float> = 0.5...0.86) -> Coach {
        coach(body: livery.body ?? 0xC9CECC, band: livery.stripe ?? 0xE9EBE5, shares: band)
    }

    static func coach(body: Int, band: Int, shares: ClosedRange<Float> = 0.5...0.86) -> Coach {
        guard let asset = Map3DSceneKit.asset(id: "05_TRA_classic_3x2-05") else { preconditionFailure("No scene-kit R20.") }
        var style = SceneKitBuilder.trainRecipe(asset).style
        style.body = Map3DColor.rgb(UInt32(body))
        style.band = shares
        return Coach(style: style, tint: Map3DColor.rgb(UInt32(band)))
    }

    /// The last coach: its back end closed, with a door, a window and two
    /// red lamps (the scene kit's subject's end).
    static func tailCoach(_ coach: Coach, named name: String) -> Map3DModelPack.Model {
        var builder = SceneKitBuilder()
        builder.addModel(SceneKitCab.coach(style: coach.style, named: name), tint: coach.tint)
        let end = -coach.style.length / 2
        builder.box(end - 0.025, 1.0, 0, 0.08, 1.04, 2.4, Map3DTrainStyle.doorColour)
        builder.box(end - 0.07, 1.9, 0, 0.025, 0.70, 1.1, Map3DTrainStyle.glass)
        builder.box(end - 0.08, 0.8, 0, 0.22, 1.5, 0.18, Map3DTrainStyle.under)
        for z: Float in [-1, 1] {
            let glowStart = builder.mesh.vertices.count
            builder.box(end - 0.05, 1.5, z, 0.10, 0.17, 0.17, Map3DPalette.lantern)
            builder.mesh.makeGlowing(from: glowStart)
        }
        return .flat(named: name, from: builder.mesh)
    }

    /// `model` with the line's share of its colours painted `tint`.
    static func baked(_ model: Map3DModelPack.Model, tint: UInt32) -> Map3DModelPack.Model {
        var builder = SceneKitBuilder()
        builder.addModel(model, tint: tint)
        return .flat(named: model.name, from: builder.mesh)
    }
}

extension Map3DModelPack.Model {
    /// This model turned round to face −x, so a train's last car can be
    /// drawn as its tail facing forward like every other car.
    var turned: Map3DModelPack.Model {
        let vertices = self.vertices.map { v in
            Map3DVertex(Map3DPoint(-v.x, -v.y, v.z), normal: Map3DPoint(-v.nx, -v.ny, v.nz), color: v.color, layer: v.layer)
        }
        return Map3DModelPack.Model(name: name, vertices: vertices,
                                    minimum: Map3DPoint(-maximum.x, -maximum.y, minimum.z), maximum: Map3DPoint(-minimum.x, -minimum.y, maximum.z))
    }
}

extension SceneKitBuilder {
    /// A locomotive's sides, so it reads as one and not as a crate: the
    /// cab windows, a band in its second colour along the body and the
    /// grilles of its engine room (the reference's garage models: E200's
    /// cream band, the hood units' cab and louvres).
    mutating func locomotiveSides(_ locomotive: Map3DTrainSet.Locomotive) {
        let accent = Map3DColor.rgb(locomotive.accent)
        let grille = Map3DColor.shaded(Map3DColor.rgb(locomotive.color), 0.62)
        if locomotive.modern {
            // A box cab at each end: the windows behind each windscreen.
            for x: Float in [-6.4, 6.4] { box(x, 2.45, 0, 1.1, 2.84, 0.85, Map3DTrainStyle.glass) }
            box(0, 1.75, 0, 15.9, 2.83, 0.28, accent)
            for x: Float in [-3.2, 0, 3.2] { box(x, 2.45, 0, 2.2, 2.84, 0.9, grille) }
        } else {
            // A hood unit: the cab's windows on every side, the hood's
            // louvres and a band along its foot.
            box(5.2, 2.75, 0, 2.6, 2.84, 0.8, Map3DTrainStyle.glass)
            box(5.2, 2.75, 0, 3.84, 1.9, 0.8, Map3DTrainStyle.glass)
            box(-1.9, 1.35, 0, 11.3, 2.24, 0.25, accent)
            for x: Float in [-6, -3.4, -0.8, 1.8] { box(x, 2.0, 0, 1.8, 2.24, 0.95, grille) }
        }
    }
}

