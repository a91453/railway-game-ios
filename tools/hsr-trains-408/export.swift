import Foundation
import GameCore
@testable import GamePresentation

// Decision 408: the high-speed sets and the E200's Chu-Kuang set before and
// after, laid out as `Map3DTrains.frame` lays them (`TrainCars.cars`, each
// model stretched to its car's chord as `Map3DTrains.instance` does), on a
// straight and on a 120 m curve; and what each costs. Built from
// tools/codex-trains-399/export.swift.
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
    (0...360).map { i in
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
let before = Map3DModelPack(models: Map3DTrainSet.byKey["highSpeedFar"]!.models()
    + Map3DTrainSet.hauled("E200CK", locomotive: .e200, coach: Map3DTrainSet.coach(TrainLivery.e200ChuKuang)).models())

/// A `count`-car train of `code` drawn by `pack` (its layout, else 20 m a car).
func train(_ pack: Map3DModelPack, _ code: String, _ count: Int, curved: Bool, far: Bool = false) -> ([Map3DVertex], String) {
    let spine = body(curved: curved), heading = TrainMotion.Point(x: 1, y: 0)
    if let layout = pack.layout(forType: code, count: count) {
        let cars = TrainCars.cars(body: spine, heading: heading, lengths: layout.map { Double($0.length) * unit }, gaps: layout.map { Double($0.gap) * unit })
        let models = layout.map { pack.models[far ? pack.farModel(of: $0.model, forType: code, count: count) ?? $0.model : $0.model] }
        return (lay(cars, models), "\(layout.count) cars \(String(format: "%.1f", layout.map(\.length).reduce(0, +))) m tris \(models.map(\.triangleCount).reduce(0, +))")
    }
    let cars = TrainCars.cars(body: spine, heading: heading, count: count, gap: Double(Map3DTrains.carGap) * unit)
    let models: [Map3DModelPack.Model?] = (0..<count).map { i in
        guard let index = pack.modelIndex(forType: code, carIndex: i, count: count) else { return nil }
        let model = pack.models[index]
        return pack.isTurned(forType: code, carIndex: i, count: count) ? model.turned : model
    }
    return (lay(cars, models), "\(count) cars x 20 m tris \(models.map { $0?.triangleCount ?? 12 }.reduce(0, +))")
}

/// `vertices` moved `across` metres to the train's left.
func shifted(_ vertices: [Map3DVertex], _ across: Float) -> [Map3DVertex] {
    vertices.map { Map3DVertex(Map3DPoint($0.x, $0.y + across, $0.z), normal: .zero, color: $0.color, layer: $0.layer) }
}

for curved in [false, true] {
    let suffix = curved ? "-curve" : ""
    let (old, oldNote) = train(before, "highSpeedFar", 12, curved: curved)
    let (t700, t700Note) = train(after, "HSR", 12, curved: curved)
    let (_, midNote) = train(after, "HSR", 12, curved: curved, far: true)
    let (n700, n700Note) = train(after, "n700sG", 12, curved: curved)
    let (n700far, n700FarNote) = train(after, "n700sG", 12, curved: curved, far: true)
    try write("hsr-n700sg-far\(suffix)", n700far, group: "hsr" + suffix)
    try write("hsr-before\(suffix)", old, group: "hsr" + suffix)
    try write("hsr-700t\(suffix)", t700, group: "hsr" + suffix)
    try write("hsr-n700sg\(suffix)", n700, group: "hsr" + suffix)
    // The three side by side, 5 m apart: before, the 700T, the N700S-G.
    try write("hsr-together\(suffix)", shifted(old, 5) + t700 + shifted(n700, -5), group: "together" + suffix)
    let (e200old, eOldNote) = train(before, "E200CK", 4, curved: curved)
    let (e200new, eNewNote) = train(after, "E200CK", 4, curved: curved)
    try write("e200-before\(suffix)", e200old, group: "e200" + suffix)
    try write("e200-after\(suffix)", e200new, group: "e200" + suffix)
    if !curved {
        report += ["high speed before (#900, 20 m a car): \(oldNote)", "700T: \(t700Note)", "700T from 500 m (#900 at the 700T's lengths): \(midNote)",
                   "N700S-G: \(n700Note)", "N700S-G from 500 m (the light rebuild): \(n700FarNote)", "E200 Chu-Kuang before: \(eOldNote)", "E200 Chu-Kuang after: \(eNewNote)"]
    }
}
// The cabs close up: the N700S-G from the 700T's recipe, the 700T, the
// light rebuild of the author's shape.
for (name, model) in [("cab-n700sg", Map3DTrainShapeRefresh.model("refresh-n700sg-cab")), ("cab-700t", Map3DTrainShapeRefresh.model("refresh-700t-cab")),
                      ("cab-n700sg-light", Map3DN700SG.model(.a)), ("panto-n700sg", Map3DTrainShapeRefresh.model("refresh-n700sg-panto"))] {
    report.append("\(name): \(model.triangleCount) triangles, \(String(format: "%.2f", model.length)) m")
    try write(name, shifted(model.vertices, 0), group: "cabs")
}
let total = { (pack: Map3DModelPack) in pack.models.map(\.triangleCount).reduce(0, +) }
report.append("pack models \(after.models.count), triangles \(total(after))")
try JSONSerialization.data(withJSONObject: ["models": records], options: [.prettyPrinted]).write(to: output.appendingPathComponent("manifest.json"))
print(report.joined(separator: "\n"))
