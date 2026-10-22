import Foundation
import GamePresentation

guard CommandLine.arguments.count == 2 else { fatalError("usage: urban-three-export OUTPUT") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let models = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
var records: [[String: Any]] = []
@MainActor func export(_ model: Map3DModelPack.Model, category: String, family: String) throws {
    guard model.triangleCount > 0, model.triangleCount <= Map3DModelFile.maximumTriangles else { fatalError("triangle budget") }
    let provenance: [String: Any] = [
        "asset": ["generator": "RailwayGameThreeTrainLiveries", "version": "1.0"],
        "extras": ["assetId": model.name, "recipeVersion": 1, "source": "owner-authorized-palette-only-revision", "coordinateSystem": "metres; +x front, +y left, +z up"]
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
for unit in Map3DGreenTram.Section.allCases { try export(Map3DGreenTram.model(unit), category: "section", family: "tram") }
try export(Map3DGreenTram.formation(), category: "formation", family: "tram")
for unit in Map3DGreenCommuter.Unit.allCases { try export(Map3DGreenCommuter.model(unit), category: "section", family: "commuter") }
try export(Map3DGreenCommuter.formation(), category: "formation", family: "commuter")
for unit in Map3DThreeCarUrban.Unit.allCases { try export(Map3DThreeCarUrban.model(unit), category: "section", family: "urban") }
try export(Map3DThreeCarUrban.formation(), category: "formation", family: "urban")
try export(Map3DModelPack.standard.models.first { $0.name == "commuter-cab" }!, category: "comparison", family: "existing")
let manifest: [String: Any] = ["schema_version": 1, "generator": "RailwayGameThreeTrainLiveries", "recipe_version": 1, "model_count": records.count,
    "native_coordinates": "metres; +x front, +y left, +z up", "gltf_coordinates": "metres; +x front, +y up, -z left",
    "directions": ["top", "bottom", "left", "right", "front", "back", "isometric"], "models": records,
    "assemblies": [
        ["id":"green-tram-formation","order":["green-tram-head","green-tram-middle","green-tram-tail"],"centres_x_m":[11.04,0,-11.04]],
        ["id":"green-commuter-formation","order":["green-commuter-leading","green-commuter-trailing"],"centres_x_m":[9.86,-9.86]],
        ["id":"urban-three-formation","order":["urban-three-leading","urban-three-middle","urban-three-trailing"],"centres_x_m":[15.28,0,-15.28]]
    ],"static":true]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
print("Exported eight independent units, three formations and one unchanged project comparison with native readback.")
