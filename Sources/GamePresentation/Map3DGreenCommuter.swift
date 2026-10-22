import Foundation

/// Two-car, high-floor commuter EMU. The two distinct cab units keep their
/// outward-facing ends without rotating a door/window layout in assembly.
/// Authored x-forward/y-up/z-right, converted once by `Model.flat`.
public enum Map3DGreenCommuter {
    public static let bodyLength: Float = 19.30
    public static let pitch: Float = 19.72
    public static let shellWidth: Float = 2.90
    public static let roofHeight: Float = 3.63
    public static let green = Map3DPalette.crown
    public static let cream = Map3DPalette.tileWhite
    public static let roof = Map3DPalette.tileWhite
    public static let glass = Map3DTrainStyle.glass

    public enum Unit: String, CaseIterable, Sendable { case leading, trailing }

    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.greenCommuter(unit)
        return .flat(named: "green-commuter-\(unit.rawValue)", from: builder.mesh)
    }

    public static func formation() -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        builder.add(model(.leading), at: Map3DPoint(pitch / 2, 0, 0))
        builder.add(model(.trailing), at: Map3DPoint(-pitch / 2, 0, 0))
        return .flat(named: "green-commuter-formation", from: builder.mesh)
    }
}

extension StationKitBuilder {
    mutating func greenCommuter(_ unit: Map3DGreenCommuter.Unit) {
        let green = Map3DGreenCommuter.green
        let cream = Map3DGreenCommuter.cream
        let grey = Map3DGreenCommuter.roof
        let pale = Map3DPalette.park
        let skirt = Map3DColor.shaded(green, 0.79)
        let glass = Map3DGreenCommuter.glass
        let ink = Self.ink
        let steel = Self.steel
        let cabSign: Float = unit == .leading ? 1 : -1
        let centre = Map3DPoint(0, 2, 0)

        // Each ring has its own width and rake. The long side stays straight;
        // only the last metre rounds into the nearly upright driving end.
        let profile: [(Float, Float)] = [
            (0.69,-1.29),(0.77,-1.43),(1.70,-1.45),(2.94,-1.45),
            (3.10,-1.45),(3.31,-1.37),(3.57,-1.06),(3.63,-0.83),
            (3.63,0.83),(3.57,1.06),(3.31,1.37),(3.10,1.45),
            (2.94,1.45),(1.70,1.45),(0.77,1.43),(0.69,1.29)
        ]
        func ring(_ x: Float, _ taper: Float = 0) -> [Map3DPoint] {
            profile.map { height,side in
                let rake = taper * max(0,height - 0.69) * 0.056
                let sx = x - (x >= 0 ? rake : -rake)
                return Map3DPoint(sx,height,side * (1 - 0.064 * taper))
            }
        }
        let rings = unit == .leading
            ? [ring(-9.65),ring(8.57),ring(9.14,0.42),ring(9.65,1)]
            : [ring(-9.65,1),ring(-9.14,0.42),ring(-8.57),ring(9.65)]
        for k in 0..<(rings.count - 1) {
            for i in profile.indices {
                let j = (i + 1) % profile.count
                let color: UInt32
                switch i {
                case 2,12: color = cream
                case 4...10: color = grey
                case 0,14,15: color = skirt
                default: color = green
                }
                let a = rings[k][i], b = rings[k][j]
                let c = rings[k + 1][j], d = rings[k + 1][i]
                face([a,b,c],inside:centre,color:color)
                face([a,c,d],inside:centre,color:color)
            }
        }
        face(rings[0],inside:centre,color:green)
        face(rings[rings.count - 1],inside:centre,color:green)

        // Full two-axle bogies: four wheels per visible side, rather than the
        // isolated little wheels of the earlier low-floor tram.
        box(0,0.68,0,18.95,2.25,0.17,ink)
        for bogie: Float in [-6.80,6.80] {
            box(bogie,0.46,0,3.55,2.20,0.23,Map3DColor.shaded(ink,0.86))
            for axle: Float in [-1.02,1.02] {
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(bogie+axle,0.38,side*1.12),
                              Map3DPoint(bogie+axle,0.38,side*1.29),
                              radius:0.38,color:Map3DStreetModel.tyre,sides:14)
                    civicTube(Map3DPoint(bogie+axle,0.38,side*1.29),
                              Map3DPoint(bogie+axle,0.38,side*1.302),
                              radius:0.17,color:steel,sides:12)
                }
            }
            for side: Float in [-1,1] {
                box(bogie,0.52,side*1.30,2.85,0.045,0.19,ink)
            }
        }
        for x: Float in [-3.0,0,3.0] { box(x,0.55,0,1.80,2.15,0.32,Map3DColor.shaded(steel,0.75)) }

        // Side elevations: three double passenger doors per car. The narrow
        // cab access door is separate and only at the outer driving end.
        for side: Float in [-1,1] {
            box(0,3.02,side*1.448,17.12,0.020,0.075,green)
            box(0,1.70,side*1.450,18.05,0.014,0.045,pale)
            box(0,0.80,side*1.434,18.25,0.014,0.16,skirt)
            let windows: [(Float,Float)] = [(-8.02,1.25),(-3.50,1.38),(-1.70,1.38),
                                             (1.70,1.38),(3.50,1.38),(7.72,1.26)]
            for (x,width) in windows {
                box(x,1.94,side*1.455,width+0.11,0.012,0.96,pale)
                box(x,1.99,side*1.464,width,0.008,0.86,ink)
                box(x,2.02,side*1.470,width-0.05,0.006,0.81,glass)
            }
            for x: Float in [-5.50,0,5.50] {
                box(x,0.78,side*1.454,1.55,0.013,2.22,green)
                box(x,1.70,side*1.463,1.55,0.009,1.29,cream)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.385,1.99,side*1.473,0.69,0.009,0.88,ink)
                    box(x+leaf*0.385,2.02,side*1.480,0.63,0.006,0.80,glass)
                }
                box(x,0.79,side*1.476,0.018,0.010,2.20,Map3DColor.shaded(green,0.80))
                box(x,0.77,side*1.477,1.56,0.009,0.035,grey)
            }
            let cabDoorX = cabSign * 8.48
            box(cabDoorX,0.81,side*1.457,0.75,0.013,2.17,green)
            box(cabDoorX,1.72,side*1.465,0.75,0.009,1.22,cream)
            box(cabDoorX,1.98,side*1.474,0.48,0.009,0.83,glass)
            box(cabDoorX-cabSign*0.23,1.31,side*1.478,0.042,0.012,0.08,ink)
        }

        // Cab: two independent windscreens, small route panel, low lamps and
        // central coupler. All front panels follow the rake of the shell.
        func frontX(_ height: Float) -> Float {
            cabSign * (9.65 - max(0,height-0.69)*0.056)
        }
        func panel(_ h0: Float,_ h1: Float,_ z0: Float,_ z1: Float,_ lift: Float,_ color: UInt32) {
            let p = [Map3DPoint(frontX(h0)+cabSign*lift,h0,z0),
                     Map3DPoint(frontX(h0)+cabSign*lift,h0,z1),
                     Map3DPoint(frontX(h1)+cabSign*lift,h1,z1),
                     Map3DPoint(frontX(h1)+cabSign*lift,h1,z0)]
            face(p,inside:centre,color:color)
        }
        panel(1.63,3.03,-1.29,1.29,0.010,cream)
        panel(0.88,1.04,-1.18,1.18,0.020,skirt)
        for side: Float in [-1,1] {
            let z0: Float = side < 0 ? -1.15 : 0.06
            let z1: Float = side < 0 ? -0.06 : 1.15
            panel(1.78,2.88,z0,z1,0.023,ink)
            panel(1.83,2.83,z0+0.04,z1-0.04,0.034,glass)
            box(frontX(1.30)+cabSign*0.05,1.26,side*0.93,0.03,0.30,0.16,Map3DPalette.tileWhite)
        }
        panel(3.14,3.32,-0.71,0.71,0.034,ink)
        box(frontX(0.85)+cabSign*0.08,0.56,0,0.23,0.47,0.45,ink)
        box(frontX(0.84)+cabSign*0.13,0.78,0,0.07,0.12,0.11,Map3DPalette.platformEdge)

        // Only the inward end has a short supported gangway face.
        box(-cabSign*9.67,0.81,0,0.085,2.27,2.54,ink)
        box(-cabSign*9.72,0.84,0,0.09,1.38,2.24,Map3DColor.shaded(ink,0.76))
        box(-cabSign*9.74,0.47,0,0.15,0.45,0.29,ink)

        // Shallow roof inspection covers seen in both oblique references.
        for x: Float in [-7.60,-5.25,-2.90,-0.55,1.80,4.15,6.50] {
            for z: Float in [-0.23,0.23] {
                box(x,3.628,z,0.45,0.26,0.018,Map3DPalette.roof)
            }
        }
    }
}
