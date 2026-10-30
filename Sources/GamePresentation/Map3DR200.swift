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
        return .flat(named: ids[far ? 1 : 0], from: b.mesh)
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
        let a=points.map { Map3DPoint(x($0.1)+end*0.002,$0.1,$0.0) }
        let b=a.map { Map3DPoint($0.x+end*depth,$0.y,$0.z) }
        r200Prism(a,b,color,simple:far)
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
            return [p(1.40,-1.426),p(1.40,1.426),p(1.78,1.426),p(2.10,1.426),p(blueTop,1.426),p(3.67,1.426),
                    p(4.0,1.126),p(4.0,-1.126),p(3.67,-1.426),p(blueTop,-1.426),p(2.10,-1.426),p(1.78,-1.426)]
        }
        let c=Map3DPoint(0,2.5,0)
        for k in 0..<stations.count-1 {
            let a=ring(stations[k]),b=ring(stations[k+1])
            for i in a.indices {
                let j=(i+1)%a.count
                r200Face([a[i],a[j],b[j],b[i]],inside:c,color:([2,3,9,10].contains(i) && max(abs(stations[k]),abs(stations[k+1]))<=7.25) ? navy:(i==6 ? dark:white))
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
            r200EndPanel(end,[(-1.12,2.68),(1.12,2.68),(1.10,3.54),(0.84,3.78),(-0.84,3.78),(-1.10,3.54)],dark,far:far)
            r200EndPanel(end,[(-1.01,2.84),(1.01,2.84),(1.00,3.48),(-1.00,3.48)],glass,depth:0.040,far:far)
            // Recessed central front ventilation panel, the large dark
            // trapezoid below the white nose, distinct from the drawgear.
            r200EndPanel(end,[(-0.62,1.43),(0.62,1.43),(0.88,1.96),(-0.88,1.96)],dark,depth:0.026,far:far)
            for z:Float in (far ? [] : [1.52,1.66,1.80]) {
                let w:Float=0.62+(z-1.43)*0.49
                r200EndPanel(end,[(-w,z),(w,z),(w,z+0.025),(-w,z+0.025)],metal,depth:0.039,far:far)
            }
            // Upper number/display recess and actual lamp housings, no logos.
            r200EndPanel(end,[(-0.43,3.60),(0.43,3.60),(0.35,3.73),(-0.35,3.73)],navy,depth:0.025,far:far)
            for side:Float in [-1,1] {
                let z=side*0.99
                r200EndPanel(end,[(z-0.21,1.97),(z+0.21,1.97),(z+0.21,2.23),(z-0.21,2.19)],dark,far:far)
                r200EndPanel(end,[(z-0.145,2.03),(z+0.145,2.03),(z+0.145,2.15),(z-0.145,2.15)],Map3DTrainStyle.headlamp,depth:0.035,far:far)
                beam(Map3DPoint(end*9.32,1.58,side*1.25),Map3DPoint(end*9.25,2.67,side*1.25),0.028,metal)
                // Side cab window, rear door and real descending access steps.
                box(end*8.30,2.88,side*1.428,0.83,0.026,0.65,dark)
                box(end*8.30,2.93,side*1.445,0.73,0.014,0.55,glass)
                box(end*7.62,1.52,side*1.431,0.52,0.025,2.09,metal)
                box(end*7.62,1.56,side*1.448,0.46,0.012,2.00,white)
                box(end*7.62,2.92,side*1.460,0.29,0.012,0.49,glass)
                for step in 0..<4 { box(end*7.62,0.40+Float(step)*0.27,side*1.35,0.55,0.30,0.065,metal) }
                for dx:Float in [-0.35,0.35] { beam(Map3DPoint(end*7.62+dx,1.40,side*1.48),Map3DPoint(end*7.62+dx,2.62,side*1.48),0.025,metal) }
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
                if !far {
                    for dz:Float in [0.34,0.60,0.83] {
                        beam(Map3DPoint(end*9.45,1.20,side*dz),Map3DPoint(end*9.48,0.43,side*(dz+0.04)),0.033,dark)
                        box(end*9.49,0.45,side*(dz+0.04),0.06,0.07,0.09,Map3DColor.rgb(0xE4BA42))
                    }
                }
            }
            box(end*9.38,0.28,0,0.22,2.40,0.12,metal)
            box(end*9.56,0.91,0,0.75,0.23,0.24,dark)
            box(end*9.88,0.84,0,0.25,0.38,0.38,metal)
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
                    if !far { for h:Float in [2.40,2.87] { box(x,h,side*1.452,0.85,0.014,0.025,metal) } }
                    if !far {
                        for h:Float in [1.96,2.43,2.90] {
                            beam(Map3DPoint(x-0.40,h,side*1.455),Map3DPoint(x+0.40,h+0.40,side*1.455),0.026,metal)
                        }
                    }
                } else if !far {
                    for j in 0..<10 { box(x,2.0+Float(j)*0.125,side*1.452,0.85,0.014,0.025,metal) }
                }
            }
            box(-4.55,1.82,side*1.436,0.68,0.025,0.55,dark)
            if !far { for x:Float in [-3,0,3] { box(x,1.82,side*1.45,0.025,0.018,1.69,metal) } }
        }
        for centre:Float in [-5.90,5.90] {
            box(centre,0.67,0,4.25,1.60,0.42,dark)
            for dx:Float in [-1.50,0,1.50] {
                for side:Float in [-1,1] {
                    civicTube(Map3DPoint(centre+dx,0.50,side*0.48),Map3DPoint(centre+dx,0.50,side*0.68),radius:0.50,color:dark,sides:far ? 8:16)
                    box(centre+dx,0.50,side*0.91,0.35,0.30,0.32,metal)
                    if !far { civicTube(Map3DPoint(centre+dx,0.50,side*0.69),Map3DPoint(centre+dx,0.50,side*0.85),radius:0.15,color:metal,sides:8) }
                }
                beam(Map3DPoint(centre+dx,0.50,-0.48),Map3DPoint(centre+dx,0.50,0.48),0.13,metal)
            }
            for side:Float in [-1,1] {
                box(centre,0.76,side*0.94,4.08,0.17,0.22,dark)
                for dx:Float in [-0.75,0.75] { cylinder(centre+dx,0.67,side*0.99,radius:0.16,height:0.35,color:metal,sides:far ? 6:10) }
            }
        }
        // Radiator fans at +X, long roof casing at -X, central exhaust. No pantographs or mirrored electric equipment.
        box(4.0,3.96,0,5.1,2.05,0.06,dark)
        box(-4.0,3.98,0,6.0,2.10,0.10,metal)
        for x:Float in [2.55,4.0,5.45] {
            cylinder(x,4.02,0,radius:0.64,height:0.045,color:metal,sides:far ? 6:16)
            if !far { for z:Float in [-0.4,-0.2,0,0.2,0.4] { box(x,4.064,z,1.0,0.025,0.009,dark) } }
        }
        box(0.20,3.98,0,2.4,1.30,0.10,metal)
        box(0.80,4.04,0,0.65,0.65,0.04,dark)
    }
}
