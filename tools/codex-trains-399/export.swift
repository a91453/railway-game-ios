import Foundation
import GameCore
@testable import GamePresentation

// Decision 399: each train before and after, laid out as `Map3DTrains.frame`
// lays it (`TrainCars.cars`, each model stretched to its car's chord as
// `Map3DTrains.instance` does), on a straight and on a 120 m curve.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let modelsDir = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
let unit = Double(WorldCoordinate.unitsPerMetre)
var records: [[String: Any]] = []
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

/// The body of a train whose head is at the origin facing +x: straight, or
/// bending left round a 120 m radius.
func body(curved: Bool) -> [TrainMotion.Point] {
    (0...160).map { i in
        let s = Double(i)
        guard curved else { return TrainMotion.Point(x: -s * unit, y: 0) }
        let r = 120.0, a = s / r
        return TrainMotion.Point(x: -r * sin(a) * unit, y: -(r - r * cos(a)) * unit)
    }
}

/// `models` (one per car, `nil` a box) along `cars`' polylines.
func lay(_ cars: [[TrainMotion.Point]], _ models: [Map3DModelPack.Model?]) -> [Map3DVertex] {
    var out: [Map3DVertex] = []
    for (car, model) in zip(cars, models) {
        guard let f = car.first, let b = car.last else { continue }
        let front = Map3DPoint(Float(f.x / unit), Float(f.y / unit), 0), back = Map3DPoint(Float(b.x / unit), Float(b.y / unit), 0)
        let along = front - back, forward = along.normalized ?? Map3DPoint(1, 0, 0), left = Map3DPoint(-forward.y, forward.x, 0)
        let model = model ?? box(length: along.length)
        let stretch = along.length / model.length, middle = (model.minimum.x + model.maximum.x) / 2
        let origin = (front + back) * 0.5 - forward * (middle * stretch)
        for v in model.vertices {
            out.append(Map3DVertex(origin + forward * (v.x * stretch) + left * v.y + Map3DPoint(0, 0, v.z), normal: .zero, color: v.color, layer: v.layer))
        }
    }
    return out
}

/// A car drawn as a box, as `Map3DTrains.frame` draws one with no model.
func box(length: Float) -> Map3DModelPack.Model {
    var b = StationKitBuilder()
    b.box(0, 0.3, 0, length, Map3DTrains.carWidth, Map3DTrains.carHeight - 0.3, Map3DTrains.body)
    b.box(0, 1.0, 0, length + 0.04, Map3DTrains.carWidth + 0.04, 0.45, Map3DTrains.band)
    return .flat(named: "box", from: b.mesh)
}

let after = Map3DModelPack.standard
var locked = Map3DModelPack.standard
locked.locked = TrainPack.sets
let ct273 = Map3DModelPack(models: Map3DTrainSet.hauled("SUMMER", locomotive: .ct273, coach: Map3DTrainSet.coach(TrainLivery.e200ChuKuang)).models())

/// A `count`-car train of `code` drawn by `pack` (its layout, else 20 m a car).
func train(_ pack: Map3DModelPack, _ code: String, _ count: Int, curved: Bool, before: Bool = false, boxes: Bool = false) -> ([Map3DVertex], String) {
    let spine = body(curved: curved), heading = TrainMotion.Point(x: 1, y: 0)
    if !before, let layout = pack.layout(forType: code, count: count) {
        let cars = TrainCars.cars(body: spine, heading: heading, lengths: layout.map { Double($0.length) * unit }, gaps: layout.map { Double($0.gap) * unit })
        let models = layout.map { pack.models[$0.model] }
        return (lay(cars, models), "\(layout.count) cars \(layout.map { String(format: "%.2f", $0.length) }) tris \(models.map(\.triangleCount).reduce(0, +))")
    }
    let cars = TrainCars.cars(body: spine, heading: heading, count: count, gap: Double(Map3DTrains.carGap) * unit)
    let models: [Map3DModelPack.Model?] = (0..<count).map { i in
        guard !boxes, let index = pack.modelIndex(forType: code, carIndex: i, count: count) else { return nil }
        let model = pack.models[index]
        return pack.isTurned(forType: code, carIndex: i, count: count) ? model.turned : model
    }
    return (lay(cars, models), "\(count) cars x 20 m tris \(models.map { $0?.triangleCount ?? 12 }.reduce(0, +))")
}

for (name, code, count, before, boxes) in [("summer", "SUMMER", 4, ct273, false), ("steam", "STEAM", 4, after, true),
                                            ("linear", "L", 4, locked, false), ("light4", "C", 4, locked, false)] {
    // Before: the CT273 stand-in's own set, the steam train as boxes, the
    // pack's sets locked (as they were).
    for curved in [false, true] {
        let suffix = curved ? "-curve" : ""
        let (old, oldNote) = train(before, code, count, curved: curved, before: true, boxes: boxes)
        let (new, newNote) = train(after, code, count, curved: curved)
        try write("\(name)-before\(suffix)", old, group: name + suffix)
        try write("\(name)-after\(suffix)", new, group: name + suffix)
        if !curved { report.append("\(name) before: \(oldNote)\n\(name) after:  \(newNote)") }
    }
}
let total = { (pack: Map3DModelPack) in pack.models.map(\.triangleCount).reduce(0, +) }
let added = after.models.filter { ["set-SUMMER-", "set-STEAM-", "set-fourCarMetro-", "set-blueSeven-"].contains(where: $0.name.hasPrefix) }
let removed = ct273.models.first { $0.name == "set-SUMMER-head" }?.triangleCount ?? 0
report.append("pack models \(after.models.count), triangles \(total(after)); this decision's sets \(added.map(\.triangleCount).reduce(0, +)) "
    + "in place of the CT273's \(removed)")
try JSONSerialization.data(withJSONObject: ["models": records], options: [.prettyPrinted]).write(to: output.appendingPathComponent("manifest.json"))
print(report.joined(separator: "\n"))
