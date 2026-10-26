import Foundation
import GamePresentation
let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let pack=Map3DModelPack.standard
let direct=[Map3DE500.model(),Map3DE500.model(far:true),Map3DEMU3000.model(.ed)]
var signatures:[[String:Any]]=[]
for (id,m) in pack.models.map({($0.name,$0)}) + direct.map({("direct-"+$0.name,$0)}) {
 var raw=Data()
 func word(_ v:UInt32){for shift:UInt32 in [0,8,16,24]{raw.append(UInt8((v>>shift)&255))}}
 for v in m.vertices {word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color);word(v.layer.bitPattern);word(v.nx.bitPattern);word(v.ny.bitPattern);word(v.nz.bitPattern)}
 let file=id.replacingOccurrences(of:"/",with:"-")+".payload"
 try raw.write(to:out.appendingPathComponent(file))
 signatures.append(["id":id,"triangles":m.triangleCount,"minimum":[m.minimum.x,m.minimum.y,m.minimum.z],"maximum":[m.maximum.x,m.maximum.y,m.maximum.z],"payload":file])
}
try JSONSerialization.data(withJSONObject:signatures,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("fingerprints.json"))
print("Captured actual base models",pack.models.count)
