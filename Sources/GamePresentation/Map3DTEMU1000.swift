import Foundation

/// Static TEMU1000 study. Geometry is authored x forward, y up, z right;
/// Model.flat converts it once to native x forward, y left, z up metres.
public enum Map3DTEMU1000 {
    public static let pitch: Float = 23.9
    public enum Unit: String, CaseIterable, Sendable { case leading, middle, pantograph, trailing }
    public static let shell = Map3DPalette.tileWhite
    public static let band = Map3DPalette.gymGreen
    public static let glass = Map3DTrainStyle.glass
    public static let passengerGlass = Map3DColor.rgb(0x405560)
    public static let ink = Map3DColor.shaded(Map3DPalette.playerRim, 0.75)

    public static func model(_ unit: Unit) -> Map3DModelPack.Model { model(unit, far: false) }

    /// `far`: decision 420's light version drawn from 500 m out, as
    /// ``Map3DE500/model(far:)`` is: fewer nose rings and cap rows, a
    /// coarser stripe, eight-sided wheels, one pane of glass along each
    /// side, and none of the small fittings.
    public static func model(_ unit: Unit, far: Bool) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.temu1000(unit, far: far)
        return .flat(named: "temu1000-\(unit.rawValue)" + (far ? "-far" : ""), from: builder.mesh)
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
    mutating func temu1000(_ unit: Map3DTEMU1000.Unit, far: Bool = false) {
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
        // The nose's rings front to back from the body, each with the
        // waist stripe's height there; decision 420's far version keeps six
        // of the ten (its rake, its shoulders and the bulge at the tip).
        let noseStations: [(x: Float, width: Float, top: Float, bottom: Float, bulge: Float, round: Float, stripe: Float, far: Bool)] = [
            (8.9, 1, 3.70, 0.83, 0, 0, 1.96, true), (9.85, 0.98, 3.56, 0.83, 0, 0, 1.94, false),
            (10.25, 0.97, 3.46, 0.82, 0, 0, 1.91, true), (10.75, 0.94, 3.26, 0.76, 0, 0, 1.87, false),
            (11.15, 0.94, 3.10, 0.71, 0, 0, 1.82, true), (11.55, 0.94, 2.80, 0.65, 0, 0, 1.75, false),
            (11.90, 0.93, 2.55, 0.64, 0.12, 0, 1.66, true), (12.18, 0.88, 2.31, 0.64, 0.25, 0, 1.57, true),
            (12.27, 0.87, 2.10, 0.66, 0.32, 0, 1.49, false), (12.36, 0.85, 1.82, 0.69, 0.42, 0.25, 1.44, true),
        ].filter { !far || $0.far }
        let noseRingsForward = noseStations.map { ring(nose*$0.x, width:$0.width, top:$0.top, bottom:$0.bottom, bulge:nose*$0.bulge, noseRound:$0.round) }
        var rings = [ring(-11.75),ring(11.75)]
        if nose > 0 {
            rings = [ring(-11.75)] + noseRingsForward
        } else if nose < 0 {
            rings = noseRingsForward.reversed() + [ring(11.75)]
        }
        for k in 0..<(rings.count-1) {
            for i in section.indices {
                let j = (i+1) % section.count
                // The supplied front and side references show a continuous
                // white shell over the cab and passenger roof. Keep grey on
                // supported HVAC housings, never as a patch on the nose.
                let c = white
                if nose != 0 && i < 7 {
                    // Opposite flanks use mirrored diagonals. Splitting the
                    // non-planar cab quads the same way on both sides made the
                    // pale front fascia appear offset in a head-on render.
                    face([rings[k][i],rings[k][j],rings[k+1][i]],inside:centre,color:c)
                    face([rings[k][j],rings[k+1][j],rings[k+1][i]],inside:centre,color:c)
                } else {
                    face([rings[k][i],rings[k][j],rings[k+1][j]],inside:centre,color:c)
                    face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:centre,color:c)
                }
            }
        }
        let capCentre = Map3DPoint(nose*12.70,1.25,0)
        let capSteps = far ? 3 : 7
        func noseCapRows(_ front: [Map3DPoint]) -> [[Map3DPoint]] {
            (0..<capSteps).map { row in
                let u = Float(row)/Float(capSteps)
                let eased = 1-(1-u)*(1-u)
                return front.map { p in
                    Map3DPoint(p.x+(capCentre.x-p.x)*eased+nose*0.025*sinf(Float.pi*u),
                               p.y+(capCentre.y-p.y)*u,p.z*(1-u))
                }
            }
        }
        if nose == 0 {
            face(rings[0],inside:centre,color:white)
            face(rings[rings.count-1],inside:centre,color:white)
        } else {
            let rear = nose > 0 ? rings[0] : rings[rings.count-1]
            let front = nose > 0 ? rings[rings.count-1] : rings[0]
            face(rear,inside:centre,color:white)
            // Several shallow concentric rows carry the face into its short
            // forward tip. A single centre fan made large flat triangles
            // across the nose in both the front and oblique close views.
            let capRows = noseCapRows(front)
            for row in 0..<(capSteps-1) {
                for i in front.indices {
                    let j = (i+1)%front.count
                    let a=capRows[row][i],b=capRows[row][j]
                    let c=capRows[row+1][j],d=capRows[row+1][i]
                    if i < 7 {
                        face([a,b,d],inside:centre,color:white)
                        face([b,c,d],inside:centre,color:white)
                    } else {
                        face([a,b,c],inside:centre,color:white)
                        face([a,c,d],inside:centre,color:white)
                    }
                }
            }
            for i in front.indices {
                face([capRows[capSteps-1][i],capRows[capSteps-1][(i+1)%front.count],capCentre],inside:centre,color:white)
            }
        }
        // Lower frame, two bogies and eight visible wheel discs; tyre bottoms z=0.
        box(0,0.75,0,22.7,2.20,0.19,ink)
        for bogie: Float in [-8.28,8.28] {
            box(bogie,0.49,0,3.35,2.20,0.22,ink)
            for axle: Float in [-1.03,1.03] {
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(bogie+axle,0.33,side*1.11),
                              Map3DPoint(bogie+axle,0.33,side*1.28),radius:0.33,color:ink,sides:far ? 8 : 12)
                    if !far {
                        civicTube(Map3DPoint(bogie+axle,0.33,side*1.28),
                                  Map3DPoint(bogie+axle,0.33,side*1.30),radius:0.14,color:metal,sides:10)
                    }
                }
            }
            if !far { for side: Float in [-1,1] { box(bogie,0.52,side*1.30,2.70,0.04,0.15,ink) } }
        }
        for x: Float in [-4.9,-1.8,1.8,4.9] { box(x,0.57,0,2.10,2.08,0.36,metal) }
        // The reference has discrete passenger windows in a dark surround.
        // Contrasting thin glazed panes sit on a solid body-backed band; doors cut it at
        // the positions visible on the supplied TED/TEM/TEP side drawing.
        for side: Float in [-1,1] {
            let doors: [Float] = nose == 0 ? [-10.25,10.25]
                : nose > 0 ? [-10.25,4.55] : [-4.55,10.25]
            box(-nose*1.10,2.12,side*1.454,nose == 0 ? 20.95 : 18.75,0.012,0.68,ink)
            if far {
                // One pane along the side, the doors over it.
                box(-nose*1.10,2.18,side*1.464,nose == 0 ? 20.0 : 17.6,0.006,0.56,Map3DTEMU1000.passengerGlass)
            }
            for x: Float in stride(from:-9.20,through:9.20,by:1.62) where !far {
                if nose != 0 && x*nose > 7.4 { continue }
                if doors.contains(where: { abs(x-$0) < 0.95 }) { continue }
                box(x,2.18,side*1.464,1.51,0.006,0.56,Map3DTEMU1000.passengerGlass)
            }
            for x in doors {
                // The narrow body-colour leaf has a shallow window and a
                // hairline edge; it does not project as an external box.
                box(x,0.89,side*1.467,0.87,0.012,2.22,white)
                if far { continue }
                box(x,2.18,side*1.477,0.64,0.006,0.56,Map3DTEMU1000.passengerGlass)
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
            let stripeHeights: [Float] = [1.96] + noseStations.map(\.stripe)
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
                    let steps = far ? 2 : 6, rows = far ? 1 : 2
                    for step in 0..<steps {
                        let t0=Float(step)/Float(steps),t1=Float(step+1)/Float(steps)
                        for row in 0..<rows {
                            let v0=Float(row)/Float(rows),v1=Float(row+1)/Float(rows)
                            face([sample(t0,v0),sample(t0,v1),sample(t1,v1),sample(t1,v0)],
                                 inside:centre,color:green)
                        }
                    }
                }
            }
            // Interpolate on the exact curved cap facets for the crossing stripe.
            let cap = nose > 0 ? rings[rings.count-1] : rings[0]
            let capRows = noseCapRows(cap)
            var capFacets: [[Map3DPoint]] = []
            for row in 0..<(capSteps-1) {
                for i in cap.indices {
                    let j = (i+1)%cap.count
                    let a=capRows[row][i],b=capRows[row][j]
                    let c=capRows[row+1][j],d=capRows[row+1][i]
                    if i < 7 {
                        capFacets.append([a,b,d])
                        capFacets.append([b,c,d])
                    } else {
                        capFacets.append([a,b,c])
                        capFacets.append([a,c,d])
                    }
                }
            }
            for i in cap.indices {
                capFacets.append([capRows[capSteps-1][i],capRows[capSteps-1][(i+1)%cap.count],capCentre])
            }
            func capSurface(_ y: Float,_ z: Float) -> Map3DPoint {
                for triangle in capFacets {
                    let a = triangle[0],b = triangle[1],c = triangle[2]
                    let by = b.y-a.y,bz = b.z-a.z
                    let cy = c.y-a.y,cz = c.z-a.z
                    let det = by*cz-bz*cy
                    if abs(det)<0.00001 { continue }
                    let py = y-a.y,pz = z-a.z
                    let u = (py*cz-pz*cy)/det,v = (by*pz-bz*py)/det
                    if u >= -0.0001 && v >= -0.0001 && u+v <= 1.0001 {
                        return Map3DPoint(a.x*(1-u-v)+b.x*u+c.x*v+nose*0.035,y,z)
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
            let pieces = far ? 8 : 24
            for i in 0..<pieces {
                let t0 = -1 + Float(i)*2/Float(pieces), t1 = -1 + Float(i+1)*2/Float(pieces)
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
            // Project the screen and lamps onto the actual shell facets.
            // Their former flat X planes made them hover over the cab rake.
            func cabSurface(_ y: Float, _ z: Float) -> Float {
                var forward = -Float.infinity
                func consider(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint) {
                    let by=b.y-a.y,bz=b.z-a.z,cy=c.y-a.y,cz=c.z-a.z
                    let det=by*cz-bz*cy
                    if abs(det)<0.00001 { return }
                    let py=y-a.y,pz=z-a.z
                    let u=(py*cz-pz*cy)/det,v=(by*pz-bz*py)/det
                    if u >= -0.0001 && v >= -0.0001 && u+v <= 1.0001 {
                        forward=max(forward,nose*(a.x*(1-u-v)+b.x*u+c.x*v))
                    }
                }
                for k in 0..<(rings.count-1) {
                    for i in section.indices {
                        let j=(i+1)%section.count
                        if i < 7 {
                            consider(rings[k][i],rings[k][j],rings[k+1][i])
                            consider(rings[k][j],rings[k+1][j],rings[k+1][i])
                        } else {
                            consider(rings[k][i],rings[k][j],rings[k+1][j])
                            consider(rings[k][i],rings[k+1][j],rings[k+1][i])
                        }
                    }
                }
                precondition(forward.isFinite,"TEMU1000 cab fitting missed the shell at \(y), \(z)")
                return forward
            }
            func cabPoint(_ y: Float, _ z: Float, offset: Float = 0) -> Map3DPoint {
                Map3DPoint(nose*(cabSurface(y,z)+offset),y,z)
            }
            // The reference screen is taller and reaches much closer to the
            // roof. Rounded bands keep its corners narrow without a thick rim.
            let screenBands: [(height:Float,halfWidth:Float)] = [
                (2.40,0.88),(2.44,1.00),(2.55,1.11),
                (3.29,1.11),(3.44,1.00),(3.52,0.86)
            ]
            let screenOutline = screenBands.map { ($0.height,-$0.halfWidth) }
                              + screenBands.reversed().map { ($0.height,$0.halfWidth) }
            func clipScreen(_ triangle: [Map3DPoint]) -> [Map3DPoint] {
                var polygon=triangle
                for edge in screenOutline.indices {
                    let a=screenOutline[edge],b=screenOutline[(edge+1)%screenOutline.count]
                    func signed(_ p: Map3DPoint) -> Float {
                        (b.0-a.0)*(p.z-a.1)-(b.1-a.1)*(p.y-a.0)
                    }
                    var next: [Map3DPoint]=[]
                    if polygon.isEmpty { return [] }
                    for i in polygon.indices {
                        let p=polygon[i],q=polygon[(i+1)%polygon.count]
                        let dp=signed(p),dq=signed(q)
                        if dp >= -0.00001 { next.append(p) }
                        if (dp < -0.00001 && dq > 0.00001) ||
                           (dp > 0.00001 && dq < -0.00001) {
                            let t=dp/(dp-dq)
                            next.append(p+(q-p)*t)
                        }
                    }
                    polygon=next
                }
                // Clipping across a shared shell edge can emit the same
                // vertex twice. Remove it before native facet triangulation.
                var clean: [Map3DPoint]=[]
                for p in polygon {
                    if let q=clean.last,
                       abs(p.x-q.x)+abs(p.y-q.y)+abs(p.z-q.z)<0.0001 { continue }
                    clean.append(p)
                }
                if clean.count>1 {
                    let p=clean[0],q=clean[clean.count-1]
                    if abs(p.x-q.x)+abs(p.y-q.y)+abs(p.z-q.z)<0.0001 { clean.removeLast() }
                }
                return clean.count>=3 ? clean : []
            }
            // Clip each actual shell triangle to the rounded screen outline.
            // This keeps glazing flush on the nose rake, without white gaps
            // from a second grid spanning across the original cab facets.
            for k in 0..<(rings.count-1) where nose*rings[k][0].x > 8.8 && nose*rings[k+1][0].x > 8.8 {
                for i in section.indices {
                    let j=(i+1)%section.count
                    let a=rings[k][i],b=rings[k][j],c=rings[k+1][j],d=rings[k+1][i]
                    let triangles = i < 7 ? [[a,b,d],[b,c,d]] : [[a,b,c],[a,c,d]]
                    for triangle in triangles {
                        let cut=clipScreen(triangle)
                        if !cut.isEmpty {
                            face(cut.map { Map3DPoint($0.x+nose*0.014,$0.y,$0.z) },
                                 inside:centre,color:glass)
                        }
                    }
                }
            }
            if !far {
                // The supplied cab photos show two slim blades rising from
                // the lower glass toward the outer corners.
                for side: Float in [-1,1] {
                    let pivot=cabPoint(2.46,side*0.25,offset:0.081)
                    let joint=cabPoint(2.73,side*0.75,offset:0.081)
                    let tip=cabPoint(2.86,side*0.99,offset:0.081)
                    civicTube(pivot,joint,radius:0.012,color:ink,sides:6)
                    civicTube(joint,tip,radius:0.010,color:ink,sides:6)
                }
            }
            // Real front views resolve two lamps inside one central housing;
            // the glare in the drawing blends them together. Its rear half
            // is buried in the roof and the lower front touches the screen.
            let lampRear = [Map3DPoint(nose*9.96,3.43,-0.17),
                            Map3DPoint(nose*9.96,3.56,-0.17),
                            Map3DPoint(nose*9.96,3.62,-0.11),
                            Map3DPoint(nose*9.96,3.62,0.11),
                            Map3DPoint(nose*9.96,3.56,0.17),
                            Map3DPoint(nose*9.96,3.43,0.17)]
            let lampFront = [Map3DPoint(nose*10.77,3.45,-0.17),
                             Map3DPoint(nose*10.77,3.56,-0.17),
                             Map3DPoint(nose*10.77,3.63,-0.11),
                             Map3DPoint(nose*10.77,3.63,0.11),
                             Map3DPoint(nose*10.77,3.56,0.17),
                             Map3DPoint(nose*10.77,3.45,0.17)]
            face(lampRear,inside:centre,color:ink)
            face(lampFront,inside:centre,color:ink)
            for i in lampFront.indices {
                let j = (i+1)%lampFront.count
                face([lampRear[i],lampRear[j],lampFront[j],lampFront[i]],inside:centre,color:ink)
            }
            for side: Float in [-1,1] {
                let first=mesh.vertices.count
                civicTube(Map3DPoint(nose*10.775,3.53,side*0.075),
                          Map3DPoint(nose*10.80,3.53,side*0.075),
                          radius:0.050,color:Map3DStreetModel.headlamp,sides:far ? 8 : 12)
                mesh.makeGlowing(from:first)
            }
            // The photos show tilted smoked housings with shallow horizontal
            // louvers; the frontal drawing's pale spots are lamp glare.
            for side: Float in [-1,1] {
                let around = far ? 8 : 16
                func oval(_ yr: Float, _ zr: Float, _ offset: Float) -> [Map3DPoint] {
                    (0..<around).map { i in
                        let a=2*Float.pi*Float(i)/Float(around)
                        let y=2.18+yr*sinf(a)+side*0.10*cosf(a)
                        let z=side*0.80+zr*cosf(a)
                        return cabPoint(y,z,offset:offset)
                    }
                }
                let back = oval(0.15,0.27,-0.014)
                let rim = oval(0.15,0.27,0.060)
                let middle=cabPoint(2.18,side*0.80,offset:0.060)
                for i in 0..<around {
                    face([middle,rim[i],rim[(i+1)%around]],inside:centre,color:ink)
                }
                for i in 0..<around {
                    let j = (i+1)%around
                    face([back[i],back[j],rim[j],rim[i]],inside:centre,color:ink)
                }
                let lens=oval(0.115,0.225,0.068)
                let lensMiddle=cabPoint(2.18,side*0.80,offset:0.068)
                for i in 0..<around {
                    face([lensMiddle,lens[i],lens[(i+1)%around]],
                         inside:centre,color:Map3DTEMU1000.passengerGlass)
                }
                for height: Float in [-0.055,0,0.055] {
                    func slat(_ across: Float, _ high: Float) -> Map3DPoint {
                        let z=side*0.80+across
                        return cabPoint(2.18+height+side*0.10*across/0.225+high,
                                        z,offset:0.081)
                    }
                    face([slat(-0.14,-0.009),slat(0.14,-0.009),
                          slat(0.14,0.009),slat(-0.14,0.009)],
                         inside:centre,color:metal)
                }
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
            if !far { box(x,3.89,0,2.30,1.30,0.09,roof) }
        }
        if unit == .pantograph {
            box(7.05,3.78,0,3.0,1.70,0.15,ink)
            for side: Float in [-1,1] {
                civicTube(Map3DPoint(6.10,3.85,side*0.58),Map3DPoint(7.05,4.46,side*0.40),radius:0.04,color:metal,sides:far ? 4 : 6)
                civicTube(Map3DPoint(7.05,4.46,side*0.40),Map3DPoint(8.00,3.85,side*0.58),radius:0.04,color:metal,sides:far ? 4 : 6)
            }
            box(7.05,4.49,0,1.90,1.02,0.07,ink)
        }
    }
}
