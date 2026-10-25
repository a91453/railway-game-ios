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
                return Map3DPoint(x + bulge * 4 * t * (1-t) * shoulder, bottom + t * (top-bottom), side * width * oval)
            }
        }
        var rings = [ring(-11.75),ring(11.75)]
        if nose > 0 {
            rings = [ring(-11.75),ring(8.9),ring(9.85,width:0.98,top:3.56),
                     ring(10.75,width:0.94,top:3.20,bottom:0.76),
                     ring(11.55,width:0.94,top:2.75,bottom:0.65),
                     ring(12.20,width:0.91,top:2.36,bottom:0.63,bulge:0.22,noseRound:0.22)]
        } else if nose < 0 {
            rings = [ring(-12.20,width:0.91,top:2.36,bottom:0.63,bulge:-0.22,noseRound:0.22),
                     ring(-11.55,width:0.94,top:2.75,bottom:0.65),
                     ring(-10.75,width:0.94,top:3.20,bottom:0.76),
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
        face(rings[0],inside:centre,color:white)
        face(rings[rings.count-1],inside:centre,color:white)
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
                nose == 0 ? 19.7 : 17.5,0.012,0.065,green)
        }
        if nose != 0 {
            // Follow the curved nose with the same narrow, non-red waist
            // stripe. The surface positions come from the actual end rings.
            let stations: [(Float,Float,Float)] = [(7.65,1.45,1.96),(8.90,1.45,1.96),
                                                    (9.85,1.421,1.79),(10.75,1.363,1.63),
                                                    (11.55,1.363,1.51),(12.20,1.277,1.44)]
            for side: Float in [-1,1] {
                for i in 0..<(stations.count-1) {
                    let a = stations[i], b = stations[i+1]
                    let z0 = side*(a.1+0.014), z1 = side*(b.1+0.014)
                    face([Map3DPoint(nose*a.0,a.2-0.035,z0),Map3DPoint(nose*a.0,a.2+0.035,z0),
                          Map3DPoint(nose*b.0,b.2+0.035,z1),Map3DPoint(nose*b.0,b.2-0.035,z1)],inside:centre,color:green)
                }
            }
            // The end ring bulges in X at mid-height; the stripe follows it
            // across the frontal nose instead of cutting a flat chord.
            for i in 0..<16 {
                func point(_ z: Float,_ y: Float) -> Map3DPoint {
                    let t = (y-0.63)/(2.36-0.63)
                    let oval = 1 - 0.22*(1-sinf(Float.pi*t))
                    let side = z/(0.91*oval)
                    let shoulder = max(0,1-(side/1.45)*(side/1.45))
                    return Map3DPoint(nose*(12.20+0.22*4*t*(1-t)*shoulder+0.012),y,z)
                }
                let z0 = -1.27 + Float(i)*2.54/16, z1 = -1.27 + Float(i+1)*2.54/16
                func arc(_ z: Float) -> Float { 0.98 + 0.46*(z/1.27)*(z/1.27) }
                face([point(z0,arc(z0)),point(z0,arc(z0)+0.07),
                      point(z1,arc(z1)+0.07),point(z1,arc(z1))],inside:centre,color:green)
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
            // Broad windscreen across the cab shoulders, supported by the
            // raked shell. The photo shows a large windshield and short,
            // rounded white face below it.
            let sx = nose*10.70
            let panel = [Map3DPoint(sx+nose*0.20,3.16,-1.13),
                         Map3DPoint(sx+nose*0.20,3.16,1.13),
                         Map3DPoint(sx+nose*1.66,2.30,1.04),
                         Map3DPoint(sx+nose*1.66,2.30,-1.04)]
            face(panel,inside:centre,color:ink)
            let pane = panel.map { Map3DPoint($0.x+nose*0.018,$0.y+0.027,$0.z*0.96) }
            face(pane,inside:centre,color:glass)
            // Oval lamp pods have a shallow closed backing sunk into the
            // white nose. Their lenses sit above the wraparound stripe.
            for side: Float in [-1,1] {
                func oval(_ x: Float, _ yr: Float, _ zr: Float) -> [Map3DPoint] {
                    (0..<12).map { i in
                        let a = 2 * Float.pi * Float(i) / 12
                        return Map3DPoint(x, 1.87 + yr*sinf(a)
                                               + side*0.04*cosf(a), side*0.79 + zr*cosf(a))
                    }
                }
                let back = oval(nose*12.28,0.11,0.21)
                let rim = oval(nose*12.36,0.11,0.21)
                face(back,inside:centre,color:ink)
                face(rim,inside:centre,color:ink)
                for i in 0..<12 {
                    let j = (i+1)%12
                    face([back[i],back[j],rim[j],rim[i]],inside:centre,color:ink)
                }
                face(oval(nose*12.37,0.065,0.15),inside:centre,color:Map3DPalette.tileWhite)
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
