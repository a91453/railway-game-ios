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
    var frontWidths: [Float] { far ? [-1.575,-1.02,0,1.02,1.575] : [-1.575,-1.34,-1.02,-0.55,0,0.55,1.02,1.34,1.575] }
    let frontHeights: [Float] = [0.78,1.18,1.95,3.26,3.6]
    func interpolate(_ x: Float,_ ks: [Float],_ vs: [Float]) -> Float {
        if x<=ks[0] { return vs[0] }
        for i in 0..<(ks.count-1) where x<=ks[i+1] {
            return vs[i]+(vs[i+1]-vs[i])*(x-ks[i])/(ks[i+1]-ks[i])
        }
        return vs.last!
    }
    func bow(_ h: Float,_ w: Float) -> Float {
        let lateral = far ? interpolate(abs(w),[0,1.02,1.575],[0,-0.07,-0.34])
            : interpolate(abs(w),[0,0.55,1.02,1.34,1.575],[0,-0.016,-0.07,-0.17,-0.34])
        let rake = interpolate(h,frontHeights,[-0.12,-0.04,0,-0.16,-0.34])
        return end+lateral+rake
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
        let ws=frontWidths
        for i in 0..<(ws.count-1) {
          for j in 0..<(frontHeights.count-1) {
            let q=clip(clip(clip(clip(p,1,ws[i],true),1,ws[i+1],false),0,frontHeights[j],true),0,frontHeights[j+1],false)
            if q.count<3 { continue }
            prism(q.map { Map3DPoint(bow($0.0,$0.1)+lift,$0.0,$0.1) }, q.map { Map3DPoint(bow($0.0,$0.1)+lift-depth,$0.0,$0.1) },color)
          }
        }
    }
    func frontPoint(_ h: Float,_ w: Float,_ lift: Float) -> Map3DPoint { Map3DPoint(bow(h,w)+lift,h,w) }
    mutating func lineOnBow(_ a: (Float,Float),_ b: (Float,Float),_ width: Float,_ color: UInt32,_ lift: Float) {
        let dz=b.0-a.0,dw=b.1-a.1,length=sqrtf(dz*dz+dw*dw)
        let z=dw/length*width/2,w = -dz/length*width/2
        panel([(a.0+z,a.1+w),(b.0+z,b.1+w),(b.0-z,b.1-w),(a.0-z,a.1-w)],color,lift,width/2)
    }
    func rounded(_ low: Float,_ high: Float,_ left: Float,_ right: Float,_ radius: Float) -> [(Float,Float)] {
        [(low,left+radius),(low,right-radius),(low+radius,right),(high-radius,right),(high,right-radius),(high,left+radius),(high-radius,left),(low+radius,left)]
    }
    mutating func shell(details: Bool) {
        let rear=section.map { Map3DPoint(-end,$0.0,$0.1) }
        let shoulder=section.map { Map3DPoint(cab ? 9.0 : end,$0.0,$0.1) }
        let front=section.map { h,w -> Map3DPoint in
            let z = cab && (h == 1.45 || h == 1.77) ? h+0.30 : h
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
            // Paint samples subdivide the same physical bow planes; they never move
            // the accepted side silhouette, glass or equipment.
            let ws: [Float] = far ? [-1.575,-1.34,-1.02,-0.55,0,0.55,1.02,1.34,1.575]
                : [-1.575,-1.48,-1.34,-1.20,-1.02,-0.80,-0.55,-0.30,0,0.30,0.55,0.80,1.02,1.20,1.34,1.48,1.575]
            for i in 0..<(ws.count-1) {
                let lo=ws[i],hi=ws[i+1]
                func smile(_ w: Float) -> Float { 1.95+0.24*powf(abs(w)/1.575,2) }
                func crown(_ w: Float) -> Float {
                    let q=abs(w)/1.575
                    let corner=max(0,min(1,(abs(w)-1.26)/0.315))
                    let eased=corner*corner*(3-2*corner)
                    return 3.32-0.06*q*q-0.12*eased
                }
                let a=smile(lo),b=smile(hi),u=crown(lo),v=crown(hi)
                let strips: [[(Float,Float)]] = [ [(1.04,lo),(1.04,hi),(b-0.44,hi),(a-0.44,lo)], [(a-0.44,lo),(b-0.44,hi),(b-0.12,hi),(a-0.12,lo)], [(a-0.12,lo),(b-0.12,hi),(b,hi),(a,lo)], [(a,lo),(b,hi),(v,hi),(u,lo)], [(u,lo),(v,hi),(3.6,hi),(3.6,lo)] ]
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
    mutating func cabDetails() {
        for sign: Float in [-1,1] {
            // Two independent windshields; the central evacuation door stays opaque.
            let frame: [(Float,Float)] = [(2.18,sign*0.64),(2.23,sign*1.42),(3.17,sign*1.42),(3.27,sign*0.64)]
            let pane: [(Float,Float)] = [(2.22,sign*0.68),(2.27,sign*1.38),(3.14,sign*1.38),(3.23,sign*0.68)]
            if !far { panel(frame,dark,0.018,0.018) }
            panel(pane,glass,0.026,0.012)
            // Each pair sits in a single rounded casting, not four isolated dots.
            var housing: [(Float,Float)] = []
            let n=far ? 6 : 12
            for i in 0...n {
                let a = -Float.pi/2+Float(i)*Float.pi/Float(n)
                housing.append((1.84+0.12*sinf(a),sign*(1.22+0.12*cosf(a))))
            }
            for i in 0...n {
                let a=Float.pi/2+Float(i)*Float.pi/Float(n)
                housing.append((1.84+0.12*sinf(a),sign*(0.96+0.12*cosf(a))))
            }
            panel(housing,steel,0.030,0.030)
            if !far {
                let inset=housing.map { v in (Float(1.84)+(v.0-1.84)*0.79,sign*1.09+(v.1-sign*1.09)*0.90) }
                panel(inset,dark,0.035,0.012)
            }
            for (w,c): (Float,UInt32) in [(0.96,Map3DTrainStyle.headlamp),(1.22,Map3DStreetModel.tailLamp)] {
                let sides=far ? 8 : 16
                let lens: [(Float,Float)] = (0..<sides).map { i in
                    let a=Float(i)*2*Float.pi/Float(sides)
                    return (Float(1.84)+0.067*sinf(a),sign*w+0.067*cosf(a))
                }
                panel(lens,c,0.043,0.012)
            }
            if !far {
                // Blade and arm are physically anchored at the lower windshield.
                let a=frontPoint(2.29,sign*1.28,0.049),b=frontPoint(2.70,sign*1.20,0.049)
                k.beam(a,b,0.022,steel)
                k.beam(frontPoint(2.27,sign*0.99,0.050),b,0.018,steel)
                k.beam(frontPoint(2.29,sign*1.28,0.026),a,0.035,steel)
            }
        }
        let marker: [(Float,Float)] = (0..<(far ? 8 : 16)).map { i in
            let a=Float(i)*2*Float.pi/Float(far ? 8 : 16)
            return (Float(3.48)+0.074*sinf(a),Float(0.074)*cosf(a))
        }
        panel(marker,steel,0.025,0.02)
        panel(marker.map { v in (Float(3.48)+(v.0-3.48)*0.74,v.1*0.74) },Map3DTrainStyle.headlamp,0.034,0.010)
        // Rounded evacuation door seam continues through the white and teal belt.
        let door=rounded(1.16,3.43,-0.54,0.54,0.08)
        for i in door.indices { lineOnBow(door[i],door[(i+1)%door.count],far ? 0.020 : 0.025,dark,0.024) }
        // Driver-right destination display = observer-left. Revision1 had it reversed.
        panel(rounded(2.96,3.20,0.72,1.34,0.025),dark,0.042,0.014)
        if !far { for h: Float in [3.045,3.115] { for w: Float in [0.79,0.91,1.03,1.15,1.27] {
            panel([(h,w),(h,w+0.035),(h+0.018,w+0.035),(h+0.018,w)],Map3DPalette.lantern,0.049,0.008)
        } } }
        // Lower silver cheeks continue the real shell, leaving the coupler notch open.
        for sign: Float in [-1,1] {
            panel([(0.85,sign*0.43),(0.90,sign*1.46),(1.12,sign*1.53),(1.12,sign*0.43)],silver,0,0.12)
            if !far { lineOnBow((1.075,sign*0.45),(1.075,sign*1.48),0.035,steel,0.010) }
        }
        // Fixed mount, drawbar, shaped Scharfenberg head and separate dark socket.
        k.box(end-0.24,0.67,0,0.35,0.26,0.34,steel)
        k.beam(Map3DPoint(end-0.25,0.78,0),Map3DPoint(half-0.12,0.78,0),0.12,steel)
        let outline: [(Float,Float)] = [(0.65,-0.18),(0.65,0.18),(0.70,0.24),(0.87,0.24),(0.92,0.15),(0.92,-0.15),(0.87,-0.24),(0.70,-0.24)]
        let inner: [(Float,Float)] = outline.map { v in (Float(0.785)+(v.0-0.785)*0.62,v.1*0.62) }
        for i in outline.indices {
            let j=(i+1)%outline.count
            let rim=[outline[i],outline[j],inner[j],inner[i]]
            prism(rim.map { Map3DPoint(half,$0.0,$0.1) },rim.map { Map3DPoint(half-0.14,$0.0,$0.1) },silver)
        }
        prism(inner.map { Map3DPoint(half-0.045,$0.0,$0.1) },inner.map { Map3DPoint(half-0.065,$0.0,$0.1) },dark)
        if !far {
            for sign: Float in [-1,1] {
                k.beam(Map3DPoint(half-0.1,0.70,sign*0.20),Map3DPoint(half-0.1,0.91,sign*0.18),0.025,steel)
            }
        }
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
        if cab { cabDetails() }
        // Distinct DM and T equipment. Unknown hidden plumbing is omitted.
        for x: Float in [-6.9,6.9] {
            k.box(x,3.60,0,2.90,1.78,0.15,silver)
            k.box(x,3.75,0,2.72,1.64,0.005,steel)
            if far { k.box(x,3.756,0,2.72,1.58,0.012,steel) }
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
