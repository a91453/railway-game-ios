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
    public static let glass = Map3DPalette.glazing
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
    mutating func dr1000(far: Bool) {
        let silver=Map3D45DR1000.silver, orange=Map3D45DR1000.orange
        let yellow=Map3D45DR1000.yellow, dark=Map3D45DR1000.dark
        let glass=Map3D45DR1000.glass
        // Long, narrow body. The stripe is part of the shell and continues on the ends.
        drShell(-9.62,9.62,1.12,2.10,silver)
        drShell(-9.62,9.62,2.10,2.20,orange)
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
            let outline:[(Float,Float)]=[(1.25,-1.28),(1.25,1.28),(3.11,1.28),(3.32,1.17),(3.43,0.93),(3.46,0),(3.43,-0.93),(3.32,-1.17),(3.11,-1.28)]
            let back=outline.map { Map3DPoint(x-end*0.03,$0.0,$0.1) }
            let front=outline.map { Map3DPoint(x+end*0.03,$0.0,$0.1) }
            drPrism(back,front,yellow)
            for side:Float in [-1,1] {
                box(x+end*0.052,2.19,side*0.82,0.025,0.79,1.05,dark)
                box(x+end*0.069,2.22,side*0.82,0.016,0.68,0.96,glass)
                if far {
                    box(x+end*0.07,3.06,side*0.85,0.025,0.16,0.16,Map3DPalette.tunnelLamp)
                } else {
                    civicTube(Map3DPoint(x+end*0.07,3.13,side*0.85),
                              Map3DPoint(x+end*0.11,3.13,side*0.85),
                              radius:0.09,color:Map3DPalette.tunnelLamp,sides:12)
                }
                box(x+end*0.08,1.52,side*1.05,0.03,0.17,0.17,Map3DColor.rgb(0xBA3433))
                // Orange V meets the side waist stripe at the outer edge.
                beam(Map3DPoint(x+end*0.09,2.17,side*1.29),Map3DPoint(x+end*0.09,1.28,side*0.50),0.18,orange)
            }
            beam(Map3DPoint(x+end*0.08,3.30,-1.13),
                 Map3DPoint(x+end*0.08,3.30,1.13),0.16,orange)
            box(x+end*0.10,1.25,0,0.08,0.76,1.86,dark)
            box(x+end*0.15,1.31,0,0.04,0.60,1.71,yellow)
            box(x+end*0.18,2.14,0,0.018,0.29,0.85,glass)
            box(x+end*0.09,0.96,0,0.20,2.35,0.21,dark)
            box(x+end*0.13,0.75,0,0.12,0.50,0.32,dark)
            // Wide striped pilot masks the underframe when seen head on.
            box(x+end*0.12,0.21,0,0.10,2.31,0.66,dark)
            for side:Float in [-1,1] {
                beam(Map3DPoint(x+end*0.18,0.25,side*0.18),
                     Map3DPoint(x+end*0.18,0.86,side*0.98),0.14,yellow)
            }
            if !far { for side:Float in [-1,1] {
                beam(Map3DPoint(x+end*0.17,2.44,side*0.42),Map3DPoint(x+end*0.17,1.49,side*0.42),0.035,Map3D45DR1000.roof)
            } }
        }
        // Inset doors and separate passenger windows; the accessible 1025 has no short toilet window.
        for side:Float in [-1,1] {
            let z=side*1.36
            for end:Float in [-1,1] {
                box(end*8.89,2.22,z,1.45,0.022,0.98,yellow)
                box(end*8.89,2.10,z+side*0.017,1.45,0.020,0.10,orange)
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
