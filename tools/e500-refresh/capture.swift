import Foundation
import GamePresentation
let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let pack=Map3DModelPack.standard
var signatures:[[String:Any]]=[]
for m in pack.models+Map3DModelPack.studies.models {
 var raw=Data()
 func word(_ v:UInt32){for shift:UInt32 in [0,8,16,24]{raw.append(UInt8((v>>shift)&255))}}
 for v in m.vertices {word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color);word(v.layer.bitPattern)}
 let file=m.name.replacingOccurrences(of:"/",with:"-")+".payload"
 try raw.write(to:out.appendingPathComponent(file))
 signatures.append(["id":m.name,"triangles":m.triangleCount,"minimum":[m.minimum.x,m.minimum.y,m.minimum.z],"maximum":[m.maximum.x,m.maximum.y,m.maximum.z],"payload":file])
}
try JSONSerialization.data(withJSONObject:signatures,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("fingerprints.json"))
print("Captured actual base models",pack.models.count+Map3DModelPack.studies.models.count)
