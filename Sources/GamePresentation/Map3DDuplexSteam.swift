import Foundation

/// Second reference train: two triples of near-equal driving wheels, a mid/front
/// cab, rear boiler/firebox, forward smokebox and independent tender. All metre
/// dimensions are proportional display estimates; exact type/hinges unconfirmed.
public enum Map3DDuplexSteam {
    public enum Unit: String, CaseIterable, Sendable {
        case locomotive, tender
        public var centre: Float { self == .locomotive ? 4.6 : -6.5 }
    }
    public struct Component: Sendable {
        public let name: String
        public let role: String
        public let model: Map3DModelPack.Model
    }
    public static let body = Map3DPalette.trimBlue
    public static let cream = Map3DPalette.shopAwnings[3]
    public static let graphite = Map3DPalette.playerRim
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.52)
    public static func components(_ unit: Unit) -> [Component] {
        var b = DuplexSteamBuilder()
        if unit == .locomotive { b.locomotive() } else { b.tender() }
        return b.parts
    }
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for p in components(unit) { b.add(p.model, at: .zero) }
        return .flat(named:"duplex-\(unit.rawValue)",from:b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for unit in Unit.allCases { b.add(model(unit),at:Map3DPoint(unit.centre,0,0)) }
        return .flat(named:"duplex-formation",from:b.mesh)
    }
}

