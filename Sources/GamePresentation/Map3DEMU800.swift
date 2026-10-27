import Foundation

/// Independent EMU800 blue-face / yellow-smile miniature. Native metres, tread Z=0.
/// Body and wheel dimensions: Nippon Sharyo. Equipment stations are visual estimates.
/// Decision 432: the operating `emu800` key (which also represents the EMU900) draws these units.
public enum Map3DEMU800 {
    public enum Role: String, CaseIterable, Sendable { case ed, ema, ep, emb }
    public struct Placement: Sendable {
        public let role: Role
        public let x: Float
        public let reversed: Bool
    }
    public static let bodyColor = Map3DPalette.concreteWalls[0]
    public static let navy = Map3DColor.rgb(0x262C57)
    public static let yellow = Map3DColor.rgb(0xFFC86B)
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.42)
    public static let rubber = Map3DColor.rgb(0x2B2E34)
    public static let sequence: [Role] = [.ed,.ema,.ep,.emb,.emb,.ep,.ema,.ed]
    public static let placements: [Placement] = {
        let pitches: [Float] = sequence.map { $0 == .ed ? 21.6 : 20.3 }
        var end = pitches.reduce(0,+)/2
        return sequence.indices.map { i in
            let p = Placement(role:sequence[i],x:end-pitches[i]/2,reversed:i>=4)
            end -= pitches[i]; return p
        }
    }()
    /// Decision 432: `light`, a lighter version still than `far`, for the
    /// operating set drawn from 500 m out: the same box, paint and lit
    /// lamps, without the small parts nobody sees from there.
    public static func id(_ role: Role, reversed: Bool = false, far: Bool = false, light: Bool = false) -> String {
        "emu800-"+role.rawValue+(reversed ? "-reverse":"")+(far ? "-far":"")+(light ? "-light":"")
    }
    public static func model(_ role: Role, reversed: Bool = false, far: Bool = false, light: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder(); b.e8Car(role,far:far,light:light)
        let m = Map3DModelPack.Model.flat(named:id(role,reversed:reversed,far:far,light:light),from:b.mesh)
        guard reversed else { return m }
        return .init(name:m.name,vertices:m.vertices.map {
            Map3DVertex(Map3DPoint(-$0.x,-$0.y,$0.z),normal:Map3DPoint(-$0.nx,-$0.ny,$0.nz),color:$0.color,layer:$0.layer)
        },minimum:Map3DPoint(-m.maximum.x,-m.maximum.y,m.minimum.z),maximum:Map3DPoint(-m.minimum.x,-m.minimum.y,m.maximum.z))
    }
    public static func formation(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for p in placements { b.add(model(p.role,reversed:p.reversed,far:far),at:Map3DPoint(p.x,0,0)) }
        return .flat(named:"emu800-formation"+(far ? "-far":""),from:b.mesh)
    }
}

