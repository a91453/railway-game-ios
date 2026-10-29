import Foundation

/// First-batch TRA R21, EMD G12, in the photographed orange era.
/// Geometry is in metres; builder Y is up and Model.flat converts to native Z up.
/// Dimensions of fittings and bogie centres are visual estimates, not drawings.
public enum Map3DG12 {
    public static let length: Float = 14.226
    public static let width: Float = 2.787
    public static let height: Float = 3.665
    public static let orange: UInt32 = Map3DColor.rgb(0xF18B42)
    public static let white: UInt32 = Map3DColor.rgb(0xF7F3EA)
    public static let charcoal: UInt32 = Map3DColor.rgb(0x30343A)
    public static let steel: UInt32 = Map3DColor.rgb(0x64686B)
    public static let glass: UInt32 = Map3DPalette.glazing
    public static let lamp: UInt32 = Map3DPalette.tunnelLamp
    public static let hazard: UInt32 = Map3DColor.rgb(0xF4CC36)

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
                                        _ color: UInt32,_ half: Float = 1.08) {
        let a=[Map3DPoint(x0,1.42,-half),Map3DPoint(x0,1.42,half),
               Map3DPoint(x0,top0,half),Map3DPoint(x0,top0,-half)]
        let b=[Map3DPoint(x1,1.42,-half),Map3DPoint(x1,1.42,half),
               Map3DPoint(x1,top1,half),Map3DPoint(x1,top1,-half)]
        g12Prism(a,b,color)
    }

    /// Rounded number board with an original, tiny geometry-only R21 reading.
    /// The registration is a vehicle number, not an operator logo or photo font.
    private mutating func g12NumberBoard(_ end: Float,_ x: Float,_ y: Float,_ z: Float,_ far: Bool) {
        let outline:[(Float,Float)]=[(-0.175,-0.10),(0.175,-0.10),(0.235,-0.04),
                                     (0.235,0.04),(0.175,0.10),(-0.175,0.10),
                                     (-0.235,0.04),(-0.235,-0.04)]
        let rear=outline.map { Map3DPoint(x,$0.1+y,$0.0+z) }
        let face=outline.map { Map3DPoint(x+end*0.045,$0.1+y,$0.0+z) }
        g12Prism(rear,face,Map3DG12.charcoal)
        guard !far else { return }
        let paintX=x+end*0.069, ink=Map3DG12.white
        let reading:Float = end > 0 ? -1:1
        func stroke(_ col:Float,_ a:(Float,Float),_ b:(Float,Float)) {
            beam(Map3DPoint(paintX,y+a.1,z+reading*(col+a.0)),
                 Map3DPoint(paintX,y+b.1,z+reading*(col+b.0)),0.016,ink)
        }
        let top:Float=0.061, mid:Float=0, bottom:Float = -0.061
        // R
        let r:Float = -0.135
        stroke(r,(-0.034,bottom),(-0.034,top));stroke(r,(-0.034,top),(0.033,top))
        stroke(r,(0.033,top),(0.033,mid));stroke(r,(-0.034,mid),(0.033,mid))
        stroke(r,(-0.006,mid),(0.036,bottom))
        // 2
        let two:Float = 0
        stroke(two,(-0.036,top),(0.036,top));stroke(two,(0.036,top),(0.036,mid))
        stroke(two,(-0.036,mid),(0.036,mid));stroke(two,(-0.036,mid),(-0.036,bottom))
        stroke(two,(-0.036,bottom),(0.036,bottom))
        // 1
        let one:Float = 0.135
        stroke(one,(0,bottom),(0,top));stroke(one,(-0.026,bottom),(0.026,bottom))
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
        let station:[(Float,Float)]=[(-3.18,2.27),(2.18,2.27),(2.60,2.24),
                                      (3.02,2.12),(3.40,1.91),(3.82,1.50),(hoodEnd,1.50)]
        for i in 0..<(station.count-1) {
            let a=station[i], b=station[i+1]
            g12LowerPanel(a.0,b.0,a.1,b.1,orange)
            g12TaperedBand(a.0,b.0,a.1,b.1,0.09,1.08,white)
            // Upper orange panel uses the complementary varying lower edge.
            let upperA=[Map3DPoint(a.0,a.1+0.09,-1.08),Map3DPoint(a.0,a.1+0.09,1.08),
                        Map3DPoint(a.0,3.10,1.08),Map3DPoint(a.0,3.27,0.98),
                        Map3DPoint(a.0,3.27,-0.98),Map3DPoint(a.0,3.10,-1.08)]
            let upperB=[Map3DPoint(b.0,b.1+0.09,-1.08),Map3DPoint(b.0,b.1+0.09,1.08),
                        Map3DPoint(b.0,3.10,1.08),Map3DPoint(b.0,3.27,0.98),
                        Map3DPoint(b.0,3.27,-0.98),Map3DPoint(b.0,3.10,-1.08)]
            g12Prism(upperA,upperB,orange)
        }
        let roofA=[Map3DPoint(-3.18,3.27,-0.98),Map3DPoint(-3.18,3.27,0.98),
                   Map3DPoint(-3.18,3.45,0.88),Map3DPoint(-3.18,3.49,0),Map3DPoint(-3.18,3.45,-0.88)]
        let roofB=roofA.map { Map3DPoint(hoodEnd,$0.y,$0.z) }
        g12Prism(roofA,roofB,dark)
        // Cab is taller and wider than either hood; its side stripe joins at the same height.
        g12Section(1.42,2.27,-5.12,-3.18,1.19,orange)
        g12Section(2.27,2.36,-5.12,-3.18,1.19,white)
        g12Section(2.36,3.12,-5.12,-3.18,1.19,orange)
        // The end of the cab roof rakes toward the short hood, while its
        // shoulder rolls in above the windows. This is a real shell profile.
        let cabShoulderA=[Map3DPoint(-5.12,3.12,-1.19),Map3DPoint(-5.12,3.12,1.19),
                          Map3DPoint(-5.31,3.45,1.04),Map3DPoint(-5.36,3.53,0.86),
                          Map3DPoint(-5.36,3.53,-0.86),Map3DPoint(-5.31,3.45,-1.04)]
        let cabShoulderB=[Map3DPoint(-3.18,3.12,-1.19),Map3DPoint(-3.18,3.12,1.19),
                          Map3DPoint(-3.11,3.45,1.04),Map3DPoint(-3.10,3.53,0.86),
                          Map3DPoint(-3.10,3.53,-0.86),Map3DPoint(-3.11,3.45,-1.04)]
        g12Prism(cabShoulderA,cabShoulderB,orange)
        let cabRoofA=[Map3DPoint(-5.36,3.53,-0.86),Map3DPoint(-5.36,3.53,0.86),
                      Map3DPoint(-5.36,3.61,0.74),Map3DPoint(-5.36,3.63,0),Map3DPoint(-5.36,3.61,-0.74)]
        let cabRoofB=cabRoofA.map { Map3DPoint(-3.10,$0.y,$0.z) }
        g12Prism(cabRoofA,cabRoofB,dark)
        // Short hood beyond the cab. It has its own end face and lamp arrangement.
        g12LowerPanel(-6.64,cabRear,1.50,2.27,orange,1.01)
        g12TaperedBand(-6.64,cabRear,1.50,2.27,0.09,1.01,white)
        let shortA=[Map3DPoint(-6.64,1.59,-1.01),Map3DPoint(-6.64,1.59,1.01),
                    Map3DPoint(-6.64,3.23,1.01),Map3DPoint(-6.64,3.23,-1.01)]
        let shortB=[Map3DPoint(cabRear,2.36,-1.01),Map3DPoint(cabRear,2.36,1.01),
                    Map3DPoint(cabRear,3.23,1.01),Map3DPoint(cabRear,3.23,-1.01)]
        g12Prism(shortA,shortB,orange)
        g12Section(3.23,3.34,-6.64,cabRear,0.98,dark)
        // Integral underframe, two distinct triple-axle bogies and centre fuel tank.
        box(0,0.88,0,13.70,2.48,0.42,dark)
        box(0.12,0.62,0,2.72,1.42,0.56,dark)
        for centre:Float in [-4.45,4.43] {
            box(centre,0.60,0,3.58,1.63,0.30,metal)
            // Fill the inter-axle shadow behind the wheel discs, as on the
            // cast side frame. It keeps six wheels from reading as loose beads.
            box(centre,0.35,0,3.82,1.46,0.28,dark)
            for dx:Float in [-1.20,0,1.20] {
                for side:Float in [-1,1] {
                    civicTube(Map3DPoint(centre+dx,0.43,side*0.65),
                              Map3DPoint(centre+dx,0.43,side*0.87),
                              radius:0.43,color:dark,sides:far ? 8:12)
                    if !far { civicTube(Map3DPoint(centre+dx,0.43,side*0.875),
                                        Map3DPoint(centre+dx,0.43,side*0.91),
                                        radius:0.12,color:Map3DColor.shaded(dark,0.76),sides:8) }
                }
            }
            for side:Float in [-1,1] {
                // A side frame masks the upper tyre arcs; axleboxes and the
                // diagonal cradle restore the weight seen in the R21 photos.
                box(centre,0.69,side*0.98,3.52,0.11,0.17,dark)
                for dx:Float in [-1.20,0,1.20] {
                    box(centre+dx,0.53,side*1.02,0.42,0.13,0.30,metal)
                }
                if !far {
                    for dx:Float in [-0.60,0.60] {
                        beam(Map3DPoint(centre+dx-0.42,0.39,side*0.99),
                             Map3DPoint(centre+dx+0.42,0.74,side*0.99),0.095,dark)
                    }
                }
            }
        }
        // Cab glass is offset from the actual local side and end faces.
        for side:Float in [-1,1] {
            box(-4.22,2.67,side*1.218,0.96,0.045,0.70,dark)
            box(-4.22,2.67,side*1.247,0.86,0.020,0.60,glass)
            box(-3.42,2.72,side*1.218,0.43,0.045,0.62,dark)
            box(-3.42,2.72,side*1.247,0.33,0.020,0.52,glass)
            box(-4.83,2.17,side*1.211,0.07,0.04,1.03,metal)
            box(-4.79,1.84,side*1.231,0.35,0.05,0.04,metal)
            if !far {
                beam(Map3DPoint(-3.16,1.49,side*1.22),Map3DPoint(-3.16,2.20,side*1.22),0.038,metal)
                box(-3.16,1.46,side*1.23,0.14,0.09,0.045,metal)
            }
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
                box(5.28,2.78,side*1.095,1.25,0.025,0.63,Map3DColor.shaded(dark,0.80))
                for y:Float in [2.51,2.60,2.69,2.78,2.87,2.96,3.05] {
                    box(5.28,y,side*1.12,1.21,0.025,0.023,metal)
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
            civicTube(Map3DPoint(6.732,y,0),Map3DPoint(6.755,y,0),radius:0.143,color:metal,sides:far ? 8:12)
            civicTube(Map3DPoint(6.74,y,0),Map3DPoint(6.80,y,0),radius:0.103,color:Map3DG12.lamp,sides:far ? 8:12)
        }
        for side:Float in [-1,1] {
            g12NumberBoard(1,6.72,3.09,side*0.64,far)
            civicTube(Map3DPoint(6.74,3.31,side*0.81),Map3DPoint(6.80,3.31,side*0.81),radius:0.087,color:Map3DColor.rgb(0xA24E44),sides:8)
        }
        if !far {
            for y:Float in [1.62,1.97,2.27] {
                beam(Map3DPoint(6.755,y,-0.32),Map3DPoint(6.755,y,0.32),0.028,white)
                for side:Float in [-1,1] {
                    beam(Map3DPoint(6.74,y-0.07,side*0.32),Map3DPoint(6.755,y,side*0.32),0.023,white)
                }
            }
        }
        // Cab front glass is partly shielded by the short hood.
        for side:Float in [-1,1] {
            box(-5.142,2.77,side*0.55,0.025,0.80,0.59,dark)
            box(-5.163,2.77,side*0.55,0.025,0.71,0.50,glass)
        }
        // R21 short-end photographs also show vertically stacked centre lamps,
        // number boards, corner markers, and three grab bars. Its hood height
        // and white-band transition remain distinct from the long end.
        for y:Float in [2.90,3.12] {
            civicTube(Map3DPoint(-6.655,y,0),Map3DPoint(-6.68,y,0),radius:0.143,color:metal,sides:far ? 8:12)
            civicTube(Map3DPoint(-6.67,y,0),Map3DPoint(-6.73,y,0),radius:0.103,color:Map3DG12.lamp,sides:far ? 8:12)
        }
        for side:Float in [-1,1] {
            g12NumberBoard(-1,-6.64,3.03,side*0.63,far)
            civicTube(Map3DPoint(-6.67,3.26,side*0.80),Map3DPoint(-6.73,3.26,side*0.80),radius:0.087,color:Map3DColor.rgb(0xA24E44),sides:8)
        }
        if !far {
            for y:Float in [1.64,1.99,2.29] {
                beam(Map3DPoint(-6.689,y,-0.32),Map3DPoint(-6.689,y,0.32),0.028,white)
                for side:Float in [-1,1] {
                    beam(Map3DPoint(-6.67,y-0.07,side*0.32),Map3DPoint(-6.689,y,side*0.32),0.023,white)
                }
            }
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
            // Both photographed ends carry a broad dark plow below the pilot.
            let plowBack=[Map3DPoint(end*6.92,0.19,-0.87),Map3DPoint(end*6.92,0.19,0.87),
                          Map3DPoint(end*6.92,0.53,1.04),Map3DPoint(end*6.92,0.53,-1.04)]
            let plowFront=plowBack.map { Map3DPoint(end*7.04,$0.y,$0.z) }
            g12Prism(plowBack,plowFront,dark)
        }
    }
}