private struct DuplexSteamBuilder {
    var parts: [Map3DDuplexSteam.Component] = []
    let body=Map3DDuplexSteam.body, cream=Map3DDuplexSteam.cream
    let dark=Map3DDuplexSteam.graphite, glass=Map3DDuplexSteam.glass
    let steel=Map3DPalette.tankSteel, gold=Map3DPalette.containers[3]
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
    mutating func wheel(_ name: String, _ x: Float, _ r: Float, _ side: Float, driver: Bool) {
        let lateral=side*1.10,inner=r*0.81,n=16
        piece(name,"wheel") { b in
            func p(_ i: Int,_ radius: Float,_ offset: Float)->Map3DPoint {
                let t=Float(i)*2*Float.pi/Float(n)
                return Map3DPoint(x+cosf(t)*radius,r+sinf(t)*radius,lateral+offset)
            }
            for i in 0..<n { let j=(i+1)%n
                let centre=(p(i,(r+inner)/2,0)+p(j,(r+inner)/2,0))*0.5
                for face in [[p(i,r,-0.08),p(j,r,-0.08),p(j,r,0.08),p(i,r,0.08)],
                             [p(i,inner,0.08),p(j,inner,0.08),p(j,inner,-0.08),p(i,inner,-0.08)],
                             [p(i,r,-0.08),p(i,inner,-0.08),p(j,inner,-0.08),p(j,r,-0.08)],
                             [p(i,r,0.08),p(j,r,0.08),p(j,inner,0.08),p(i,inner,0.08)]] { b.face(face,inside:centre,color:Map3DPalette.tankSteel) }
            }
        }
        tube(name+"-hub","hub",Map3DPoint(x,r,lateral-0.10),Map3DPoint(x,r,lateral+0.10),r*0.21,dark,8)
        let count=driver ? 10:6
        for i in 0..<count {
            let t=Float(i)*2*Float.pi/Float(count)
            piece(name+"-spoke-\(i)","spoke") { b in
                b.beam(Map3DPoint(x,r,lateral),Map3DPoint(x+cosf(t)*(inner+0.02),r+sinf(t)*(inner+0.02),lateral),driver ? 0.064:0.055,Map3DDuplexSteam.graphite)
            }
        }
    }
    mutating func axle(_ name: String,_ x: Float,_ r: Float,driver: Bool) {
        tube(name,"axle",Map3DPoint(x,r,-1.17),Map3DPoint(x,r,1.17),0.085,dark,8)
        for side: Float in [-1,1] {
            wheel(name+"-\(side)",x,r,side,driver:driver)
            box(name+"-bearing-\(side)","support",x,r-0.08,side*0.78,0.30,0.30,0.48,dark)
        }
    }
    mutating func locomotive() {
        // New twin running-group chassis, with near-equal wheel diameters.
        box("centre-spine","frame",1.05,0.90,0,14.3,0.76,0.34,dark)
        for group: Float in [-2.0,4.35] {
            box("engine-frame-\(group)","frame",group,0.85,0,4.65,1.55,0.33,dark)
            for dx: Float in [-1.65,0,1.65] { axle("drive-\(group)-\(dx)",group+dx,0.72,driver:true) }
            for side: Float in [-1,1] {
                box("spring-rail-\(group)-\(side)","support",group,1.13,side*0.77,4.5,0.25,0.14,steel)
                for dx: Float in [-1.65,0,1.65] {
                    tube("crank-\(group)-\(side)-\(dx)","pin",Map3DPoint(group+dx+0.19,0.56,side*1.10),Map3DPoint(group+dx+0.19,0.56,side*1.36),0.075,steel,8)
                }
                tube("coupling-rod-\(group)-\(side)","rod",Map3DPoint(group-1.46,0.56,side*1.36),Map3DPoint(group+1.84,0.56,side*1.36),0.065,steel,6)
                tube("main-rod-\(group)-\(side)","rod",Map3DPoint(group+0.19,0.56,side*1.42),Map3DPoint(group+2.55,1.03,side*1.42),0.065,steel,6)
            }
        }
        // Supported cylinders at the front of EACH engine group; the heavy
        // front equipment replaces the first train's little leading-wheel area.
        for x: Float in [0.98,7.30] {
            box("cylinder-crossmember-\(x)","support",x,1.06,0,0.86,2.28,0.28,dark)
            for side: Float in [-1,1] {
                tube("cylinder-\(x)-\(side)","equipment",Map3DPoint(x-0.52,0.92,side*1.12),Map3DPoint(x+0.52,0.92,side*1.12),0.53,dark,12)
                tube("cylinder-end-\(x)-\(side)","equipment",Map3DPoint(x+0.51,0.92,side*1.12),Map3DPoint(x+0.56,0.92,side*1.12),0.44,steel,12)
                box("cylinder-top-\(x)-\(side)","support",x,1.30,side*1.12,1.02,0.72,0.22,dark)
                tube("crosshead-\(x)-\(side)","pin",Map3DPoint(x-0.42,1.03,side*0.92),Map3DPoint(x-0.42,1.03,side*1.44),0.09,steel,8)
                box("slide-guide-\(x)-\(side)","equipment",x-0.70,1.16,side*1.37,0.74,0.12,0.085,dark)
            }
        }
        // Barrel behind the cab; a compact front smoke chamber in front of it.
        tube("rear-boiler","boiler",Map3DPoint(-5.55,3.0,0),Map3DPoint(2.35,3.0,0),1.12,body,28)
        tube("cab-front-barrel","boiler",Map3DPoint(4.32,3.0,0),Map3DPoint(4.85,3.0,0),1.02,body,24)
        tube("front-smokebox","boiler",Map3DPoint(4.82,3.0,0),Map3DPoint(6.78,3.0,0),1.02,dark,28)
        for x: Float in [-4.6,-2.8,-0.8,1.5] { tube("barrel-band-\(x)","band",Map3DPoint(x-0.025,3,0),Map3DPoint(x+0.025,3,0),1.135,steel,28) }
        // Flared, broad rear firebox: an independent eight-corner section.
        let fireSection: [(Float,Float)]=[(1.49,-1.36),(1.65,-1.50),(3.67,-1.24),(4.0,-0.91),(4.0,0.91),(3.67,1.24),(1.65,1.50),(1.49,1.36)]
        sweep("wide-rear-firebox","body",[-6.15,-4.15].map { x in fireSection.map { Map3DPoint(x,$0.0,$0.1) } },body)
        box("rear-apron","body",-6.17,1.30,0,0.16,2.95,2.86,dark)
        box("rear-walkway","frame",-6.18,1.25,0,0.25,2.90,0.20,dark)
        for x: Float in [-4.45,-0.4,3.1,5.55] { box("boiler-saddle-\(x)","support",x,1.18,0,0.62,1.70,0.88,dark) }
        // Cab is forward of the long visible blue barrel, not at its rear.
        box("cab-wall","body",3.10,1.68,0,2.64,2.86,2.33,body)
        for side: Float in [-1,1] {
            box("running-board-\(side)","frame",0.1,1.58,side*1.31,12.5,0.37,0.12,dark)
            box("cab-glass-frame-\(side)","window-frame",3.10,2.85,side*1.438,2.31,0.018,1.02,dark)
            for i in -1...1 {
                box("cab-glass-\(side)-\(i)","glass",3.10+Float(i)*0.75,2.90,side*1.450,0.66,0.014,0.92,glass)
            }
            box("cab-blue-lower-\(side)","trim",3.10,1.93,side*1.438,2.58,0.014,0.19,cream)
            box("cab-gold-line-\(side)","trim",3.10,2.45,side*1.439,2.58,0.016,0.026,gold)
            box("front-cab-window-\(side)","glass",4.429,2.90,side*0.99,0.014,0.54,0.86,glass)
            // Distinct three/four pipe paths along the rear barrel.
            for i in 0..<(side>0 ? 3:4) {
                let h=2.32+Float(i)*0.18
                tube("pipe-\(side)-\(i)","pipe",Map3DPoint(-4.45,h,side*1.12),Map3DPoint(1.78,h,side*1.12),0.024,dark,6)
            }
            for x: Float in [-4.3,-1.2,1.4] {
                box("pipe-clamp-\(side)-\(x)","support",x,2.12,side*1.10,0.07,0.24,0.84,steel)
                tube("barrel-handrail-post-\(side)-\(x)","support",Map3DPoint(x,3.46,side*0.96),Map3DPoint(x,3.46,side*1.25),0.03,steel,6)
            }
            tube("barrel-handrail-\(side)","rail",Map3DPoint(-4.6,3.46,side*1.25),Map3DPoint(1.7,3.46,side*1.25),0.028,steel,6)
            // Two prominent longitudinal reservoirs on EACH firebox shoulder.
            for z: Float in [0.67,1.08] {
                for x: Float in [-5.32,-3.25] { box("reservoir-foot-\(side)-\(z)-\(x)","support",x,3.69,side*z,0.18,0.20,0.38,dark) }
                tube("upper-reservoir-\(side)-\(z)","equipment",Map3DPoint(-5.55,4.02,side*z),Map3DPoint(-3.05,4.02,side*z),0.155,dark,10)
            }
            // Cab and mid-engine access steps have real vertical carriers.
            for x: Float in [1.56,7.95] {
                for z: Float in [-0.20,0.20] { tube("step-carrier-\(x)-\(side)-\(z)","support",Map3DPoint(x+z,0.33,side*1.22),Map3DPoint(x+z,1.62,side*1.22),0.035,dark,6) }
                for i in 0..<4 { box("step-\(x)-\(side)-\(i)","equipment",x,0.37+Float(i)*0.33,side*1.28,0.46,0.30,0.07,steel) }
            }
        }
        // Closed strips form a gently arched cab roof without concave caps.
        let roof: [(Float,Float)]=[(4.0,-1.55),(4.28,-1.16),(4.39,-0.55),(4.42,0),(4.39,0.55),(4.28,1.16),(4.0,1.55)]
        for i in 0..<6 {
            let a=roof[i],b=roof[i+1],section=[a,b,(b.0-0.09,b.1),(a.0-0.09,a.1)]
            sweep("cab-roof-\(i)","roof",[Float(1.60),4.59].map { x in section.map { Map3DPoint(x,$0.0,$0.1) } },dark)
        }
        box("roof-hatch","equipment",3.1,4.40,0,0.82,0.75,0.075,cream)
        for (x,r) in [(Float(-1.1),Float(0.48)),(0.6,0.44)] {
            let rings=[(Float(4.0),r),(4.30,r),(4.42,r*0.66)].map { h,rad in (0..<12).map { i in let t=Float(i)*2*Float.pi/12;return Map3DPoint(x+cosf(t)*rad,h,sinf(t)*rad) } }
            sweep("boiler-dome-\(x)","equipment",rings,dark)
        }
        tube("safety-valve","equipment",Map3DPoint(-1.1,4.41,0),Map3DPoint(-1.1,4.68,0),0.075,gold,8)
        tube("chimney-foot","equipment",Map3DPoint(5.75,3.94,0),Map3DPoint(5.75,4.10,0),0.34,dark,12)
        tube("chimney","equipment",Map3DPoint(5.75,4.07,0),Map3DPoint(5.75,4.51,0),0.25,dark,12)
        tube("chimney-top","equipment",Map3DPoint(5.75,4.47,0),Map3DPoint(5.75,4.53,0),0.29,steel,12)
        tube("front-dome","equipment",Map3DPoint(4.85,3.94,0),Map3DPoint(4.85,4.22,0),0.34,dark,12)
        tube("smokebox-rim","equipment",Map3DPoint(6.76,3,0),Map3DPoint(6.85,3,0),1.04,steel,28)
        tube("smokebox-door","equipment",Map3DPoint(6.84,3,0),Map3DPoint(6.91,3,0),0.89,dark,24)
        tube("blank-centre-ring","equipment",Map3DPoint(6.91,2.97,0),Map3DPoint(6.94,2.97,0),0.30,gold,16)
        tube("blank-centre-face","equipment",Map3DPoint(6.94,2.97,0),Map3DPoint(6.96,2.97,0),0.255,dark,16)
        box("headlamp-mount","support",6.76,3.67,0,0.32,0.47,0.52,dark)
        box("headlamp-case","equipment",6.90,3.86,0,0.38,0.54,0.54,cream)
        tube("headlamp-lens","equipment",Map3DPoint(7.09,4.13,0),Map3DPoint(7.12,4.13,0),0.185,gold,12)
        for i in 0..<10 { let t=Float(i)*2*Float.pi/10
            tube("smokebox-bolt-\(i)","equipment",Map3DPoint(6.905,3+cosf(t)*0.80,sinf(t)*0.80),Map3DPoint(6.94,3+cosf(t)*0.80,sinf(t)*0.80),0.035,steel,6)
        }
        // Broad supported front deck, square railings, central coupling. No
        // first-train cowcatcher, sloping ladders or small leading wheels.
        box("front-platform","frame",7.48,1.50,0,2.06,2.90,0.16,dark)
        box("front-platform-support","support",8.18,1.04,0,0.68,1.14,0.50,dark)
        box("front-bufferbeam","frame",8.43,0.72,0,0.22,2.98,0.58,dark)
        box("front-platform-step","frame",8.54,0.54,0,0.46,1.45,0.12,steel)
        for z: Float in [-0.55,0.55] { tube("front-platform-step-hanger-\(z)","support",Map3DPoint(8.50,0.60,z),Map3DPoint(8.50,0.83,z),0.04,dark,6) }
        for side: Float in [-1,1] {
            for x: Float in [6.70,8.35] { tube("front-rail-post-\(side)-\(x)","support",Map3DPoint(x,1.66,side*1.33),Map3DPoint(x,2.48,side*1.33),0.035,steel,6) }
            tube("front-rail-side-\(side)","rail",Map3DPoint(6.70,2.48,side*1.33),Map3DPoint(8.35,2.48,side*1.33),0.035,steel,6)
        }
        tube("front-rail-top","rail",Map3DPoint(8.35,2.48,-1.33),Map3DPoint(8.35,2.48,1.33),0.035,steel,6)
        tube("front-rail-mid","rail",Map3DPoint(8.35,2.06,-1.33),Map3DPoint(8.35,2.06,1.33),0.025,steel,6)
        box("front-coupler","coupler",8.61,0.87,0,0.68,0.42,0.35,dark)
        box("rear-coupler","coupler",-6.225,0.85,0,0.35,0.32,0.24,dark)
    }
    mutating func tender() {
        // New lower water tank and notched raised bunker, not the first tender.
        box("tender-underframe","frame",0,1.02,0,8.90,2.84,0.20,dark)
        box("water-tank","body",0,1.22,0,8.90,3.0,1.92,dark)
        let profile: [(Float,Float)]=[(-4.45,3.10),(-4.45,3.28),(-3.42,3.28),(-2.88,3.82),(2.88,3.82),(3.42,3.28),(4.45,3.28),(4.45,3.10)]
        // One convex raised centre plus flat rear/front shoulders, closed strips.
        for side: Float in [-1,1] {
            for i in 0..<profile.count-1 {
                let a=profile[i],b=profile[i+1]
                if a.0==b.0 { continue }
                let section=[Map3DPoint(a.0,3.10,0),Map3DPoint(b.0,3.10,0),Map3DPoint(b.0,b.1,0),Map3DPoint(a.0,a.1,0)]
                if a.1==3.10 && b.1==3.10 { continue }
                // Small bottom overlap avoids a degenerate zero-height tip.
                let valid=section.map { Map3DPoint($0.x,$0.y==3.10 ? 3.08:$0.y,$0.z) }
                sweep("bunker-wall-\(side)-\(i)","body",[Float(1.32),1.50].map { z in valid.map { Map3DPoint($0.x,$0.y,side*z) } },body)
            }
            box("tender-blue-panel-\(side)","trim",0,1.44,side*1.506,8.55,0.014,1.51,body)
            box("tender-thin-line-\(side)","trim",0,2.98,side*1.507,8.55,0.016,0.023,gold)
        }
        box("bunker-front","body",3.35,3.08,0,0.16,2.74,0.28,body)
        box("bunker-rear","body",-3.35,3.08,0,0.16,2.74,0.28,body)
        let coalRings=[(Float(3.14),Float(1.0)),(3.66,0.90),(3.79,0.32)].map { h,s in [(Float(-3.25),Float(-1.27)),(3.25,-1.27),(3.25,1.27),(-3.25,1.27)].map { x,z in Map3DPoint(x*s,h,z*s) } }
        sweep("coal-mound","equipment",coalRings,dark)
        for x: Float in [-1.6,0,1.6] { for z: Float in [-0.52,0.52] {
            piece("coal-facet-\(x)-\(z)","equipment") { b in
                let c=Map3DPoint(x,3.66,z),p=[c+Map3DPoint(0,0.20,0),c-Map3DPoint(0,0.16,0),c+Map3DPoint(0.23,0,0),c+Map3DPoint(0,0,0.23),c-Map3DPoint(0.23,0,0),c-Map3DPoint(0,0,0.23)]
                for i in 0..<4 { let a=2+i,d=2+(i+1)%4;b.face([p[0],p[a],p[d]],inside:c,color:Map3DDuplexSteam.graphite);b.face([p[1],p[d],p[a]],inside:c,color:Map3DDuplexSteam.graphite) }
            }
        } }
        box("rear-water-hatch-base","support",-3.90,3.14,0,0.68,1.05,0.07,steel)
        box("rear-water-hatch","equipment",-3.90,3.21,0,0.60,0.95,0.06,cream)
        tube("hatch-handle","equipment",Map3DPoint(-3.90,3.28,-0.22),Map3DPoint(-3.90,3.28,0.22),0.027,dark,6)
        for bx: Float in [-2.60,2.60] {
            box("bogie-\(bx)","frame",bx,0.68,0,2.22,1.85,0.33,dark)
            box("bolster-\(bx)","support",bx,0.98,0,0.92,1.75,0.09,steel)
            for dx: Float in [-0.72,0.72] { axle("tender-axle-\(bx)-\(dx)",bx+dx,0.48,driver:false) }
            for side: Float in [-1,1] {
                box("bogie-side-\(bx)-\(side)","support",bx,0.53,side*0.90,2.20,0.28,0.31,dark)
                box("bogie-spring-\(bx)-\(side)","equipment",bx,0.83,side*0.90,0.62,0.30,0.11,steel)
            }
        }
        for x: Float in [-4.45,4.45] {
            box("tender-buffer-\(x)","frame",x,0.80,0,0.18,3.04,0.42,dark)
            box("tender-coupler-\(x)","coupler",x>0 ? 4.55:-4.63,0.85,0,0.30,0.34,0.24,dark)
            for side: Float in [-1,1] {
                box("tender-step-\(x)-\(side)","equipment",x,0.50,side*1.25,0.50,0.40,0.10,steel)
                tube("tender-step-hanger-\(x)-\(side)","support",Map3DPoint(x,0.5,side*1.25),Map3DPoint(x,1.15,side*1.25),0.04,dark,6)
            }
        }
        // Central rear ladder, rope-like grab and upper rear lamp are distinctive.
        for z: Float in [-0.25,0.25] { tube("rear-ladder-\(z)","support",Map3DPoint(-4.60,1.02,z),Map3DPoint(-4.60,3.23,z),0.032,steel,6)
            tube("rear-ladder-anchor-\(z)","support",Map3DPoint(-4.44,1.16,z),Map3DPoint(-4.60,1.16,z),0.04,steel,6)
        }
        for i in 0..<7 { tube("rear-rung-\(i)","equipment",Map3DPoint(-4.60,1.13+Float(i)*0.30,-0.25),Map3DPoint(-4.60,1.13+Float(i)*0.30,0.25),0.027,steel,6) }
        for side: Float in [-1,1] { tube("rear-grab-post-\(side)","support",Map3DPoint(-4.46,1.25,side*0.70),Map3DPoint(-4.46,2.55,side*0.70),0.03,steel,6) }
        tube("rear-grab","rail",Map3DPoint(-4.46,2.10,-0.70),Map3DPoint(-4.46,1.92,0),0.025,steel,6)
        tube("rear-grab-other","rail",Map3DPoint(-4.46,1.92,0),Map3DPoint(-4.46,2.10,0.70),0.025,steel,6)
        box("rear-lamp-base","support",-4.08,3.14,0,0.40,0.44,0.17,dark)
        box("rear-lamp-case","equipment",-4.10,3.31,0,0.42,0.48,0.50,cream)
        tube("rear-lamp-lens","equipment",Map3DPoint(-4.31,3.56,0),Map3DPoint(-4.34,3.56,0),0.16,gold,12)
    }
}
