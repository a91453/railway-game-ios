import Foundation

/// TEMU2000 static native study. Builder axes: X forward, Y up, Z right;
/// Model.flat converts once to X forward, Y left, Z up in metres.
public enum Map3DTEMU2000 {
    public enum Unit: String, CaseIterable, Sendable {
        case leading, tema, tep, temb, trailing
    }
    public static let bodyWidth: Float = 2.900
    public static let leadingOverallLength: Float = 22.095
    public static let intermediateOverallLength: Float = 20.700
    public static let formationLength: Float = 168.390
    public static let white = Map3DPalette.tileWhite
    public static let teal = Map3DColor.rgb(0x12A08F)
    public static let navy = Map3DColor.rgb(0x262C57)
    // The studies-only TRA production palette. The operating set retains its
    // exact previous vertex payload until a separate integration change.
    public static let studyRed = Map3DColor.rgb(0xD92E48)
    public static let studyDark = Map3DColor.rgb(0x273039)
    public static let glass = Map3DColor.rgb(0x405560)
    public static let silver = Map3DColor.rgb(0xAAB7BF)

    public static func model(_ unit: Unit) -> Map3DModelPack.Model { model(unit, far: false) }

    /// `far`: decision 426's light version drawn from 500 m out, as
    /// ``Map3DTEMU1000/model(_:far:)`` is: fewer nose rings and front
    /// panel rows, no wheel hubs, one pane of glass between the doors on
    /// each side, and none of the small fittings. The shape, the colours
    /// and the length are the near unit's, the tyres still on the rail.
    public static func model(_ unit: Unit, far: Bool) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.temu2000(unit, far: far)
        return .flat(named: "temu2000-\(unit.rawValue)" + (far ? "-far" : ""), from: builder.mesh)
    }

    public static func studyModel(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.temu2000(unit, far: far, study: true)
        return .flat(named: "temu2000-\(unit.rawValue)" + (far ? "-far" : ""), from: builder.mesh)
    }

    /// Symmetric official TED–TEMA–TEP–TEMB–TEMB–TEP–TEMA–TED order.
    /// The negative-X TED is reversed in its own geometry, so both cabs face out.
    public static let order: [Unit] = [
        .trailing, .tema, .tep, .temb, .temb, .tep, .tema, .leading
    ]
    public static let centres: [Float] = [
        -73.1475, -51.75, -31.05, -10.35, 10.35, 31.05, 51.75, 73.1475
    ]
    /// The second TEP faces outward so its pantograph points toward car 8.
    public static let rotations: [Float] = [
        0, 0, 0, 0, 0, .pi, 0, 0
    ]

    public static func formation() -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        for (index, unit) in order.enumerated() {
            builder.add(model(unit), at: Map3DPoint(centres[index], 0, 0),
                        angle: rotations[index])
        }
        return .flat(named: "temu2000-formation", from: builder.mesh)
    }

    public static func studyFormation() -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        for (index, unit) in order.enumerated() {
            builder.add(studyModel(unit), at: Map3DPoint(centres[index], 0, 0),
                        angle: rotations[index])
        }
        return .flat(named: "temu2000-formation", from: builder.mesh)
    }
}

