import Foundation
import GamePresentation

guard CommandLine.arguments.count==2 else { fatalError("usage: shuttle-bus-export OUTPUT_DIRECTORY") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
@MainActor func export(_ model: Map3DModelPack.Model,info: [String:Any]) throws {
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+model.name) }
    let provenance: [String:Any]=["asset":["generator":"Map3DShuttleBus","version":"2.0"],"extras":["assetId":model.name,"recipeVersion":1,"source":"native-procedural","fidelity":info["fidelity"] ?? "illustrative","coordinateSystem":"metres; +x front, +y left, +z up"]]
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
    guard decoded.model.vertices.count==model.vertices.count else { fatalError("Vertex count differs") }
    for (a,b) in zip(decoded.model.vertices,model.vertices) {
        guard a.position==b.position,a.color==b.color,a.layer==b.layer,abs(a.nx-b.nx)<0.00001,abs(a.ny-b.ny)<0.00001,abs(a.nz-b.nz)<0.00001 else { fatalError("Native readback differs: "+model.name) }
    }
    try data.write(to:directory.appendingPathComponent(model.name+".m3dmodel"),options:.atomic)
    var record=info
    record.merge(["id":model.name,"native":"models/"+model.name+".m3dmodel","triangles":model.triangleCount,
                  "minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]]) { _,v in v }
    records.append(record)
}
try export(Map3DShuttleBus.model(),info:["name":"高頂接駁小巴","category":"vehicle","fidelity":"owner-reference-recomposed","mount":"ground"])
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let original=try Map3DModelFile(decoding:Data(contentsOf:root.appendingPathComponent("RailwayGameApp/Resources/Models/city-bus.m3dmodel")),named:"city-bus")
try export(Map3DCityBus.model(from:original),info:["name":"既有大型市區公車（對照）","category":"reference","fidelity":"existing-game-model"])
let manifest: [String:Any]=["schema_version":1,"generator":"Map3DShuttleBus","recipe_version":1,"model_count":records.count,"part_count":1,"comparison_count":1,"example_count":0,
    "native_coordinates":"metres; +x front, +y left, +z up","gltf_coordinates":"metres; +x front, +y up, -z left",
    "directions":["top","bottom","left","right","front","back","isometric"],"models":records,
    "notes":"One new high-roof shuttle bus type, plus existing city bus for comparison; fixed teal/off-white livery, static native geometry. Street motion uses the existing traffic system."]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported one new shuttle bus and one existing bus comparison; all positions, colours, glow and normals verified through native loader.")
