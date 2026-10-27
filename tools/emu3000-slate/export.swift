import Foundation
import GamePresentation

guard CommandLine.arguments.count == 2 else { fatalError("usage: export OUTPUT") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output.appendingPathComponent("models"),withIntermediateDirectories:true)
let producer=ProcessInfo.processInfo.environment["PRODUCER_COMMIT"] ?? "WORKING-TREE-NOT-FINAL"
var records:[[String:Any]]=[]
var nativeUnits:[String:String]=[:]
func encoded(_ model:Map3DModelPack.Model) throws -> Data {
    guard model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("unit budget: \(model.name)") }
    let metadata=try JSONSerialization.data(withJSONObject:["generator":"native-emu3000-slate","producer_commit":producer,"coordinates":"metres +X front +Y left +Z up","recipe_version":6],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func word(_ bits:UInt32) { let n:UInt32=bits==0x80000000 ? 0:bits; for s:UInt32 in [0,8,16,24] { data.append(UInt8((n>>s)&255)) } }
    data.append(contentsOf:[1,0,0,0]);word(UInt32(model.triangleCount));word(UInt32(metadata.count));data.append(metadata)
    data.append(contentsOf:repeatElement(UInt8(0),count:(4-metadata.count%4)%4))
    for i in stride(from:0,to:model.vertices.count,by:3) {
        word(model.vertices[i..<i+3].contains(where:{$0.glows}) ? 1:0)
        for v in model.vertices[i..<i+3] { word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color) }
    }
    let decoded=try Map3DModelFile(decoding:data,named:model.name).model
    guard decoded.vertices.count==model.vertices.count else {fatalError("readback count")}
    for (a,b) in zip(decoded.vertices,model.vertices) {
        guard a.position==b.position,a.color==b.color,a.layer==b.layer,
            abs(a.nx-b.nx)<0.00001,abs(a.ny-b.ny)<0.00001,abs(a.nz-b.nz)<0.00001 else {fatalError("readback geometry/normal/color")}
    }
    return data
}
func record(_ model:Map3DModelPack.Model,_ file:String,_ category:String,_ family:String) -> [String:Any] {
    ["id":model.name,"name":model.name,"native":file,"category":category,"family":family,"triangles":model.triangleCount,
     "minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]]
}
for far in [false,true] {
    for unit in Map3DEMU3000.Unit.allCases {
        let m=Map3DEMU3000.model(unit,far:far),data=try encoded(m),file="models/\(m.name).m3dmodel"
        try data.write(to:output.appendingPathComponent(file));nativeUnits[m.name]=data.base64EncodedString()
        records.append(record(m,file,"section",far ? "far":"emu3000"))
    }
    let m=Map3DEMU3000.formation(far:far)
    let placements:[[String:Any]]=Map3DEMU3000.placements.map {
        ["unit":$0.unit.id+(far ? "-far":""),"translation":[$0.x,Float(0),Float(0)],"rotation_degrees":0]
    }
    let units=nativeUnits.filter {far ? $0.key.hasSuffix("-far"): !$0.key.hasSuffix("-far")}
    let scene:[String:Any]=["format":"M3DAssembly","version":1,"producer_commit":producer,"units":units,"placements":placements]
    let file="models/\(m.name).m3dscene.json"
    try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys]).write(to:output.appendingPathComponent(file))
    var r=record(m,file,"formation",far ? "far":"emu3000");r["native_kind"]="assembly";records.append(r)
    // Exact Swift assembly payload, compared independently against JS assembly.
    var raw=Data()
    func word(_ bits:UInt32){let n:UInt32=bits==0x80000000 ? 0:bits;for s:UInt32 in [0,8,16,24]{raw.append(UInt8((n>>s)&255))}}
    for i in stride(from:0,to:m.vertices.count,by:3){word(m.vertices[i..<i+3].contains(where:{$0.glows}) ? 1:0);for v in m.vertices[i..<i+3]{word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color)}}
    try raw.write(to:output.appendingPathComponent(m.name+"-expected.bin"))
}
let previous=URL(fileURLWithPath:ProcessInfo.processInfo.environment["EMU_PREVIOUS"]!)
let old=try JSONSerialization.jsonObject(with:Data(contentsOf:previous.appendingPathComponent("manifest.json"))) as! [String:Any]
for var r in old["models"] as! [[String:Any]] where ["emu3000-ed","emu3000-tail","emu3000-em","emu3000-ed-far","emu3000-tail-far","emu3000-em-far"].contains(r["id"] as! String) {
 let id="previous-"+(r["id"] as! String),file="models/\(id).m3dmodel",d=try Data(contentsOf:previous.appendingPathComponent(r["native"] as! String))
 try d.write(to:output.appendingPathComponent(file));r["id"]=id;r["name"]=id;r["native"]=file;r["category"]="comparison";r["family"]="before";r["source_producer_commit"]=old["producer_commit"];records.append(r)
}
for (id,key,sourceCommit) in [("e500","SLATE_E500","85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a"),("chukuang-standard","SLATE_CHUKUANG","ac4c1e1e2b33c09f6c866424828e9ed17a6534f8")] {
 let d=try Data(contentsOf:URL(fileURLWithPath:ProcessInfo.processInfo.environment[key]!))
 let file="models/\(id).m3dmodel",m=try Map3DModelFile(decoding:d,named:id).model
 try d.write(to:output.appendingPathComponent(file));var r=record(m,file,"comparison","game-style");r["source_producer_commit"]=sourceCommit;r["accepted_by_user"]=(id=="e500");records.append(r)
}
let manifest:[String:Any]=["schema_version":1,"recipe_version":6,"generator":"native-emu3000-slate","producer_commit":producer,
    "model_count":records.count,"models":records,"directions":["top","bottom","left","right","front","back","isometric"],
    "native_coordinates":"metres +X front +Y left +Z up; tread z=0","gltf_coordinates":"metres +X front +Y up -Z left",
    "assembly":["sequence":Map3DEMU3000.sequence.map(\.rawValue),"positions_x_m":Map3DEMU3000.placements.map(\.x),"rotation":"tail baked 180 degrees; placements no rotation","unit_pitch_m":Map3DEMU3000.sequence.map(\.pitch),"length_m":245.7,"body_gap_m":0.7,"note":"Middle body 19.6m, pitch20.3m. ED body21m pitch21.35m. Coupler ends touch; roof equipment is proportion-estimated."],
    "palette":["body":Map3DEMU3000.bodyColor,"glass":Map3DEMU3000.glassColor,"mask":Map3DEMU3000.maskColor,"hardware":Map3DEMU3000.hardwareColor,"accent":Map3DEMU3000.accentColor],
    "runtime":"Dedicated EMU3000 near/far; presentation-only own-length layout. No GameCore change.","static_geometry":true]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"))
print("Exported \(records.count) models; all native units read back exactly.")

if let scratch=ProcessInfo.processInfo.environment["EMU_FINGERPRINTS"] {
 let dir=URL(fileURLWithPath:scratch,isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
 var rows:[[String:Any]]=[]
 for m in Map3DModelPack.standard.models {
  var payload=Data()
  func w(_ n:UInt32){for s:UInt32 in [0,8,16,24]{payload.append(UInt8((n>>s)&255))}}
  for v in m.vertices {w(v.x.bitPattern);w(v.y.bitPattern);w(v.z.bitPattern);w(v.color);w(v.layer.bitPattern)}
  let file=m.name.replacingOccurrences(of:"/",with:"-")+".payload";try payload.write(to:dir.appendingPathComponent(file));rows.append(["id":m.name,"payload":file,"triangles":m.triangleCount])
 }
 try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:dir.appendingPathComponent("fingerprints.json"))
}
