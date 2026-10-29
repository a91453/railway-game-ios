import Foundation
@testable import GamePresentation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
var checked=0
var maximumError: Float = 0
for far in [false,true] {
    let suffix=far ? "-far" : ""
    var builder=StationKitBuilder()
    for (role,x,angle):(Map3DKaohsiung.Unit,Float,Float) in [(.dm1,21.7525,0),(.t,0,0),(.dm2,-21.7525,.pi)] {
        let bytes=try Data(contentsOf:root.appendingPathComponent("models/kaohsiung-\(role.rawValue)\(suffix).m3dmodel"))
        let unit=try Map3DModelFile(decoding:bytes,named:"unit").model
        builder.add(unit,at:Map3DPoint(x,0,0),angle:angle)
    }
    let expected=Map3DModelPack.Model.flat(named:"direct",from:builder.mesh)
    let file=root.appendingPathComponent("models/kaohsiung-formation\(suffix).triangles.bin")
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
print("VERIFIED independent Swift formation: \(checked) vertices, maximum position error \(maximumError)m; all colours equal")
