import Foundation
import GameCore
@testable import GamePresentation

// Decision 410: every train built in code, as a short train (its head, one
// middle car and its tail, or a railcar alone) laid straight, front at the
// origin facing +x; and the scene kit's train subjects. Run once on main
// (`before`) and once on the branch (`after`) into the same directory: the
// two land in one group each, drawn with one camera (render.mjs). Built
// from tools/hsr-trains-408/export.swift.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let tag = CommandLine.arguments[2]
let modelsDir = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
let manifestURL = output.appendingPathComponent("manifest.json")
var records = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))) as? [String: Any])?["models"] as? [[String: Any]] ?? []
records.removeAll { ($0["id"] as? String)?.hasSuffix("-" + tag) == true }
var report: [String] = []

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

/// `models` front to back, each 0.4 m behind the one before, the line's
/// colour (alpha 0) painted a blue as the map paints a line.
func lay(_ models: [Map3DModelPack.Model]) -> [Map3DVertex] {
    var out: [Map3DVertex] = [], front: Float = 0
    for model in models {
        let shift = front - model.maximum.x
        for v in model.vertices {
            let colour = v.color >> 24 == 0xFF ? v.color : SceneKitBuilder.baked(v.color, tint: Map3DColor.rgb(0x2F6DB5))
            out.append(Map3DVertex(Map3DPoint(v.x + shift, v.y, v.z), normal: .zero, color: colour, layer: v.layer))
        }
        front += -model.length - 0.4
    }
    return out
}

let pack = Map3DModelPack.standard
func named(_ name: String) -> Map3DModelPack.Model? { pack.index(of: name).map { pack.models[$0] } }

var subjects: [(String, [Map3DModelPack.Model])] = []
for style in Map3DTrainStyle.all {
    let cab = named(style.name + "-cab")!, car = named(style.name + "-car")!
    subjects.append(("style-" + style.name, [cab, car, cab.turned]))
}
for key in ["emu3000", "puyuma", "taroko", "emu800", "metroC381", "wenhu", "dieselExpress", "highSpeedFar", "E200CK", "BLUE", "MINGRI", "STAR", "pushPull"] {
    let set = Map3DTrainSet.byKey[key]!
    let head = named(set.headName)!, middle = named(set.middleName)!
    let tail = named(set.tailName) ?? head.turned
    subjects.append(("set-" + key, [head, middle, tail]))
}
subjects.append(("set-dieselRailcar", [named(Map3DTrainSet.byKey["dieselRailcar"]!.singleName)!]))
for (name, models) in subjects {
    try write(name + "-" + tag, lay(models), group: name)
    report.append("\(name): " + models.map { "\($0.triangleCount)" }.joined(separator: " / "))
}
for asset in Map3DSceneKit.assets where [.traModern, .traClassic, .metro, .lightRail].contains(asset.family) {
    let model = Map3DSceneKit.model(for: asset)
    try write("kit-\(asset.id)-" + tag, lay([model]), group: "kit-\(asset.id)")
    report.append("kit \(asset.id): \(model.triangleCount)")
}
try JSONSerialization.data(withJSONObject: ["models": records], options: [.prettyPrinted, .sortedKeys]).write(to: manifestURL)
print(report.joined(separator: "\n"))
