import Foundation

// Dimension-free surface operations adapted from Codex KLRT producer cfeed799. Used only by new Taipei studies.
// No vehicle profile, door layout, equipment position or livery lives here.
struct NTLRTSurface {
    var b = StationKitBuilder()
    typealias UV = SIMD2<Float>
    struct Patch { var points: [UV]; var color: UInt32 }

    static func clip(_ p: [UV], _ a: UV, _ b: UV, inside: Bool) -> [UV] {
        func distance(_ v: UV) -> Float { (b.x-a.x)*(v.y-a.y)-(b.y-a.y)*(v.x-a.x) }
        var out: [UV] = []
        for i in p.indices {
            let v=p[i], w=p[(i+1)%p.count], d=distance(v), e=distance(w)
            let keep = inside ? d >= 0 : d <= 0, next = inside ? e >= 0 : e <= 0
            if keep { out.append(v) }
            if keep != next { out.append(v+(w-v)*(d/(d-e))) }
        }
        var clean: [UV] = []
        for v in out {
            if let last=clean.last, abs(last.x-v.x)+abs(last.y-v.y)<0.00003 { continue }
            clean.append(v)
        }
        if clean.count>1, let a=clean.first, let z=clean.last, abs(a.x-z.x)+abs(a.y-z.y)<0.00003 { clean.removeLast() }
        guard clean.count>=3 else { return [] }
        var area: Float=0
        for i in clean.indices { let a=clean[i], b=clean[(i+1)%clean.count];area += a.x*b.y-a.y*b.x }
        return abs(area)>0.0000001 ? clean : []
    }
    // A convex colour region cuts the physical surface. No overlaid colour mesh.
    static func paint(_ patches: [Patch], polygon: [UV], color: UInt32) -> [Patch] {
        var result: [Patch] = []
        for patch in patches {
            var intersection=patch.points
            for i in polygon.indices {
                intersection=clip(intersection,polygon[i],polygon[(i+1)%polygon.count],inside:true)
                if intersection.isEmpty { break }
            }
            // A region outside this piece must not extend all of its edge lines
            // across the rest of the shell (quadratic, invisible tessellation).
            if intersection.isEmpty { result.append(patch);continue }
            var remaining=patch.points
            for i in polygon.indices {
                if remaining.isEmpty { break }
                let a=polygon[i], z=polygon[(i+1)%polygon.count]
                let outside=clip(remaining,a,z,inside:false)
                if !outside.isEmpty { result.append(Patch(points:outside,color:patch.color)) }
                remaining=clip(remaining,a,z,inside:true)
            }
            if !remaining.isEmpty { result.append(Patch(points:remaining,color:color)) }
        }
        return result
    }
    static func rectangle(_ x0: Float,_ x1: Float,_ y0: Float,_ y1: Float) -> [UV] {
        [UV(x0,y0),UV(x1,y0),UV(x1,y1),UV(x0,y1)]
    }
    static func ellipse(_ x: Float,_ y: Float,_ rx: Float,_ ry: Float, sides: Int) -> [UV] {
        (0..<sides).map { i in let a=Float(i)*2*Float.pi/Float(sides); return UV(x+rx*cosf(a),y+ry*sinf(a)) }
    }
    static func lerp(_ x: Float,_ ks: [Float],_ vs: [Float]) -> Float {
        if x<=ks[0] { return vs[0] }
        for i in 0..<(ks.count-1) where x<=ks[i+1] { return vs[i]+(vs[i+1]-vs[i])*(x-ks[i])/(ks[i+1]-ks[i]) }
        return vs.last!
    }
    mutating func face(_ p: [Map3DPoint], inside: Map3DPoint, color: UInt32) {
        guard p.count>=3 else { return }
        // Individual triangles avoid fan diagonals starting with collinear points.
        for i in 1..<(p.count-1) {
            let q=[p[0],p[i],p[i+1]],n=(q[1]-q[0]).cross(q[2]-q[0])
            guard n.length>0.00000002 else { continue }
            let c=(q[0]+q[1]+q[2])*(1/3)
            b.mesh.addFacet(n.dot(c-inside)>0 ? q : Array(q.reversed()),color:color)
        }
    }
    mutating func slab(_ p: [Map3DPoint], inward: Map3DPoint, color: UInt32, backing: UInt32) {
        let back=p.map { $0+inward }, c=(p+back).reduce(.zero,+)*(1/Float(p.count*2))
        face(p,inside:c,color:color);face(back,inside:c,color:backing)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],back[i],back[j],p[j]],inside:c,color:backing) }
    }
    // Clip in parameter space, interpolate within each original planar triangle.
    mutating func surface(_ uv: [UV], map: (UV)->Map3DPoint, inward: Map3DPoint,
                          base: UInt32, regions: [([UV],UInt32)], backing: UInt32, planar: Bool = false) {
        let cells=planar ? [uv] : (1..<(uv.count-1)).map { [uv[0],uv[$0],uv[$0+1]] }
        for q in cells {
            let p=q.map(map)
            var patches=[Patch(points:q,color:base)]
            for (poly,c) in regions { patches=Self.paint(patches,polygon:poly,color:c) }
            let a=q[1]-q[0],z=q[2]-q[0],det=a.x*z.y-a.y*z.x
            guard abs(det)>0.00000001 else { continue }
            for patch in patches {
                let points=patch.points.map { v -> Map3DPoint in
                    let d=v-q[0],s=(d.x*z.y-d.y*z.x)/det,t=(a.x*d.y-a.y*d.x)/det
                    return p[0]+(p[1]-p[0])*s+(p[2]-p[0])*t
                }
                slab(points,inward:inward,color:patch.color,backing:patch.color == Map3DTrainStyle.glass ? Map3DColor.shaded(patch.color,0.28) : patch.color)
            }
        }
    }
    mutating func box(_ x: Float,_ h: Float,_ w: Float,_ length: Float,_ width: Float,_ height: Float,_ color: UInt32) {
        b.box(x,h,w,length,width,height,color)
    }
    mutating func wheel(_ x: Float,_ w: Float,radius: Float,sides: Int,color: UInt32) {
        b.civicTube(Map3DPoint(x,radius,w-0.055),Map3DPoint(x,radius,w+0.055),radius:radius,color:color,sides:sides)
    }
    // Closed bellows sleeve segments. No passenger-car coupler or invented axle.
    mutating func bellows(_ x: Float, direction: Float, length: Float, width: Float, bottom: Float, top: Float, folds: Int, color: UInt32) {
        for i in 0..<folds {
            let step=length/Float(folds),a=x+direction*Float(i)*step,z=x+direction*Float(i+1)*step
            let mid=(a+z)/2,half=step/2
            box(mid,bottom,0,half*2,width,top-bottom,color)
            box(mid,bottom+0.025,0,half,width+0.07,top-bottom-0.05,Map3DColor.shaded(color,1.18))
        }
    }
}

