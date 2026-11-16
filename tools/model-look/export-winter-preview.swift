import Foundation
import GameCore
@testable import GamePresentation

// Preview only, for the owner to choose (WINTER-LIGHTS-2): the Christmas
// livery options on named cars. Usage: export-winter.sh preview OUTPUT_DIRECTORY MODEL_NAME...
// NAME-plain, NAME-red (the whole-car red of decision 802), NAME-trim (the
// car's own livery with a berry waist line, a string of lights and a wreath),
// each also as -night (unlit faces darkened).
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
let pack=Map3DModelPack.standard
func write(_ vertices: [Map3DVertex],named name: String,night: Bool) throws {
    let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":name,"coordinateSystem":"metres"]],options:[.sortedKeys])
    var data=Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
    put16(1);put16(0);put32(UInt32(vertices.count/3));put32(UInt32(text.count));data.append(text)
    data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
    for start in stride(from:0,to:vertices.count,by:3) {
        let t=vertices[start..<start+3],glows=t.contains { $0.glows };put32(glows ? 1 : 0)
        for v in t {
            var c=v.color>>24==0xFF ? v.color : 0xFF00_0000|Map3DColor.shaded(0xFF3A_7BD5,1)&0xFFFFFF
            if night && !glows { var d: UInt32=0xFF00_0000; for s: UInt32 in [0,8,16] { d |= UInt32(Float((c>>s)&255)*0.3)<<s }; c=d }
            put32(v.x.bitPattern);put32(v.y.bitPattern);put32(v.z.bitPattern);put32(c)
        }
    }
    try data.write(to:directory.appendingPathComponent(name+(night ? "-night":"")+".m3dmodel"),options:.atomic)
}
let berry=Map3DColor.shaded(0xFF3A_1C8C,1),fir=Map3DColor.shaded(0xFF44_5A1F,1),gold=Map3DColor.shaded(0xFF3A_A9D9,1),warm=Map3DColor.shaded(0xFFB0_E7FF,1),bow=Map3DColor.shaded(0xFF3A_2AC2,1)
func trimmed(_ model: Map3DModelPack.Model,table: [UInt8],head: Bool) -> [Map3DVertex] {
    var out=model.vertices
    var area=[Float](repeating:0,count:4),red: Float=0
    for first in stride(from:0,to:out.count-2,by:3) {
        let a=out[first],b=out[first+1],c=out[first+2],size=((b.position-a.position).cross(c.position-a.position)).length/2
        area[Int(table[first]&3)]+=size
        if table[first]&3==1 { let ch=Map3DChristmasLivery.channels(a.color); if max(ch[0],ch[2])>ch[1]*1.6 && abs(ch[0]-ch[2])>0.25 { red+=size } }
    }
    let painted=area[1]+area[2]+area[3],bandNarrow=area[2]<=painted*0.3
    let waist=red>area[1]*0.5 ? fir : berry
    for at in out.indices {
        let part=table[at]&3,shade=Float(table[at]>>2)/63
        if bandNarrow { if part==2 { out[at].color=Map3DColor.shaded(waist,shade) } else if part==3 { out[at].color=Map3DColor.shaded(gold,shade) } }
        else if part==3 { out[at].color=Map3DColor.shaded(waist,shade) }
    }
    // Where the car is: x along, y sideways, z up.
    let xs=model.vertices.map(\.x),ys=model.vertices.map(\.y)
    let half=ys.map(abs).max()!,front=xs.max()!,back=xs.min()!
    let wall=model.vertices.filter { abs($0.y)>half*0.93 }.map(\.z).max()!
    var seed=model.vertices[0];seed.layer=Map3DVertex.plain;seed.u=0;seed.v=0
    func tri(_ a: Map3DPoint,_ b: Map3DPoint,_ c: Map3DPoint,_ colour: UInt32,glow: Bool) {
        let n=(b-a).cross(c-a)
        for (p,flip) in [(a,false),(b,false),(c,false),(a,true),(c,true),(b,true)] {
            var v=seed;v.x=p.x;v.y=p.y;v.z=p.z;let s: Float=flip ? -1:1;v.nx=n.x*s;v.ny=n.y*s;v.nz=n.z*s;v.color=colour;v.layer=glow ? Map3DVertex.glowing:Map3DVertex.plain;out.append(v)
        }
    }
    func bulb(_ at: Map3DPoint) {
        let r: Float=0.14
        let p=[Map3DPoint(r,0,0),Map3DPoint(-r,0,0),Map3DPoint(0,r,0),Map3DPoint(0,-r,0),Map3DPoint(0,0,r),Map3DPoint(0,0,-r)].map { at+$0 }
        for (a,b,c) in [(0,2,4),(0,4,3),(0,3,5),(0,5,2),(1,4,2),(1,3,4),(1,5,3),(1,2,5)] { tri(p[a],p[b],p[c],warm,glow:true) }
    }
    // The string of lights: along the top of each side wall.
    let inset: Float=head ? 3.0 : 0.6
    var x=back+0.6
    while x<=front-inset {
        for side: Float in [-1,1] { bulb(Map3DPoint(x,side*(half+0.06),wall-0.05)) }
        x+=0.9
    }
    // The wreath on the nose.
    if head {
        let height=wall*0.5
        let nose=model.vertices.filter { abs($0.y)<0.7 && abs($0.z-height)<0.6 }.map(\.x).max() ?? front
        let centre=Map3DPoint(nose+0.12,0,height),outer: Float=0.45,inner: Float=0.25
        for step in 0..<14 {
            let a=Float(step)/14*2 * .pi,b=Float(step+1)/14*2 * .pi
            func at(_ r: Float,_ t: Float) -> Map3DPoint { centre+Map3DPoint(0,cos(t)*r,sin(t)*r) }
            tri(at(inner,a),at(outer,a),at(outer,b),fir,glow:false);tri(at(inner,a),at(outer,b),at(inner,b),fir,glow:false)
        }
        let knot=centre+Map3DPoint(0.02,0,-0.35)
        tri(knot,knot+Map3DPoint(0,-0.26,0.16),knot+Map3DPoint(0,-0.26,-0.16),bow,glow:false)
        tri(knot,knot+Map3DPoint(0,0.26,-0.16),knot+Map3DPoint(0,0.26,0.16),bow,glow:false)
    }
    return out
}
let wanted=Set(CommandLine.arguments.dropFirst(2))
for index in pack.christmas.keys.sorted() {
    let model=pack.models[index],table=pack.christmas[index]!
    guard wanted.contains(model.name) else { continue }
    let head=model.name.contains("head") || model.name.contains("cab") || model.name.contains("single")
    for night in [false,true] {
        try write(model.vertices,named:model.name+"-plain",night:night)
        try write(Map3DChristmasLivery.recoloured(model.vertices,table:table),named:model.name+"-red",night:night)
        try write(trimmed(model,table:table,head:head),named:model.name+"-trim",night:night)
    }
}
