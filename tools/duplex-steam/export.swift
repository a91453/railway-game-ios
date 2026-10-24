import Foundation
import GamePresentation

guard CommandLine.arguments.count == 2 else { fatalError("usage: duplex-steam-export OUTPUT") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let models = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
var records: [[String: Any]] = []
@MainActor func export(_ model: Map3DModelPack.Model, category: String, family: String = "comparison") throws {
    guard model.triangleCount > 0, model.triangleCount <= Map3DModelFile.maximumTriangles else { fatalError("triangle budget") }
    let provenance: [String: Any] = [
        "asset": ["generator": "native-duplex-steam-export", "version": "1.0"],
        "extras": ["assetId": model.name, "recipeVersion": 1, "source": category == "comparison" ? "existing-project-style-comparison" : "owner-eleven-view-duplex-locomotive-tender-proportional-reconstruction", "coordinateSystem": "metres; +x front, +y left, +z up"]
    ]
    let metadata = try JSONSerialization.data(withJSONObject: provenance, options: .sortedKeys)
    var data = Data("M3DM".utf8)
    func u16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
    func u32(_ n: UInt32) { for shift: UInt32 in [0, 8, 16, 24] { data.append(UInt8((n >> shift) & 255)) } }
    u16(1); u16(0); u32(UInt32(model.triangleCount)); u32(UInt32(metadata.count)); data.append(metadata)
    data.append(contentsOf: repeatElement(UInt8(0), count: (4 - metadata.count % 4) % 4))
    for start in stride(from: 0, to: model.vertices.count, by: 3) {
        let triangle = model.vertices[start..<start + 3]
        u32(triangle.contains { $0.glows } ? 1 : 0)
        for v in triangle { u32(v.x.bitPattern); u32(v.y.bitPattern); u32(v.z.bitPattern); u32(v.color) }
    }
    let decoded = try Map3DModelFile(decoding: data, named: model.name)
    guard decoded.model.vertices.count == model.vertices.count else { fatalError("readback vertex mismatch") }
    for (a, b) in zip(decoded.model.vertices, model.vertices) {
        guard a.position == b.position, a.color == b.color, a.layer == b.layer,
              abs(a.nx - b.nx) < 0.00001, abs(a.ny - b.ny) < 0.00001, abs(a.nz - b.nz) < 0.00001 else { fatalError("readback mismatch") }
    }
    try data.write(to: models.appendingPathComponent(model.name + ".m3dmodel"), options: .atomic)
    records.append(["id": model.name, "name": model.name, "category": category, "family": family, "native": "models/\(model.name).m3dmodel", "triangles": model.triangleCount,
                    "minimum": [model.minimum.x, model.minimum.y, model.minimum.z], "maximum": [model.maximum.x, model.maximum.y, model.maximum.z]])
}
for unit in Map3DDuplexSteam.Unit.allCases { try export(Map3DDuplexSteam.model(unit), category: "section", family: "steam") }
try export(Map3DDuplexSteam.formation(), category: "formation", family: "steam")
try export(Map3DFourCarMetro.model(.leading), category: "comparison")
try export(Map3DSevenSectionLRT.model(.leading), category: "comparison")
var componentRecords: [String: Any] = [:]
for unit in Map3DDuplexSteam.Unit.allCases {
    var start = 0
    componentRecords["duplex-\(unit.rawValue)"] = Map3DDuplexSteam.components(unit).map { p -> [String: Any] in
        let record: [String: Any] = ["name":p.name,"role":p.role,"start_triangle":start,"triangles":p.model.triangleCount]
        start += p.model.triangleCount
        return record
    }
}
try JSONSerialization.data(withJSONObject:componentRecords,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("components.json"))
let manifest: [String: Any] = ["schema_version":1,"generator":"native-duplex-steam-export","recipe_version":1,"model_count":records.count,
    "native_coordinates":"metres; +x front, +y left, +z up","gltf_coordinates":"metres; +x front, +y up, -z left",
    "directions":["top","bottom","left","right","front","back","isometric"],"models":records,
    "assemblies":["steam":["centres_x_m":Map3DDuplexSteam.Unit.allCases.map { $0.centre },"rotations_radians":[0,0],"body_gap_m":0.50,"hidden_running_gear":"six visible near-equal locomotive axle groups in two triples; four tender axles displayed. Exact real type, concealed axles and articulation unconfirmed"]],"static":true]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported locomotive, tender, complete formation and two style comparisons with native readback.")
