import Foundation

/// Static TEMU1000 study. Geometry is authored x forward, y up, z right;
/// Model.flat converts it once to native x forward, y left, z up metres.
public enum Map3DTEMU1000 {
    public static let pitch: Float = 23.9
    public enum Unit: String, CaseIterable, Sendable { case leading, middle, pantograph, trailing }
    public static let shell = Map3DPalette.tileWhite
    public static let band = Map3DPalette.trimBlue
    public static let glass = Map3DTrainStyle.glass
    public static let ink = Map3DColor.shaded(Map3DPalette.trimBlue, 0.45)

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
        func ring(_ x: Float, width: Float = 1, top: Float = 3.70, bottom: Float = 0.83) -> [Map3DPoint] {
            section.map { h, side in
                let t = (h - 0.83) / 2.87
                return Map3DPoint(x, bottom + t * (top-bottom), side * width)
            }
        }
        var rings = [ring(-11.75),ring(11.75)]
        if nose > 0 {
            rings = [ring(-11.75),ring(8.9),ring(9.85,width:0.98,top:3.56),
                     ring(10.75,width:0.94,top:3.26,bottom:0.76),
                     ring(11.65,width:0.83,top:2.76,bottom:0.61),
                     ring(12.35,width:0.72,top:2.05,bottom:0.60)]
        } else if nose < 0 {
            rings = [ring(-12.35,width:0.72,top:2.05,bottom:0.60),
                     ring(-11.65,width:0.83,top:2.76,bottom:0.61),
                     ring(-10.75,width:0.94,top:3.26,bottom:0.76),
                     ring(-9.85,width:0.98,top:3.56),ring(-8.9),ring(11.75)]
        }
        for k in 0..<(rings.count-1) {
            for i in section.indices {
                let j = (i+1) % section.count
                let c: UInt32
                if (i == 2 || i == 12) { c = white }
                else if i == 3 || i == 11 { c = ink }
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
        // Doors are shallow panels embedded in the straight flank; thin seams.
        for side: Float in [-1,1] {
            for x: Float in [-10.35,10.35] {
                if nose != 0 && x*nose > 0 { continue }
                box(x,1.58,side*1.451,0.88,0.012,1.92,white)
                box(x,2.00,side*1.459,0.54,0.006,0.74,glass)
                box(x,0.68,side*1.458,0.012,0.008,0.10,ink)
            }
            // A continuous dark band with narrow upright panes and visible piers.
            for x: Float in stride(from:-8.8,through:8.8,by:1.75) {
                if nose != 0 && x*nose > 7.4 { continue }
                if abs(x) > 9.1 { continue }
                box(x,2.46,side*1.451,1.49,0.010,0.87,ink)
                box(x,2.47,side*1.459,1.36,0.007,0.77,glass)
            }
            box(0,1.43,side*1.452,18.5,0.015,0.095,green)
        }
        if nose != 0 {
            // Cab side triangular glass sits over a solid shoulder on each side.
            for side: Float in [-1,1] {
                let x = nose*9.02
                box(x,2.43,side*1.408,1.35,0.022,0.61,ink)
                box(x,2.44,side*1.423,1.21,0.008,0.51,glass)
            }
            // Raked windshield, with a white brow and a dark backing.
            let sx = nose*10.57
            let panel = [Map3DPoint(sx-nose*0.54,3.50,-0.94),
                         Map3DPoint(sx-nose*0.54,3.50,0.94),
                         Map3DPoint(sx+nose*0.62,3.08,0.80),
                         Map3DPoint(sx+nose*0.62,3.08,-0.80)]
            face(panel,inside:centre,color:ink)
            let pane = panel.map { Map3DPoint($0.x+nose*0.012,$0.y+0.020,$0.z*0.92) }
            face(pane,inside:centre,color:glass)
            for side: Float in [-1,1] {
                box(nose*11.79,1.56,side*0.61,0.12,0.13,0.18,white)
            }
            for side: Float in [-1,1] {
                civicTube(Map3DPoint(nose*12.35,1.65,side*0.70),
                          Map3DPoint(nose*12.39,1.65,side*0.70),radius:0.17,color:ink,sides:10)
                civicTube(Map3DPoint(nose*12.39,1.65,side*0.70),
                          Map3DPoint(nose*12.40,1.65,side*0.70),radius:0.10,color:Map3DPalette.tileWhite,sides:10)
            }
            box(nose*12.15,0.68,0,0.25,0.36,0.20,ink)
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
