import Foundation

/// Static TEMU1000 study. Geometry is authored x forward, y up, z right;
/// Model.flat converts it once to native x forward, y left, z up metres.
public enum Map3DTEMU1000 {
    public static let pitch: Float = 23.9
    public enum Unit: String, CaseIterable, Sendable { case leading, middle, pantograph, trailing }
    public static let shell = Map3DPalette.tileWhite
    public static let band = Map3DPalette.gymGreen
    public static let glass = Map3DTrainStyle.glass
    public static let ink = Map3DColor.shaded(Map3DPalette.playerRim, 0.75)

    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.temu1000(unit)
        return .flat(named: "temu1000-\(unit.rawValue)", from: builder.mesh)
    }

    public static let order: [Unit] = [.trailing, .middle, .pantograph, .middle,
                                       .middle, .pantograph, .middle, .leading]
    public static func formation() -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        for (i, unit) in order.enumerated() {
            builder.add(model(unit), at: Map3DPoint((Float(i) - 3.5) * pitch, 0, 0))
        }
        return .flat(named: "temu1000-formation", from: builder.mesh)
    }
}

extension StationKitBuilder {
    mutating func temu1000(_ unit: Map3DTEMU1000.Unit) {
        let white = Map3DTEMU1000.shell, green = Map3DTEMU1000.band
        let glass = Map3DTEMU1000.glass, ink = Map3DTEMU1000.ink
        let roof = Map3DPalette.roof, metal = Self.steel
        let nose: Float = unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let centre = Map3DPoint(0, 2, 0)
        // A rounded, full-shouldered section. Nose stations separately control
        // upper rake and lateral taper so the front is not a single wedge.
        let section: [(Float, Float)] = [
            (0.83,-1.23),(0.91,-1.41),(1.51,-1.45),(2.54,-1.45),
            (3.07,-1.42),(3.43,-1.23),(3.63,-0.90),(3.70,-0.40),
            (3.70,0.40),(3.63,0.90),(3.43,1.23),(3.07,1.42),
            (2.54,1.45),(1.51,1.45),(0.91,1.41),(0.83,1.23)
        ]
        func ring(_ x: Float, width: Float = 1, top: Float = 3.70, bottom: Float = 0.83, bulge: Float = 0, noseRound: Float = 0) -> [Map3DPoint] {
            section.map { h, side in
                let t = (h - 0.83) / 2.87
                let shoulder = max(0, 1 - (side / 1.45) * (side / 1.45))
                let oval = 1 - noseRound * (1 - sinf(Float.pi * t))
                let forward = bulge * 4 * t * (1-t) * (0.55 + 0.45 * shoulder)
                return Map3DPoint(x + forward, bottom + t * (top-bottom), side * width * oval)
            }
        }
        var rings = [ring(-11.75),ring(11.75)]
        if nose > 0 {
            rings = [ring(-11.75),ring(8.9),ring(9.85,width:0.98,top:3.56),
                     ring(10.25,width:0.97,top:3.46,bottom:0.82),
                     ring(10.75,width:0.94,top:3.26,bottom:0.76),
                     ring(11.15,width:0.94,top:3.10,bottom:0.71),
                     ring(11.55,width:0.94,top:2.80,bottom:0.65),
                     ring(11.90,width:0.93,top:2.55,bottom:0.64,bulge:0.12),
                     ring(12.18,width:0.88,top:2.31,bottom:0.64,bulge:0.25),
                     ring(12.27,width:0.87,top:2.10,bottom:0.66,bulge:0.32),
                     ring(12.36,width:0.85,top:1.82,bottom:0.69,bulge:0.42,noseRound:0.25)]
        } else if nose < 0 {
            rings = [ring(-12.36,width:0.85,top:1.82,bottom:0.69,bulge:-0.42,noseRound:0.25),
                     ring(-12.27,width:0.87,top:2.10,bottom:0.66,bulge:-0.32),
                     ring(-12.18,width:0.88,top:2.31,bottom:0.64,bulge:-0.25),
                     ring(-11.90,width:0.93,top:2.55,bottom:0.64,bulge:-0.12),
                     ring(-11.55,width:0.94,top:2.80,bottom:0.65),
                     ring(-11.15,width:0.94,top:3.10,bottom:0.71),
                     ring(-10.75,width:0.94,top:3.26,bottom:0.76),
                     ring(-10.25,width:0.97,top:3.46,bottom:0.82),
                     ring(-9.85,width:0.98,top:3.56),ring(-8.9),ring(11.75)]
        }
        for k in 0..<(rings.count-1) {
            for i in section.indices {
                let j = (i+1) % section.count
                let c: UInt32
                if (i == 2 || i == 12) { c = white }
                else if i == 3 || i == 11 { c = white }
                else if i >= 6 && i <= 9 { c = roof }
                else { c = white }
                face([rings[k][i],rings[k][j],rings[k+1][j]],inside:centre,color:c)
                face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:centre,color:c)
            }
        }
        let capCentre = Map3DPoint(nose*12.70,1.25,0)
        if nose == 0 {
            face(rings[0],inside:centre,color:white)
            face(rings[rings.count-1],inside:centre,color:white)
        } else {
            let rear = nose > 0 ? rings[0] : rings[rings.count-1]
            let front = nose > 0 ? rings[rings.count-1] : rings[0]
            face(rear,inside:centre,color:white)
            for i in front.indices {
                face([capCentre,front[i],front[(i+1)%front.count]],inside:centre,color:white)
            }
        }
        // Lower frame, two bogies and eight visible wheel discs; tyre bottoms z=0.
        box(0,0.75,0,22.7,2.20,0.19,ink)
        for bogie: Float in [-8.28,8.28] {
            box(bogie,0.49,0,3.35,2.20,0.22,ink)
            for axle: Float in [-1.03,1.03] {
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(bogie+axle,0.39,side*1.11),
                              Map3DPoint(bogie+axle,0.39,side*1.28),radius:0.39,color:ink,sides:12)
                    civicTube(Map3DPoint(bogie+axle,0.39,side*1.28),
                              Map3DPoint(bogie+axle,0.39,side*1.30),radius:0.18,color:metal,sides:10)
                }
            }
            for side: Float in [-1,1] { box(bogie,0.52,side*1.30,2.70,0.04,0.15,ink) }
        }
        for x: Float in [-4.9,-1.8,1.8,4.9] { box(x,0.57,0,2.10,2.08,0.36,metal) }
        // The reference reads as one nearly unbroken dark window ribbon.
        // Thin glazed panes sit on a solid body-backed band; doors cut it at
        // the positions visible on the supplied TED/TEM/TEP side drawing.
        for side: Float in [-1,1] {
            let doors: [Float] = nose == 0 ? [-10.25,10.25]
                : nose > 0 ? [-10.25,4.55] : [-4.55,10.25]
            box(-nose*1.10,2.12,side*1.454,nose == 0 ? 20.95 : 18.75,0.012,0.68,ink)
            for x: Float in stride(from:-9.20,through:9.20,by:1.62) {
                if nose != 0 && x*nose > 7.4 { continue }
                if doors.contains(where: { abs(x-$0) < 0.95 }) { continue }
                box(x,2.18,side*1.464,1.51,0.006,0.56,glass)
            }
            for x in doors {
                // The narrow body-colour leaf has a shallow window and a
                // hairline edge; it does not project as an external box.
                box(x,0.89,side*1.467,0.87,0.012,2.22,white)
                box(x,2.18,side*1.477,0.64,0.006,0.56,glass)
                box(x+0.39,0.90,side*1.475,0.012,0.008,2.18,ink)
            }
            box(-nose*1.10,1.96,side*1.453,
                nose == 0 ? 19.7 : 17.8,0.012,0.065,green)
        }
        if nose != 0 {
            // Follow the curved nose with the same narrow, non-red waist
            // stripe. Sample the actual shell rings instead of placing a
            // separate planar ribbon beside the curved surface.
            let noseRings = nose > 0 ? Array(rings.dropFirst()) : Array(rings.dropLast().reversed())
            let stripeRings = [ring(nose*7.65)] + noseRings
            let stripeHeights: [Float] = [1.96,1.96,1.94,1.91,1.87,1.82,
                                          1.75,1.66,1.57,1.49,1.44]
            func sideStripePoint(_ cross: [Map3DPoint],_ side: Float,_ height: Float) -> Map3DPoint {
                let range = side > 0 ? 8..<15 : 0..<7
                for i in range {
                    let a = cross[i], b = cross[i+1]
                    if (a.y-height)*(b.y-height) <= 0 && abs(a.y-b.y) > 0.00001 {
                        let t = (height-a.y)/(b.y-a.y)
                        let forward = min(1,max(0,(abs(cross[0].x)-7.65)/4.71))*0.030
                        return Map3DPoint(a.x+t*(b.x-a.x)+nose*forward,height,
                                          a.z+t*(b.z-a.z)+side*(0.010+forward*0.5))
                    }
                }
                preconditionFailure("TEMU1000 side stripe missed the body at \(height)")
            }
            func sideSurface(_ x: Float,_ y: Float,_ side: Float,_ forward: Float) -> Map3DPoint {
                var outer: Float = -Float.infinity
                func consider(_ a: Map3DPoint,_ b: Map3DPoint,_ c: Map3DPoint) {
                    // Project both painted flanks through the same positive
                    // cross section; the shell's opposite diagonal must not
                    // introduce a visible left/right paint drift.
                    if a.z < 0 || b.z < 0 || c.z < 0 { return }
                    let bx=b.x-a.x,by=b.y-a.y,cx=c.x-a.x,cy=c.y-a.y
                    let det=bx*cy-by*cx
                    if abs(det)<0.00001 { return }
                    let px=x-a.x,py=y-a.y
                    let u=(px*cy-py*cx)/det,v=(bx*py-by*px)/det
                    if u >= -0.0001 && v >= -0.0001 && u+v <= 1.0001 {
                        outer=max(outer,a.z*(1-u-v)+b.z*u+c.z*v)
                    }
                }
                for k in 0..<(rings.count-1) {
                    for i in section.indices {
                        let j=(i+1)%section.count
                        consider(rings[k][i],rings[k][j],rings[k+1][j])
                        consider(rings[k][i],rings[k+1][j],rings[k+1][i])
                    }
                }
                precondition(outer.isFinite,"TEMU1000 stripe missed the shell")
                return Map3DPoint(x+nose*forward,y,side*(outer+0.010+forward*0.5))
            }
            for side: Float in [-1,1] {
                for i in 0..<(stripeRings.count-1) {
                    let a = stripeRings[i], b = stripeRings[i+1]
                    let boostA=min(1,max(0,(abs(a[0].x)-7.65)/4.71))*0.030
                    let boostB=min(1,max(0,(abs(b[0].x)-7.65)/4.71))*0.030
                    func sample(_ along: Float,_ across: Float) -> Map3DPoint {
                        let y=(stripeHeights[i]+(stripeHeights[i+1]-stripeHeights[i])*along) + (across-0.5)*0.070
                        let pa=sideStripePoint(a,side,stripeHeights[i]+(across-0.5)*0.070)
                        let pb=sideStripePoint(b,side,stripeHeights[i+1]+(across-0.5)*0.070)
                        let boost=boostA+(boostB-boostA)*along
                        let x=pa.x+(pb.x-pa.x)*along-nose*boost
                        return sideSurface(x,y,side,boost)
                    }
                    for step in 0..<6 {
                        let t0=Float(step)/6,t1=Float(step+1)/6
                        for row in 0..<2 {
                            let v0=Float(row)/2,v1=Float(row+1)/2
                            face([sample(t0,v0),sample(t0,v1),sample(t1,v1),sample(t1,v0)],
                                 inside:centre,color:green)
                        }
                    }
                }
            }
            // The white nose is a triangular fan about a forward centre.
            // Interpolate on those same real facets for the crossing stripe.
            let cap = nose > 0 ? rings[rings.count-1] : rings[0]
            func capSurface(_ y: Float,_ z: Float) -> Map3DPoint {
                for i in cap.indices {
                    let b = cap[i],c = cap[(i+1)%cap.count]
                    let by = b.y-capCentre.y,bz = b.z-capCentre.z
                    let cy = c.y-capCentre.y,cz = c.z-capCentre.z
                    let det = by*cz-bz*cy
                    if abs(det)<0.00001 { continue }
                    let py = y-capCentre.y,pz = z-capCentre.z
                    let u = (py*cz-pz*cy)/det,v = (by*pz-bz*py)/det
                    if u >= -0.0001 && v >= -0.0001 && u+v <= 1.0001 {
                        return Map3DPoint(capCentre.x*(1-u-v)+b.x*u+c.x*v+nose*0.035,y,z)
                    }
                }
                preconditionFailure("front stripe left the TEMU1000 nose surface at \(y), \(z)")
            }
            let lastRing = stripeRings[stripeRings.count-1]
            let lowEnd = sideStripePoint(lastRing,1,1.405)
            let highEnd = sideStripePoint(lastRing,1,1.475)
            func frontStripePoint(_ t: Float,_ high: Bool) -> Map3DPoint {
                if t <= -1 { return sideStripePoint(lastRing,-1,high ? 1.475 : 1.405) }
                if t >= 1 { return high ? highEnd : lowEnd }
                let lowY: Float = 0.98 + 0.425*t*t
                let y = lowY + (high ? 0.07 : 0)
                let z = t * abs(high ? highEnd.z : lowEnd.z)
                return capSurface(y,z)
            }
            for i in 0..<24 {
                let t0 = -1 + Float(i)*2/24, t1 = -1 + Float(i+1)*2/24
                face([frontStripePoint(t0,false),frontStripePoint(t0,true),
                      frontStripePoint(t1,true),frontStripePoint(t1,false)],inside:centre,color:green)
            }
            // Cab side glass narrows into the lowered windshield rake.
            for side: Float in [-1,1] {
                let cab = [Map3DPoint(nose*8.48,2.63,side*1.465),
                           Map3DPoint(nose*9.77,2.63,side*1.437),
                           Map3DPoint(nose*10.38,2.15,side*1.395),
                           Map3DPoint(nose*8.48,2.15,side*1.465)]
                face(cab,inside:centre,color:ink)
                let cabPane = cab.map { Map3DPoint($0.x,$0.y-0.025,$0.z+side*0.012) }
                face(cabPane,inside:centre,color:glass)
            }
            // The cab screen follows the rake and bends across the width.
            // Chamfered corners and a short closed rim keep the glazing part
            // of the nose instead of a flat panel hovering over the shell.
            func screenPoint(_ y: Float, _ z: Float, offset: Float = 0) -> Map3DPoint {
                let t = (3.20-y)/0.93
                let transverse = 0.24 * max(0,1-(z/1.15)*(z/1.15))
                return Map3DPoint(nose*(10.94+1.25*t+transverse+offset),y,z)
            }
            let outline: [(Float,Float)] = [(3.16,-1.00),(3.19,-0.88),(3.19,0.88),
                                            (3.16,1.00),(3.05,1.08),(2.48,1.08),
                                            (2.34,0.98),(2.31,0),(2.34,-0.98),
                                            (2.48,-1.08),(3.05,-1.08)]
            let frame = outline.map { screenPoint($0.0,$0.1,offset:0.025) }
            let backing = outline.map { screenPoint($0.0,$0.1,offset:-0.035) }
            face(frame,inside:centre,color:ink)
            face(backing,inside:centre,color:ink)
            for i in outline.indices {
                let j = (i+1)%outline.count
                face([frame[i],frame[j],backing[j],backing[i]],inside:centre,color:ink)
            }
            let pane = outline.map { y,z in screenPoint(2.74+(y-2.74)*0.91,z*0.94,offset:0.030) }
            face(pane,inside:centre,color:glass)
            // The twin upper marker lamps share one roof-backed, closed pod.
            // Its rear edge intersects the solid roof, while its lower front
            // edge overlaps the screen rim rather than hovering above it.
            let lampRear = [Map3DPoint(nose*10.70,3.12,-0.30),
                            Map3DPoint(nose*10.70,3.23,-0.30),
                            Map3DPoint(nose*10.70,3.27,-0.24),
                            Map3DPoint(nose*10.70,3.27,0.24),
                            Map3DPoint(nose*10.70,3.23,0.30),
                            Map3DPoint(nose*10.70,3.12,0.30)]
            let lampFront = [Map3DPoint(nose*11.34,3.10,-0.30),
                             Map3DPoint(nose*11.34,3.36,-0.30),
                             Map3DPoint(nose*11.34,3.41,-0.24),
                             Map3DPoint(nose*11.34,3.41,0.24),
                             Map3DPoint(nose*11.34,3.36,0.30),
                             Map3DPoint(nose*11.34,3.10,0.30)]
            face(lampRear,inside:centre,color:ink)
            face(lampFront,inside:centre,color:ink)
            for i in lampFront.indices {
                let j = (i+1)%lampFront.count
                face([lampRear[i],lampRear[j],lampFront[j],lampFront[i]],inside:centre,color:ink)
            }
            for side: Float in [-1,1] {
                civicTube(Map3DPoint(nose*11.345,3.27,side*0.135),
                          Map3DPoint(nose*11.37,3.27,side*0.135),
                          radius:0.073,color:Map3DStreetModel.headlamp,sides:12)
            }
            // Oval lamp pods have a shallow closed backing sunk into the
            // white nose. Their lenses sit above the wraparound stripe.
            for side: Float in [-1,1] {
                func oval(_ x: Float, _ yr: Float, _ zr: Float) -> [Map3DPoint] {
                    (0..<12).map { i in
                        let a = 2 * Float.pi * Float(i) / 12
                        return Map3DPoint(x, 2.09 + yr*sinf(a)
                                               + side*0.04*cosf(a), side*0.79 + zr*cosf(a))
                    }
                }
                let back = oval(nose*12.34,0.11,0.21)
                let rim = oval(nose*12.42,0.11,0.21)
                face(back,inside:centre,color:ink)
                face(rim,inside:centre,color:ink)
                for i in 0..<12 {
                    let j = (i+1)%12
                    face([back[i],back[j],rim[j],rim[i]],inside:centre,color:ink)
                }
                face(oval(nose*12.43,0.065,0.15),inside:centre,color:Map3DPalette.tileWhite)
            }
            box(nose*12.10,0.48,0,0.20,0.34,0.17,ink)
        } else {
            // Both ends of a middle unit are gangways, never a driving face.
            for x: Float in [-11.78,11.78] {
                box(x,0.81,0,0.09,1.80,2.50,ink)
                box(x,0.84,0,0.10,1.42,2.16,metal)
            }
        }
        // HVAC housings are visible in all types; only TEP has a pantograph.
        for x: Float in [-5.6,4.3] {
            box(x,3.78,0,3.05,1.62,0.18,metal)
            box(x,3.89,0,2.30,1.30,0.09,roof)
        }
        if unit == .pantograph {
            box(7.05,3.78,0,3.0,1.70,0.15,ink)
            for side: Float in [-1,1] {
                civicTube(Map3DPoint(6.10,3.85,side*0.58),Map3DPoint(7.05,4.46,side*0.40),radius:0.04,color:metal,sides:6)
                civicTube(Map3DPoint(7.05,4.46,side*0.40),Map3DPoint(8.00,3.85,side*0.58),radius:0.04,color:metal,sides:6)
            }
            box(7.05,4.49,0,1.90,1.02,0.07,ink)
        }
    }
}
