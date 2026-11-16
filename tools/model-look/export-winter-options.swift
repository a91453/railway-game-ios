import Foundation
import GameCore
@testable import GamePresentation

// Preview only, for the owner to choose (WINTER-LIVERY-2, decision 806): the
// Christmas livery as decoration on a train's own livery, three ways, on
// whole formations. Usage: export-winter.sh options OUTPUT_DIRECTORY
//   A1 ribbon:    the cab cars' waist a wide berry belt with gold lines, a white and gold ribbon crossed over their front third
//   A2 snow roof: every roof warm white, a string of warm bulbs along both roof edges, a wreath on the front
//   A3:           A1's belt with A2's roof, bulbs and wreath (no ribbon)
//   mix:          A2 with A1's ribbon and bow on the cab cars: the one chosen, drawn by the game's own Map3DChristmasLivery
// Each train plain, a1, a2, a3, mix; by day and by night (unlit faces darkened,
// windows and lamps lit as decision 449 lights them; NAME-night-mask holds
// only the lamps and bulbs, for the glow shoot-livery.mjs draws round it); as a pair
// of cars (-pair) and as four cars on a track (-scene; -far the far set).
// Nothing here is read by the game; no model or hash of the pack changes.
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
let round=CommandLine.arguments.count>2 ? Int(CommandLine.arguments[2]) ?? 3 : 3
let pack=Map3DModelPack.standard

struct Tri { var a: Map3DPoint, b: Map3DPoint, c: Map3DPoint; var colour: UInt32; var lit=false
    /// Lit and a lamp (not a window): the game draws a glow round it (decision 617).
    var halo: Bool { lit && !pane }
    var pane=false }
func rgb(_ hex: UInt32) -> UInt32 { Map3DColor.rgb(hex) }
// The four colours the options may use, and the snow's.
let berry=rgb(0x8C1C3A),fir=rgb(0x1F5A44),gold=rgb(0xD9A93A),white=rgb(0xF4F1E6),bulbWarm=rgb(0xFFE7B0),bowRed=rgb(0xB5223C)

func shaded(_ colour: UInt32,_ by: Float) -> UInt32 {
    var out: UInt32=0xFF00_0000
    for s: UInt32 in [0,8,16] { out |= UInt32(min(255,Float((colour>>s)&255)*by))<<s }
    return out
}
func luminance(_ c: UInt32) -> Float { (0.2126*Float(c&255)+0.7152*Float((c>>8)&255)+0.0722*Float((c>>16)&255))/255 }

/// A car's mesh, asked where its surface is.
struct Shell {
    let tris: [Tri]
    let low: Map3DPoint, high: Map3DPoint
    var half: Float { max(abs(low.y),abs(high.y)) }
    /// The surface farthest along `axis` (0 x, 1 y, 2 z; `sign` its way) over the point (`u`,`v`) of the other two axes, in their order.
    func surface(axis: Int,sign: Float,_ u: Float,_ v: Float,below limit: Float = .infinity) -> Float? {
        var best: Float?
        func parts(_ p: Map3DPoint) -> (Float,Float,Float) { axis==0 ? (p.y,p.z,p.x) : axis==1 ? (p.x,p.z,p.y) : (p.x,p.y,p.z) }
        for t in tris {
            let (au,av,aw)=parts(t.a),(bu,bv,bw)=parts(t.b),(cu,cv,cw)=parts(t.c)
            guard u>=min(au,bu,cu),u<=max(au,bu,cu),v>=min(av,bv,cv),v<=max(av,bv,cv) else { continue }
            let d=(bv-cv)*(au-cu)+(cu-bu)*(av-cv)
            guard abs(d)>1e-9 else { continue }
            let l1=((bv-cv)*(u-cu)+(cu-bu)*(v-cv))/d,l2=((cv-av)*(u-cu)+(au-cu)*(v-cv))/d,l3=1-l1-l2
            guard l1 >= -1e-4,l2 >= -1e-4,l3 >= -1e-4 else { continue }
            let w=(l1*aw+l2*bw+l3*cw)*sign
            guard w<=limit else { continue }
            if best==nil || w>best! { best=w }
        }
        return best
    }
}

