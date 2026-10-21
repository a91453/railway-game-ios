import Foundation

/// Rounded cab-over midibus, recomposed from the owner's four reference views.
/// Internal builder axes are x/front, y/up, z/right; flat converts exactly once.
public enum Map3DMidiBus {
    public static let modelName = "life-midiBus"
    public static let length: Float = 9.15
    public static let bodyWidth: Float = 2.38
    public static let height: Float = 3.16
    public static let bodyColor = Map3DPalette.shopAwnings[3]
    public static let accentColor = Map3DPalette.shopAwnings[0]
    public static func model() -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.midiBus()
        return .flat(named:modelName,from:b.mesh)
    }
}

extension StationKitBuilder {
    mutating func midiBus() {
        let white=Map3DMidiBus.bodyColor,teal=Map3DMidiBus.accentColor
        let trim=Map3DStreetModel.trim,steel=Self.steel
        // The planar side contour has two genuine concave wheel openings.
        var contour=[Map3DPoint(-4.52,0.28,0)]
        for axle: Float in [-2.12,2.86] {
            contour.append(Map3DPoint(axle-0.53,0.28,0))
            for i in 0...12 { let a=Float.pi-Float(i)*Float.pi/12
                contour.append(Map3DPoint(axle+cosf(a)*0.53,0.44+sinf(a)*0.53,0))
            }
            contour.append(Map3DPoint(axle+0.53,0.28,0))
        }
        let front: [(Float,Float)]=[(4.20,0.28),(4.28,0.50),(4.21,1.24),(3.75,2.48),(3.486,2.80),(3.42,2.88),(3.04,3.10),(2.65,3.16)]
        contour += front.prefix(5).map { Map3DPoint($0.0,$0.1,0) }
        contour.append(Map3DPoint(-4.52,2.80,0))
        shuttleShell(contour,halfWidth:1.19,color:white)
        // Closed faceted nose: the central bow projects 29 cm beyond the
        // side contour. Seven sections round the corners in plan as well
        // as in profile, instead of merely painting a square bus front.
        let sections: [(Float,Float)]=[(-1.19,0),(-1.04,0.16),(-0.68,0.25),(0,0.29),(0.68,0.25),(1.04,0.16),(1.19,0)]
        for i in 0..<front.count-1 { for j in 0..<sections.count-1 {
            let a=front[i],b=front[i+1],c=sections[j],d=sections[j+1]
            let n=Map3DPoint(b.1-a.1,a.0-b.0,0)
            shuttlePanel([Map3DPoint(a.0+c.1,a.1,c.0),Map3DPoint(a.0+d.1,a.1,d.0),Map3DPoint(b.0+d.1,b.1,d.0),Map3DPoint(b.0+c.1,b.1,c.0)],normal:n,color:i>=4 ? teal : white)
        } }
        for k in [0,front.count-1] { let p=front[k]
            for j in 0..<sections.count-1 { let a=sections[j],b=sections[j+1]
                var cap=[Map3DPoint(p.0,p.1,a.0)]
                if a.1>0 { cap.append(Map3DPoint(p.0+a.1,p.1,a.0)) }
                if b.1>0 { cap.append(Map3DPoint(p.0+b.1,p.1,b.0)) }
                cap.append(Map3DPoint(p.0,p.1,b.0))
                shuttlePanel(cap,normal:Map3DPoint(0,k==0 ? -1 : 1,0),color:k==0 ? white : teal)
            }
        }
        // Raised forehead is an integral closed roof, not a floating box.
        shuttleShell([Map3DPoint(-4.52,2.80,0),Map3DPoint(3.486,2.80,0),Map3DPoint(3.42,2.88,0),Map3DPoint(3.04,3.10,0),Map3DPoint(2.65,3.16,0),Map3DPoint(1.40,3.16,0),Map3DPoint(0.35,3.03,0),Map3DPoint(-4.24,3.03,0)],halfWidth:1.194,color:teal)
        box(-0.10,0.28,0,8.18,1.68,0.12,trim)
        for axle: Float in [-2.12,2.86] { for side: Float in [-1,1] {
            civicTube(Map3DPoint(axle,0.44,side*1.00),Map3DPoint(axle,0.44,side*1.225),radius:0.44,color:Map3DStreetModel.tyre,sides:20)
            civicTube(Map3DPoint(axle,0.44,side*1.225),Map3DPoint(axle,0.44,side*1.238),radius:0.27,color:steel,sides:16)
            civicTube(Map3DPoint(axle,0.44,side*1.238),Map3DPoint(axle,0.44,side*1.245),radius:0.115,color:trim,sides:12)
            for i in 0..<12 { let a=Float.pi-Float(i)*Float.pi/12,b=Float.pi-Float(i+1)*Float.pi/12,z=side*1.198
                shuttlePanel([Map3DPoint(axle+cosf(a)*0.53,0.44+sinf(a)*0.53,z),Map3DPoint(axle+cosf(b)*0.53,0.44+sinf(b)*0.53,z),Map3DPoint(axle+cosf(b)*0.57,0.44+sinf(b)*0.57,z),Map3DPoint(axle+cosf(a)*0.57,0.44+sinf(a)*0.57,z)],normal:Map3DPoint(0,0,side),color:teal)
            }
        } }
        for side: Float in [-1,1] {
            box(-0.30,1.40,side*1.195,7.95,0.018,1.35,trim)
            box(-0.32,1.14,side*1.195,7.98,0.018,0.23,teal)
            let windows: [(Float,Float)]=side>0 ? [(-3.53,1.17),(-2.16,1.25),(-0.72,1.35),(0.58,1.02)] : [(-2.13,1.27),(-0.66,1.40),(0.88,1.42),(2.00,0.65)]
            for (x,w) in windows { shuttleSideWindow(x,1.49,side*1.212,width:w,height:1.16) }
            // Front side pane follows the actual raked roof boundary.
            shuttlePanel([Map3DPoint(2.40,1.49,side*1.212),Map3DPoint(4.10,1.49,side*1.212),Map3DPoint(3.65,2.56,side*1.212),Map3DPoint(2.40,2.65,side*1.212)],normal:Map3DPoint(0,0,side),color:Self.glass)
            // Solid backing already extends to x=4.117 at y=1.49, but
            // the upper corner is inset from the front contour as well.
            for x: Float in [-4.05,-0.72,3.85] { let first=mesh.vertices.count
                box(x,0.60,side*1.204,0.13,0.02,0.055,Map3DPalette.platformEdge);mesh.makeGlowing(from:first)
            }
            beam(Map3DPoint(3.43,2.72,side*1.19),Map3DPoint(3.62,2.72,side*1.40),0.035,steel)
            beam(Map3DPoint(3.62,2.72,side*1.40),Map3DPoint(3.62,2.43,side*1.40),0.035,steel)
            box(3.62,2.29,side*1.40,0.19,0.11,0.30,trim)
        }
        // Right-front double folding passenger door; no left-side boarding.
        box(1.72,0.29,1.207,1.06,0.04,2.40,trim)
        for x: Float in [1.47,1.97] {
            box(x,0.35,1.231,0.45,0.018,2.27,white)
            shuttleSideWindow(x,0.68,1.247,width:0.36,height:1.87)
        }
        box(1.72,0.27,1.22,1.10,0.16,0.07,trim)
        box(1.72,0.29,1.252,0.025,0.018,2.38,trim)
        // The tall left-rear reference door becomes an emergency/equipment
        // hatch: body-coloured lower half, fine seam, small recessed grip.
        box(-3.55,0.33,-1.202,0.91,0.018,2.37,trim)
        shuttlePanel([Map3DPoint(-3.985,0.35,-1.215),Map3DPoint(-3.115,0.35,-1.215),Map3DPoint(-3.115,1.40,-1.215),Map3DPoint(-3.985,1.40,-1.215)],normal:Map3DPoint(0,0,-1),color:white)
        shuttleSideWindow(-3.55,1.49,-1.219,width:0.76,height:1.12)
        box(-3.23,1.22,-1.225,0.11,0.014,0.025,trim)
        // Curved panoramic screen: four independently backed plan facets.
        func frontX(_ y: Float) -> Float { 4.21-(y-1.24)*0.46/1.24 }
        for j in 1..<sections.count-2 { let a=sections[j],b=sections[j+1]
            let n=Map3DPoint(1,0.46/1.24,-(b.1-a.1)/(b.0-a.0)).normalized!
            func pane(_ low: Float,_ high: Float,_ offset: Float) -> [Map3DPoint] {
                [Map3DPoint(frontX(low)+a.1,low,a.0)+n*offset,Map3DPoint(frontX(low)+b.1,low,b.0)+n*offset,Map3DPoint(frontX(high)+b.1,high,b.0)+n*offset,Map3DPoint(frontX(high)+a.1,high,a.0)+n*offset]
            }
            shuttlePanel(pane(1.31,2.46,0.009),normal:n,color:trim)
            shuttlePanel(pane(1.36,2.42,0.015),normal:n,color:Self.glass)
        }
        // Separate destination brow follows the next genuine body slope.
        for side: Float in [-1,1] {
            let n=Map3DPoint(1,0.33/0.40,side*0.04/0.68).normalized!
            func brow(_ y: Float,_ z: Float) -> Map3DPoint { Map3DPoint(3.75-(y-2.48)*0.33/0.40+0.29-abs(z)*0.04/0.68,y,z)+n*0.012 }
            shuttlePanel([brow(2.55,0),brow(2.55,side*0.62),brow(2.77,side*0.62),brow(2.77,0)],normal:n,color:trim)
        }
        for side: Float in [-1,1] {
            // Small swept lamps, mounted on a real lower-front facet.
            let n=Map3DPoint(1,0.07/0.74,side*0.25).normalized!
            func lamp(_ y: Float,_ z: Float) -> Map3DPoint {
                Map3DPoint(4.28-(y-0.50)*0.07/0.74+0.25-(abs(z)-0.68)*0.25,y,z)+n*0.012
            }
            shuttlePanel([lamp(0.80,side*0.72),lamp(0.83,side*1.00),lamp(1.01,side*1.00),lamp(0.96,side*0.72)],normal:n,color:trim)
            shuttlePanel([lamp(0.84,side*0.76)+n*0.006,lamp(0.86,side*0.96)+n*0.006,lamp(0.96,side*0.96)+n*0.006,lamp(0.92,side*0.76)+n*0.006],normal:n,color:Map3DStreetModel.headlamp,glows:true)
        }
        // Rear window is backed by the flat rear shell. Clean painted rear
        // cover avoids the heavy grey luggage lids of the earlier coach.
        box(-4.527,1.62,0,0.014,1.96,0.98,trim)
        box(-4.540,1.70,0,0.012,1.80,0.82,Self.glass)
        box(-4.535,0.43,0,0.03,2.14,0.11,teal)
        box(-4.548,0.77,0,0.018,0.36,0.12,trim)
        for side: Float in [-1,1] { for (y,c): (Float,UInt32) in [(0.76,Map3DStreetModel.headlamp),(0.98,Map3DPalette.platformEdge),(1.20,Map3DStreetModel.tailLamp)] {
            civicTube(Map3DPoint(-4.525,y,side*0.97),Map3DPoint(-4.565,y,side*0.97),radius:0.075,color:trim,sides:12)
            let first=mesh.vertices.count;civicTube(Map3DPoint(-4.565,y,side*0.97),Map3DPoint(-4.575,y,side*0.97),radius:0.052,color:c,sides:12);mesh.makeGlowing(from:first)
        } }
        // Shallow roof service hatches contact the real rear roof at 3.03m.
        for x: Float in [-2.82,-0.95] { box(x,3.03,0,0.68,0.70,0.015,white) }
    }
}
