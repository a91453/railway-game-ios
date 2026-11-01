import Foundation

/// EMD G22U / TRA R100: R122 orange era and R123 Breezy Blue, 22 January 2023.
/// Metres, native +X SHORT hood, +Y left looking toward +X, +Z up, rail Z=0.
/// +X is a modelling convention; the official end numbering is not established.
/// The TTSB class envelope is 15.800 x 2.950 x 3.920 m; its length datum is
/// unspecified. Coupler faces at +/-7.9 below are a display assembly contract,
/// not a claim that the published length was measured between coupler faces.
public enum Map3DR100 {
    public enum Livery: String, CaseIterable, Sendable {
        case orange, breezyBlue
        public var identifier: String {
            self == .orange ? "tra-r100-r122-orange-locomotive" : "tra-r100-r123-breezy-blue-locomotive"
        }
        public var representativeNumber: String { self == .orange ? "R122" : "R123" }
        public var body: UInt32 { Map3DColor.rgb(self == .orange ? 0xE76E32 : 0x243E59) }
        /// R123's documented 2019 restoration painted the roof navy as well;
        /// the ordinary orange-era R122 keeps its grey roof.
        public var roof: UInt32 { self == .orange ? Map3DR100.roof : Map3DColor.rgb(0x30475C) }
    }
    public static let length: Float = 15.8
    public static let width: Float = 2.95
    public static let height: Float = 3.92
    public static let white = Map3DColor.rgb(0xEEEFE8)
    public static let dark = Map3DColor.rgb(0x30363A)
    public static let roof = Map3DColor.rgb(0x727B81)
    public static let metal = Map3DColor.rgb(0x626B70)
    public static let yellow = Map3DColor.rgb(0xE8BC35)
    /// Unpublished dimensions: photo-informed simplifications, not engineering data.
    public static let bogieCentres: [Float] = [-4.55,4.55]
    public static let axleOffsets: [Float] = [-1.35,0,1.35]
    public static func model(livery: Livery = .orange, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.r100Vehicle(livery: livery, far: far)
        return .flat(named: livery.identifier + (far ? "-far" : ""), from: b.mesh)
    }
}

