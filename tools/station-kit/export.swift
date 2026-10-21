import Foundation
import GamePresentation

guard CommandLine.arguments.count==2 else { fatalError("usage: station-kit-export OUTPUT_DIRECTORY") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
@MainActor func export(_ model: Map3DModelPack.Model,info: [String:Any]) throws {
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+model.name) }
    let provenance: [String:Any]=["asset":["generator":"Map3DStationKit","version":"2.0"],"extras":["assetId":model.name,"recipeVersion":1,"source":"native-procedural","fidelity":info["fidelity"] ?? "illustrative","coordinateSystem":"metres; +x front, +y left, +z up"]]
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
    let decoded=try Map3DModelFile(decoding:data,named:model.name)
    guard decoded.model.vertices==model.vertices else { fatalError("Native readback differs: "+model.name) }
    try data.write(to:directory.appendingPathComponent(model.name+".m3dmodel"),options:.atomic)
    var record=info
    record.merge(["id":model.name,"native":"models/"+model.name+".m3dmodel","triangles":model.triangleCount,
                  "minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]]) { _,v in v }
    records.append(record)
}
for station in Map3DStationKit.stations {
    try export(Map3DStationKit.model(for:station),info:["name":station.name,"category":"station","system":station.system,"profile":station.profile.rawValue,
        "landmark":station.isLandmark,"fidelity":station.isLandmark ? "remixed-landmark-exterior" : "catalog-archetype",
        "latitude":station.latitude,"longitude":station.longitude,"lines":station.lines,"planned":station.planned,
        "realBuildingHeightM":NSNull(),"railElevationM":NSNull(),"layout":"illustrative; not a surveyed or operational station plan"])
}
for part in Map3DStationKit.Part.allCases {
    try export(Map3DStationKit.model(for:part),info:["name":part.name,"category":part.category,"mount":part.mount.rawValue,"fidelity":"modular-game-part",
        "connectors":part.connectors.map { ["name":$0.name,"position":[$0.position.x,$0.position.y,$0.position.z],"normal":[$0.normal.x,$0.normal.y,$0.normal.z]] }])
}
try export(Map3DStationKit.exampleModel(),info:["name":"模組化站前與月台組景","category":"example","fidelity":"illustrative-assembly"])
let manifest: [String:Any]=["schema_version":1,"generator":"Map3DStationKit","recipe_version":1,"model_count":records.count,
    "station_count":Map3DStationKit.stations.count,"part_count":Map3DStationKit.Part.allCases.count,
    "native_coordinates":"metres; +x front, +y left, +z up","gltf_coordinates":"metres; +x front, +y up, -z left",
    "source_catalog":"RailwayGameApp/Resources/RealRailways/track_stations.geojson","directions":["top","bottom","left","right","front","back","isometric"],"models":records]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported \(records.count) native models; every vertex round-trips through the native loader.")
