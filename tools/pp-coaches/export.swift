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
 let metadata=try JSONSerialization.data(withJSONObject:["generator":"native-pp-coaches","producer_commit":sourceProducer ?? producer,"coordinates":"metres +X front +Y left +Z up","recipe_version":1],options:[.sortedKeys])
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
 if sourceProducer==acceptedE500,let accepted=ProcessInfo.processInfo.environment["PP_ACCEPTED_E500"] {
  let exact=try Data(contentsOf:URL(fileURLWithPath:accepted).appendingPathComponent(file))
  let decoded=try Map3DModelFile(decoding:exact,named:m.name).model
  guard words(decoded.vertices)==words(m.vertices) else {fatalError("accepted E500 geometry differs")}
  d=exact
 }
 try d.write(to:output.appendingPathComponent(file));nativeUnits[m.name]=d.base64EncodedString();actualModels[m.name]=m
 var r=record(m,file,category,family);if let sourceProducer {r["source_producer_commit"]=sourceProducer};records.append(r)
}
for far in [false,true] {
 for role in Map3DPPPassenger.Role.allCases {try unit(Map3DPPPassenger.model(role,far:far),category:"section",family:far ? "far":"pp")}
 try unit(Map3DE500.model(far:far),category:"comparison",family:"accepted-e500",sourceProducer:acceptedE500)
}
try unit(Map3DEMU3000.model(.ed),category:"comparison",family:"accepted-style")
// A static, explicitly illustrative hauled formation. No operational or push-pull claim.
let sequence:[Map3DPPPassenger.Role]=[.ppm2500,.pph1300]+Array(repeating:.ppt1000,count:9)+[.ppc1400]
var assemblyRows:[[String:Any]]=[]
for far in [false,true] {
 let suffix=far ? "-far":"",id="pp-e500-formation"+suffix
 var placements:[[String:Any]]=[["unit":"e500"+suffix,"translation":[Float(0),Float(0),Float(0)],"rotation_degrees":0]]
 var x:Float = -10.385-Map3DPPPassenger.couplingHalfLength
 for role in sequence {
  placements.append(["unit":"pp-"+role.rawValue+suffix,"translation":[x,Float(0),Float(0)],"rotation_degrees":0]);x-=Map3DPPPassenger.couplingHalfLength*2
 }
 placements.append(["unit":"e500"+suffix,"translation":[x+Map3DPPPassenger.couplingHalfLength-10.385,Float(0),Float(0)],"rotation_degrees":180])
 let used=Set(placements.map {$0["unit"] as! String}),units=nativeUnits.filter {used.contains($0.key)}
 let scene:[String:Any]=["format":"M3DAssembly","version":1,"producer_commit":producer,"units":units,"placements":placements,"purpose":"static illustrative double-ended E500 PP display; not certified operation or push-pull control"]
 let file="models/\(id).m3dscene.json";try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys]).write(to:output.appendingPathComponent(file))
 var payload=Data(),lo=[Float.infinity,Float.infinity,Float.infinity],hi=[-Float.infinity,-Float.infinity,-Float.infinity],count=0
 for p in placements {
  let m=actualModels[p["unit"] as! String]!,translation=(p["translation"] as! [Float])[0]
  let reversed=(p["rotation_degrees"] as! Int)==180
  payload.append(words(m.vertices,translation:translation,reversed:reversed));count+=m.triangleCount
  for v in m.vertices {for (axis,n) in [(reversed ? -v.x:v.x)+translation,reversed ? -v.y:v.y,v.z].enumerated(){lo[axis]=min(lo[axis],n);hi[axis]=max(hi[axis],n)}}
 }
 try payload.write(to:output.appendingPathComponent(id+"-expected.bin"))
 records.append(["id":id,"name":id,"native":file,"native_kind":"assembly","category":"formation","family":far ? "far":"pp","triangles":count,"minimum":lo,"maximum":hi])
 assemblyRows.append(["id":id,"placements":placements,"shared_origin":"E500 centre; +X forward; rail Z=0","coach_coupler_half_length_m":Map3DPPPassenger.couplingHalfLength,"coach_body_half_length_m":Map3DPPPassenger.bodyHalfLength,"coach_gangway_half_length_m":Map3DPPPassenger.gangwayHalfLength,"rotation":"front locomotive 0 degrees; rear locomotive 180 degrees; coaches 0 degrees","note":"E500 at both ends; rear instance rotated 180 degrees, original accepted unit unmodified. Coupler tips touch. E500 has no passenger gangway; both outer coach gangways end at their own ends. Four independent roles: PPM2500 multi-function car, PPH1300 accessible car, nine PPT1000 standard coaches, PPC1400 conductor-room coach. Illustrative ordering; not a certified E500 operating consist."])
}
if let previous=ProcessInfo.processInfo.environment["PP_PREVIOUS"] {
 let base=URL(fileURLWithPath:previous),old=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("manifest.json"))) as! [String:Any]
 for var r in old["models"] as! [[String:Any]] where (r["category"] as? String)=="section" {
  let original=r["id"] as! String,id="previous-"+original,file="models/\(id).m3dmodel",d=try Data(contentsOf:base.appendingPathComponent(r["native"] as! String))
  try d.write(to:output.appendingPathComponent(file));r["id"]=id;r["name"]=id;r["native"]=file;r["category"]="comparison";r["family"]="genuine-first-pass";records.append(r)
 }
}
if let baseline=ProcessInfo.processInfo.environment["PP_BASELINE"] {
 let d=try Data(contentsOf:URL(fileURLWithPath:baseline)),file="models/before-pp-ppt1000.m3dmodel",m=try Map3DModelFile(decoding:d,named:"before-pp-ppt1000").model
 try d.write(to:output.appendingPathComponent(file));var r=record(m,file,"comparison","genuine-operating-baseline");r["source_producer_commit"]="c005788c778d0743291f0c724d1336c668078385";r["description"]="True existing set-pushPull-car generic operating coach; not the new PP-specific recipe";records.append(r)
}
let manifest:[String:Any]=["schema_version":1,"recipe_version":1,"generator":"native-pp-coaches","producer_commit":producer,"models":records,"model_count":records.count,"directions":["top","bottom","left","right","front","back","isometric"],"native_coordinates":"metres +X front +Y left +Z up; tread Z=0","gltf_coordinates":"metres +X front +Y up -Z left","assembly":assemblyRows,"palette":["body":Map3DPPPassenger.bodyColor,"base":Map3DColor.rgb(0xF2F0EA),"accent":Map3DE500.bodyColor,"mask":Map3DE500.maskColor,"glass":Map3DE500.glassColor,"tire":Map3DColor.rgb(0x2B2E34)],"runtime":"Dedicated pushPull display uses PPT1000 near/far. E500 hauled full display is an independent static assembly, not assigned to an operating set. E500CK/MINGRI/STAR retain their distinct existing coaches.","static_geometry":true]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"))
print("Exported \(records.count) native models and exact composition payloads; all units read back.")
