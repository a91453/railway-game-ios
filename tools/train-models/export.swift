import Foundation
import GameCore
@testable import GamePresentation

// The shared train-model tool's exporter (tools/train-models/README.md).
// Writes the pack's train models as M3DM files, a manifest (triangles, box,
// FNV-1a hash of every vertex field, the near/far pairs of every train
// set) and the game's light at the two hours the renderer uses.
//
//   export OUT [--tag NAME] [--ids a,b,c] [--all] [--lock FILE]
//
// Without `--ids` the models are the pack's trains (`set-*` and `style-*`).
// `--lock FILE` writes the hash of EVERY model in the pack to FILE (the
// baseline `check.mjs` compares against) and nothing else.
let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let at = arguments.firstIndex(of: name), at + 1 < arguments.count else { return nil }
    return arguments[at + 1]
}
guard let outputPath = arguments.first, !outputPath.hasPrefix("--") else { fatalError("usage: export OUT [--tag NAME] [--ids a,b] [--lock FILE]") }
let tag = option("--tag") ?? "after"
let pack = Map3DModelPack.standard

/// Every vertex field, FNV-1a: the function the pinning tests use
/// (Map3DEMU800IntegrationTests `hash`), so a hash here is one a test can pin.
func hash(_ model: Map3DModelPack.Model) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for v in model.vertices {
        for word in [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
                     v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern] {
            for shift in stride(from: 0, to: 32, by: 8) { h = (h ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100000001b3 }
        }
    }
    return String(h, radix: 16)
}

func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

if let lock = option("--lock") {
    var entries: [String: Any] = [:]
    for model in pack.models { entries[model.name] = ["triangles": model.triangleCount, "hash": hash(model)] }
    try json(["comment": "FNV-1a of every vertex field of every model in Map3DModelPack.standard (tools/train-models/export.swift). A changed value is a deliberate model change the PR must justify.", "models": entries]).write(to: URL(fileURLWithPath: lock))
    print("locked \(entries.count) models in \(lock)")
    exit(0)
}

let output = URL(fileURLWithPath: outputPath, isDirectory: true)
let modelsDir = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

func nativeFile(_ model: Map3DModelPack.Model) throws -> Data {
    var data = Data("M3DM".utf8)
    let meta = try JSONSerialization.data(withJSONObject: ["extras": ["assetId": model.name]])
    func u16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
    func u32(_ n: UInt32) { for s: UInt32 in [0, 8, 16, 24] { data.append(UInt8((n >> s) & 255)) } }
    u16(1); u16(0); u32(UInt32(model.vertices.count / 3)); u32(UInt32(meta.count)); data.append(meta)
    data.append(contentsOf: repeatElement(UInt8(0), count: (4 - meta.count % 4) % 4))
    for start in stride(from: 0, to: model.vertices.count, by: 3) {
        let t = model.vertices[start..<start + 3]
        // Bit 0 lit at night; decision 450: bit 1 glass, bit 2 stainless
        // (Map3DTrainMaterial), for renderer.js's `--features 1`.
        let layer = t.first!.layer
        let glass: UInt32 = layer == Map3DVertex.trainGlass || layer == Map3DVertex.trainGlassLit ? 2 : 0
        let steel: UInt32 = layer == Map3DVertex.trainSteel ? 4 : 0
        u32((t.contains { $0.glows } ? 1 : 0) | glass | steel)
        for v in t { u32(v.x.bitPattern); u32(v.y.bitPattern); u32(v.z.bitPattern); u32(v.color) }
    }
    return data
}

// Which models, and which are far versions of which near ones.
var wanted: [String]
if let ids = option("--ids") {
    wanted = ids.split(separator: ",").map(String.init)
    for id in wanted where pack.index(of: id) == nil { fatalError("no model \(id) in Map3DModelPack.standard") }
} else {
    wanted = pack.models.map(\.name).filter { $0.hasPrefix("set-") || $0.hasPrefix("style-") }
}
var farOf: [String: String] = [:]
var sets: [[String: Any]] = []
for key in Map3DTrainSet.byKey.keys.sorted() {
    let set = Map3DTrainSet.byKey[key]!
    let prefix = "set-\(key)-"
    let units = pack.models.map(\.name).filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("-") }
    var record: [String: Any] = ["key": key, "units": units.map { String($0.dropFirst(prefix.count)) }]
    if let far = set.far {
        record["far"] = far
        for unit in units {
            let farName = "set-\(far)-" + unit.dropFirst(prefix.count)
            if pack.index(of: farName) != nil { farOf[unit] = farName }
        }
    }
    sets.append(record)
}
let wantedSet = Set(wanted)
for (near, far) in farOf where wantedSet.contains(near) && !wantedSet.contains(far) { wanted.append(far) }

func box(_ m: Map3DModelPack.Model) -> [String: Any] {
    ["minimum": [m.minimum.x, m.minimum.y, m.minimum.z], "maximum": [m.maximum.x, m.maximum.y, m.maximum.z]]
}
var records: [[String: Any]] = []
let farNames = Set(farOf.values)
for id in wanted {
    let model = pack.models[pack.index(of: id)!]
    try nativeFile(model).write(to: modelsDir.appendingPathComponent(id + ".m3dmodel"))
    var record: [String: Any] = ["id": id, "native": "models/\(id).m3dmodel", "triangles": model.triangleCount, "hash": hash(model),
                                 "role": farNames.contains(id) ? "far" : "near", "glowTriangles": stride(from: 0, to: model.vertices.count, by: 3).filter { model.vertices[$0..<$0 + 3].contains { $0.glows } }.count,
                                 "glassTriangles": stride(from: 0, to: model.vertices.count, by: 3).filter { [Map3DVertex.trainGlass, Map3DVertex.trainGlassLit].contains(model.vertices[$0].layer) }.count,
                                 "steelTriangles": stride(from: 0, to: model.vertices.count, by: 3).filter { model.vertices[$0].layer == Map3DVertex.trainSteel }.count]
    record.merge(box(model)) { a, _ in a }
    if let far = farOf[id] { record["far"] = far }
    records.append(record)
}

// The game's light, as the shaders get it (Map3DMetalView.uniformValues):
// 14:00, where the soft light's ratio is 1, and 23:00 with the lights on.
func light(_ minute: Double) -> [String: Any] {
    let l = Map3DLighting(minute: minute)
    func v(_ s: SIMD3<Float>) -> [Float] { [s.x, s.y, s.z] }
    return ["minute": minute, "sunDirection": [l.sunDirection.x, l.sunDirection.y, l.sunDirection.z], "sunLight": v(l.sunLight),
            "skyLight": v(l.skyLight), "groundLight": v(l.groundLight), "lights": l.lights, "lampGlow": v(l.lampGlow(SIMD3<Float>(1, 1, 1))), "fogColour": v(l.fogColour),
            // Decision 450: what the glass mirrors (Map3DReflection.rows).
            "zenith": v(Map3DSky(l).zenith), "sunShown": Map3DSky(l).sunShown,
            "glint": Array(Map3DReflection.rows(sky: Map3DSky(l), sunLight: l.sunLight, quality: .high, seconds: 0, reduceMotion: true)[8..<11])]
}
let manifest: [String: Any] = ["schema_version": 1, "tag": tag, "model_count": records.count, "models": records, "sets": sets,
                               "lighting": ["day": light(14 * 60), "night": light(23 * 60)],
                               "native_coordinates": "metres; +x front, +y left, +z up; alpha 0 = the line's colour"]
try json(manifest).write(to: output.appendingPathComponent("manifest.json"))
print("wrote \(records.count) models to \(outputPath)")
