import Foundation
import GamePresentation

// tools/model-look: writes station-kit models as native .m3dmodel files for
// shoot.mjs. Usage: export-station OUTPUT_DIRECTORY STATION_ID...
// (ids as in Map3DStationKitCatalog.swift, e.g. station-tra_sched-3acfda8b).
guard CommandLine.arguments.count>2 else { fatalError("usage: export-station OUTPUT_DIRECTORY STATION_ID...") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for id in CommandLine.arguments.dropFirst(2) {
    guard let model=Map3DStationKit.model(id:id) else { fatalError("No station-kit model named "+id) }
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+id) }
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
    guard try Map3DModelFile(decoding:data,named:id).model.vertices==model.vertices else { fatalError("Native readback differs: "+id) }
    try data.write(to:directory.appendingPathComponent(id+".m3dmodel"),options:.atomic)
    print(id,model.triangleCount,"triangles",model.minimum,model.maximum)
}
