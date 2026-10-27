import Foundation

/// Independent early-service EMU900. Published coupling pitches; unsourced shell
/// stations and equipment dimensions are visual estimates, not engineering measurements.
public enum Map3DEMU900 {
    public enum Role: String, CaseIterable, Sendable { case ed, emToilet, emSIV, emCrew, epCompressor, epAccessible
        public var hasPantograph: Bool { self == .epCompressor || self == .epAccessible }
    }
    public struct Placement: Sendable { public let role: Role; public let x: Float; public let reversed: Bool }
    public static let bodyColor = Map3DPalette.concreteWalls[2]
    public static let roofColor = Map3DPalette.concreteWalls[0]
    public static let teal = Map3DPalette.shopAwnings[0]
    public static let navy = Map3DColor.rgb(0x262C57)
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.62)
    public static let rubber = Map3DColor.rgb(0x2B2E34)
    public static let sequence: [Role] = [.ed,.emToilet,.epCompressor,.emSIV,.emCrew,.epAccessible,.emSIV,.epCompressor,.emToilet,.ed]
    public static let placements: [Placement] = {
        var edge: Float = 205.56/2
        return sequence.indices.map { i in
            let pitch: Float = sequence[i] == .ed ? 21.58:20.30
            // Car 6 points opposite car 3; the train is not two mirrored five-car halves.
            let p = Placement(role:sequence[i],x:edge-pitch/2,reversed:i>=5)
            edge -= pitch; return p
        }
    }()
    public static func id(_ role: Role, reversed: Bool = false, far: Bool = false, light: Bool = false) -> String {
        "emu900-"+role.rawValue+(reversed ? "-reverse":"")+(far ? "-far":"")+(light ? "-light":"")
    }
    public static func model(_ role: Role, reversed: Bool = false, far: Bool = false, light: Bool = false) -> Map3DModelPack.Model {
        var b = E900Builder(role:role,far:far || light,light:light); b.build()
        let m = Map3DModelPack.Model.flat(named:id(role,reversed:reversed,far:far,light:light),from:b.k.mesh)
        guard reversed else { return m }
        return .init(name:m.name,vertices:m.vertices.map { Map3DVertex(.init(-$0.x,-$0.y,$0.z),normal:.init(-$0.nx,-$0.ny,$0.nz),color:$0.color,layer:$0.layer) },minimum:.init(-m.maximum.x,-m.maximum.y,m.minimum.z),maximum:.init(-m.minimum.x,-m.minimum.y,m.maximum.z))
    }
    public static func formation(far: Bool = false, light: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for p in placements { b.add(model(p.role,reversed:p.reversed,far:far,light:light),at:.init(p.x,0,0)) }
        return .flat(named:"emu900-formation"+(far ? "-far":"")+(light ? "-light":""),from:b.mesh)
    }
}

