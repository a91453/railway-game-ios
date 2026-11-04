import Foundation
import GamePresentation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)!
var count=0
for case let url as URL in files where url.pathExtension=="m3dmodel" {
 let bytes=[UInt8](try Data(contentsOf:url)), model=try Map3DModelFile(decoding:bytes,named:url.lastPathComponent).model
 func u32(_ at:Int)->UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at+$1]) << UInt32($1*8) } }
 let n=Int(u32(8)),start=16+(Int(u32(12))+3)/4*4
 precondition(model.triangleCount==n)
 for i in 0..<n { for j in 0..<3 {
  let at=start+i*52+4+j*16,v=model.vertices[i*3+j]
  precondition(v.x.bitPattern==u32(at) && v.y.bitPattern==u32(at+4) && v.z.bitPattern==u32(at+8) && v.color==u32(at+12))
  precondition(v.glows == (u32(start+i*52)&1 != 0))
  precondition(v.layer == (u32(start+i*52)&2 != 0 ? Map3DVertex.trainGlass : Map3DVertex.plain))
 } }
 count+=1
}
print("VERIFIED native Swift loader: \(count) files, every position/color/glow/glass layer round-trips")
