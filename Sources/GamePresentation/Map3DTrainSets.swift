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
/// models for the locomotives, the EMU800 and the railcars) on #900's
/// shapes, baked in, so they do not take the line's colour; the metro's
/// band stays the line's. The locomotives are ``Map3DTrainLocomotive``.
public struct Map3DTrainSet: Sendable {
    /// The type's code (``TrainTypeSpec/code``) or, for a train whose type
    /// has no style, its performance's (``TrainPerformanceSpec/code``).
    public let key: String
    /// The middle cars with a pantograph (``Map3DTrainStyle/pantographCars``).
    var pantographCars: Set<Int> = []
    let build: @Sendable () -> Cars

    struct Cars {
        var head: Map3DModelPack.Model
        /// `nil` for a set only ever two cars long.
        var middle: Map3DModelPack.Model?
        var tail: Map3DModelPack.Model?
        var single: Map3DModelPack.Model?
        var pantograph: Model? = nil
        typealias Model = Map3DModelPack.Model
    }

    /// The models' names in the pack.
    var headName: String { "set-\(key)-head" }
    var middleName: String { "set-\(key)-car" }
    var tailName: String { "set-\(key)-tail" }
    var singleName: String { "set-\(key)-single" }
    var pantographName: String { "set-\(key)-panto" }

