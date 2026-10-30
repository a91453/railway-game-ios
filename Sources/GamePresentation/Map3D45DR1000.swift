import Foundation

/// TRA 45DR1000 / DRC1025, 2006–08 orange and yellow stainless livery.
/// Fittings and height are photographic estimates; length and width follow the published type dimensions.
public enum Map3D45DR1000 {
    public static let length: Float = 19.774
    public static let width: Float = 2.690
    public static let silver = Map3DColor.rgb(0xBBBDB9)
    public static let orange = Map3DColor.rgb(0xE77448)
    public static let yellow = Map3DColor.rgb(0xE9BB3B)
    public static let roof = Map3DColor.rgb(0x777D7C)
    public static let dark = Map3DColor.rgb(0x30343A)
    public static let glass = Map3DTrainStyle.glass
    public static func model(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.dr1000(far: far)
        return .flat(named: far ? "45dr1000-drc1025-far" : "45dr1000-drc1025", from: b.mesh)
    }
}

extension StationKitBuilder {
    private mutating func drPrism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let inside = (a+b).reduce(Map3DPoint.zero,+) * (1/Float(a.count+b.count))
        face(a,inside:inside,color:color); face(b,inside:inside,color:color)
        for i in a.indices { let j=(i+1)%a.count; face([a[i],a[j],b[j],b[i]],inside:inside,color:color) }
    }
    private mutating func drShell(_ x0: Float,_ x1: Float,_ bottom: Float,_ top: Float,_ color: UInt32) {
        func p(_ x:Float)->[Map3DPoint] { [Map3DPoint(x,bottom,-1.345),Map3DPoint(x,bottom,1.345),Map3DPoint(x,top,1.345),Map3DPoint(x,top,-1.345)] }
        drPrism(p(x0),p(x1),color)
    }
    /// A shallow raised casting on a cab end. Coordinates are height and lateral
    /// position in metres; there is no shared locomotive/end-cab geometry.
    private mutating func drEndPanel(_ end: Float,_ x: Float,_ outline: [(Float,Float)],_ depth: Float,_ color: UInt32) {
        let back=outline.map { Map3DPoint(x+end*(depth-0.025),$0.0,$0.1) }
        let front=outline.map { Map3DPoint(x+end*depth,$0.0,$0.1) }
        drPrism(back,front,color)
    }
    mutating func dr1000(far: Bool) {
        let silver=Map3D45DR1000.silver, orange=Map3D45DR1000.orange
        let yellow=Map3D45DR1000.yellow, dark=Map3D45DR1000.dark
        let glass=Map3D45DR1000.glass
        // Long, narrow body. The stripe is part of the shell and continues on the ends.
        // The photographed orange waist occupies about one fifth of the
        // window height. Its lower edge is estimated from the 2006/08 photos.
        drShell(-9.62,9.62,1.12,2.02,silver)
        drShell(-9.62,9.62,2.02,2.20,orange)
        drShell(-9.62,9.62,2.20,3.05,silver)
        drShell(-9.62,9.62,3.05,3.15,yellow)
        drShell(-9.62,9.62,3.15,3.26,silver)
        // Six-facet rounded shoulder, substantially narrower at the crown than the sidewall.
        func roofProfile(_ x:Float)->[Map3DPoint] {
            [Map3DPoint(x,3.26,-1.345),Map3DPoint(x,3.26,1.345),
             Map3DPoint(x,3.46,1.22),Map3DPoint(x,3.58,0.94),Map3DPoint(x,3.62,0),
             Map3DPoint(x,3.58,-0.94),Map3DPoint(x,3.46,-1.22)]
        }
        drPrism(roofProfile(-9.62),roofProfile(9.62),Map3D45DR1000.roof)
        // Both ends have cab windows and a central gangway, not a G12 hood or cab.
        for end:Float in [-1,1] {
            let x=end*9.65
            // On DRC1025 the orange brow rolls over the roof shoulder. The
            // yellow panel below it remains visible between three dark openings.
            drEndPanel(end,x,[(1.25,-1.22),(1.25,1.22),(3.13,1.22),
                              (3.19,1.17),(3.19,-1.17),(3.13,-1.22)],0.055,yellow)
            drEndPanel(end,x,[(3.13,-1.22),(3.13,1.22),(3.32,1.17),
                              (3.43,0.93),(3.46,0),(3.43,-0.93),
                              (3.32,-1.17)],0.064,orange)
            for side:Float in [-1,1] {
                // The cab corner turns from the 2.69 m sidewall into the
                // slightly narrower end instead of ending at a square seam.
                let outer=side*1.345, inner=side*1.29
                let a=[Map3DPoint(end*9.37,1.25,outer),Map3DPoint(end*9.37,1.25,inner),
                       Map3DPoint(end*9.37,3.16,inner),Map3DPoint(end*9.37,3.16,outer)]
                let b=[Map3DPoint(end*9.69,1.25,side*1.22),Map3DPoint(end*9.69,1.25,side*1.17),
                       Map3DPoint(end*9.69,3.16,side*1.17),Map3DPoint(end*9.69,3.16,side*1.22)]
                drPrism(a,b,yellow)
                if far {
                    box(x+end*0.073,2.17,side*0.82,0.025,0.76,1.06,dark)
                    box(x+end*0.089,2.21,side*0.82,0.016,0.65,0.97,glass)
                    box(x+end*0.111,2.98,side*0.88,0.019,0.18,0.16,
                        Map3DPalette.tunnelLamp)
                } else {
                    func roundedWindow(_ base:Float,_ half:Float,_ top:Float) -> [(Float,Float)] {
                        let centre=side*0.82
                        return [(base,centre-half+0.05),(base,centre+half-0.05),
                                (base+0.05,centre+half),(top-0.16,centre+half),
                                (top-0.05,centre+half-0.07),(top,centre+half-0.20),
                                (top,centre-half+0.20),(top-0.05,centre-half+0.07),
                                (top-0.16,centre-half),(base+0.05,centre-half)]
                    }
                    drEndPanel(end,x,roundedWindow(2.15,0.38,3.25),0.085,dark)
                    drEndPanel(end,x,roundedWindow(2.22,0.32,3.18),0.104,glass)
                    // Lamp and its dark circular bezel sit in the black cab field.
                    civicTube(Map3DPoint(x+end*0.108,3.04,side*0.88),
                              Map3DPoint(x+end*0.137,3.04,side*0.88),
                              radius:0.145,color:Map3DColor.rgb(0x202428),sides:12)
                    civicTube(Map3DPoint(x+end*0.139,3.04,side*0.88),
                              Map3DPoint(x+end*0.151,3.04,side*0.88),
                              radius:0.083,color:Map3DPalette.tunnelLamp,sides:12)
                    beam(Map3DPoint(x+end*0.151,2.29,side*0.51),
                         Map3DPoint(x+end*0.151,2.76,side*1.05),0.024,dark)
                    if end > 0 && side > 0 {
                        // Small pale car-number card seen under the left lamp
                        // in the dated DRC1025 photograph. No borrowed font.
                        box(x+end*0.158,2.84,side*0.86,0.012,0.40,0.095,
                            Map3DColor.rgb(0xE4E0D6))
                    }
                }
                civicTube(Map3DPoint(x+end*0.086,1.55,side*1.05),
                          Map3DPoint(x+end*0.115,1.55,side*1.05),
                          radius:0.18,color:yellow,sides:far ? 8:12)
                civicTube(Map3DPoint(x+end*0.118,1.55,side*1.05),
                          Map3DPoint(x+end*0.132,1.55,side*1.05),
                          radius:0.09,color:Map3DColor.rgb(0xBA3433),sides:far ? 8:12)
                // Orange V meets the side waist stripe at the outer edge.
                beam(Map3DPoint(x+end*0.09,2.17,side*1.29),Map3DPoint(x+end*0.09,1.28,side*0.50),0.18,orange)
            }
            drEndPanel(end,x,[(1.23,-0.42),(1.23,0.42),(3.11,0.42),
                              (3.22,0.32),(3.22,-0.32),(3.11,-0.42)],0.14,dark)
            drEndPanel(end,x,[(1.29,-0.34),(1.29,0.34),(3.05,0.34),
                              (3.15,0.27),(3.15,-0.27),(3.05,-0.34)],0.16,yellow)
            drEndPanel(end,x,[(2.23,-0.17),(2.23,0.17),(2.95,0.17),
                              (3.03,0.12),(3.03,-0.12),(2.95,-0.17)],0.18,glass)
            if !far {
                for side:Float in [-1,1] {
                    beam(Map3DPoint(x+end*0.18,1.47,side*0.41),
                         Map3DPoint(x+end*0.18,3.04,side*0.41),0.035,Map3D45DR1000.roof)
                }
            }
            box(x+end*0.09,0.96,0,0.20,2.35,0.21,dark)
            box(x+end*0.13,0.75,0,0.12,0.50,0.32,dark)
            // The pilot is tapered at its lower corners, with two yellow
            // diagonal chevrons and a visible central coupler and air hoses.
            drEndPanel(end,x,[(0.20,-0.76),(0.20,0.76),(0.34,1.14),
                              (0.87,1.14),(0.87,-1.14),(0.34,-1.14)],0.17,dark)
            for side:Float in [-1,1] {
                beam(Map3DPoint(x+end*0.18,0.25,side*0.18),
                     Map3DPoint(x+end*0.18,0.86,side*0.98),0.14,yellow)
                beam(Map3DPoint(x+end*0.18,0.22,side*0.72),
                     Map3DPoint(x+end*0.18,0.60,side*1.08),0.10,yellow)
                if !far {
                    beam(Map3DPoint(x+end*0.19,1.05,side*0.32),
                         Map3DPoint(x+end*0.22,0.53,side*0.57),0.055,Map3D45DR1000.roof)
                    beam(Map3DPoint(x+end*0.22,0.53,side*0.57),
                         Map3DPoint(x+end*0.17,0.35,side*0.47),0.055,Map3D45DR1000.roof)
                }
            }
            box(x+end*0.20,0.73,0,0.08,0.26,0.22,Map3DColor.rgb(0x595D5A))
        }
        // Inset doors and separate passenger windows; the accessible 1025 has no short toilet window.
        for side:Float in [-1,1] {
            let z=side*1.36
            for end:Float in [-1,1] {
                box(end*8.89,2.22,z,1.45,0.022,0.98,yellow)
                box(end*8.89,2.11,z+side*0.017,1.45,0.020,0.18,orange)
            }
            for x:Float in [-5.95,5.95] {
                if !far { box(x,1.12,z,0.87,0.035,2.12,Map3D45DR1000.roof) }
                box(x,2.21,z+side*0.025,0.58,0.02,0.80,glass)
                if !far { box(x,1.42,z+side*0.027,0.56,0.021,0.10,silver) }
            }
            if far {
                box(0,2.20,z,17.6,0.025,0.82,glass)
            } else {
                for x:Float in [-8.17,-7.0,-4.65,-2.95,-1.25,0.45,2.15,3.85,7.0,8.15] {
                    box(x,2.19,z,1.14,0.025,0.91,dark)
                    box(x,2.24,z+side*0.017,1.04,0.020,0.81,glass)
                }
            }
            if !far { for y:Float in [1.38,1.52,1.66,1.80,1.94] { box(0,y,z+side*0.022,18.8,0.025,0.018,Map3DColor.rgb(0x9FA29F)) } }
        }
        // Two two-axle bogies; separate engine/generator boxes and two roof coolers.
        box(0,0.98,0,19.1,2.35,0.25,dark)
        for centre:Float in [-6.55,6.55] {
            box(centre,0.60,0,3.15,1.62,0.29,dark)
            for dx:Float in [-0.94,0.94] { for side:Float in [-1,1] {
                civicTube(Map3DPoint(centre+dx,0.43,side*0.71),Map3DPoint(centre+dx,0.43,side*0.89),radius:0.41,color:dark,sides:far ? 8:12)
            } }
            for side:Float in [-1,1] { box(centre,0.66,side*0.93,2.83,0.10,0.16,Map3D45DR1000.roof) }
        }
        box(-1.9,0.68,0,2.3,1.48,0.52,Map3D45DR1000.roof)
        box(1.6,0.72,0,2.1,1.25,0.43,dark)
        for x:Float in [-4.6,3.3] {
            box(x,3.62,0,3.10,1.62,0.27,Map3D45DR1000.roof)
            if !far { for i in -3...3 { box(x+Float(i)*0.34,3.89,0,0.035,1.41,0.02,dark) } }
        }
    }
}
