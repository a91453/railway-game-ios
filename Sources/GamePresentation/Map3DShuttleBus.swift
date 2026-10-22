import Foundation

/// A high-roof, short-bonnet shuttle minibus, recomposed from the owner's
/// four supplied views. Native axes: +x front, +y left, +z up; metres.
public enum Map3DShuttleBus {
    public static let modelName = "life-shuttleBus"
    public static let length: Float = 6.78
    public static let bodyWidth: Float = 2.08
    public static let height: Float = 2.88
    /// Reuse the game's muted teal and warm off-white, with opaque paint.
    public static let bodyColor = Map3DPalette.shopAwnings[0]
    public static let roofColor = Map3DPalette.shopAwnings[3]
    public static func model() -> Map3DModelPack.Model {
        var b=StationKitBuilder();b.shuttleBus()
        return .flat(named:modelName,from:b.mesh)
    }
}

extension StationKitBuilder {
    /// Ear clipping keeps the wheel arches open; a fan would fill their
    /// concave cut-outs with triangles. Input contour is counter-clockwise.
    mutating func shuttleShell(_ contour: [Map3DPoint],halfWidth: Float,color: UInt32,shoulder: Bool = false) {
        var indices=Array(contour.indices),triangles: [[Int]]=[]
        func cross(_ a: Map3DPoint,_ b: Map3DPoint,_ c: Map3DPoint) -> Float { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
        while indices.count>3 {
            var clipped=false
            for i in indices.indices {
                let a=indices[(i+indices.count-1)%indices.count],b=indices[i],c=indices[(i+1)%indices.count]
                guard cross(contour[a],contour[b],contour[c])>0.000001 else { continue }
                let contains=indices.contains { p in
                    p != a && p != b && p != c && cross(contour[a],contour[b],contour[p]) >= -0.000001 && cross(contour[b],contour[c],contour[p]) >= -0.000001 && cross(contour[c],contour[a],contour[p]) >= -0.000001
                }
                if !contains { triangles.append([a,b,c]);indices.remove(at:i);clipped=true;break }
            }
            precondition(clipped,"Invalid shuttle body contour")
        }
        triangles.append(indices)
        func at(_ p: Map3DPoint,_ side: Float) -> Map3DPoint { Map3DPoint(p.x,p.y,side*(halfWidth-(shoulder ? max(0,p.y-2.48)*0.30 : 0))) }
        for t in triangles {
            mesh.addFacet(t.map { at(contour[$0],1) },color:color)
            mesh.addFacet(t.reversed().map { at(contour[$0],-1) },color:color)
        }
        for i in contour.indices {
            let j=(i+1)%contour.count,a=contour[i],b=contour[j]
            mesh.addFacet([at(a,-1),at(b,-1),at(b,1),at(a,1)],color:color)
        }
    }
    mutating func shuttlePanel(_ points: [Map3DPoint],normal: Map3DPoint,color: UInt32,glows: Bool = false) {
        let start=mesh.vertices.count
        face(points,inside:points.reduce(.zero,+)*(1/Float(points.count))-normal,color:color)
        if glows { mesh.makeGlowing(from:start) }
    }
    mutating func shuttleSideWindow(_ x: Float,_ y: Float,_ z: Float,width: Float,height: Float) {
        let r: Float=0.055,a=x-width/2,b=x+width/2
        let outline=[Map3DPoint(a+r,y,z),Map3DPoint(b-r,y,z),Map3DPoint(b,y+r,z),Map3DPoint(b,y+height-r,z),Map3DPoint(b-r,y+height,z),Map3DPoint(a+r,y+height,z),Map3DPoint(a,y+height-r,z),Map3DPoint(a,y+r,z)]
        shuttlePanel(outline,normal:Map3DPoint(0,0,z>0 ? 1 : -1),color:Self.glass)
    }
    mutating func shuttleBus() {
        let teal=Map3DShuttleBus.bodyColor,cream=Map3DShuttleBus.roofColor,trim=Map3DStreetModel.trim,steel=Self.steel
        var contour=[Map3DPoint(-3.30,0.34,0)]
        for axle: Float in [-1.90,2.10] {
            contour.append(Map3DPoint(axle-0.44,0.34,0))
            for i in 0...12 { let a=Float.pi-Float(i)*Float.pi/12
                contour.append(Map3DPoint(axle+cosf(a)*0.44,0.36+sinf(a)*0.44,0))
            }
            contour.append(Map3DPoint(axle+0.44,0.34,0))
        }
        let roofFront: Float=2.50-(2.48-1.42)*0.90/1.16
        contour += [Map3DPoint(3.28,0.34,0),Map3DPoint(3.36,0.52,0),Map3DPoint(3.32,1.08,0),Map3DPoint(3.10,1.28,0),Map3DPoint(2.50,1.42,0),Map3DPoint(roofFront,2.48,0),Map3DPoint(-3.30,2.48,0)]
        shuttleShell(contour,halfWidth:1.04,color:teal)
        // Separate planar shoulder panels taper the high roof without
        // pulling the lower wall away from its window backing planes.
        let upper=[Map3DPoint(-3.30,2.48,0),Map3DPoint(roofFront,2.48,0),Map3DPoint(1.60,2.58,0),Map3DPoint(1.36,2.80,0),Map3DPoint(1.10,2.86,0),Map3DPoint(-3.02,2.86,0),Map3DPoint(-3.30,2.68,0)]
        shuttleShell(upper,halfWidth:1.04,color:teal,shoulder:true)
        // Roof cap sits on the same flat and sloping roof surfaces.
        box(-0.96,2.86,0,4.12,1.80,0.02,cream)
        shuttlePanel([Map3DPoint(1.10,2.88,-0.90),Map3DPoint(1.36,2.82,-0.90),Map3DPoint(1.36,2.82,0.90),Map3DPoint(1.10,2.88,0.90)],normal:Map3DPoint(0.2,1,0),color:cream)
        box(0,0.34,0,5.6,1.56,0.12,trim)
        for axle: Float in [-1.90,2.10] { for side: Float in [-1,1] {
            // Separate tyres/hubs, with actual empty arches in the shell.
            civicTube(Map3DPoint(axle,0.36,side*0.91),Map3DPoint(axle,0.36,side*1.12),radius:0.36,color:Map3DStreetModel.tyre,sides:20)
            civicTube(Map3DPoint(axle,0.36,side*1.12),Map3DPoint(axle,0.36,side*1.132),radius:0.23,color:steel,sides:16)
            civicTube(Map3DPoint(axle,0.36,side*1.132),Map3DPoint(axle,0.36,side*1.14),radius:0.11,color:Map3DPalette.roof,sides:12)
            for i in 0..<12 { let a=Float.pi-Float(i)*Float.pi/12,b=Float.pi-Float(i+1)*Float.pi/12,z=side*1.047
                shuttlePanel([Map3DPoint(axle+cosf(a)*0.44,0.36+sinf(a)*0.44,z),Map3DPoint(axle+cosf(b)*0.44,0.36+sinf(b)*0.44,z),Map3DPoint(axle+cosf(b)*0.49,0.36+sinf(b)*0.49,z),Map3DPoint(axle+cosf(a)*0.49,0.36+sinf(a)*0.49,z)],normal:Map3DPoint(0,0,side),color:trim)
            }
        } }
        // Waist trim stays above the wheel openings, never across a tyre.
        for side: Float in [-1,1] {
            box(-0.25,1.05,side*1.045,5.8,0.025,0.09,cream)
            if side<0 {
                box(-1.12,1.50,side*1.045,4.05,0.02,1.0,trim)
                for (x,w): (Float,Float) in [(-2.66,0.75),(-1.70,0.86),(-0.66,0.88),(0.38,0.80)] { shuttleSideWindow(x,1.60,side*1.062,width:w,height:0.78) }
            } else {
                box(-1.60,1.50,side*1.045,3.1,0.02,1.0,trim)
                for (x,w): (Float,Float) in [(-2.66,0.75),(-1.70,0.86),(-0.66,0.86)] { shuttleSideWindow(x,1.60,side*1.062,width:w,height:0.78) }
            }
            // Driver's trapezoidal side window follows the short bonnet.
            shuttlePanel([Map3DPoint(1.23,1.51,side*1.052),Map3DPoint(2.29,1.51,side*1.052),Map3DPoint(1.54,2.48,side*1.052),Map3DPoint(1.23,2.48,side*1.052)],normal:Map3DPoint(0,0,side),color:Self.glass)
            box(1.18,0.92,side*1.055,0.18,0.025,0.045,trim)
            box(1.08,0.45,side*1.05,0.018,0.018,2.1,trim)
            beam(Map3DPoint(1.81,1.70,side*1.04),Map3DPoint(1.74,1.90,side*1.28),0.035,steel)
            box(1.74,1.73,side*1.28,0.19,0.11,0.34,trim)
        }
        // Right-side folding passenger door: opaque backing, two tall panes.
        box(0.60,0.35,1.055,0.94,0.04,2.27,trim)
        for x: Float in [0.37,0.83] { box(x,0.48,1.079,0.40,0.018,2.03,teal);shuttleSideWindow(x,0.79,1.096,width:0.32,height:1.63) }
        box(0.60,0.35,1.09,0.035,0.025,2.27,steel)
        box(0.60,0.29,1.09,1.04,0.20,0.08,trim)
        // The screen is offset along the true raked front surface normal.
        func noseX(_ y: Float) -> Float { 2.50-(y-1.42)*0.90/1.16 }
        let n=Map3DPoint(1.16,0.90,0).normalized!
        shuttlePanel([Map3DPoint(noseX(1.50),1.50,-0.94)+n*0.012,Map3DPoint(noseX(1.50),1.50,0.94)+n*0.012,Map3DPoint(noseX(2.48),2.48,0.88)+n*0.012,Map3DPoint(noseX(2.48),2.48,-0.88)+n*0.012],normal:n,color:trim)
        shuttlePanel([Map3DPoint(noseX(1.57),1.57,-0.87)+n*0.014,Map3DPoint(noseX(1.57),1.57,0.87)+n*0.014,Map3DPoint(noseX(2.41),2.41,0.82)+n*0.014,Map3DPoint(noseX(2.41),2.41,-0.82)+n*0.014],normal:n,color:Self.glass)
        // Rear double doors, split rear glazing, vertical lamps.
        box(-3.305,1.43,0,0.02,1.78,0.95,trim)
        for side: Float in [-1,1] {
            box(-3.322,1.51,side*0.43,0.018,0.76,0.79,Self.glass)
            box(-3.318,0.54,side*0.95,0.025,0.12,0.75,Map3DStreetModel.tailLamp)
            let first=mesh.vertices.count;box(-3.335,0.62,side*0.95,0.018,0.08,0.57,Map3DStreetModel.tailLamp);mesh.makeGlowing(from:first)
            box(-3.33,1.02,side*0.12,0.025,0.16,0.045,trim)
        }
        box(-3.319,0.36,0,0.04,0.018,2.23,trim)
        box(-3.34,0.33,0,0.08,2.07,0.22,trim)
        box(3.305,0.35,0,0.18,1.96,0.19,trim)
        func frontX(_ y: Float) -> Float { 3.36-(y-0.52)*0.04/0.56+0.014 }
        for side: Float in [-1,1] {
            shuttlePanel([Map3DPoint(frontX(0.85),0.85,side*0.61),Map3DPoint(frontX(0.87),0.87,side*0.94),Map3DPoint(frontX(1.04),1.04,side*0.90),Map3DPoint(frontX(1.00),1.00,side*0.69)],normal:Map3DPoint(1,0.07,0),color:Map3DStreetModel.headlamp,glows:true)
        }
        for y: Float in [0.65,0.73,0.81] {
            shuttlePanel([Map3DPoint(frontX(y),y,-0.54),Map3DPoint(frontX(y),y,0.54),Map3DPoint(frontX(y+0.035),y+0.035,0.54),Map3DPoint(frontX(y+0.035),y+0.035,-0.54)],normal:Map3DPoint(1,0.07,0),color:trim)
        }
    }
}
