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
 let metadata=try JSONSerialization.data(withJSONObject:["generator":"native-pp-coaches","producer_commit":sourceProducer ?? producer,"coordinates":"metres +X front +Y left +Z up","recipe_version":2],options:[.sortedKeys])
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
for far in [false,true] {try unit(Map3DE1000.model(far:far),category:"section",family:far ? "far":"e1000")}
let protectedRoot=URL(fileURLWithPath:ProcessInfo.processInfo.environment["PP_ACCEPTED_ROOT"] ?? "/workspace/scratch/pp-final")
let protectedManifest=try JSONSerialization.jsonObject(with:Data(contentsOf:protectedRoot.appendingPathComponent("manifest.json"))) as! [String:Any]
for var row in protectedManifest["models"] as! [[String:Any]] where (row["native_kind"] as? String) != "assembly" && !(row["id"] as! String).hasPrefix("before-") {
 let id=row["id"] as! String,file=row["native"] as! String,d=try Data(contentsOf:protectedRoot.appendingPathComponent(file))
 let model=try Map3DModelFile(decoding:d,named:id).model
 if id.hasPrefix("pp-") {guard words(model.vertices)==words(Map3DPPPassenger.model(Map3DPPPassenger.Role(rawValue:id.replacingOccurrences(of:"pp-",with:"").replacingOccurrences(of:"-far",with:""))!,far:id.hasSuffix("-far")).vertices) else {fatalError("PP changed")}}
 try d.write(to:output.appendingPathComponent(file));nativeUnits[id]=d.base64EncodedString();actualModels[id]=model
 row["category"]="comparison";row["family"]="protected-accepted";records.append(row)
}
// Illustrative broad roles from table1.5-1; PPT2000 is not modeled. No identities.
let sequence:[Map3DPPPassenger.Role]=[.ppc1400,.ppt1000,.pph1300,.ppt1000,.ppt1000,.ppt1000,.ppc1400,.pph1300,.ppt1000,.ppt1000,.ppt1000,.ppm2500]
var assemblyRows:[[String:Any]]=[]
for far in [false,true] {
 let suffix=far ? "-far":"",id="e1000-pp-formation"+suffix
 var placements:[[String:Any]]=[["unit":"e1000"+suffix,"translation":[Float(0),Float(0),Float(0)],"rotation_degrees":0]]
 var x:Float = -Map3DE1000.couplingHalfLength-Map3DPPPassenger.couplingHalfLength
 for role in sequence {placements.append(["unit":"pp-"+role.rawValue+suffix,"translation":[x,Float(0),Float(0)],"rotation_degrees":0]);x-=Map3DPPPassenger.couplingHalfLength*2}
 placements.append(["unit":"e1000"+suffix,"translation":[x+Map3DPPPassenger.couplingHalfLength-Map3DE1000.couplingHalfLength,Float(0),Float(0)],"rotation_degrees":180])
 let used=Set(placements.map{$0["unit"] as! String}),units=nativeUnits.filter{used.contains($0.key)}
 let scene:[String:Any]=["format":"M3DAssembly","version":1,"producer_commit":producer,"units":units,"placements":placements,"purpose":"static E1000 PP assembly, not control/animation verification"]
 let file="models/\(id).m3dscene.json";try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys]).write(to:output.appendingPathComponent(file))
 var payload=Data(),lo=[Float.infinity,Float.infinity,Float.infinity],hi=[-Float.infinity,-Float.infinity,-Float.infinity],count=0
 for p in placements {let m=actualModels[p["unit"] as! String]!,translation=(p["translation"] as! [Float])[0],reversed=(p["rotation_degrees"] as! Int)==180
  payload.append(words(m.vertices,translation:translation,reversed:reversed));count+=m.triangleCount
  for v in m.vertices {for (a,n) in [(reversed ? -v.x:v.x)+translation,reversed ? -v.y:v.y,v.z].enumerated(){lo[a]=min(lo[a],n);hi[a]=max(hi[a],n)}}
 }
 try payload.write(to:output.appendingPathComponent(id+"-expected.bin"))
 records.append(["id":id,"name":id,"native":file,"native_kind":"assembly","category":"formation","family":far ? "far":"e1000","triangles":count,"minimum":lo,"maximum":hi])
 assemblyRows.append(["id":id,"placements":placements,"shared_origin":"front E1000 centre, metres X forward Y left Z up rail=0","source":"TTSB177 report table1.5-1; 12 coach roles, broad roles only; PPT2000 subtype not modeled, all displayed PPT units are explicitly PPT1000","locomotive_body_length_m":Float(16.5),"locomotive_coupler_half_length_m":Map3DE1000.couplingHalfLength,"coach_coupler_half_length_m":Map3DPPPassenger.couplingHalfLength,"rotation":"front0, rear180 degrees"])
}
for (variable,suffix) in [("E1000_BASELINE",""),("E1000_BASELINE_FAR","-far")] {
 if let before=ProcessInfo.processInfo.environment[variable] {
 let d=try Data(contentsOf:URL(fileURLWithPath:before)),id="before-e1000"+suffix,file="models/before-e1000"+suffix+".m3dmodel",m=try Map3DModelFile(decoding:d,named:id).model
 try d.write(to:output.appendingPathComponent(file));records.append(record(m,file,"comparison","true-parent-baseline"))
}
}
let manifest:[String:Any]=["schema_version":1,"recipe_version":2,"generator":"native-e1000-pp","producer_commit":producer,"models":records,"model_count":records.count,"directions":["top","bottom","left","right","front","back","isometric"],"native_coordinates":"metres +X front +Y left +Z up, rail Z=0","gltf_coordinates":"metres +X front +Y up -Z left","assembly":assemblyRows,"palette":["body":Map3DColor.rgb(0xF2F0EA),"accent":Map3DE500.bodyColor,"mask":Map3DE500.maskColor,"glass":Map3DE1000.glassColor,"tire":Map3DColor.rgb(0x2B2E34)],"runtime":"pushPull power cars only, existing coaches/other services unchanged; static geometry not push-pull-control validation","static_geometry":true]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"))
print("Exported \(records.count) native units/assemblies with exact readback")
