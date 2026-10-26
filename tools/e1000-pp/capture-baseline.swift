import Foundation
import GamePresentation
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output.appendingPathComponent("models"),withIntermediateDirectories:true)
for (name,suffix) in [("set-pushPull-head",""),("set-pushPullFar-head","-far")] {
guard let m=Map3DModelPack.standard.models.first(where:{$0.name==name}) else {fatalError("actual baseline pushPull coach unavailable")}
let metadata=try JSONSerialization.data(withJSONObject:["producer_commit":"2be9dacaf2e1fa92b9fae6e3593cfa122aeeb189","source_model":m.name,"role":"genuine first delivered E1000 power car","coordinates":"metres +X front +Y left +Z up"],options:[.sortedKeys])
var data=Data("M3DM".utf8)
@MainActor func word(_ bits:UInt32){let n:UInt32=bits==0x80000000 ? 0:bits;for s:UInt32 in [0,8,16,24]{data.append(UInt8((n>>s)&255))}}
data.append(contentsOf:[1,0,0,0]);word(UInt32(m.triangleCount));word(UInt32(metadata.count));data.append(metadata);data.append(contentsOf:repeatElement(UInt8(0),count:(4-metadata.count%4)%4))
for i in stride(from:0,to:m.vertices.count,by:3){word(m.vertices[i..<i+3].contains(where:{$0.glows}) ? 1:0);for v in m.vertices[i..<i+3]{word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color)}}
let decoded=try Map3DModelFile(decoding:data,named:"before-e1000").model
guard decoded.vertices.count==m.vertices.count else {fatalError("baseline readback count")}
for (a,b) in zip(decoded.vertices,m.vertices){guard a.position==b.position,a.color==b.color,a.layer==b.layer,abs(a.nx-b.nx)<0.00001,abs(a.ny-b.ny)<0.00001,abs(a.nz-b.nz)<0.00001 else {fatalError("baseline payload/normal mismatch")}}
try data.write(to:output.appendingPathComponent("models/before-e1000"+suffix+".m3dmodel"))
print("Captured genuine baseline",m.name,m.triangleCount)

}
