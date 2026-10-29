import Foundation

/// First-batch TRA R21, EMD G12, in the photographed orange era.
/// Geometry is in metres; builder Y is up and Model.flat converts to native Z up.
/// Dimensions of fittings and bogie centres are visual estimates, not drawings.
public enum Map3DG12 {
    public static let length: Float = 14.226
    public static let width: Float = 2.787
    public static let height: Float = 3.665
    public static let orange: UInt32 = Map3DColor.rgb(0xD97732)
    public static let white: UInt32 = Map3DColor.rgb(0xE9E5D9)
    public static let charcoal: UInt32 = Map3DColor.rgb(0x30343A)
    public static let steel: UInt32 = Map3DColor.rgb(0x64686B)
    public static let glass: UInt32 = Map3DPalette.glazing
    public static let lamp: UInt32 = Map3DPalette.tunnelLamp
    public static let hazard: UInt32 = Map3DColor.rgb(0xE9B72F)

    public static func model(far: Bool = false) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.g12(far: far)
        return .flat(named: far ? "g12-r21-far" : "g12-r21", from: builder.mesh)
    }
}

extension StationKitBuilder {
    /// A closed prism from two end profiles. Its bands are the shell's own faces.
    private mutating func g12Prism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let inside = (a+b).reduce(Map3DPoint.zero,+) * (1/Float(a.count+b.count))
        face(a,inside:inside,color:color)
        face(b,inside:inside,color:color)
        for i in a.indices {
            let j = (i+1) % a.count
            face([a[i],a[j],b[j],b[i]],inside:inside,color:color)
        }
    }

    private mutating func g12Section(_ lo: Float, _ hi: Float, _ x0: Float, _ x1: Float, _ half: Float, _ color: UInt32) {
        func profile(_ x: Float) -> [Map3DPoint] {
            [Map3DPoint(x,lo,-half),Map3DPoint(x,lo,half),
             Map3DPoint(x,hi,half),Map3DPoint(x,hi,-half)]
        }
        g12Prism(profile(x0),profile(x1),color)
    }

    private mutating func g12TaperedBand(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float,
                                         _ h: Float, _ half: Float, _ color: UInt32) {
        let a=[Map3DPoint(x0,y0,-half),Map3DPoint(x0,y0,half),
               Map3DPoint(x0,y0+h,half),Map3DPoint(x0,y0+h,-half)]
        let b=[Map3DPoint(x1,y1,-half),Map3DPoint(x1,y1,half),
               Map3DPoint(x1,y1+h,half),Map3DPoint(x1,y1+h,-half)]
        g12Prism(a,b,color)
    }

    private mutating func g12LowerPanel(_ x0: Float,_ x1: Float,_ top0: Float,_ top1: Float,
                                        _ color: UInt32) {
        let a=[Map3DPoint(x0,1.42,-1.08),Map3DPoint(x0,1.42,1.08),
               Map3DPoint(x0,top0,1.08),Map3DPoint(x0,top0,-1.08)]
        let b=[Map3DPoint(x1,1.42,-1.08),Map3DPoint(x1,1.42,1.08),
               Map3DPoint(x1,top1,1.08),Map3DPoint(x1,top1,-1.08)]
        g12Prism(a,b,color)
    }

    mutating func g12(far: Bool) {
        let orange=Map3DG12.orange, white=Map3DG12.white
        let dark=Map3DG12.charcoal, metal=Map3DG12.steel
        let glass=Map3DG12.glass
        // Long hood is +X. Cab and short hood are -X; they are distinct.
        let hoodEnd:Float=6.72, cabRear:Float = -5.06
        box(0,1.15,0,13.46,2.68,0.30,dark)
        // Long hood: orange lower panel, integrated white waist, orange upper panel,
        // and a rounded dark roof. No floating coloured decal spans a seam.
        let station:[(Float,Float)]=[(-3.18,2.27),(2.80,2.27),(3.24,2.15),(3.75,1.50),(hoodEnd,1.50)]
        for i in 0..<(station.count-1) {
            let a=station[i], b=station[i+1]
            g12LowerPanel(a.0,b.0,a.1,b.1,orange)
            g12TaperedBand(a.0,b.0,a.1,b.1,0.09,1.08,white)
            // Upper orange panel uses the complementary varying lower edge.
            let upperA=[Map3DPoint(a.0,a.1+0.09,-1.08),Map3DPoint(a.0,a.1+0.09,1.08),
                        Map3DPoint(a.0,3.27,1.08),Map3DPoint(a.0,3.27,-1.08)]
            let upperB=[Map3DPoint(b.0,b.1+0.09,-1.08),Map3DPoint(b.0,b.1+0.09,1.08),
                        Map3DPoint(b.0,3.27,1.08),Map3DPoint(b.0,3.27,-1.08)]
            g12Prism(upperA,upperB,orange)
        }
        let roofA=[Map3DPoint(-3.18,3.27,-1.08),Map3DPoint(-3.18,3.27,1.08),
                   Map3DPoint(-3.18,3.45,0.88),Map3DPoint(-3.18,3.49,0),Map3DPoint(-3.18,3.45,-0.88)]
        let roofB=roofA.map { Map3DPoint(hoodEnd,$0.y,$0.z) }
        g12Prism(roofA,roofB,dark)
        // Cab is taller and wider than either hood; its side stripe joins at the same height.
        g12Section(1.42,2.27,-5.12,-3.18,1.19,orange)
        g12Section(2.27,2.36,-5.12,-3.18,1.19,white)
        g12Section(2.36,3.52,-5.12,-3.18,1.19,orange)
        g12Section(3.52,3.61,-5.12,-3.18,1.17,dark)
        // Short hood beyond the cab. It has its own end face and lamp arrangement.
        g12Section(1.42,2.27,-6.64,cabRear,1.01,orange)
        g12Section(2.27,2.36,-6.64,cabRear,1.01,white)
        g12Section(2.36,2.99,-6.64,cabRear,1.01,orange)
        g12Section(2.99,3.07,-6.64,cabRear,1.01,dark)
        // Integral underframe, two distinct triple-axle bogies and centre fuel tank.
        box(0,0.88,0,13.70,2.48,0.42,dark)
        box(0.12,0.62,0,2.72,1.42,0.56,dark)
        for centre:Float in [-4.45,4.43] {
            box(centre,0.60,0,3.58,1.63,0.30,metal)
            for dx:Float in [-1.20,0,1.20] {
                for side:Float in [-1,1] {
                    civicTube(Map3DPoint(centre+dx,0.43,side*0.65),
                              Map3DPoint(centre+dx,0.43,side*0.87),
                              radius:0.43,color:dark,sides:far ? 8:12)
                    if !far { civicTube(Map3DPoint(centre+dx,0.43,side*0.875),
                                        Map3DPoint(centre+dx,0.43,side*0.91),
                                        radius:0.19,color:metal,sides:8) }
                }
            }
            if !far { for side:Float in [-1,1] {
                beam(Map3DPoint(centre-1.62,0.72,side*0.9),Map3DPoint(centre+1.62,0.72,side*0.9),0.12,metal)
            }}
        }
        // Cab glass is offset from the actual local side and end faces.
        for side:Float in [-1,1] {
            box(-4.18,2.67,side*1.211,0.97,0.025,0.68,glass)
            box(-3.39,2.72,side*1.211,0.39,0.025,0.58,glass)
            box(-4.83,2.17,side*1.211,0.07,0.04,1.03,metal)
            box(-4.79,1.84,side*1.231,0.35,0.05,0.04,metal)
            // Equipment doors and the asymmetric radiator field belong to the long hood.
            if !far {
                for x:Float in [-2.40,-1.44,-0.48,0.48,1.44,2.40,3.36,4.32] {
                    box(x,2.55,side*1.092,0.025,0.022,0.53,metal)
                    box(x,1.61,side*1.092,0.025,0.022,0.35,metal)
                }
                for x:Float in [-2.67,-2.47,-2.27,-2.07] {
                    box(x,2.62,side*1.109,0.07,0.018,0.59,dark)
                }
                for y:Float in [2.55,2.66,2.77,2.88,2.99] {
                    box(5.28,y,side*1.113,1.17,0.02,0.036,dark)
                }
            } else {
                box(5.28,2.76,side*1.11,1.22,0.02,0.52,dark)
            }
            // Continuous platform handrail, supported at both ends.
            for x:Float in [-6.28,6.35] {
                beam(Map3DPoint(x,1.12,side*1.31),Map3DPoint(x,2.05,side*1.31),0.043,metal)
            }
            beam(Map3DPoint(-6.28,2.05,side*1.31),Map3DPoint(6.35,2.05,side*1.31),0.041,metal)
            for x:Float in [-6.2,6.25] {
                box(x,0.65,side*1.16,0.44,0.42,0.095,metal)
                if !far { box(x,0.39,side*1.19,0.29,0.34,0.075,metal) }
            }
        }
        // Dark exhaust stack and roof intake sit on the long hood.
        box(1.82,3.49,0,0.42,0.52,0.14,dark)
        if !far { box(3.48,3.47,0,0.90,0.62,0.13,metal) }
        // Long-end central twin white lamps; upper red markers left and right.
        for y:Float in [2.96,3.18] {
            civicTube(Map3DPoint(6.74,y,0),Map3DPoint(6.80,y,0),radius:0.103,color:Map3DG12.lamp,sides:far ? 8:12)
        }
        for side:Float in [-1,1] {
            civicTube(Map3DPoint(6.74,3.31,side*0.81),Map3DPoint(6.80,3.31,side*0.81),radius:0.087,color:Map3DColor.rgb(0xA24E44),sides:8)
        }
        // Short-end cab windows, separate twin lamps and two markers.
        for side:Float in [-1,1] {
            box(-5.132,2.77,side*0.55,0.025,0.76,0.55,glass)
            civicTube(Map3DPoint(-6.67,2.79,side*0.60),Map3DPoint(-6.73,2.79,side*0.60),radius:0.095,color:Map3DG12.lamp,sides:far ? 8:12)
        }
        // Both ends have a pilot, supported draw gear and rail-level steps.
        for end:Float in [-1,1] {
            // The yellow/charcoal chevrons are closed pieces of the pilot plate,
            // flush with one another, rather than a coloured decal over a seam.
            // Clip diagonal bands into closed prisms; no square colour pixels.
            let columns=far ? 4:12
            for col in 0..<columns {
                let z0:Float = -1.23+2.46*Float(col)/Float(columns)
                let z1:Float = -1.23+2.46*Float(col+1)/Float(columns)
                let sign:Float = z0+z1 < 0 ? -1:1
                let rectangle:[(Float,Float)]=[(z0,0.645),(z1,0.645),(z1,1.195),(z0,1.195)]
                func clip(_ input:[(Float,Float)],_ boundary:Float,_ keepAbove:Bool)->[(Float,Float)] {
                    guard !input.isEmpty else { return [] }
                    func score(_ p:(Float,Float))->Float { p.1*5+sign*p.0*3-boundary }
                    var output:[(Float,Float)]=[]
                    for i in input.indices {
                        let a=input[i],b=input[(i+1)%input.count],fa=score(a),fb=score(b)
                        let insideA=keepAbove ? fa >= 0:fa <= 0
                        let insideB=keepAbove ? fb >= 0:fb <= 0
                        if insideA { output.append(a) }
                        if insideA != insideB {
                            let t=fa/(fa-fb)
                            output.append((a.0+(b.0-a.0)*t,a.1+(b.1-a.1)*t))
                        }
                    }
                    return output
                }
                for band in 0..<10 {
                    let p=clip(clip(rectangle,Float(band),true),Float(band+1),false)
                    guard p.count>=3 else { continue }
                    let a=p.map { Map3DPoint(end*6.705,$0.1,$0.0) }
                    let b=p.map { Map3DPoint(end*6.895,$0.1,$0.0) }
                    g12Prism(a,b,band.isMultiple(of:2) ? Map3DG12.hazard:dark)
                }
            }
            box(end*6.89,0.68,0,0.38,0.43,0.27,metal)
            box(end*6.96,0.64,0,0.30,0.54,0.22,dark)
            box(end*6.96,0.34,0,0.27,2.05,0.16,metal)
        }
    }
}
