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
/// take the line's colour. The locomotives are ``Map3DTrainLocomotive``.
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
            hauled("E200CK", locomotive: .e200, coach: chuKuang),
            hauled("E500CK", locomotive: .e500, coach: chuKuang),
            hauled("R100CK", locomotive: .r100, coach: chuKuang),
            hauled("R200CK", locomotive: .r200, coach: chuKuang),
            // Decision 286: the Blue Train's R135 and its old blue coaches.
            hauled("BLUE", locomotive: .r135,
                   coach: coach(TrainLivery.blueTrain, band: 0.38...0.43)),
            // The push-pull Tze-Chiang: an E1000 power car at each end.
            hauled("pushPull", locomotive: .e1000,
                   coach: coach(body: 0xC9CECC, band: 0xED822A), lastIsLocomotive: true),
            // The multiple units, by their performance (decision 237).
            multipleUnit("puyuma", asset: "01_TRA_modern_3x2-02", livery: TrainLivery.puyuma),
            multipleUnit("taroko", asset: "01_TRA_modern_3x2-03", livery: TrainLivery.taroko),
            // The EMU800: grey, a blue band and its blue face (the reference's
            // garage `emu800`).
            multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90),
            // The DR1000 railcar and the DR3100 diesel express: silver, an
            // orange band, flat yellow ends with a gangway door (the
            // reference's `dr1000`, `dr3100`, front `yellowgangway`).
            railcar("dieselRailcar", asset: "05_TRA_classic_3x2-03", single: true),
            railcar("dieselExpress", asset: "05_TRA_classic_3x2-04"),
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

    static func hauled(_ key: String, locomotive: Map3DTrainLocomotive, coach: Coach, lastIsLocomotive: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            let head = locomotive.model
            let middle = baked(SceneKitCab.coach(style: coach.style, named: key), tint: coach.tint)
            return Cars(head: head, middle: middle, tail: lastIsLocomotive ? nil : tailCoach(coach, named: key), single: nil)
        }
    }

    static func multipleUnit(_ key: String, asset id: String, livery: TrainLivery? = nil, body: Int? = nil, band: Int? = nil,
                             face: Int? = nil, single: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            guard let asset = Map3DSceneKit.asset(id: id) else { preconditionFailure("No scene-kit subject \(id).") }
            var recipe = SceneKitBuilder.trainRecipe(asset)
            if let colour = livery?.body ?? body { recipe.style.body = Map3DColor.rgb(UInt32(colour)) }
            if let colour = livery?.stripe ?? band { recipe.tint = Map3DColor.rgb(UInt32(colour)) }
            var head = baked(SceneKitCab(style: recipe.style, asset: asset, tail: false, tint: recipe.tint).model(), tint: recipe.tint)
            var tail = baked(SceneKitCab(style: recipe.style, asset: asset, tail: true, tint: recipe.tint).model(), tint: recipe.tint)
            if let face {
                head = head.painting(recipe.style.body, within: recipe.style.nose, as: Map3DColor.rgb(UInt32(face)))
                tail = tail.painting(recipe.style.body, within: recipe.style.nose, as: Map3DColor.rgb(UInt32(face)))
            }
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

    /// A railcar set with flat ends: its cars are the scene kit's
    /// subject's middle car, closed at the cab ends by a yellow face with a
    /// gangway door, two windscreens and lamps.
    static func railcar(_ key: String, asset id: String, single: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            guard let asset = Map3DSceneKit.asset(id: id) else { preconditionFailure("No scene-kit subject \(id).") }
            var recipe = SceneKitBuilder.trainRecipe(asset)
            recipe.style.body = Map3DColor.rgb(0xBFC8C9)
            // A thin band under the windows, not a wide one.
            recipe.style.band = 0.36...0.40
            let band = Map3DColor.rgb(0xE89A27)
            let car = Map3DTrainBuilder(style: recipe.style, cab: false).model(named: key)
            func ends(_ ends: [(Float, Bool)]) -> Map3DModelPack.Model {
                var builder = SceneKitBuilder()
                builder.addModel(car, tint: band)
                for (end, head) in ends { builder.flatEnd(end: end, at: car.maximum.x, style: recipe.style, face: band, head: head) }
                return .flat(named: key, from: builder.mesh)
            }
            return Cars(head: ends([(1, true)]), middle: baked(car, tint: band), tail: ends([(1, false)]).turned,
                        single: single ? ends([(1, true), (-1, false)]) : nil)
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
    /// This model with its `colour` within `depth` of its front painted
    /// `paint` (a cab car's face in its own colour).
    func painting(_ colour: UInt32, within depth: Float, as paint: UInt32) -> Map3DModelPack.Model {
        let from = maximum.x - depth
        let vertices = self.vertices.map { v in
            v.x > from && v.color == colour ? Map3DVertex(Map3DPoint(v.x, v.y, v.z), normal: Map3DPoint(v.nx, v.ny, v.nz), color: paint, layer: v.layer) : v
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: minimum, maximum: maximum)
    }

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
    /// A flat cab end at `end` × `x`: the face in `face`'s colour, the
    /// gangway door between two windscreens, the lamps (white at the head,
    /// red at the tail) and the coupler.
    mutating func flatEnd(end: Float, at x: Float, style: Map3DTrainStyle, face colour: UInt32, head: Bool) {
        let face = end * x, floor = style.floor, width = 2 * style.halfWidth
        box(face + end * 0.03, floor, 0, 0.06, width - 0.06, style.roof - floor - 0.12, colour)
        box(face + end * 0.07, floor + 0.05, 0, 0.04, 0.78, 1.95, Map3DTrainStyle.doorColour)
        box(face + end * 0.095, floor + 1.15, 0, 0.02, 0.46, 0.6, Map3DTrainStyle.glass)
        for z: Float in [-0.95, 0.95] { box(face + end * 0.08, floor + 1.35, z, 0.04, 0.8, 0.75, Map3DTrainStyle.glass) }
        let lamp = head ? Map3DTrainStyle.headlamp : Map3DPalette.lantern
        for z: Float in [-0.95, 0.95] {
            let start = mesh.vertices.count
            box(face + end * 0.09, floor + 0.55, z, 0.08, 0.22, 0.2, lamp)
            mesh.makeGlowing(from: start)
        }
        box(face + end * 0.15, 0.55, 0, 0.3, 0.4, 0.3, Map3DTrainStyle.under)
    }
}