/// What a car is decorated as: its nose at +x (1), at -x (-1), or a middle car (0).
struct Decoration {
    let shell: Shell, nose: Float, redBody: Bool
    var out: [Tri]=[]
    let wall: Float, bottom: Float
    init(_ tris: [Tri],low: Map3DPoint,high: Map3DPoint,nose: Float,redBody: Bool) {
        shell=Shell(tris:tris,low:low,high:high);self.nose=nose;self.redBody=redBody
        let half=shell.half
        var top: Float=0
        for t in tris { for p in [t.a,t.b,t.c] where abs(p.y)>half*0.93 { top=max(top,p.z) } }
        wall=top;bottom=low.z+(high.z-low.z)*0.18
    }
    mutating func tri(_ a: Map3DPoint,_ b: Map3DPoint,_ c: Map3DPoint,_ colour: UInt32,lit: Bool=false) {
        out.append(Tri(a:a,b:b,c:c,colour:colour,lit:lit));out.append(Tri(a:a,b:c,c:b,colour:colour,lit:lit))
    }
    mutating func quad(_ a: Map3DPoint,_ b: Map3DPoint,_ c: Map3DPoint,_ d: Map3DPoint,_ colour: UInt32) { tri(a,b,c,colour);tri(a,c,d,colour) }
    func side(_ x: Float,_ z: Float,_ s: Float) -> Float? {
        guard let y=shell.surface(axis:1,sign:s,x,z),y>shell.half*0.45 else { return nil }
        return y
    }
    func roof(_ x: Float,_ y: Float) -> Float? { shell.surface(axis:2,sign:1,x,y,below:wall+0.5) }

    /// The heights the belt covers: a fifth of the side, under the windows where there is room.
    var belt: (low: Float,high: Float) {
        let height=(wall-bottom)*0.2
        var panes: [(z: Float,area: Float)]=[]
        for t in shell.tris where Map3DTrainLights.isGlass(t.colour) {
            let n=(t.b-t.a).cross(t.c-t.a);guard n.length>0,abs(n.y)/n.length>=0.6 else { continue }
            panes.append((min(t.a.z,t.b.z,t.c.z),n.length/2))
        }
        panes.sort { $0.z<$1.z }
        let all=panes.reduce(0) { $0+$1.area }
        var sum: Float=0,sill=bottom+(wall-bottom)*0.45
        for p in panes { sum+=p.area;if sum>=all*0.15 { sill=p.z;break } }
        let top=sill-0.05
        if top-height>=bottom-0.15 { return (top-height,top) }
        return (bottom,bottom+height)
    }

    /// A1 and A3: the wide belt on both sides, a thin gold line above and below it.
    mutating func addBelt() {
        let (low,high)=belt,colour=redBody ? fir : berry,line: Float=0.07
        for s: Float in [1,-1] {
            var last: (x: Float,yl: Float,yh: Float)?
            var x=shell.low.x+0.05
            while x<=shell.high.x-0.05 {
                if let yl=side(x,low+0.03,s),let yh=side(x,high-0.03,s) {
                    if let l=last,abs(l.yl-yl)<0.3 {
                        func p(_ x: Float,_ y: Float,_ z: Float,_ off: Float) -> Map3DPoint { Map3DPoint(x,(y+off)*s,z) }
                        quad(p(l.x,l.yl,low,0.025),p(x,yl,low,0.025),p(x,yh,high,0.025),p(l.x,l.yh,high,0.025),colour)
                        quad(p(l.x,l.yh,high-line,0.035),p(x,yh,high-line,0.035),p(x,yh,high,0.035),p(l.x,l.yh,high,0.035),gold)
                        quad(p(l.x,l.yl,low,0.035),p(x,yl,low,0.035),p(x,yl,low+line,0.035),p(l.x,l.yl,low+line,0.035),gold)
                    }
                    last=(x,yl,yh)
                } else { last=nil }
                x+=0.25
            }
        }
    }

