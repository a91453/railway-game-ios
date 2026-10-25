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
    let metadata=try JSONSerialization.data(withJSONObject:["generator":"native-e500-refresh","producer_commit":producer,"coordinates":"metres +X front +Y left +Z up","recipe_version":3],options:[.sortedKeys])
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

var models=[Map3DE500.model(),Map3DE500.model(far:true),Map3DTrainShapeRefresh.model("refresh-e200"),Map3DEMU3000.model(.ed)]
for m in models {
 let id=m.name=="set-E500CK-head" ? "before-e500":m.name
 let file="models/\(id).m3dmodel"
 try encoded(m).write(to:output.appendingPathComponent(file))
 var r=record(m,file,id.hasPrefix("e500") ? "section":"comparison",id=="e500" ? "e500":id=="e500-far" ? "far":id=="before-e500" ? "before":"accepted-style");r["id"]=id;r["name"]=id;records.append(r)
}
if let base=ProcessInfo.processInfo.environment["E500_BASELINE"] {
 let b=URL(fileURLWithPath:base),file="models/before-e500.m3dmodel",d=try Data(contentsOf:b.appendingPathComponent(file))
 try d.write(to:output.appendingPathComponent(file))
 let old=try Map3DModelFile(decoding:d,named:"before-e500").model
 records.append(record(old,file,"comparison","before"))
}
if let first=ProcessInfo.processInfo.environment["E500_FIRST_PASS"] {
 let file="models/first-pass-e500.m3dmodel",d=try Data(contentsOf:URL(fileURLWithPath:first).appendingPathComponent("models/e500.m3dmodel"))
 try d.write(to:output.appendingPathComponent(file));let m=try Map3DModelFile(decoding:d,named:"first-pass-e500").model
 records.append(record(m,file,"comparison","first-pass"))
}
if let previous=ProcessInfo.processInfo.environment["E500_PREVIOUS"] {
 for id in ["e500","e500-far"] {
  let file="models/previous-"+id+".m3dmodel",d=try Data(contentsOf:URL(fileURLWithPath:previous).appendingPathComponent("models/"+id+".m3dmodel"))
  try d.write(to:output.appendingPathComponent(file));let m=try Map3DModelFile(decoding:d,named:"previous-"+id).model
  records.append(record(m,file,"comparison","previous-producer-68913f4f"))
 }
}
let manifest:[String:Any] = ["schema_version":1,"recipe_version":3,"generator":"native-e500-refresh","producer_commit":producer,"models":records,"model_count":records.count,"directions":["top","bottom","left","right","front","back","isometric"],"native_coordinates":"metres +X front +Y left +Z up; tread Z=0","gltf_coordinates":"metres +X front +Y up -Z left","assembly":["unit":"e500","translation_m":[0,0,0],"rotation_degrees":0,"note":"single locomotive; one evidenced single-arm pantograph raised; no coach assets in this delivery"],"palette":["body":Map3DE500.bodyColor,"glass":Map3DE500.glassColor,"mask":Map3DE500.maskColor,"tire":Map3DColor.rgb(0x2B2E34)],"static_geometry":true]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("manifest.json"))
print("Exported \(records.count) native models with exact Swift readback")
