import Foundation
import GameCore
@testable import GamePresentation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let modelsDir = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
let carLength = Float(TrainType.c.spec.carLength) / Float(WorldCoordinate.unitsPerMetre) - Map3DTrains.carGap
var records: [[String: Any]] = []

@MainActor func write(_ name: String, _ vertices: [Map3DVertex], note: String) throws {
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
    var lo = Map3DPoint(.infinity, .infinity, .infinity), hi = Map3DPoint(-.infinity, -.infinity, -.infinity)
    for v in vertices { lo = Map3DPoint(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z)); hi = Map3DPoint(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z)) }
    records.append(["id": name, "native": "models/\(name).m3dmodel", "note": note, "triangles": vertices.count / 3,
                    "minimum": [lo.x, lo.y, lo.z], "maximum": [hi.x, hi.y, hi.z]])
}

/// The train as the map draws it: car i its model stretched to carLength, cars 0.6 m apart,
/// optionally bent: each car turned by `bend` radians more than the one in front (a curve).
func train(_ cars: [Map3DModelPack.Model], bend: Float = 0) -> ([Map3DVertex], [Float]) {
    var out: [Map3DVertex] = []
    var stretches: [Float] = []
    var front = Map3DPoint(0, 0, 0), angle: Float = 0
    for model in cars {
        let s = carLength / model.length
        stretches.append(s)
        let mid = (model.minimum.x + model.maximum.x) / 2
        let dir = Map3DPoint(cosf(angle), sinf(angle), 0), left = Map3DPoint(-sinf(angle), cosf(angle), 0)
        let centre = front - dir * (carLength / 2)
        for v in model.vertices {
            let p = centre + dir * ((v.x - mid) * s) + left * v.y + Map3DPoint(0, 0, v.z)
            out.append(Map3DVertex(p, normal: .zero, color: v.color, layer: v.layer))
        }
        front = centre - dir * (carLength / 2 + Map3DTrains.carGap)
        angle += bend
    }
    return (out, stretches)
}

func set(_ s: Map3DTrainSet, count: Int) -> [Map3DModelPack.Model] {
    let c = s.build()
    if count == 2 { return [c.head, c.tail!] }
    return [c.head, c.middle!] + Array(repeating: c.middle!, count: count - 3) + [c.tail!]
}
var report: [String] = []
@MainActor func option(_ name: String, _ cars: [Map3DModelPack.Model], note: String) throws {
    let (straight, s) = train(cars)
    let (curved, _) = train(cars, bend: 0.12)
    try write(name, straight, note: note)
    try write(name + "-curve", curved, note: note + " (curve)")
    report.append("\(name): lengths \(cars.map { String(format: "%.2f", $0.length) }) stretch \(s.map { String(format: "%.3f", $0) }) tris \(cars.map(\.triangleCount))")
}
let five = Map3DFiveSectionLRT.formation(), seven = Map3DSevenSectionLRT.formation()
let lamps5 = Map3DTrainSet.Lamps(x: 16.935, height: 0.79, across: 0.68, width: 0.30, tall: 0.09)
let lamps7 = Map3DTrainSet.Lamps(x: 22.675, height: 0.81, across: 0.67, width: 0.28, tall: 0.10)
try option("five-A-mid", set(Map3DTrainSet.articulated("x", formation: five, cuts: [0], lamps: lamps5), count: 2), note: "five, cut mid-module, bodies meet in gap")
try option("five-B-joint", set(Map3DTrainSet.articulated("x", formation: five, cuts: [3.6], lamps: lamps5), count: 2), note: "five, cut at a real joint")
try option("seven-A-panel", set(Map3DTrainSet.articulated("x", formation: seven, cuts: [7.08, -7.08], lamps: lamps7), count: 3), note: "seven, cut on the panel between window and door")
try option("seven-E-doors", set(Map3DTrainSet.articulated("x", formation: seven, cuts: [7.83, -7.83], lamps: lamps7), count: 3), note: "seven, cut at door centres")
try option("seven-B-thirds", set(Map3DTrainSet.articulated("x", formation: seven, cuts: [7.583, -7.583], lamps: lamps7), count: 3), note: "seven, equal thirds")
try option("seven-C-joints", set(Map3DTrainSet.articulated("x", formation: seven, cuts: [9.35, -9.35], lamps: lamps7), count: 3), note: "seven, at real joints")
try option("seven-D-two", set(Map3DTrainSet.articulated("x", formation: seven, cuts: [0], lamps: lamps7), count: 2), note: "seven as two cars")
let tram = Map3DTrainSet.byKey["greenTram"]!
try option("tram-2", set(tram, count: 2), note: "green tram 2 cars (locked)")
try option("tram-3", set(tram, count: 3), note: "green tram 3 cars (locked)")
try JSONSerialization.data(withJSONObject: ["models": records], options: [.prettyPrinted]).write(to: output.appendingPathComponent("manifest.json"))
print(report.joined(separator: "\n"))
