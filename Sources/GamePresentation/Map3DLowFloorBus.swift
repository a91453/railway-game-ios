import Foundation

/// Full-size two-door city bus, recomposed from the owner's four views.
/// Native axes: +x front, +y left, +z up, metres; fixed matte livery.
public enum Map3DLowFloorBus {
    public static let modelName = "life-lowFloorBus"
    public static let length: Float = 12.08
    public static let bodyWidth: Float = 2.46
    public static let height: Float = 3.40
    public static let bodyColor = Map3DPalette.shopAwnings[3]
    public static let accentColor = Map3DPalette.shopAwnings[2]
    public static func model() -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.lowFloorBus()
        return .flat(named:modelName,from:b.mesh)
    }
}

extension StationKitBuilder {
    mutating func lowFloorBus() {
        let white=Map3DLowFloorBus.bodyColor,blue=Map3DLowFloorBus.accentColor
        let trim=Map3DStreetModel.trim,glass=Self.glass,steel=Self.steel
        // The side profile includes real wheel cut-outs, closed all around
        // with the same ear-clipped shell used by the smaller shuttle.
        var contour=[Map3DPoint(-5.96,0.35,0)]
        for axle: Float in [-3.55,3.45] {
            contour.append(Map3DPoint(axle-0.57,0.35,0))
            for i in 0...12 { let a=Float.pi-Float(i)*Float.pi/12
                contour.append(Map3DPoint(axle+cosf(a)*0.57,0.48+sinf(a)*0.57,0))
            }
            contour.append(Map3DPoint(axle+0.57,0.35,0))
        }
        contour += [Map3DPoint(5.88,0.35,0),Map3DPoint(6.00,0.54,0),Map3DPoint(6.00,1.10,0),Map3DPoint(5.78,2.86,0),Map3DPoint(5.58,3.00,0),Map3DPoint(-5.64,3.00,0),Map3DPoint(-5.96,2.80,0)]
        shuttleShell(contour,halfWidth:1.23,color:white)
        // A shallow closed roof shoulder, with the roof cap touching its
        // lower perimeter rather than floating above the window band.
        let low=[Map3DPoint(-5.64,3,-1.23),Map3DPoint(5.58,3,-1.23),Map3DPoint(5.58,3,1.23),Map3DPoint(-5.64,3,1.23)]
        let high=[Map3DPoint(-5.48,3.14,-1.08),Map3DPoint(5.42,3.14,-1.08),Map3DPoint(5.42,3.14,1.08),Map3DPoint(-5.48,3.14,1.08)]
        let centre=Map3DPoint(0,3.07,0)
        for i in 0..<4 { let j=(i+1)%4;face([low[i],low[j],high[j],high[i]],inside:centre,color:white) }
        face(high,inside:centre,color:white);face(low,inside:centre,color:white)
        box(0,0.35,0,10.9,1.72,0.14,trim)
        for axle: Float in [-3.55,3.45] { for side: Float in [-1,1] {
            civicTube(Map3DPoint(axle,0.48,side*1.02),Map3DPoint(axle,0.48,side*1.25),radius:0.48,color:Map3DStreetModel.tyre,sides:20)
            civicTube(Map3DPoint(axle,0.48,side*1.25),Map3DPoint(axle,0.48,side*1.265),radius:0.29,color:steel,sides:16)
            civicTube(Map3DPoint(axle,0.48,side*1.265),Map3DPoint(axle,0.48,side*1.275),radius:0.13,color:Map3DPalette.roof,sides:12)
            for i in 0..<12 { let a=Float.pi-Float(i)*Float.pi/12,b=Float.pi-Float(i+1)*Float.pi/12,z=side*1.237
                shuttlePanel([Map3DPoint(axle+cosf(a)*0.57,0.48+sinf(a)*0.57,z),Map3DPoint(axle+cosf(b)*0.57,0.48+sinf(b)*0.57,z),Map3DPoint(axle+cosf(b)*0.62,0.48+sinf(b)*0.62,z),Map3DPoint(axle+cosf(a)*0.62,0.48+sinf(a)*0.62,z)],normal:Map3DPoint(0,0,side),color:blue)
            }
        } }
        for side: Float in [-1,1] {
            // Blue waist stripe is above the cut-outs. The low skirt is
            // split around the wheels so the tyre silhouette remains open.
            box(-0.10,1.10,side*1.235,11.44,0.025,0.19,blue)
            for (x,w): (Float,Float) in [(-5.04,1.60),(-0.05,5.60),(4.98,1.46)] { box(x,0.36,side*1.235,w,0.025,0.12,blue) }
            box(-0.08,1.40,side*1.235,11.44,0.025,1.40,trim)
            let panes: [(Float,Float)] = side<0
                ? [(-4.64,1.80),(-2.73,1.80),(-0.80,1.80),(1.13,1.80),(3.06,1.80),(4.83,1.43)]
                : [(-4.77,1.56),(-3.10,1.56),(-1.59,1.30),(1.65,1.30),(3.03,1.30)]
            for (x,w) in panes { shuttleSideWindow(x,1.52,side*1.252,width:w,height:1.13) }
            // A rear cooling louvre, different in layout from the reference:
            // seven horizontal slots, with a solid panel behind every slot.
            box(-4.96,1.45,side*1.259,1.25,0.025,1.28,steel)
            for y: Float in [1.57,1.73,1.89,2.05,2.21,2.37,2.53] { box(-4.96,y,side*1.278,1.05,0.02,0.065,trim) }
            // Supported mirror arm begins on the true raked front corner.
            beam(Map3DPoint(5.72,2.43,side*1.23),Map3DPoint(5.66,2.46,side*1.46),0.045,steel)
            box(5.66,2.05,side*1.46,0.19,0.13,0.43,trim)
            for x: Float in [-4.55,-1.05,2.30,5.65] {
                let first=mesh.vertices.count;box(x,0.78,side*1.255,0.16,0.025,0.07,Map3DPalette.platformEdge);mesh.makeGlowing(from:first)
            }
        }
        // Right-side front and middle double-leaf doors, opaque backing,
        // inset tall glass, sill touching the floor. No left-side doors.
        for (x,w): (Float,Float) in [(4.86,1.12),(0.05,1.50)] {
            box(x,0.35,1.263,w+0.12,0.06,2.44,trim)
            for sign: Float in [-1,1] {
                let leaf=x+sign*w/4
                box(leaf,0.42,1.30,w/2-0.035,0.024,2.29,blue)
                shuttleSideWindow(leaf,0.67,1.316,width:w/2-0.13,height:1.96)
            }
            box(x,0.35,1.324,0.04,0.025,2.43,steel)
            box(x,0.28,1.26,w+0.18,0.18,0.08,trim)
        }
        // Plane of front glass follows the actual rake of the body shell.
        func frontX(_ y: Float) -> Float { 6-(y-1.10)*0.22/1.76 }
        let n=Map3DPoint(1.76,0.22,0).normalized!
        func frontQuad(_ y0: Float,_ y1: Float,_ width: Float,_ offset: Float) -> [Map3DPoint] {
            [Map3DPoint(frontX(y0),y0,-width/2)+n*offset,Map3DPoint(frontX(y0),y0,width/2)+n*offset,Map3DPoint(frontX(y1),y1,width/2)+n*offset,Map3DPoint(frontX(y1),y1,-width/2)+n*offset]
        }
        shuttlePanel(frontQuad(1.27,2.82,2.30,0.012),normal:n,color:trim)
        shuttlePanel(frontQuad(1.39,2.53,2.10,0.017),normal:n,color:glass)
        shuttlePanel(frontQuad(2.62,2.76,1.38,0.018),normal:n,color:blue)
        // Two modest wipers and a blue apron; angular lamps replace the
        // reference's white wedges. All pieces share the supporting plane.
        for side: Float in [-1,1] {
            beam(Map3DPoint(frontX(1.42),1.42,side*0.48)+n*0.025,Map3DPoint(frontX(1.70),1.70,side*0.72)+n*0.025,0.022,steel)
        }
        box(6.015,0.40,0,0.05,2.25,0.13,trim)
        box(6.008,0.63,0,0.035,1.44,0.34,blue)
        for side: Float in [-1,1] {
            box(6.01,0.66,side*0.94,0.04,0.38,0.40,trim)
            let first=mesh.vertices.count
            box(6.035,0.89,side*0.94,0.018,0.28,0.075,Map3DStreetModel.headlamp)
            box(6.035,0.73,side*1.055,0.018,0.05,0.14,Map3DStreetModel.headlamp);mesh.makeGlowing(from:first)
        }
        // Rear service hatch, upper window and separated vertical lamps;
        // the bottom vent and bumper make the rear read at map scale.
        box(-5.974,1.86,0,0.026,1.78,0.82,trim)
        box(-5.993,1.94,0,0.018,1.58,0.64,glass)
        box(-5.978,0.66,0,0.026,1.74,0.89,blue)
        for y: Float in [0.78,0.91,1.04] { box(-5.997,y,0,0.02,1.35,0.055,trim) }
        box(-5.99,0.36,0,0.10,2.29,0.16,trim)
        for side: Float in [-1,1] {
            box(-5.978,0.81,side*1.04,0.026,0.20,0.99,trim)
            for y: Float in [0.91,1.19,1.47] {
                let first=mesh.vertices.count;box(-6.0,y,side*1.04,0.026,0.12,0.19,Map3DStreetModel.tailLamp);mesh.makeGlowing(from:first)
            }
        }
        // Roof HVAC, sealed shoulders and feet in contact with the roof.
        for x: Float in [-3.52,-1.28] { box(x,3.14,0,0.18,1.42,0.06,steel) }
        let unit=[Map3DPoint(-3.85,3.20,0),Map3DPoint(-0.95,3.20,0),Map3DPoint(-1.15,3.40,0),Map3DPoint(-3.60,3.40,0)]
        shuttleShell(unit,halfWidth:0.83,color:white)
        for side: Float in [-1,1] { for x: Float in [-3.39,-3.11,-2.83,-2.55,-2.27,-1.99,-1.71,-1.43] { box(x,3.24,side*0.836,0.16,0.02,0.08,steel) } }
        box(1.6,3.14,0,0.78,0.80,0.035,steel)
        box(1.6,3.175,0,0.64,0.66,0.035,white)
    }
}
