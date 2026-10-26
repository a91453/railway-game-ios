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
    public static let glass = Map3DColor.rgb(0x405560)
    public static let silver = Map3DColor.rgb(0xAAB7BF)

    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.temu2000(unit)
        return .flat(named: "temu2000-\(unit.rawValue)", from: builder.mesh)
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
}

extension StationKitBuilder {
    mutating func temu2000(_ unit: Map3DTEMU2000.Unit) {
        let white = Map3DTEMU2000.white
        let teal = Map3DTEMU2000.teal
        let navy = Map3DTEMU2000.navy
        let glass = Map3DTEMU2000.glass
        let silver = Map3DTEMU2000.silver
        let cab: Float = unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let halfBody: Float = cab == 0 ? 10.0 : 10.8725
        let roofHeight: Float = cab == 0 ? 3.565 : 3.632
        let inside = Map3DPoint(0, 2.0, 0)

        // New TEMU2000 section: long straight waist, softly rolled upper
        // shoulders and a narrow roof crown. Height and half-width are sampled
        // separately through the cab; no TEMU1000 shell vertices are reused.
        let section: [(Float, Float)] = [
            (0.96,-1.17),(1.05,-1.37),(1.38,-1.45),(2.53,-1.45),
            (2.99,-1.42),(3.29,-1.30),(3.49,-1.06),(3.565,-0.66),
            (3.565,0.66),(3.49,1.06),(3.29,1.30),(2.99,1.42),
            (2.53,1.45),(1.38,1.45),(1.05,1.37),(0.96,1.17)
        ]
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
        let noseStations: [(x: Float,w: Float,h: Float,b: Float,c: Float)] = [
            (6.84,1.00,roofHeight,0.96,0.00),
            (7.34,1.00,3.59,0.95,0.03),
            (7.84,0.99,3.50,0.87,0.08),
            (8.35,0.98,3.35,0.72,0.11),
            (8.82,0.97,3.12,0.54,0.13),
            (9.28,0.95,2.84,0.40,0.15),
            (9.72,0.91,2.49,0.35,0.15),
            (10.11,0.84,2.11,0.38,0.13),
            (10.28,0.785,1.96,0.42,0.11),
            (10.47,0.70,1.79,0.47,0.09),
            (10.60,0.625,1.68,0.52,0.07),
            (10.75,0.52,1.55,0.59,0.05),
            (10.8725,0.36,1.39,0.69,0.02)
        ]
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
                face([rings[k][i],rings[k][j],rings[k+1][j]],inside:inside,color:white)
                face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:inside,color:white)
            }
        }
        face(rings[0],inside:inside,color:white)
        face(rings[rings.count-1],inside:inside,color:white)

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
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(bogie+axle,0.43,side*0.80),
                              Map3DPoint(bogie+axle,0.43,side*0.82),
                              radius:0.20,color:silver,sides:8)
                }
            }
            for side: Float in [-1,1] {
                box(bogie,0.58,side*0.95,2.64,0.11,0.26,navy)
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
            let windowXs: [Float] = cab == 0
                ? [-7.75,-6.53,-5.31,-4.09,-2.87,-1.65,-0.43,
                   0.79,2.01,3.23,4.45,5.67,6.89,8.11]
                : [-7.80,-6.54,-5.28,-4.02,-2.76,-1.50,-0.24,
                   1.02,2.28,3.54,4.80]
            for x in windowXs where !doors.contains(where: { abs(x-$0)<0.72 }) {
                box(x,2.08,side*1.455,0.87,0.016,0.55,navy)
                box(x,2.13,side*1.467,0.77,0.008,0.45,glass)
            }
            for x in doors {
                box(x,0.99,side*1.455,0.86,0.010,2.08,white)
                box(x,2.12,side*1.465,0.54,0.008,0.65,navy)
                box(x,2.16,side*1.472,0.46,0.004,0.56,glass)
                box(x+0.38,1.00,side*1.467,0.012,0.010,2.02,silver)
            }
            // Clean game-palette waist stripe, visibly below individual panes.
            let stripeCenter = cab == 0 ? Float(0) : -cab*1.78
            let stripeLength = cab == 0 ? Float(19.2) : Float(17.35)
            box(stripeCenter,1.62,side*1.454,stripeLength,0.014,0.10,teal)
            box(stripeCenter,1.48,side*1.450,stripeLength,0.012,0.035,navy)
            if cab != 0 {
                // Cab side glass is a distinct tapered quadrilateral.
                let s = side*1.46
                face([
                    Map3DPoint(cab*6.91,2.48,s),
                    Map3DPoint(cab*7.95,2.48,s*0.988),
                    Map3DPoint(cab*8.28,2.94,s*0.970),
                    Map3DPoint(cab*7.05,2.99,s)
                ],inside:inside,color:navy)
                face([
                    Map3DPoint(cab*7.00,2.53,s*1.006),
                    Map3DPoint(cab*7.90,2.53,s*0.995),
                    Map3DPoint(cab*8.17,2.88,s*0.978),
                    Map3DPoint(cab*7.12,2.92,s*1.006)
                ],inside:inside,color:glass)
            }
        }

        // Roof housings are physically separate, low and supported; the body
        // roof itself stays white. TEP alone carries the raised pantograph.
        for x: Float in [-5.9,5.9] {
            // The cab-end HVAC shroud reads as a white hump behind the face,
            // not a dark rectangular header above its three embedded lamps.
            box(x,roofHeight-0.005,0,3.15,1.70,0.30,
                cab != 0 && x*cab > 0 ? white : silver)
            box(x,roofHeight+0.292,0,2.34,1.21,0.025,white)
        }
        for x: Float in [-1.92,1.92] {
            box(x,roofHeight-0.005,0,1.00,1.02,0.14,silver)
        }
        if unit == .tep {
            let x: Float = -8.05
            box(x,roofHeight-0.005,0,1.60,1.06,0.22,navy)
            for side: Float in [-1,1] {
                civicTube(Map3DPoint(x-0.48,roofHeight+0.24,side*0.34),
                          Map3DPoint(x+0.20,roofHeight+0.54,side*0.34),
                          radius:0.035,color:navy,sides:8)
                civicTube(Map3DPoint(x+0.20,roofHeight+0.54,side*0.34),
                          Map3DPoint(x+0.72,roofHeight+0.70,side*0.34),
                          radius:0.035,color:navy,sides:8)
            }
            civicTube(Map3DPoint(x+0.43,roofHeight+0.685,-0.76),
                      Map3DPoint(x+0.43,roofHeight+0.685,0.76),
                      radius:0.048,color:navy,sides:8)
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
                func at(_ q: (x: Float,w: Float,h: Float,b: Float,c: Float)) -> Map3DPoint {
                    let cross = ring(cab*q.x,width:q.w,top:q.h,bottom:q.b,crown:q.c)
                    let z = abs(lateral)
                    for i in 8..<12 {
                        let p = cross[i], next = cross[i+1]
                        if z <= next.z {
                            let f = min(1,max(0,(z-p.z)/max(0.00001,next.z-p.z)))
                            return Map3DPoint(p.x+(next.x-p.x)*f,
                                              p.y+(next.y-p.y)*f, lateral)
                        }
                    }
                    return Map3DPoint(cross[12].x,cross[12].y,lateral)
                }
                let p=at(a),q=at(b)
                return Map3DPoint(p.x+(q.x-p.x)*blend+cab*lift,
                                  p.y+(q.y-p.y)*blend+lift,lateral)
            }
            func panel(_ stations: [Float],_ halfWidths: [Float],_ columns: Int,
                       _ color: UInt32,_ lift: Float,_ lowerCurve: Float = 0) {
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
                        face([a,b,c],inside:inside,color:color)
                        face([a,c,d],inside:inside,color:color)
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
            face([
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
            ],inside:inside,color:teal)
            // Lens faces are laid on the swept cab skin, so their position
            // follows the forehead instead of floating above the roof.
            func lens(_ station: Float,_ lateral: Float,_ along: Float,
                      _ across: Float,_ lift: Float,_ color: UInt32) {
                var rim: [Map3DPoint] = []
                for i in 0..<8 {
                    let angle = Float(i)*Float.pi/4
                    rim.append(roofPoint(station+along*cosf(angle),
                                         lateral+across*sinf(angle),lift))
                }
                face(rim,inside:inside,color:color)
            }
            for side: Float in [-1,1] {
                let s = side
                // The lower paired lamps sit in compact horizontal pods.
                face([
                    roofPoint(9.93,s*0.39,0.160),roofPoint(9.87,s*0.79,0.160),
                    roofPoint(9.99,s*0.97,0.160),roofPoint(10.16,s*0.97,0.160),
                    roofPoint(10.30,s*0.89,0.160),roofPoint(10.25,s*0.47,0.160)
                ],inside:inside,color:navy)
                lens(10.09,s*0.62,0.065,0.09,0.180,silver)
                lens(10.12,s*0.94,0.065,0.09,0.180,silver)
                lens(8.37,s*0.68,0.330,0.145,0.151,navy)
                lens(8.37,s*0.68,0.245,0.100,0.169,silver)
            }
            face([
                roofPoint(8.30,-0.19,0.155),roofPoint(8.30,0.19,0.155),
                roofPoint(8.60,0.19,0.155),roofPoint(8.60,-0.19,0.155)
            ],inside:inside,color:navy)
            for side: Float in [-1,1] {
                civicTube(roofPoint(9.30,side*0.04,0.180),
                          roofPoint(8.97,side*0.66,0.180),
                          radius:0.018,color:navy,sides:6)
            }
        }
    }
}
