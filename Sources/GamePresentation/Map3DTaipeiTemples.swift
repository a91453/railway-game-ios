import Foundation
import GameCore

// Decision 725: nine of Taipei's temples and a church in their own shape,
// from the Taipei City Government Department of Civil Affairs' "臺北市宗教建築
// 3D 模型庫" (data.gov.tw dataset 121136, Open Government Data License
// version 1.0). `tools/tpe-temples/` reads each temple's KMZ, keeps its
// shape only (no photo or texture), simplifies it and paints it in the
// game's colours as a `.m3dmodel`; the app bundles them as
// `Resources/Models/tpe-*.m3dmodel` and hands them to the scene with the
// temples file (``RealTemples/landmarks``). Each stands where its KMZ puts
// it, as decision 457's landmarks do, and replaces the temple kit's
// generic temple (decision 331) on the ground it takes.

/// Decision 725: the Taipei temples drawn in their own shape.
public enum Map3DTaipeiTemple: String, CaseIterable, Sendable {
    /// 艋舺龍山寺 and its gateway (108003, 108003A).
    case longshan
    /// 行天宮 (104001).
    case xingtian
    /// 指南宮 (116001).
    case zhinan
    /// 臺灣省城隍廟 (100001).
    case provincialCityGod
    /// 台北霞海城隍廟 (103002).
    case xiahaiCityGod
    /// 臺北天后宮 (108001).
    case tianhou
    /// 艋舺清水巖祖師廟 (108004).
    case qingshui
    /// 濟南基督長老教會 (100005).
    case jinanChurch
    /// 士林慈諴宮 (111001_01).
    case cixian
    /// 芝山岩惠濟宮 (111003).
    case huiji

    /// The file's name (and ``fileExtension``) in the app's resources.
    public var fileName: String {
        switch self {
        case .longshan: "tpe-temple-longshan"
        case .xingtian: "tpe-temple-xingtian"
        case .zhinan: "tpe-temple-zhinan"
        case .provincialCityGod: "tpe-temple-provincial-city-god"
        case .xiahaiCityGod: "tpe-temple-xiahai-city-god"
        case .tianhou: "tpe-temple-tianhou"
        case .qingshui: "tpe-temple-qingshui"
        case .jinanChurch: "tpe-church-jinan"
        case .cixian: "tpe-temple-cixian"
        case .huiji: "tpe-temple-huiji"
        }
    }

    public static let fileExtension = "m3dmodel"

    /// Where the model's origin stands: its KMZ's point
    /// (`tools/tpe-temples/` writes them in `placements.json`). The model
    /// is in metres east (+x), north (+y) and up of it.
    var latitude: Double {
        switch self {
        case .longshan: 25.037196
        case .xingtian: 25.06306
        case .zhinan: 24.98041
        case .provincialCityGod: 25.043857
        case .xiahaiCityGod: 25.055595
        case .tianhou: 25.042954
        case .qingshui: 25.040243
        case .jinanChurch: 25.043433
        case .cixian: 25.089482
        case .huiji: 25.102936
        }
    }

    var longitude: Double {
        switch self {
        case .longshan: 121.499888
        case .xingtian: 121.533825
        case .zhinan: 121.588707
        case .provincialCityGod: 121.512702
        case .xiahaiCityGod: 121.510162
        case .tianhou: 121.506365
        case .qingshui: 121.50255
        case .jinanChurch: 121.519496
        case .cixian: 121.52463
        case .huiji: 121.530721
        }
    }

    /// The models read from `files`, each that reads, fits within
    /// ``Map3DModelFile/maximumTriangles`` and paints no texture; a file
    /// that does not is left out (its temple keeps the kit's).
    public static func models(files: [Map3DTaipeiTemple: URL]) -> [Map3DTaipeiTemple: Map3DModelPack.Model] {
        var models: [Map3DTaipeiTemple: Map3DModelPack.Model] = [:]
        for (temple, url) in files {
            guard let data = try? Data(contentsOf: url), let file = try? Map3DModelFile(decoding: data, named: temple.fileName),
                  file.model.texture == nil else { continue }
            models[temple] = file.model
        }
        return models
    }

    /// The model in the scene (x east, y up, z south) with its origin on
    /// `origin` and its ground `ground` high.
    static func placed(_ model: Map3DModelPack.Model, origin: Map3DPoint, ground: Float, roofOnly: Bool) -> Map3DMesh {
        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(model.vertices.count)
        for first in stride(from: 0, to: model.vertices.count - 2, by: 3) {
            // From afar, only what faces the sky: the roofs and the
            // courtyards, which are what a temple is from there.
            if roofOnly, model.vertices[first].nz < 0.3 { continue }
            for v in model.vertices[first..<(first + 3)] {
                vertices.append(Map3DVertex(Map3DPoint(v.x + origin.x, v.z + ground, -v.y + origin.z), normal: Map3DPoint(v.nx, v.nz, -v.ny),
                                            color: v.color, layer: v.layer))
            }
        }
        return Map3DMesh(vertices: vertices, indices: (0..<UInt32(vertices.count)).map { $0 })
    }

    /// Decision 457's margin: the 64 m cells within this many metres of
    /// the model's shape keep no city lot, real building or prop.
    static let clearingMargin: Float = 6
}

extension Map3DScene.Builder {
    /// Decision 725: the Taipei temples `temples` carries models of, each
    /// where it stands when the scene holds its origin and neither the
    /// player's track nor a platform runs within it: in full close by,
    /// only its roofs and courtyards from afar. Returns the 64 m cells of
    /// the ground each clears, which keep no city lot, real building,
    /// prop or kit temple.
    mutating func addTaipeiTemples(_ temples: RealTemples, frame: RealWorldFrame) -> Set<Map3DScene.ChunkKey> {
        var cleared = Set<Map3DScene.ChunkKey>()
        for temple in Map3DTaipeiTemple.allCases {
            guard let model = temples.landmarks[temple] else { continue }
            let place = frame.worldPosition(latitude: temple.latitude, longitude: temple.longitude)
            guard contains(x: place.x, y: place.y) else { continue }
            let centre = point(x: place.x, y: place.y, height: 0)
            let body = [(model.minimum.x, model.minimum.y), (model.maximum.x, model.minimum.y),
                        (model.maximum.x, model.maximum.y), (model.minimum.x, model.maximum.y)]
                .map { Map3DPoint($0.0 + centre.x, 0, -$0.1 + centre.z) }
            guard isClearOfTrack(body) else { continue }
            let ground = body.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0
            let saved = target
            var shape = Map3DMesh()
            for (level, roofOnly) in [(Target.near, false), (.far, true)] {
                target = level
                let mesh = Map3DTaipeiTemple.placed(model, origin: centre, ground: ground, roofOnly: roofOnly)
                if !roofOnly { shape = mesh }
                keptColours.formUnion(mesh.vertices.map(\.color))
                self.mesh(at: centre) { $0.append(mesh) }
            }
            target = saved
            cleared.formUnion(cells(under: shape, margin: Map3DTaipeiTemple.clearingMargin))
        }
        return cleared
    }
}