    /// A band wrapped over the car like a parcel's ribbon: up one side, over the roof and down the other, `lean` metres along the car from one hem to the other.
    mutating func addRibbon(at centre: Float,lean: Float,width: Float) {
        let step: Float=0.2,rise=wall-bottom,across=shell.half*2,whole=rise*2+across
        var path: [Map3DPoint]=[]
        func x(_ d: Float) -> Float { centre+lean*(d/whole-0.5) }
        var z=bottom
        while z<wall-0.02 { if let y=side(x(z-bottom),z,1) { path.append(Map3DPoint(x(z-bottom),y+0.04,z)) };z+=step }
        var y=shell.half
        while y >= -shell.half { let d=rise+(shell.half-y);if let top=roof(x(d),y*0.97) { path.append(Map3DPoint(x(d),y*0.97,max(top,wall-0.4)+0.04)) };y-=step }
        z=wall-0.02
        while z>=bottom { let d=rise+across+(wall-z);if let y=side(x(d),z,-1) { path.append(Map3DPoint(x(d),-(y+0.04),z)) };z-=step }
        let edge=width*0.18
        for (p,q) in zip(path,path.dropFirst()) where (q-p).length<1.2 {
            func at(_ point: Map3DPoint,_ along: Float) -> Map3DPoint { Map3DPoint(point.x+along,point.y,point.z) }
            let h=width/2,cuts: [Float]=[-h,edge-h,h-edge,h],colours: [UInt32]=[gold,round==1 ? white : (redBody ? fir : berry),gold]
            for i in 0..<3 { quad(at(p,cuts[i]),at(p,cuts[i+1]),at(q,cuts[i+1]),at(q,cuts[i]),colours[i]) }
        }
    }

    /// A1: two ribbons crossed over the front third, and a bow where they cross.
    mutating func addRibbons(width: Float,bow: Bool) {
        guard nose != 0 else { return }
        let length=shell.high.x-shell.low.x,front=nose>0 ? shell.high.x : shell.low.x
        let centre=front-nose*length*0.24
        addRibbon(at:centre,lean:length*0.2,width:width);addRibbon(at:centre,lean:-length*0.2,width:width)
        if bow { addBow(at:centre,size:width*1.3,colour:round==2 || redBody ? gold : bowRed) }
    }

    /// A bow lying on the roof: two loops across the car, two tails along it.
    mutating func addBow(at x: Float,size r: Float,colour: UInt32) {
        guard let top=roof(x,0) else { return }
        let c=Map3DPoint(x,0,max(top,wall-0.4)+0.08)
        for s: Float in [1,-1] {
            tri(c,c+Map3DPoint(r*0.55,s*r,0.45),c+Map3DPoint(-r*0.55,s*r,0.45),colour)
            tri(c,c+Map3DPoint(s*r*0.9,r*0.3,0.03),c+Map3DPoint(s*r*0.9,-r*0.3,0.03),shaded(colour,0.85))
        }
    }

    /// A2 and A3, round 2 on: a bow on the roof's front end, seen from above where the wreath on the front is not.
    mutating func addFrontBow() {
        guard nose != 0 else { return }
        var x=nose>0 ? shell.high.x : shell.low.x
        for _ in 0..<60 { if let top=roof(x,0),top>wall-0.3 { break };x-=nose*0.25 }
        addBow(at:x-nose*1.1,size:shell.half*0.62,colour:redBody ? gold : bowRed)
    }

    /// A2 and A3: a bulb every `pitch` metres along both edges of the roof, and (round 2 on) the green garland they hang on.
    mutating func addLights(pitch: Float,radius r: Float,garland: Float) {
        var x=shell.low.x+0.5
        var last: [Float: Map3DPoint]=[:]
        while x<=shell.high.x-0.5 {
            for s: Float in [1,-1] {
                guard let edge=side(x,wall-0.12,s),let top=roof(x,(edge-0.18)*s),top>wall-0.35 else { last[s]=nil;continue }
                let at=Map3DPoint(x,(edge-0.18)*s,top+r)
                if garland>0,let l=last[s] {
                    let w=Map3DPoint(0,garland/2,0),lift=Map3DPoint(0,0,0.03-r)
                    quad(l+lift-w,at+lift-w,at+lift+w,l+lift+w,fir)
                }
                last[s]=at
                let p=[Map3DPoint(r,0,0),Map3DPoint(-r,0,0),Map3DPoint(0,r,0),Map3DPoint(0,-r,0),Map3DPoint(0,0,r),Map3DPoint(0,0,-r)].map { at+$0 }
                for (a,b,c) in [(0,2,4),(0,4,3),(0,3,5),(0,5,2),(1,4,2),(1,3,4),(1,5,3),(1,2,5)] { out.append(Tri(a:p[a],b:p[b],c:p[c],colour:bulbWarm,lit:true)) }
            }
            x+=pitch
        }
    }

