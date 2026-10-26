import Foundation
import GameCore
@testable import GamePresentation

// Decision 422: the 700T's and the N700S-G's cars near and far (each
// unit of `highSpeed`, `highSpeedFar`, `n700sG`, `n700sGFar`) written as
// M3DM files with a manifest for render.mjs (tools/mesh-lod-420's format,
// `<set>-<unit>`), and their triangles a car and a twelve-car train, the
// pack's vertex data and each set's build time printed. Run on main
// first for the old far sets, then on the branch.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let modelsDir = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
var records: [[String: Any]] = []

@MainActor func write(_ name: String, _ vertices: [Map3DVertex], group: String) throws {
    var data = Data("M3DM".utf8)
    let meta = try JSONSerialization.data(withJSONObject: ["extras": ["assetId": name]])
    func u16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
    func u32(_ n: UInt32) { for s: UInt32 in [0, 8, 16, 24] { data.append(UInt8((n >> s) & 255)) } }
    u16(1); u16(0); u32(UInt32(vertices.count / 3)); u32(UInt32(meta.count)); data.append(meta)
    data.append(contentsOf: repeatElement(UInt8(0), count: (4 - meta.count % 4) % 4))
    for start in stride(from: 0, to: vertices.count, by: 3) {
        let t = vertices[start..<start + 3]
        u32(t.contains { $0.glows } ? 1 : 0)
        for v in t { u32(v.x.bitPattern); u32(v.y.bitPattern); u32(v.z.bitPattern); u32(v.color) }
    }
    try data.write(to: modelsDir.appendingPathComponent(name + ".m3dmodel"))
    records.append(["id": name, "native": "models/\(name).m3dmodel", "group": group, "triangles": vertices.count / 3])
}

let pack = Map3DModelPack.standard
let vertexStride = MemoryLayout<Map3DVertex>.stride
var lines: [String] = []
for (key, type) in [("highSpeed", "HSR"), ("highSpeedFar", "HSR"), ("n700sG", "n700sG"), ("n700sGFar", "n700sG")] {
    let set = Map3DTrainSet.byKey[key]!
    let started = Date()
    _ = set.build()
    let took = Date().timeIntervalSince(started)
    var cars: [String] = [], vertices = 0
    for model in set.models() {
        let unit = String(model.name.dropFirst("set-\(key)-".count))
        try write("\(key)-\(unit)", model.vertices, group: key)
        cars.append("\(unit) \(model.triangleCount)")
        vertices += model.vertices.count
    }
    // The twelve cars as the map lays them, near; the far set by each
    // near car's far model.
    let near = key.hasSuffix("Far") ? String(key.dropLast(3)) : key
    let laid = pack.layout(forType: near == "highSpeed" ? type : near, count: 12)!
    let train = laid.reduce(0) { total, car in
        let index = key.hasSuffix("Far") ? pack.farModel(of: car.model, forType: type, count: 12)! : car.model
        return total + pack.models[index].triangleCount
    }
    lines.append(String(format: "%@: %@; twelve cars %d; models %.2f MB; built in %.3f s", key, cars.joined(separator: ", "), train,
                        Double(vertices * vertexStride) / 1_000_000, took))
}
lines.append(String(format: "pack: %d models, %.1f MB", pack.models.count,
                    Double(pack.models.reduce(0) { $0 + $1.vertices.count } * vertexStride) / 1_000_000))
try JSONSerialization.data(withJSONObject: ["models": records], options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("manifest.json"))
print(lines.joined(separator: "\n"))
