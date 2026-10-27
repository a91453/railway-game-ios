import Foundation
import GamePresentation

guard CommandLine.arguments.count == 2 else { fatalError("usage: c341-export OUTPUT") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let models = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
var records: [[String: Any]] = []
var units: [String:String] = [:]
@MainActor func export(_ model: Map3DModelPack.Model, category: String) throws {
    if category == "formation", model.triangleCount > Map3DModelFile.maximumTriangles {
        let placements = Map3DC341.arrangement.enumerated().map { i,u in
            ["unit":"c341-"+u.rawValue,"translation":[(2.5-Float(i))*Map3DC341.pitch,Float(0),Float(0)]] as [String:Any]
        }
        let scene: [String:Any] = ["format":"M3DAssembly","version":1,"units":units,"placements":placements]
        let file="models/"+model.name+".m3dscene.json"
        try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys]).write(to:output.appendingPathComponent(file))
        records.append(["id":model.name,"name":model.name,"category":category,"native":file,"native_kind":"assembly","triangles":model.triangleCount,"minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]])
        var expected=Data()
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let tri=model.vertices[i..<i+3]
            for word in [UInt32(tri.contains { $0.glows } ? 1:0)]+tri.flatMap({[$0.x.bitPattern,$0.y.bitPattern,$0.z.bitPattern,$0.color]}) {
                var le=word.littleEndian;withUnsafeBytes(of:&le){expected.append(contentsOf:$0)}
            }
        }
        try expected.write(to:output.appendingPathComponent("assembly-expected.bin"))
        return
    }
    guard model.triangleCount > 0, model.triangleCount <= Map3DModelFile.maximumTriangles else { fatalError("triangle budget") }
    let provenance: [String: Any] = [
        "asset": ["generator": "Map3DC341", "version": "1.0"],
        "extras": ["assetId": model.name, "recipeVersion": 1, "source": "four-inline-references-and-C341-photo-study-proportional-estimates", "coordinateSystem": "metres; +x front, +y left, +z up"]
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
    units[model.name]=data.base64EncodedString()
    records.append(["id": model.name, "name": model.name, "category": category, "native": "models/\(model.name).m3dmodel", "triangles": model.triangleCount,
                    "minimum": [model.minimum.x, model.minimum.y, model.minimum.z], "maximum": [model.maximum.x, model.maximum.y, model.maximum.z]])
}
for unit in Map3DC341.Unit.allCases { try export(Map3DC341.model(unit), category: "section") }
try export(Map3DC341.formation(), category: "formation")
try export(Map3DEMU3000.model(.ed), category: "comparison")
let placements = Map3DC341.arrangement.enumerated().map { i, unit in
    ["index": i, "unit": unit.rawValue, "x_m": (2.5-Float(i))*Map3DC341.pitch, "rotation_deg": 0] as [String : Any]
}
let manifest: [String: Any] = ["schema_version": 1, "generator": "Map3DC341", "recipe_version": 1, "model_count": records.count,
    "native_coordinates": "metres; +x front, +y left, +z up", "gltf_coordinates": "metres; +x front, +y up, -z left",
    "directions": ["top", "bottom", "left", "right", "front", "back", "isometric"], "models": records,
    "native_palette": ["body": Map3DC341.body & 0x00ffffff, "accent": Map3DC341.accent & 0x00ffffff,
        "glass": Map3DC341.glass & 0x00ffffff, "mask": Map3DC341.mask & 0x00ffffff],
    "assembly": ["placements": placements, "pitch_m": 23.5, "shell_gap_m": 0.4, "rail_z_m": 0, "rear_rotation_baked_deg": 180, "static": true]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
print("Exported DM, T, M, reverse DM, six-car formation and style comparison through native readback.")
var existing = Data()
for m in Map3DModelPack.standard.models where !m.name.hasPrefix("c341-") {
    existing.append(contentsOf: m.name.utf8);existing.append(0)
    for v in m.vertices {
        for word in [v.x.bitPattern,v.y.bitPattern,v.z.bitPattern,v.nx.bitPattern,v.ny.bitPattern,v.nz.bitPattern,v.color,v.layer.bitPattern] {
            var little=word.littleEndian
            withUnsafeBytes(of:&little) { existing.append(contentsOf:$0) }
        }
    }
}
try existing.write(to:output.appendingPathComponent("existing-payload.bin"))
