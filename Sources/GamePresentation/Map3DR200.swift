import Foundation

/// TRA R200, R216 ordinary white/navy service appearance, December 2024.
/// New geometry, not the older one-cab R200CK placeholder. Metres, native
/// +X radiator/fan end (cab numbering unverified), +Y left, Z rail.
/// Overall envelope follows the published 20.010 x 2.852 x 4.080 m specification.
/// Wheel diameter, axle stations and fittings are photo estimates, not drawings.
public enum Map3DR200 {
    public static let ids = ["tra-r200-r216-locomotive", "tra-r200-r216-locomotive-far"]
    public static let white = Map3DColor.rgb(0xEBEDEA)
    public static let navy = Map3DColor.rgb(0x202F49)
    public static let dark = Map3DColor.rgb(0x303639)
    public static let metal = Map3DColor.rgb(0x626B70)
    public static func model(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.r200Vehicle(far: far)
        return roundedEnds(.flat(named: ids[far ? 1 : 0], from: b.mesh), far: far)
    }
    /// Subdivide shared long edges before bowing the end surfaces. Every
    /// matching edge gets the same midpoint, preserving a closed mesh.
    private static func roundedEnds(_ source: Map3DModelPack.Model, far: Bool) -> Map3DModelPack.Model {
        struct Triangle { var p:[Map3DPoint]; var color:UInt32; var layer:Float }
        var ts=stride(from:0,to:source.vertices.count,by:3).map { i in
            Triangle(p:source.vertices[i..<i+3].map(\.position),color:source.vertices[i].color,layer:source.vertices[i].layer)
        }
        func key(_ p:Map3DPoint)->String { "\(p.x.bitPattern),\(p.y.bitPattern),\(p.z.bitPattern)" }
        func edge(_ a:Map3DPoint,_ b:Map3DPoint)->String { let x=key(a),y=key(b);return x<y ? x+"|"+y:y+"|"+x }
        let limit:Float=far ? 1.10:0.55
        for _ in 0..<6 {
            var mids:[String:Map3DPoint]=[:]
            for t in ts { for i in 0..<3 {
                let a=t.p[i],b=t.p[(i+1)%3]
                if max(abs(a.x),abs(b.x))>7.8 && min(a.z,b.z)>=1.4 && (a-b).length>limit {
                    let k=edge(a,b)
                    if mids[k]==nil { mids[k]=(a+b)*0.5 }
                }
            } }
            if mids.isEmpty { break }
            var next:[Triangle]=[]
            for t in ts {
                let p=t.p,m=(0..<3).map { mids[edge(p[$0],p[($0+1)%3])] },count=m.compactMap{$0}.count
                func add(_ a:Map3DPoint,_ b:Map3DPoint,_ c:Map3DPoint) { next.append(Triangle(p:[a,b,c],color:t.color,layer:t.layer)) }
                if count==0 { next.append(t) }
                else if count==3 {
                    add(p[0],m[0]!,m[2]!);add(m[0]!,p[1],m[1]!);add(m[2]!,m[1]!,p[2]);add(m[0]!,m[1]!,m[2]!)
                } else if count==1 {
                    let i=m.firstIndex(where:{$0 != nil})!,j=(i+1)%3,k=(i+2)%3
                    add(p[i],m[i]!,p[k]);add(m[i]!,p[j],p[k])
                } else {
                    let i=(0..<3).first { m[$0] != nil && m[($0+1)%3] != nil }!,j=(i+1)%3,k=(i+2)%3
                    add(p[j],m[j]!,m[i]!);add(p[i],m[i]!,p[k]);add(m[i]!,m[j]!,p[k])
                }
            }
            ts=next
        }
        func shape(_ p:Map3DPoint)->Map3DPoint {
            if p.z<1.4 { return p }
            let t=max(0,min(1,(abs(p.x)-7.6))),w=t*t*(3-2*t)
            let crown=max(0,1-(p.y/1.426)*(p.y/1.426))*0.045*w
            let low=max(0,min(1,(2.45-p.z)/1.05))
            let u=max(0,min(1,(p.z-3.67)/0.33)),arch=u*u*(3-2*u)
            let height=p.z-0.07*w*arch*(p.y/1.126)*(p.y/1.126)
            return Map3DPoint(p.x+(p.x>0 ? 1:-1)*crown,p.y*(1-0.035*w*low),height)
        }
        var vs:[Map3DVertex]=[]
        for t in ts {
            let p=t.p.map(shape),n=(p[1]-p[0]).cross(p[2]-p[0]).normalized ?? .up
            vs += p.map { Map3DVertex($0,normal:n,color:t.color,layer:t.layer) }
        }
        return Map3DModelPack.Model(name:source.name,vertices:vs,
            minimum:Map3DPoint(vs.map(\.x).min()!,vs.map(\.y).min()!,vs.map(\.z).min()!),
            maximum:Map3DPoint(vs.map(\.x).max()!,vs.map(\.y).max()!,vs.map(\.z).max()!))
    }
}