    /// A2 and A3: a wreath on the front, `share` of the car's width across, lying on the nose where it slopes; `lift` how far up the front (0 its foot, 1 the roof's edge).
    mutating func addWreath(share: Float,lift: Float) {
        guard nose != 0 else { return }
        let outer=shell.half*share,inner=outer*0.55,height=bottom+(wall-bottom)*lift
        func front(_ y: Float,_ z: Float) -> Float? { shell.surface(axis:0,sign:nose,y,z) }
        guard let mid=front(0,height) else { return }
        let top=front(0,height+outer) ?? mid,foot=front(0,height-outer) ?? mid
        // The plane the wreath lies in: leaning with the nose, never further than 70 degrees back.
        let lean=max(-2.7,min(2.7,(top-foot)/(2*outer)))
        func at(_ r: Float,_ t: Float,_ off: Float=0) -> Map3DPoint {
            let z=sin(t)*r
            return Map3DPoint((max(mid,(top+foot)/2)+lean*z+0.08+off)*nose,cos(t)*r,height+z)
        }
        let steps=16
        for i in 0..<steps {
            let a=Float(i)/Float(steps)*2 * .pi,b=Float(i+1)/Float(steps)*2 * .pi
            quad(at(inner,a),at(outer,a),at(outer,b),at(inner,b),i%2==0 ? fir : shaded(fir,1.25))
        }
        let knot=at(outer*0.82,-.pi/2,0.03),w=outer*0.55,h=outer*0.4
        tri(knot,knot+Map3DPoint(0,-w,h*0.6),knot+Map3DPoint(0,-w,-h),bowRed)
        tri(knot,knot+Map3DPoint(0,w,-h),knot+Map3DPoint(0,w,h*0.6),bowRed)
        for t: Float in [0.5,1.4,2.3,3.4] { let c=at((inner+outer)/2,t,0.03),d=outer*0.13;tri(c+Map3DPoint(0,-d,-d),c+Map3DPoint(0,d,-d),c+Map3DPoint(0,0,d),gold) }
    }
}

/// A2 and A3: the faces of the roof that look up, warm white.
func snowed(_ tris: [Tri],wall: Float) -> [Tri] {
    tris.map { t in
        guard !t.lit,!Map3DTrainLights.isGlass(t.colour) else { return t }
        let n=(t.b-t.a).cross(t.c-t.a),z=(t.a.z+t.b.z+t.c.z)/3
        guard n.length>0,n.z/n.length>=0.5,z>=wall-0.3,z<=wall+0.8 else { return t }
        let ch=Map3DChristmasLivery.channels(t.colour),most=max(ch[0],ch[1],ch[2],1)
        if round>1,(most-min(ch[0],ch[1],ch[2]))/most>0.5 { return t }
        var out=t;out.colour=shaded(white,min(1,max(0.86,0.8+0.25*luminance(t.colour))));return out
    }
}

enum Variant: String, CaseIterable { case plain,a1,a2,a3,mix }