extension StationKitBuilder {
    mutating func temuSolidFace(_ points: [Map3DPoint], inside: Map3DPoint, color: UInt32) {
        guard points.count >= 3 else { return }
        if points.count > 3 {
            for i in 1..<(points.count-1) {
                temuSolidFace([points[0],points[i],points[i+1]],inside:inside,color:color)
            }
            return
        }
        var front = points
        let n = (front[1]-front[0]).cross(front[2]-front[0])
        let centre = front.reduce(Map3DPoint.zero) { $0 + $1*(1/Float(front.count)) }
        if n.dot(centre-inside) < 0 { front.reverse() }
        let normal = (front[1]-front[0]).cross(front[2]-front[0])
        let length = max(0.000001,sqrtf(normal.dot(normal)))
        let offset = normal*(-0.004/length)
        let back = front.map { $0 + offset }
        mesh.addFacet(front,color:color)
        mesh.addFacet(Array(back.reversed()),color:color)
        for i in front.indices {
            let j = (i+1)%front.count
            mesh.addFacet([front[i],back[i],back[j],front[j]],color:color)
        }
    }
    mutating func temu2000(_ unit: Map3DTEMU2000.Unit, far: Bool = false, study: Bool = false) {
        let white = Map3DTEMU2000.white
        let teal = study ? Map3DTEMU2000.studyRed : Map3DTEMU2000.teal
        let navy = study ? Map3DTEMU2000.studyDark : Map3DTEMU2000.navy
        let glass = Map3DTEMU2000.glass
        let silver = Map3DTEMU2000.silver
        let cab: Float = unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let halfBody: Float = cab == 0 ? 10.0 : 10.8725
        let roofHeight: Float = cab == 0 ? 3.565 : 3.632
        let inside = Map3DPoint(0, 2.0, 0)

        // New TEMU2000 section: long straight waist, softly rolled upper
        // shoulders and a narrow roof crown. Height and half-width are sampled
        // separately through the cab; no TEMU1000 shell vertices are reused.
        let studySection: [(Float, Float)] = [
            (0.96,-1.17),(1.05,-1.37),(1.38,-1.45),
            (1.43,-1.45),(1.53,-1.45),(1.59,-1.45),(1.64,-1.45),(2.53,-1.45),
            (2.99,-1.42),(3.29,-1.30),(3.49,-1.06),(3.565,-0.66),
            (3.565,0.66),(3.49,1.06),(3.29,1.30),(2.99,1.42),
            (2.53,1.45),(1.64,1.45),(1.59,1.45),(1.53,1.45),
            (1.43,1.45),(1.38,1.45),(1.05,1.37),(0.96,1.17)
        ]
        let operatingSection: [(Float, Float)] = [
            (0.96,-1.17),(1.05,-1.37),(1.38,-1.45),(2.53,-1.45),
            (2.99,-1.42),(3.29,-1.30),(3.49,-1.06),(3.565,-0.66),
            (3.565,0.66),(3.49,1.06),(3.29,1.30),(2.99,1.42),
            (2.53,1.45),(1.38,1.45),(1.05,1.37),(0.96,1.17)
        ]
        let section = study ? studySection : operatingSection
        func ring(_ x: Float, width: Float = 1, top: Float = roofHeight,
                  bottom: Float = 0.96, crown: Float = 0) -> [Map3DPoint] {
            section.map { y, lateral in
                let t = (y - 0.96) / (3.565 - 0.96)
                let side = lateral * width * (1 - 0.055 * crown * sinf(Float.pi * t))
                let centerBias = 1 - 0.16 * abs(lateral) / 1.45
                return Map3DPoint(x + cab * crown * centerBias * sinf(Float.pi * t),
                                  bottom + t * (top - bottom), side)
            }
        }
        // The full-height carbody begins around the front bogie. Its top
        // descends through several shallow stations, while the lower cheeks
        // stay wide until the short blunt lip. These dimensions after the
        // official envelope are proportional estimates from the supplied views.
        // Decision 426: the far version keeps seven of the thirteen (the
        // roof's descent, the shoulder, the lip and the tip).
        let allNoseStations: [(x: Float,w: Float,h: Float,b: Float,c: Float,far: Bool)] = [
            (6.84,1.00,roofHeight,0.96,0.00,true),
            (7.34,1.00,3.59,0.95,0.03,false),
            (7.84,0.99,3.50,0.87,0.08,true),
            (8.35,0.98,3.35,0.72,0.11,false),
            (8.82,0.97,3.12,0.54,0.13,true),
            (9.28,0.95,2.84,0.40,0.15,false),
            (9.72,0.91,2.49,0.35,0.15,true),
            (10.11,0.84,2.11,0.38,0.13,false),
            (10.28,0.785,1.96,0.42,0.11,true),
            (10.47,0.70,1.79,0.47,0.09,false),
            (10.60,0.625,1.68,0.52,0.07,true),
            (10.75,0.52,1.55,0.59,0.05,false),
            (10.8725,0.36,1.39,0.69,0.02,true)
        ]
        let noseStations = allNoseStations.filter { !far || $0.far }
        var rings: [[Map3DPoint]]
        if cab > 0 {
            rings = [ring(-halfBody)] + noseStations.map {
                ring($0.x,width:$0.w,top:$0.h,bottom:$0.b,crown:$0.c)
            }
        } else if cab < 0 {
            rings = noseStations.reversed().map {
                ring(-$0.x,width:$0.w,top:$0.h,bottom:$0.b,crown:$0.c)
            } + [ring(halfBody)]
        } else {
            rings = [ring(-halfBody),ring(halfBody)]
        }
        for k in 0..<(rings.count - 1) {
            for i in section.indices {
                let j = (i + 1) % section.count
                let bodySpan = cab == 0 || k == (cab > 0 ? 0 : rings.count-2)
                let bandHeight = (section[i].0 + section[j].0)*0.5
                let isBand = bodySpan && ((bandHeight >= 1.43 && bandHeight < 1.53)
                    || (bandHeight >= 1.59 && bandHeight < 1.64))
                let shellColor = isBand ? teal : white
                // Preserve one winding across every swept station. Choosing
                // per-triangle orientation against a fixed centre flipped
                // individual faces where the cab folds down at its lip.
                if study {
                    mesh.addFacet([rings[k][i],rings[k][j],rings[k+1][j]],color:shellColor)
                    mesh.addFacet([rings[k][i],rings[k+1][j],rings[k+1][i]],color:shellColor)
                } else {
                    face([rings[k][i],rings[k][j],rings[k+1][j]],inside:inside,color:white)
                    face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:inside,color:white)
                }
            }
        }
        face(rings[0],inside:inside,color:white)
        face(rings[rings.count-1],inside:inside,color:white)

