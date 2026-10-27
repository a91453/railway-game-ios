import Foundation

/// Circular Line phase-one 610, normal white/yellow livery. Independent shell.
/// Dimensions not explicitly sourced in the handoff are proportional estimates.
public enum Map3DTaipei610 {
    public enum Role: String, CaseIterable, Sendable { case a, c, d, b }
    public static let body = Map3DPalette.concreteWalls[2]
    public static let roof = Map3DPalette.concreteWalls[0]
    public static let yellow = Map3DPalette.player
    public static let mask = Map3DPalette.playerRim
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.62)
    public static let rubber = Map3DColor.rgb(0x2B2E34)
    public static let sequence: [Role] = [.a,.c,.d,.b]
    public static let centres: [Float] = [25.4775,8.38,-8.38,-25.4775]
    public static func id(_ role: Role, far: Bool = false, light: Bool = false) -> String {
        "taipei610-" + role.rawValue + (light ? "-light" : far ? "-far" : "")
    }
    public static func model(_ role: Role, far: Bool = false, light: Bool = false) -> Map3DModelPack.Model {
        var builder = Taipei610Builder(role: role, far: far || light, light: light)
        builder.build()
        let m = Map3DModelPack.Model.flat(named: id(role,far:far,light:light), from: builder.k.mesh)
        guard role == .b else { return m }
        return .init(name:m.name,vertices:m.vertices.map { Map3DVertex(.init(-$0.x,-$0.y,$0.z),normal:.init(-$0.nx,-$0.ny,$0.nz),color:$0.color,layer:$0.layer) },minimum:.init(-m.maximum.x,-m.maximum.y,m.minimum.z),maximum:.init(-m.minimum.x,-m.minimum.y,m.maximum.z))
    }
    public static func formation(far: Bool = false, light: Bool = false) -> Map3DModelPack.Model {
        var k = StationKitBuilder()
        for (i,r) in sequence.enumerated() { k.add(model(r,far:far,light:light),at:.init(centres[i],0,0)) }
        let m = Map3DModelPack.Model.flat(named:"taipei610-formation"+(light ? "-light":far ? "-far":""),from:k.mesh)
        return .init(name:m.name,vertices:m.vertices.map { Map3DVertex(.init($0.x == 0 ? 0:$0.x,$0.y == 0 ? 0:$0.y,$0.z == 0 ? 0:$0.z),normal:.init($0.nx,$0.ny,$0.nz),color:$0.color,layer:$0.layer) },minimum:m.minimum,maximum:m.maximum)
    }
}

