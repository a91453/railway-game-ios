import Foundation
@testable import GamePresentation
let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)!
var rows:[[String:Any]]=[]
for case let file as URL in files where file.pathExtension=="m3dmodel" {
    let original=try Map3DModelFile(decoding:Data(contentsOf:file),named:file.lastPathComponent).model
    let model=Map3DTransparentGlass.applying(to:original)
    var panes=0,horizontal=0
    for (old,new) in zip(original.vertices,model.vertices) {
        if old.layer == Map3DVertex.trainGlass || old.layer == Map3DVertex.trainGlassLit {
            precondition(new.isTransparentGlass && old.position==new.position && old.color==new.color && old.glows==new.glows)
            precondition(new.u == (abs(old.nz)>0.8 ? 0.06 : 0.14));panes+=1;if abs(old.nz)>0.8 {horizontal+=1}
        } else {precondition(old==new,"Opaque geometry or material changed")}
    }
    precondition(panes>0 && panes%3==0)
    let t:[Float]=[1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1]
    var t2=t;t2[12]=4;t2[13]=0.2;t2[14]=1.8
    let eye=Map3DPoint(4,3,4),target=Map3DPoint(0,-2,0),look=(target-eye).normalized!
    let world=Map3DTransparentGlass.Cache(models:[model]).vertices(instances:[Map3DInstance(model:0,transform:t2,stripe:(1,1,1)),Map3DInstance(model:0,transform:t,stripe:(1,1,1))],eye:eye,toward:target)
    precondition(world.count==panes*2)
    var last:Float = .infinity
    for i in stride(from:0,to:world.count,by:3) {
        let normal=Map3DPoint(world[i].nx,world[i].ny,world[i].nz)
        precondition(normal.length.isFinite && abs(normal.length-1)<0.00001)
        let centre=(world[i].position+world[i+1].position+world[i+2].position)*(1/Float(3)),depth=(centre-eye).dot(look)
        precondition(depth<=last+0.00001,"Actual cabin glass is not globally sorted");last=depth
    }
    rows.append(["id":file.lastPathComponent,"family":file.path.contains("sunmoon") ? "sunmoon" : "maokong","glass_triangles":panes/3,"horizontal_glass_triangles":horizontal/3,"world_triangles_two_instances":world.count/3,"opaque_attributes_unchanged":true,"normals_unit_and_global_depth_sorted":true])
}
precondition(rows.count==8)
#if os(macOS)
let checkPlatform = "macOS Swift6.4 CPU / not Metal"
#else
let checkPlatform = "Linux Swift6.4 CPU / not Metal"
#endif
try JSONSerialization.data(withJSONObject:["status":"VERIFIED","platform":checkPlatform,"vertex_stride":MemoryLayout<Map3DVertex>.stride,"models":rows],options:[.sortedKeys,.prettyPrinted]).write(to:output)
print("VERIFIED 8 real near/LOD cabin models: glass/floor style, opaque byte attributes, world normals and global sort")
