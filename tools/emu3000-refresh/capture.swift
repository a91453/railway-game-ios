import Foundation
import GamePresentation
let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let pack=Map3DModelPack.standard
var signatures:[[String:Any]]=[]
for m in pack.models {
 var raw=Data()
 func word(_ v:UInt32){for shift:UInt32 in [0,8,16,24]{raw.append(UInt8((v>>shift)&255))}}
 for v in m.vertices {word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color);word(v.layer.bitPattern)}
 let file=m.name.replacingOccurrences(of:"/",with:"-")+".payload"
 try raw.write(to:out.appendingPathComponent(file))
 signatures.append(["id":m.name,"triangles":m.triangleCount,"minimum":[m.minimum.x,m.minimum.y,m.minimum.z],"maximum":[m.maximum.x,m.maximum.y,m.maximum.z],"payload":file])
}
try JSONSerialization.data(withJSONObject:signatures,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("fingerprints.json"))
print("Captured actual base models",pack.models.count)

var units:[String:String]=[:];var records:[[String:Any]]=[]
for name in ["set-emu3000-head","set-emu3000-car","set-emu3000-tail"] {
 guard let m=pack.models.first(where:{$0.name == name}) else {continue}
 let meta=Data("{\"producer\":\"85d9aa359dfcd6213f76a6559abebd9155806e97\",\"source\":\"actual-pre-change-native-pack\"}".utf8)
 var d=Data("M3DM".utf8)
 func w(_ n:UInt32){for k:UInt32 in [0,8,16,24]{d.append(UInt8((n>>k)&255))}}
 d.append(contentsOf:[1,0,0,0]);w(UInt32(m.triangleCount));w(UInt32(meta.count));d.append(meta);d.append(contentsOf:repeatElement(UInt8(0),count:(4-meta.count%4)%4))
 for i in stride(from:0,to:m.vertices.count,by:3){w(m.vertices[i..<i+3].contains(where:{$0.glows}) ? 1:0);for v in m.vertices[i..<i+3]{w(v.x.bitPattern);w(v.y.bitPattern);w(v.z.bitPattern);w(v.color)}}
 let file=name+".m3dmodel";try d.write(to:out.appendingPathComponent(file));units[name]=d.base64EncodedString()
 records.append(["id":name,"native":file,"category":"baseline","minimum":[m.minimum.x,m.minimum.y,m.minimum.z],"maximum":[m.maximum.x,m.maximum.y,m.maximum.z],"triangles":m.triangleCount])
}
var places:[[String:Any]]=[]
for i in 0..<12 {
 let id = i == 0 ? "set-emu3000-head" : i == 11 ? "set-emu3000-tail":"set-emu3000-car"
 let m=pack.models.first(where:{$0.name==id})!,pos:[Float]=[Float(11-2*i)*10,0,0]
 // Exact pre-change straight-track display contract:20m pitch,19.4m body.
 places.append(["unit":id,"translation":pos,"scale_x":Float(19.4)/m.length])
}
let scene:[String:Any] = ["format":"M3DAssembly","version":1,"units":units,"placements":places]
try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys]).write(to:out.appendingPathComponent("before-formation.m3dscene.json"))
try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("models.json"))
