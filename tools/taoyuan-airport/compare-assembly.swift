import Foundation
@testable import GamePresentation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
var checked=0
var maximumError: Float = 0
for fleet in ["1000","2000"] { for far in [false,true] {
    let suffix=far ? "-far" : ""
    var builder=StationKitBuilder()
    let roles: [Map3DTaoyuanAirport.Role] = fleet == "1000" ? [.dmc1,.mc1,.mc2,.dmc2] : [.dme1,.me1,.me3,.me4,.dmb]
    var cursor=roles.reduce(Float(0)) { $0+$1.pitch }/2
    for (index,role) in roles.enumerated() {
        let x=cursor-role.pitch/2;cursor-=role.pitch
        let bytes=try Data(contentsOf:root.appendingPathComponent("models/taoyuan-airport-\(role.rawValue)\(suffix).m3dmodel"))
        let unit=try Map3DModelFile(decoding:bytes,named:"unit").model
        builder.add(unit,at:Map3DPoint(x,0,0),angle:index == roles.count-1 ? .pi : 0)
    }
    let expected=Map3DModelPack.Model.flat(named:"direct",from:builder.mesh)
    let file=root.appendingPathComponent("models/taoyuan-airport-\(fleet)-formation\(suffix).triangles.bin")
    let payload=[UInt8](try Data(contentsOf:file))
    func word(_ at:Int)->UInt32 { (0..<4).reduce(0) { $0 | UInt32(payload[at+$1]) << UInt32(8*$1) } }
    precondition(payload.count==expected.triangleCount*52)
    for (i,v) in expected.vertices.enumerated() {
        let at=(i/3)*52+4+(i%3)*16
        for (axis,value) in [v.x,v.y,v.z].enumerated() {
            let error=abs(Float(bitPattern:word(at+axis*4))-value)
            maximumError=max(maximumError,error);precondition(error<0.00001)
        }
        precondition(word(at+12)==v.color);checked+=1
    }
}
}
print("VERIFIED independent Swift formation: \(checked) vertices, maximum position error \(maximumError)m; all colours equal")