        if study {
            // The manufacturer's 2014 brochure shows a recessed passage
            // and rubber diaphragm between cars. Keep it within each end
            // wall, leaving the driver's nose clear.
            for end: Float in [-1,1] where cab == 0 || end == -cab {
                box(end*halfBody,1.05,0,0.22,1.65,1.95,navy)
            }
        }

        // Separate underframe, two 2.2 m wheelbase bogies, actual 0.86 m
        // wheel diameter. Wheel-centre positions are constrained by 14.3 m
        // bogie spacing; undisclosed equipment sizes are proportional estimates.
        let frameCenter = cab == 0 ? Float(0) : -cab*1.55
        let frameLength = cab == 0 ? Float(19.6) : Float(18.0)
        box(frameCenter,0.77,0,frameLength,2.15,0.18,navy)
        for bogie: Float in [-7.15,7.15] {
            box(bogie,0.60,0,2.83,1.96,0.18,navy)
            for axle: Float in [-1.10,1.10] {
                civicTube(Map3DPoint(bogie+axle,0.43,-0.69),
                          Map3DPoint(bogie+axle,0.43,-0.79),
                          radius:0.43,color:navy,sides:8)
                civicTube(Map3DPoint(bogie+axle,0.43,0.69),
                          Map3DPoint(bogie+axle,0.43,0.79),
                          radius:0.43,color:navy,sides:8)
                if !far {
                    for side: Float in [-1,1] {
                        civicTube(Map3DPoint(bogie+axle,0.43,side*0.80),
                                  Map3DPoint(bogie+axle,0.43,side*0.82),
                                  radius:0.20,color:silver,sides:8)
                    }
                }
            }
            if !far {
                for side: Float in [-1,1] {
                    box(bogie,0.58,side*0.95,2.64,0.11,0.26,navy)
                }
            }
        }
        for x: Float in [-4.6,-1.5,1.5,4.6] {
            box(x,0.56,0,2.05,1.84,0.34,unit == .temb ? navy : silver)
        }
        if unit == .temb {
            box(0,0.58,0,2.85,1.95,0.34,navy)
        }

