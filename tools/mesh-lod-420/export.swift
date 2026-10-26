import Foundation
import GameCore
@testable import GamePresentation

// Decision 420: each subject's front car (or the bus) whole, at each
// share the game's own simplifier leaves, its far model made in code
// (decisions 408, 410 and 420's), and the box drawn past them. Written as
// M3DM files with a manifest for render.mjs (tools/train-modeling-410's
// format), and the triangle counts printed.
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

/// The model with the line's colour (alpha below 1) painted the blue the
/// map paints a line.
func painted(_ model: Map3DModelPack.Model) -> [Map3DVertex] {
    model.vertices.map { v in
        let colour = v.color >> 24 == 0xFF ? v.color : SceneKitBuilder.baked(v.color, tint: Map3DColor.rgb(0x2F6DB5))
        return Map3DVertex(v.position, normal: .zero, color: colour, layer: v.layer)
    }
}

/// The box the map draws past the models: the model's bounds, grey.
func box(_ model: Map3DModelPack.Model) -> [Map3DVertex] {
    let lo = model.minimum, hi = model.maximum, grey = Map3DColor.rgb(0x9AA0A4)
    let p = (0..<8).map { i in Map3DPoint(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z) }
    let quads = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
    return quads.flatMap { q in [q[0], q[1], q[2], q[0], q[2], q[3]].map { Map3DVertex(p[$0], normal: .zero, color: grey) } }
}

let pack = Map3DModelPack.standard
func named(_ name: String) -> Map3DModelPack.Model { pack.models[pack.index(of: name)!] }
func head(_ key: String) -> Map3DModelPack.Model {
    if key.hasPrefix("emu3000") { return named(Map3DEMU3000.gameName(Map3DEMU3000.unit(at: 0, count: 6), far: key == "emu3000Far")) }
    return named(Map3DTrainSet.byKey[key]!.headName)
}

let shares = [0.5, 0.25, 0.1]
var subjects: [(String, Map3DModelPack.Model, Map3DModelPack.Model?)] = [
    ("set-taroko", head("taroko"), head("tarokoFar")),
    ("set-emu800", head("emu800"), head("emu800Far")),
    ("set-emu3000", head("emu3000"), head("emu3000Far")),
    ("set-E500CK", head("E500CK"), head("E500CKFar")),
    ("set-highSpeed", head("highSpeed"), head("highSpeedFar")),
]
subjects.append(("bus-route", Map3DLowFloorBus.routeModel(), nil))
var report: [String] = []
for (group, model, far) in subjects {
    let started = Date()
    let levels = model.simplified(to: shares)
    let took = Date().timeIntervalSince(started)
    try write(group + "-100", painted(model), group: group)
    for (share, level) in zip(shares, levels) { try write(group + "-\(Int(share * 100))", painted(level), group: group) }
    if let far { try write(group + "-hand", painted(far), group: group) }
    try write(group + "-box", box(model), group: group)
    report.append("\(group): \(model.triangleCount) / " + levels.map { "\($0.triangleCount)" }.joined(separator: " / ")
        + (far.map { " hand \($0.triangleCount)" } ?? "") + String(format: " (%.2f s)", took))
}
try JSONSerialization.data(withJSONObject: ["models": records], options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("manifest.json"))
print(report.joined(separator: "\n"))

// How long each set takes to build, near and far (the far set made in
// code), against the simplifier's time above.
for key in ["taroko", "tarokoFar", "emu800", "emu800Far", "emu3000", "emu3000Far", "E500CK", "E500CKFar", "highSpeed", "highSpeedFar"] {
    let started = Date()
    let cars = Map3DTrainSet.byKey[key]!.build()
    let took = Date().timeIntervalSince(started)
    let count = [cars.head, cars.middle, cars.tail, cars.pantograph].compactMap { $0?.triangleCount }
    print(String(format: "build %@: %.3f s, head/car/tail/panto %@", key, took, count.map(String.init).joined(separator: "/")))
}
