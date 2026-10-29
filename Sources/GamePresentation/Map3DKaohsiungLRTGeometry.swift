import Foundation

// Dimension-free geometry operations, used only by the two new KLRT studies.
// No vehicle profile, door layout, equipment position or livery lives here.
struct KLRTGeometry {
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
