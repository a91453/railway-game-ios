import Foundation
@testable import GamePresentation

// Read delivered independent native units, assemble using the native builder,
// then compare the JS expansion's *actual* payload, positions, flags and colours.
let root=URL(fileURLWithPath:CommandLine.arguments[1])
var rows: [[String:Any]]=[]
for (fleet,roles,positions) in [
    ("caf",["c1","s1","r","s2","c2"],[Float(13.1915),5.65,0,-5.65,-13.1915]),
    ("citadis",["m1","sc1","np","sc2","m2"],[Float(12.775),5.325,0,-5.325,-12.775])
] {
    for far in [false,true] {
        let suffix=far ? "-far":"", dir=root.appendingPathComponent(fleet)
        var builder=StationKitBuilder()
        for i in 0..<5 {
            let id="klrt-\(fleet)-\(roles[i])\(suffix)"
            let bytes=try Data(contentsOf:dir.appendingPathComponent("models/\(id).m3dmodel"))
            let unit=try Map3DModelFile(decoding:bytes,named:id).model
            builder.add(unit,at:Map3DPoint(positions[i],0,0),angle:i==4 ? .pi:0)
        }
        let expected=Map3DModelPack.Model.flat(named:"direct",from:builder.mesh)
        // flat(named:from:) is the existing prop helper: it reduces layers to
        // plain/glowing. Compare material flags from the builder's real corners
        // instead, preserving native train glass without changing that helper.
        precondition(expected.vertices.count==builder.mesh.indices.count)
        let id="klrt-\(fleet)-formation\(suffix)"
        let payload=[UInt8](try Data(contentsOf:dir.appendingPathComponent("models/\(id).triangles.bin")))
        func word(_ at: Int)->UInt32 { (0..<4).reduce(0) { $0 | UInt32(payload[at+$1]) << UInt32(8*$1) } }
        precondition(payload.count==expected.triangleCount*52)
        var error:Float=0
        for (i,v) in expected.vertices.enumerated() {
            let at=(i/3)*52+4+(i%3)*16
            for (axis,value) in [v.x,v.y,v.z].enumerated() { error=max(error,abs(Float(bitPattern:word(at+axis*4))-value)) }
            precondition(word(at+12)==v.color)
            let flags=word((i/3)*52)
            let corner=builder.mesh.vertices[Int(builder.mesh.indices[i])]
            let glass:UInt32=[Map3DVertex.trainGlass,Map3DVertex.trainGlassLit].contains(corner.layer) ? 2:0
            let steel:UInt32=corner.layer==Map3DVertex.trainSteel ? 4:0
            precondition(flags==(corner.glows ? 1:0)|glass|steel)
        }
        precondition(error<0.00001)
        rows.append(["id":id,"vertices":expected.vertices.count,"maximum_position_error_metres":error,"colors_and_glass_flags_equal":true])
    }
}
let data=try JSONSerialization.data(withJSONObject:["status":"VERIFIED","models":rows],options:[.prettyPrinted,.sortedKeys])
try data.write(to:root.appendingPathComponent("swift-assembly-verification.json"))
print(String(decoding:data,as:UTF8.self))
