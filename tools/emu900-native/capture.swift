import Foundation
import GamePresentation
let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let pack=Map3DModelPack.standard
let direct=[Map3DE500.model(),Map3DE500.model(far:true),Map3DEMU3000.model(.ed)]
var signatures:[[String:Any]]=[]
for (id,m) in pack.models.map({($0.name,$0)}) + direct.map({("direct-"+$0.name,$0)}) {
 var raw=Data()
 var pin:UInt64=0xcbf29ce484222325
 func word(_ v:UInt32){for shift:UInt32 in [0,8,16,24]{raw.append(UInt8((v>>shift)&255))}}
 for v in m.vertices {
  for bits in [v.x.bitPattern,v.y.bitPattern,v.z.bitPattern,v.nx.bitPattern,v.ny.bitPattern,v.nz.bitPattern,v.color,v.u.bitPattern,v.v.bitPattern,v.layer.bitPattern] {
   for shift:UInt32 in [0,8,16,24] {pin = (pin ^ UInt64((bits>>shift)&255)) &* 0x100000001b3}
  }
  word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color);word(v.layer.bitPattern);word(v.nx.bitPattern);word(v.ny.bitPattern);word(v.nz.bitPattern)}
 let file=id.replacingOccurrences(of:"/",with:"-")+".payload"
 try raw.write(to:out.appendingPathComponent(file))
 signatures.append(["id":id,"triangles":m.triangleCount,"minimum":[m.minimum.x,m.minimum.y,m.minimum.z],"maximum":[m.maximum.x,m.maximum.y,m.maximum.z],"payload":file,"payload_fnv1a64":String(pin,radix:16)])
}
try JSONSerialization.data(withJSONObject:signatures,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("fingerprints.json"))
print("Captured actual base models",pack.models.count)

if let m=pack.models.first(where:{$0.name == "set-emu800-head"}) {
 var raw=Data("M3DM".utf8);raw.append(contentsOf:[1,0,0,0])
 func word(_ v:UInt32){for shift:UInt32 in [0,8,16,24]{raw.append(UInt8((v>>shift)&255))}}
 word(UInt32(m.triangleCount));word(2);raw.append(contentsOf:[123,125,0,0])
 for i in stride(from:0,to:m.vertices.count,by:3){word(0);for v in m.vertices[i..<i+3]{word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color)}}
 try raw.write(to:out.appendingPathComponent("before-emu900.m3dmodel"))
}
