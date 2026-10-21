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
    public static let windowColor = Map3DColor.shaded(Map3DPalette.glazing,0.72)
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
        // Several short profile segments turn the upright lower screen
        // progressively into the roof. The old single rake looked boxy.
        let front: [(Float,Float)]=[(4.20,0.28),(4.28,0.50),(4.29,0.84),(4.28,1.14),(4.28,1.48),(4.25,1.82),(4.18,2.12),(4.04,2.39),(3.87,2.60),(3.72,2.72)]
        contour += front.map { Map3DPoint($0.0,$0.1,0) }
        contour.append(Map3DPoint(-4.52,2.72,0))
        shuttleShell(contour,halfWidth:1.19,color:white)
        // A continuous bowed nose and ten plan facets soften the corners.
        let sections: [(Float,Float)]=[(-1.19,0),(-1.13,0.12),(-0.98,0.21),(-0.75,0.25),(-0.38,0.273),(0,0.28),(0.38,0.273),(0.75,0.25),(0.98,0.21),(1.13,0.12),(1.19,0)]
        for i in 0..<front.count-1 { for j in 0..<sections.count-1 {
            let a=front[i],b=front[i+1],c=sections[j],d=sections[j+1]
            let n=Map3DPoint(b.1-a.1,a.0-b.0,0)
            shuttlePanel([Map3DPoint(a.0+c.1,a.1,c.0),Map3DPoint(a.0+d.1,a.1,d.0),Map3DPoint(b.0+d.1,b.1,d.0),Map3DPoint(b.0+c.1,b.1,c.0)],normal:n,color:white)
        } }
        for k in [0,front.count-1] { let p=front[k]
            for j in 0..<sections.count-1 { let a=sections[j],b=sections[j+1]
                var cap=[Map3DPoint(p.0,p.1,a.0)]
                if a.1>0 { cap.append(Map3DPoint(p.0+a.1,p.1,a.0)) }
                if b.1>0 { cap.append(Map3DPoint(p.0+b.1,p.1,b.0)) }
                cap.append(Map3DPoint(p.0,p.1,b.0))
                shuttlePanel(cap,normal:Map3DPoint(0,k==0 ? -1 : 1,0),color:white)
            }
        }
        // A closed longitudinal loft with a rounded transverse shoulder.
        // Side edges meet the body at 2.72m; there is no full-width flat
        // roof slab, and no overlapping differently coloured top faces.
        let roof: [(Float,Float)]=[(-4.52,2.72),(-4.38,2.89),(-4.12,2.99),(-3.70,3.03),(-1.0,3.03),(0.45,3.04),(1.40,3.13),(2.42,3.16),(2.80,3.14),(3.12,3.07),(3.40,2.92),(3.72,2.72)]
        func roofNode(_ row: Int,_ column: Int) -> Map3DPoint {
            let p=roof[row],s=sections[column],u=abs(s.0)/1.19
            let bow=max(0,min(1,(p.0-0.45)/1.95))
            return Map3DPoint(p.0+s.1*bow,2.72+(p.1-2.72)*cosf(u*Float.pi/2),s.0)
        }
        for i in 0..<roof.count-1 { for j in 0..<sections.count-1 {
            shuttlePanel([roofNode(i,j),roofNode(i+1,j),roofNode(i+1,j+1),roofNode(i,j+1)],normal:Map3DPoint(0,1,0),color:teal)
        } }
        let floor=[Map3DPoint(-4.52,2.72,-1.19),Map3DPoint(-4.52,2.72,1.19)]+sections.reversed().map { Map3DPoint(3.72+$0.1,2.72,$0.0) }
        // The bottom has a convex bowed front and is hidden inside the
        // body, nevertheless it is capped for the underside view.
        shuttlePanel(floor,normal:Map3DPoint(0,-1,0),color:teal)
        func window(_ x: Float,_ y: Float,_ z: Float,_ width: Float,_ height: Float) -> [Map3DPoint] {
            let r: Float=0.09,a=x-width/2,b=x+width/2
            return [Map3DPoint(a+r,y,z),Map3DPoint(b-r,y,z),Map3DPoint(b,y+r,z),Map3DPoint(b,y+height-r,z),Map3DPoint(b-r,y+height,z),Map3DPoint(a+r,y+height,z),Map3DPoint(a,y+height-r,z),Map3DPoint(a,y+r,z)]
        }
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
            // The dark ribbon reaches the nose; slimmer pillars and a
            // descending waist line avoid the old row of square boxes.
            let n=Map3DPoint(0,0,side),z=side*1.203
            // Split at the waist kink: these are convex patches. Using
            // one concave fan reversed the ribbon and exposed white gaps.
            shuttlePanel([Map3DPoint(-4.30,1.39,z),Map3DPoint(2.38,1.29,z),Map3DPoint(2.38,2.70,z),Map3DPoint(-4.30,2.70,z)],normal:n,color:trim)
            shuttlePanel([Map3DPoint(2.38,1.29,z),Map3DPoint(4.23,1.15,z),Map3DPoint(4.23,1.84,z),Map3DPoint(3.67,2.70,z),Map3DPoint(2.38,2.70,z)],normal:n,color:trim)
            shuttlePanel([Map3DPoint(-4.30,1.08,z),Map3DPoint(2.38,0.98,z),Map3DPoint(2.38,1.27,z),Map3DPoint(-4.30,1.37,z)],normal:n,color:teal)
            shuttlePanel([Map3DPoint(2.38,0.98,z),Map3DPoint(4.20,0.98,z),Map3DPoint(4.23,1.13,z),Map3DPoint(2.38,1.27,z)],normal:n,color:teal)
            let windows: [(Float,Float)]=side>0 ? [(-3.57,1.31),(-2.18,1.37),(-0.72,1.43),(0.57,1.08)] : [(-2.15,1.34),(-0.68,1.43),(0.83,1.48),(2.00,0.74)]
            for (x,w) in windows { shuttlePanel(window(x,1.46,side*1.213,w,1.18),normal:n,color:Map3DMidiBus.windowColor) }
            shuttlePanel([Map3DPoint(2.42,1.39,side*1.213),Map3DPoint(4.19,1.23,side*1.213),Map3DPoint(4.18,2.05,side*1.213),Map3DPoint(3.68,2.64,side*1.213),Map3DPoint(2.42,2.64,side*1.213)],normal:n,color:Map3DMidiBus.windowColor)
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
            shuttlePanel(window(x,0.68,1.247,0.36,1.87),normal:Map3DPoint(0,0,1),color:Map3DMidiBus.windowColor)
        }
        box(1.72,0.27,1.22,1.10,0.16,0.07,trim)
        box(1.72,0.29,1.252,0.025,0.018,2.38,trim)
        // The tall left-rear reference door becomes an emergency/equipment
        // hatch: body-coloured lower half, fine seam, small recessed grip.
        box(-3.55,0.33,-1.202,0.91,0.018,2.37,trim)
        shuttlePanel([Map3DPoint(-3.985,0.35,-1.215),Map3DPoint(-3.115,0.35,-1.215),Map3DPoint(-3.115,1.40,-1.215),Map3DPoint(-3.985,1.40,-1.215)],normal:Map3DPoint(0,0,-1),color:white)
        shuttlePanel(window(-3.55,1.49,-1.219,0.76,1.12),normal:Map3DPoint(0,0,-1),color:Map3DMidiBus.windowColor)
        box(-3.23,1.22,-1.225,0.11,0.014,0.025,trim)
        // Glazing follows every actual nose facet in BOTH dimensions.
        // Shared boundaries use the same x-offset (rather than divergent
        // per-pane normals) so adjacent panes cannot crack or flicker.
        for i in 3..<front.count-1 { for j in 0..<sections.count-1 {
            let a=front[i],b=front[i+1],c=sections[j],d=sections[j+1]
            let n=Map3DPoint(1,(a.0-b.0)/(b.1-a.1),-(d.1-c.1)/(d.0-c.0)).normalized!
            func pane(_ offset: Float) -> [Map3DPoint] {
                [Map3DPoint(a.0+c.1+offset,a.1,c.0),Map3DPoint(a.0+d.1+offset,a.1,d.0),Map3DPoint(b.0+d.1+offset,b.1,d.0),Map3DPoint(b.0+c.1+offset,b.1,c.0)]
            }
            shuttlePanel(pane(0.009),normal:n,color:trim)
            shuttlePanel(pane(0.015),normal:n,color:Map3DMidiBus.windowColor)
        } }
        // Destination brow is cut from the actual planar roof triangles.
        // Bilinear interpolation across a non-planar quad can bury a sign.
        func clipped(_ polygon: [(Map3DPoint,Float)],at limit: Float,above: Bool) -> [(Map3DPoint,Float)] {
            var result=[(Map3DPoint,Float)]()
            for i in polygon.indices {
                let a=polygon[i],b=polygon[(i+1)%polygon.count]
                let ai=above ? a.1>=limit : a.1<=limit,bi=above ? b.1>=limit : b.1<=limit
                if ai { result.append(a) }
                if ai != bi { let t=(limit-a.1)/(b.1-a.1);result.append((a.0*(1-t)+b.0*t,limit)) }
            }
            return result
        }
        for j in 3..<7 {
            let a=roofNode(10,j),b=roofNode(11,j),c=roofNode(11,j+1),d=roofNode(10,j+1)
            let triangles: [[(Map3DPoint,Float)]]=[[(a,0),(b,1),(c,1)],[(a,0),(c,1),(d,0)]]
            for triangle in triangles {
                var n=(triangle[1].0-triangle[0].0).cross(triangle[2].0-triangle[0].0).normalized!
                if n.y<0 { n=n * -1 }
                let patch=clipped(clipped(triangle,at:0.17,above:true),at:0.76,above:false)
                shuttlePanel(patch.map { $0.0+n*0.014 },normal:n,color:trim)
            }
        }
        func noseX(_ y: Float) -> Float {
            for i in 0..<front.count-1 where y<=front[i+1].1 {
                let a=front[i],b=front[i+1];return a.0+(b.0-a.0)*(y-a.1)/(b.1-a.1)
            }
            return front.last!.0
        }
        func bow(_ z: Float) -> Float {
            for i in 0..<sections.count-1 where z<=sections[i+1].0 {
                let a=sections[i],b=sections[i+1];return a.1+(b.1-a.1)*(z-a.0)/(b.0-a.0)
            }
            return 0
        }
        func onNose(_ y: Float,_ z: Float,_ offset: Float) -> Map3DPoint { Map3DPoint(noseX(y)+bow(z)+offset,y,z) }
        // The painted apron rises gently towards both corners.
        for j in 0..<sections.count-1 { let a=sections[j].0,b=sections[j+1].0
            func low(_ z: Float) -> Float { 0.91+abs(z)/1.19*0.08 }
            func high(_ z: Float) -> Float { 1.07+abs(z)/1.19*0.06 }
            shuttlePanel([onNose(low(a),a,0.009),onNose(low(b),b,0.009),onNose(high(b),b,0.009),onNose(high(a),a,0.009)],normal:Map3DPoint(1,0,0),color:teal)
        }
        // Swept slim lamps wrap two real front-corner facets, rather than
        // floating a broad rectangular headlamp across the curved nose.
        for side: Float in [-1,1] { for j in 7..<9 {
            let a=sections[j].0*side,b=sections[j+1].0*side
            func low(_ z: Float) -> Float { 0.66+(abs(z)-0.75)*0.30 }
            func high(_ z: Float) -> Float { 0.83+(abs(z)-0.75)*0.42 }
            let n=Map3DPoint(1,0,side*0.3)
            shuttlePanel([onNose(low(a),a,0.012),onNose(low(b),b,0.012),onNose(high(b),b,0.012),onNose(high(a),a,0.012)],normal:n,color:trim)
            shuttlePanel([onNose(low(a)+0.035,a,0.019),onNose(low(b)+0.035,b,0.019),onNose(high(b)-0.035,b,0.019),onNose(high(a)-0.035,a,0.019)],normal:n,color:Map3DStreetModel.headlamp,glows:true)
        } }
        // Rear window is backed by the flat rear shell. Clean painted rear
        // cover avoids the heavy grey luggage lids of the earlier coach.
        box(-4.527,1.62,0,0.014,1.96,0.98,trim)
        box(-4.540,1.70,0,0.012,1.80,0.82,Map3DMidiBus.windowColor)
        box(-4.535,0.43,0,0.03,2.14,0.11,teal)
        box(-4.548,0.77,0,0.018,0.36,0.12,trim)
        for side: Float in [-1,1] { for (y,c): (Float,UInt32) in [(0.76,Map3DStreetModel.headlamp),(0.98,Map3DPalette.platformEdge),(1.20,Map3DStreetModel.tailLamp)] {
            civicTube(Map3DPoint(-4.525,y,side*0.97),Map3DPoint(-4.565,y,side*0.97),radius:0.075,color:trim,sides:12)
            let first=mesh.vertices.count;civicTube(Map3DPoint(-4.565,y,side*0.97),Map3DPoint(-4.575,y,side*0.97),radius:0.052,color:c,sides:12);mesh.makeGlowing(from:first)
        } }

    }
}
