import Foundation
import GamePresentation

guard CommandLine.arguments.count == 2 else { fatalError("usage: emu500-export OUTPUT") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let models = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
var records: [[String: Any]] = []
@MainActor func export(_ model: Map3DModelPack.Model, category: String) throws {
    guard model.triangleCount > 0, model.triangleCount <= Map3DModelFile.maximumTriangles else { fatalError("triangle budget") }
    let provenance: [String: Any] = [
        "asset": ["generator": "Map3DEMU500", "version": "1.0"],
        "extras": ["assetId": model.name, "recipeVersion": 1, "source": "owner-six-image-reconstruction-and-sourced-formation", "coordinateSystem": "metres; +x front, +y left, +z up"]
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
    records.append(["id": model.name, "name": model.name, "category": category, "native": "models/\(model.name).m3dmodel", "triangles": model.triangleCount,
                    "minimum": [model.minimum.x, model.minimum.y, model.minimum.z], "maximum": [model.maximum.x, model.maximum.y, model.maximum.z]])
}
for unit in Map3DEMU500.Unit.allCases { try export(Map3DEMU500.model(unit), category: "section") }
try export(Map3DEMU500.formation(), category: "formation")
try export(Map3DEMU3000.model(.ed), category: "comparison")
let placements = Map3DEMU500.order.enumerated().map { i, unit in
    ["index": i, "unit": unit.rawValue, "x_m": Map3DEMU500.centres[i],
     "rotation_deg": Map3DEMU500.rotations[i] * 180 / Float.pi] as [String : Any]
}
let manifest: [String: Any] = ["schema_version": 1, "generator": "Map3DEMU500", "recipe_version": 1, "model_count": records.count,
    "native_coordinates": "metres; +x front, +y left, +z up", "gltf_coordinates": "metres; +x front, +y up, -z left",
    "directions": ["top", "bottom", "left", "right", "front", "back", "isometric"], "models": records,
    "native_palette": ["body": Map3DEMU500.silver & 0x00ffffff, "accent": Map3DEMU500.accent & 0x00ffffff,
        "glass": Map3DEMU500.glass & 0x00ffffff, "frame": Map3DEMU500.frameColor & 0x00ffffff,
        "mask": Map3DEMU500.maskColor & 0x00ffffff, "rubber": Map3DEMU500.rubberColor & 0x00ffffff,
        "roof": Map3DEMU500.roofColor & 0x00ffffff, "lamp": Map3DEMU500.lampColor & 0x00ffffff],
    "assembly": ["placements": placements, "coupled_length_m": 81.32, "static": true]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
print("Exported four distinct units, four-car formation and EMU3000 style comparison through native readback.")