extension StationKitBuilder {
    /// A colour partition of one real shell triangle. Intersections are computed
    /// from original linearly interpolated values; paint never adds another shell.
    private mutating func r100PaintFace(_ points: [Map3DPoint], inside: Map3DPoint,
                                        levels: [Float], value: (Map3DPoint)->Float,
                                        colour: (Float)->UInt32) {
        struct P { var p: Map3DPoint; var d: Float }
        func clip(_ ps: [P], _ level: Float, above: Bool) -> [P] {
            var out: [P] = []
            guard !ps.isEmpty else { return [] }
            for i in ps.indices {
                let a=ps[i],b=ps[(i+1)%ps.count]
                let ai=above ? a.d>=level : a.d<=level,bi=above ? b.d>=level : b.d<=level
                if ai { out.append(a) }
                if ai != bi {
                    let t=(level-a.d)/(b.d-a.d)
                    out.append(P(p:a.p+(b.p-a.p)*t,d:level))
                }
            }
            var clean:[P]=[]
            for p in out where !clean.contains(where: { ($0.p-p.p).length<0.0000001 }) { clean.append(p) }
            return clean
        }
        // A centre fan preserves all specified cap boundary vertices.
        let centre=points.reduce(Map3DPoint.zero,+)*(1/Float(points.count))
        for i in points.indices {
            let tri=[centre,points[i],points[(i+1)%points.count]]
            guard (tri[1]-tri[0]).cross(tri[2]-tri[0]).length>0.00000001 else { continue }
            let ps=tri.map { P(p:$0,d:value($0)) }
            let cuts=[-Float.infinity]+levels+[Float.infinity]
            for j in 0..<(cuts.count-1) {
                var q=ps
                if cuts[j].isFinite { q=clip(q,cuts[j],above:true) }
                if cuts[j+1].isFinite { q=clip(q,cuts[j+1],above:false) }
                guard q.count>=3 else { continue }
                let mid=q.map(\.d).reduce(0,+)/Float(q.count)
                for k in 1..<(q.count-1) {
                    let p=[q[0].p,q[k].p,q[k+1].p]
                    if (p[1]-p[0]).cross(p[2]-p[0]).length>0.00000001 { face(p,inside:inside,color:colour(mid)) }
                }
            }
        }
    }
    private mutating func r100Prism(_ a: [Map3DPoint],_ b: [Map3DPoint],_ colour: UInt32) {
        let c=(a+b).reduce(Map3DPoint.zero,+)*(1/Float(a.count+b.count))
        face(a,inside:c,color:colour);face(b,inside:c,color:colour)
        for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside:c,color:colour) }
    }
    private mutating func r100Hood(_ x0:Float,_ x1:Float,_ top:Float,_ half:Float,
                                   livery:Map3DR100.Livery,short:Bool) {
        let body=livery.body,white=Map3DR100.white,grey=livery.roof
        let shortStations:[Float] = [-half,-0.90,-0.72,-0.40,0,0.40,0.72,0.90,half]
        func shortTop(_ z:Float)->Float {
            abs(z)<=half-0.18 ? top-0.03*abs(z)/(half-0.18) : top-0.03-0.19*(abs(z)-half+0.18)/0.18
        }
        func ring(_ x:Float)->[Map3DPoint] {
            if short {
                return shortStations.map { Map3DPoint(x,1.48,$0) }
                    + shortStations.reversed().map { Map3DPoint(x,shortTop($0),$0) }
            }
            return [Map3DPoint(x,1.48,-half),Map3DPoint(x,1.48,0),Map3DPoint(x,1.48,half),
             Map3DPoint(x,top-0.22,half),Map3DPoint(x,top-0.03,half-0.18),
             Map3DPoint(x,top,0),Map3DPoint(x,top-0.03,-half+0.18),Map3DPoint(x,top-0.22,-half)]
        }
        // Each longitudinal station is a complete section, including the colour
        // transition from high side band to the long-end low horizontal band.
        let xs: [Float] = short ? [x0,x1] : [x0,-5.05,-4.65,-4.15,-3.65,-3.10,x1]
        func stripe(_ p:Map3DPoint)->Float {
            if short {
                let t=max(0,min(1,(p.x-x0)/(x1-x0)))
                // The characteristic curved white wings narrow to a low
                // central point. These lateral stations are real shell cuts.
                return 2.33*(1-t)+(1.69+0.64*sqrt(abs(p.z)/half))*t
            }
            let t=max(0,min(1,(p.x+5.05)/1.95)),e=t*t*(3-2*t)
            return 1.59+0.74*e
        }
        func paint(_ ps:[Map3DPoint],_ centre:Map3DPoint,_ isRoof:Bool) {
            r100PaintFace(ps,inside:centre,levels:[0,0.14],value:{ $0.y-stripe($0) },colour:{ d in
                if isRoof { return grey }
                return d>=0 && d<=0.14 ? white : body
            })
        }
        for n in 0..<(xs.count-1) {
            let a=ring(xs[n]),b=ring(xs[n+1]),c=Map3DPoint((xs[n]+xs[n+1])/2,2.3,0)
            for i in a.indices {
                let j=(i+1)%a.count
                let isRoof = short ? i>=shortStations.count && i<shortStations.count*2-1 : i>=3 && i<=6
                paint([a[i],a[j],b[j],b[i]],c,isRoof)
            }
        }
        for x in [x0,x1] {
            let c=Map3DPoint((x0+x1)/2,2.3,0)
            if short {
                for i in 0..<(shortStations.count-1) {
                    let z0=shortStations[i],z1=shortStations[i+1]
                    paint([Map3DPoint(x,1.48,z0),Map3DPoint(x,1.48,z1),
                           Map3DPoint(x,shortTop(z1),z1),Map3DPoint(x,shortTop(z0),z0)],c,false)
                }
            } else { paint(ring(x),c,false) }
        }
    }
    private mutating func r100Cab(_ livery:Map3DR100.Livery) {
        let body=livery.body
        let a:[Map3DPoint]=[Map3DPoint(3.18,1.48,-1.44),Map3DPoint(3.18,1.48,1.44),
            Map3DPoint(3.18,3.44,1.44),Map3DPoint(3.18,3.54,1.40),Map3DPoint(3.18,3.67,1.28),Map3DPoint(3.18,3.76,1.10),
            Map3DPoint(3.18,3.80,0),Map3DPoint(3.18,3.76,-1.10),Map3DPoint(3.18,3.44,-1.44)]
        let cabProfile=Array(a.dropLast())+[Map3DPoint(3.18,3.67,-1.28),Map3DPoint(3.18,3.54,-1.40),a.last!]
        let b=cabProfile.map { Map3DPoint(5.22,$0.y,$0.z) },c=Map3DPoint(4.2,2.5,0)
        for p in [cabProfile,b] { r100PaintFace(p,inside:c,levels:[2.33,2.47],value:{$0.y},colour:{ $0>=2.33 && $0<=2.47 ? Map3DR100.white:body }) }
        for i in cabProfile.indices { let j=(i+1)%cabProfile.count
            r100PaintFace([cabProfile[i],cabProfile[j],b[j],b[i]],inside:c,levels:[2.33,2.47],value:{$0.y},colour:{ h in
                if i>=2 && i<=cabProfile.count-2 { return livery.roof }
                return h>=2.33 && h<=2.47 ? Map3DR100.white:body
            })
        }
    }
    private mutating func r100EndPane(_ end:Float,_ x:Float,_ lo:Float,_ hi:Float,_ z0:Float,_ z1:Float,_ colour:UInt32) {
        let a=[Map3DPoint(x,lo,z0),Map3DPoint(x,lo,z1),Map3DPoint(x,hi,z1),Map3DPoint(x,hi,z0)]
        let b=a.map { Map3DPoint($0.x+end*0.022,$0.y,$0.z) }
        r100Prism(a,b,colour)
    }
    private mutating func r100Windshield(_ end:Float,_ x:Float,_ lo:Float,_ hi:Float,_ z0:Float,_ z1:Float) {
        let r:Float=0.055
        let points:[(Float,Float)]=[(lo,z0+r),(lo,z1-r),(lo+r,z1),(hi-r,z1),
                                     (hi,z1-r),(hi,z0+r),(hi-r,z0),(lo+r,z0)]
        let a=points.map { Map3DPoint(x,$0.0,$0.1) }
        r100Prism(a,a.map { Map3DPoint($0.x+end*0.022,$0.y,$0.z) },Map3DTrainStyle.glass)
    }
    private mutating func r100Pilot(_ end:Float) {
        let a=[Map3DPoint(end*7.26,0.38,-1.30),Map3DPoint(end*7.26,0.38,1.30),
               Map3DPoint(end*7.26,1.48,1.30),Map3DPoint(end*7.26,1.48,-1.30)]
        let b=a.map { Map3DPoint(end*7.40,$0.y,$0.z) },c=Map3DPoint(end*7.33,0.9,0)
        func paint(_ p:[Map3DPoint]) {
            r100PaintFace(p,inside:c,levels:Array(stride(from:Float(-1),through:2,by:0.22)),value:{$0.y-0.82*abs($0.z)},colour:{ d in
                Int(floor((d+1)/0.22))%2==0 ? Map3DR100.yellow:Map3DR100.dark
            })
        }
        paint(a);paint(b)
        for i in a.indices { let j=(i+1)%a.count;paint([a[i],a[j],b[j],b[i]]) }
        // The lower snowplough is a separate real fitting on the pilot.
        let p=[Map3DPoint(end*7.42,0.17,-1.05),Map3DPoint(end*7.42,0.17,1.05),
               Map3DPoint(end*7.40,0.52,1.14),Map3DPoint(end*7.40,0.52,-1.14)]
        r100Prism(p,p.map{Map3DPoint($0.x-end*0.06,$0.y,$0.z)},Map3DR100.metal)
    }
    fileprivate mutating func r100Vehicle(livery:Map3DR100.Livery,far:Bool) {
        let body=livery.body,dark=Map3DR100.dark,white=Map3DR100.white,metal=Map3DR100.metal
        let glass=Map3DTrainStyle.glass
        // Independent R100 proportions, not the common hoodUnit/R200 body.
        box(0,1.24,0,14.90,2.86,0.24,dark)
        box(0,1.08,0,14.2,2.25,0.16,dark)
        r100Hood(-7.12,3.18,3.53,1.08,livery:livery,short:false)
        r100Cab(livery)
        for side:Float in [-1,1] { box(4.20,3.44,side*1.4575,2.04,0.035,0.025,livery.roof) }
        r100Hood(5.22,7.10,2.80,1.08,livery:livery,short:true)
        // A1A-A1A: middle wheels are unpowered and visibly smaller. Every tyre
        // touches the common rail, independently of the frame's lower bound.
        for centre in Map3DR100.bogieCentres {
            box(centre,0.84,0,3.62,1.48,0.22,dark)
            box(centre,1.06,0,0.78,1.18,0.18,metal)
            for side:Float in [-1,1] {
                for dx in Map3DR100.axleOffsets {
                    let r:Float=dx==0 ? 0.43:0.508
                    civicTube(Map3DPoint(centre+dx,r,side*0.5335),Map3DPoint(centre+dx,r,side*0.7135),radius:r,color:dark,sides:far ? 8:16)
                    if !far { civicTube(Map3DPoint(centre+dx,r,side*0.714),Map3DPoint(centre+dx,r,side*0.75),radius:0.16,color:metal,sides:8) }
                    if !far { box(centre+dx,0.47,side*0.80,0.32,0.18,0.30,metal) }
                }
                // Open cast frame: the arch between the idler and powered axles
                // remains visible rather than filling it with a solid bogie box.
                for dx:Float in [-0.70,0.70] {
                    beam(Map3DPoint(centre+dx-0.55,0.77,side*0.80),Map3DPoint(centre+dx+0.55,0.63,side*0.80),0.15,metal)
                    if !far {
                        box(centre+dx,0.53,side*0.86,0.38,0.20,0.055,dark)
                        for z:Float in [0.59,0.645,0.70,0.755] { box(centre+dx,z,side*0.86,0.28,0.20,0.027,metal) }
                    }
                }
                let arch:[(Float,Float)] = far ? [(-1.62,0.83),(-0.90,0.91),(0,0.81),(0.90,0.91),(1.62,0.83)]
                    : [(-1.62,0.83),(-1.35,0.92),(-0.94,0.92),(-0.67,0.81),(-0.32,0.79),(0,0.84),(0.32,0.79),(0.67,0.81),(0.94,0.92),(1.35,0.92),(1.62,0.83)]
                for i in 0..<(arch.count-1) {
                    beam(Map3DPoint(centre+arch[i].0,arch[i].1,side*0.86),Map3DPoint(centre+arch[i+1].0,arch[i+1].1,side*0.86),0.11,metal)
                }
            }
        }
        // Fuel tank has a shallow sloping lower edge; two right-side air
        // reservoirs are distinct fittings, not a second fuel tank.
        let ta=[Map3DPoint(-2.50,0.40,-0.88),Map3DPoint(-2.50,0.40,0.88),Map3DPoint(-2.50,1.08,0.88),Map3DPoint(-2.50,1.08,-0.88)]
        let tb=ta.map { Map3DPoint(1.35,$0.y,$0.z) }
        r100Prism(ta,tb,dark)
        for x:Float in [-2.05,-0.75] { civicTube(Map3DPoint(x-0.48,1.00,0.98),Map3DPoint(x+0.48,1.00,0.98),radius:0.14,color:metal,sides:far ? 8:12) }
        for side:Float in [-1,1] {
            // Cab's cream door/window surround is a real thin door panel.
            box(3.89,2.58,side*1.447,1.14,0.018,0.91,white)
            for x:Float in [3.65,4.14] { box(x,2.97,side*1.461,0.32,0.018,0.44,glass) }
            box(4.78,2.94,side*1.447,0.55,0.018,0.48,glass)
            if !far {
                box(4.42,2.40,side*1.455,0.055,0.025,0.24,metal)
                beam(Map3DPoint(4.45,1.49,side*1.45),Map3DPoint(4.45,2.58,side*1.45),0.035,white)
            }
            // R100 has end-platform rails. No invented continuous railing runs
            // down both sides of its long hood.
            for end:Float in [-1,1] {
                let x0:Float=end>0 ? 5.30:-7.20,x1:Float=end>0 ? 7.28:-6.88
                beam(Map3DPoint(x0,2.44,side*1.44),Map3DPoint(x1,2.44,side*1.44),0.045,white)
                for x in [x0,x1] { beam(Map3DPoint(x,1.48,side*1.44),Map3DPoint(x,2.44,side*1.44),0.045,white) }
                // Three accessible treads on two vertical stiles.
                for level:Float in [0.48,0.81,1.14] { box(end*6.99,level,side*1.23,0.59,0.43,0.055,metal) }
                for x:Float in [6.70,7.28] { beam(Map3DPoint(end*x,0.45,side*1.42),Map3DPoint(end*x,1.47,side*1.42),0.05,dark) }
            }
        }
        // Two short-end windscreens on the actual cab end, distinct from its
        // lower nose. Backward-facing cab windows flank the long hood.
        for side:Float in [-1,1] {
            r100Windshield(1,5.22,2.94,3.46,side>0 ? 0.13:-1.08,side>0 ? 1.08:-0.13)
            r100Windshield(1,5.22,2.96,3.38,side>0 ? 1.15:-1.35,side>0 ? 1.35:-1.15)
            r100EndPane(-1,3.18,2.96,3.42,side>0 ? 1.10:-1.35,side>0 ? 1.35:-1.10,glass)
            if !far {
                beam(Map3DPoint(5.248,2.96,side*0.25),Map3DPoint(5.248,3.33,side*0.69),0.018,dark)
            }
        }
        // Stacked central lamps and number boards, independently placed at
        // short cab end and high long-hood end (no phantom second cab).
        for end:Float in [-1,1] {
            let x:Float=end>0 ? 5.22:-7.12
            let lo:Float=end>0 ? 3.51:3.11
            r100EndPane(end,x,lo-0.04,lo+0.31,-0.14,0.14,dark)
            for h in [lo+0.05,lo+0.23] {
                civicTube(Map3DPoint(x+end*0.021,h,0),Map3DPoint(x+end*0.085,h,0),radius:0.083,color:Map3DPalette.tunnelLamp,sides:far ? 8:12)
            }
            for side:Float in [-1,1] {
                r100EndPane(end,x,lo+0.10,lo+0.31,side*0.60-0.25,side*0.60+0.25,dark)
                civicTube(Map3DPoint(end>0 ? 7.10:-7.12,2.55,side*0.88),Map3DPoint((end>0 ? 7.10:-7.12)+end*0.055,2.55,side*0.88),radius:0.063,color:Map3DColor.rgb(0x943D36),sides:far ? 8:12)
            }
            r100Pilot(end)
            box(end*7.42,0.88,0,0.55,0.34,0.25,dark)
            // Knuckle is bounded by the documented display connection plane.
            box(end*7.74,0.89,0,0.32,0.35,0.23,metal)
            if !far {
                for side:Float in [-1,1] { beam(Map3DPoint(end*7.46,1.18,side*0.40),Map3DPoint(end*7.53,0.65,side*0.33),0.055,dark) }
            }
        }
        // Long-end radiator sides: large opening plus narrow neighbouring
        // intake, as in the 2005-onwards refitted grille doors.
        for side:Float in [-1,1] {
            box(-6.34,1.72,side*1.089,1.12,0.018,1.16,dark)
            box(-5.47,1.74,side*1.089,0.38,0.018,1.15,dark)
            let count=far ? 1:14
            for i in 0..<count { box(-6.84+(count==1 ? 0.5:Float(i)*1.0/Float(count-1)),1.74,side*1.104,0.022,0.018,1.10,metal) }
            // Engine doors and louvres are part of a narrower long hood.
            for x:Float in [-1.85,-0.95,0.48,1.45,2.35] {
                box(x,2.33,side*1.09,0.52,0.018,0.92,Map3DColor.shaded(body,0.75))
                if !far { for i in 0..<8 { box(x,2.39+Float(i)*0.095,side*1.104,0.48,0.018,0.026,metal) } }
            }
            if !far {
                for x:Float in stride(from:-6.9,through:2.8,by:0.78) {
                    box(x,1.59,side*1.095,0.025,0.018,1.56,Map3DColor.shaded(body,0.88))
                    // The long engine-hood access doors have small latches;
                    // retain these only near the viewer, not in the far mesh.
                    box(x+0.09,1.88,side*1.104,0.075,0.025,0.055,metal)
                }
            }
        }
        // Roof radiator grille at the LONG end, one exhaust stack further
        // toward the engine, and the separately supported cab air conditioner.
        box(-5.85,3.51,0,1.90,1.57,0.035,dark)
        for z:Float in [-0.55,0,0.55] { box(-5.85,3.545,z,1.85,0.025,0.025,metal) }
        box(-0.65,3.50,0,0.62,0.55,0.13,dark)
        box(-0.65,3.63,0,0.44,0.37,0.10,dark)
        // Two shallow saddles follow the sloping cab crown. The appliance
        // touches these feet over an area, rather than only the centre ridge.
        for side:Float in [-1,1] { box(3.90,3.785,side*0.34,0.80,0.13,0.015,metal) }
        box(3.90,3.80,0,0.91,0.90,0.12,metal)
        if !far { for z:Float in [-0.28,0,0.28] { box(3.90,3.919,z,0.68,0.025,0.001,dark) } }
        // Roof-mounted air horn at the short end, visibly offset rather than
        // mirrored into fictitious equipment on the opposite side of the cab.
        box(4.98,3.72,-0.51,0.28,0.16,0.08,dark)
        civicTube(Map3DPoint(4.83,3.85,-0.51),Map3DPoint(5.45,3.85,-0.51),radius:0.07,color:dark,sides:far ? 6:8)
    }
}