private extension StationKitBuilder {
    typealias E8 = Map3DEMU800
    mutating func e8Face(_ points:[Map3DPoint],inside:Map3DPoint,color:UInt32) {
        guard points.count>=3 else {return}
        if points.count==3 {face(points,inside:inside,color:color);return}
        if points.count==4 {
            face([points[0],points[1],points[2]],inside:inside,color:color)
            face([points[0],points[2],points[3]],inside:inside,color:color);return
        }
        let c=points.reduce(.zero,+)*(1/Float(points.count))
        for i in points.indices {face([c,points[i],points[(i+1)%points.count]],inside:inside,color:color)}
    }
    // Closed convex panel; offsets follow its support plane rather than an unattached decal.
    mutating func e8Panel(_ p: [Map3DPoint], _ offset: Map3DPoint, _ color: UInt32) {
        let q=p.map {$0+offset},inside=(p+q).reduce(.zero,+)*(1/Float(p.count*2))
        e8Face(p,inside:inside,color:color);e8Face(q,inside:inside,color:color)
        for i in p.indices {let j=(i+1)%p.count;e8Face([p[i],p[j],q[j],q[i]],inside:inside,color:color)}
    }
    static func e8Round(_ x:Float,_ y:Float,_ w:Float,_ h:Float,_ r:Float,_ n:Int)->[Map3DPoint] {
        var out:[Map3DPoint]=[]
        for (sx,sy,a):(Float,Float,Float) in [(1,1,0),(-1,1,Float.pi/2),(-1,-1,Float.pi),(1,-1,Float.pi*1.5)] {
            for j in 0...n {let t=a+Float(j)*Float.pi/(2*Float(n));out.append(Map3DPoint(x+sx*(w/2-r)+r*cosf(t),y+sy*(h/2-r)+r*sinf(t),0))}
        }
        return out
    }
    mutating func e8Side(_ x:Float,_ h:Float,_ w:Float,_ height:Float,_ side:Float,_ far:Bool,_ color:UInt32, rim:Bool = true, light:Bool = false) {
        if rim && !light {e8Side(x,h,w+0.055,height+0.055,side,far,E8.rubber,rim:false)}
        let depth:Float = light ? 1.452:rim ? 1.464:1.450
        // Decision 432: `light`, a plain pane on the wall, no rubber rim.
        let outline = light ? [Map3DPoint(x-w/2,h-height/2,0),Map3DPoint(x+w/2,h-height/2,0),Map3DPoint(x+w/2,h+height/2,0),Map3DPoint(x-w/2,h+height/2,0)]
            : Self.e8Round(x,h,w,height,min(0.13,height/4),far ? 1:3)
        e8Panel(outline.map {Map3DPoint($0.x,$0.y,side*depth)},Map3DPoint(0,0,side*0.010),color)
    }
    // Forward face: a broad curved disk, independently controlled in height and width.
    // Coordinates are builder x/front,y/up,z/right; no EMU700/900 shell is used.
    static func e8Front(_ u:Float,_ h:Float)->Map3DPoint {
        let width:Float
        if h<1.45 {width=1.08+0.365*powf(max(0,(h-0.25)/1.20),0.45)}
        else if h>3.30 {width=1.445-(h-3.30)/0.40*0.24}
        else {width=1.445}
        let t=max(0,(h-0.8)/2.9)
        let x:Float=10.625-1.72*t*t-0.32*u*u-0.15*max(0,(0.8-h)/0.35)
        return Map3DPoint(x,h,u*width)
    }
    mutating func e8FrontPatch(_ triangles:[[Map3DPoint]],_ outline:[Map3DPoint],_ color:UInt32,_ depth:Float) {
        // Convex clipping onto the FINAL front triangles. Each clipped prism is closed.
        let area=outline.indices.reduce(Float(0)){a,i in let j=(i+1)%outline.count;return a+outline[i].y*outline[j].z-outline[j].y*outline[i].z}
        let sign:Float=area>=0 ? 1:-1
        for tri in triangles {
            var p=tri
            for i in outline.indices {
                let a=outline[i],b=outline[(i+1)%outline.count],edge=b-a
                var q:[Map3DPoint]=[]
                for j in p.indices {
                    let c=p[j],d=p[(j+1)%p.count],f=sign*edge.cross(c-a).x,g=sign*edge.cross(d-a).x
                    if f>=0 {q.append(c)}
                    if f*g<0 {q.append(c+(d-c)*(f/(f-g)))}
                }
                p=q;if p.count<3 {break}
            }
            guard p.count>=3 else {continue}
            // Snap shared clipped positions; discard zero area edge fragments.
            let area=(p[1]-p[0]).cross(p[2]-p[0]);guard area.dot(area)>1e-13 else {continue}
            e8Panel(p.map {$0+Map3DPoint(depth-0.025,0,0)},Map3DPoint(0.025,0,0),color)
        }
    }
    mutating func e8Car(_ role:E8.Role,far farDetail:Bool,light:Bool) {
        let far=farDetail||light
        let cab=role == .ed, rear:Float=cab ? -10.625:-9.8,front:Float=cab ? 7.65:9.8
        let body=E8.bodyColor,steel=Self.steel,dark=E8.rubber,glass=E8.glass
        let levels:[Float]=[0.95,1.42,1.49,1.56,3.27,3.32,3.40,3.55,3.65]
        // Flat sides allow small fitted door/window solids to stay on their support surface.
        func half(_ h:Float)->Float {h<=3.32 ? 1.445:h<=3.40 ? 1.40:h<=3.55 ? 1.26:0.95}
        var section:[Map3DPoint]=levels.map {Map3DPoint(0,$0,half($0))}
        section += levels.reversed().map {Map3DPoint(0,$0,-half($0))}
        let inside=Map3DPoint((rear+front)/2,2.2,0)
        let a=section.map {Map3DPoint(rear,$0.y,$0.z)},b=section.map {Map3DPoint(front,$0.y,$0.z)}
        for i in section.indices {
            let j=(i+1)%section.count
            let h=(section[i].y+section[j].y)/2
            let col = h>1.42&&h<1.49 ? E8.navy:h>1.49&&h<1.56 || h>3.27&&h<3.32 ? E8.yellow:body
            e8Face([a[i],a[j],b[j],b[i]],inside:inside,color:col)
        }
        e8Face(a,inside:inside,color:body)
        if !cab {e8Face(b,inside:inside,color:body)}
        var frontTris:[[Map3DPoint]]=[]
        if cab {
            let n=light ? 6:far ? 12:24
            // Paint boundaries are rows of the actual shell, not overlapping coloured boards.
            var grid:[[Map3DPoint]]=[]
            for k in 0...n {
                let u=Float(k)*2/Float(n)-1
                let yellow:Float=1.38+0.84*u*u,blue:Float=1.65+0.74*u*u
                let hs:[Float]=[0.25+0.22*u*u,0.78,1.02,yellow,blue,2.48+0.18*u*u,2.94,3.25,3.48,3.70-0.10*u*u]
                grid.append(hs.map {Self.e8Front(u,$0)})
            }
            let centre=Map3DPoint(8.0,2.0,0)
            for k in 0..<n {for j in 0..<grid[k].count-1 {
                let p=grid[k][j],q=grid[k+1][j],r=grid[k+1][j+1],s=grid[k][j+1]
                let col=j==3 ? E8.yellow:j>=4 ? E8.navy:body
                for t in [[p,q,r],[p,r,s]] {e8Face(t,inside:centre,color:col);frontTris.append(t)}
            }}
            // Side, roof and lower return from the straight body to the curved face perimeter.
            let perimeter=grid.map {$0.first!}+grid.last!.dropFirst()+grid.dropLast().reversed().map {$0.last!}+grid.first!.dropFirst().dropLast().reversed()
            let ring=Array(perimeter),back=ring.map {p in Map3DPoint(front,max(0.95,p.y),p.z)}
            // This nose is a closed separate volume; its rear lies inside the straight body.
            e8Face(back,inside:centre,color:body)
            for i in ring.indices {
                let j=(i+1)%ring.count,p=ring[i],q=ring[j],a=back[i],b=back[j]
                let c=p+(a-p)*0.11,d=q+(b-q)*0.11
                let stripe=abs(p.z)>1.30 && abs(q.z)>1.30 && min(p.y,q.y)>1.9
                e8Face([p,q,d,c],inside:centre,color:stripe ? E8.yellow:body)
                e8Face([c,d,b,a],inside:centre,color:body)
            }
            // Close the straight body's front separately; contact is internal, never a visible patch.
            e8Face(b,inside:inside,color:body)
            func yz(_ pts:[Map3DPoint])->[Map3DPoint] {pts.map {Map3DPoint(0,$0.y,$0.x)}}
            let wind:[Map3DPoint]=[.init(-1.13,2.98,0),.init(-1.02,2.27,0),.init(-0.87,2.20,0),.init(0.87,2.20,0),.init(1.02,2.27,0),.init(1.13,2.98,0)]
            e8FrontPatch(frontTris,yz(wind),dark,0.018)
            e8FrontPatch(frontTris,yz(wind.map {Map3DPoint($0.x*0.94,2.60+($0.y-2.60)*0.88,0)}),glass,0.031)
            if !light {e8FrontPatch(frontTris,yz(Self.e8Round(0,3.31,0.58,0.23,0.075,far ? 2:3)),dark,0.020)}
            for s:Float in [-1,1] {
                e8FrontPatch(frontTris,yz(Self.e8Round(s*0.86,3.31,0.40,0.30,0.12,far ? 2:4)),dark,0.022)
                e8FrontPatch(frontTris,yz(Self.e8Round(s*0.86,3.31,0.27,0.22,0.10,far ? 2:4)),Map3DPalette.tunnelLamp,0.034)
                for z:Float in (light ? []:[0.34,0.79]) {
                    let c=s*z,h:Float=z>0.5 ? 1.99:1.91
                    let circle=(0..<(far ? 10:16)).map {i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(far ? 10:16);return Map3DPoint(0,h+0.175*sinf(t),c+0.175*cosf(t))}
                    e8FrontPatch(frontTris,circle,dark,0.019)
                    e8FrontPatch(frontTris,circle.map {Map3DPoint(0,h+($0.y-h)*0.73,c+($0.z-c)*0.73)},Map3DPalette.railTop,0.032)
                }
                if !far {for h:Float in [0.81,0.88,0.95] {e8FrontPatch(frontTris,yz(Self.e8Round(s*0.63,h,0.28,0.025,0.01,1)),dark,0.013)}}
            }
            if !far {for side:Float in [-1,1] {
                let w:[Map3DPoint]=[.init(0,2.25,side*0.10),.init(0,2.27,side*0.12),.init(0,2.62,side*0.80),.init(0,2.60,side*0.82)]
                e8FrontPatch(frontTris,w,dark,0.046)
            }}
            if !light {e8FrontPatch(frontTris,yz(Self.e8Round(0,1.01,0.016,0.90,0.006,1)),steel,0.012)}
        }
        // Exactly three double passenger doors per side, six main window bays on motor cars.
        let doors:[Float]=cab ? [-6.30,-0.30,5.70]:[-5.90,0.10,6.10]
        for side:Float in [-1,1] {
            for x in doors {
                // Thin jambs and seam, the body itself supplies the door leaves.
                for dx:Float in [-0.69,0,0.69] {box(x+dx,1.02,side*1.453,0.018,0.014,2.12,steel)}
                box(x,3.12,side*1.453,1.39,0.014,0.022,steel)
                for dx:Float in [-0.34,0.34] {e8Side(x+dx,2.56,0.47,0.95,side,far,glass,light:light)}
            }
            let wins:[Float]=cab ? [-8.45,-4.25,-2.25,1.75,3.75]:[-8.30,-3.88,-1.88,2.12,4.12,8.40]
            for (i,x) in wins.enumerated() {
                let toilet=(role == .ep && i==0 && side<0)||(cab && i==0 && side>0)
                e8Side(x,2.48,toilet ? 0.52:1.51,toilet ? 0.52:0.89,side,far,toilet ? Map3DPalette.tunnelLining:glass,light:light)
                if !far && !toilet && (i%2==0) {box(x,2.65,side*1.480,1.40,0.012,0.025,steel)}
            }
            if cab {
                e8Side(7.13,2.60,0.30,0.82,side,far,glass,light:light)
                if !light {for dx:Float in [-0.30,0.30] {box(7.13+dx,1.10,side*1.45,0.018,0.014,2.05,steel)}}
                // Cab side glass stays in the parallel portion; angled front edge follows the front profile.
                e8Panel([Map3DPoint(7.52,2.20,side*1.451),Map3DPoint(7.52,3.08,side*1.451),Map3DPoint(8.53,2.92,side*1.451),Map3DPoint(9.28,2.20,side*1.451)],Map3DPoint(0,0,side*0.012),glass)
            }
            if !light {for x in [doors[0]+1.2,doors[1]+1.2] {box(x,3.12,side*1.45,0.48,0.018,0.13,dark)}}
        }
        // End gangways and couplers. Cab-front coupler remains under its normal closed cover.
        let pitch:Float=cab ? 21.6:20.3
        for end:Float in (cab ? [-1]:[-1,1]) {
            let edge=end*(cab ? 10.625:9.8)
            box(edge,1.10,0,0.08,1.12,2.02,dark)
            if !light {for z:Float in [-0.59,0.59] {box(edge+end*0.12,1.12,z,0.28,0.10,2.00,dark)}
            box(edge+end*0.12,3.12,0,0.28,1.28,0.10,dark)}
            box(end*(pitch/2-0.14),0.75,0,0.28,0.34,0.24,steel)
        }
        // ND-741 wheelbase is 2.30 m; bogie centres are proportion estimates.
        for centre:Float in (cab ? [-6.75,6.10]:[-6.90,6.90]) {
            box(centre,0.92,0,3.25,1.80,0.10,dark)
            for side:Float in [-1,1] {
                box(centre,0.56,side*0.95,3.25,0.16,0.22,steel)
                for dx:Float in [-1.15,1.15] {
                    civicTube(Map3DPoint(centre+dx,0.43,side*0.49),Map3DPoint(centre+dx,0.43,side*0.66),radius:0.43,color:dark,sides:light ? 8:far ? 12:20)
                    if !light {civicTube(Map3DPoint(centre+dx,0.43,side*0.67),Map3DPoint(centre+dx,0.43,side*1.04),radius:0.085,color:steel,sides:8)
                    box(centre+dx,0.36,side*0.97,0.35,0.23,0.30,steel)}
                    if !far {box(centre+dx,0.72,side*0.97,0.48,0.22,0.09,dark)}
                }
            }
        }
        // Distinct equipment roles; unseen cable paths are simplified, never mirrored wholesale.
        for (i,x) in [Float(-3.6),-0.8,2.6].enumerated() {
            let side:Float = role == .ep ? -1:1
            box(x,0.42,side*0.63,role == .ep && i==1 ? 2.5:1.6,0.84,0.47,steel)
            if !far {for d:Float in [-0.4,0,0.4] {box(x+d,0.47,side*1.06,0.035,0.012,0.32,dark)}}
        }
        if role == .ed && !light {for x:Float in [-3.6,-2.7] {civicTube(Map3DPoint(x,0.63,-0.65),Map3DPoint(x,0.63,0.45),radius:0.29,color:steel,sides:far ? 8:12)}}
        if role == .emb {box(9.83,2.70,0.9,0.025,0.14,0.18,Map3DPalette.tunnelLining)}
        // AC housings and supports. EP keeps its own HV bay and a single-arm pantograph.
        let ac:[Float]=role == .ep ? [-4.2,6.0]:cab ? [-6.6,5.0]:[-5.0,5.0]
        for x in ac {
            box(x,3.65,0,3.70,1.52,0.10,steel)
            let bottom:[(Float,Float)]=[(-0.94,3.75),(-0.76,3.94),(0.76,3.94),(0.94,3.75)]
            let rings=[x-1.98,x+1.98].map {xx in bottom.map {Map3DPoint(xx,$0.1,$0.0)}}
            let c=Map3DPoint(x,3.82,0)
            for r in rings {e8Face(r,inside:c,color:body)}
            for i in bottom.indices {let j=(i+1)%bottom.count;e8Face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],inside:c,color:body)}
            box(x,3.94,0,2.90,1.20,0.009,steel)
            if !far {for dx:Float in [-1.2,-0.9,-0.6,-0.3,0,0.3,0.6,0.9,1.2] {box(x+dx,3.95,0,0.028,1.18,0.008,body)}}
        }
        if role == .ep {
            box(-8.1,3.65,0,2.35,1.24,0.08,steel)
            if !light {for x:Float in [-8.8,-7.4] {for z:Float in [-0.43,0.43] {cylinder(x,3.73,z,radius:0.11,height:0.27,color:Map3DPalette.tileWhite,sides:8)}}}
            box(-8.1,4.00,0,1.65,0.95,0.10,dark)
            beam(Map3DPoint(-8.5,4.10,0),Map3DPoint(-7.0,4.75,0),0.075,dark)
            beam(Map3DPoint(-7.0,4.75,0),Map3DPoint(-8.10,5.18,0),0.065,steel)
            box(-8.10,5.18,0,0.30,1.40,0.055,dark)
            if !far {beam(Map3DPoint(-8.10,4.06,0.40),Map3DPoint(-6.40,3.72,0.40),0.03,dark)}
        }
    }
}