private struct E900Builder {
    typealias E = Map3DEMU900
    let role: E.Role
    let far: Bool
    let light: Bool
    var k = StationKitBuilder()
    var cab: Bool { role == .ed }
    var ep: Bool { role == .epCompressor || role == .epAccessible }
    var half: Float { cab ? 10.55:9.85 }
    // General closed panel/clipping methods adapted from the delivered native tooling;
    // no EMU800 shell, door coordinates, livery or equipment stations are imported.
    mutating func face(_ p: [Map3DPoint], _ inside: Map3DPoint, _ color: UInt32) {
        guard p.count>=3 else {return}
        if p.count==3 {k.face(p,inside:inside,color:color);return}
        if p.count==4 {k.face([p[0],p[1],p[2]],inside:inside,color:color);k.face([p[0],p[2],p[3]],inside:inside,color:color);return}
        let c=p.reduce(.zero,+)*(1/Float(p.count))
        for i in p.indices {k.face([c,p[i],p[(i+1)%p.count]],inside:inside,color:color)}
    }
    mutating func panel(_ p:[Map3DPoint],_ d:Map3DPoint,_ color:UInt32) {
        let q=p.map {$0+d},c=(p+q).reduce(.zero,+)*(1/Float(p.count*2))
        face(p,c,color);face(q,c,color)
        for i in p.indices {let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],c,color)}
    }
    static func rounded(_ x:Float,_ y:Float,_ w:Float,_ h:Float,_ r:Float,_ steps:Int)->[Map3DPoint] {
        var p:[Map3DPoint]=[]
        for (sx,sy,a):(Float,Float,Float) in [(1,1,0),(-1,1,Float.pi/2),(-1,-1,Float.pi),(1,-1,Float.pi*1.5)] {
            for i in 0...steps {let t=a+Float(i)*Float.pi/Float(steps*2);p.append(.init(x+sx*(w/2-r)+r*cosf(t),y+sy*(h/2-r)+r*sinf(t),0))}
        };return p
    }
    mutating func side(_ x:Float,_ y:Float,_ w:Float,_ h:Float,_ s:Float,_ color:UInt32) {
        if light {
            panel([.init(x-w/2,y-h/2,s*1.445),.init(x+w/2,y-h/2,s*1.445),.init(x+w/2,y+h/2,s*1.445),.init(x-w/2,y+h/2,s*1.445)],.init(0,0,s*0.010),color)
            return
        }
        let p=Self.rounded(x,y,w,h,min(0.11,h/4),far ? 1:2)
        panel(p.map {.init($0.x,$0.y,s*1.445)},.init(0,0,s*0.009),E.rubber)
        let inner=Self.rounded(x,y,w-0.045,h-0.045,min(0.09,h/5),far ? 1:2)
        panel(inner.map {.init($0.x,$0.y,s*1.454)},.init(0,0,s*0.009),color)
    }
    static func nose(_ u:Float,_ h:Float)->Map3DPoint {
        let width:Float = h>3.25 ? 1.445-(h-3.25)*0.60:h<1.6 ? 1.12+0.325*max(0,(h-0.60)):1.445
        let slope=max(0,h-1.35)
        return .init(10.55-0.20*u*u-0.24*slope-0.10*slope*slope,h,u*width)
    }
    mutating func patch(_ tris:[[Map3DPoint]],_ outline:[Map3DPoint],_ color:UInt32,_ depth:Float) {
        let area=outline.indices.reduce(Float(0)){a,i in let j=(i+1)%outline.count;return a+outline[i].y*outline[j].z-outline[j].y*outline[i].z}
        let sign:Float=area>0 ? 1:-1
        for tri in tris {
            var p=tri
            for i in outline.indices {
                let a=outline[i],b=outline[(i+1)%outline.count],e=b-a;var q:[Map3DPoint]=[]
                for j in p.indices {let c=p[j],d=p[(j+1)%p.count],f=sign*e.cross(c-a).x,g=sign*e.cross(d-a).x
                    if f>=0 {q.append(c)}
                    if f*g<0 {q.append(c+(d-c)*(f/(f-g)))}
                };p=q;if p.count<3 {break}
            }
            guard p.count>=3 else {continue}
            let n=(p[1]-p[0]).cross(p[2]-p[0]);guard n.dot(n)>1e-12 else {continue}
            panel(p.map {$0+Map3DPoint(depth-0.012,0,0)},.init(0.012,0,0),color)
        }
    }
    mutating func buildCab(_ body:UInt32,_ metal:UInt32,_ dark:UInt32) {
        let n=light ? 6:far ? 12:20
        let widths:[Float]=[0.94,1.20,1.23,1.22,1.20,1.15,1.05]
        var grid:[[Map3DPoint]]=[]
        func surface(_ z:Float,_ h:Float)->Map3DPoint {
            let w:Float=h>3.25 ? 1.445-(h-3.25)*0.60:h<1.6 ? 1.12+0.325*max(0,h-0.60):1.445
            return Self.nose(z/w,h)
        }
        for i in 0...n {
            let u=Float(i)*2/Float(n)-1
            let heights:[Float]=[1.37+0.25*u*u,1.82+0.15*u*u,2.18,2.60,3.10,3.34,3.58-0.13*powf(abs(u),4)]
            grid.append(heights.indices.map {surface(u*widths[$0],heights[$0])})
        }
        let inside=Map3DPoint(8.8,2.2,0)
        var tris:[[Map3DPoint]]=[]
        // The mask boundary is a shared curved perimeter of the actual shell.
        // It never changes colour by coarse column thresholds.
        for i in 0..<n {for j in 0..<6 {
            let p=grid[i][j],q=grid[i+1][j],r=grid[i+1][j+1],s=grid[i][j+1]
            for t in [[p,q,r],[p,r,s]] {face(t,inside,E.navy);tris.append(t)}
        }}
        let ring=grid.map {$0.first!}+grid.last!.dropFirst()+grid.dropLast().reversed().map {$0.last!}+grid.first!.dropFirst().dropLast().reversed()
        let rows=Array(repeating:0,count:n+1)+Array(1...6)+Array(repeating:6,count:n)+Array((1...5).reversed())
        let heights:[Float]=[1.0,1.53,1.80,2.60,3.10,3.40,3.65]
        var outer:[Map3DPoint]=[],back:[Map3DPoint]=[]
        for i in ring.indices {
            let p=ring[i],row=rows[i],h=heights[row],u=p.z/widths[row]
            let frontH:Float=row==0 ? 0.98:row==6 ? 3.65-0.10*u*u:h
            let frontZ:Float=row==0 ? u*1.40:row==6 ? u*1.14:(p.z<0 ? -1:1)*(h>3.28 ? 1.355:1.445)
            outer.append(surface(frontZ,frontH))
            let bw:Float=h<=3.28 ? 1.445:h<=3.48 ? 1.35:0.75
            back.append(.init(8.35,h,row==0 ? u*1.445:row==6 ? u*0.75:(p.z<0 ? -bw:bw)))
        }
        face(back,inside,body)
        for i in ring.indices {
            let j=(i+1)%ring.count
            let band=(rows[i]==1&&rows[j]==2)||(rows[i]==2&&rows[j]==1)
            let color=band ? E.teal:body
            for t in [[ring[i],ring[j],outer[j]],[ring[i],outer[j],outer[i]]] {face(t,inside,color);tris.append(t)}
            face([outer[i],outer[j],back[j],back[i]],inside,color)
        }
        func yz(_ p:[Map3DPoint])->[Map3DPoint] {p.map {.init(0,$0.y,$0.x)}}
        let wind:[Map3DPoint]=[.init(-0.77,2.12,0),.init(0.77,2.12,0),.init(0.93,2.22,0),.init(1.04,2.55,0),.init(1.08,3.04,0),.init(1.02,3.21,0),.init(0.85,3.28,0),.init(-0.85,3.28,0),.init(-1.02,3.21,0),.init(-1.08,3.04,0),.init(-1.04,2.55,0),.init(-0.93,2.22,0)]
        patch(tris,yz(wind),E.glass,0.020)
        if !light {patch(tris,yz(Self.rounded(0,3.40,0.72,0.18,0.04,2)),dark,0.017)}
        patch(tris,yz([.init(-0.74,1.45,0),.init(0.74,1.45,0),.init(0.68,1.55,0),.init(-0.68,1.55,0)]),Map3DPalette.tileWhite,0.018)
        for sign:Float in [-1,1] {
            for (z,h,r):(Float,Float,Float) in [(sign*0.84,3.40,0.10),(sign*1.06,2.05,0.09),(sign*0.99,1.84,0.09)] {
                let sides=light ? 6:far ? 8:12
                let circle=(0..<sides).map {i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(sides);return .init(0,h+r*sinf(t),z+r*cosf(t))}
                patch(tris,circle,Map3DPalette.tunnelLamp,0.025)
            }
            if !far {patch(tris,[.init(0,2.12,sign*0.06),.init(0,2.15,sign*0.06),.init(0,2.28,sign*0.87),.init(0,2.25,sign*0.87)],dark,0.038)}
            // Rounded cheeks surround an open, recessed coupling well.
            let cheek:[(Float,Float)]=[(0.61,1.10),(1.40,1.10),(1.39,0.83),(1.32,0.63),(1.20,0.49),(0.89,0.49),(0.71,0.59),(0.61,0.78)]
            let front=cheek.map {surface(sign*$0.0,$0.1)+Map3DPoint(-0.11,0,0)}
            let rear=cheek.map {Map3DPoint(9.75,$0.1,sign*$0.0)}
            let centre=(front+rear).reduce(.zero,+)*(1/Float(front.count*2))
            face(front,centre,body);face(rear,centre,body)
            for i in front.indices {let j=(i+1)%front.count;face([front[i],front[j],rear[j],rear[i]],centre,body)}
            if !light {
                k.beam(.init(10.30,0.70,sign*0.38),.init(10.29,0.34,sign*0.45),0.04,dark)
                k.beam(.init(10.29,0.34,sign*0.45),.init(10.43,0.30,sign*0.34),0.04,dark)
            }
        }
        k.box(9.82,0.55,0,0.16,1.25,0.57,dark)
        k.box(10.22,0.73,0,0.80,0.28,0.20,metal)
        let coupling=Self.rounded(0,0.76,0.49,0.31,0.055,1).map {Map3DPoint(10.60,$0.y,$0.x)}
        panel(coupling,.init(0.12,0,0),metal)
        if !light {panel(Self.rounded(0,0.76,0.23,0.15,0.04,1).map {.init(10.721,$0.y,$0.x)},.init(0.008,0,0),dark)}
        // Bevelled deflector, supported at the rear rather than an isolated block.
        let plow:[Map3DPoint]=[.init(10.15,0.17,-1.08),.init(10.40,0.17,0),.init(10.15,0.17,1.08),.init(10.10,0.40,0.98),.init(10.30,0.40,0),.init(10.10,0.40,-0.98)]
        // Separate convex halves keep all faces closed and consistently oriented.
        panel([plow[0],plow[1],plow[4],plow[5]],.init(-0.09,0,0),metal)
        panel([plow[1],plow[2],plow[3],plow[4]],.init(-0.09,0,0),metal)
    }
    mutating func build() {
        let body=E.bodyColor,metal=StationKitBuilder.steel,dark=E.rubber
        let start = -half, end:Float=cab ? 8.35:half
        // Body height excludes roof AC. Actual side band is part of the shell.
        let profile:[(Float,Float)]=[(1.0,-1.445),(1.53,-1.445),(1.80,-1.445),(3.28,-1.445),(3.48,-1.35),(3.62,-1.10),(3.65,-0.75),(3.65,0.75),(3.62,1.10),(3.48,1.35),(3.28,1.445),(1.80,1.445),(1.53,1.445),(1.0,1.445)]
        let a=profile.map {Map3DPoint(start,$0.0,$0.1)},b=profile.map {Map3DPoint(end,$0.0,$0.1)},inside=Map3DPoint(0,2.3,0)
        for i in profile.indices {let j=(i+1)%profile.count,h=(profile[i].0+profile[j].0)/2;face([a[i],a[j],b[j],b[i]],inside,h>1.53&&h<1.8 ? E.teal:body)}
        face(a,inside,body);face(b,inside,body)
        if cab { buildCab(body,metal,dark) }
        let doors:[Float]=cab ? [-5.95,-0.35,5.25]:[-5.65,0,5.65]
        for s:Float in [-1,1] {
            for x in doors {
                for dx:Float in (light ? [0]:[-0.68,0,0.68]) {k.box(x+dx,1.04,s*1.45,0.018,0.012,2.06,metal)}
                if !light {k.box(x,3.10,s*1.45,1.38,0.012,0.025,metal)}
                for dx:Float in [-0.34,0.34] {side(x+dx,2.60,0.47,0.89,s,E.glass)}
            }
            let windows:[Float]=cab ? [-8.30,-4.02,-2.18,1.58,3.42]:[-8.15,-3.72,-1.90,1.90,3.72,8.15]
            for (i,x) in windows.enumerated() {
                let toilet=role == .emToilet&&i==0&&s<0 || role == .epAccessible&&i==windows.count-1&&s>0
                side(x,2.50,toilet ? 0.58:1.40,toilet ? 0.46:0.82,s,toilet ? Map3DPalette.tunnelLining:E.glass)
            }
            if cab {
                side(7.40,2.58,0.35,0.84,s,E.glass)
                for dx:Float in (light ? []:[-0.30,0.30]) {k.box(7.40+dx,1.08,s*1.45,0.015,0.015,2.00,metal)}
                side(8.30,2.62,0.46,0.88,s,E.glass)
            }
            if !far {for x in [doors[0]+2.0,doors[1]+2.0] {side(x,3.16,0.72,0.12,s,dark)}}
        }
        let pitch:Float=cab ? 21.58:20.30
        for e:Float in (cab ? [-1]:[-1,1]) {
            k.box(e*half,1.12,0,0.06,1.05,1.98,dark)
            k.box(e*(half+0.09),1.12,0,0.18,1.16,2.05,dark)
            k.box(e*(pitch/2-0.12),0.75,0,0.24,0.34,0.24,metal)
        }
        // 860 mm wheel diameter and 2300 mm fixed wheelbase; centres remain estimates.
        for bx:Float in (cab ? [-6.75,6.40]:[-6.90,6.90]) {
            k.box(bx,0.91,0,3.20,1.70,0.08,dark)
            for s:Float in [-1,1] {
                k.box(bx,0.53,s*0.93,3.08,0.16,0.24,metal)
                if !far {
                    // Main bolster, secondary air spring and primary suspension.
                    k.cylinder(bx,0.65,s*0.69,radius:0.22,height:0.16,color:dark,sides:12)
                    for dx:Float in [-0.64,0.64] {
                        k.cylinder(bx+dx,0.65,s*0.93,radius:0.12,height:0.18,color:metal,sides:10)
                        for h:Float in [0.67,0.72,0.77] {k.cylinder(bx+dx,h,s*0.93,radius:0.13,height:0.018,color:dark,sides:10)}
                    }
                    for dx:Float in [-1,1] {k.beam(.init(bx+dx*1.0,0.54,s*0.93),.init(bx+dx*0.35,0.69,s*0.93),0.11,metal)}
                }
                for dx:Float in [-1.15,1.15] {
                    k.civicTube(.init(bx+dx,0.43,s*0.49),.init(bx+dx,0.43,s*0.66),radius:0.43,color:dark,sides:light ? 8:far ? 12:20)
                    if !light {
                        k.civicTube(.init(bx+dx,0.43,s*0.67),.init(bx+dx,0.43,s*1.02),radius:0.09,color:metal,sides:8)
                        k.box(bx+dx,0.35,s*0.97,0.32,0.20,0.27,metal)
                    }
                }
            }
        }
        let boxes:[Float]=role == .emSIV ? [-3.9,-1.8,0.7,3.6]:role == .emCrew ? [-3.0,0,3.1]:ep ? [-3.8,-0.4,3.0]:[-3.4,0.3,3.4]
        for (i,x) in boxes.enumerated() {
            let s:Float=ep ? -1:1
            k.box(x,0.40,s*0.60,ep&&i==1 ? 2.6:1.7,0.92,0.48,metal)
            if !far {for d:Float in [-0.5,0,0.5] {k.box(x+d,0.45,s*1.065,0.025,0.012,0.30,dark)}}
        }
        if role == .epCompressor || role == .emToilet {
            for x:Float in [-2.8,-1.8] {k.civicTube(.init(x,0.58,-0.66),.init(x,0.58,0.36),radius:0.25,color:metal,sides:light ? 6:far ? 8:12)}
        }
        // Two continuous AC housings, sitting on narrow roof support rails.
        for x:Float in (cab ? [-6.4,4.6]:[-5.0,5.0]) {
            k.box(x,3.65,0,2.75,1.36,0.07,metal)
            let profile:[(Float,Float)]=[(-0.85,3.72),(-0.66,3.99),(0.66,3.99),(0.85,3.72)]
            let a=profile.map {Map3DPoint(x-1.48,$0.1,$0.0)},b=profile.map {Map3DPoint(x+1.48,$0.1,$0.0)},c=Map3DPoint(x,3.80,0)
            face(a,c,E.roofColor);face(b,c,E.roofColor)
            for i in profile.indices {let j=(i+1)%profile.count;face([a[i],a[j],b[j],b[i]],c,E.roofColor)}
            if !far {for dx:Float in [-0.9,-0.6,-0.3,0,0.3,0.6,0.9] {k.box(x+dx,3.991,0,0.025,1.05,0.008,metal)}}
        }
        if ep {
            let px:Float=7.8
            k.box(px,3.65,0,2.6,1.2,0.08,metal)
            for dx:Float in [-0.65,0.65] {for s:Float in [-1,1] {k.cylinder(px+dx,3.73,s*0.40,radius:0.10,height:0.25,color:Map3DPalette.tileWhite,sides:8)}}
            k.box(px,3.98,0,1.55,0.95,0.08,dark)
            k.beam(.init(px-0.5,4.06,0),.init(px+0.9,4.70,0),0.07,dark)
            k.beam(.init(px+0.9,4.70,0),.init(px-0.15,5.12,0),0.06,metal)
            k.box(px-0.15,5.12,0,0.26,1.40,0.06,dark)
            k.beam(.init(px,3.99,0.4),.init(px-1.8,3.73,0.4),0.03,dark)
        }
    }
}