        // Each passenger pane is independent. The dark recess is narrow and
        // local to each pane; there is no continuous black window strip.
        for side: Float in [-1,1] {
            let doors: [Float] = cab == 0 ? [-9.10,9.10]
                : cab > 0 ? [-9.15,5.80] : [-5.80,9.15]
            func doorPanel(_ x: Float) {
                if study {
                    // The door leaf is segmented at the same two paint
                    // heights as the shell; no overlapping colour plate.
                    for (base,height,color): (Float,Float,UInt32) in [
                        (0.99,0.44,white),(1.43,0.10,teal),
                        (1.53,0.06,white),(1.59,0.05,teal),
                        (1.64,1.43,white)
                    ] { box(x,base,side*1.455,0.86,0.010,height,color) }
                } else {
                    box(x,0.99,side*1.455,0.86,0.010,2.08,white)
                }
            }
            let windowXs: [Float] = cab == 0
                ? [-7.75,-6.53,-5.31,-4.09,-2.87,-1.65,-0.43,
                   0.79,2.01,3.23,4.45,5.67,6.89,8.11]
                : [-7.80,-6.54,-5.28,-4.02,-2.76,-1.50,-0.24,
                   1.02,2.28,3.54,4.80]
            if far {
                // One pane along the side between the doors, the doors
                // over it: the near panes' first and last edges.
                let first = (windowXs.min() ?? 0) - 0.435, last = (windowXs.max() ?? 0) + 0.435
                var from = first
                for door in doors.sorted() + [Float.infinity] {
                    let to = min(last, door - 0.50)
                    if to - from > 0.8 {
                        box((from+to)/2,2.08,side*1.455,to-from,0.016,0.55,navy)
                        box((from+to)/2,2.13,side*1.467,to-from-0.10,0.008,0.45,glass)
                    }
                    from = max(from, door + 0.50)
                }
                for x in doors { doorPanel(x) }
            } else {
                for x in windowXs where !doors.contains(where: { abs(x-$0)<0.72 }) {
                    box(x,2.08,side*1.455,0.87,0.016,0.55,navy)
                    box(x,2.13,side*1.467,0.77,0.008,0.45,glass)
                }
                for x in doors {
                    doorPanel(x)
                    box(x,2.12,side*1.465,0.54,0.008,0.65,navy)
                    box(x,2.16,side*1.472,0.46,0.004,0.56,glass)
                    box(x+0.38,1.00,side*1.467,0.012,0.010,2.02,silver)
                }
            }
            if !study {
                let stripeCenter = cab == 0 ? Float(0) : -cab*1.78
                let stripeLength = cab == 0 ? Float(19.2) : Float(17.35)
                box(stripeCenter,1.62,side*1.454,stripeLength,0.014,0.10,teal)
                box(stripeCenter,1.48,side*1.450,stripeLength,0.012,0.035,navy)
            }
            if cab != 0 {
                // Cab side glass is a distinct tapered quadrilateral.
                let s = side*1.46
                let sidePaneOuter = [
                    Map3DPoint(cab*6.91,2.48,s),
                    Map3DPoint(cab*7.95,2.48,s*0.988),
                    Map3DPoint(cab*8.28,2.94,s*0.970),
                    Map3DPoint(cab*7.05,2.99,s)
                ]
                let sidePaneInner = [
                    Map3DPoint(cab*7.00,2.53,s*1.006),
                    Map3DPoint(cab*7.90,2.53,s*0.995),
                    Map3DPoint(cab*8.17,2.88,s*0.978),
                    Map3DPoint(cab*7.12,2.92,s*1.006)
                ]
                if study {
                    temuSolidFace(sidePaneOuter,inside:inside,color:navy)
                    temuSolidFace(sidePaneInner,inside:inside,color:glass)
                } else {
                    face(sidePaneOuter,inside:inside,color:navy)
                    face(sidePaneInner,inside:inside,color:glass)
                }
            }
        }

