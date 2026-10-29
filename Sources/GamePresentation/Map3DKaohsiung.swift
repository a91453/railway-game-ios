import Foundation

/// Siemens high-capacity EMU, shared by Kaohsiung Red/Orange lines.
/// Independent study; photo-fitted details are not engineering dimensions.
public enum Map3DKaohsiung {
    public enum Unit: String, CaseIterable, Sendable { case dm1, t, dm2 }
    public static func model(_ unit: Unit, far: Bool = false, shellOnly: Bool = false) -> Map3DModelPack.Model {
        var r = KaohsiungRecipe(unit: unit, far: far)
        r.build(details: !shellOnly)
        return .flat(named: "kaohsiung-" + unit.rawValue + (far ? "-far" : "") + (shellOnly ? "-shell" : ""), from: r.k.mesh)
    }
}

private struct KaohsiungRecipe {
    let unit: Map3DKaohsiung.Unit
    let far: Bool
    var k = StationKitBuilder()
    let silver = Map3DPalette.counters[2]
    let white = Map3DPalette.tileWhite
    let teal = Map3DColor.rgb(0x45D3C0)
    let dark = Map3DColor.shaded(Map3DPalette.playerRim, 0.60)
    let glass = Map3DTrainStyle.glass
    let steel = Map3DColor.shaded(StationKitBuilder.steel, 0.48)
    var cab: Bool { unit != .t }
    var half: Float { cab ? 10.9725 : 10.78 }
    // Body ends are shorter than coupling pitch. Dimensions in builder x/up/right.
    var end: Float { half - 0.24 }
    let section: [(Float,Float)] = [(1.04,-1.48),(1.13,-1.575),(1.45,-1.575),(1.77,-1.575),(3.14,-1.575),(3.35,-1.52),(3.51,-1.34),(3.59,-1.02),(3.60,0),(3.59,1.02),(3.51,1.34),(3.35,1.52),(3.14,1.575),(1.77,1.575),(1.45,1.575),(1.13,1.575),(1.04,1.48)]
    func bow(_ h: Float,_ w: Float) -> Float {
        end - 0.12 * powf(abs(w)/1.575,2) - max(0,h-1.8)*0.19
    }
    mutating func face(_ p: [Map3DPoint],_ inside: Map3DPoint,_ color: UInt32) {
        var n = Map3DPoint.zero
        for i in 1..<(p.count-1) { n = n + (p[i]-p[0]).cross(p[i+1]-p[0]) }
        let c = p.reduce(.zero,+)*(1/Float(p.count))
        var q = n.dot(c-inside) >= 0 ? p : Array(p.reversed())
        // Clipping can start on a straight edge; addFacet requires a real first triangle.
        for _ in q.indices {
            if (q[1]-q[0]).cross(q[2]-q[0]).dot((q[1]-q[0]).cross(q[2]-q[0])) > 0.000000000001 { break }
            q.append(q.removeFirst())
        }
        k.mesh.addFacet(q, color: color)
    }
    mutating func prism(_ a: [Map3DPoint],_ b: [Map3DPoint],_ color: UInt32) {
        let c = (a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
        face(a,c,color); face(b,c,color)
        for i in a.indices { let j = (i+1)%a.count; face([a[i],a[j],b[j],b[i]],c,color) }
    }
    // Convex clipping in front elevation, used for real shell colour boundaries.
    func clip(_ p: [(Float,Float)],_ axis: Int,_ limit: Float,_ above: Bool) -> [(Float,Float)] {
        var q: [(Float,Float)] = []
        func v(_ a: (Float,Float)) -> Float { axis == 0 ? a.0 : a.1 }
        for i in p.indices {
            let a=p[i],b=p[(i+1)%p.count],va=v(a),vb=v(b)
            let ia=above ? va>=limit : va<=limit, ib=above ? vb>=limit : vb<=limit
            if ia { q.append(a) }
            if ia != ib { let t=(limit-va)/(vb-va); if t>0 && t<1 { q.append((a.0+t*(b.0-a.0),a.1+t*(b.1-a.1))) } }
        }
        var clean: [(Float,Float)] = []
        for v in q {
            let p = ((v.0*1_000_000).rounded()/1_000_000,(v.1*1_000_000).rounded()/1_000_000)
            if let a=clean.last,abs(a.0-p.0)+abs(a.1-p.1)<0.000001 { continue }
            clean.append(p)
        }
        if clean.count>1,let a=clean.first,let b=clean.last,abs(a.0-b.0)+abs(a.1-b.1)<0.000001 { clean.removeLast() }
        return clean
    }
    mutating func panel(_ p: [(Float,Float)],_ color: UInt32,_ lift: Float = 0,_ depth: Float = 0.014) {
        let ws: [Float] = far ? [-1.575,0,1.575] : [-1.575,-1.34,-1.02,-0.55,0,0.55,1.02,1.34,1.575]
        for i in 0..<(ws.count-1) {
            let q=clip(clip(p,1,ws[i],true),1,ws[i+1],false)
            if q.count<3 { continue }
            prism(q.map { Map3DPoint(bow($0.0,$0.1)+lift,$0.0,$0.1) }, q.map { Map3DPoint(bow($0.0,$0.1)+lift-depth,$0.0,$0.1) },color)
        }
    }
    mutating func shell(details: Bool) {
        let rear=section.map { Map3DPoint(-end,$0.0,$0.1) }
        let shoulder=section.map { Map3DPoint(cab ? 9.0 : end,$0.0,$0.1) }
        let front=section.map { h,w -> Map3DPoint in
            let z = cab && (h == 1.45 || h == 1.77) ? h+0.25 : h
            return Map3DPoint(cab ? bow(z,w)-0.12 : end,z,w)
        }
        let inside=Map3DPoint(0,2.2,0)
        face(rear,inside,silver);face(front,inside,silver)
        let rings = cab ? [rear,shoulder,front] : [rear,front]
        for pair in 0..<(rings.count-1) {
            let a=rings[pair],b=rings[pair+1]
            for i in section.indices {
                let j=(i+1)%section.count
                let band = min(section[i].0,section[j].0)>=1.45 && max(section[i].0,section[j].0)<=1.77
                face([a[i],a[j],b[j],b[i]],inside,details && band ? teal : silver)
            }
        }
        if cab {
            // Each slab is the actual shell, not a floating livery decal.
            let ws: [Float] = [-1.575,-1.34,-1.02,-0.55,0,0.55,1.02,1.34,1.575]
            for i in 0..<(ws.count-1) {
                let lo=ws[i],hi=ws[i+1]
                func smile(_ w: Float) -> Float { 1.89+0.25*powf(abs(w)/1.575,1.5) }
                let a=smile(lo),b=smile(hi)
                let strips: [[(Float,Float)]] = [ [(1.04,lo),(1.04,hi),(b-0.43,hi),(a-0.43,lo)], [(a-0.43,lo),(b-0.43,hi),(b-0.12,hi),(a-0.12,lo)], [(a-0.12,lo),(b-0.12,hi),(b,hi),(a,lo)], [(a,lo),(b,hi),(3.32,hi),(3.32,lo)], [(3.32,lo),(3.32,hi),(3.6,hi),(3.6,lo)] ]
                let colors=[silver,teal,white,dark,teal]
                for s in strips.indices {
                    var p=strips[s]
                    // Intersect with rounded shoulder polygon.
                    for e in section.indices {
                        let c=section[e],d=section[(e+1)%section.count]
                        var out: [(Float,Float)]=[]
                        func value(_ v: (Float,Float)) -> Float { (d.0-c.0)*(v.1-c.1)-(d.1-c.1)*(v.0-c.0) }
                        for n in p.indices {
                            let u=p[n],v=p[(n+1)%p.count],vu=value(u),vv=value(v)
                            if vu>=0 { out.append(u) }
                            if (vu>=0) != (vv>=0) { let t=vu/(vu-vv);out.append((u.0+t*(v.0-u.0),u.1+t*(v.1-u.1))) }
                        }
                        p=out
                        if p.count<3 { break }
                    }
                    if p.count>=3 { panel(p,details ? colors[s] : silver,0,0.12) }
                }
            }
        }
    }
    mutating func sideWindow(_ x: Float,_ z: Float,_ side: Float,_ width: Float,_ height: Float) {
        if far { k.box(x,z,side*1.610,width,0.016,height,glass); return }
        let r: Float = 0.07
        let p: [(Float,Float)] = [(-width/2+r,0),(width/2-r,0),(width/2,r),(width/2,height-r),(width/2-r,height),(-width/2+r,height),(-width/2,height-r),(-width/2,r)]
        prism(p.map { Map3DPoint(x+$0.0,z+$0.1,side*1.602) },p.map { Map3DPoint(x+$0.0,z+$0.1,side*1.618) },glass)
    }
    mutating func build(details: Bool) {
        shell(details: details)
        if !details { return }
        for side: Float in [-1,1] {
            for x: Float in [-7.35,-2.45,2.45,7.35] {
                // Four pairs of externally sliding doors per side, colour cut at belt.
                for (z,h,c) in (far ? [] : [(Float(1.13),Float(0.32),silver),(1.45,0.32,teal),(1.77,1.35,silver)]) {
                    k.box(x,z,side*1.582,1.54,0.022,h,c)
                }
                if !far { k.box(x,1.13,side*1.60,0.025,0.014,1.99,dark) }
                for dx: Float in [-0.39,0.39] { sideWindow(x+dx,2.12,side,0.55,0.82) }
                if !far { k.box(x,1.10,side*1.60,1.70,0.02,0.045,silver) }
            }
            for x: Float in [-4.9,0,4.9] {
                for dx: Float in [-0.64,0.64] { sideWindow(x+dx,2.12,side,1.12,0.82) }
            }
            if cab { k.box(9.45,2.13,side*1.59,0.65,0.028,0.94,glass) }
        }
        if cab {
            for sign: Float in [-1,1] {
                panel([(2.26,sign*0.59),(2.26,sign*1.40),(3.23,sign*1.40),(3.30,sign*0.59)],glass,0.020,0.012)
                // Individually circular lenses, mounted on the true bow.
                for (w,c) in [(Float(0.96),Map3DTrainStyle.headlamp),(1.25,Map3DStreetModel.tailLamp)] {
                    let wc=sign*w,h: Float=1.69+0.11*abs(wc)
                    let n=far ? 8 : 12
                    var ring: [(Float,Float)] = []
                    for i in 0..<n { let a=Float(i)*2*Float.pi/Float(n); ring.append((h+0.085*sinf(a),wc+0.085*cosf(a))) }
                    if !far { panel(ring,steel,0.025,0.025) }
                    let lens: [(Float,Float)] = ring.map { p in (h+(p.0-h)*Float(0.72),wc+(p.1-wc)*Float(0.72)) }
                    panel(lens,c,0.030,0.010)
                }
            }
            let marker: [(Float,Float)] = (0..<12).map { i in
                let a=Float(i)*2*Float.pi/12
                return (Float(3.49)+0.065*sinf(a),Float(0.065)*cosf(a))
            }
            panel(marker,Map3DTrainStyle.headlamp,0.025,0.02)
            // Central evacuation door perimeter. No trademark or textual destination.
            for w: Float in (far ? [] : [-0.55,0.55]) { panel([(1.20,w-0.012),(1.20,w+0.012),(3.42,w+0.012),(3.42,w-0.012)],dark,0.022,0.014) }
            if !far { panel([(3.39,-0.55),(3.39,0.55),(3.42,0.55),(3.42,-0.55)],dark,0.022) }
            panel([(2.97,-1.36),(2.97,-0.65),(3.20,-0.65),(3.20,-1.36)],dark,0.038)
            if !far { for x: Float in [-1.25,-1.08,-0.91,-0.74] { panel([(3.06,x),(3.06,x+0.06),(3.09,x+0.06),(3.09,x)],Map3DPalette.lantern,0.045) } }
            k.box(end-0.18,0.56,0,0.25,0.34,0.48,steel)
            k.box(half-0.16,0.62,0,0.32,0.44,0.21,silver)
        }
        // Distinct DM and T equipment. Unknown hidden plumbing is omitted.
        for x: Float in [-6.9,6.9] {
            k.box(x,3.60,0,2.90,1.78,0.15,silver)
            k.box(x,3.75,0,2.72,1.64,0.005,steel)
            if far { k.box(x,3.756,0,2.72,1.58,0.012,silver) }
            if !far { for dx: Float in [-0.85,0,0.85] { k.box(x+dx,3.756,0,0.06,1.58,0.012,silver) } }
        }
        for x: Float in [-3.5,0,3.5] { for w: Float in [-0.62,0.62] { k.box(x,3.60,w,0.48,0.38,0.055,silver) } }
        for x: Float in (unit == .t ? [-4.4,-1.5,1.5,4.4] : [-4.1,-0.9,3.6]) {
            k.box(x,0.48,0,unit == .t ? 1.7 : 2.1,1.8,0.48,steel)
        }
        for bx: Float in [-7.15,7.15] {
            k.box(bx,0.78,0,1.1,1.15,0.26,steel)
            k.box(bx,0.45,0,3.00,1.32,0.25,steel)
            for dx: Float in [-1.15,1.15] {
                let n=far ? 8 : 16
                for side: Float in [-1,1] {
                    let a=(0..<n).map { i in let t=Float(i)*2*Float.pi/Float(n);return Map3DPoint(bx+dx+0.425*cosf(t),0.425+0.425*sinf(t),side*0.7175-0.07) }
                    prism(a,a.map { $0+Map3DPoint(0,0,0.14) },dark)
                }
                k.beam(Map3DPoint(bx+dx,0.425,-0.72),Map3DPoint(bx+dx,0.425,0.72),0.12,steel)
            }
            for side: Float in [-1,1] { k.box(bx,0.30,side*1.18,0.60,0.32,0.09,steel) }
        }
        for sign: Float in (cab ? [-1] : [-1,1]) {
            k.box(sign*(half-0.13),1.15,0,0.26,1.92,2.10,dark)
            if !far { for i in 0..<4 { k.box(sign*(half-0.24+Float(i)*0.06),1.15,0,0.018,2.0,2.14,steel) } }
        }
    }
}
