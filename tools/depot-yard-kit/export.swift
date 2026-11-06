import Foundation
import GamePresentation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let directory = output.appendingPathComponent("models", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var records: [[String: Any]] = []
@MainActor func export(_ model: Map3DModelPack.Model, part: Map3DDepotYardKit.Part?, far: Bool) throws {
    precondition(model.triangleCount > 0 && (part == nil || model.triangleCount <= Map3DModelFile.maximumTriangles), "Triangle budget: \(model.name) \(model.triangleCount)")
    let provenance: [String: Any] = ["asset": ["generator": "Map3DDepotYardKit", "version": "2.0"], "extras": ["source": "game-native-procedural", "coordinateSystem": "metres; +x front, +y left, +z up"]]
    let source = try JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys])
    var data = Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0, 8, 16, 24] { data.append(UInt8((n >> shift) & 255)) } }
    put16(1); put16(0); put32(UInt32(model.triangleCount)); put32(UInt32(source.count)); data.append(source)
    data.append(contentsOf: [UInt8](repeating: 0, count: (4 - source.count % 4) % 4))
    for start in stride(from: 0, to: model.vertices.count, by: 3) {
        let triangle = model.vertices[start..<(start + 3)]
        put32(triangle.contains { $0.glows } ? 1 : 0)
        for vertex in triangle { put32(vertex.x.bitPattern); put32(vertex.y.bitPattern); put32(vertex.z.bitPattern); put32(vertex.color) }
    }
    if part != nil {
        let decoded = try Map3DModelFile(decoding: data, named: model.name)
        precondition(decoded.model.vertices == model.vertices)
    }
    try data.write(to: directory.appendingPathComponent(model.name + ".m3dmodel"), options: .atomic)
    let connectors = part?.connectors.map { ["name": $0.name, "position": [$0.position.x, $0.position.y, $0.position.z], "normal": [$0.normal.x, $0.normal.y, $0.normal.z]] as [String: Any] } ?? []
    records.append(["id": model.name, "native": "models/\(model.name).m3dmodel", "vertices": model.vertices.count, "triangles": model.triangleCount, "far": far, "system": part?.system.rawValue ?? "scene", "kind": part?.kind.rawValue ?? "scene", "tracks": part?.tracks ?? 0, "connectors": connectors])
}
for system in Map3DDepotYardKit.System.allCases {
    for kind in Map3DDepotYardKit.Kind.allCases {
        let trackCounts: [Int] = switch kind {
        case .shedHead, .shedMiddle, .shedTail: [2, 4]
        case .parkingCanopy: Array(2...6)
        default: [2]
        }
        for tracks in trackCounts {
            let part = Map3DDepotYardKit.part(kind, system: system, tracks: tracks)
            try export(Map3DDepotYardKit.model(for: part), part: part, far: false)
            try export(Map3DDepotYardKit.model(for: part, far: true), part: part, far: true)
        }
    }
}
for system in Map3DDepotYardKit.System.allCases {
    try export(Map3DDepotYardKit.reviewScene(system: system), part: nil, far: false)
}
let manifest: [String: Any] = ["schema_version": 1, "generator": "Map3DDepotYardKit", "directions": ["top", "bottom", "left", "right", "front", "back", "isometric"], "models": records]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("manifest.json"))
print("Exported \(records.count) models")
