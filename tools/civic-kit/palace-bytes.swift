import Foundation
@testable import GamePresentation
var data=Data()
@MainActor func put(_ n: UInt32) { for s: UInt32 in [0,8,16,24] { data.append(UInt8((n>>s)&255)) } }
for kind in Map3DTaipeiLandmark.allCases {
    for full in [false,true] {
        let mesh=kind.model(full:full)
        data.append(contentsOf:(String(describing:kind)+(full ? "-near" : "-far")).utf8);data.append(0)
        put(UInt32(mesh.vertices.count));put(UInt32(mesh.indices.count))
        for v in mesh.vertices {
            for f in [v.x,v.y,v.z,v.nx,v.ny,v.nz,v.u,v.v,v.layer] { put(f.bitPattern) }
            put(v.color)
        }
        for i in mesh.indices { put(i) }
    }
}
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("Exported every field of all Taipei landmark near/far vertices and indices: \(data.count) bytes")
