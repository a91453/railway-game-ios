import Foundation

/// Independent TMRT Green line DM1/DM2 study. Official overall dimensions;
/// fitting stations and hidden equipment are visual estimates (see source record).
public enum Map3DTaichungGreen {
    public enum Role: String, CaseIterable, Sendable { case dm1, dm2 }
    public static let carLength: Float = 22.17
    public static func model(_ role: Role, far: Bool = false, shellOnly: Bool = false) -> Map3DModelPack.Model {
        var recipe = TaichungGreenRecipe(far: far)
        recipe.build(details: !shellOnly, second: role == .dm2)
        return .flat(named: "taichung-green-" + role.rawValue + (far ? "-far" : "") + (shellOnly ? "-shell" : ""), from: recipe.kit.mesh)
    }
}

private struct TaichungGreenRecipe {
    var kit = StationKitBuilder()
    let far: Bool
    let white = Map3DPalette.tileWhite
    let silver = Map3DPalette.counters[2]
    let dark = Map3DColor.shaded(Map3DPalette.playerRim, 0.60)
    // Existing foliage base swatch, before Map3DLook softens street props.
    let green = Map3DColor.rgb(0x7CC058)
    let glass = Map3DTrainStyle.glass
    let hardware = Map3DColor.shaded(StationKitBuilder.steel, 0.48)
    // Height/lateral section, independent of the Taipei/Sanying recipes.
    let outline: [(Float, Float)] = [(1.04,-1.32),(1.12,-1.418),(3.12,-1.448),(3.36,-1.388),(3.55,-1.25),(3.63,-0.88),(3.65,0),(3.63,0.88),(3.55,1.25),(3.36,1.388),(3.12,1.448),(1.12,1.418),(1.04,1.32)]
    var heights: [Float] { far ? [0.6,1.04,1.85,2.6,3.3,3.65] : [0.6,1.04,1.25,1.55,1.85,2.2,2.6,3.0,3.3,3.55,3.65] }
    var widths: [Float] { far ? [-1.5,-1,0,1,1.5] : [-1.5,-1.25,-1.0,-0.7,-0.35,0,0.35,0.7,1.0,1.25,1.5] }
    func interpolate(_ x: Float,_ knots: [Float],_ values: [Float]) -> Float {
        if x <= knots[0] { return values[0] }
        for i in 0..<(knots.count-1) where x <= knots[i+1] {
            return values[i]+(values[i+1]-values[i])*(x-knots[i])/(knots[i+1]-knots[i])
        }
        return values.last!
    }
    func front(_ h: Float,_ w: Float) -> Float {
        10.88 + interpolate(h,heights,far ? [-0.05,0,-0.06,-0.30,-0.64,-0.92] : [-0.05,0,0.015,0,-0.06,-0.16,-0.30,-0.48,-0.64,-0.81,-0.92])
            + interpolate(abs(w),far ? [0,1,1.5] : [0,0.35,0.7,1.0,1.25,1.5],far ? [0,-0.08,-0.30] : [0,-0.008,-0.035,-0.08,-0.16,-0.30])
    }
    // Fine silhouette samples can leave collinear first corners after clipping.
    // Orient by the complete planar polygon area, rather than its first triple.
    mutating func face(_ points: [Map3DPoint],inside: Map3DPoint,color: UInt32) {
        guard points.count>=3 else { return }
        var n=Map3DPoint.zero
        for i in 1..<(points.count-1) { n=n+(points[i]-points[0]).cross(points[i+1]-points[0]) }
        let c=points.reduce(Map3DPoint.zero,+)*(1/Float(points.count))
        kit.mesh.addFacet(n.dot(c-inside)>=0 ? points : Array(points.reversed()),color:color)
    }
    mutating func prism(_ a: [Map3DPoint],_ b: [Map3DPoint],_ color: UInt32) {
        let c=(a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
        face(a,inside:c,color:color); face(b,inside:c,color:color)
        for i in a.indices { let j=(i+1)%a.count; face([a[i],a[j],b[j],b[i]],inside:c,color:color) }
    }
    func clip(_ p: [(Float,Float)],axis: Int,at limit: Float,greater: Bool) -> [(Float,Float)] {
        func value(_ p: (Float,Float)) -> Float { axis == 0 ? p.0 : p.1 }
        var out: [(Float,Float)] = []
        for i in p.indices {
            let a=p[i],b=p[(i+1)%p.count],va=value(a),vb=value(b)
            let ia=greater ? va>=limit : va<=limit,ib=greater ? vb>=limit : vb<=limit
            if ia { out.append(a) }
            if ia != ib { let t=(limit-va)/(vb-va); if t>0 && t<1 { out.append((a.0+t*(b.0-a.0),a.1+t*(b.1-a.1))) } }
        }
        var clean: [(Float,Float)] = []
        for p in out { if let q=clean.last, abs(p.0-q.0)+abs(p.1-q.1)<0.00001 { continue }; clean.append(p) }
        if clean.count>1, let a=clean.first, let b=clean.last, abs(a.0-b.0)+abs(a.1-b.1)<0.00001 { clean.removeLast() }
        return clean
    }
    // Separable piecewise-linear surface: every grid cell is planar. Panels
    // use these exact planes, with real backs and perimeter walls.
    mutating func patch(_ polygon: [(Float,Float)],color: UInt32,lift: Float,thickness: Float) {
        func p(_ v: (Float,Float),_ offset: Float) -> Map3DPoint { Map3DPoint(front(v.0,v.1)+offset,v.0,v.1) }
        for i in 0..<(heights.count-1) { for j in 0..<(widths.count-1) {
            var q=clip(clip(polygon,axis:0,at:heights[i],greater:true),axis:0,at:heights[i+1],greater:false)
            q=clip(clip(q,axis:1,at:widths[j],greater:true),axis:1,at:widths[j+1],greater:false)
            if q.count<3 { continue }
            let c=q.map { p($0,lift-thickness/2) }.reduce(.zero,+)*(1/Float(q.count))
            face(q.map { p($0,lift) },inside:c,color:color)
            face(q.map { p($0,lift-thickness) },inside:c,color:color)
        } }
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count];var ts: [Float] = [0,1]
            if a.0 != b.0 { ts += heights.map { ($0-a.0)/(b.0-a.0) }.filter { $0>0 && $0<1 } }
            if a.1 != b.1 { ts += widths.map { ($0-a.1)/(b.1-a.1) }.filter { $0>0 && $0<1 } }
            ts=Array(Set(ts)).sorted()
            ts=ts.enumerated().filter { $0.offset == 0 || $0.element-ts[$0.offset-1]>0.00001 }.map(\.element)
            for k in 0..<(ts.count-1) {
                func at(_ t: Float) -> (Float,Float) { (a.0+t*(b.0-a.0),a.1+t*(b.1-a.1)) }
                let u=at(ts[k]),v=at(ts[k+1]),c=polygon.map { p($0,lift-thickness/2) }.reduce(.zero,+)*(1/Float(polygon.count))
                face([p(u,lift),p(v,lift),p(v,lift-thickness),p(u,lift-thickness)],inside:c,color:color)
            }
        }
    }
    mutating func build(details: Bool,second: Bool) {
        let rear=outline.map { Map3DPoint(-10.74,$0.0,$0.1) }
        let nose=outline.map { Map3DPoint(front($0.0,$0.1)-0.22,$0.0,$0.1) }
        // Front slab is built separately, allowing a truly curved bow.
        prism(rear,nose,silver)
        patch(outline,color:white,lift:0,thickness:0.22)
        if !details { return }
        // Black inverted pear/U mask and separately supported windscreen.
        let mask: [(Float,Float)] = far ? [
            (3.57,-0.96),(3.63,0),(3.57,0.96),(3.40,1.08),(3.04,1.01),
            (2.56,0.88),(2.09,0.67),(1.77,0.37),(1.66,0),
            (1.77,-0.37),(2.09,-0.67),(2.56,-0.88),(3.04,-1.01),(3.40,-1.08)
        ] : [
            (3.57,-0.96),(3.61,-0.55),(3.63,0),(3.61,0.55),(3.57,0.96),
            (3.51,1.04),(3.40,1.08),(3.22,1.06),(3.04,1.01),
            (2.80,0.95),(2.56,0.88),(2.32,0.79),(2.09,0.67),
            (1.91,0.53),(1.77,0.37),(1.69,0.18),(1.66,0),
            (1.69,-0.18),(1.77,-0.37),(1.91,-0.53),(2.09,-0.67),
            (2.32,-0.79),(2.56,-0.88),(2.80,-0.95),(3.04,-1.01),
            (3.22,-1.06),(3.40,-1.08),(3.51,-1.04)
        ]
        patch(mask,color:dark,lift:0.012,thickness:0.012)
        let windscreen: [(Float,Float)] = [(3.27,-0.84),(3.29,-0.46),(3.30,0),
            (3.29,0.46),(3.27,0.84),(3.22,0.91),(3.10,0.91),
            (2.32,0.73),(2.22,0.67),(2.16,0.55),(2.16,-0.55),
            (2.22,-0.67),(2.32,-0.73),(3.10,-0.91),(3.22,-0.91)]
        patch(windscreen,color:glass,lift:0.027,thickness:0.015)
        // The white U's lower boundary rises at the centre, leaving a dark
        // curved valance above the real coupler opening, rather than a flat chin.
        patch([(1.04,-1.32),(1.04,1.32),(1.11,1.40),(1.13,1.15),
               (1.22,0.72),(1.28,0),(1.22,-0.72),(1.13,-1.15),(1.11,-1.40)],
              color:dark,lift:0.012,thickness:0.012)
        for side: Float in [-1,1] {
            patch([(1.31,side*1.17),(1.35,side*1.33),(1.42,side*1.35),
                   (1.92,side*1.29),(2.00,side*1.21),(1.99,side*1.08),
                   (1.91,side*1.03),(1.44,side*0.90),(1.35,side*0.98)],
                  color:dark,lift:0.016,thickness:0.016)
            for h: Float in [1.53,1.82] {
                let n=far ? 8 : 16
                let rim=(0..<n).map { i -> (Float,Float) in
                    let a=Float(i)*2*Float.pi/Float(n)
                    return (h+sinf(a)*0.116,side*1.17+cosf(a)*0.116)
                }
                patch(rim,color:StationKitBuilder.steel,lift:0.033,thickness:0.017)
                let lens=(0..<n).map { i -> (Float,Float) in
                    let a=Float(i)*2*Float.pi/Float(n)
                    return (h+sinf(a)*0.081,side*1.17+cosf(a)*0.081)
                }
                patch(lens,color:h<1.7 ? Map3DTrainStyle.headlamp : glass,
                      lift:0.040,thickness:0.007)
            }
            // Side paint: narrow sill and roof bands, vertical green shoulder.
            kit.box(-0.10,1.12,side*1.426,21.2,0.018,0.17,green)
            kit.box(-0.60,3.12,side*1.448,20.2,0.018,0.20,green)
            // Green returns diagonally over the FRP shoulders; true local
            // section width at each height, instead of a vertical stripe box.
            let levels: [Float] = far ? [1.25,1.85,2.6,3.30] : [1.25,1.55,1.85,2.2,2.6,3.0,3.12,3.30]
            func shoulder(_ h: Float,_ back: Bool,_ offset: Float) -> Map3DPoint {
                let w=interpolate(h,[1.12,3.12,3.36],[1.418,1.448,1.388])
                let band=interpolate(h,[1.25,1.55,1.85,2.2,2.6,3.0,3.30],
                                     [0.78,0.68,0.55,0.48,0.45,0.60,0.85])
                let x=front(h,w)-(back ? band : 0.03)
                return Map3DPoint(x,h,side*(w+offset))
            }
            for i in 0..<(levels.count-1) {
                let a=levels[i],b=levels[i+1]
                prism([shoulder(a,true,0),shoulder(b,true,0),shoulder(b,false,0),shoulder(a,false,0)],
                      [shoulder(a,true,0.018),shoulder(b,true,0.018),shoulder(b,false,0.018),shoulder(a,false,0.018)],green)
            }
            kit.box(-0.8,2.1,side*1.453,19.8,0.018,1.02,dark)
            // Five double-leaf doorways, each side; no fictional cab door.
            for x: Float in [-9.0,-5.05,-1.1,2.85,6.8] {
                if far {
                    kit.box(x,1.24,side*1.470,1.448,0.016,1.875,silver)
                    kit.box(x,2.25,side*1.484,1.14,0.012,0.70,glass)
                    continue
                }
                for leaf: Float in [-1,1] {
                    let cx=x+leaf*0.375
                    kit.box(cx,1.24,side*1.470,0.738,0.016,1.875,silver)
                    kit.box(cx,2.25,side*1.484,0.39,0.012,0.70,glass)
                }
            }
            for x: Float in [-7.05,-3.10,0.85,4.80] { kit.box(x,2.17,side*1.470,1.56,0.016,0.78,glass) }
            // Thin yellow safety line visible on the dark belt.
            if !far { for x: Float in [-7.05,-3.1,0.85,4.8] { kit.box(x,2.50,side*1.482,1.56,0.008,0.025,Map3DPalette.lantern) } }
        }
        kit.box(0,0.91,0,20.8,2.35,0.13,hardware)
        // Two independently supported roof air conditioners per vehicle.
        for x: Float in [-7.3,7.1] {
            kit.box(x,3.65,0,3.7,1.65,0.105,silver)
            if far { kit.box(x,3.755,0,2.8,1.30,0.025,hardware) }
            if !far { for dx: Float in [-1.05,0,1.05] { kit.box(x+dx,3.755,0,0.70,1.30,0.025,hardware) } }
        }
        for x: Float in [-6.85,6.85] {
            kit.box(x,0.45,0,3.25,1.10,0.37,hardware)
            kit.box(x,0.80,0,1.20,0.80,0.14,hardware)
            for dx: Float in [-1.05,1.05] {
                kit.beam(Map3DPoint(x+dx,0.39,-0.91),Map3DPoint(x+dx,0.39,0.91),0.15,hardware)
                for side: Float in [-1,1] {
                    let n=far ? 8 : 16
                    let a=(0..<n).map { i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(n);return Map3DPoint(x+dx+cosf(t)*0.39,0.39+sinf(t)*0.39,side*0.7175-0.065) }
                    prism(a,a.map { $0+Map3DPoint(0,0,0.13) },hardware)
                }
            }
            // Third-rail shoes, no pantograph. Placement is a visual estimate.
            for side: Float in [-1,1] { kit.box(x,0.35,side*1.03,0.65,0.60,0.10,hardware) }
        }
        // DM1/DM2 have different underfloor box groups; no claim of full engineering detail.
        for x: Float in (second ? [-3.7,-0.4,3.1] : [-4.1,-1.0,2.7]) {
            kit.box(x,0.48,second ? 0.16 : -0.16,2.1,1.62,0.43,hardware)
        }
        // Open centre with a narrow stalk and a round socket. The box-like
        // underfloor appliances are darkened, so they do not fill the opening.
        kit.box(10.22,0.66,0,1.52,0.22,0.15,hardware)
        kit.box(10.12,0.79,0,0.70,0.32,0.25,hardware)
        let count=far ? 8 : 16
        let socket=(0..<count).map { i -> Map3DPoint in
            let a=Float(i)*2*Float.pi/Float(count)
            return Map3DPoint(10.88,0.73+sinf(a)*0.19,cosf(a)*0.28)
        }
        let outer=socket.map { Map3DPoint(11.085,$0.y,$0.z) }
        let inner=(0..<count).map { i -> Map3DPoint in
            let a=Float(i)*2*Float.pi/Float(count)
            return Map3DPoint(11.085,0.73+sinf(a)*0.13,cosf(a)*0.16)
        }
        let bottom=inner.map { Map3DPoint(11.0,$0.y,$0.z) }
        let materialCentre=Map3DPoint(10.97,0.73,0)
        face(socket,inside:materialCentre,color:hardware)
        face(bottom,inside:materialCentre,color:dark)
        for i in 0..<count {
            let j=(i+1)%count,angle=(Float(i)+0.5)*2*Float.pi/Float(count)
            face([socket[i],socket[j],outer[j],outer[i]],inside:materialCentre,color:StationKitBuilder.steel)
            face([outer[i],outer[j],inner[j],inner[i]],inside:materialCentre,color:StationKitBuilder.steel)
            face([inner[i],inner[j],bottom[j],bottom[i]],
                     inside:Map3DPoint(11.04,0.73+sinf(angle)*0.17,cosf(angle)*0.23),color:dark)
        }
        for side: Float in [-1,1] {
            let cheek: [(Float,Float)] = far ? [(1.08,0.62),(1.08,1.40),
                (0.78,1.35),(0.65,1.16),(0.65,0.88)] : [
                (1.08,0.62),(1.08,1.30),(1.02,1.42),(0.86,1.40),
                (0.74,1.32),(0.67,1.19),(0.65,1.04),(0.65,0.88)]
            let face=cheek.map { h,w in Map3DPoint(front(h,w)-0.10,h,side*w) }
            prism(face.map { $0-Map3DPoint(0.54,0,0) },face,white)
        }
        kit.box(-10.91,0.65,0,0.35,0.28,0.19,hardware)
        kit.box(-10.81,1.08,0,0.55,1.54,2.18,dark)
        if !far {
            for x: Float in [-10.93,-10.84,-10.75] { kit.box(x,1.08,0,0.035,1.58,2.18,hardware) }
            kit.beam(Map3DPoint(front(2.17,-0.5)+0.045,2.17,-0.5),Map3DPoint(front(2.28,0.46)+0.045,2.28,0.46),0.026,dark)
        }
    }
}
