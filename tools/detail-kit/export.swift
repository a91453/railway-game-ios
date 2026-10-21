import Foundation
import GamePresentation

guard CommandLine.arguments.count==2 else { fatalError("usage: detail-kit-export OUTPUT_DIRECTORY") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
var componentRecords: [[String:Any]]=[]
@MainActor func export(_ model: Map3DModelPack.Model,info: [String:Any],name: String? = nil) throws {
    let assetName=name ?? model.name
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+assetName) }
    let provenance: [String:Any]=["asset":["generator":"Map3DDetailKit","version":"2.0"],"extras":["assetId":assetName,"recipeVersion":1,"source":"native-procedural","fidelity":info["fidelity"] ?? "illustrative","coordinateSystem":"metres; +x front, +y left, +z up"]]
    let text=try JSONSerialization.data(withJSONObject:provenance,options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let t=model.vertices[start..<start+3];put32(t.contains { $0.glows } ? 1 : 0)
        for v in t { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
    }
    let decoded=try Map3DModelFile(decoding:data,named:assetName)
    guard decoded.model.vertices==model.vertices else { fatalError("Native readback differs: "+assetName) }
    try data.write(to:directory.appendingPathComponent(assetName+".m3dmodel"),options:.atomic)
    var record=info
    record.merge(["id":assetName,"native":"models/"+assetName+".m3dmodel","triangles":model.triangleCount,
                  "minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]]) { _,v in v }
    if record["category"] as? String == "component" { componentRecords.append(record) } else { records.append(record) }
}

func point(_ p: Map3DPoint) -> [Float] { [p.x,p.y,p.z] }
for part in Map3DDetailKit.Part.allCases {
    var info: [String:Any]=["name":part.name,"category":part.category.rawValue,"mount":part.mount.rawValue,"fidelity":"modular-game-detail",
        "connectors":part.connectors.map { ["name":$0.name,"position":point($0.position),"normal":point($0.normal)] }]
    if let joint=part.joint {
        let pieces=Map3DDetailKit.components(for:part)
        info["joint"]=["kind":joint.kind.rawValue,"pivot":point(joint.pivot),"axis":point(joint.axis),"limit":[joint.limit.lowerBound,joint.limit.upperBound],"unit":joint.unit]
        info["component_ids"]=[pieces.fixed.name,pieces.moving!.name]
        for piece in [pieces.fixed,pieces.moving!] {
            try export(piece,info:["name":piece.name,"category":"component","parent":part.id,"fidelity":"separate-native-body"])
        }
    }
    try export(Map3DDetailKit.model(for:part),info:info)
    if let j=part.joint {
        let pose=j.limit.upperBound*0.63,model=Map3DDetailKit.model(for:part,pose:pose)
        try export(model,info:["name":part.name+"・動作姿態","category":"pose","parent":part.id,"pose":pose,"fidelity":"articulated-native-pose"],name:part.id+"-pose")
    }
}
for example in Map3DDetailKit.Example.allCases {
    try export(Map3DDetailKit.model(for:example),info:["name":example.name,"category":"example","fidelity":"illustrative-assembly"])
}
let manifest: [String:Any]=["schema_version":1,"generator":"Map3DDetailKit","recipe_version":1,"model_count":records.count,"part_count":Map3DDetailKit.Part.allCases.count,"example_count":Map3DDetailKit.Example.allCases.count,
    "native_coordinates":"metres; +x front, +y left, +z up","gltf_coordinates":"metres; +x front, +y up, -z left",
    "directions":["top","bottom","left","right","front","back","isometric"],"models":records,"components":componentRecords,
    "notes":"Illustrative game assets, not engineering drawings or safety equipment specifications. GLBs are static; animate separate bodies with the joint metadata."]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported \(records.count) viewable models and \(componentRecords.count) component meshes; every vertex round-trips through the native loader.")
