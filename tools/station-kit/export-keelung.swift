import Foundation
import GamePresentation

guard CommandLine.arguments.count==2 else { fatalError("usage: station-kit-export OUTPUT_DIRECTORY") }
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
@MainActor func export(_ model: Map3DModelPack.Model,info: [String:Any]) throws {
    guard model.triangleCount>0,model.triangleCount<=Map3DModelFile.maximumTriangles else { fatalError("Triangle budget: "+model.name) }
    let provenance: [String:Any]=["asset":["generator":"Map3DStationExteriorBatch2","version":"2.0"],"extras":["assetId":model.name,"recipeVersion":1,"source":"OSM footprint; procedural superstructure","fidelity":info["fidelity"] ?? "illustrative","coordinateSystem":"metres; +x east, +y south, +z up"]]
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
let stationInfo: [Map3DStationExteriorBatch2.Station: (String, String)] = [
    .keelung: ("臺鐵基隆", "TRA"),
    .chiayi: ("臺鐵嘉義", "TRA"),
    .tainan: ("臺鐵臺南", "TRA"),
    .beimen: ("阿里山林鐵北門", "Alishan Forest Railway"),
    .fenqihu: ("阿里山林鐵奮起湖", "Alishan Forest Railway"),
    .alishan: ("阿里山林鐵阿里山", "Alishan Forest Railway"),
    .wushulin: ("糖鐵烏樹林", "Sugar Railway"),
    .xihu: ("糖鐵溪湖", "Sugar Railway"),
    .qiaotou: ("糖鐵橋頭", "Sugar Railway"),
]
for station in [Map3DStationExteriorBatch2.Station.keelung] {
    for detail in [Map3DStationExteriorBatch2.LevelOfDetail.near, .far] {
        let model = Map3DStationExteriorBatch2.model(for: station, detail: detail)
        let (name, system) = stationInfo[station]!
        try export(model, info: ["name":name, "system":system, "category":"station-exterior-study", "lod":detail == .near ? "near" : "far", "fidelity":"research-exterior"])
    }
    if let context=Map3DStationExteriorBatch2.contextModel(for:station,detail:.near) {
        let (name,system)=stationInfo[station]!
        try export(context,info:["name":name+"（可選站前零件）","system":system,"category":"station-context","lod":"near","fidelity":"estimated-context"])
        let scene=Map3DStationExteriorBatch2.model(for:station,detail:.near,includeContext:true)
        try export(scene,info:["name":name+"（站房與可選站前零件）","system":system,"category":"station-exterior-scene","lod":"near","fidelity":"research-exterior-context"])
    }
}
let manifest: [String:Any]=["schema_version":1,"generator":"Map3DStationExteriorBatch2","recipe_version":1,"model_count":records.count,
    "station_count":1,"part_count":0,"native_coordinates":"metres; +x east, +y south, +z up",
    "gltf_coordinates":"metres; +x east, +y up, -z south","directions":["top","bottom","left","right","front","back","isometric"],"models":records]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported \(records.count) native models; every vertex round-trips through the native loader.")
