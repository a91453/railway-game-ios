import Foundation
import GameCore
@testable import GamePresentation

// tools/model-look: each kind of station building with the winter event's
// lights hung on it as the map hangs them (Map3DWinterLights.strings(on:)),
// and the kit's exit with its own, as .m3dmodel files for shoot.mjs.
// Usage: export-winter.sh lights OUTPUT_DIRECTORY [before]
// `before`: the lights as decision 794 first hung them (along the bounds'
// front, forecourt included), for the before half of a sheet.
guard CommandLine.arguments.count>1 else { fatalError("usage: export-winter.sh lights OUTPUT_DIRECTORY [before]") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),before=CommandLine.arguments.dropFirst(2).first=="before"
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
let string=Map3DWinterDecor.lightString.model!
/// The house's model (native: x front, y left, z up) with a length of lights at each of `points` (the kit's: y up, z along).
func hung(_ mesh: Map3DMesh,_ points: [Map3DPoint],alongX: Bool = false,named name: String) -> Map3DModelPack.Model {
    var vertices=Map3DModelPack.Model.flat(named:name,from:mesh).vertices
    for p in points {
        for v in string.vertices {
            var w=v
            let at=alongX ? Map3DPoint(p.x+v.x,-p.z+v.y,p.y+v.z) : Map3DPoint(p.x-v.y,-p.z+v.x,p.y+v.z)
            w.x=at.x;w.y=at.y;w.z=at.z
            vertices.append(w)
        }
    }
    var low=Map3DPoint(.infinity,.infinity,.infinity),high=Map3DPoint(-.infinity,-.infinity,-.infinity)
    for v in vertices { low=Map3DPoint(min(low.x,v.x),min(low.y,v.y),min(low.z,v.z));high=Map3DPoint(max(high.x,v.x),max(high.y,v.y),max(high.z,v.z)) }
    return Map3DModelPack.Model(name:name,vertices:vertices,minimum:low,maximum:high)
}
func old(_ mesh: Map3DMesh) -> [Map3DPoint] {
    guard let b=mesh.bounds else { return [] }
    let wide=b.max.z-b.min.z,count=min(8,Int(((wide-1)/4).rounded(.down)))
    let height=min(b.max.y*0.6,6)
    return (0..<max(0,count)).map { Map3DPoint(b.max.x-0.4,height,(b.min.z+b.max.z)/2+(Float($0)-Float(count-1)/2)*4) }
}
func write(_ model: Map3DModelPack.Model) throws {
    let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":model.name,"coordinateSystem":"metres; x front, y left, z up"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let t=model.vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
    }
    try data.write(to:directory.appendingPathComponent(model.name+".m3dmodel"),options:.atomic)
}
// One station of each profile that has a building; the two roofs of the plain ones; the two expansions.
var kinds: [(name: String,station: Map3DStationKit.Station,expansion: StationExpansion?)]=[]
for profile in Map3DStationKit.Profile.allCases where Map3DStationKit.hasHouse(profile) {
    let all=Map3DStationKit.stations.filter { $0.profile==profile }
    guard let first=all.first else { continue }
    kinds.append((profile.rawValue,first,nil))
    if profile == .regional || profile == .halt,let other=all.first(where:{ $0.seed%7%2 != first.seed%7%2 }) { kinds.append((profile.rawValue+"-2",other,nil)) }
    if profile == .regional { kinds.append((profile.rawValue+"-concourse",first,.concourse));kinds.append((profile.rawValue+"-hall",first,.hall)) }
}
for kind in kinds {
    var kit=StationKitBuilder();kit.house(kind.station,expansion:kind.expansion)
    let points=before ? old(kit.mesh) : Map3DWinterLights.strings(on:kit.mesh)
    let model=hung(kit.mesh,points,named:"winter-"+kind.name)
    try write(model)
    let b=kit.mesh.bounds!
    print(model.name,kind.station.name,points.count,"strings",points.map { String(format:"(%.1f,%.1f,%.1f)",$0.x,$0.y,$0.z) }.joined(separator:" "),"bounds x",b.min.x,b.max.x,"top",b.max.y)
}
for part in [Map3DStationKit.Part.undergroundExit,.stairHead] {
    var kit=StationKitBuilder();kit.part(part)
    try write(hung(kit.mesh,before ? [] : Map3DWinterLights.exitStrings,alongX:true,named:"winter-"+part.id))
}
