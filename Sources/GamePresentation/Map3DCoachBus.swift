import Foundation

/// Three-axle high-deck coach, recomposed from four owner-supplied views.
/// Native axes: +x front, +y left, +z up, in metres; opaque matte paint.
public enum Map3DCoachBus {
    public static let modelName = "life-coachBus"
    public static let length: Float = 13.19
    public static let bodyWidth: Float = 2.50
    public static let height: Float = 3.76
    public static let bodyColor = Map3DPalette.shopAwnings[3]
    public static let accentColor = Map3DPalette.shopAwnings[1]
    public static func model() -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.coachBus()
        return .flat(named:modelName,from:b.mesh)
    }
}

extension StationKitBuilder {
    /// Thin, closed body-coloured luggage door with a narrow seam and a
    /// small flush grip. Direct face colours keep the paint identical to
    /// the surrounding shell; addBox's shaded sides made the old doors grey.
    mutating func coachLuggageDoor(_ x: Float,_ side: Float) {
        let paint=Map3DCoachBus.bodyColor,seam=Map3DColor.shaded(paint,0.87)
        let normal=Map3DPoint(0,0,side)
        func outline(_ cx: Float,_ y: Float,_ z: Float,_ width: Float,_ height: Float,_ r: Float) -> [Map3DPoint] {
            let a=cx-width/2,b=cx+width/2
            return [Map3DPoint(a+r,y,z),Map3DPoint(b-r,y,z),Map3DPoint(b,y+r,z),Map3DPoint(b,y+height-r,z),Map3DPoint(b-r,y+height,z),Map3DPoint(a+r,y+height,z),Map3DPoint(a,y+height-r,z),Map3DPoint(a,y+r,z)]
        }
        let back=outline(x,0.64,side*1.249,1.43,0.83,0.045)
        let front=outline(x,0.64,side*1.256,1.43,0.83,0.045)
        let centre=Map3DPoint(x,1.055,side*1.2525)
        face(back,inside:centre,color:seam);face(front,inside:centre,color:seam)
        for i in 0..<8 { let j=(i+1)%8;face([back[i],back[j],front[j],front[i]],inside:centre,color:seam) }
        // 12 mm reveal; separate paint/backing enough to avoid depth flicker.
        // Paint is 9 mm proud; the small grip stays within 12 mm.
        shuttlePanel(outline(x,0.652,side*1.259,1.406,0.806,0.035),normal:normal,color:paint)
        shuttlePanel(outline(x+0.40,1.298,side*1.2615,0.14,0.026,0.006),normal:normal,color:Map3DStreetModel.trim)
    }
    mutating func coachBus() {
        let white=Map3DCoachBus.bodyColor,red=Map3DCoachBus.accentColor
        let trim=Map3DStreetModel.trim,steel=Self.steel
        var contour=[Map3DPoint(-6.44,0.36,0)]
        for axle: Float in [-3.90,-2.60,3.80] {
            contour.append(Map3DPoint(axle-0.57,0.36,0))
            for i in 0...12 { let a=Float.pi-Float(i)*Float.pi/12
                contour.append(Map3DPoint(axle+cosf(a)*0.57,0.50+sinf(a)*0.57,0))
            }
            contour.append(Map3DPoint(axle+0.57,0.36,0))
        }
        contour += [Map3DPoint(6.34,0.36,0),Map3DPoint(6.54,0.62,0),Map3DPoint(6.54,1.25,0),Map3DPoint(6.36,2.20,0),Map3DPoint(6.02,3.22,0),Map3DPoint(5.72,3.35,0),Map3DPoint(-6.12,3.35,0),Map3DPoint(-6.42,3.20,0),Map3DPoint(-6.55,2.80,0),Map3DPoint(-6.55,0.60,0)]
        shuttleShell(contour,halfWidth:1.25,color:white)
        // Closed shallow roof shoulder. The side windows below it remain
        // on the flat, fully backed wall instead of following a false rake.
        let low=[Map3DPoint(-6.12,3.35,-1.25),Map3DPoint(5.72,3.35,-1.25),Map3DPoint(5.72,3.35,1.25),Map3DPoint(-6.12,3.35,1.25)]
        let high=[Map3DPoint(-5.92,3.52,-1.08),Map3DPoint(5.52,3.52,-1.08),Map3DPoint(5.52,3.52,1.08),Map3DPoint(-5.92,3.52,1.08)]
        let centre=Map3DPoint(0,3.43,0)
        for i in 0..<4 { let j=(i+1)%4;face([low[i],low[j],high[j],high[i]],inside:centre,color:white) }
        face(low,inside:centre,color:white);face(high,inside:centre,color:white)
        box(0,0.36,0,11.7,1.70,0.14,trim)
        for axle: Float in [-3.90,-2.60,3.80] { for side: Float in [-1,1] {
            civicTube(Map3DPoint(axle,0.50,side*1.04),Map3DPoint(axle,0.50,side*1.27),radius:0.50,color:Map3DStreetModel.tyre,sides:20)
            civicTube(Map3DPoint(axle,0.50,side*1.27),Map3DPoint(axle,0.50,side*1.282),radius:0.30,color:steel,sides:16)
            civicTube(Map3DPoint(axle,0.50,side*1.282),Map3DPoint(axle,0.50,side*1.29),radius:0.13,color:Map3DPalette.roof,sides:12)
            for i in 0..<12 { let a=Float.pi-Float(i)*Float.pi/12,b=Float.pi-Float(i+1)*Float.pi/12,z=side*1.257
                shuttlePanel([Map3DPoint(axle+cosf(a)*0.57,0.50+sinf(a)*0.57,z),Map3DPoint(axle+cosf(b)*0.57,0.50+sinf(b)*0.57,z),Map3DPoint(axle+cosf(b)*0.61,0.50+sinf(b)*0.61,z),Map3DPoint(axle+cosf(a)*0.61,0.50+sinf(a)*0.61,z)],normal:Map3DPoint(0,0,side),color:red)
            }
        } }
        for side: Float in [-1,1] {
            // Raised glazing band and a rising accent at the front create
            // a coach silhouette distinct from the low-floor city bus.
            box(-0.18,2.02,side*1.255,11.72,0.025,1.20,trim)
            let windows: [(Float,Float)]=side<0
                ? [(-5.14,1.48),(-3.53,1.48),(-1.92,1.48),(-0.31,1.48),(1.30,1.48),(2.91,1.48),(4.65,1.72)]
                : [(-5.14,1.48),(-3.53,1.48),(-1.92,1.48),(-0.31,1.48),(1.30,1.48),(2.91,1.48),(4.25,0.95)]
            for (x,w) in windows { shuttleSideWindow(x,2.10,side*1.272,width:w,height:1.03) }
            shuttlePanel([Map3DPoint(-6.03,1.65,side*1.272),Map3DPoint(4.65,1.65,side*1.272),Map3DPoint(5.95,1.93,side*1.272),Map3DPoint(5.95,2.00,side*1.272),Map3DPoint(-6.03,1.86,side*1.272)],normal:Map3DPoint(0,0,side),color:red)
            // Luggage hatches between the tandem rear and front axle.
            for x: Float in [-1.15,0.42,1.99] {
                coachLuggageDoor(x,side)
            }
            for (x,w): (Float,Float) in [(-5.35,1.58),(-0.08,3.82),(5.38,1.40)] { box(x,0.37,side*1.255,w,0.025,0.11,red) }
            box(-5.37,0.81,side*1.263,1.25,0.026,0.62,steel)
            for y: Float in [0.90,1.05,1.20] { box(-5.37,y,side*1.282,1.07,0.02,0.06,trim) }
            for x: Float in [-5.90,-1.76,1.25,5.88] {
                let first=mesh.vertices.count;box(x,0.60,side*1.27,0.14,0.025,0.06,Map3DPalette.platformEdge);mesh.makeGlowing(from:first)
            }
            // The mirror has two connected arms, not an unsupported shell.
            beam(Map3DPoint(5.86,2.85,side*1.25),Map3DPoint(5.94,2.92,side*1.51),0.05,steel)
            beam(Map3DPoint(5.94,2.92,side*1.51),Map3DPoint(6.10,2.42,side*1.51),0.05,steel)
            box(6.10,2.18,side*1.51,0.22,0.14,0.46,red)
        }
        // One tall right-front passenger door and contact-supported steps.
        box(5.22,0.41,1.279,0.98,0.06,2.75,trim)
        box(5.22,0.48,1.314,0.86,0.025,2.61,red)
        shuttleSideWindow(5.22,0.86,1.333,width:0.70,height:2.15)
        box(5.22,0.38,1.26,1.04,0.18,0.09,trim)
        for i in 0..<2 { box(5.22,0.48+Float(i)*0.13,1.309,0.79,0.09,0.06,steel) }
        // The bent panoramic screen is split at the body's actual break:
        // each pane follows its own physical supporting face.
        func frontX(_ y: Float) -> Float { y<=2.20 ? 6.54-(y-1.25)*0.18/0.95 : 6.36-(y-2.20)*0.34/1.02 }
        func frontQuad(_ y0: Float,_ y1: Float,_ width: Float,_ offset: Float,_ n: Map3DPoint) -> [Map3DPoint] {
            [Map3DPoint(frontX(y0),y0,-width/2)+n*offset,Map3DPoint(frontX(y0),y0,width/2)+n*offset,Map3DPoint(frontX(y1),y1,width/2)+n*offset,Map3DPoint(frontX(y1),y1,-width/2)+n*offset]
        }
        for (bottom,top,n): (Float,Float,Map3DPoint) in [(1.40,2.20,Map3DPoint(0.95,0.18,0).normalized!),(2.20,3.20,Map3DPoint(1.02,0.34,0).normalized!)] {
            shuttlePanel(frontQuad(bottom,top,2.30,0.012,n),normal:n,color:trim)
            shuttlePanel(frontQuad(bottom+0.035,top-0.015,2.13,0.018,n),normal:n,color:Self.glass)
        }
        let lowerNormal=Map3DPoint(0.95,0.18,0).normalized!
        for side: Float in [-1,1] { beam(Map3DPoint(frontX(1.47),1.47,side*0.46)+lowerNormal*0.03,Map3DPoint(frontX(1.78),1.78,side*0.76)+lowerNormal*0.03,0.022,steel) }
        box(6.553,0.48,0,0.045,2.26,0.16,trim)
        box(6.549,0.79,0,0.032,1.54,0.24,red)
        // Twin small lamps in swept housings, with no brand badge.
        for side: Float in [-1,1] {
            box(6.548,0.77,side*0.98,0.04,0.36,0.46,trim)
            shuttlePanel([Map3DPoint(6.571,0.78,side*0.84),Map3DPoint(6.571,0.84,side*1.14),Map3DPoint(6.571,1.20,side*1.12),Map3DPoint(6.571,1.14,side*0.84)],normal:Map3DPoint(1,0,0),color:trim)
            for y: Float in [0.89,1.08] {
                let first=mesh.vertices.count;civicTube(Map3DPoint(6.571,y,side*0.98),Map3DPoint(6.584,y,side*0.98),radius:0.065,color:Map3DStreetModel.headlamp,sides:10);mesh.makeGlowing(from:first)
            }
        }
        // Rear glazing and service cover are mounted on the flat rear.
        box(-6.563,2.02,0,0.026,1.96,0.73,trim)
        box(-6.581,2.10,0,0.016,1.78,0.57,Self.glass)
        box(-6.566,0.78,0,0.032,1.65,0.97,red)
        box(-6.587,0.94,0,0.018,1.38,0.08,trim)
        box(-6.56,0.42,0,0.08,2.25,0.18,trim)
        for side: Float in [-1,1] {
            box(-6.57,0.89,side*1.08,0.04,0.19,0.91,trim)
            for y: Float in [1.02,1.31,1.60] {
                let first=mesh.vertices.count;box(-6.596,y,side*1.08,0.016,0.12,0.18,Map3DStreetModel.tailLamp);mesh.makeGlowing(from:first)
            }
        }
        // Roof HVAC feet fill the entire 6 cm roof-to-enclosure gap.
        for x: Float in [-1.55,0.95] { box(x,3.52,0,0.20,1.46,0.06,steel) }
        shuttleShell([Map3DPoint(-1.92,3.58,0),Map3DPoint(1.32,3.58,0),Map3DPoint(1.12,3.76,0),Map3DPoint(-1.72,3.76,0)],halfWidth:0.88,color:white)
        for side: Float in [-1,1] { for x: Float in [-1.48,-1.16,-0.84,-0.52,-0.20,0.12,0.44,0.76] { box(x,3.62,side*0.886,0.18,0.02,0.075,steel) } }
        for x: Float in [-4.65,3.55] { box(x,3.52,0,0.80,0.78,0.03,steel);box(x,3.55,0,0.66,0.64,0.035,white) }
    }
}