extension StationKitBuilder {
    private mutating func r200Face(_ points:[Map3DPoint],inside:Map3DPoint,color:UInt32) {
        var ps:[Map3DPoint]=[]
        for p in points { if !ps.contains(where:{ ($0-p).length < 0.000001 }) { ps.append(p) } }
        guard ps.count>=3 else { return }
        // A centre fan preserves every boundary split, including colour cuts.
        let mid=ps.reduce(Map3DPoint.zero,+)*(1/Float(ps.count))
        for i in ps.indices {
            let j=(i+1)%ps.count
            if (ps[i]-mid).cross(ps[j]-mid).length>0.00000001 { face([mid,ps[i],ps[j]],inside:inside,color:color) }
        }
    }
    private mutating func r200Prism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32, simple: Bool = false) {
        let c=(a+b).reduce(Map3DPoint.zero,+)*(1/Float(a.count+b.count))
        if simple {
            face(a,inside:c,color:color);face(b,inside:c,color:color)
            for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside:c,color:color) }
        } else {
            r200Face(a,inside:c,color:color);r200Face(b,inside:c,color:color)
            for i in a.indices { let j=(i+1)%a.count;r200Face([a[i],a[j],b[j],b[i]],inside:c,color:color) }
        }
    }
    // Thin solid fitted to the real raked end plane; no internal cab cover.
    private mutating func r200EndPanel(_ end: Float, _ points: [(Float,Float)], _ color: UInt32, depth: Float = 0.018, far: Bool) {
        func x(_ h: Float) -> Float { end * (9.45 - max(0,h-2.10)*0.39) }
        let a=points.map { Map3DPoint(x($0.1)-end*0.012,$0.1,$0.0) }
        let b=points.map { Map3DPoint(x($0.1)+end*(depth+0.002),$0.1,$0.0) }
        r200Prism(a,b,color,simple:far)
    }
    /// One closed concave casting, with a real knuckle opening. The cap is
    /// ear-clipped; overlapping bevelled boxes would duplicate corner faces.
    private mutating func r200Coupler(_ end:Float,_ color:UInt32,far:Bool) {
        let outline:[(Float,Float)]=far
            ? [(-0.19,0.84),(0.19,0.84),(0.19,0.98),(-0.055,0.98),(-0.055,1.08),(0.19,1.08),(0.19,1.22),(-0.19,1.22)]
            : [(-0.165,0.84),(0.165,0.84),(0.19,0.865),(0.19,0.955),(0.165,0.98),(-0.04,0.98),(-0.055,0.995),(-0.055,1.065),(-0.04,1.08),(0.165,1.08),(0.19,1.105),(0.19,1.195),(0.165,1.22),(-0.165,1.22),(-0.19,1.195),(-0.19,0.865)]
        let a=outline.map{Map3DPoint(end*9.755,$0.1,$0.0)},b=outline.map{Map3DPoint(end*10.005,$0.1,$0.0)}
        func cross(_ i:Int,_ j:Int,_ k:Int)->Float { let p=outline[i],q=outline[j],r=outline[k];return (q.0-p.0)*(r.1-p.1)-(q.1-p.1)*(r.0-p.0) }
        var indices=Array(outline.indices),triangles:[[Int]]=[]
        while indices.count>3 {
            var clipped=false
            for j in indices.indices {
                let i=indices[(j+indices.count-1)%indices.count],k=indices[j],l=indices[(j+1)%indices.count]
                guard cross(i,k,l)>0.0000001 else { continue }
                let blocked=indices.contains { v in v != i && v != k && v != l && cross(i,k,v)>=0 && cross(k,l,v)>=0 && cross(l,i,v)>=0 }
                if !blocked { triangles.append([i,k,l]);indices.remove(at:j);clipped=true;break }
            }
            precondition(clipped,"R200 casting polygon")
        }
        triangles.append(indices)
        for t in triangles {
            let mid=(a[t[0]]+a[t[1]]+a[t[2]])*(1/3 as Float)
            let inside=Map3DPoint(end*9.88,mid.y,mid.z)
            face(t.map{a[$0]},inside:inside,color:color);face(t.map{b[$0]},inside:inside,color:color)
        }
        for i in outline.indices {
            let j=(i+1)%outline.count,du=outline[j].0-outline[i].0,dv=outline[j].1-outline[i].1
            let inside=Map3DPoint(end*9.88,(outline[i].1+outline[j].1)/2+du*0.05,(outline[i].0+outline[j].0)/2-dv*0.05)
            face([a[i],a[j],b[j],b[i]],inside:inside,color:color)
        }
    }
    fileprivate mutating func r200Vehicle(far: Bool) {
        let white=Map3DR200.white, navy=Map3DR200.navy, dark=Map3DR200.dark, metal=Map3DR200.metal
        let glass=Map3DTrainStyle.glass
        // Independent closed body loft. Side navy and white boundary are the
        // shell faces themselves, not a second body or floating colour panel.
        let stations:[Float]=[-9.45,-8.75,-7.25,-6.7,0,6.7,7.25,8.75,9.45]
        func ring(_ x: Float) -> [Map3DPoint] {
            let t=max(0,(abs(x)-7.25)/2.2)
            func p(_ h:Float,_ z:Float)->Map3DPoint {
                Map3DPoint(x-(x>0 ? 1:-1)*max(0,h-2.10)*0.39*t,h,z)
            }
            let blueTop:Float=max(2.10,1.78+1.78*max(0,min(1,(7.25-abs(x))/0.55)))
            let roof:Float=abs(x)<=7.25 ? 3.78:4.0
            return [p(1.40,-1.426),p(1.40,1.426),p(1.78,1.426),p(2.10,1.426),p(blueTop,1.426),p(3.67,1.426),
                    p(roof,1.126),p(roof,-1.126),p(3.67,-1.426),p(blueTop,-1.426),p(2.10,-1.426),p(1.78,-1.426)]
        }
        let c=Map3DPoint(0,2.5,0)
        for k in 0..<stations.count-1 {
            let a=ring(stations[k]),b=ring(stations[k+1])
            for i in a.indices {
                let j=(i+1)%a.count
                let inside=Map3DPoint((a[i].x+a[j].x+b[j].x+b[i].x)/4,2.5,0)
                r200Face([a[i],a[j],b[j],b[i]],inside:inside,color:([2,3,9,10].contains(i) && max(abs(stations[k]),abs(stations[k+1]))<=7.25) ? navy:(i==6 ? dark:white))
            }
        }
        for end:Float in [-1,1] {
            // Broad raked front with chamfered roof corners. Independent end
            // panels, lamps and equipment; no long/short hood on this vehicle.
            let low:[(Float,Float)]=[(-1.426,1.40),(1.426,1.40),(1.426,1.78),(1.426,2.10),(-1.426,2.10),(-1.426,1.78)]
            let high:[(Float,Float)]=[(-1.426,2.10),(1.426,2.10),(1.426,3.67),(1.126,4.0),(-1.126,4.0),(-1.426,3.67)]
            for cap in [low,high] {
                r200Face(cap.map { Map3DPoint(end*(9.45-max(0,$0.1-2.10)*0.39),$0.1,$0.0) },inside:c,color:white)
            }
            r200EndPanel(end,[(-1.19,2.68),(0,2.61),(1.19,2.68),(1.17,3.59),(1.06,3.76),(0.62,3.88),(0,3.91),(-0.62,3.88),(-1.06,3.76),(-1.17,3.59)],dark,far:far)
            r200EndPanel(end,[(-1.09,2.82),(1.09,2.82),(1.07,3.55),(0.99,3.67),(-0.99,3.67),(-1.07,3.55)],glass,depth:0.040,far:far)
            // Recessed central front ventilation panel, the large dark
            // trapezoid below the white nose, distinct from the drawgear.
            r200EndPanel(end,[(-0.62,1.43),(0.62,1.43),(0.88,1.96),(-0.88,1.96)],dark,depth:0.026,far:far)
            for z:Float in (far ? [] : [1.52,1.66,1.80]) {
                let w:Float=0.62+(z-1.43)*0.49
                r200EndPanel(end,[(-w,z),(w,z),(w,z+0.025),(-w,z+0.025)],metal,depth:0.039,far:far)
            }
            // Upper number/display recess and actual lamp housings, no logos.
            r200EndPanel(end,[(-0.43,3.77),(0.43,3.77),(0.35,3.87),(-0.35,3.87)],navy,depth:0.025,far:far)
            for side:Float in [-1,1] {
                let z=side*0.99
                r200EndPanel(end,[(z-0.235,1.94),(z+0.235,1.94),(z+0.245,2.23),(z+0.20,2.29),(z-0.20,2.25)],dark,far:far)
                for u:Float in [-0.08,0.08] {
                    r200EndPanel(end,[(z+u-0.06,2.03),(z+u+0.06,2.03),(z+u+0.06,2.16),(z+u-0.06,2.16)],Map3DTrainStyle.headlamp,depth:0.035,far:far)
                }
                let low=Map3DPoint(end*9.49,1.58,side*1.25),bend=Map3DPoint(end*9.49,2.10,side*1.25)
                let high=Map3DPoint(end*9.2677,2.67,side*1.25)
                beam(low,bend,0.028,metal);beam(bend,high,0.028,metal)
                beam(low,Map3DPoint(end*9.445,1.58,side*1.25),0.028,metal)
                beam(high,Map3DPoint(end*9.223,2.67,side*1.25),0.028,metal)
                // Side cab window, rear door and real descending access steps.
                box(end*8.30,2.88,side*1.428,0.83,0.026,0.65,dark)
                box(end*8.30,2.93,side*1.445,0.73,0.014,0.55,glass)
                box(end*7.62,1.52,side*1.431,0.52,0.025,2.09,metal)
                box(end*7.62,1.56,side*1.448,0.46,0.012,2.00,white)
                box(end*7.62,2.92,side*1.460,0.29,0.012,0.49,glass)
                for step in 0..<4 { box(end*7.62,0.40+Float(step)*0.27,side*1.35,0.55,0.30,0.065,metal) }
                for dx:Float in [-0.25,0.25] {
                    beam(Map3DPoint(end*7.62+dx,0.38,side*1.32),Map3DPoint(end*7.62+dx,1.44,side*1.32),0.035,metal)
                }
                if !far { for dx:Float in [-0.35,0.35] {
                    beam(Map3DPoint(end*7.62+dx,1.40,side*1.48),Map3DPoint(end*7.62+dx,2.62,side*1.48),0.025,metal)
                    for h:Float in [1.43,2.59] { beam(Map3DPoint(end*7.62+dx,h,side*1.42),Map3DPoint(end*7.62+dx,h,side*1.48),0.025,metal) }
                } }
                if !far {
                    beam(Map3DPoint(end*8.50,2.76,side*1.47),Map3DPoint(end*8.50,3.31,side*1.47),0.025,dark)
                    // Windscreen wipers rest along the glass's lower edge.
                    beam(Map3DPoint(end*9.21,2.81,side*0.2),Map3DPoint(end*9.16,2.91,side*0.82),0.025,metal)
                }
            }
            // Open pilot: two side cheeks, crossmember, drawgear and hoses.
            box(end*9.18,1.20,0,0.48,2.55,0.18,dark)
            for side:Float in [-1,1] {
                box(end*9.25,0.30,side*1.05,0.25,0.39,0.90,dark)
                beam(Map3DPoint(end*9.32,0.30,side*0.90),Map3DPoint(end*9.32,1.20,side*0.56),0.065,metal)
                let valves:[UInt32]=[Map3DColor.rgb(0xB54C48),Map3DColor.rgb(0xD8D7D1),Map3DColor.rgb(0x467B9C),Map3DColor.rgb(0xE4BA42)]
                for (j,dz) in [Float(0.30),0.52,0.74,0.96].enumerated() {
                    let ps=[Map3DPoint(end*9.44,1.25,side*dz),Map3DPoint(end*9.53,0.96,side*(dz+0.01)),Map3DPoint(end*9.64,0.61,side*(dz+0.08)),Map3DPoint(end*9.60,0.33,side*(dz+0.07))]
                    for k in 0..<3 { civicTube(ps[k],ps[k+1],radius:0.024,color:dark,sides:far ? 4:6) }
                    box(end*9.46,1.15,side*dz,0.08,0.065,0.12,valves[j])
                    if !far {
                        for k in [1,2] { let a=ps[k],b=a+(ps[k+1]-a)*0.13;civicTube(a,b,radius:0.033,color:Map3DColor.rgb(0xD8D7D1),sides:6) }
                    }
                }
            }
            box(end*9.38,0.28,0,0.22,2.40,0.12,metal)
            box(end*9.56,0.91,0,0.75,0.23,0.24,dark)
            box(end*9.20,1.08,0,0.38,0.42,0.18,dark)
            r200Coupler(end,metal,far:far)
        }
        box(0,1.15,0,18.3,2.65,0.25,dark)
        box(-0.30,0.40,0,5.5,1.72,0.76,dark)
        for side:Float in [-1,1] {
            box(1.8,0.63,side*1.05,1.50,0.40,0.50,metal)
            // Photographed large grille stations; obscured opposite side is provisional.
            let vents:[Float]=[-3.4,3.2,4.5,5.8]
            for x in vents {
                box(x,1.94,side*1.435,0.92,0.022,1.40,dark)
                if x>0 {
                    for h:Float in [2.40,2.87] { box(x,h,side*1.452,0.85,0.014,0.025,metal) }
                    if !far {
                        for h:Float in [1.96,2.43,2.90] {
                            beam(Map3DPoint(x-0.40,h,side*1.455),Map3DPoint(x+0.40,h+0.40,side*1.455),0.026,metal)
                        }
                    }
                } else if !far {
                    for j in 0..<10 { box(x-0.40+Float(j)*0.088,2.0,side*1.452,0.022,0.014,1.27,metal) }
                }
            }
            box(-4.55,1.82,side*1.436,0.68,0.025,0.55,dark)
            if !far { for x:Float in [-3,0,3] { box(x,1.82,side*1.45,0.025,0.018,1.69,metal) } }
        }
        for centre:Float in [-5.90,5.90] {
            box(centre,0.77,0,0.80,1.60,0.33,dark)
            box(centre,0.78,0,3.70,0.60,0.21,dark)
            box(centre,1.07,0,0.70,0.60,0.14,dark)
            for dx:Float in [-1.50,0,1.50] {
                for side:Float in [-1,1] {
                    civicTube(Map3DPoint(centre+dx,0.50,side*0.48),Map3DPoint(centre+dx,0.50,side*0.68),radius:0.50,color:dark,sides:far ? 8:16)
                    box(centre+dx,0.40,side*0.89,0.30,0.26,0.25,metal)
                    box(centre+dx,0.60,side*0.91,0.22,0.20,0.26,dark)
                    if !far {
                        civicTube(Map3DPoint(centre+dx,0.50,side*0.677),Map3DPoint(centre+dx,0.50,side*0.705),radius:0.36,color:Map3DColor.shaded(metal,0.68),sides:12)
                        civicTube(Map3DPoint(centre+dx,0.50,side*0.675),Map3DPoint(centre+dx,0.50,side*0.85),radius:0.14,color:metal,sides:8)
                    }
                }
                beam(Map3DPoint(centre+dx,0.50,-0.90),Map3DPoint(centre+dx,0.50,0.90),0.13,metal)
            }
            for dx:Float in [-0.75,0.75] { beam(Map3DPoint(centre+dx,0.86,-0.97),Map3DPoint(centre+dx,0.86,0.97),0.13,dark) }
            for side:Float in [-1,1] {
                box(centre,0.815,side*0.97,4.08,0.13,0.13,dark)
                for dx:Float in [-0.75,0.75] {
                    beam(Map3DPoint(centre+dx-0.46,0.62,side*0.97),Map3DPoint(centre+dx,0.43,side*0.97),0.10,dark)
                    beam(Map3DPoint(centre+dx,0.43,side*0.97),Map3DPoint(centre+dx+0.46,0.62,side*0.97),0.10,dark)
                }
                for dx:Float in [-0.75,0.75] { cylinder(centre+dx,0.67,side*0.99,radius:0.16,height:0.35,color:metal,sides:far ? 6:10) }
            }
        }
        // Radiator fans at +X, long roof casing at -X, central exhaust. No pantographs or mirrored electric equipment.
        box(4.0,3.78,0,5.1,2.05,0.12,dark)
        let roofProfile:[(Float,Float)]=[(-1.05,3.78),(1.05,3.78),(1.05,3.97),(0.94,4.08),(-0.94,4.08),(-1.05,3.97)]
        r200Prism(roofProfile.map{Map3DPoint(-7,$0.1,$0.0)},roofProfile.map{Map3DPoint(-1,$0.1,$0.0)},metal,simple:far)
        for x:Float in [2.55,4.0,5.45] {
            cylinder(x,3.90,0,radius:0.64,height:0.09,color:metal,sides:far ? 8:16)
            if !far { for z:Float in [-0.4,-0.2,0,0.2,0.4] { box(x,3.989,z,1.0,0.025,0.012,dark) } }
        }
        box(0.20,3.78,0,2.4,1.30,0.16,metal)
        box(0.80,3.94,0,0.65,0.65,0.06,dark)
        for side:Float in [-1,1] {
            for x:Float in [-0.60,0.55] { beam(Map3DPoint(x,3.93,side*0.46),Map3DPoint(x,4.015,side*0.46),0.06,metal) }
            civicTube(Map3DPoint(-0.65,4.015,side*0.46),Map3DPoint(0.60,4.015,side*0.46),radius:0.035,color:Map3DColor.rgb(0x9B7864),sides:far ? 4:8)
        }
    }
}