private struct Taipei610Builder {
    typealias E = Map3DTaipei610
    let role: E.Role
    let far: Bool
    let light: Bool
    var k = StationKitBuilder()
    var cab: Bool { role == .a || role == .b }
    var half: Float { cab ? 8.4775 : 8.13 }
    var segments: Int { far ? 8 : 32 }
    // Shared primitive methods only; no other train's shell or stations.
    mutating func face(_ p:[Map3DPoint],_ centre:Map3DPoint,_ color:UInt32) {
        if p.count == 4 {
            k.face([p[0],p[1],p[2]],inside:centre,color:color)
            k.face([p[0],p[2],p[3]],inside:centre,color:color)
        } else { k.face(p,inside:centre,color:color) }
    }
    mutating func solid(_ a:[Map3DPoint],_ b:[Map3DPoint],_ color:UInt32) {
        let c=(a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
        for p in [a,b] { for i in 1..<p.count-1 { face([p[0],p[i],p[i+1]],c,color) } }
        for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],c,color) }
    }
    static func noseX(_ h:Float,_ w:Float,_ half:Float)->Float {
        half-max(0,h-1.3)*0.34-0.12*powf(abs(w)/1.325,4)
    }
    func frontRing(_ width:Float,_ height:Float,_ centre:Float,_ inset:Float=0)->[Map3DPoint] {
        (0..<segments).map { i in
            let t=Float(i)*2*Float.pi/Float(segments),c=cosf(t),s=sinf(t)
            let h=centre+height*(s>=0 ? 1:-1)*powf(abs(s),0.48)
            let w=width*(c>=0 ? 1:-1)*powf(abs(c),0.48)*(1+0.06*(h-centre))
            return .init(Self.noseX(h,w,half)+inset,h,w)
        }
    }
    mutating func join(_ a:[Map3DPoint],_ b:[Map3DPoint],_ color:UInt32) {
        for i in a.indices {let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],.init(0,2.0,0),color)}
    }
    mutating func pane(_ x:Float,_ h:Float,_ width:Float,_ height:Float,_ side:Float,_ color:UInt32,_ depth:Float=0.014) {
        let r:Float = light ? 0 : 0.065
        let p:[(Float,Float)] = far ? [(-width/2,-height/2),(width/2,-height/2),(width/2,height/2),(-width/2,height/2)] : [(-width/2+r,-height/2),(width/2-r,-height/2),(width/2,-height/2+r),(width/2,height/2-r),(width/2-r,height/2),(-width/2+r,height/2),(-width/2,height/2-r),(-width/2,-height/2+r)]
        solid(p.map{.init(x+$0.0,h+$0.1,side*1.325)},p.map{.init(x+$0.0,h+$0.1,side*(1.325+depth))},color)
    }
    mutating func build() {
        let white=E.body,ink=E.mask,glass=E.glass,rubber=E.rubber
        // Shell stations deliberately include paint boundaries: coplanar faces,
        // no floating livery plates across passenger doors or glazing.
        let profile:[(Float,Float)] = [(0.94,-1.18),(1.05,-1.325),(1.36,-1.325),(1.55,-1.325),(3.13,-1.325),(3.32,-1.23),(3.40,-0.95),(3.42,0),(3.40,0.95),(3.32,1.23),(3.13,1.325),(1.55,1.325),(1.36,1.325),(1.05,1.325),(0.94,1.18)]
        let end=cab ? half-1.15 : half
        let back=profile.map{Map3DPoint(-half,$0.0,$0.1)},straight=profile.map{Map3DPoint(end,$0.0,$0.1)}
        for i in profile.indices {
            let j=(i+1)%profile.count,mid=(profile[i].0+profile[j].0)/2
            let color:UInt32 = mid>1.36 && mid<1.55 ? E.yellow : mid>1.55 && mid<3.13 ? ink:white
            face([back[i],back[j],straight[j],straight[i]],.init(0,2,0),color)
        }
        k.face(back,inside:.init(0,2,0),color:white)
        k.face(straight,inside:.init(0,2,0),color:white)
        if cab {
            // Rounded dolphin front. Front glass/mask/yellow surround are
            // regions of the closed nose itself, following the same surface.
            let outer=frontRing(1.25,1.24,2.18)
            // Connect the straight-section contour to a matching sampled ring.
            let rear=outer.map{Map3DPoint(end,$0.y,$0.z)}
            k.face(Array(rear.reversed()),inside:.init(half,2,0),color:white)
            join(rear,outer,white)
            // Fill transition back to main body; a short tapered roof/shoulder.
            let rim=frontRing(1.08,0.91,2.45)
            for i in outer.indices {let j=(i+1)%outer.count;face([outer[i],outer[j],rim[j],rim[i]],.init(0,2,0),(rim[i].y+rim[j].y)/2>3.18 ? ink:white)}
            let border=frontRing(0.98,0.83,2.45)
            for i in rim.indices {let j=(i+1)%rim.count;face([rim[i],rim[j],border[j],border[i]],.init(0,2,0),(rim[i].y+rim[j].y)/2>3.18 ? ink:E.yellow)}
            let window=frontRing(0.92,0.76,2.47)
            join(border,window,ink)
            let backingFront=window.map { $0 - Map3DPoint(0.035,0,0) }
            let backingBack=window.map { $0 - Map3DPoint(0.065,0,0) }
            let fc=Map3DPoint(Self.noseX(2.47,0,half)-0.035,2.47,0),bc=fc-Map3DPoint(0.030,0,0)
            for i in window.indices {
                let j=(i+1)%window.count
                face([fc,backingFront[i],backingFront[j]],fc-Map3DPoint(1,0,0),ink)
                face([bc,backingBack[i],backingBack[j]],bc+Map3DPoint(1,0,0),ink)
                face([backingFront[i],backingFront[j],backingBack[j],backingBack[i]],.init(fc.x,2.47,0),ink)
            }
            // The inner backing is mounted to the real glazing/frame boundary.
            // Four short inward frame ties keep the backing from floating inside
            // the nose; the original exterior shell and glass stay untouched.
            for i in [0,segments/4,segments/2,segments*3/4] {
                k.beam(backingBack[i],window[i]+Map3DPoint(0.005,0,0),0.040,ink)
            }
            let c=Map3DPoint(Self.noseX(2.47,0,half),2.47,0)
            for i in window.indices {face([c,window[i],window[(i+1)%window.count]],.init(0,2,0),glass)}
            // Paired organic lamp bezels; no red tail lenses or brand text.
            for s:Float in [-1,1] {
                let y:Float=1.65,w=s*1.02,x=Self.noseX(y,w,half)
                let n=far ? 8:16
                let a=(0..<n).map { i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(n);return .init(x+0.01,y+0.105*sinf(t),w+0.20*cosf(t)) }
                solid(a,a.map{$0 + Map3DPoint(0.025,0,0)},rubber)
                for off:Float in [-0.075,0.075] { k.box(x+0.04,y-0.040,w+off,0.025,0.08,0.08,Map3DPalette.tunnelLamp) }
            }
            k.box(half-0.20,0.98,0,0.35,2.45,0.32,white)
            for s:Float in [-1,1] {
                k.box(half+0.01,1.04,s*0.87,0.16,0.39,0.25,E.roof)
                if !far {for i in 0..<4 {k.box(half+0.10,1.07+Float(i)*0.048,s*0.87,0.06,0.36,0.02,StationKitBuilder.steel)}}
            }
            if !light {
                let pivot=Map3DPoint(Self.noseX(1.80,0.04,half)+0.030,1.80,0.04)
                k.box(pivot.x-0.010,1.76,0.04,0.050,0.080,0.080,rubber)
                k.beam(pivot,.init(Self.noseX(2.32,0.53,half)+0.030,2.32,0.53),0.035,rubber)
            }
            // Actual drawbar hanger contacts both the drawbar and floor.
            // Previously these were only within a 65mm proximity allowance.
            k.box(half-0.45,0.77,0,0.24,0.22,0.12,StationKitBuilder.steel)
            k.beam(.init(half-0.60,0.70,0),.init(half+0.25,0.70,0),0.17,StationKitBuilder.steel)
            k.box(half+0.29,0.56,0,0.20,0.40,0.26,StationKitBuilder.steel)
        }
        k.box(0,0.87,0,2*half,2.36,0.10,StationKitBuilder.steel)
        let doors:[Float] = cab ? [-5.90,-0.65,4.60] : [-5.30,0,5.30]
        for s:Float in [-1,1] {
            for d in doors {
                pane(d,2.08,1.52,2.05,s,ink)
                pane(d,1.22,1.50,0.34,s,white,0.019)
                for leaf:Float in [-1,1] {
                    pane(d+leaf*0.35,2.50,0.44,0.97,s,glass,0.026)
                }
                k.box(d,1.07,s*1.354,0.025,0.018,2.02,rubber)
                k.box(d,1.36,s*1.345,1.48,0.025,0.19,E.yellow)
            }
            for i in 0..<2 {
                let start=doors[i]+0.85,end=doors[i+1]-0.85,gap:Float=0.12,w=(end-start-gap)/2
                for j in 0..<2 {pane(start+w/2+Float(j)*(w+gap),2.50,w,1.02,s,glass)}
            }
            if cab {
                // Unmanned observation-end side window, no crew door.
                solid([.init(6.02,1.76,s*1.326),.init(7.25,1.76,s*1.326),.init(6.85,3.09,s*1.326),.init(6.02,3.09,s*1.326)], [.init(6.02,1.76,s*1.344),.init(7.25,1.76,s*1.344),.init(6.85,3.09,s*1.344),.init(6.02,3.09,s*1.344)],glass)
            }
        }
        // Two continuous HVAC cases per car, supported on the actual roof.
        for x:Float in [-4.25,4.25] {
            k.box(x,3.42,0,3.45,1.72,0.18,E.roof)
            if !far {for i in 0..<9 {k.box(x-1.4+Float(i)*0.35,3.60,0,0.055,1.42,0.012,StationKitBuilder.steel)}}
        }
        // Published role split: compressors on A/B, inverter on every car.
        k.box(-1.6,0.40,0,2.8,1.9,0.47,StationKitBuilder.steel)
        k.box(1.6,0.47,0.12,1.7,1.65,0.40,E.roof)
        if cab {k.cylinder(3.0,0.42,-0.50,radius:0.25,height:0.35,color:StationKitBuilder.steel,sides:far ? 8:12); k.box(3.0,0.77,-0.50,0.35,0.30,0.10,StationKitBuilder.steel)}
        else if !far {k.box(role == .c ? -3.45:3.45,0.44,-0.30,1.0,1.05,0.43,E.roof)}
        let bogie:Float = cab ? 5.72:5.60
        for bx in [-bogie,bogie] {
            k.box(bx,0.58,0,2.55,1.20,0.23,StationKitBuilder.steel)
            k.beam(.init(bx,0.77,-1.00),.init(bx,0.77,1.00),0.12,StationKitBuilder.steel)
            if far { k.box(bx,0.81,0,0.85,1.45,0.13,rubber) }
            else { for s:Float in [-1,1] { k.cylinder(bx,0.81,s*0.45,radius:0.18,height:0.13,color:rubber,sides:8) } }
            for dx:Float in [-0.90,0.90] {
                let x=bx+dx
                k.box(x,0.40,0,0.30,1.20,0.20,StationKitBuilder.steel)
                for s:Float in [-1,1] {
                    let n=far ? 8:20
                    let a=(0..<n).map { i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(n);return .init(x+0.355*cosf(t),0.355+0.355*sinf(t),s*0.67) }
                    solid(a,a.map{$0 + Map3DPoint(0,0,s*0.18)},rubber)
                    if !far {k.box(x,0.39,s*1.00,0.36,0.25,0.26,E.roof); k.beam(.init(x,0.55,s*1.00),.init(bx,0.77,s*1.00),0.10,StationKitBuilder.steel)}
                }
                k.beam(.init(x,0.355,-1.00),.init(x,0.355,1.00),0.12,StationKitBuilder.steel)
            }
            // Mersen collector: insulated mounting, arm, carbon shoe. Position
            // and dimensions estimated; no roof collection gear.
            for s:Float in [-1,1] {
                k.box(bx,0.56,s*1.00,0.48,0.35,0.25,E.roof)
                k.box(bx,0.48,s*1.23,0.30,0.16,0.55,E.yellow)
                k.beam(.init(bx,0.52,s*1.28),.init(bx,0.27,s*1.48),0.12,E.roof)
                k.box(bx,0.22,s*1.48,0.52,0.18,0.06,rubber)
            }
        }
        // Each end owns half of the flexible gangway; no stretched train mesh.
        for s:Float in cab ? [-1]:[-1,1] {
            if !far {
                k.box(s*(half+0.10),0.65,0,0.28,0.18,0.12,StationKitBuilder.steel)
                k.box(s*(half-0.08),0.77,0,0.28,0.18,0.10,StationKitBuilder.steel)
            }
            k.box(s*(half+0.12),1.10,0,0.24,1.75,2.12,rubber)
            if !light {for i in 0..<5 {k.box(s*(half+0.025+Float(i)*0.045),1.10,0,0.018,1.82,2.12,E.roof)}}
        }
    }
}
