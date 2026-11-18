import Foundation
import GameCore
@testable import GamePresentation

// tools/model-look: decision 840's reindeer as .m3dmodel files for shoot.mjs,
// each in its colours now (`<name>`) and as first integrated (`<name>-before`:
// pale antlers, the sleigh's team grey).
// Usage: export-reindeer.sh OUTPUT_DIRECTORY
guard CommandLine.arguments.count>1 else { fatalError("usage: export-reindeer.sh OUTPUT_DIRECTORY") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func write(_ model: Map3DModelPack.Model,named name: String) throws {
    let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":name,"coordinateSystem":"metres; x front, y left, z up"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let t=model.vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
    }
    try data.write(to:directory.appendingPathComponent(name+".m3dmodel"),options:.atomic)
}
// The colours as first integrated: bone-grey antlers, every team grey.
var first=Map3DReindeer.meshPalette
first[3]=Map3DPalette.concrete
for unit in Map3DReindeer.Unit.allCases {
    let now=Map3DReindeer.model(unit)!
    try write(now,named:unit.rawValue)
    let data=Data(base64Encoded:Map3DReindeer.encoded[unit.rawValue]!,options:.ignoreUnknownCharacters)!
    let old=Map3DRedCommuter.decodedMesh([UInt8](data),named:unit.rawValue+"-before",palette:first)!
    try write(old,named:unit.rawValue+"-before")
    print(unit.rawValue,now.triangleCount,"bounds",now.minimum,now.maximum)
}
