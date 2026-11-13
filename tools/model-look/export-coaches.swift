import Foundation
import GameCore
@testable import GamePresentation

// tools/model-look: writes decision 708's coach stop and coaches as native
// .m3dmodel files for shoot.mjs. Usage: export-coaches OUTPUT_DIRECTORY
// Writes coach-stop (near), coach-stop-far, coach-stop-scene (the stop with
// a coach of each of two liveries standing at its kerb, as the map shows
// it) and coach-<livery> for every livery the routes use.
guard CommandLine.arguments.count>1 else { fatalError("usage: export-coaches OUTPUT_DIRECTORY") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func write(_ model: Map3DModelPack.Model,_ id: String) throws {
    let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":id,"coordinateSystem":"metres; x front, y left, z up"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let t=model.vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
    }
    try data.write(to:directory.appendingPathComponent(id+".m3dmodel"),options:.atomic)
    print(id,model.triangleCount,"triangles",model.minimum,model.maximum)
}
/// `model` moved by (`x`, `y`) on the ground.
func moved(_ model: Map3DModelPack.Model,x: Float,y: Float) -> [Map3DVertex] {
    model.vertices.map { var v=$0;v.x+=x;v.y+=y;return v }
}
let stop=Map3DCoachStop.model()
try write(stop,"coach-stop")
try write(Map3DCoachStop.model(far:true),"coach-stop-far")
for livery in Map3DCoaches.liveries { try write(Map3DCoachBus.model(livery:livery),"coach-"+livery.rawValue) }
// The stop as the map shows it: the kerb on its left (native +y), a coach
// standing there and another passing in the far lane.
var scene=stop.vertices
let kerb = Map3DCoachStop.depth/2+Map3DCoaches.stopSetback
scene+=moved(Map3DCoachBus.model(livery:Map3DCoaches.liveries[1]),x:0,y:kerb+1.6)
scene+=moved(Map3DCoachBus.model(livery:Map3DCoaches.liveries[4]),x:-9,y:kerb+5.2)
func bounds(_ vertices: [Map3DVertex]) -> (Map3DPoint,Map3DPoint) {
    var low=Map3DPoint(.infinity,.infinity,.infinity),high=Map3DPoint(-.infinity,-.infinity,-.infinity)
    for v in vertices { low=Map3DPoint(min(low.x,v.x),min(low.y,v.y),min(low.z,v.z));high=Map3DPoint(max(high.x,v.x),max(high.y,v.y),max(high.z,v.z)) }
    return (low,high)
}
let (low,high)=bounds(scene)
try write(Map3DModelPack.Model(name:"coach-stop-scene",vertices:scene,minimum:low,maximum:high),"coach-stop-scene")