/// One car of the pack as the option draws it, in its own space.
func car(_ index: Int,_ variant: Variant,nose: Float,night: Bool,line: UInt32) -> [Tri] {
    let model=pack.models[index]
    var tris: [Tri]=[]
    func take(_ vertices: [Map3DVertex],lit: Bool?=nil,colour: UInt32?=nil) {
        for first in stride(from:0,to:vertices.count-2,by:3) {
            let v=vertices[first]
            let own=v.color>>24==0xFF ? v.color : line
            tris.append(Tri(a:v.position,b:vertices[first+1].position,c:vertices[first+2].position,colour:colour ?? own,lit:lit ?? (night && v.glows),pane:colour != nil || Map3DTrainLights.isGlass(own)))
        }
    }
    take(model.vertices)
    // A car whose body is red already wears fir green.
    var red: Float=0,body: Float=0
    for first in stride(from:0,to:model.vertices.count-2,by:3) where abs(model.vertices[first].ny)>=0.6 {
        let a=model.vertices[first],size=((model.vertices[first+1].position-a.position).cross(model.vertices[first+2].position-a.position)).length/2
        guard a.color>>24==0xFF,!Map3DTrainLights.isGlass(a.color) else { continue }
        let ch=Map3DChristmasLivery.channels(a.color);body+=size
        if ch[0]>max(ch[1],ch[2])*1.6 { red+=size }
    }
    var decoration=Decoration(tris,low:model.minimum,high:model.maximum,nose:nose,redBody:red>body*0.5)
    if variant != .plain && variant != .a1 { tris=snowed(tris,wall:decoration.wall) }
    switch variant {
    case .plain: break
    case .a1:
        if nose != 0 { decoration.addBelt() }
        decoration.addRibbons(width:round==1 ? 0.6 : 1.1,bow:round>1)
    case .a2:
        decoration.addLights(pitch:round==1 ? 0.9 : 0.75,radius:round==1 ? 0.12 : round==2 ? 0.16 : 0.18,garland:round==1 ? 0 : round==2 ? 0.22 : 0.36)
        decoration.addWreath(share:round==1 ? 0.38 : 0.4,lift:round==1 ? 0.5 : 0.62)
        if round>1 { decoration.addFrontBow() }
    case .a3:
        if nose != 0 { decoration.addBelt() }
        decoration.addLights(pitch:round==1 ? 0.9 : 0.75,radius:round==1 ? 0.12 : round==2 ? 0.16 : 0.18,garland:round==1 ? 0 : round==2 ? 0.22 : 0.36)
        decoration.addWreath(share:round==1 ? 0.38 : 0.4,lift:round==1 ? 0.5 : 0.62)
        if round>1 { decoration.addFrontBow() }
    case .mix:
        // The one chosen (decision 806): the game's own, Map3DChristmasLivery, not this tool's.
        if let wear=pack.christmas[index] {
            tris=[]
            take(Map3DChristmasLivery.dressed(model.vertices,minimum:model.minimum,maximum:model.maximum,wear:wear))
        }
    }
    tris+=decoration.out
    if night,let lights=pack.lights[index] {
        if let windows=lights.windows { take(pack.models[windows].vertices,lit:true,colour:Map3DTrainLights.saloon) }
        if nose>0 { take(lights.front.head,lit:true) } else if nose<0 { take(lights.back.tail,lit:true) }
    }
    return tris
}

struct Placed { let model: Int; let front: Float; let turned: Bool; let nose: Float; let stretch: Float }
/// The cars of a `count`-car train of `code`, its front at x 0, running towards +x.
func formation(_ code: String,_ count: Int,far: Bool) -> [Placed] {
    var cars: [(model: Int,gap: Float,own: Bool)]=[]
    if let laid=pack.layout(forType:code,count:count) { cars=laid.map { ($0.model,$0.gap,true) } }
    else { cars=(0..<count).compactMap { pack.modelIndex(forType:code,carIndex:$0,count:count) }.map { ($0,0,false) } }
    var out: [Placed]=[],cursor: Float=0
    for (at,c) in cars.enumerated() {
        let last=at==cars.count-1,first=at==0
        let turned=last && !first && pack.models[c.model].name==pack.models[cars[0].model].name
        let name=pack.models[c.model].name
        let nose: Float=first ? 1 : last ? (turned ? 1 : (name.hasSuffix("tail") ? -1 : 0)) : 0
        let model=far ? pack.farModel(of:c.model,forType:code,count:count) ?? c.model : c.model
        let length=pack.models[model].length,pitch: Float=c.own ? length : 20
        out.append(Placed(model:model,front:cursor,turned:turned,nose:nose,stretch:c.own ? 1 : pitch/length))
        cursor-=pitch+c.gap
    }
    return out
}
func train(_ cars: [Placed],_ variant: Variant,night: Bool,line: UInt32) -> [Tri] {
    var out: [Tri]=[]
    for placed in cars {
        let model=pack.models[placed.model]
        let turn: Float=placed.turned ? -1 : 1
        // Its front end (after turning) at `front`.
        let lead=placed.turned ? -model.minimum.x : model.maximum.x
        func move(_ p: Map3DPoint) -> Map3DPoint { Map3DPoint((p.x*turn-lead)*placed.stretch+placed.front,p.y*turn,p.z) }
        out+=car(placed.model,variant,nose:placed.nose,night:night,line:line).map { Tri(a:move($0.a),b:move($0.b),c:move($0.c),colour:$0.colour,lit:$0.lit,pane:$0.pane) }
    }
    return out
}

