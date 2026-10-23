import Foundation

/// Independent static steam locomotive + tender reconstructed from ten owner
/// views. Metre dimensions and concealed axles are display estimates, not an
/// identification of a real locomotive. No operating train binding is added.
public enum Map3DSteamTender {
    public enum Unit: String, CaseIterable, Sendable {
        case locomotive, tender
        public var centre: Float { self == .locomotive ? 4.35 : -7.25 }
    }
    public struct Component: Sendable {
        public let name: String
        public let role: String
        public let model: Map3DModelPack.Model
    }
    public static let body = Map3DPalette.shopAwnings[0]
    public static let graphite = Map3DPalette.playerRim
    public static let trim = Map3DPalette.containers[3]
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.52)
    public static func components(_ unit: Unit) -> [Component] {
        var b = SteamTenderBuilder()
        if unit == .locomotive { b.locomotive() } else { b.tender() }
        return b.parts
    }
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for p in components(unit) { b.add(p.model, at: .zero) }
        return .flat(named: "steam-\(unit.rawValue)", from: b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for unit in Unit.allCases { b.add(model(unit), at: Map3DPoint(unit.centre, 0, 0)) }
        return .flat(named: "steam-formation", from: b.mesh)
    }
}

/// Each primitive is a closed, outward oriented solid. Semantic ranges let
/// the exported-geometry audit inspect the actual wheels, glazing and supports.
private struct SteamTenderBuilder {
    var parts: [Map3DSteamTender.Component] = []
    let body = Map3DSteamTender.body, dark = Map3DSteamTender.graphite
    let trim = Map3DSteamTender.trim, glass = Map3DSteamTender.glass
    let steel = Map3DPalette.tankSteel
    mutating func piece(_ name: String, _ role: String, _ build: (inout StationKitBuilder) -> Void) {
        var b = StationKitBuilder(); build(&b)
        parts.append(.init(name: name, role: role, model: .flat(named: name, from: b.mesh)))
    }
    mutating func box(_ name: String, _ role: String, _ x: Float, _ h: Float, _ z: Float,
                      _ l: Float, _ w: Float, _ height: Float, _ c: UInt32) {
        piece(name, role) { $0.box(x,h,z,l,w,height,c) }
    }
    mutating func tube(_ name: String, _ role: String, _ a: Map3DPoint, _ b: Map3DPoint,
                       _ radius: Float, _ c: UInt32, _ sides: Int = 12) {
        piece(name, role) { $0.civicTube(a,b,radius:radius,color:c,sides:sides) }
    }
    // A closed swept section. Rings are convex; each quad is explicitly split
    // into planar triangles so the roof and boiler cannot acquire missing faces.
    mutating func sweep(_ name: String, _ role: String, _ rings: [[Map3DPoint]], _ c: UInt32) {
        piece(name, role) { b in
            let centre=rings.flatMap { $0 }.reduce(Map3DPoint.zero) { $0+$1*(1/Float(rings.count*rings[0].count)) }
            b.face(rings[0],inside:centre,color:c); b.face(rings.last!,inside:centre,color:c)
            for k in 0..<rings.count-1 { for i in rings[0].indices {
                let j=(i+1)%rings[0].count
                b.face([rings[k][i],rings[k][j],rings[k+1][j]],inside:centre,color:c)
                b.face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:centre,color:c)
            } }
        }
    }
    mutating func wheel(_ name: String, x: Float, radius: Float, side: Float, spoked: Bool) {
        let z=side*1.02, n=20, inner=radius*(spoked ? 0.81:0.55)
        piece(name,"wheel") { b in
            func p(_ i: Int,_ r: Float,_ dz: Float)->Map3DPoint {
                let a=Float(i)*2*Float.pi/Float(n)
                return Map3DPoint(x+cosf(a)*r,radius+sinf(a)*r,z+dz)
            }
            // Annular wheel rim has a real opening, not a dark disc with lines.
            for i in 0..<n { let j=(i+1)%n
                let a=p(i,radius,-0.09),q=p(j,radius,-0.09),c=p(j,radius,0.09),d=p(i,radius,0.09)
                let e=p(i,inner,-0.09),f=p(j,inner,-0.09),g=p(j,inner,0.09),h=p(i,inner,0.09)
                let centre=Map3DPoint(x+(cosf(Float(i)*2*Float.pi/Float(n))+cosf(Float(j)*2*Float.pi/Float(n)))*(radius+inner)/4,
                                          radius+(sinf(Float(i)*2*Float.pi/Float(n))+sinf(Float(j)*2*Float.pi/Float(n)))*(radius+inner)/4,z)
                for face in [[a,q,c,d],[h,g,f,e],[a,e,f,q],[d,c,g,h]] { b.face(face,inside:centre,color:Map3DPalette.tankSteel) }
            }
        }
        tube(name+"-hub","wheel-hub",Map3DPoint(x,radius,z-0.10),Map3DPoint(x,radius,z+0.10),radius*0.20,body,12)
        let spokes=spoked ? 16:6
        for i in 0..<spokes {
            let a=Float(i)*2*Float.pi/Float(spokes),r=inner+0.025
            tube(name+"-spoke-\(i)","spoke",Map3DPoint(x,radius,z),Map3DPoint(x+cosf(a)*r,radius+sinf(a)*r,z),spoked ? 0.042:0.047,body,6)
        }
    }
    mutating func axle(_ name: String, _ x: Float, _ radius: Float) {
        tube(name,"axle",Map3DPoint(x,radius,-1.06),Map3DPoint(x,radius,1.06),0.095,dark,8)
        for side: Float in [-1,1] { wheel(name+"-\(side)",x:x,radius:radius,side:side,spoked:radius>0.8) }
    }
    mutating func locomotive() {
        // Narrow centre frame leaves the large spokes and their crowns clear.
        box("engine-frame","frame",0,0.83,0,13.7,0.72,0.38,dark)
        box("firebox","body",-3.7,1.20,0,2.2,1.70,1.95,dark)
        // Tapered rear boiler, cylindrical barrel and short graphite smokebox.
        let boilerRings: [[Map3DPoint]]=[(Float(-4.3),Float(1.02)),(-2.8,1.17),(3.4,1.13)].map { x,r in
            (0..<32).map { i in let a=Float(i)*2*Float.pi/32;return Map3DPoint(x,2.94+cosf(a)*r,sinf(a)*r) }
        }
        sweep("boiler","boiler",boilerRings,body)
        tube("smokebox","boiler",Map3DPoint(3.38,2.94,0),Map3DPoint(5.18,2.94,0),1.14,dark,32)
        for x: Float in [-3.05,-1.18,0.85,3.4] {
            tube("boiler-band-\(x)","band",Map3DPoint(x-0.023,2.94,0),Map3DPoint(x+0.023,2.94,0),x == -3.05 ? 1.149:1.177,steel,32)
        }
        tube("smokebox-rim","equipment",Map3DPoint(5.17,2.94,0),Map3DPoint(5.24,2.94,0),1.17,steel,32)
        tube("smokebox-door","equipment",Map3DPoint(5.23,2.94,0),Map3DPoint(5.30,2.94,0),0.98,dark,32)
        for i in 0..<12 { let a=Float(i)*2*Float.pi/12
            tube("door-bolt-\(i)","equipment",Map3DPoint(5.295,2.94+cosf(a)*0.89,sinf(a)*0.89),Map3DPoint(5.33,2.94+cosf(a)*0.89,sinf(a)*0.89),0.037,steel,6)
        }
        tube("headlamp-body","equipment",Map3DPoint(5.27,2.83,0),Map3DPoint(5.64,2.83,0),0.255,body,16)
        tube("headlamp-lens","equipment",Map3DPoint(5.64,2.83,0),Map3DPoint(5.66,2.83,0),0.19,Map3DPalette.shopAwnings[3],16)
        box("blank-front-plate","equipment",5.315,2.34,0,0.025,0.66,0.22,trim)
        // Low chimney and two separate boiler domes; no pantograph or HVAC.
        tube("chimney-foot","equipment",Map3DPoint(4.02,3.98,0),Map3DPoint(4.02,4.09,0),0.41,dark,20)
        tube("chimney","equipment",Map3DPoint(4.02,4.07,0),Map3DPoint(4.02,4.52,0),0.29,dark,20)
        tube("chimney-lip","equipment",Map3DPoint(4.02,4.49,0),Map3DPoint(4.02,4.56,0),0.34,steel,20)
        tube("chimney-dark-top","equipment",Map3DPoint(4.02,4.55,0),Map3DPoint(4.02,4.565,0),0.255,dark,20)
        for (x,r) in [(Float(1.85),Float(0.49)),(-1.30,0.40)] {
            let rings: [[Map3DPoint]]=[(Float(4.0),r),(4.36,r),(4.48,r*0.66)].map { h,rad in
                (0..<16).map { i in let a=Float(i)*2*Float.pi/16;return Map3DPoint(x+cosf(a)*rad,h,sinf(a)*rad) }
            }
            sweep("dome-\(x)","equipment",rings,body)
            tube("dome-trim-\(x)","band",Map3DPoint(x,4.35,0),Map3DPoint(x,4.39,0),r+0.015,trim,16)
        }
        box("bell-mount","support",4.84,3.83,0,0.4,0.50,0.30,body)
        tube("bell","equipment",Map3DPoint(4.84,4.06,0),Map3DPoint(4.84,4.33,0),0.16,trim,12)
        // Main axle positions reconstructed as visible groups. Concealed exact
        // arrangement is an explicit six-axle display completion.
        for x: Float in [-2.3,0,2.3] { axle("driver-\(x)",x,1.0) }
        for x: Float in [4.55,6.0] { axle("leading-\(x)",x,0.45) }
        axle("trailing",-5.10,0.50)
        box("leading-truck","frame",5.2,0.65,0,2.4,1.30,0.18,dark)
        box("trailing-truck","frame",-5.1,0.72,0,1.6,1.35,0.20,dark)
        for side: Float in [-1,1] {
            // Running boards sit above the wheel crowns, rather than clipping.
            box("running-board-\(side)","frame",0.15,2.055,side*1.18,10.5,0.48,0.12,body)
            for x: Float in [-2.3,0,2.3] {
                box("bearing-\(x)-\(side)","support",x,0.85,side*0.55,0.38,0.45,0.55,dark)
                tube("crankpin-\(x)-\(side)","pin",Map3DPoint(x+0.26,0.78,side*1.02),Map3DPoint(x+0.26,0.78,side*1.37),0.10,steel,10)
            }
            tube("coupling-rod-\(side)","rod",Map3DPoint(-2.04,0.78,side*1.37),Map3DPoint(2.56,0.78,side*1.37),0.095,steel,8)
            tube("main-rod-\(side)","rod",Map3DPoint(0.26,0.78,side*1.42),Map3DPoint(4.55,1.34,side*1.42),0.085,steel,8)
            tube("cylinder-\(side)","equipment",Map3DPoint(4.25,1.24,side*1.05),Map3DPoint(5.25,1.24,side*1.05),0.34,body,16)
            box("cylinder-saddle-\(side)","support",4.75,1.18,side*0.57,1.0,0.90,0.28,dark)
            tube("crosshead-\(side)","pin",Map3DPoint(4.42,1.34,side*1.05),Map3DPoint(4.42,1.34,side*1.44),0.14,dark,8)
            box("guide-\(side)","equipment",3.85,1.43,side*1.42,1.4,0.10,0.08,dark)
            // Distinct pipe runs on the two sides, with boiler-mounted brackets.
            for j in 0..<(side>0 ? 3:4) {
                let h=2.35+Float(j)*0.13,z=side*1.17
                tube("pipe-\(side)-\(j)-front","pipe",Map3DPoint(-2.5,h,z),Map3DPoint(3.9,h,z),0.028,dark,6)
                tube("pipe-\(side)-\(j)-bend","pipe",Map3DPoint(-3.3,1.78+Float(j)*0.13,z),Map3DPoint(-2.5,h,z),0.028,dark,6)
                tube("pipe-\(side)-\(j)-rear","pipe",Map3DPoint(-4.8,1.78+Float(j)*0.13,z),Map3DPoint(-3.3,1.78+Float(j)*0.13,z),0.028,dark,6)
            }
            for x: Float in [-2.4,0.3,2.9] {
                tube("handrail-post-\(x)-\(side)","support",Map3DPoint(x,3.55,side*0.86),Map3DPoint(x,3.55,side*1.17),0.035,steel,6)
                box("pipe-bracket-\(x)-\(side)","support",x,2.17,side*1.13,0.075,0.25,0.66,body)
            }
            tube("handrail-\(side)","rail",Map3DPoint(-3.8,3.55,side*1.17),Map3DPoint(4.8,3.55,side*1.17),0.030,steel,6)
            // Thin flush window frames over the actual cab wall, no grey boxes.
            box("cab-window-frame-\(side)","window-frame",-5.52,2.88,side*1.398,1.62,0.024,0.90,dark)
            box("cab-glass-\(side)","glass",-5.52,2.93,side*1.415,1.51,0.018,0.80,glass)
            for dx: Float in [-0.31,0.31] { box("cab-mullion-\(side)-\(dx)","window-frame",-5.52+dx,2.93,side*1.428,0.034,0.012,0.80,body) }
            box("cab-trim-top-\(side)","trim",-5.54,2.58,side*1.408,2.02,0.016,0.025,trim)
            box("cab-trim-low-\(side)","trim",-5.54,1.82,side*1.408,2.02,0.016,0.025,trim)
            for x: Float in [-6.55,-4.53] { box("cab-trim-edge-\(side)-\(x)","trim",x,1.82,side*1.408,0.025,0.016,0.785,trim) }
            for i in 0..<3 { box("cab-step-\(side)-\(i)","equipment",-6.6,0.65+Float(i)*0.33,side*1.32,0.50,0.44,0.09,dark) }
            for x: Float in [-6.77,-6.40] { tube("cab-step-upright-\(side)-\(x)","support",Map3DPoint(x,0.64,side*1.18),Map3DPoint(x,1.68,side*1.18),0.035,steel,6) }
        }
        box("cab-wall","body",-5.57,1.68,0,2.6,2.78,2.32,body)
        let roofSection: [(Float,Float)]=[(3.96,-1.51),(4.22,-1.15),(4.33,-0.55),(4.36,0),(4.33,0.55),(4.22,1.15),(3.96,1.51),(3.90,1.46),(4.14,1.11),(4.25,0.53),(4.28,0),(4.25,-0.53),(4.14,-1.11),(3.90,-1.46)]
        // Roof is built from closed individual strips (concave full roof ends
        // must not be triangulated as a convex fan).
        for i in 0..<6 {
            let section=[roofSection[i],roofSection[i+1],roofSection[12-i],roofSection[13-i]]
            sweep("cab-roof-\(i)","roof",[-7.0,-4.1].map { x in section.map { Map3DPoint(x,$0.0,$0.1) } },body)
        }
        box("roof-hatch","equipment",-5.55,4.34,0,0.72,0.74,0.06,dark)
        for side: Float in [-1,1] { box("front-cab-glass-\(side)","glass",-4.252,3.28,side*0.94,0.018,0.52,0.53,glass) }
        box("rear-cab-doorway","equipment",-6.881,1.72,0,0.022,1.20,1.97,dark)
        box("rear-cab-threshold","support",-6.92,1.64,0,0.22,1.35,0.09,steel)
        box("front-deck","frame",6.15,0.91,0,1.85,2.60,0.22,body)
        box("front-bufferbeam","frame",7.0,0.65,0,0.22,2.65,0.48,body)
        for side: Float in [-1,1] {
            tube("pilot-brace-\(side)","support",Map3DPoint(5.35,2.10,side*1.05),Map3DPoint(6.90,1.10,side*1.05),0.065,body,8)
            for i in 0..<4 { box("pilot-ladder-\(side)-\(i)","equipment",5.70+Float(i)*0.32,1.90-Float(i)*0.21,side*1.05,0.42,0.15,0.065,steel) }
        }
        for i in -6...6 { let z=Float(i)*0.17
            tube("cowcatcher-\(i)","equipment",Map3DPoint(6.92,0.72,z),Map3DPoint(7.34,0.26,z*0.72),0.036,body,6)
        }
        tube("pilot-bottom","support",Map3DPoint(7.34,0.26,-0.76),Map3DPoint(7.34,0.26,0.76),0.045,dark,8)
        box("front-coupler","coupler",7.37,0.59,0,0.60,0.40,0.33,dark)
        box("rear-coupler","coupler",-6.94,0.76,0,0.32,0.32,0.22,dark)
    }
    mutating func tender() {
        box("tender-frame","frame",0,1.0,0,8.0,2.58,0.22,dark)
        box("tank","body",0,1.22,0,8.0,2.75,1.72,body)
        // Coal bunker slopes inward at its upper shoulder; rear deck stays flat.
        for side: Float in [-1,1] {
            let section: [(Float,Float)]=[(2.90,1.25),(2.90,1.375),(3.58,1.18),(3.58,1.05)]
            sweep("bunker-wall-\(side)","body",[-1.6,3.95].map { x in section.map { Map3DPoint(x,$0.0,side*$0.1) } },body)
            for h: Float in [1.46,2.82] { box("tank-line-\(side)-\(h)","trim",0,h,side*1.383,7.65,0.016,0.026,trim) }
            for x: Float in [-3.83,3.83] { box("tank-line-end-\(side)-\(x)","trim",x,1.46,side*1.383,0.026,0.016,1.386,trim) }
            for x: Float in [-1.6,1.4] { box("tank-panel-\(side)-\(x)","equipment",x,1.50,side*1.379,0.023,0.012,1.26,Map3DColor.shaded(body,0.92)) }
        }
        box("bunker-rear","body",-1.56,2.92,0,0.14,2.20,0.56,body)
        box("bunker-front","body",3.87,2.92,0,0.16,2.20,0.38,body)
        // Closed low-poly coal mound seated in the bunker, no texture or noise.
        let rings: [[Map3DPoint]]=[(Float(2.93),Float(1.0)),(3.48,0.76),(3.64,0.28)].map { h,s in
            [(Float(-1.47),Float(-1.04)),(3.73,-1.04),(3.73,1.04),(-1.47,1.04)].map { x,z in Map3DPoint(1.13+(x-1.13)*s,h,z*s) }
        }
        sweep("coal","equipment",rings,dark)
        box("water-hatch-base","support",-2.68,2.94,0,1.12,1.24,0.07,steel)
        box("water-hatch","equipment",-2.68,3.01,0,0.98,1.10,0.05,body)
        for z: Float in [-0.31,0.31] { tube("hatch-handle-\(z)","equipment",Map3DPoint(-2.78,3.06,z),Map3DPoint(-2.56,3.06,z),0.025,dark,6) }
        for bx: Float in [-2.35,2.35] {
            box("bogie-\(bx)","frame",bx,0.60,0,2.20,1.68,0.30,dark)
            box("bolster-\(bx)","support",bx,0.88,0,1.1,1.60,0.12,steel)
            for dx: Float in [-0.72,0.72] {
                axle("tender-axle-\(bx)-\(dx)",bx+dx,0.47)
                for side: Float in [-1,1] {
                    box("axlebox-\(bx)-\(dx)-\(side)","support",bx+dx,0.43,side*0.82,0.32,0.38,0.37,dark)
                }
            }
            for side: Float in [-1,1] {
                box("bogie-side-\(bx)-\(side)","support",bx,0.56,side*1.04,2.05,0.16,0.20,dark)
                box("spring-hanger-\(bx)-\(side)","support",bx,0.66,side*1.04,0.13,0.26,0.20,dark)
                for i in -2...2 { box("spring-\(bx)-\(side)-\(i)","equipment",bx,0.73+Float(i)*0.035,side*1.04,0.63,0.22,0.023,steel) }
            }
        }
        for x: Float in [-4.02,4.02] {
            box("tender-endbeam-\(x)","frame",x,0.85,0,0.18,2.65,0.36,body)
            box("tender-coupler-\(x)","coupler",x+(x>0 ? 0.22:-0.22),0.76,0,0.52,0.32,0.22,dark)
            for side: Float in [-1,1] {
                box("tender-endstep-\(x)-\(side)","equipment",x,0.50,side*1.12,0.65,0.42,0.10,dark)
                tube("endstep-support-\(x)-\(side)","support",Map3DPoint(x,0.50,side*1.18),Map3DPoint(x,1.13,side*1.18),0.04,body,6)
            }
        }
        // Closed faceted coal pieces sit into the underlying solid mound.
        for (i,x) in [Float(-0.2),0.5,1.2,1.9,2.6].enumerated() {
            let z: Float = i%2 == 0 ? 0.24:-0.24
            piece("coal-lump-\(i)","equipment") { b in
                let c=Map3DPoint(x,3.51,z),r: Float=0.25
                let points=[c+Map3DPoint(0,0.24,0),c-Map3DPoint(0,0.19,0),c+Map3DPoint(r,0,0),c+Map3DPoint(0,0,r),c-Map3DPoint(r,0,0),c-Map3DPoint(0,0,r)]
                for j in 0..<4 { let a=2+j,d=2+(j+1)%4
                    b.face([points[0],points[a],points[d]],inside:c,color:Map3DSteamTender.graphite)
                    b.face([points[1],points[d],points[a]],inside:c,color:Map3DSteamTender.graphite)
                }
            }
        }
        // Rear-only ladder and grab rail. Front face has no driver's windows.
        for z: Float in [-0.90,-0.48] { tube("rear-ladder-\(z)","support",Map3DPoint(-4.12,0.90,z),Map3DPoint(-4.12,3.33,z),0.032,steel,6) }
        for i in 0..<8 { tube("rear-rung-\(i)","equipment",Map3DPoint(-4.12,1.06+Float(i)*0.28,-0.90),Map3DPoint(-4.12,1.06+Float(i)*0.28,-0.48),0.028,steel,6) }
        for z: Float in [-0.90,-0.48] { tube("ladder-anchor-\(z)","support",Map3DPoint(-3.98,2.85,z),Map3DPoint(-4.12,2.85,z),0.035,steel,6) }
        for z: Float in [-0.86,0.86] {
            tube("rear-grab-post-\(z)","support",Map3DPoint(-3.60,2.94,z),Map3DPoint(-3.60,3.38,z),0.03,steel,6)
        }
        tube("rear-grab","rail",Map3DPoint(-3.60,3.38,-0.86),Map3DPoint(-3.60,3.38,0.86),0.03,steel,6)
    }
}
