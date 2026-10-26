import Foundation

/// Independent photo-led static studies. Decision 408: the E200 draws the
/// Chu-Kuang sets' locomotive and the 700T units the high-speed set
/// (``Map3DTrainSet/highSpeed700T()``); their shapes are as made here.
public enum Map3DTrainShapeRefresh {
    public static let highSpeedBodyColor=Map3DPalette.shopAwnings[3]
    public static let highSpeedAccentColor=Map3DColor.shaded(Map3DPalette.tankStand,0.42)
    public static let highSpeedGlassColor=Map3DColor.shaded(Map3DPalette.glazing,0.5)
    public static let ids = ["refresh-e200", "refresh-700t-cab", "refresh-700t-middle", "refresh-700t-panto", "refresh-700t-tail"]
    public static func model(_ id: String) -> Map3DModelPack.Model { model(id, far: false) }
    /// `far`: decision 422's light 700T car drawn from 500 m out, made by
    /// this recipe as ``Map3DE500/model(far:)`` is by its own: the same
    /// shell, paint and length on half the sections and fewer nose rings,
    /// each window one flat pane, a door its window,
    /// plain bogies and pantograph, the windscreen in a few flat cells, and
    /// none of the small fittings. The E200 has none.
    public static func model(_ id: String, far: Bool) -> Map3DModelPack.Model {
        let far = far && id != ids[0], name = far ? id + "-far" : id
        var b = StationKitBuilder()
        if id == ids[0] { b.refreshElectric() }
        else { b.refreshHighSpeed(cab: id == ids[1] || id == ids[4], panto: id == ids[3], far: far) }
        let m = Map3DModelPack.Model.flat(named: name, from: b.mesh)
        if id == ids[4] {
            var reverse = StationKitBuilder(); reverse.add(m, at: .zero, angle: .pi)
            return .flat(named: name, from: reverse.mesh)
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
    /// The 700T's bogies centred at `centres` (metres along the car), their
    /// axles at `axles` from each centre; decision 408 draws the N700S-G's
    /// on them too, its axles where the author's stood.
    mutating func refreshHighSpeedRunning(_ centres: [Float],axles: [Float] = [-1.25,1.25]) {
        refreshRunning(centres,axles:axles,radius:0.40,gauge:1.435)
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
    mutating func refreshHighSpeed(cab: Bool,panto: Bool,far: Bool = false) {
        let hsrBody=Map3DTrainShapeRefresh.highSpeedBodyColor
        let hsrGlass=Map3DTrainShapeRefresh.highSpeedGlassColor
        // Decision 422: the far car on half the sections (the underside
        // the same arc) and eleven of the nose's 24 spans.
        let segments=far ? 20:40, bottom: Float=0.78, under=far ? 12...17:24...35
        let xs: [Float] = !cab ? [-12.5,12.5] : far ? [-12.5,3.7,5.8,6.7,7.5,8.3,9.1,9.7,10.5,11.5,12.2,12.5]
            : [-12.5,-6,0,3.7,4.2,4.8,5.8,6.3,6.7,7.1,7.5,7.9,8.3,8.7,9.1,9.5,9.7,10,10.5,11,11.5,11.9,12.2,12.4,12.5]
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
            var y=bottom+(h-bottom)*(0.5+0.5*(s>=0 ? 1:-1)*powf(abs(s),0.65))
            if cab && x>5.8 && s<0 {
                let t=max(0,min(1,(x-5.8)/1.3)),ease=t*t*(3-2*t)
                // Continuous lower fairing, part of the closed body shell.
                // The leading bogie at x<=4.65 retains its original clearance.
                y -= 0.54*ease*powf(-s,0.50)
            }
            return Map3DPoint(x,y,z)
        }
        let rings=xs.map { x in (0..<segments).map { i in
            let a=Float(i)*2*Float.pi/Float(segments),p=surface(x,a)
            guard cab && x>5.8 else { return p }
            // Photo-led rounded shoulder: keep width below the narrowing white
            // nose. N700S GLB informed the section relationship, not these vertices.
            let (h,_)=dimensions(x),u=max(0,min(1,(x-5.8)/6.7))
            let amplitude: Float=0.20*powf(max(0,sinf(Float.pi*u)),1.5)
            let shoulderHeight=bottom+0.32*(h-bottom),radius=0.22*(h-bottom)+0.08
            let distance=(p.y-shoulderHeight)/radius
            let swell=amplitude*expf(-distance*distance)
            let lateral=min(1.69,abs(p.z)+swell)
            return Map3DPoint(p.x,p.y,p.z>=0 ? lateral:-lateral)
        } }
        func bandHeight(_ x: Float)->Float {
            // Smooth centreline height; the flank term below wraps this boundary
            // around the sculpted shoulder instead of drawing a flat stripe.
            let baseline: Float=1.7852976
            func ease(_ t: Float)->Float { let u=max(0,min(1,t));return u*u*(3-2*u) }
            if !cab || x<=6.7 { return baseline }
            return baseline+(0.94-baseline)*ease((x-6.7)/5.8)
        }
        func clip(_ polygon: [Map3DPoint],at x0: Float,_ x1: Float,upper: Bool,offset: Float = 0)->[Map3DPoint] {
            let h0=bandHeight(x0),h1=bandHeight(x1)
            func distance(_ p: Map3DPoint)->Float {
                let (_,w)=dimensions(p.x)
                let t=cab ? max(0,min(1,(p.x-3.7)/7.2)):0,ease=t*t*(3-2*t)
                let flank=abs(p.z)/w
                // The coloured rim climbs around the sides, leaving a tapered
                // white inset. A flat height cut erased this in the prior version.
                let height=h0+(h1-h0)*(p.x-x0)/(x1-x0)+0.70*ease*powf(flank,4)
                let d=p.y-height-offset
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
        func orientedTriangles(_ polygon: [Map3DPoint],inside: Map3DPoint)->[[Map3DPoint]] {
            guard polygon.count>=3 else { return [] }
            let normal=(polygon[1]-polygon[0]).cross(polygon[2]-polygon[0])
            let centre=polygon.reduce(Map3DPoint.zero) { $0+$1*(1/Float(polygon.count)) }
            let points=normal.dot(centre-inside)>=0 ? polygon:Array(polygon.reversed())
            return (1..<points.count-1).map { [points[0],points[$0],points[$0+1]] }
        }
        func skirtHeight(_ x: Float)->Float {
            guard cab else { return bottom-0.01 }
            return bottom-0.01-0.01*max(0,min(1,(x-3.7)/2.1))
        }
        func skirtClip(_ polygon: [Map3DPoint],_ x0: Float,_ x1: Float,upper: Bool)->[Map3DPoint] {
            func distance(_ p: Map3DPoint)->Float {
                let h=skirtHeight(x0)+(skirtHeight(x1)-skirtHeight(x0))*(p.x-x0)/(x1-x0)
                let t=max(0,min(1,(p.x-3.7)/2.1)),ease=t*t*(3-2*t)
                let flank=abs(p.z)/1.69
                let d=p.y-h-0.18*ease*flank*flank
                return abs(d)<0.000001 ? 0:d
            }
            var result: [Map3DPoint]=[]
            for i in polygon.indices {
                let a=polygon[i],b=polygon[(i+1)%polygon.count],da=distance(a),db=distance(b)
                let ia=upper ? da>=0:da<=0,ib=upper ? db>=0:db<=0
                if ia { result.append(a) }
                if ia != ib && da != 0 && db != 0 {
                    let lo=a.x<b.x || (a.x==b.x && a.z<b.z) ? a:b,hi=lo==a ? b:a
                    let dl=distance(lo),dh=distance(hi)
                    result.append(lo+(hi-lo)*(dl/(dl-dh)))
                }
            }
            return result
        }
        func hullParts(_ polygon: [Map3DPoint],_ x0: Float,_ x1: Float)->([Map3DPoint],[Map3DPoint]) {
            guard cab else { return (polygon,[]) }
            return (skirtClip(polygon,x0,x1,upper:true),skirtClip(polygon,x0,x1,upper:false))
        }
        func nosePaintParts(_ triangle: [Map3DPoint],_ x0: Float,_ x1: Float)->[[Map3DPoint]] {
            typealias PaintVertex=(point: Map3DPoint,distance: Float)
            let h0=bandHeight(x0),h1=bandHeight(x1)
            let original: [PaintVertex]=triangle.map { p in
                let h=p.x==x0 ? h0:p.x==x1 ? h1:h0+(h1-h0)*(p.x-x0)/(x1-x0)
                let t=max(0,min(1,(p.x-3.7)/7.2)),ease=t*t*(3-2*t)
                let localWidth=dimensions(p.x).1
                let tip=max(0,min(1,(p.x-11)/1.4)),roundTip=tip*tip*(3-2*tip)
                // Blend toward the body-scale width at the end. Normalizing by
                // the tiny cap width pinches the white inset into a small tab.
                let flank=abs(p.z)/(localWidth+0.4*(1.69-localWidth)*roundTip)
                let d=p.y-h-0.62*ease*powf(flank,4)
                let snapped: Float=abs(d)<0.000001 ? 0:abs(d-0.055)<0.000001 ? 0.055:d
                return (p,snapped)
            }
            func cut(_ polygon: [PaintVertex],at level: Float,upper: Bool)->[PaintVertex] {
                var result: [PaintVertex]=[]
                for i in polygon.indices {
                    let a=polygon[i],b=polygon[(i+1)%polygon.count]
                    let ia=upper ? a.distance>=level:a.distance<=level
                    let ib=upper ? b.distance>=level:b.distance<=level
                    if ia { result.append(a) }
                    if ia != ib && a.distance != level && b.distance != level {
                        let p=a.point,q=b.point
                        let before=p.x<q.x || (p.x==q.x && (p.z<q.z || (p.z==q.z && p.y<q.y)))
                        let lo=before ? a:b,hi=before ? b:a
                        let t=(level-lo.distance)/(hi.distance-lo.distance)
                        // Carry the exact isovalue into the next cut. Computing
                        // the nonlinear field again creates extra colour-edge
                        // vertices and T-junctions on very small front faces.
                        result.append((lo.point+(hi.point-lo.point)*t,level))
                    }
                }
                return result
            }
            let upper=cut(original,at:0,upper:true)
            return [cut(upper,at:0.055,upper:true),cut(upper,at:0.055,upper:false),cut(original,at:0,upper:false)].map { $0.map(\.point) }
        }
        for k in 0..<rings.count-1 {
            let h=(dimensions(xs[k]).0+dimensions(xs[k+1]).0)/2
            let inside=Map3DPoint((xs[k]+xs[k+1])/2,(bottom+h)/2,0)
            for i in 0..<segments {
                let j=(i+1)%segments
                let shoulderBand = cab && xs[k]>=3.7
                let teal = shoulderBand ? (20...23).contains(i) || (36...39).contains(i) : [21,22,23,36,37,38].contains(i)
                let color: UInt32 = under.contains(i) ? Self.steel : teal ? refreshTeal:hsrBody
                for triangle in [[rings[k][i],rings[k][j],rings[k+1][j]],[rings[k][i],rings[k+1][j],rings[k+1][i]]] {
                    if cab && xs[k]>=3.7 && !under.contains(i) {
                        let paint=nosePaintParts(triangle,xs[k],xs[k+1])
                        face(paint[0],inside:inside,color:hsrBody)
                        face(paint[1],inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                        let parts=hullParts(paint[2],xs[k],xs[k+1])
                        face(parts.0,inside:inside,color:refreshTeal)
                        face(parts.1,inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                    } else if !under.contains(i) {
                        // Split the final sculpted shell along its shared paint boundary.
                        // No overlapping colour decal or separate lip box.
                        let upper=clip(triangle,at:xs[k],xs[k+1],upper:true)
                        // Preserve the previous triangulation before adding the
                        // fine stripe within its planes.
                        for panel in orientedTriangles(upper,inside:inside) {
                            face(clip(panel,at:xs[k],xs[k+1],upper:true,offset:0.055),inside:inside,color:hsrBody)
                            face(clip(panel,at:xs[k],xs[k+1],upper:false,offset:0.055),inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                        }
                        let parts=hullParts(clip(triangle,at:xs[k],xs[k+1],upper:false),xs[k],xs[k+1])
                        face(parts.0,inside:inside,color:refreshTeal)
                        face(parts.1,inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                    } else {
                        let parts=hullParts(triangle,xs[k],xs[k+1])
                        face(parts.0,inside:inside,color:color)
                        face(parts.1,inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                    }
                }
            }
        }
        for end in [0,rings.count-1] {
            let inside=Map3DPoint(0,2,0),cap=rings[end],x=xs[end]
            if cab && end==rings.count-1 {
                for panel in orientedTriangles(cap,inside:inside) {
                    let paint=nosePaintParts(panel,x,x+1)
                    face(paint[0],inside:inside,color:hsrBody)
                    face(paint[1],inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                    let parts=hullParts(paint[2],x-1,x+1)
                    face(parts.0,inside:inside,color:refreshTeal)
                    face(parts.1,inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                }
                continue
            }
            // Matching subdivisions on the white end caps close the side
            // stripe's new edge vertices; no T-junction is left at the ends.
            for panel in orientedTriangles(cap,inside:inside) {
                face(clip(panel,at:x-1,x+1,upper:false),inside:inside,color:hsrBody)
                let upper=clip(panel,at:x-1,x+1,upper:true)
                for part in orientedTriangles(upper,inside:inside) {
                    face(clip(part,at:x-1,x+1,upper:true,offset:0.055),inside:inside,color:hsrBody)
                    face(clip(part,at:x-1,x+1,upper:false,offset:0.055),inside:inside,color:Map3DTrainShapeRefresh.highSpeedAccentColor)
                }
            }
        }
        if far { refreshHighSpeedFarRunning([-8.8,cab ? 3.4:8.8]) } else { refreshHighSpeedRunning([-8.8,cab ? 3.4:8.8]) }
        box(cab ? -3.7:0,0.92,0,cab ? 17.4:23.8,2.55,0.12,Self.ink)
        func flank(_ h: Float)->Float {
            let s=(h-bottom)/(3.65-bottom)*2-1
            return 1.69*powf(max(0,1-powf(abs(s),2/0.65)),0.58/2)
        }
        if far {
            refreshHighSpeedFarFittings(cab:cab,panto:panto,flank:flank,surface:surface)
            return
        }
        for sign: Float in [-1,1] {
            box(cab ? -3.7:0,0.55,sign*1.42,cab ? 17.4:23.8,0.09,0.67,Self.steel)
            func side(_ x: Float,_ h: Float,_ offset: Float)->Map3DPoint { Map3DPoint(x,h,sign*(flank(h)+offset)) }
            for i in 0..<(cab ? 12:18) {
                let x: Float = -9.3+Float(i)*0.81
                let gasket=refreshRoundedOutline(x: x,y:2.345,width:0.56,height:0.75,radius:0.12)
                refreshPanel(gasket.map { side($0.0,$0.1,0.012) },thickness:0.028,color:Self.ink)
                let pane=refreshRoundedOutline(x:x,y:2.345,width:0.49,height:0.68,radius:0.10)
                refreshPanel(pane.map { side($0.0,$0.1,0.024) },thickness:0.028,color:hsrGlass)
            }
            for x: Float in cab ? [-11,3.1]:[-11,11] {
                let frame=refreshRoundedOutline(x:x,y:2.04,width:0.83,height:1.96,radius:0.11)
                refreshPanel(frame.map { side($0.0,$0.1,0.012) },thickness:0.025,color:Self.steel)
                let leaf=refreshRoundedOutline(x:x,y:2.04,width:0.77,height:1.90,radius:0.09)
                refreshPanel(leaf.map { side($0.0,$0.1,0.024) },thickness:0.035,color:hsrBody)
                let pane=refreshRoundedOutline(x:x,y:2.37,width:0.34,height:0.61,radius:0.07)
                refreshPanel(pane.map { side($0.0,$0.1,0.033) },thickness:0.035,color:hsrGlass)
                box(x+0.25,1.82,sign*(flank(1.82)+0.045),0.07,0.028,0.05,Self.steel)
            }
        }
        if cab {
            // Rounded trapezoidal cockpit mapped onto the real nose surface.
            // Each small prism is backed by that same shell; no billboard box.
            func screen(_ v: Float,_ u: Float)->Map3DPoint {
                let a=Float.pi/2+(u-0.5)*(1.02-0.16*v)
                let corner=max(0,(abs(2*u-1)-0.60)/0.40)
                let cap=sqrtf(max(0,1-corner*corner))
                let rear: Float=8.15+0.36*(1-cap),front: Float=9.78-0.27*(1-cap)
                return surface(rear+(front-rear)*v,a)+Map3DPoint(0,0.018,0)
            }
            for row in 0..<6 { for col in 0..<12 {
                let v=Float(row)/6,u=Float(col)/12
                let p=[screen(v,u),screen(v,u+1/12),screen(v+1/6,u+1/12),screen(v+1/6,u)]
                refreshPanel(p,thickness:0.035,color:hsrGlass)
            } }
            let rim=Map3DColor.shaded(hsrGlass,0.72)
            for c in 0..<12 { for v: Float in [0,1] { beam(screen(v,Float(c)/12),screen(v,Float(c+1)/12),0.025,rim) } }
            for r in 0..<6 { for u: Float in [0,1] { beam(screen(Float(r)/6,u),screen(Float(r+1)/6,u),0.025,rim) } }
            // Upper glazing follows the supported mask instead of reading as
            // one featureless black plate. Small cells follow its curvature.
            let pane=Map3DColor.shaded(Map3DPalette.glazing,0.68)
            func glass(_ v: Float,_ u: Float)->Map3DPoint { screen(0.17+v*0.34,0.13+u*0.74)+Map3DPoint(0,0.012,0) }
            for r in 0..<2 { for c in 0..<8 {
                let v=Float(r)/2,u=Float(c)/8
                refreshPanel([glass(v,u),glass(v,u+1/8),glass(v+1/2,u+1/8),glass(v+1/2,u)],thickness:0.018,color:pane)
            } }
            for c in 0..<8 { for v: Float in [0,1] { beam(glass(v,Float(c)/8),glass(v,Float(c+1)/8),0.018,rim) } }
            for r in 0..<2 { for u: Float in [0,1] { beam(glass(Float(r)/2,u),glass(Float(r+1)/2,u),0.018,rim) } }
            for u: Float in [0.20,0.80] {
                let hand: Float=u<0.5 ? 1:-1
                let base=glass(0.91,u)+Map3DPoint(0,0.014,0)
                let elbow=glass(0.70,u+hand*0.10)+Map3DPoint(0,0.014,0)
                let tip=glass(0.12,u+hand*0.10)+Map3DPoint(0,0.014,0)
                civicTube(glass(0.91,u)-Map3DPoint(0,0.008,0),base+Map3DPoint(0,0.008,0),radius:0.022,color:rim,sides:8)
                beam(base,elbow,0.014,rim);beam(elbow,tip,0.018,rim)
            }
            // Two low lens clusters, two actual warm-white lamps in each.
            for side: Float in [-1,1] {
                let a: Float = side>0 ? 1.34:Float.pi-1.34
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
    /// Decision 422: the far car's bogies, a frame and a side beam each
    /// side over a six-sided wheelset at each axle; the N700S-G's far
    /// cars stand on them too, its axles where the author's stood.
    mutating func refreshHighSpeedFarRunning(_ centres: [Float],axles: [Float] = [-1.25,1.25]) {
        let gauge: Float=1.435,radius: Float=0.40,span=axles.last!-axles.first!
        for x in centres {
            box(x,0.49,0,span+0.8,gauge+0.22,0.25,Self.ink)
            for side: Float in [-1,1] { box(x,0.48,side*(gauge/2+0.22),span+0.74,0.16,0.23,Self.steel) }
            for dx in axles {
                civicTube(Map3DPoint(x+dx,radius,-(gauge/2+0.15)),Map3DPoint(x+dx,radius,gauge/2+0.15),radius:radius,color:Map3DStreetModel.tyre,sides:6)
            }
        }
    }
    /// Decision 422: the far car's skirt, glass, doors, windscreen, lamps,
    /// gangway and pantograph, each a flat face where the near car's are
    /// framed panels: a side window one pane the size of its gasket, a
    /// door its window, the windscreen three rows of six
    /// cells and its upper glazing four, a lamp cluster one lens.
    private mutating func refreshHighSpeedFarFittings(cab: Bool,panto: Bool,flank: (Float)->Float,surface: (Float,Float)->Map3DPoint) {
        let hsrGlass=Map3DTrainShapeRefresh.highSpeedGlassColor,centre=Map3DPoint(0,2,0)
        for sign: Float in [-1,1] {
            box(cab ? -3.7:0,0.55,sign*1.42,cab ? 17.4:23.8,0.09,0.67,Self.steel)
            func side(_ x: Float,_ h: Float)->Map3DPoint { Map3DPoint(x,h,sign*(flank(h)+0.024)) }
            for i in 0..<(cab ? 12:18) {
                let x: Float = -9.3+Float(i)*0.81
                face([side(x-0.28,1.97),side(x+0.28,1.97),side(x+0.28,2.72),side(x-0.28,2.72)],inside:centre,color:hsrGlass)
            }
            for x: Float in cab ? [-11,3.1]:[-11,11] {
                face([side(x-0.17,2.065),side(x+0.17,2.065),side(x+0.17,2.675),side(x-0.17,2.675)],inside:centre,color:hsrGlass)
            }
        }
        if cab {
            func screen(_ v: Float,_ u: Float)->Map3DPoint {
                let a=Float.pi/2+(u-0.5)*(1.02-0.16*v)
                let corner=max(0,(abs(2*u-1)-0.60)/0.40)
                let cap=sqrtf(max(0,1-corner*corner))
                let rear: Float=8.15+0.36*(1-cap),front: Float=9.78-0.27*(1-cap)
                return surface(rear+(front-rear)*v,a)+Map3DPoint(0,0.018,0)
            }
            for row in 0..<3 { for col in 0..<6 {
                let v=Float(row)/3,u=Float(col)/6
                face([screen(v,u),screen(v,u+1/6),screen(v+1/3,u+1/6),screen(v+1/3,u)],inside:centre,color:hsrGlass)
            } }
            let pane=Map3DColor.shaded(Map3DPalette.glazing,0.68)
            func glass(_ v: Float,_ u: Float)->Map3DPoint { screen(0.17+v*0.34,0.13+u*0.74)+Map3DPoint(0,0.012,0) }
            for c in 0..<4 {
                let u=Float(c)/4
                face([glass(0,u),glass(0,u+1/4),glass(1,u+1/4),glass(1,u)],inside:centre,color:pane)
            }
            for side: Float in [-1,1] {
                let a: Float = side>0 ? 1.34:Float.pi-1.34
                let middle=surface(9.34,a)+Map3DPoint(0,0.041,0)
                let along=Map3DPoint(0,0,side*0.26),across=(surface(9.49,a)-surface(9.19,a)).normalized!*0.075
                face([middle-along-across,middle+along-across,middle+along+across,middle-along+across],inside:centre,color:Map3DPalette.tunnelLamp)
            }
        }
        for end: Float in cab ? [-1]:[-1,1] {
            // The gangway's end and the coupler, so the car is as long as the near one.
            box(end*12.58,1.05,0,0.18,2.15,2.07,Self.ink)
            box(end*12.58,0.66,0,0.32,0.35,0.3,Self.steel)
        }
        if panto {
            // One arm over the base, its head across: the single-arm
            // pantograph as it reads from afar.
            let x: Float=6.8,roof: Float=3.65
            box(x,roof,0,1.8,1.15,0.12,Self.steel)
            beam(Map3DPoint(x-0.45,roof+0.28,0),Map3DPoint(x+0.65,roof+0.58,0),0.07,Self.ink)
            beam(Map3DPoint(x+0.65,roof+0.58,0),Map3DPoint(x,roof+0.90,0),0.06,Self.ink)
            box(x,roof+0.88,0,0.16,1.5,0.07,Self.steel)
        }
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
