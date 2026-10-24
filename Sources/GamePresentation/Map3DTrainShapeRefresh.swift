import Foundation

/// Independent photo-led static studies. Not assigned to operating train types.
public enum Map3DTrainShapeRefresh {
    public static let ids = ["refresh-e200", "refresh-700t-cab", "refresh-700t-middle", "refresh-700t-panto", "refresh-700t-tail"]
    public static func model(_ id: String) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        if id == ids[0] { b.refreshElectric() }
        else { b.refreshHighSpeed(cab: id == ids[1] || id == ids[4], panto: id == ids[3]) }
        let m = Map3DModelPack.Model.flat(named: id, from: b.mesh)
        if id == ids[4] {
            var reverse = StationKitBuilder(); reverse.add(m, at: .zero, angle: .pi)
            return .flat(named: id, from: reverse.mesh)
        }
        return m
    }
    /// Display formation: cab + ten middle cars + reverse cab. Metre offsets
    /// are display estimates. Pantographs on cars 4 and 9 (one-based).
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for i in 0..<12 {
            let id = i == 0 ? ids[1] : i == 11 ? ids[4] : [3,8].contains(i) ? ids[3] : ids[2]
            b.add(model(id), at: Map3DPoint(Float(11-2*i)*12.7,0,0))
        }
        return .flat(named: "refresh-700t-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    private var refreshWhite: UInt32 { Map3DPalette.shopAwnings[3] }
    private var refreshTeal: UInt32 { Map3DPalette.shopAwnings[0] }
    private var refreshGlass: UInt32 { Map3DColor.shaded(Map3DPalette.glazing,0.5) }
    private mutating func refreshRunning(_ centres: [Float], axles: [Float], radius: Float, gauge: Float) {
        // Twelve-sided cross sections include the true bottom contact point.
        let contactHeight=radius
        for x in centres {
            box(x,0.49,0,axles.last! - axles.first! + 0.8,gauge+0.22,0.25,Self.ink)
            for dx in axles {
                civicTube(Map3DPoint(x+dx,contactHeight,-gauge/2),Map3DPoint(x+dx,contactHeight,gauge/2),radius:0.075,color:Self.steel,sides:6)
                for s: Float in [-1,1] {
                    civicTube(Map3DPoint(x+dx,contactHeight,s*(gauge/2-0.04)),Map3DPoint(x+dx,contactHeight,s*(gauge/2+0.15)),radius:radius,color:Map3DStreetModel.tyre,sides:12)
                }
            }
            box(x,0.72,0,1.2,gauge,0.35,Self.steel)
            for side: Float in [-1,1] {
                let outer=side*(gauge/2+0.22)
                box(x,0.48,outer,axles.last!-axles.first!+0.74,0.16,0.23,Self.steel)
                for dx in axles {
                    box(x+dx,0.36,outer,0.37,0.19,0.28,Self.ink)
                    civicTube(Map3DPoint(x+dx,contactHeight,outer),Map3DPoint(x+dx,contactHeight,outer+side*0.035),radius:radius*0.43,color:Self.steel,sides:12)
                    for coil: Float in [-0.3,0.3] { cylinder(x+dx+coil,0.58,outer,radius:0.10,height:0.23,color:Self.ink,sides:8) }
                }
            }
        }
    }
    private mutating func refreshPanto(_ x: Float, roof: Float, singleArm: Bool = false) {
        box(x,roof,0,1.8,1.15,0.12,Self.steel)
        for z: Float in [-0.43,0.43] {
            cylinder(x,roof+0.12,z,radius:0.12,height:0.18,color:refreshWhite,sides:8)
            if singleArm {
                let hand: Float = x>=0 ? 1:-1
                beam(Map3DPoint(x-hand*0.45,roof+0.28,z),Map3DPoint(x+hand*0.65,roof+0.58,z),0.055,Self.ink)
                beam(Map3DPoint(x+hand*0.65,roof+0.58,z),Map3DPoint(x,roof+0.90,z),0.045,Self.ink)
            } else {
                for sign: Float in [-1,1] {
                    beam(Map3DPoint(x,roof+0.28,z),Map3DPoint(x+sign*0.65,roof+0.57,z),0.045,Self.ink)
                    beam(Map3DPoint(x+sign*0.65,roof+0.57,z),Map3DPoint(x,roof+0.9,z),0.045,Self.ink)
                }
            }
        }
        box(x,roof+0.88,0,0.16,1.5,0.07,Self.steel)
    }
    mutating func refreshElectric() {
        // E200 dimensions from the project's sourced engineering catalog.
        let half: Float = 8.5245, w: Float = 1.486
        let profile: [(Float,Float)] = [(1.13,-w),(3.35,-w),(3.92,-1.14),(3.92,1.14),(3.35,w),(1.13,w)]
        let rings = [-half,-half+0.42,half-0.42,half].map { x in
            profile.map { h,z in Map3DPoint(x.sign == .minus ? x + (h>3.35 ? 0.18:0) : x - (h>3.35 ? 0.18:0),h,z) }
        }
        let inside = Map3DPoint(0,2.5,0)
        for k in 0..<3 { for i in profile.indices {
            let j=(i+1)%profile.count
            face([rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],inside:inside,color:i==5 ? Self.ink:refreshWhite)
        } }
        for k in [0,3] {
            face([rings[k][0],rings[k][1],rings[k][4],rings[k][5]],inside:inside,color:refreshWhite)
            face([rings[k][1],rings[k][2],rings[k][3],rings[k][4]],inside:inside,color:refreshWhite)
        }
        for sign: Float in [-1,1] { box(sign*(half+0.008),1.13,0,0.018,2*w,1.62,refreshTeal) }
        box(0,0.99,0,16.8,2.65,0.14,Self.ink)
        refreshRunning([-5.1,5.1],axles:[-1.5,0,1.5],radius:0.51,gauge:1.067)
        for s: Float in [-1,1] {
            box(0,1.15,s*1.482,16.15,0.02,1.42,refreshTeal)
            box(0,2.64,s*1.486,16.15,0.022,0.055,refreshTeal)
            for x: Float in [-7.2,7.2] {
                box(x,1.3,s*1.49,0.63,0.018,2.05,Map3DPalette.tankWhite)
                box(x,2.65,s*1.502,0.44,0.012,0.57,refreshGlass)
                box(x+(x>0 ? 0.65:-0.65),2.73,s*1.49,0.84,0.02,0.59,refreshGlass)
            }
            // Photo shows broad smooth side panels; vents belong on the roof.
            for x: Float in [-5.9,0,5.9] {
                box(x,1.35,s*1.493,0.025,0.014,2.0,Self.steel)
                for h: Float in [1.62,2.16,2.74,3.15] { box(x, h,s*1.502,0.06,0.018,0.055,Self.ink) }
            }
            let x=s*half
            // Two front windows; face panel is almost upright below shoulder.
            for z: Float in [-0.68,0.68] {
                let outline=refreshRoundedOutline(x:z,y:3.285,width:1.16,height:0.65,radius:0.075)
                for upper in [false,true] {
                    var clipped: [(Float,Float)]=[]
                    for i in outline.indices {
                        let a=outline[i],b=outline[(i+1)%outline.count]
                        let ia=upper ? a.1>=3.35:a.1<=3.35,ib=upper ? b.1>=3.35:b.1<=3.35
                        if ia { clipped.append(a) }
                        if ia != ib { let t=(3.35-a.1)/(b.1-a.1);clipped.append((a.0+(b.0-a.0)*t,3.35)) }
                    }
                    let p=clipped.map { lateral,h in Map3DPoint(x-s*max(0,h-3.35)*0.18/0.57+s*0.022,h,lateral) }
                    refreshPanel(p,thickness:0.025,color:refreshGlass)
                }
            }
            box(x-s*0.12,3.70,0,0.24,0.62,0.18,Self.steel)
            for z: Float in [-0.15,0.15] {
                civicTube(Map3DPoint(x-s*0.01,3.79,z),Map3DPoint(x+s*0.035,3.79,z),radius:0.095,color:Map3DPalette.tunnelLamp,sides:12)
            }
            for z: Float in [-1,1] {
                beam(Map3DPoint(x+s*0.02,2.66,z*1.35),Map3DPoint(x+s*0.02,1.91,0),0.065,refreshWhite)
            }
            box(x,0.54,0,0.11,2.55,0.48,Self.steel)
            box(x+s*0.15,0.83,0,0.44,0.34,0.22,Self.ink)
        }
        for x: Float in [-4.8,4.8] { refreshPanto(x,roof:3.92,singleArm:true) }
        // E201 source study: asymmetric roof equipment, rebuilt in simple solids.
        // Its source mesh/texture is not copied and its dimensions are not used.
        box(1.72,3.92,0,3.85,1.88,0.14,Self.steel)
        box(1.72,4.06,0,3.58,1.55,0.23,refreshWhite)
        for side: Float in [-1,1] { for i in 0..<3 {
            box(0.55+Float(i)*1.14,4.11,side*0.786,1.00,0.025,0.14,Self.ink)
            for j in 0..<4 { box(0.55+Float(i)*1.14,4.12+Float(j)*0.033,side*0.804,0.94,0.012,0.009,Self.steel) }
        } }
        for x: Float in [-7.45,7.45] {
            box(x,3.92,0,0.9,1.3,0.18,refreshWhite)
            cylinder(x,4.10,0,radius:0.43,height:0.035,color:Self.ink,sides:16)
            for j in -2...2 { box(x+Float(j)*0.14,4.14,0,0.025,0.70,0.018,Self.steel) }
        }
        for lateral: Float in [-0.47,0.47] {
            box(-2.15,3.92,lateral,2.75,0.28,0.10,Self.steel)
            for i in 0..<9 { cylinder(-3.2+Float(i)*0.26,4.02,lateral,radius:0.10,height:0.19,color:refreshWhite,sides:8) }
        }
        for sign: Float in [-1,1] { for x: Float in [-7.15,7.15] {
            for j in 0..<3 { box(x,0.56+Float(j)*0.22,sign*1.39,0.64,0.24,0.07,Self.steel) }
            for dx: Float in [-0.30,0.30] { beam(Map3DPoint(x+dx,0.55,sign*1.4),Map3DPoint(x+dx,1.3,sign*1.4),0.045,Self.ink) }
        } }
        box(0,0.38,0,4.9,1.95,0.59,Self.steel)
        for side: Float in [-1,1] { for j in 0..<9 { box(-2.1+Float(j)*0.52,0.52,side*0.987,0.33,0.025,0.27,Self.ink) } }
        for x: Float in [-3.45,3.45] {
            cylinder(x,3.92,0,radius:0.16,height:0.43,color:refreshWhite,sides:10)
            for j in 0..<4 { cylinder(x,4.00+Float(j)*0.085,0,radius:0.20,height:0.035,color:Self.steel,sides:10) }
        }
        beam(Map3DPoint(-4.8,4.17,0.43),Map3DPoint(4.8,4.17,0.43),0.04,Self.ink)
    }
    mutating func refreshHighSpeed(cab: Bool,panto: Bool) {
        let segments=40, bottom: Float=0.78
        let xs: [Float] = cab ? [-12.5,-6,0,3.7,4.2,4.8,5.8,6.3,6.7,7.1,7.5,7.9,8.3,8.7,9.1,9.5,9.7,10,10.5,11,11.5,11.9,12.2,12.4,12.5] : [-12.5,12.5]
        func interpolate(_ t: Float,_ points: [(Float,Float)])->Float {
            for i in 1..<points.count where t<=points[i].0 {
                let a=points[i-1],b=points[i]
                return a.1+(b.1-a.1)*(t-a.0)/(b.0-a.0)
            }
            return points.last!.1
        }
        func dimensions(_ x: Float)->(Float,Float) {
            if !cab || x<=5.8 { return (3.65,1.69) }
            let t=(x-5.8)/6.7
            let h=interpolate(t,[(0,3.65),(0.16,3.65),(0.28,3.52),(0.40,3.16),(0.52,2.69),(0.65,2.12),(0.80,1.60),(0.92,1.34),(1,1.18)])
            let w=interpolate(t,[(0,1.69),(0.3,1.69),(0.5,1.66),(0.7,1.54),(0.85,1.32),(0.95,0.90),(0.985,0.48),(1,0.08)])
            // Restore the original nose length. The photo's coloured shoulder
            // carries the lip; extending the whole nose made a flat paddle.
            return (h,w)
        }
        func surface(_ x: Float,_ a: Float)->Map3DPoint {
            let (h,w)=dimensions(x),c=cosf(a),s=sinf(a)
            let z=w*(c>=0 ? 1:-1)*powf(abs(c),0.58)
            let y=bottom+(h-bottom)*(0.5+0.5*(s>=0 ? 1:-1)*powf(abs(s),0.65))
            return Map3DPoint(x,y,z)
        }
        func shellAngle(_ x: Float,_ i: Int)->Float {
            let original=Float(i)*2*Float.pi/Float(segments)
            guard cab && x>=3.7 else { return original }
            // Preserve the delivered shell sampling. Paint is clipped separately
            // below so its boundary cannot inherit this angular height wave.
            let a=interpolate(x,[(3.7,-0.157),(4.8,-0.07),(5.8,-0.015),(7.5,0.02),(9.1,0.20),(10,0.53),(10.5,0.76),(11,1.0),(11.5,1.30),(11.9,1.46),(12.5,1.46)])
            return interpolate(Float(i),[(0,a),(10,Float.pi/2),(20,Float.pi-a),(24,Float.pi+0.63),(30,1.5*Float.pi),(36,2*Float.pi-0.63),(40,2*Float.pi+a)])
        }
        let rings=xs.map { x in (0..<segments).map { i in
            let a=shellAngle(x,i),p=surface(x,a)
            let shoulder = cab && x>3.7 ? interpolate(x,[(3.7,0),(5.8,0.035),(8.7,0.065),(10.5,0.045),(11.9,0.018),(12.5,0)]) : 0
            let swell=shoulder*powf(max(0,1-abs(sinf(a))),4)
            return Map3DPoint(p.x,p.y,p.z+(cosf(a)>=0 ? swell:-swell))
        } }
        func bandHeight(_ x: Float)->Float {
            // C1-continuous joins to the straight body stripe and low lip.
            // Evaluate height directly: angular colours made the old wavy hump.
            let baseline: Float=1.7852976
            func ease(_ t: Float)->Float { let u=max(0,min(1,t));return u*u*(3-2*u) }
            if x<=3.7 { return baseline }
            if x<=6.7 { return baseline+(1.98-baseline)*ease((x-3.7)/3) }
            return 1.98+(1.30-1.98)*ease((x-6.7)/5.8)
        }
        func clip(_ polygon: [Map3DPoint],at x0: Float,_ x1: Float,upper: Bool)->[Map3DPoint] {
            let h0=bandHeight(x0),h1=bandHeight(x1)
            func distance(_ p: Map3DPoint)->Float {
                let d=p.y-(h0+(h1-h0)*(p.x-x0)/(x1-x0))
                return abs(d)<0.000001 ? 0:d
            }
            var out: [Map3DPoint]=[]
            for i in polygon.indices {
                let a=polygon[i],b=polygon[(i+1)%polygon.count],da=distance(a),db=distance(b)
                let ia=upper ? da>=0:da<=0,ib=upper ? db>=0:db<=0
                if ia { out.append(a) }
                if ia != ib && da != 0 && db != 0 {
                    // Sort edge endpoints so both neighbouring triangles produce
                    // exactly the same intersection, avoiding cracks/T-junctions.
                    let lo=a.x<b.x || (a.x==b.x && a.z<b.z) ? a:b
                    let hi=lo==a ? b:a
                    let dl=distance(lo),dh=distance(hi)
                    out.append(lo+(hi-lo)*(dl/(dl-dh)))
                }
            }
            return out
        }
        for k in 0..<rings.count-1 {
            let h=(dimensions(xs[k]).0+dimensions(xs[k+1]).0)/2
            let inside=Map3DPoint((xs[k]+xs[k+1])/2,(bottom+h)/2,0)
            for i in 0..<segments {
                let j=(i+1)%segments
                let shoulderBand = cab && xs[k]>=3.7
                let teal = shoulderBand ? (20...23).contains(i) || (36...39).contains(i) : [21,22,23,36,37,38].contains(i)
                let color: UInt32 = (24...35).contains(i) ? Self.steel : teal ? refreshTeal:refreshWhite
                for triangle in [[rings[k][i],rings[k][j],rings[k+1][j]],[rings[k][i],rings[k+1][j],rings[k+1][i]]] {
                    if cab && xs[k]>=0 && !(24...35).contains(i) {
                        // Subdivide the existing planar triangle for paint only;
                        // never move the original surface to chase a colour edge.
                        face(clip(triangle,at:xs[k],xs[k+1],upper:true),inside:inside,color:refreshWhite)
                        face(clip(triangle,at:xs[k],xs[k+1],upper:false),inside:inside,color:refreshTeal)
                    } else { face(triangle,inside:inside,color:color) }
                }
            }
        }
        face(rings[0],inside:Map3DPoint(0,2,0),color:refreshWhite)
        face(rings.last!,inside:Map3DPoint(0,2,0),color:cab ? refreshTeal:refreshWhite)
        refreshRunning([-8.8,cab ? 3.4:8.8],axles:[-1.25,1.25],radius:0.40,gauge:1.435)
        box(cab ? -3.7:0,0.92,0,cab ? 17.4:23.8,2.55,0.12,Self.ink)
        func flank(_ h: Float)->Float {
            let s=(h-bottom)/(3.65-bottom)*2-1
            return 1.69*powf(max(0,1-powf(abs(s),2/0.65)),0.58/2)
        }
        for sign: Float in [-1,1] {
            box(cab ? -3.7:0,0.55,sign*1.42,cab ? 17.4:23.8,0.09,0.67,Self.steel)
            func side(_ x: Float,_ h: Float,_ offset: Float)->Map3DPoint { Map3DPoint(x,h,sign*(flank(h)+offset)) }
            for i in 0..<(cab ? 12:18) {
                let x: Float = -9.3+Float(i)*0.81
                let gasket=refreshRoundedOutline(x: x,y:2.345,width:0.56,height:0.75,radius:0.12)
                refreshPanel(gasket.map { side($0.0,$0.1,0.012) },thickness:0.028,color:Self.ink)
                let pane=refreshRoundedOutline(x:x,y:2.345,width:0.49,height:0.68,radius:0.10)
                refreshPanel(pane.map { side($0.0,$0.1,0.024) },thickness:0.028,color:refreshGlass)
            }
            for x: Float in cab ? [-11,3.1]:[-11,11] {
                let frame=refreshRoundedOutline(x:x,y:2.04,width:0.83,height:1.96,radius:0.11)
                refreshPanel(frame.map { side($0.0,$0.1,0.012) },thickness:0.025,color:Self.steel)
                let leaf=refreshRoundedOutline(x:x,y:2.04,width:0.77,height:1.90,radius:0.09)
                refreshPanel(leaf.map { side($0.0,$0.1,0.024) },thickness:0.035,color:refreshWhite)
                let pane=refreshRoundedOutline(x:x,y:2.37,width:0.34,height:0.61,radius:0.07)
                refreshPanel(pane.map { side($0.0,$0.1,0.033) },thickness:0.035,color:refreshGlass)
                box(x+0.25,1.82,sign*(flank(1.82)+0.045),0.07,0.028,0.05,Self.steel)
            }
        }
        if cab {
            // Rounded trapezoidal cockpit mapped onto the real nose surface.
            // Each small prism is backed by that same shell; no billboard box.
                func screen(_ r: Int,_ c: Int)->Map3DPoint {
                    let v=Float(r)/6,u=Float(c)/12
                    let a: Float=0.92+u*(Float.pi-1.84)
                    let round=sinf(u*Float.pi)
                    let rear: Float=7.30-0.16*round,front: Float=9.55+0.13*round
                    let x=rear+(front-rear)*v
                    let p=surface(x,a)
                    return p+Map3DPoint(0,0.018,0)
                }
            for row in 0..<6 { for col in 0..<12 {
                let p=[screen(row,col),screen(row,col+1),screen(row+1,col+1),screen(row+1,col)]
                refreshPanel(p,thickness:0.035,color:refreshGlass)
            } }
            let rim=Map3DColor.shaded(refreshGlass,0.72)
            for c in 0..<12 { for r in [0,6] { beam(screen(r,c),screen(r,c+1),0.025,rim) } }
            for r in 0..<6 { for c in [0,12] { beam(screen(r,c),screen(r+1,c),0.025,rim) } }
            // Two low lens clusters, two actual warm-white lamps in each.
            for side: Float in [-1,1] {
                let a: Float = side>0 ? 1.28:Float.pi-1.28
                let centre=surface(9.34,a)+Map3DPoint(0,0.041,0)
                let along=Map3DPoint(0,0,side)
                let across=(surface(9.49,a)-surface(9.19,a)).normalized!
                let housing=refreshRoundedOutline(x:0,y:0,width:0.66,height:0.29,radius:0.07)
                refreshPanel(housing.map { centre+along*$0.0+across*$0.1 },thickness:0.045,color:Self.steel)
                for offset: Float in [-0.16,0.16] {
                    let lens=refreshRoundedOutline(x:offset,y:0,width:0.21,height:0.15,radius:0.045)
                    refreshPanel(lens.map { centre+along*$0.0+across*$0.1+Map3DPoint(0,0.019,0) },thickness:0.025,color:Map3DPalette.tunnelLamp)
                }
            }
        }
        for end: Float in cab ? [-1]:[-1,1] {
            box(end*12.58,1.05,0,0.18,2.15,2.07,Self.ink)
            for dx: Float in [-0.055,0,0.055] { box(end*12.58+dx,1.05,0,0.018,2.19,2.07,Self.steel) }
            box(end*12.58,0.66,0,0.32,0.35,0.3,Self.steel)
        }
        if panto { refreshPanto(6.8,roof:3.65,singleArm:true) }
    }
    /// Twelve-vertex rounded rectangle, shared only by this Codex recipe.
    private func refreshRoundedOutline(x: Float,y: Float,width: Float,height: Float,radius: Float)->[(Float,Float)] {
        let r=min(radius,min(width,height)/2)
        let corners: [(Float,Float,Float)]=[(x+width/2-r,y+height/2-r,0),(x-width/2+r,y+height/2-r,90),(x-width/2+r,y-height/2+r,180),(x+width/2-r,y-height/2+r,270)]
        var result: [(Float,Float)]=[]
        for (cx,cy,start) in corners {
            for i in 0...2 { let a=(start+Float(i)*45)*Float.pi/180;result.append((cx+cosf(a)*r,cy+sinf(a)*r)) }
        }
        return result
    }
    private mutating func refreshPanel(_ p: [Map3DPoint],thickness: Float,color: UInt32) {
        var raw=Map3DPoint.zero
        for i in 2..<p.count { if let n=(p[1]-p[0]).cross(p[i]-p[0]).normalized { raw=n;break } }
        let centre=p.reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count)) }
        let normal=raw.dot(centre-Map3DPoint(0,2,0))>=0 ? raw:raw*(-1)
        let back=p.map { $0-normal*thickness }
        let c=(p+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count*2)) }
        face(p,inside:c,color:color);face(back,inside:c,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],back[i],back[j],p[j]],inside:c,color:color) }
    }
}
