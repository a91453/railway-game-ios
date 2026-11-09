import Foundation
import GamePresentation

guard CommandLine.arguments.count==2 else { fatalError("usage: civic-kit-export OUTPUT_DIRECTORY") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
@MainActor func export(_ model: Map3DModelPack.Model,info: [String:Any]) throws {
    let id=info["id"] as? String ?? model.name
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+model.name) }
    let provenance: [String:Any]=["asset":["generator":"ChineseRoofKits669","version":"1.0"],"extras":["assetId":id,"recipeVersion":1,"source":"native-procedural","fidelity":info["fidelity"] ?? "illustrative","coordinateSystem":"metres; +x front, +y left, +z up"]]
    let text=try JSONSerialization.data(withJSONObject:provenance,options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let t=model.vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
    }
    let decoded=try Map3DModelFile(decoding:data,named:model.name)
    guard decoded.model.vertices==model.vertices else { fatalError("Native readback differs: "+model.name) }
    try data.write(to:directory.appendingPathComponent(id+".m3dmodel"),options:.atomic)
    var record=info
    record.merge(["id":id,"native":"models/"+id+".m3dmodel","triangles":model.triangleCount,
                  "minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]]) { _,v in v }
    records.append(record)
}
for state in ["near","far","fallback"] {
    let far=state == "far",traditional=state != "fallback"
    for part: Map3DCivicKit.Part in [.templeGate,.templeHall,.templeSideHall,.templeWall] {
        let model=Map3DCivicKit.model(for:part,far:far,traditional:traditional)
        try export(model,info:["id":part.id+"-"+state,"name":part.name,"category":"culture","state":state,"base_id":part.id])
    }
    for part: Map3DResidentialKit.Part in [.courtyardHouse,.narrowTownhouse] {
        let model=Map3DResidentialKit.model(for:part,far:far,traditional:traditional)
        try export(model,info:["id":part.id+"-"+state,"name":part.name,"category":"home","state":state,"base_id":part.id])
    }
}
let manifest: [String:Any] = ["schema_version":1,"generator":"ChineseRoofKits669","models":records,
    "directions":["top","bottom","left","right","front","back","isometric"]]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported \(records.count) variants with native vertex readback.")
