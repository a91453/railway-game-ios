import Foundation
import GamePresentation

let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
var records: [[String:Any]]=[]
for livery in Map3DCoachLivery.allCases {
    for far in [false,true] {
        let model=Map3DCoachBus.model(livery:livery,far:far)
        let id=livery.rawValue+(far ? "-far" : "-near")
        let folder=output.appendingPathComponent(id,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let provenance: [String:Any]=["asset":["generator":"coach-bus/liveries-export.swift","version":"1"],"extras":["id":id,"studyOnly":true,"coordinates":"metres +x front +y left +z up"]]
        let info=try JSONSerialization.data(withJSONObject:provenance,options:[.sortedKeys])
        var data=Data("M3DM".utf8)
        func put16(_ v:UInt16) { data.append(UInt8(v&255));data.append(UInt8(v>>8)) }
        func put32(_ v:UInt32) { for shift:UInt32 in [0,8,16,24] { data.append(UInt8((v>>shift)&255)) } }
        put16(1);put16(0);put32(UInt32(model.triangleCount));put32(UInt32(info.count));data.append(info)
        data.append(contentsOf:repeatElement(0,count:(4-info.count%4)%4))
        for start in stride(from:0,to:model.vertices.count,by:3) {
            let triangle=model.vertices[start..<start+3]
            put32(triangle.contains { $0.glows } ? 1 : 0)
            for v in triangle { put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(v.color) }
        }
        let native=id+"/"+id+".m3dmodel"
        try data.write(to:output.appendingPathComponent(native),options:.atomic)
        records.append(["id":id,"livery_id":livery.rawValue,"name_zh":livery.nameZH,"name_en":livery.nameEN,"tourism":livery.isTourism,"far":far,"native":native,"triangles":model.triangleCount])
    }
}
let manifest: [String:Any]=["schema_version":1,"coordinates":"metres +x front +y left +z up","directions":["top","bottom","left","right","front","back","isometric"],"models":records]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
print("Exported \(records.count) livery models")
