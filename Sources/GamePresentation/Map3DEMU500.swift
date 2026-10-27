import Foundation

/// Independent EMU500 static reconstruction; no prior vehicle mesh is reused.
/// Builder X/front Y/up Z/right; Model.flat converts to native metres Z/up.
public enum Map3DEMU500 {
    public enum Unit: String, CaseIterable, Sendable { case emc, ep, et, em }
    public static let pitch: Float = 20.33
    public static let order: [Unit] = [.emc, .ep, .et, .em]
    public static let centres: [Float] = [30.495, 10.165, -10.165, -30.495]
    public static let rotations: [Float] = [0, 0, 0, .pi]
    public static let blue = Map3DColor.rgb(0x214F90)
    public static let silver = Map3DColor.rgb(0xBBC6C9)
    public static let glass = Map3DColor.rgb(0x263C40)
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b = StationKitBuilder(); b.emu500(unit)
        return .flat(named: "emu500-\(unit.rawValue)", from: b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for i in order.indices { b.add(model(order[i]), at: Map3DPoint(centres[i],0,0), angle: rotations[i]) }
        return .flat(named: "emu500-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    /// A convex closed prism with outward winding on every face.
    mutating func e500Prism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let centre = (a+b).reduce(Map3DPoint.zero) { $0+$1*(1/Float(a.count+b.count)) }
        face(a,inside:centre,color:color); face(b,inside:centre,color:color)
        for i in a.indices { let j=(i+1)%a.count; face([a[i],a[j],b[j],b[i]],inside:centre,color:color) }
    }
    mutating func e500Panel(x: Float, y: Float, z: Float, w: Float, h: Float, depth: Float, front: Bool, color: UInt32) {
        let r: Float = min(0.10,min(w,h)*0.16)
        let p: [(Float,Float)] = [(-w/2+r,0),(w/2-r,0),(w/2,r),(w/2,h-r),(w/2-r,h),(-w/2+r,h),(-w/2,h-r),(-w/2,r)]
        func layer(_ d: Float)->[Map3DPoint] { p.map { u,v in front ? Map3DPoint(x+d,y+v,z+u) : Map3DPoint(x+u,y+v,z+d) } }
        e500Prism(layer(-depth/2),layer(depth/2),color)
    }
    mutating func emu500(_ unit: Map3DEMU500.Unit) {
        let cab = unit == .emc || unit == .em
        let silver=Map3DEMU500.silver, blue=Map3DEMU500.blue, glass=Map3DEMU500.glass
        let dark=Map3DPalette.playerRim, white=Map3DPalette.tileWhite, yellow=Map3DColor.rgb(0xFFC86B)
        // Fresh cross-section: upright sides, rolled shoulders, broad shallow roof.
        let profile: [(Float,Float)] = [(1.12,-1.34),(1.18,-1.4265),(3.22,-1.4265),(3.40,-1.39),(3.55,-1.27),(3.63,-1.04),(3.65,-0.65),(3.65,0.65),(3.63,1.04),(3.55,1.27),(3.40,1.39),(3.22,1.4265),(1.18,1.4265),(1.12,1.34)]
        func ring(_ x: Float,_ width: Float)->[Map3DPoint] { profile.map { Map3DPoint(x,$0.0,$0.1*width) } }
        // End cap is subtly rounded in plan, not a projecting express nose.
        e500Prism(ring(-9.94,1),ring(cab ? 9.52 : 9.94,1),silver)
        if cab { e500Prism(ring(9.52,1),ring(9.94,0.955),blue) }
        box(0,0.96,0,19.6,2.53,0.16,dark)
        // Waist stripes sit on the vertical body; doors overlay them locally.
        for side: Float in [-1,1] {
            box(0,2.12,side*1.433,19.84,0.014,0.075,blue)
            box(0,2.205,side*1.433,19.84,0.014,0.045,white)
            box(0,3.22,side*1.426,19.5,0.016,0.05,blue)
            for y: Float in [1.32,1.49,1.66,1.83] { box(0,y,side*1.431,19.5,0.01,0.018,silver) }
            // Three pairs of flush passenger doors. All dimensions proportional estimates.
            for x: Float in [-5.9,0,5.9] {
                e500Panel(x:x,y:1.17,z:side*1.438,w:1.33,h:1.94,depth:0.024,front:false,color:dark)
                for dx: Float in [-0.323,0.323] {
                    box(x+dx,1.19,side*1.463,0.625,0.018,1.9,silver)
                    e500Panel(x:x+dx,y:2.30,z:side*1.480,w:0.43,h:0.65,depth:0.014,front:false,color:glass)
                }
            }
            let windows: [Float] = [-8.0,-3.95,-1.98,1.98,3.95,8.0]
            for (i,x) in windows.enumerated() {
                let small = (unit == .ep && i == 0) || (unit == .et && i == 5)
                let w: Float = small ? 0.62 : 1.22
                let y: Float = small ? 2.49 : 2.32
                e500Panel(x:x,y:y,z:side*1.438,w:w+0.07,h:small ? 0.43 : 0.77,depth:0.023,front:false,color:dark)
                e500Panel(x:x,y:y+0.035,z:side*1.454,w:w,h:small ? 0.36 : 0.70,depth:0.014,front:false,color:glass)
                if !small && i % 3 == 0 { box(x,y+0.53,side*1.476,w,0.012,0.025,silver) }
            }
            if cab {
                // Slanting blue cab-side boundary observed in the supplied views.
                let a=[Map3DPoint(8.30,3.20,side*1.433),Map3DPoint(9.50,3.20,side*1.433),Map3DPoint(9.50,1.18,side*1.433),Map3DPoint(9.20,1.18,side*1.433)]
                e500Prism(a,a.map { $0+Map3DPoint(0,0,side*0.009) },blue)
                e500Panel(x:9.05,y:2.40,z:side*1.435,w:0.60,h:0.65,depth:0.025,front:false,color:glass) }
        }
        // Two separate two-axle bogies; 860 mm tyres at native rail Z=0.
        for bx: Float in [-6.65,6.65] {
            box(bx,0.47,0,3.6,1.90,0.24,dark)
            box(bx,0.71,0,1.15,1.65,0.25,dark)
            for ax: Float in [-1.4,1.4] {
                beam(Map3DPoint(bx+ax,0.43,-0.72),Map3DPoint(bx+ax,0.43,0.72),0.13,dark)
                for side: Float in [-1,1] {
                    let z=side*0.615
                    func circle(_ zz: Float)->[Map3DPoint] { (0..<16).map { i in let a=Float(i)*2*Float.pi/16;return Map3DPoint(bx+ax+0.43*cosf(a),0.43+0.43*sinf(a),zz) } }
                    e500Prism(circle(z-0.09),circle(z+0.09),dark)
                }
            }
        }
        for (i,x) in [Float(-3.8),-1.4,1.5,3.8].enumerated() {
            box(x,0.56,unit == .ep ? 0.15 : -0.12,1.8,1.8,i % 2 == 0 ? 0.40 : 0.33,dark)
            box(x,0.87,0,0.30,1.65,0.09,dark)
        }
        // Roof AC housings seated on real roof, with shallow matte grille panels.
        for x: Float in [-7.8,7.8] {
            box(x,3.65,0,2.60,1.75,0.064,silver)
            box(x,3.714,0,2.35,1.58,0.25,silver)
            for dx: Float in [-0.55,0,0.55] { box(x+dx,3.965,0,0.43,1.30,0.012,dark) }
        }
        if unit == .ep {
            box(-5.3,3.65,0,1.9,1.6,0.10,dark)
            for z: Float in [-0.5,0.5] {
                cylinder(-5.3,3.75,z,radius:0.10,height:0.18,color:silver,sides:8)
                beam(Map3DPoint(-5.8,3.93,z),Map3DPoint(-4.5,4.48,z),0.065,dark)
                beam(Map3DPoint(-4.5,4.48,z),Map3DPoint(-5.6,4.95,z),0.055,dark)
            }
            box(-5.6,4.95,0,0.10,1.75,0.05,dark)
        }
        // Couplers and supported gangways; no cab features on EP / ET.
        for end: Float in [-1,1] {
            box(end*10.03,0.70,0,0.27,0.36,0.25,dark)
            if end < 0 || !cab { box(end*9.99,1.25,0,0.10,1.04,1.95,dark) }
        }
        if cab {
            // Central gangway frame and door, with two independent driving panes.
            box(9.965,1.18,0,0.05,1.03,2.18,dark)
            box(10.00,1.25,0,0.025,0.78,1.98,blue)
            e500Panel(x:10.022,y:2.16,z:0,w:0.43,h:0.76,depth:0.018,front:true,color:glass)
            box(10.022,1.66,0,0.02,0.68,0.40,white)
            for z: Float in [-0.92,0.92] {
                e500Panel(x:9.954,y:2.26,z:z,w:0.62,h:0.94,depth:0.036,front:true,color:dark)
                e500Panel(x:9.978,y:2.31,z:z,w:0.54,h:0.83,depth:0.018,front:true,color:glass)
                for dy: Float in [0,0.11,0.22] {
                    let side: Float = z < 0 ? -1 : 1
                    box(9.979,1.91+dy,side*1.03,0.025,0.43,0.037,white)
                    beam(Map3DPoint(9.991,1.929+dy,side*0.815),Map3DPoint(9.991,1.87+dy,side*0.69),0.037,white)
                    box(9.979,1.60+dy,side*0.69,0.025,0.037,0.27,white)
                }
                // Circular lower lamp pods are horizontal closed prisms.
                for dz: Float in [-0.17,0.17] {
                    let points=(0..<12).map { i in let a=Float(i)*2*Float.pi/12;return Map3DPoint(9.98,1.65+0.12*sinf(a),z+dz+0.12*cosf(a)) }
                    e500Prism(points,points.map { $0+Map3DPoint(0.055,0,0) },dz < 0 ? white : dark)
                }
            }
            box(9.91,3.40,0,0.20,0.63,0.27,dark)
            for z: Float in [-0.17,0.17] {
                let p=(0..<12).map { i in let a=Float(i)*2*Float.pi/12;return Map3DPoint(10.01,3.535+0.10*sinf(a),z+0.10*cosf(a)) }
                e500Prism(p,p.map { $0+Map3DPoint(0.025,0,0) },yellow)
            }
            box(9.90,0.38,0,0.10,2.60,0.73,dark)
            box(10.08,0.70,0,0.17,0.40,0.30,dark)
            // Simplified hazard chevrons on a physical lower apron.
            for z: Float in [-1.00,-0.50,0.50,1.00] {
                let direction: Float = z < 0 ? -1 : 1
                beam(Map3DPoint(9.96,0.40,z-direction*0.18),Map3DPoint(9.96,1.08,z+direction*0.18),0.17,yellow)
            }
        }
    }
}
