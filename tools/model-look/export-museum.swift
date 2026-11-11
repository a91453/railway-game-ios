import Foundation
import GameCore
import GamePresentation

// tools/model-look: writes the railway museum (decision 696) as native
// .m3dmodel files for shoot.mjs, one for each count of exhibits given, its
// exhibits a likely collection's first types, as their far models where they
// have them. With its exhibits it is a scene of several models: shoot it
// with --max-triangles 200000.
// Usage: export-museum OUTPUT_DIRECTORY EXHIBITS|hall...  (hall: the hall alone)
guard CommandLine.arguments.count>2 else { fatalError("usage: export-museum OUTPUT_DIRECTORY EXHIBITS...") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
// The types a company comes to own, the ones with a model of their own first.
let order=["EMU3000","HSR","STEAM","C","R200CK","A","BLUE","EMU100","E200CK","L","MINGRI","ALISHAN"]
let types=order.compactMap { code in TrainType.allCases.first { $0.spec.code==code } }+TrainType.allCases.filter { !order.contains($0.spec.code) }
for argument in CommandLine.arguments.dropFirst(2) {
    let model: Map3DModelPack.Model,id: String
    if argument=="hall" { model=Map3DRailwayMuseum.hallModel();id="railway-museum-hall" }
    else {
        guard let count=Int(argument),count>=0 else { fatalError("Not a count or hall: "+argument) }
        model=Map3DRailwayMuseum.lookModel(exhibits:Array(types.prefix(count)),far:true);id="railway-museum-\(count)"
    }
    guard model.triangleCount>0 else { fatalError("Empty: "+id) }
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
