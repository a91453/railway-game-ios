import Foundation

/// C381 standard six-car static study; cab is 23.710 m between coupling faces.
public enum Map3DC381 {
    public enum Unit: String, CaseIterable, Sendable { case dm, t, m, rear }
    public static let arrangement: [Unit] = [.dm,.t,.m,.m,.t,.rear]
    public static let lengths: [Float] = [23.710,23.5,23.5,23.5,23.5,23.710]
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        if unit == .rear {
            let first=model(.dm)
            var b=StationKitBuilder();b.add(first,at:.zero,angle:.pi)
            return .flat(named:"c381-rear",from:b.mesh)
        }
        var b=MetroStudyGeometry(cab:unit == .dm,trailer:unit == .t,curved:true,length:unit == .dm ? 23.710 : 23.5,body:Map3DPalette.counters[2],blue:Map3DPalette.containers[1])
        b.build()
        return .flat(named:"c381-"+unit.rawValue,from:b.kit.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        let centres: [Float] = [58.855,35.25,11.75,-11.75,-35.25,-58.855]
        for (i,u) in arrangement.enumerated() { b.add(model(u),at:Map3DPoint(centres[i],0,0)) }
        return .flat(named:"c381-formation",from:b.mesh)
    }
}

// C381-specific surface stations and fascia: the C371 recipe is not reused.
extension MetroStudyGeometry {
    func c381FaceX(_ h: Float,_ z: Float) -> Float {
        func sample(_ x: Float,_ knots: [Float],_ values: [Float]) -> Float {
            if x <= knots[0] { return values[0] }
            for i in 0..<(knots.count-1) where x <= knots[i+1] {
                return values[i]+(values[i+1]-values[i])*(x-knots[i])/(knots[i+1]-knots[i])
            }
            return values[values.count-1]
        }
        let lateral=sample(abs(z),[0,0.40,0.80,1.20,1.55],[0.18,0.175,0.15,0.065,-0.05])
        let vertical=sample(h,[0.60,0.95,1.40,2.10,2.75,3.20,3.60],[0.02,0.05,0.10,0.12,0.10,0.06,0])
        return half-0.14+lateral+vertical
    }
    /// Closed layered patches, split at every surface-plane boundary before
    /// triangulation, so the black mask and glass cannot cross their backing.
    mutating func c381Patch(_ polygon: [(Float,Float)],_ color: UInt32,lift: Float = 0,thickness: Float = 0.035) {
        let hs: [Float] = [0.50,0.60,0.95,1.40,2.10,2.75,3.20,3.60]
        let zs: [Float] = [-1.55,-1.20,-0.80,-0.40,0,0.40,0.80,1.20,1.55]
        func clip(_ p: [(Float,Float)],_ axis: Int,_ limit: Float,_ greater: Bool) -> [(Float,Float)] {
            func value(_ q: (Float,Float)) -> Float { axis == 0 ? q.0 : q.1 }
            var out: [(Float,Float)] = []
            func append(_ q: (Float,Float)) {
                if let last=out.last, abs(last.0-q.0)+abs(last.1-q.1)<0.000001 { return }
                out.append(q)
            }
            for i in p.indices {
                let a=p[i],b=p[(i+1)%p.count],va=value(a),vb=value(b)
                let ia=greater ? va>=limit : va<=limit,ib=greater ? vb>=limit : vb<=limit
                if ia { append(a) }
                if ia != ib {
                    let t=(limit-va)/(vb-va)
                    if t>0 && t<1 { append((a.0+t*(b.0-a.0),a.1+t*(b.1-a.1))) }
                }
            }
            if out.count>1,let a=out.first,let b=out.last,abs(a.0-b.0)+abs(a.1-b.1)<0.000001 { out.removeLast() }
            return out
        }
        func point(_ p: (Float,Float),_ offset: Float) -> Map3DPoint {
            Map3DPoint(c381FaceX(p.0,p.1)+lift+offset,p.0,p.1)
        }
        for i in 0..<(hs.count-1) { for j in 0..<(zs.count-1) {
            var p=clip(clip(polygon,0,hs[i],true),0,hs[i+1],false)
            p=clip(clip(p,1,zs[j],true),1,zs[j+1],false)
            if p.count<3 { continue }
            let centre=p.map { point($0,-thickness/2) }.reduce(.zero,+)*(1/Float(p.count))
            kit.face(p.map { point($0,0) },inside:centre,color:color)
            kit.face(p.map { point($0,-thickness) },inside:centre,color:color)
        } }
        let centre=polygon.map { point($0,-thickness/2) }.reduce(.zero,+)*(1/Float(polygon.count))
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count]
            var ts: [Float] = [0,1]
            if a.0 != b.0 { ts += hs.map { ($0-a.0)/(b.0-a.0) }.filter { $0>0 && $0<1 } }
            if a.1 != b.1 { ts += zs.map { ($0-a.1)/(b.1-a.1) }.filter { $0>0 && $0<1 } }
            ts.sort();var unique: [Float] = []
            for t in ts where unique.last.map({abs($0-t)>0.000001}) ?? true { unique.append(t) }
            for j in 0..<(unique.count-1) {
                func at(_ t: Float) -> (Float,Float) { (a.0+t*(b.0-a.0),a.1+t*(b.1-a.1)) }
                let u=at(unique[j]),v=at(unique[j+1])
                kit.face([point(u,0),point(v,0),point(v,-thickness),point(u,-thickness)],inside:centre,color:color)
            }
        }
    }
    mutating func c381SideBands() {
        for sign: Float in [-1,1] { for fine in [false,true] {
            let stations: [Float] = cab ? [-half,half-1.05,half-0.52,half] : [-half,half]
            var rings: [[Map3DPoint]] = []
            for x in stations {
                let t=cab ? max(0,(x-(half-1.05))/1.05) : 0
                let low: Float = fine ? 1.17 : 1.43+t*0.05
                let high: Float = fine ? 1.22 : 1.73+t*0.01
                let z=sign*(1.59*(1-t*0.025)+0.018)
                let xx=x-t*0.12
                rings.append([Map3DPoint(xx,low,z),Map3DPoint(xx,high,z),Map3DPoint(xx,high,z-sign*0.020),Map3DPoint(xx,low,z-sign*0.020)])
            }
            if cab {
                let low: Float = fine ? 1.17 : 1.48, high: Float = fine ? 1.22 : 1.74
                let z=sign*1.55,lift: Float = fine ? 0.060 : 0.055
                rings.append([Map3DPoint(c381FaceX(low,z)+lift,low,z+sign*0.018),Map3DPoint(c381FaceX(high,z)+lift,high,z+sign*0.018),Map3DPoint(c381FaceX(high,z)+lift,high,z-sign*0.002),Map3DPoint(c381FaceX(low,z)+lift,low,z-sign*0.002)])
            }
            for i in 0..<(rings.count-1) { prism(rings[i],rings[i+1],blue) }
        } }
    }
    mutating func buildC381Cab() {
        let outerBrow=(-16...16).map { i -> (Float,Float) in
            let a=Float(i)*Float.pi/32
            return (3.17+0.415*cosf(a),1.55*sinf(a))
        }
        c381Patch([(0.98,-1.43),(1.08,-1.54)]+outerBrow+[(1.08,1.54),(0.98,1.43)],body,lift:-0.015,thickness:0.18)
        let maskBrow=(-16...16).map { i -> (Float,Float) in
            let a=Float(i)*Float.pi/32
            return (3.18+0.385*cosf(a),1.46*sinf(a))
        }
        c381Patch([(1.94,-1.23),(1.98,-1.39),(2.11,-1.46)]+maskBrow+[(2.11,1.46),(1.98,1.39),(1.94,1.23)],ink)
        // Full-height escape door, silver lower leaf and a distinct centre pane.
        c381Patch(roundRect(-0.54,0.54,1.07,3.27,0.085),Map3DColor.shaded(steel,0.55),lift:0.020)
        c381Patch(roundRect(-0.522,0.522,1.09,3.25,0.075),ink,lift:0.039)
        c381Patch(roundRect(-0.50,0.50,1.105,1.98,0.055),body,lift:0.051)
        c381Patch(roundRect(-0.44,0.44,2.00,3.15,0.09),glass,lift:0.061)
        for sign: Float in [-1,1] {
            let l: Float = sign<0 ? -1.37 : 0.60, r: Float = sign<0 ? -0.60 : 1.37
            let frame=roundRect(l,r,2.00,3.16,0.13).map { h,z in (h,z-sign*0.045*max(0,min(1,(h-2)/1.16))) }
            c381Patch(frame,Map3DColor.shaded(body,0.63),lift:0.025)
            let pane=roundRect(l+0.018,r-0.018,2.018,3.142,0.115).map { h,z in (h,z-sign*0.045*max(0,min(1,(h-2)/1.16))) }
            c381Patch(pane,glass,lift:0.043)
            c381Patch([(2.93,l+0.06),(2.93,r-0.08),(2.96,r-0.08),(2.96,l+0.06)],Map3DPalette.shopAwnings[0],lift:0.066)
            if sign>0 { c381Patch(roundRect(l+0.04,r-0.08,3.00,3.12,0.025),Map3DColor.shaded(glass,0.55),lift:0.065) }
            let footZ=sign*1.12,tipZ=sign*0.72
            kit.beam(Map3DPoint(c381FaceX(1.99,footZ)+0.050,1.99,footZ),Map3DPoint(c381FaceX(2.48,tipZ)+0.050,2.48,tipZ),0.016,ink)
        }
        // Feathered main wings and the independent thin lower stripe.
        let spans: [Float] = [-1.55,-1.30,-1.10,-0.85,-0.65,-0.45,-0.25,0,0.25,0.45,0.65,0.85,1.10,1.30,1.55]
        func boundaries(_ z: Float,_ fine: Bool) -> (Float,Float) {
            let t=abs(z)/1.55,curve=1-(1-t)*(1-t)
            if fine { let low: Float = 1.075+0.095*curve;return (low,low+0.05) }
            return (1.14+0.34*curve,1.18+0.56*curve)
        }
        for fine in [false,true] { for i in 0..<(spans.count-1) {
            let a=spans[i],b=spans[i+1],u=boundaries(a,fine),v=boundaries(b,fine)
            c381Patch([(u.0,a),(v.0,b),(v.1,b),(u.1,a)],blue,lift:fine ? 0.060 : 0.055,thickness:0.025)
        } }
        // Rounded lamp recesses; lenses follow the final surface rather than
        // being cylinders floating ahead of a curved nose.
        func circle(_ h: Float,_ z: Float,_ radius: Float) -> [(Float,Float)] {
            (0..<16).map { i in let a=Float(i)*Float.pi/8;return (h+radius*sinf(a),z+radius*cosf(a)) }
        }
        func cut(_ p: [(Float,Float)],_ field: ((Float,Float)) -> Float) -> [(Float,Float)] {
            var out: [(Float,Float)] = []
            for i in p.indices {
                let a=p[i],b=p[(i+1)%p.count],u=field(a),v=field(b)
                if u>=0 { out.append(a) }
                if (u>=0) != (v>=0) { let t=u/(u-v);if t>0 && t<1 { out.append((a.0+t*(b.0-a.0),a.1+t*(b.1-a.1))) } }
            }
            return out
        }
        for sign: Float in [-1,1] {
            let z=sign*1.00
            c381Patch(roundRect(z-0.355,z+0.355,1.30,1.71,0.115),ink,lift:0.064,thickness:0.10)
            let recess=roundRect(z-0.341,z+0.341,1.314,1.696,0.101)
            // The clear real lamp cover shows the blue/white livery behind it.
            // Split its opaque toy-style backing on the very same boundaries.
            for i in 0..<(spans.count-1) {
                let a=spans[i],b=spans[i+1]
                let piece=cut(cut(recess,{$0.1-a}),{b-$0.1})
                if piece.count<3 { continue }
                let u=boundaries(a,false),v=boundaries(b,false)
                func low(_ p: (Float,Float)) -> Float { p.0-(u.0+(v.0-u.0)*(p.1-a)/(b-a)) }
                func high(_ p: (Float,Float)) -> Float { p.0-(u.1+(v.1-u.1)*(p.1-a)/(b-a)) }
                let bluePart=cut(cut(piece,low),{-high($0)})
                let bottom=cut(piece,{-low($0)}),top=cut(piece,high)
                for q in [bottom,top] where q.count>=3 { c381Patch(q,Map3DColor.shaded(body,0.78),lift:0.074,thickness:0.025) }
                if bluePart.count>=3 { c381Patch(bluePart,blue,lift:0.074,thickness:0.025) }
            }
            for offset: Float in [-0.16,0.16] {
                let zz=z+offset
                c381Patch(circle(1.50,zz,0.126),steel,lift:0.087,thickness:0.025)
                c381Patch(circle(1.50,zz,0.106),offset*sign>0 ? Map3DColor.rgb(0xD9473F) : Map3DPalette.tunnelLamp,lift:0.099,thickness:0.020)
                if offset*sign>0 { c381Patch(circle(1.50,zz,0.080),ink,lift:0.110,thickness:0.020) }
            }
            c381Patch(circle(3.35,sign*1.18,0.060),steel,lift:0.028,thickness:0.030)
            c381Patch(circle(3.35,sign*1.18,0.043),Map3DPalette.tunnelLamp,lift:0.040,thickness:0.025)
        }
        c381Patch(roundRect(-0.070,0.070,3.35,3.47,0.015),Map3DColor.rgb(0xD9473F),lift:0.040)
        // Split FRP apron leaves a real coupler opening; brackets meet floor.
        for sign: Float in [-1,1] {
            let l: Float = sign<0 ? -1.48 : 0.38, r: Float = sign<0 ? -0.38 : 1.48
            c381Patch(roundRect(l,r,0.55,0.97,0.075),body,lift:0.040,thickness:0.18)
            kit.box(half-0.16,0.70,sign*0.96,0.22,0.20,0.25,ink)
        }
        c381Patch([(0.905,-1.43),(0.905,1.43),(1.04,1.43),(1.04,-1.43)],ink,lift:0.066,thickness:0.17)
        for h: Float in [0.920,0.960,1.000] { c381Patch([(h,-1.43),(h,1.43),(h+0.014,1.43),(h+0.014,-1.43)],Map3DColor.shaded(steel,0.48),lift:0.081,thickness:0.025) }
        kit.box(half-0.10,0.70,0,0.30,0.32,0.30,ink)
        kit.box(half+0.21,0.64,0,0.13,0.22,0.14,steel)
    }
}