/// The ground a train stands on in the game-size pictures: two tracks, a road, three plain blocks (the colours tools/model-look/shoot.mjs gives the map).
func scenery() -> [Tri] {
    var out: [Tri]=[]
    func box(_ x0: Float,_ x1: Float,_ y0: Float,_ y1: Float,_ z0: Float,_ z1: Float,_ side: UInt32,_ top: UInt32) {
        let p={ (x: Float,y: Float,z: Float) in Map3DPoint(x,y,z) }
        func quad(_ a: Map3DPoint,_ b: Map3DPoint,_ c: Map3DPoint,_ d: Map3DPoint,_ colour: UInt32) { out.append(Tri(a:a,b:b,c:c,colour:colour));out.append(Tri(a:a,b:c,c:d,colour:colour)) }
        quad(p(x0,y0,z1),p(x1,y0,z1),p(x1,y1,z1),p(x0,y1,z1),top)
        quad(p(x1,y0,z0),p(x1,y1,z0),p(x1,y1,z1),p(x1,y0,z1),side);quad(p(x0,y1,z0),p(x0,y0,z0),p(x0,y0,z1),p(x0,y1,z1),side)
        quad(p(x1,y1,z0),p(x0,y1,z0),p(x0,y1,z1),p(x1,y1,z1),side);quad(p(x0,y0,z0),p(x1,y0,z0),p(x1,y0,z1),p(x0,y0,z1),side)
    }
    let ground=rgb(0xE4E3DF),road=rgb(0xA09FAA),kerb=rgb(0xF7F7F4),wall=rgb(0xA3A7B0),roofs=rgb(0xBABDC8),ballast=rgb(0x7E786D),rail=rgb(0x6E7379),sleeper=rgb(0x5E574E),green=rgb(0x8FB58A)
    box(-400,300,-300,300,-1.2,-0.62,ground,ground)
    for track: Float in [0,-4.4] {
        box(-400,300,track-1.9,track+1.9,-0.62,-0.34,ballast,ballast)
        var x: Float = -160
        while x<120 { box(x,x+0.26,track-1.15,track+1.15,-0.34,-0.2,sleeper,sleeper);x+=0.65 }
        for y: Float in [-0.57,0.5] { box(-400,300,track+y,track+y+0.07,-0.2,0,rail,rail) }
    }
    box(-400,300,9,10.2,-0.62,-0.5,kerb,kerb);box(-400,300,10.2,19,-0.62,-0.58,road,road);box(-400,300,19,20.2,-0.62,-0.5,kerb,kerb)
    box(-52,-34,24,42,-0.62,13,wall,roofs);box(-18,2,-30,-14,-0.62,9.5,wall,roofs);box(-66,-44,-34,-13,-0.62,17,wall,roofs)
    box(8,40,-26,-12,-0.62,-0.55,green,green)
    return out
}