    /// The four model names and their models, in the pack's order.
    func models() -> [Map3DModelPack.Model] {
        let cars = build()
        func named(_ model: Map3DModelPack.Model, _ name: String) -> Map3DModelPack.Model {
            Map3DModelPack.Model(name: name, vertices: model.vertices, minimum: model.minimum, maximum: model.maximum)
        }
        var models = [named(cars.head, headName)]
        if let middle = cars.middle { models.append(named(middle, middleName)) }
        if let tail = cars.tail { models.append(named(tail, tailName)) }
        if let single = cars.single { models.append(named(single, singleName)) }
        if let pantograph = cars.pantograph { models.append(named(pantograph, pantographName)) }
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
            // The multiple units, by their performance (decision 237); the
            // EMU3000, the 700T and the metro as #900 has them (the author,
            // 2026-10-21), the metro's band the line's colour.
            multipleUnit("emu3000", asset: "01_TRA_modern_3x2-01", livery: TrainLivery.emu3000),
            multipleUnit("highSpeed", asset: "02_HSR_MRT_3x2-01", livery: TrainLivery.highSpeed, pantographCars: [3, 8]),
            multipleUnit("metroC381", asset: "02_HSR_MRT_3x2-02", lineColoured: true),
            multipleUnit("wenhu", asset: "02_HSR_MRT_3x2-03", lineColoured: true),
            multipleUnit("puyuma", asset: "01_TRA_modern_3x2-02", livery: TrainLivery.puyuma),
            multipleUnit("taroko", asset: "01_TRA_modern_3x2-03", livery: TrainLivery.taroko),
            // The EMU800: grey, a blue band and its blue face (the reference's
            // garage `emu800`) on #900's curved front (the author, 2026-10-21).
            multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90),
            // The DR1000 railcar and the DR3100 diesel express: silver, a thin
            // orange band, yellow-orange faces (the reference's `dr1000`,
            // `dr3100`) on #900's curved fronts.
            multipleUnit("dieselRailcar", asset: "05_TRA_classic_3x2-03", body: 0xBFC8C9, band: 0xE89A27, thinBand: true,
                         face: 0xE89A27, single: true),
            multipleUnit("dieselExpress", asset: "05_TRA_classic_3x2-04", body: 0xBFC8C9, band: 0xE89A27, thinBand: true,
                         face: 0xE89A27),
            // Decision 331: the light metro as the green low-floor tram.
            lowFloorTram("greenTram"),
            // Decision 331, later: a two-car commuter as the green
            // two-car EMU, its two cab units as they are.
            greenCommuter("greenCommuter"),
            // Decision 331, fourth: a three-car commuter as the three-car
            // urban EMU, its three units as they are; in the train pack
            // (decision 338).
            threeCarUrban("threeCarUrban"),
            // Decision 338, later: a two-car light metro as #992's
            // five-section LRT, a three-car one as its seven-section LRT,
            // each whole train cut into its cars; in the train pack.
            articulated("fiveSectionLRT", formation: Map3DFiveSectionLRT.formation(), cuts: [0],
                        lamps: Lamps(x: 16.935, height: 0.79, across: 0.68, width: 0.30, tall: 0.09)),
            articulated("sevenSectionLRT", formation: Map3DSevenSectionLRT.formation(), cuts: [7.08, -7.08],
                        lamps: Lamps(x: 22.675, height: 0.81, across: 0.67, width: 0.28, tall: 0.10)),
        ]
    }()

    static let byKey: [String: Map3DTrainSet] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// The types drawn as a set of another key: the EMU3000 and the
    /// high-speed set as their models, every metro size but the light
    /// metro as the C381, the light metro as the green tram (decision 331)
    /// and the people mover as the Wenhu line's car.
    static let byType: [String: String] = [
        "EMU3000": "emu3000", "HSR": "highSpeed",
        "A": "metroC381", "B": "metroC381", "C": "greenTram", "L": "metroC381", "D": "metroC381", "APM": "wenhu",
    ]

    /// How far from the eye a car of `key` is drawn with its model, in
    /// metres: ``Map3DTrains/modelReach``, but the green tram's cars, ten
    /// times a metro car's triangles, only half as far (decision 331).
    static func reach(of key: String) -> Float {
        named(key)?.key == "greenTram" ? tramReach : Map3DTrains.modelReach
    }

    /// Decision 338, later: the light metro's articulated sets, by their
    /// cars (the green tram's other sizes).
    static let articulatedByCount: [Int: String] = [2: "fiveSectionLRT", 3: "sevenSectionLRT"]

    static let tramReach: Float = 500

    /// The set of `key`: a set's own, or a type's (``byType``).
    static func named(_ key: String) -> Map3DTrainSet? {
        byKey[byType[key] ?? key]
    }

    /// The set of a `count`-car train of `key`: the diesel railcar's
    /// performance runs as the diesel express's (the same curves, so a
    /// train's key is always the express's), and one or two cars are a
    /// DR1000 railcar, more a DR3100 set; decision 331, later: a two-car
    /// commuter EMU of no type is the green two-car EMU, a three-car one
    /// the three-car urban EMU. Decision 338: a set in `locked` (the train
    /// pack's, until it is unlocked) is drawn as it was before it; later, a
    /// two- or three-car light metro is an articulated LRT
    /// (``articulatedByCount``).
    static func set(forKey key: String, count: Int, locked: Set<String> = []) -> Map3DTrainSet? {
        let set: Map3DTrainSet?
        if key == "dieselExpress", count <= 2 {
            set = byKey["dieselRailcar"]
        } else if key == "", count == 2 {
            set = byKey["greenCommuter"]
        } else if key == "", count == 3 {
            set = byKey["threeCarUrban"]
        } else if named(key)?.key == "greenTram", let articulated = articulatedByCount[count] {
            set = byKey[articulated]
        } else {
            set = named(key)
        }
        guard let set, locked.contains(set.key) else { return set }
        return named(key).flatMap { locked.contains($0.key) ? nil : $0 }
    }

    /// The performances that are the same trains as a type with a set
    /// (decision 252: the Chu-Kuang presets).
    static let aliases: [String: String] = [
        "e200ChuKuang": "E200CK", "e500ChuKuang": "E500CK", "r100ChuKuang": "R100CK", "r200ChuKuang": "R200CK",
        "metro": "metroC381",
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
                             thinBand: Bool = false, face: Int? = nil, single: Bool = false, pantographCars: Set<Int> = [],
                             lineColoured: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key: key, pantographCars: pantographCars) {
            guard let asset = Map3DSceneKit.asset(id: id) else { preconditionFailure("No scene-kit subject \(id).") }
            var recipe = SceneKitBuilder.trainRecipe(asset)
            if let colour = livery?.body ?? body { recipe.style.body = Map3DColor.rgb(UInt32(colour)) }
            if let colour = livery?.stripe ?? band { recipe.tint = Map3DColor.rgb(UInt32(colour)) }
            // A thin band under the windows, not a wide one.
            if thinBand { recipe.style.band = 0.36...0.40 }
            func cab(tail: Bool) -> Map3DModelPack.Model {
                let model = baked(SceneKitCab(style: recipe.style, asset: asset, tail: tail, tint: recipe.tint, lineColoured: lineColoured).model(),
                                  tint: recipe.tint, keepsShares: lineColoured)
                guard let face else { return model }
                return model.painting(recipe.style.body, within: recipe.style.nose, as: Map3DColor.rgb(UInt32(face)))
            }
            func car(pantograph: Bool) -> Map3DModelPack.Model {
                baked(Map3DTrainBuilder(style: recipe.style, cab: false, pantograph: pantograph).model(named: key),
                      tint: recipe.tint, keepsShares: lineColoured)
            }
            let head = cab(tail: false), tail = cab(tail: true), middle = car(pantograph: false)
            var one: Map3DModelPack.Model?
            if single {
                // The scene kit's railbus: the front halves of a head and a
                // tail cab car, back to back.
                var builder = SceneKitBuilder()
                builder.addModel(SceneKitCab.clipped(head, maximumX: 0, keepFront: true), tint: recipe.tint)
                builder.addModel(SceneKitCab.clipped(tail, maximumX: 0, keepFront: true), angle: .pi, tint: recipe.tint)
                one = .flat(named: key, from: builder.mesh)
            }
            return Cars(head: head, middle: middle, tail: tail.turned, single: one,
                        pantograph: pantographCars.isEmpty ? nil : car(pantograph: true))
        }
    }

    /// The green low-floor tram (#954, ``Map3DGreenTram``) as a train of
    /// the light metro's 19 m cars (decision 331): each car two of its
    /// sections coupled as the whole tram couples them, the head car's
    /// front and the last car's back its cabs, their lamps lit. A car alone
    /// is the two cab sections.
    static func lowFloorTram(_ key: String) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            func car(_ front: Map3DGreenTram.Section, _ back: Map3DGreenTram.Section) -> Map3DModelPack.Model {
                var builder = StationKitBuilder()
                let half = (Map3DGreenTram.sectionLength + Map3DGreenTram.gap) / 2
                builder.add(Map3DGreenTram.model(front), at: Map3DPoint(half, 0, 0))
                builder.add(Map3DGreenTram.model(back), at: Map3DPoint(-half, 0, 0))
                // Over the section's white lamp blocks, a hand's breadth
                // in front of its cab face.
                if front == .head { builder.tramLamps(atX: half + 5.43, colour: Map3DTrainStyle.headlamp) }
                if back == .tail { builder.tramLamps(atX: -half - 5.43, colour: Map3DPalette.lantern) }
                return .flat(named: key, from: builder.mesh)
            }
            return Cars(head: car(.head, .middle), middle: car(.middle, .middle), tail: car(.middle, .tail),
                        single: car(.head, .tail))
        }
    }

    /// Decision 331, later: #961's two units, the leading one's cab at its
    /// front and the trailing one's at its back, their lamps lit over the
    /// units' white lamp blocks.
    static func greenCommuter(_ key: String) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            func unit(_ unit: Map3DGreenCommuter.Unit, lamps x: Float, colour: UInt32) -> Map3DModelPack.Model {
                var builder = StationKitBuilder()
                builder.add(Map3DGreenCommuter.model(unit), at: .zero)
                builder.cabLamps(atX: x, colour: colour, height: 1.26, across: 0.93, width: 0.30, tall: 0.16)
                return .flat(named: key, from: builder.mesh)
            }
            let leading = unit(.leading, lamps: 9.69, colour: Map3DTrainStyle.headlamp)
            return Cars(head: leading, middle: leading, tail: unit(.trailing, lamps: -9.69, colour: Map3DPalette.lantern), single: nil)
        }
    }

    /// Decision 331, fourth: #988's three units, the leading one's cab at
    /// its front, the trailing one's at its back and the middle one with
    /// none, their lamps lit over the cabs' white lamp blocks.
    static func threeCarUrban(_ key: String) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            func unit(_ unit: Map3DThreeCarUrban.Unit, lamps x: Float?, colour: UInt32) -> Map3DModelPack.Model {
                var builder = StationKitBuilder()
                builder.add(Map3DThreeCarUrban.model(unit), at: .zero)
                if let x { builder.cabLamps(atX: x, colour: colour, height: 1.28, across: 1.02, width: 0.07, tall: 0.40) }
                return .flat(named: key, from: builder.mesh)
            }
            return Cars(head: unit(.leading, lamps: 7.515, colour: Map3DTrainStyle.headlamp),
                        middle: unit(.middle, lamps: nil, colour: 0),
                        tail: unit(.trailing, lamps: -7.515, colour: Map3DPalette.lantern), single: nil)
        }
    }

    /// Where a cab's two lit lamps stand (``StationKitBuilder/cabLamps``).
    struct Lamps {
        var x, height, across, width, tall: Float
    }

    /// Decision 338, later: a whole articulated train (`formation`, its
    /// front at +x) as the light metro's cars, cut at `cuts` (front to
    /// back), the lamps lit over the cabs' lamp blocks at `lamps.x` and
    /// −`lamps.x`. A car's length is from cut to cut (or to its nose), but
    /// the train as it is at each cut is drawn on into the gap between the
    /// cars, as far as meets the next car halfway once stretched to its
    /// car, and closed there, so a curve never shows it hollow. The cuts
    /// are on plain body, where drawing it on shows no seam.
    static func articulated(_ key: String, formation: Map3DModelPack.Model, cuts: [Float], lamps: Lamps) -> Map3DTrainSet {
        Map3DTrainSet(key: key) {
            let carLength = Float(TrainType.c.spec.carLength) / Float(WorldCoordinate.unitsPerMetre) - Map3DTrains.carGap
            let ends = [formation.maximum.x] + cuts + [formation.minimum.x]
            func car(_ index: Int) -> Map3DModelPack.Model {
                let front = ends[index], back = ends[index + 1]
                // Half the gap, in the car's own metres before stretching.
                let reach = Map3DTrains.carGap / 2 * (front - back) / carLength
                var builder = StationKitBuilder()
                builder.add(formation.cut(from: index < cuts.count ? back : back - 1, to: index > 0 ? front : front + 1,
                                          reach: (index < cuts.count ? reach : 0, index > 0 ? reach : 0)), at: .zero)
                if index == 0 { builder.cabLamps(lamps, atX: lamps.x, colour: Map3DTrainStyle.headlamp) }
                if index == cuts.count { builder.cabLamps(lamps, atX: -lamps.x, colour: Map3DPalette.lantern) }
                let model = Map3DModelPack.Model.flat(named: key, from: builder.mesh)
                return Map3DModelPack.Model(name: key, vertices: model.vertices, minimum: Map3DPoint(back, model.minimum.y, model.minimum.z),
                                            maximum: Map3DPoint(front, model.maximum.y, model.maximum.z))
            }
            return Cars(head: car(0), middle: cuts.count > 1 ? car(1) : nil, tail: car(cuts.count), single: nil)
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
    static func baked(_ model: Map3DModelPack.Model, tint: UInt32, keepsShares: Bool = false) -> Map3DModelPack.Model {
        var builder = SceneKitBuilder()
        builder.addModel(model, tint: tint, keepsShares: keepsShares)
        return .flat(named: model.name, from: builder.mesh)
    }
}

extension StationKitBuilder {
    /// The tram's two lamps lit at `x`.
    fileprivate mutating func tramLamps(atX x: Float, colour: UInt32) {
        cabLamps(atX: x, colour: colour, height: 0.88, across: 0.77, width: 0.24, tall: 0.13)
    }

    fileprivate mutating func cabLamps(_ lamps: Map3DTrainSet.Lamps, atX x: Float, colour: UInt32) {
        cabLamps(atX: x, colour: colour, height: lamps.height, across: lamps.across, width: lamps.width, tall: lamps.tall)
    }

    /// Two lit lamps `across` either side of the middle, `height` up.
    fileprivate mutating func cabLamps(atX x: Float, colour: UInt32, height: Float, across: Float, width: Float, tall: Float) {
        for z in [-across, across] {
            let start = mesh.vertices.count
            box(x, height, z, 0.02, width, tall, colour)
            mesh.makeGlowing(from: start)
        }
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

    /// Decision 338, later: this model's part from `back` to `front` along
    /// its length, each cut drawn on, as it is there, `reach` farther out
    /// (`reach.back` behind `back`, `reach.front` before `front`) and
    /// closed: every closed piece it cuts through gets a face over its
    /// outline there, in the colour most of its cut faces are.
    func cut(from back: Float, to front: Float, reach: (back: Float, front: Float)) -> Map3DModelPack.Model {
        typealias Segment = (a: Map3DPoint, b: Map3DPoint, normal: Map3DPoint, colour: UInt32)
        var vertices: [Map3DVertex] = []
        var cuts: [(plane: Float, outward: Float, reach: Float, segments: [Segment])] = [(back, -1, reach.back, []), (front, 1, reach.front, [])]
        for start in stride(from: 0, to: self.vertices.count, by: 3) {
            var polygon = Array(self.vertices[start..<start + 3])
            let normal = Map3DPoint(polygon[0].nx, polygon[0].ny, polygon[0].nz)
            for c in cuts.indices {
                let plane = cuts[c].plane, outward = cuts[c].outward
                var kept: [Map3DVertex] = [], crossing: [Map3DPoint] = []
                for (i, a) in polygon.enumerated() {
                    let b = polygon[(i + 1) % polygon.count]
                    let inA = (a.x - plane) * outward <= 0, inB = (b.x - plane) * outward <= 0
                    if inA { kept.append(a) }
                    guard inA != inB else { continue }
                    // From the same end of the edge each time, so the two
                    // triangles sharing it cut it at the same point.
                    let (p, q) = (a.x, a.y, a.z) < (b.x, b.y, b.z) ? (a, b) : (b, a)
                    let t = (plane - p.x) / (q.x - p.x)
                    var v = p
                    v.x = plane
                    v.y = p.y + (q.y - p.y) * t
                    v.z = p.z + (q.z - p.z) * t
                    kept.append(v)
                    crossing.append(v.position)
                }
                if crossing.count == 2 { cuts[c].segments.append((crossing[0], crossing[1], normal, polygon[0].color)) }
                polygon = kept
                if polygon.count < 3 { break }
            }
            guard polygon.count >= 3 else { continue }
            for j in 1..<polygon.count - 1 { vertices += [polygon[0], polygon[j], polygon[j + 1]] }
        }
        for cut in cuts where !cut.segments.isEmpty {
            // The cut's outline drawn on, each side the face it cuts.
            let shift = Map3DPoint(cut.outward * cut.reach, 0, 0)
            for segment in cut.segments where cut.reach > 0 {
                var quad = [segment.a, segment.b, segment.b + shift, segment.a + shift]
                guard var normal = (quad[1] - quad[0]).cross(quad[3] - quad[0]).normalized else { continue }
                if normal.dot(segment.normal) < 0 {
                    quad.reverse()
                    normal = normal * -1
                }
                for corner in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]] {
                    vertices.append(Map3DVertex(corner, normal: normal, color: segment.colour))
                }
            }
            vertices += Self.caps(over: cut.segments.map { ($0.a, $0.b, $0.colour) }, at: cut.plane + shift.x, outward: cut.outward)
        }
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for v in vertices {
            low = Map3DPoint(min(low.x, v.x), min(low.y, v.y), min(low.z, v.z))
            high = Map3DPoint(max(high.x, v.x), max(high.y, v.y), max(high.z, v.z))
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
    }

    /// The faces over a cut at x = `plane`: the cut's `segments` joined
    /// where they meet into pieces, each piece's outline (its convex hull)
    /// facing `outward` along x.
    private static func caps(over segments: [(Map3DPoint, Map3DPoint, UInt32)], at plane: Float, outward: Float) -> [Map3DVertex] {
        func key(_ p: Map3DPoint) -> [Int] { [Int((p.y * 10_000).rounded()), Int((p.z * 10_000).rounded())] }
        var parent: [[Int]: [Int]] = [:]
        func root(_ k: [Int]) -> [Int] {
            var k = k
            while let p = parent[k], p != k { k = p }
            return k
        }
        for (a, b, _) in segments {
            let ka = key(a), kb = key(b)
            if parent[ka] == nil { parent[ka] = ka }
            if parent[kb] == nil { parent[kb] = kb }
            let ra = root(ka), rb = root(kb)
            if ra != rb { parent[ra] = rb }
        }
        var pieces: [[Int]: (points: [(Float, Float)], colours: [UInt32: Int])] = [:]
        for (a, b, colour) in segments {
            let r = root(key(a))
            pieces[r, default: ([], [:])].points += [(a.y, a.z), (b.y, b.z)]
            pieces[r, default: ([], [:])].colours[colour, default: 0] += 1
        }
        var vertices: [Map3DVertex] = []
        let normal = Map3DPoint(outward, 0, 0)
        for root in pieces.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            guard let piece = pieces[root] else { continue }
            let hull = convexHull(piece.points)
            guard hull.count >= 3 else { continue }
            let colour = piece.colours.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? 0
            for j in 1..<hull.count - 1 {
                // The hull runs anticlockwise in (y, z), so as seen from +x;
                // turned round to face −x.
                let corners = outward > 0 ? [hull[0], hull[j], hull[j + 1]] : [hull[0], hull[j + 1], hull[j]]
                vertices += corners.map { Map3DVertex(Map3DPoint(plane, $0.0, $0.1), normal: normal, color: colour) }
            }
        }
        return vertices
    }

    /// The anticlockwise convex hull of `points` (Andrew's monotone chain).
    private static func convexHull(_ points: [(Float, Float)]) -> [(Float, Float)] {
        let sorted = points.sorted { $0 < $1 }
        guard sorted.count >= 3 else { return sorted }
        func turn(_ o: (Float, Float), _ a: (Float, Float), _ b: (Float, Float)) -> Float {
            (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
        }
        var lower: [(Float, Float)] = [], upper: [(Float, Float)] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 1e-7 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 1e-7 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
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
