import Foundation
import GamePresentation

guard CommandLine.arguments.count == 2 else { fatalError("usage: export OUTPUT") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output.appendingPathComponent("models"),withIntermediateDirectories:true)
let producer=ProcessInfo.processInfo.environment["PRODUCER_COMMIT"] ?? "WORKING-TREE-NOT-FINAL"
let acceptedE500="85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a"
var records:[[String:Any]]=[]
var nativeUnits:[String:String]=[:]
var actualModels:[String:Map3DModelPack.Model]=[:]
func words(_ vertices:[Map3DVertex],translation:Float=0,reversed:Bool=false)->Data {
 var raw=Data()
 func word(_ bits:UInt32){let n:UInt32=bits==0x80000000 ? 0:bits;for s:UInt32 in [0,8,16,24]{raw.append(UInt8((n>>s)&255))}}
 for i in stride(from:0,to:vertices.count,by:3){word(vertices[i..<i+3].contains(where:{$0.glows}) ? 1:0);for v in vertices[i..<i+3]{word(((reversed ? -v.x:v.x)+translation).bitPattern);word((reversed ? -v.y:v.y).bitPattern);word(v.z.bitPattern);word(v.color)}}
 return raw
}
func encoded(_ model:Map3DModelPack.Model,sourceProducer:String?=nil)throws->Data {
 guard model.triangleCount<=Map3DModelFile.maximumTriangles else {fatalError("unit budget: \(model.name)")}
 let metadata=try JSONSerialization.data(withJSONObject:["generator":"native-emu800","producer_commit":sourceProducer ?? producer,"coordinates":"metres +X front +Y left +Z up","recipe_version":1],options:[.sortedKeys])
 var data=Data("M3DM".utf8)
 func word(_ n:UInt32){for s:UInt32 in [0,8,16,24]{data.append(UInt8((n>>s)&255))}}
 data.append(contentsOf:[1,0,0,0]);word(UInt32(model.triangleCount));word(UInt32(metadata.count));data.append(metadata)
 data.append(contentsOf:repeatElement(UInt8(0),count:(4-metadata.count%4)%4));data.append(words(model.vertices))
 let decoded=try Map3DModelFile(decoding:data,named:model.name).model
 guard decoded.vertices.count==model.vertices.count else {fatalError("readback count")}
 for (a,b) in zip(decoded.vertices,model.vertices){guard a.position==b.position,a.color==b.color,a.layer==b.layer,abs(a.nx-b.nx)<0.00001,abs(a.ny-b.ny)<0.00001,abs(a.nz-b.nz)<0.00001 else {fatalError("readback geometry/normal/color")}}
 return data
}
func record(_ model:Map3DModelPack.Model,_ file:String,_ category:String,_ family:String)->[String:Any]{
 ["id":model.name,"name":model.name,"native":file,"category":category,"family":family,"triangles":model.triangleCount,"minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]]
}
@MainActor func unit(_ m:Map3DModelPack.Model,category:String,family:String,sourceProducer:String?=nil)throws {
 let file="models/\(m.name).m3dmodel"
 var d=try encoded(m,sourceProducer:sourceProducer)
 if sourceProducer==acceptedE500,let accepted=ProcessInfo.processInfo.environment["E8_ACCEPTED_E500"] {
  let exact=try Data(contentsOf:URL(fileURLWithPath:accepted).appendingPathComponent(file))
  let decoded=try Map3DModelFile(decoding:exact,named:m.name).model
  guard words(decoded.vertices)==words(m.vertices) else {fatalError("accepted E500 geometry differs")}
  d=exact
 }
 try d.write(to:output.appendingPathComponent(file));nativeUnits[m.name]=d.base64EncodedString();actualModels[m.name]=m
 var r=record(m,file,category,family);if let sourceProducer {r["source_producer_commit"]=sourceProducer};records.append(r)
}

for far in [false,true] {
 for role in Map3DEMU800.Role.allCases {for reversed in [false,true] {
  try unit(Map3DEMU800.model(role,reversed:reversed,far:far),category:"section",family:far ? "far":"emu800")
 }}
}
for (file,source) in [("e500.m3dmodel",acceptedE500),("emu3000-ed.m3dmodel","66a515e8f84ddb5001bae2dd0ce5d79f49063113")] {
 let dir=ProcessInfo.processInfo.environment["E8_ACCEPTED"]!
 let d=try Data(contentsOf:URL(fileURLWithPath:dir).appendingPathComponent(file))
 let id=String(file.dropLast(9)),m=try Map3DModelFile(decoding:d,named:id).model
 try unit(m,category:"comparison",family:"accepted-style",sourceProducer:source)
 try d.write(to:output.appendingPathComponent("models/"+file))
}
let base=ProcessInfo.processInfo.environment["E8_BASELINE"]!
let baseline=try Data(contentsOf:URL(fileURLWithPath:base).appendingPathComponent("before-emu800.m3dmodel"))
let bm=try Map3DModelFile(decoding:baseline,named:"before-emu800").model
try unit(bm,category:"comparison",family:"true-existing-generic-display")
try baseline.write(to:output.appendingPathComponent("models/before-emu800.m3dmodel"))
var assemblies:[[String:Any]]=[]
for far in [false,true] {
 let suffix=far ? "-far":"",id="emu800-formation"+suffix
 let placements:[[String:Any]]=Map3DEMU800.placements.map {
  ["unit":Map3DEMU800.id($0.role,reversed:$0.reversed,far:far),"translation":[$0.x,Float(0),Float(0)],"rotation_degrees":0]
 }
 let used=Set(placements.map {$0["unit"] as! String})
 let scene:[String:Any]=["format":"M3DAssembly","version":1,"producer_commit":producer,"units":nativeUnits.filter {used.contains($0.key)},"placements":placements]
 let file="models/"+id+".m3dscene.json"
 try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys]).write(to:output.appendingPathComponent(file))
 let m=Map3DEMU800.formation(far:far)
 try words(m.vertices).write(to:output.appendingPathComponent(id+"-expected.bin"))
 var r=record(m,file,"formation",far ? "far":"emu800");r["native_kind"]="assembly";records.append(r)
 assemblies.append(["id":id,"placements":placements,"sequence":Map3DEMU800.sequence.map(\.rawValue),"rotation":"reverse models already rotated; no double rotation","pitch_m":Map3DEMU800.sequence.map {$0 == .ed ? 21.6:20.3}])
}
let manifest:[String:Any]=["schema_version":1,"recipe_version":1,"generator":"native-emu800","producer_commit":producer,"models":records,"model_count":records.count,"directions":["top","bottom","left","right","front","back","isometric"],"native_coordinates":"metres +X front +Y left +Z up; tread Z=0","gltf_coordinates":"metres +X front +Y up -Z left","assembly":assemblies,"palette":["body":Map3DEMU800.bodyColor,"navy":Map3DEMU800.navy,"yellow":Map3DEMU800.yellow,"glass":Map3DEMU800.glass],"runtime":"Static registration only. Existing emu800 key includes general TRA commuters and EMU900 performance; unchanged.","static_geometry":true]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"))
print("Exported",records.count,"models, exact readback and composition payloads")
