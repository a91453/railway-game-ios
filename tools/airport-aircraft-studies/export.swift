import Foundation
import GamePresentation

// Writes the Swift recipes of the airport and aircraft studies as native
// .m3dmodel files, named as produce.py names them, so parity.py can compare
// the two. Usage: export OUTPUT_DIRECTORY
guard CommandLine.arguments.count==2 else { fatalError("usage: export OUTPUT_DIRECTORY") }
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func write(_ id: String,_ model: Map3DModelPack.Model) throws {
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+id) }
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
    print(id,model.triangleCount)
}
let aircraft: [(Map3DAircraftStudies.Kind,String)]=[(.commuter19,"commuter19"),(.regional70,"regional70"),(.narrowJet,"narrowjet"),(.wideJet,"widejet")]
let parts: [(Map3DAirportStudies.Kind,String)]=[(.cityTerminal,"city"),(.islandTerminal,"island"),(.runway,"runway"),(.runwayEnd,"runway-end"),(.taxiway,"taxiway"),(.apron,"apron"),(.papi,"papi"),(.windsock,"windsock"),(.fence,"fence"),(.tug,"tug"),(.baggageCart,"baggage"),(.boardingStairs,"stairs"),(.fuelTruck,"fuel")]
for far in [false,true] {
    for (kind,id) in aircraft { try write(id+(far ? "-lod" : "-near"),Map3DAircraftStudies.model(kind,far:far)) }
    for (kind,id) in parts { try write(id+(far ? "-lod" : "-near"),Map3DAirportStudies.model(kind,far:far)) }
}
