import Foundation
import GamePresentation

// Built and linked by export.sh against this checkout's native Swift modules.
// No image reconstruction, private mesh input or third-party dependency.
let arguments=CommandLine.arguments
guard arguments.count==2 else {
    FileHandle.standardError.write(Data("usage: scene-kit-export OUTPUT_DIRECTORY\n".utf8))
    exit(2)
}
let output=URL(fileURLWithPath:arguments[1],isDirectory:true)
let directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
for asset in Map3DSceneKit.assets {
    let model=Map3DSceneKit.model(for:asset)
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else {
        throw NSError(domain:"SceneKitExport",code:1,userInfo:[NSLocalizedDescriptionKey:"Invalid triangle budget for \(asset.id): \(model.triangleCount)"])
    }
    let provenance: [String:Any]=[
        "asset":["generator":"Along the Line native procedural scene kit","version":"2.0"],
        "extras":["assetId":asset.id,"recipeVersion":1,"source":"native-procedural","coordinateSystem":"metres; +x front, +y left, +z up"]
    ]
    let text=try JSONSerialization.data(withJSONObject:provenance,options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3) {
        let triangle=model.vertices[start..<start+3]
        put32(triangle.contains { $0.glows } ? 1 : 0)
        for vertex in triangle {
            put32(vertex.x.bitPattern);put32(vertex.y.bitPattern);put32(vertex.z.bitPattern);put32(vertex.color)
        }
    }
    let decoded=try Map3DModelFile(decoding:data,named:asset.id)
    guard decoded.model.vertices==model.vertices else {
        throw NSError(domain:"SceneKitExport",code:2,userInfo:[NSLocalizedDescriptionKey:"Native round-trip mismatch: \(asset.id)"])
    }
    try data.write(to:directory.appendingPathComponent(asset.id+".m3dmodel"),options:.atomic)
    records.append([
        "id":asset.id,"name":asset.name,"category":asset.category,"family":asset.family.rawValue,"variant":asset.variant,
        "native":"models/"+asset.id+".m3dmodel","triangles":model.triangleCount,
        "minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z],
        "remixed":"New massing, roof profile, facade rhythm and equipment arrangement in the native matte palette; no private source vertices or textures."
    ])
}
let manifest: [String:Any]=[
    "schema_version":1,"generator":"Map3DSceneKit","recipe_version":1,"model_count":records.count,
    "native_coordinates":"metres; +x front, +y left, +z up",
    "gltf_coordinates":"metres; +x front, +y up, -z left",
    "directions":["top","bottom","left","right","front","back","isometric"],"models":records
]
let manifestData=try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
try manifestData.write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported \(records.count) native models; every file round-trips through Map3DModelFile.")
