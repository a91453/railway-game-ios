import Foundation
import GamePresentation

let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let directory=output.appendingPathComponent("models",isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
var records:[[String:Any]]=[]
var units:[String:String]=[:]
@MainActor func write(_ model:Map3DModelPack.Model, category:String, arrangement:[String]=[], centres:[Float]=[]) throws {
    let id=model.name
    if category == "formation" && model.triangleCount > Map3DModelFile.maximumTriangles {
        let placements=zip(arrangement,centres).map { ["unit":$0.0,"translation":[$0.1,Float(0),Float(0)]] as [String:Any] }
        let scene:[String:Any]=["format":"M3DAssembly","version":1,"units":units,"placements":placements]
        let name="models/"+id+".m3dscene.json"
        var sceneData=try JSONSerialization.data(withJSONObject:scene,options:[.sortedKeys])
        if id == "c371-formation",CommandLine.arguments.count>2,!CommandLine.arguments[2].isEmpty {
            let frozen=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
            guard let previous=try JSONSerialization.jsonObject(with:frozen) as? [String:Any],
                  previous["format"] as? String == "M3DAssembly",
                  let oldUnits=previous["units"] as? [String:String],
                  let oldPlacements=previous["placements"] as? [[String:Any]],oldPlacements.count==arrangement.count else {fatalError("invalid protected C371 assembly")}
            for (i,unit) in arrangement.enumerated() {
                guard oldUnits[unit]==units[unit],oldPlacements[i]["unit"] as? String==unit,
                      let p=oldPlacements[i]["translation"] as? [NSNumber],p.count==3,
                      p[0].floatValue==centres[i],p[1].floatValue==0,p[2].floatValue==0 else {fatalError("protected C371 unit or placement changed")}
            }
            // The accepted assembly contains unused legacy C381 entries.
            // Preserve its complete bytes; validate every referenced C371
            // unit/placement here and the expanded Swift payload in package.mjs.
            sceneData=frozen
        }
        try sceneData.write(to:output.appendingPathComponent(name))
        // Raw expected triangle payload, never an over-limit M3DM file.
        let expectedDirectory=output.appendingPathComponent("verification",isDirectory:true)
        try FileManager.default.createDirectory(at:expectedDirectory,withIntermediateDirectories:true)
        var expected=Data()
        func word(_ n:UInt32){for shift:UInt32 in [0,8,16,24]{expected.append(UInt8((n>>shift)&255))}}
        for start in stride(from:0,to:model.vertices.count,by:3) {
            let tri=model.vertices[start..<start+3];word(tri.contains{$0.glows} ? 1:0)
            for v in tri {word(v.x.bitPattern);word(v.y.bitPattern);word(v.z.bitPattern);word(v.color)}
        }
        let expectedPath="verification/"+id+".expected-triangles.bin"
        try expected.write(to:output.appendingPathComponent(expectedPath))
        records.append(["id":id,"name":id,"category":category,"native":name,"native_kind":"assembly","assembly_expected":expectedPath,"triangles":model.triangleCount,"minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]])
        return
    }
    guard model.triangleCount>0 && model.triangleCount<=Map3DModelFile.maximumTriangles else {fatalError("triangle budget")}
    let metadata=try JSONSerialization.data(withJSONObject:["asset":["generator":"Map3DC371+Map3DC381","version":"1.0"],"extras":["assetId":id,"coordinateSystem":"metres +x front +y left +z up"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func u16(_ n:UInt16){data.append(UInt8(n&255));data.append(UInt8(n>>8))}
    func u32(_ n:UInt32){for shift:UInt32 in [0,8,16,24]{data.append(UInt8((n>>shift)&255))}}
    u16(1);u16(0);u32(UInt32(model.triangleCount));u32(UInt32(metadata.count));data.append(metadata)
    data.append(contentsOf:repeatElement(UInt8(0),count:(4-metadata.count%4)%4))
    for start in stride(from:0,to:model.vertices.count,by:3){let tri=model.vertices[start..<start+3];u32(tri.contains{$0.glows} ? 1:0);for v in tri{u32(v.x.bitPattern);u32(v.y.bitPattern);u32(v.z.bitPattern);u32(v.color)}}
    let decoded=try Map3DModelFile(decoding:data,named:id).model
    guard decoded.vertices.count==model.vertices.count else{fatalError("vertex count")}
    for (a,b) in zip(decoded.vertices,model.vertices){guard a.position==b.position && a.color==b.color && abs(a.nx-b.nx)<0.00001 && abs(a.ny-b.ny)<0.00001 && abs(a.nz-b.nz)<0.00001 else{fatalError("readback")}}
    let name="models/"+id+".m3dmodel"
    try data.write(to:output.appendingPathComponent(name))
    units[id]=data.base64EncodedString()
    records.append(["id":id,"name":id,"category":category,"native":name,"triangles":model.triangleCount,"minimum":[model.minimum.x,model.minimum.y,model.minimum.z],"maximum":[model.maximum.x,model.maximum.y,model.maximum.z]])
}
for unit in Map3DC371.Unit.allCases {try write(Map3DC371.model(unit),category:"section")}
for unit in Map3DC381.Unit.allCases {try write(Map3DC381.model(unit),category:"section")}
try write(Map3DC371.formation(),category:"formation",arrangement:Map3DC371.arrangement.map{"c371-"+$0.rawValue},centres:(0..<6).map{(2.5-Float($0))*23.5})
try write(Map3DC381.formation(),category:"formation",arrangement:Map3DC381.arrangement.map{"c381-"+$0.rawValue},centres:[58.855,35.25,11.75,-11.75,-35.25,-58.855])
try write(Map3DEMU3000.model(.ed),category:"comparison")
let manifest:[String:Any]=["schema_version":1,"generator":"Map3DC371+Map3DC381","model_count":records.count,"native_coordinates":"metres +x front +y left +z up","gltf_coordinates":"metres +x front +y up -z left","directions":["top","bottom","left","right","front","back","isometric"],"models":records,"assembly":["c371_centres_m":[58.75,35.25,11.75,-11.75,-35.25,-58.75],"c381_centres_m":[58.855,35.25,11.75,-11.75,-35.25,-58.855],"rail_z_m":0,"static":true]]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("manifest.json"))
print("Exported \(records.count) units/assemblies/comparison; readback passed")
