import Foundation

extension StationKitBuilder {
    mutating func recreationAquatic(_ p: Map3DRecreationKit.Part) {
        switch p {
        case .trainingPool:
            box(0,0,0,14,9,0.18,Self.white)
            for x: Float in [-6.5,6.5] { box(x,0.18,0,1,9,0.9,Self.white) }
            for z: Float in [-4,4] { box(0,0.18,z,12,1,0.9,Self.white) }
            box(0,0.18,0,12,7,0.6,Map3DPalette.water)
            for z: Float in [-1.7,0,1.7] { civicTube(.init(-6.02,0.82,z),.init(6.02,0.82,z),radius:0.025,color:Self.recreationGold,sides:6) }
            for x: Float in [-6.5,6.5] { for z: Float in [-2,0,2] { box(x,1.08,z,0.35,0.07,0.01,Self.ink) } }
        case .divingPlatform:
            for x: Float in [-1,1] { for z: Float in [-0.65,0.65] {
                box(x,0,z,0.45,0.40,0.12,Map3DPalette.concrete)
                box(x,0.10,z,0.18,0.18,2.52,Self.steel)
            } }
            box(0,2.62,0,2.4,1.8,0.16,Self.white)
            box(1.6,2.78,0,2.0,0.55,0.12,Self.recreationGreen)
            for x: Float in [-1.1,0.9] { for z: Float in [-0.82,0.82] { box(x,2.78,z,0.07,0.07,0.8,Self.steel) } }
            for z: Float in [-0.82,0.82] { civicTube(.init(-1.1,3.58,z),.init(0.9,3.58,z),radius:0.035,color:Self.steel,sides:8) }
            civicTube(.init(-1.1,3.58,-0.82),.init(-1.1,3.58,0.82),radius:0.035,color:Self.steel,sides:8)
            for z: Float in [-0.6,0.6] { box(-2.5,0,z,0.3,0.25,0.12,Map3DPalette.concrete) }
            recreationLadder(.init(-2.5,0.10,0),.init(-1,2.68,0),1.2,8)
        case .startBlock:
            box(0,0,0,0.7,0.8,0.08,Self.white)
            for x: Float in [-0.18,0.18] { box(x,0.08,0,0.12,0.50,0.62,Self.steel) }
            recreationPanel(.init(-0.5,0.78,0),.init(0.5,0.68,0),0.85,0.12,Self.recreationGreen)
        case .lifeguardSeat:
            box(0.1,0,0,2.5,1.6,0.10,Map3DPalette.forecourt)
            box(-0.45,0.10,0,0.18,0.18,2.0,Self.steel)
            for z: Float in [-0.5,0.5] { civicTube(.init(0.70,0.10,z),.init(-0.40,1.80,z*0.8),radius:0.055,color:Self.steel,sides:8) }
            box(0,2.1,0,0.90,1.10,0.10,Self.recreationGold);box(-0.4,2.2,0,0.10,1.10,0.65,Self.recreationGold)
            box(0.7,1.5,0,0.6,1.1,0.10,Self.white)
            for z: Float in [-0.45,0.45] { box(0.7,0.10,z,0.07,0.07,1.45,Self.steel) }
            recreationLadder(.init(1.1,0.10,0),.init(0.5,1.55,0),0.85,5)
            for z: Float in [-0.52,0.52] { box(0.30,2.2,z,0.07,0.07,0.30,Self.steel);civicTube(.init(-0.4,2.5,z),.init(0.45,2.5,z),radius:0.03,color:Self.steel,sides:8) }
        case .poolLaneReel:
            for z: Float in [-1,1] { for x: Float in [-0.6,0.6] {
                box(x,0,z,0.35,0.3,0.10,Self.steel)
                civicTube(.init(x,0.08,z),.init(0,0.85,z),radius:0.06,color:Self.steel,sides:8)
            } }
            recreationWheel(0,0.85,0,0.07,2.44,Self.steel)
            recreationWheel(0,0.85,0,0.55,1.4,Self.recreationGreen)
            for z: Float in [-0.75,0.75] { recreationWheel(0,0.85,z,0.67,0.10,Self.white) }
            for z: Float in [-0.5,-0.25,0,0.25,0.5] { recreationWheel(0,0.85,z,0.56,0.045,Self.recreationGold) }
            civicTube(.init(0,0.85,1.2),.init(0.3,0.85,1.2),radius:0.04,color:Self.steel,sides:8)
            civicTube(.init(0.3,0.85,1.2),.init(0.3,0.85,1.4),radius:0.05,color:Self.ink,sides:8)
        case .showerArch:
            box(0,0,0,2,2,0.08,Map3DPalette.forecourt)
            for z: Float in [-0.7,0.7] { cylinder(0,0.08,z,0.06,2.4,Self.steel,sides:8) }
            civicTube(.init(0,2.45,-0.7),.init(0,2.45,0.7),radius:0.06,color:Self.steel,sides:8)
            civicTube(.init(0,2.45,0),.init(0.3,2.45,0),radius:0.04,color:Self.steel,sides:8)
            cylinder(0.3,2.28,0,0.035,0.17,Self.steel,sides:8)
            cylinder(0.3,2.24,0,0.18,0.06,Self.white,sides:12)
        default: break
        }
    }
}