func write(_ tris: [Tri],named name: String,night: Bool) throws {
    func file(_ suffix: String,_ colour: (Tri) -> UInt32) throws {
        let text=try JSONSerialization.data(withJSONObject:["extras":["assetId":name+suffix,"coordinateSystem":"metres; x front, y left, z up"]],options:[.sortedKeys])
        var data=Data("M3DM".utf8)
        func put16(_ n: UInt16) { data.append(UInt8(n&255));data.append(UInt8(n>>8)) }
        func put32(_ n: UInt32) { for shift: UInt32 in [0,8,16,24] { data.append(UInt8((n>>shift)&255)) } }
        put16(1);put16(0);put32(UInt32(tris.count));put32(UInt32(text.count));data.append(text)
        data.append(contentsOf:[UInt8](repeating:0,count:(4-text.count%4)%4))
        for t in tris {
            put32(t.lit ? 1 : 0);let c=colour(t)
            for p in [t.a,t.b,t.c] { put32(p.x.bitPattern);put32(p.y.bitPattern);put32(p.z.bitPattern);put32(c) }
        }
        try data.write(to:directory.appendingPathComponent(name+suffix+".m3dmodel"),options:.atomic)
    }
    if night {
        // Night: what is not lit under a blue dusk; and the lit faces alone, for their glow.
        try file("-night") { t in
            if t.lit { return t.colour }
            let c=t.colour
            return 0xFF00_0000|UInt32(Float(c&255)*0.25)|UInt32(Float((c>>8)&255)*0.28)<<8|UInt32(Float((c>>16)&255)*0.38)<<16
        }
        try file("-night-mask") { $0.halo ? $0.colour : 0xFF00_0000 }
    } else { try file("") { $0.colour } }
}

// The nine trains of the first sheet (WINTER-LIGHTS-2), each with a line colour of its own.
let trains: [(id: String,label: String,code: String,line: UInt32)]=[
    ("hsr700t","高鐵 700T","highSpeed",rgb(0xE8731A)),("emu500","EMU500","emu500",rgb(0x2E6DB4)),("emu3000","EMU3000","emu3000",rgb(0x1E8A5A)),
    ("puyuma","普悠瑪","puyuma",rgb(0xC8382E)),("wenhu370","文湖線 370","wenhu370",rgb(0xB57A25)),("danhai","淡海輕軌","danhaiLRT",rgb(0x2AA7C9)),
    ("mtrurban","港鐵市區線","mtrUrbanLine",rgb(0xE2231A)),("pushpull","推拉式客車","pushPull",rgb(0xE8731A)),("alishan","阿里山客車","ALISHAN",rgb(0x8A5A2B))]
let ground=scenery()
var listed: [[String: Any]]=[]
for t in trains {
    let near=formation(t.code,4,far:false),far=formation(t.code,4,far:true)
    guard !near.isEmpty else { print("no cars for \(t.code)");continue }
    let names=near.map { pack.models[$0.model].name },farNames=far.map { pack.models[$0.model].name }
    print(t.id,names.joined(separator:" "),"| far:",farNames==names ? "(none)" : farNames.joined(separator:" "))
    var added: [String: Int]=[:]
    for variant in Variant.allCases {
        for night in [false,true] {
            let whole=train(near,variant,night:night,line:t.line)
            try write(train(Array(near.prefix(2)),variant,night:night,line:t.line),named:"\(t.id)-\(variant.rawValue)-pair",night:night)
            try write(whole+ground,named:"\(t.id)-\(variant.rawValue)-scene",night:night)
            try write(train(far,variant,night:night,line:t.line)+ground,named:"\(t.id)-\(variant.rawValue)-far",night:night)
            if !night { added[variant.rawValue]=whole.count }
        }
    }
    let plain=added["plain"] ?? 0
    print("  mix \((added["mix"] ?? plain)-plain)")
    // Head car and second car: where the game-size pictures look.
    listed.append(["id":t.id,"label":t.label,"headLength":pack.models[near[0].model].length,
                   "triangles":["plain":plain,"a1":(added["a1"] ?? plain)-plain,"a2":(added["a2"] ?? plain)-plain,"a3":(added["a3"] ?? plain)-plain,"mix":(added["mix"] ?? plain)-plain]])
    print("  added triangles (4 cars, both faces counted): a1 \((added["a1"] ?? plain)-plain)  a2 \((added["a2"] ?? plain)-plain)  a3 \((added["a3"] ?? plain)-plain)")
}
try JSONSerialization.data(withJSONObject:["round":round,"trains":listed,"variants":Variant.allCases.map(\.rawValue)],options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("options.json"))