// Official common dimensions and main design, cross-checked against photographs.
// These are display surfaces, not interchangeable manufacturing parts. Undocumented
// contours and equipment dimensions remain explicit photo estimates in sources.json.
struct NTLRTBody {
    typealias G = NTLRTSurface
    typealias UV = SIMD2<Float>
    static let ink = StationKitBuilder.ink
    static let glass = Map3DTrainStyle.glass
    static func blend(_ a: UInt32,_ b: UInt32,_ t: Float) -> UInt32 {
        var c: UInt32=0xFF000000
        for shift in [0,8,16] { c |= UInt32(Float((a >> shift)&255)*(1-t)+Float((b >> shift)&255)*t) << shift }
        return c
    }
    static let roof: Float = 3.35
    static let hs: [Float] = [0.25,0.40,0.65,0.95,1.40,2.0,2.6,2.98,3.08,3.20,3.28,3.35]
    static let rake: [Float] = [0.16,0.035,0,0.035,0.14,0.35,0.65,0.91,1.01,1.13,1.22,1.30]
    static func width(_ h: Float) -> Float {
        G.lerp(h, [0.25,0.4,2.98,3.08,3.2,3.28,3.35], [1.18,1.325,1.325,1.30,1.24,1.17,1.07])
    }
    static func front(_ half: Float,_ w: Float,_ h: Float) -> Map3DPoint {
        Map3DPoint(half-G.lerp(h,hs,rake)-0.20*powf(abs(w)/1.325,4),h,w)
    }
    static func model(id: String, length: Float, role: String, far: Bool, sea: Bool, body: UInt32) -> Map3DModelPack.Model {
        var g=G(); let half=length/2, cab=role == "m1" || role == "m5"
        let suspended=role == "m2" || role == "m4"
        let white=Map3DPalette.shopAwnings[3], steel=Map3DPalette.rollerDoor
        let end=cab ? half-1.5 : half
        let bays: [(Float,Float)] = cab ? [(-2.45,2.30),(2.05,0.85)] : suspended
            ? (role == "m2" ? [(0.60,2.85)] : [(-0.60,2.85)]) : [(0,3.65)]
        let doors: [Float] = cab ? [0.0] : role == "m2" ? [-1.85] : role == "m4" ? [1.85] : []
        for side: Float in [-1,1] {
            var regions: [([UV],UInt32)] = []
            // Original standard sea livery: blue cab, white lower saloon panels,
            // discrete blue wave marks and shoulder dots, all cut into the shell.
            if sea {
                regions.append((G.rectangle(-half,end,0.35,1.08),white))
                for k in 0..<(far ? 3 : 7) {
                    let x = -half+0.28+Float(k)*(end+half-0.56)/Float(far ? 3 : 7)
                    regions.append(([UV(x,0.48),UV(x+0.55,0.57),UV(x+0.8,0.72),UV(x+0.25,0.62)],body))
                }
            }
            regions.append((G.rectangle(-half,end,1.07,2.98),ink))
            for (x,w) in bays {
                regions.append((G.rectangle(max(-half+0.12,x-w/2),min(end-0.06,x+w/2),1.16,2.82),glass))
            }
            for (x,w) in bays where w>2.25 { regions.append((G.rectangle(x-0.025,x+0.025,1.07,2.98),ink)) }
            if sea {
                for k in 0..<(far ? 3 : 5) { let x = -half+0.25+Float(k)*(end+half-0.5)/Float(far ? 3 : 5)
                    regions.append((G.ellipse(x,3.10,0.16,0.055,sides:8),body))
                }
            }
            for x in doors {
                regions.append((G.rectangle(x-0.72,x+0.72,0.35,2.97),ink))
                for s: Float in [-1,1] {
                    regions.append((G.rectangle(x+s*0.345-0.315,x+s*0.345+0.315,0.48,2.80),glass))
                }
                regions.append((G.rectangle(x-0.68,x+0.68,0.35,0.40),steel))
                if !far { regions.append((G.ellipse(x+0.57,1.24,0.035,0.035,sides:8),Map3DPalette.platformEdge)) }
            }
            if sea && cab { regions.append((G.rectangle(1.5,end,0.25,1.08),body)) }
            // Side face follows the actual shoulder cross section; glass occupies
            // the surface itself, with a closed 24mm backing, never an overlay.
            let sideHeights: [Float] = far ? (cab ? [0.25,0.40,0.65,1.4,2.6,2.98,3.20,3.35] : [0.25,0.40,2.98,3.20,3.35]) : hs
            for j in 0..<(sideHeights.count-1) {
                let h0=sideHeights[j],h1=sideHeights[j+1]
                g.surface(G.rectangle(-half,end,h0,h1),map:{ uv in Map3DPoint(uv.x,uv.y,side*width(uv.y)) },
                          inward:Map3DPoint(0,0,-side*0.024),base:sea && h0>=2.98 ? white : body,regions:regions,backing:body,planar:true)
                if cab {
                    let uv=G.rectangle(0,1,h0,h1)
                    let paint: [([UV],UInt32)] = [ (G.rectangle(0,1,1.07,2.98),ink),
                        ([UV(0.03,1.18),UV(0.95,1.18),UV(0.95,2.80),UV(0.03,2.80)],glass)]
                    g.surface(uv,map:{ v in
                        let w=side*width(v.y),p=front(half,w,v.y)
                        return Map3DPoint(end+(p.x-end)*v.x,v.y,w)
                    },inward:Map3DPoint(0,0,-side*0.024),base:body,regions:paint,backing:body)
                }
            }
        }
        // Roof plus floor are narrow thin solids. The floor is above the wheel
        // envelope only at the bogie enclosure; no cross-axle through the aisle.
        let roofEnd=cab ? half-1.5 : half
        g.box((-half+roofEnd)/2,roof-0.024,0,roofEnd+half,2.14,0.024,sea ? white : body)
        // Keep the hidden cab floor behind the coarser far nose as well as
        // the near shell. A full-length plate pierced the far lower corners.
        let floorBack = -half+0.06, floorFront = half-(cab ? 0.25 : 0.06)
        g.box((floorBack+floorFront)/2,0.65,0,floorFront-floorBack,1.62,0.055,ink)
        if cab {
            var patches: [([UV],UInt32)] = []
            let mask=[UV(-0.46,0.83),UV(0.46,0.83),UV(0.78,0.90),UV(0.98,1.06),UV(1.10,1.3),UV(1.10,2.95),UV(-1.10,2.95),UV(-1.10,1.3),UV(-0.98,1.06),UV(-0.78,0.90)]
            let pane=[UV(-0.48,1.12),UV(0.48,1.12),UV(0.80,1.20),UV(0.99,1.45),UV(1.02,2.82),UV(-1.02,2.82),UV(-0.99,1.45),UV(-0.80,1.20)]
            patches += [(mask,ink),(pane,glass)]
            for side: Float in [-1,1] {
                for k in 0..<3 {
                    let w=side*(0.63+Float(k)*0.14),h:Float=0.98+Float(k)*0.045
                    patches.append((G.ellipse(w,h,0.047,0.047,sides:far ? 6 : 16),Map3DTrainStyle.headlamp))
                }
                patches.append((G.ellipse(side*0.73,0.60,0.046,0.046,sides:far ? 6 : 16),Map3DTrainStyle.headlamp))
                patches.append((G.ellipse(side*0.73,0.34,0.035,0.035,sides:8),Map3DPalette.lantern))
            }
            patches.append((G.ellipse(0,3.05,0.037,0.037,sides:8),Map3DTrainStyle.headlamp))
            let ws: [Float] = far ? [-1,-0.8,0,0.8,1] : (0...10).map { -1+Float($0)/5 }
            let frontHeights: [Float] = far ? [0.25,0.40,0.65,1.4,2.6,2.98,3.20,3.35] : hs
            for j in 0..<(frontHeights.count-1) { for i in 0..<(ws.count-1) {
                let u0=ws[i],u1=ws[i+1],h0=frontHeights[j],h1=frontHeights[j+1]
                g.surface(G.rectangle(u0,u1,h0,h1),map:{ v in front(half,v.x*width(v.y),v.y) },
                          inward:Map3DPoint(-0.024,0,0),base:body,
                          regions:patches.map { poly,c in (poly.map { UV($0.x/1.325,$0.y) },c) },backing:body)
            }}
            // Close the short crown bridge to the cab front. No end wall at
            // the four passenger gangways; they retain a 1.41m clear passage.
            g.slab([Map3DPoint(end,roof,-1.07),front(half,-1.07,roof),front(half,1.07,roof),Map3DPoint(end,roof,1.07)],inward:Map3DPoint(0,-0.024,0),color:body,backing:body)
            if !far {
                g.b.beam(front(half,-0.18,1.16)+Map3DPoint(0.035,0,0),front(half,0.45,2.06)+Map3DPoint(0.035,0,0),0.018,ink)
            }
        }
        if !suspended {
            let bx: Float = cab ? -1.55 : 0
            g.box(bx,0.35,0,2.18,1.25,0.23,ink)
            for dx: Float in [-0.83,0.83] { for side: Float in [-1,1] {
                g.wheel(bx+dx,side*0.7175,radius:0.29,sides:far ? 8 : 20,color:Map3DStreetModel.tyre)
                if !far { g.b.civicTube(Map3DPoint(bx+dx,0.29,side*0.77),Map3DPoint(bx+dx,0.29,side*0.779),radius:0.13,color:steel,sides:12) }
            }}
        }
        // Four open bellows sleeves belong to inward ends of M1/2/4/5.
        let joint: Float? = cab ? -half : role == "m2" ? -half : role == "m4" ? half : nil
        if let x=joint {
            let sign: Float = x<0 ? -1 : 1
            for k in 0..<(far ? 3 : 7) {
                let n: Float = far ? 3 : 7,step:Float=0.5/n
                let at=x+sign*(Float(k)+0.5)*step
                let w:Float=k%2 == 0 ? 2.53 : 2.47
                for side: Float in [-1,1] { g.box(at,0.35,side*(w/2-0.025),step,w == 2.53 ? 0.05 : 0.04,2.85,steel) }
                g.box(at,3.15,0,step,w,0.05,steel);g.box(at,0.35,0,step,1.41,0.04,ink)
            }
        }
        // Visible equipment layout: HVAC on each end, storage on suspended
        // modules, one central pantograph with two collector strips. Hidden
        // cabling and exact housing subdivisions are simplified.
        if cab {
            g.box(-0.5,roof,0,3.10,1.63,0.27,steel)
            // ABB published Danhai CC400: 1.70 x 1.60 x 0.45m overall.
            // Display cover uses 0.40m above deck (mount/interface omitted).
            // Ankeng part revision is unverified; same approximate family envelope.
            g.box(-2.90,roof,0,1.70,1.60,0.40,steel)
        } else if suspended {
            g.box(0,roof,0,4.85,1.66,0.14,steel)
            for x: Float in [-1.55,0,1.55] { g.box(x,roof+0.14,0,1.48,1.58,0.16,steel) }
        } else {
            g.box(0,roof,0,2.7,1.38,0.11,steel)
            g.box(0,roof+0.11,0,1.6,1.02,0.09,ink)
            for side: Float in [-1,1] {
                g.b.beam(Map3DPoint(-0.7,3.55,side*0.40),Map3DPoint(0.75,3.94,side*0.17),0.045,ink)
                g.b.beam(Map3DPoint(0.75,3.94,side*0.17),Map3DPoint(-0.10,4.32,side*0.60),0.035,ink)
            }
            for x: Float in [-0.24,0.04] { g.box(x,4.32,0,0.055,1.55,0.035,steel) }
        }
        if !far {
            let gx: [Float] = cab ? [-1.4,-0.8,-0.2,0.4] : suspended ? [-1.8,-1.2,-0.6,0,0.6,1.2,1.8] : []
            for x in gx { g.box(x, cab ? 3.62 : 3.65,0,0.075,1.38,0.012,ink) }
        }
        return .flat(named:id,from:g.b.mesh)
    }
}
