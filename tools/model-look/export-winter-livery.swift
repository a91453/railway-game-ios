import Foundation
import GameCore
@testable import GamePresentation

// tools/model-look: the Christmas livery (decision 795) on the pack's
// running cars. Prints, a car a line, how much of its painted side is body,
// band and line (the cars to look at are those with more band than body, or
// no band); writes each car named plain and in the livery as .m3dmodel
// files for shoot.mjs. Usage: export-winter.sh livery OUTPUT_DIRECTORY [MODEL_NAME...]
guard CommandLine.arguments.count>1 else { fatalError("usage: export-winter-livery OUTPUT_DIRECTORY [MODEL_NAME...]") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
let pack=Map3DModelPack.standard
func write(_ vertices: [Map3DVertex],named name: String) throws {
    let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":name,"coordinateSystem":"metres; x front, y left, z up"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(vertices.count/3));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:vertices.count,by:3) {
        let t=vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        // A band's alpha is the share of the line's colour: drawn here as a mid grey line colour.
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color>>24==0xFF ? v.color : 0xFF00_0000|Map3DColor.shaded(0xFF3A_7BD5,1)&0xFFFFFF) }
    }
    try data.write(to:directory.appendingPathComponent(name+".m3dmodel"),options:.atomic)
}
let wanted=Set(CommandLine.arguments.dropFirst(2))
for index in pack.christmas.keys.sorted() {
    let model=pack.models[index],table=pack.christmas[index]!
    var area=[Float](repeating:0,count:4)
    for first in stride(from:0,to:model.vertices.count-2,by:3) {
        let a=model.vertices[first],b=model.vertices[first+1],c=model.vertices[first+2]
        area[Int(table[first]&3)]+=((b.position-a.position).cross(c.position-a.position)).length/2
    }
    let painted=area[1]+area[2]+area[3]
    print(String(format:"%@\tbody %.0f%%\tband %.0f%%\tline %.0f%%",model.name,area[1]/painted*100,area[2]/painted*100,area[3]/painted*100))
    guard wanted.contains(model.name) else { continue }
    try write(model.vertices,named:model.name+"-plain")
    try write(Map3DChristmasLivery.recoloured(model.vertices,table:table),named:model.name+"-christmas")
}