        // Roof housings are physically separate, low and supported; the body
        // roof itself stays white. TEP alone carries the raised pantograph.
        for x: Float in [-5.9,5.9] {
            // The nose-side housing must sit behind the forehead. The old
            // 1.7 m wide rectangular block projected above the front face.
            let cabEnd = cab != 0 && x*cab > 0
            if study {
                let housingLength: Float = cabEnd ? 2.20 : 3.15
                let housingWidth: Float = cab != 0 ? 1.12 : 1.50
                let housingHeight: Float = cab != 0 ? 0.025 : 0.15
                box(x,roofHeight-0.005,0,housingLength,housingWidth,housingHeight,
                    cab != 0 ? white : silver)
            } else {
                box(x,roofHeight-0.005,0,3.15,1.70,0.30,
                    cabEnd ? white : silver)
                if !far { box(x,roofHeight+0.292,0,2.34,1.21,0.025,white) }
            }
        }
        for x: Float in [-1.92,1.92] {
            box(x,roofHeight-0.005,0,1.00,1.02,study && cab != 0 ? 0.025 : 0.14,
                study && cab != 0 ? white : silver)
        }
        if unit == .tep {
            let x: Float = -8.05
            box(x,roofHeight-0.005,0,1.60,1.06,0.22,navy)
            for side: Float in [-1,1] {
                civicTube(Map3DPoint(x-0.48,roofHeight+0.24,side*0.34),
                          Map3DPoint(x+0.20,roofHeight+0.54,side*0.34),
                          radius:0.035,color:navy,sides:far ? 4 : 8)
                civicTube(Map3DPoint(x+0.20,roofHeight+0.54,side*0.34),
                          Map3DPoint(x+0.72,roofHeight+0.70,side*0.34),
                          radius:0.035,color:navy,sides:far ? 4 : 8)
            }
            civicTube(Map3DPoint(x+0.43,roofHeight+0.685,-0.76),
                      Map3DPoint(x+0.43,roofHeight+0.685,0.76),
                      radius:0.048,color:navy,sides:far ? 4 : 8)
        }

