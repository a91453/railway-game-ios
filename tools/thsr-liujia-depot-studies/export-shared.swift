import Foundation
import GamePresentation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for kind in [Map3DDepotYardKit.Kind.office, .fence, .gate, .guardHouse] {
    for far in [false, true] {
        let part = Map3DDepotYardKit.part(kind, system: .taiwanRail)
        let model = Map3DDepotYardKit.model(for: part, far: far)
        let provenance: [String: Any] = ["asset": ["generator": "Map3DDepotYardKit", "version": "2.0"], "extras": ["kind": kind.rawValue, "source": "shared-unmodified-game-recipe"]]
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
        let name = "\(kind.rawValue)\(far ? "-far" : "")"
        try data.write(to: root.appendingPathComponent(name + ".m3dmodel"), options: .atomic)
    }
}
