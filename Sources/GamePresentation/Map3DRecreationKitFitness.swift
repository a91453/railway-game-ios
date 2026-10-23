import Foundation

extension StationKitBuilder {
    mutating func recreationFitness(_ p: Map3DRecreationKit.Part) {
        switch p {
        case .treadmill:
            for x: Float in [-0.85,0.85] { for z: Float in [-0.40,0.40] { box(x,0,z,0.22,0.18,0.16,Self.ink) } }
            box(0,0.12,0,2.1,0.95,0.18,Self.white);box(-0.1,0.30,0,1.65,0.70,0.025,Self.ink)
            for z: Float in [-0.43,0.43] {
                box(0.75,0.15,z,0.08,0.08,1.17,Self.steel)
                civicTube(.init(0.75,1.15,z),.init(-0.3,1.05,z),radius:0.035,color:Self.steel,sides:8)
            }
            box(0.75,1.28,0,0.32,0.95,0.17,Self.recreationGold)
            pane(0.915,1.30,0,0.60,0.065)
        case .exerciseBike:
            for x: Float in [-0.65,0.65] { box(x,0,0,0.3,0.8,0.10,Self.ink) }
            box(0,0.08,0,1.5,0.16,0.18,Self.steel)
            recreationWheel(-0.4,0.5,0,0.34,0.20,Self.white)
            for (a,b) in [(Map3DPoint(-0.4,0.5,0),Map3DPoint(0.2,0.45,0)),(.init(-0.4,0.2,0),.init(-0.25,0.91,0)),(.init(0.65,0.2,0),.init(0.65,1.2,0)),(.init(-0.25,0.75,0),.init(0.65,0.5,0))] { civicTube(a,b,radius:0.055,color:Self.recreationGold,sides:8) }
            box(-0.25,0.91,0,0.5,0.4,0.1,Self.ink)
            civicTube(.init(0.65,1.2,-0.32),.init(0.65,1.2,0.32),radius:0.04,color:Self.ink,sides:8)
            civicTube(.init(0.2,0.45,-0.3),.init(0.2,0.45,0.3),radius:0.035,color:Self.steel,sides:8)
            for sign: Float in [-1,1] {
                civicTube(.init(0.2,0.45,sign*0.3),.init(0.36,0.22,sign*0.3),radius:0.03,color:Self.steel,sides:8)
                box(0.36,0.18,sign*0.3,0.22,0.17,0.08,Self.ink)
            }
        case .rowingErgometer:
            for x: Float in [-1.1,1.1] { box(x,0,0,0.22,0.7,0.26,Self.steel) }
            box(0,0.25,0,2.6,0.15,0.12,Self.white);box(-0.3,0.37,0,0.40,0.50,0.12,Self.ink)
            civicTube(.init(1.05,0.24,0),.init(1.05,0.65,0),radius:0.08,color:Self.steel,sides:8)
            recreationWheel(1.05,0.65,0,0.42,0.28,Self.recreationGold)
            civicTube(.init(0.85,0.80,0),.init(0.1,0.80,0),radius:0.018,color:Self.ink,sides:6)
            civicTube(.init(0.1,0.80,-0.32),.init(0.1,0.80,0.32),radius:0.035,color:Self.ink,sides:8)
            for z: Float in [-0.25,0.25] { box(0.25,0.27,z,0.42,0.26,0.12,Self.ink) }
        case .adjustableBench:
            for x: Float in [-0.7,0.7] {
                box(x,0,0,0.22,0.8,0.10,Self.steel)
                civicTube(.init(x,0.08,-0.3),.init(x,0.48,0),radius:0.045,color:Self.steel,sides:8)
                civicTube(.init(x,0.08,0.3),.init(x,0.48,0),radius:0.045,color:Self.steel,sides:8)
            }
            box(0,0.40,0,1.7,0.10,0.10,Self.steel)
            box(0.5,0.5,0,0.6,0.5,0.10,Self.recreationGreen)
            recreationPanel(.init(-0.85,0.90,0),.init(0.2,0.60,0),0.5,0.10,Self.recreationGreen)
            civicTube(.init(-0.55,0.44,0),.init(-0.55,0.72,0),radius:0.05,color:Self.steel,sides:8)
            recreationWheel(0.2,0.53,0,0.065,0.6,Self.steel)
        case .dumbbellRack:
            for x: Float in [-0.8,0.8] { for sign: Float in [-1,1] {
                box(x,0,sign*0.32,0.25,0.22,0.10,Self.steel)
                civicTube(.init(x,0.08,sign*0.32),.init(x,1.15,sign*0.20),radius:0.045,color:Self.steel,sides:8)
            } }
            for y: Float in [0.48,0.82] {
                box(0,y,0,1.9,0.55,0.08,Self.white)
                for x: Float in [-0.6,0,0.6] {
                    let h=y+0.19
                    recreationWheel(x,h,0,0.035,0.40,Self.steel)
                    for z: Float in [-0.16,0.16] { recreationWheel(x,h,z,0.11,0.08,Self.ink) }
                }
            }
        case .plateTree:
            box(0,0,0,1.1,0.25,0.12,Self.steel);box(0,0,0,0.25,1.1,0.12,Self.steel)
            box(0,0.10,0,0.12,0.12,1.35,Self.white)
            for y: Float in [0.4,0.8,1.2] {
                recreationWheel(0,y,0,0.035,0.9,Self.steel)
                for z: Float in [-0.25,0.25] { recreationWheel(0,y,z,0.20,0.10,Self.ink) }
            }
        default: break
        }
    }
}
