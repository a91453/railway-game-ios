import Foundation
import GameCore
import GamePresentation

// tools/model-look: writes each way the company's house is drawn (decision
// 896, ``Map3DPlacedHouses``) as a native .m3dmodel file for shoot.mjs.
// Usage: export-houses OUTPUT_DIRECTORY
guard CommandLine.arguments.count==2 else { fatalError("usage: export-houses OUTPUT_DIRECTORY") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for index in 0..<Map3DPlacedHouses.count {
    let model=Map3DPlacedHouses.model(index,tin:index%4),id=model.name
    let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":id,"coordinateSystem":"metres; x front, y left, z up"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let t=model.vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
    }
    try data.write(to:directory.appendingPathComponent(id+".m3dmodel"),options:.atomic)
    print(id,model.triangleCount,"triangles",model.minimum,model.maximum)
}