        if cab != 0 {
            // Sample the *actual* cab rings for each fascia vertex. V1 put
            // front fittings inside the swept shell; all these patches now
            // follow the visible sloped surface and leave white side cheeks.
            func roofPoint(_ station: Float, _ lateral: Float, _ lift: Float = 0.025) -> Map3DPoint {
                let upper = noseStations.firstIndex { $0.x >= station } ?? noseStations.count-1
                let lower = max(0,upper-1)
                let a = noseStations[lower], b = noseStations[upper]
                let blend = abs(b.x-a.x) < 0.0001 ? Float(0) : (station-a.x)/(b.x-a.x)
                func at(_ q: (x: Float,w: Float,h: Float,b: Float,c: Float,far: Bool)) -> Map3DPoint {
                    let cross = ring(cab*q.x,width:q.w,top:q.h,bottom:q.b,crown:q.c)
                    let z = abs(lateral)
                    for i in (study ? 12..<16 : 8..<12) {
                        let p = cross[i], next = cross[i+1]
                        if z <= next.z {
                            let f = min(1,max(0,(z-p.z)/max(0.00001,next.z-p.z)))
                            return Map3DPoint(p.x+(next.x-p.x)*f,
                                              p.y+(next.y-p.y)*f, lateral)
                        }
                    }
                    let last = study ? 16 : 12
                    return Map3DPoint(cross[last].x,cross[last].y,lateral)
                }
                let p=at(a),q=at(b)
                return Map3DPoint(p.x+(q.x-p.x)*blend+cab*lift,
                                  p.y+(q.y-p.y)*blend+lift,lateral)
            }
            // Close the decorative patches as shallow solids. A lone facet
            // passed the old render checks but failed a real edge audit and
            // disappeared when the view was reversed.
            func solidFace(_ points: [Map3DPoint], _ color: UInt32) {
                if study { temuSolidFace(points,inside:inside,color:color) }
                else { face(points,inside:inside,color:color) }
            }
            func panel(_ allStations: [Float],_ allHalfWidths: [Float],_ allColumns: Int,
                       _ color: UInt32,_ lift: Float,_ lowerCurve: Float = 0) {
                // Decision 426: the far version has every other row and
                // half the columns, the first and last row kept.
                let kept = allStations.indices.filter { !far || $0 % 2 == 0 || $0 == allStations.count-1 }
                let stations = kept.map { allStations[$0] }, halfWidths = kept.map { allHalfWidths[$0] }
                let columns = far ? allColumns/2 : allColumns
                for row in 0..<(stations.count-1) {
                    for col in 0..<columns {
                        let v0 = Float(col)/Float(columns)*2-1
                        let v1 = Float(col+1)/Float(columns)*2-1
                        func point(_ r: Int,_ v: Float) -> Map3DPoint {
                            let u = Float(r)/Float(stations.count-1)
                            let station = stations[r] + lowerCurve*u*(1-v*v)
                            return roofPoint(station,v*halfWidths[r],lift)
                        }
                        let a=point(row,v0),b=point(row,v1)
                        let c=point(row+1,v1),d=point(row+1,v0)
                        solidFace([a,b,c],color)
                        solidFace([a,c,d],color)
                    }
                }
            }
            // A full-height coloured forehead holds the three upper lamps.
            // The glass begins lower on the slope, leaving a visible band
            // like the supplied near-front photo and frontal illustration.
            panel([7.77,8.06,8.34,8.62,8.92,9.23,9.54],
                  [1.05,1.12,1.17,1.19,1.18,1.15,1.13],8,teal,0.101)
            // Broad windshield with its own dark rubber surround.
            panel([8.82,9.03,9.26,9.50,9.74],
                  [1.04,1.14,1.18,1.16,1.09],8,navy,0.124,0.06)
            panel([8.89,9.08,9.29,9.50,9.67],
                  [0.94,1.04,1.09,1.06,0.99],8,glass,0.145,0.04)
            // Close stations form a shallow S-curve around each white cheek.
            // The colour stays broad below the lamps, leaving two restrained
            // side cheeks instead of white lobes that push into the centre.
            panel([9.40,9.72,9.99,10.13,10.23,10.31,10.39,
                   10.47,10.55,10.63,10.71,10.80,10.8725],
                  [1.16,1.16,1.13,1.05,0.98,0.88,0.78,
                   0.73,0.68,0.62,0.56,0.52,0.48],8,teal,0.110)
            // Carry the tapered centre field down the short blunt end cap.
            // A slight bow replaces the perfectly straight cheek-side edge;
            // the white lower lip remains exposed.
            solidFace([
                Map3DPoint(cab*10.925,1.51,-0.48),
                Map3DPoint(cab*10.925,1.51,0.48),
                Map3DPoint(cab*10.925,1.36,0.50),
                Map3DPoint(cab*10.925,1.12,0.50),
                Map3DPoint(cab*10.925,0.87,0.48),
                Map3DPoint(cab*10.925,0.80,0.45),
                Map3DPoint(cab*10.925,0.80,-0.45),
                Map3DPoint(cab*10.925,0.87,-0.48),
                Map3DPoint(cab*10.925,1.12,-0.50),
                Map3DPoint(cab*10.925,1.36,-0.50)
            ],teal)
            // Lens faces are laid on the swept cab skin, so their position
            // follows the forehead instead of floating above the roof.
            func lens(_ station: Float,_ lateral: Float,_ along: Float,
                      _ across: Float,_ lift: Float,_ color: UInt32) {
                var rim: [Map3DPoint] = []
                let around = far ? 6 : 8
                for i in 0..<around {
                    let angle = Float(i)*2*Float.pi/Float(around)
                    rim.append(roofPoint(station+along*cosf(angle),
                                         lateral+across*sinf(angle),lift))
                }
                solidFace(rim,color)
            }
            for side: Float in [-1,1] {
                let s = side
                // The lower paired lamps sit in compact horizontal pods.
                solidFace([
                    roofPoint(9.93,s*0.39,0.160),roofPoint(9.87,s*0.79,0.160),
                    roofPoint(9.99,s*0.97,0.160),roofPoint(10.16,s*0.97,0.160),
                    roofPoint(10.30,s*0.89,0.160),roofPoint(10.25,s*0.47,0.160)
                ],navy)
                lens(10.09,s*0.62,0.065,0.09,0.180,silver)
                lens(10.12,s*0.94,0.065,0.09,0.180,silver)
                lens(8.37,s*0.68,0.330,0.145,0.151,navy)
                lens(8.37,s*0.68,0.245,0.100,0.169,silver)
            }
            solidFace([
                roofPoint(8.30,-0.19,0.155),roofPoint(8.30,0.19,0.155),
                roofPoint(8.60,0.19,0.155),roofPoint(8.60,-0.19,0.155)
            ],navy)
            for side: Float in [-1,1] {
                civicTube(roofPoint(9.30,side*0.04,0.180),
                          roofPoint(8.97,side*0.66,0.180),
                          radius:0.018,color:navy,sides:far ? 4 : 6)
            }
        }
    }
}
