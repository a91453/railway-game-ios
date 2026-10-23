import Foundation

extension StationKitBuilder {
    mutating func recreationSport(_ p: Map3DRecreationKit.Part) {
        switch p {
        case .climbingWall:
            for z: Float in [-1.3,1.3] {
                box(-1.8,0,z,0.4,0.4,0.12,Self.steel)
                box(-0.4,0,z,0.5,0.4,0.20,Self.steel)
                civicTube(.init(-1.8,0.08,z),.init(0.50,4.40,z),radius:0.075,color:Self.steel,sides:8)
            }
            let a=[Map3DPoint(-0.5,0.16,-1.75),.init(0.5,4.5,-1.75),.init(0.7,4.5,-1.75),.init(-0.3,0.16,-1.75)]
            recreationPrism(a,a.map { $0+Map3DPoint(0,0,3.5) },Self.white)
            for i in 0..<7 { for z: Float in [-1.1,0,1.1] {
                let y=0.6+Float(i)*0.55,x = -0.3+(y-0.16)/4.34
                box(x+0.04,y,z+Float(i%2)*0.15,0.16,0.22,0.12,i%2==0 ? Self.recreationGold:Self.recreationGreen)
            } }
        case .boxingRing:
            for x: Float in [-2.2,2.2] { for z: Float in [-2.2,2.2] { box(x,0,z,0.35,0.35,0.45,Self.steel) } }
            box(0,0.42,0,5.2,5.2,0.16,Self.recreationGold);box(0,0.58,0,4.9,4.9,0.06,Self.recreationGreen)
            for x: Float in [-2.4,2.4] { for z: Float in [-2.4,2.4] { box(x,0.42,z,0.16,0.16,1.7,Self.white) } }
            for y: Float in [1.0,1.4,1.8] {
                for sign: Float in [-1,1] {
                    civicTube(.init(-2.4,y,sign*2.4),.init(2.4,y,sign*2.4),radius:0.026,color:Self.white,sides:6)
                    civicTube(.init(sign*2.4,y,-2.4),.init(sign*2.4,y,2.4),radius:0.026,color:Self.white,sides:6)
                }
            }
            box(3,0,0,0.8,1.4,0.2,Map3DPalette.concrete);box(2.8,0.2,0,0.8,1.4,0.2,Map3DPalette.concrete)
        case .bowlingLane:
            box(0,0,0.30,8.4,3.0,0.12,Map3DPalette.counters[1])
            box(0,0.12,0,8,1.6,0.025,Map3DPalette.forecourt)
            for z: Float in [-0.95,0.95] { box(0,0.12,z,8,0.20,0.03,Self.ink) }
            box(-4,0.12,0,0.2,2.2,0.8,Self.white)
            for row in 0..<4 { for j in 0...row {
                let x = -2.5-Float(row)*0.26,z=(Float(j)-Float(row)/2)*0.24
                recreationFrustum(x,0.145,z,0.06,0.09,0.18,Self.white,sides:8)
                recreationFrustum(x,0.325,z,0.09,0.035,0.14,Self.white,sides:8)
                cylinder(x,0.465,z,0.035,0.08,Self.recreationGold,sides:8)
                recreationFrustum(x,0.545,z,0.055,0.025,0.08,Self.white,sides:8)
            } }
            for x: Float in [-2.8,2.8] { box(x,0.12,1.4,0.15,0.15,0.40,Self.steel) }
            for z: Float in [1.28,1.52] { civicTube(.init(-3.3,0.50,z),.init(3.3,0.50,z),radius:0.035,color:Self.steel,sides:8) }
            for x: Float in [-3.3,3.3] { civicTube(.init(x,0.5,1.28),.init(x,0.5,1.52),radius:0.035,color:Self.steel,sides:8) }
            recreationBall(2.0,0.68,1.4,0.20)
        case .umpireChair:
            for z: Float in [-0.4,0.4] { for x: Float in [-0.5,0.5] {
                box(x,0,z,0.20,0.18,0.08,Self.steel)
                civicTube(.init(x,0.06,z),.init(-0.1,1.50,z),radius:0.045,color:Self.steel,sides:8)
            } }
            box(-0.1,1.5,0,0.65,0.90,0.12,Self.recreationGold)
            box(-0.38,1.62,0,0.10,0.90,0.60,Self.recreationGold)
            recreationLadder(.init(0.5,0.08,0),.init(-0.1,1.5,0),0.70,5)
            for z: Float in [-0.43,0.43] {
                box(0.12,1.62,z,0.07,0.07,0.30,Self.steel)
                civicTube(.init(-0.38,1.92,z),.init(0.25,1.92,z),radius:0.03,color:Self.steel,sides:8)
            }
        case .ballCart:
            for x: Float in [-0.48,0.48] { for z: Float in [-0.34,0.34] { recreationWheel(x,0.12,z,0.12,0.10,Self.ink) } }
            box(0,0.22,0,1.2,0.8,0.15,Self.white)
            for x: Float in [-0.55,0.55] { for z: Float in [-0.35,0.35] { box(x,0.30,z,0.06,0.06,0.9,Self.steel) } }
            for y: Float in [0.60,0.9,1.2] {
                for z: Float in [-0.35,0.35] { civicTube(.init(-0.55,y,z),.init(0.55,y,z),radius:0.02,color:Self.steel,sides:6) }
                for x: Float in [-0.55,0.55] { civicTube(.init(x,y,-0.35),.init(x,y,0.35),radius:0.02,color:Self.steel,sides:6) }
            }
            for x: Float in [-0.35,0,0.35] { for z: Float in [-0.35,0.35] { box(x,0.37,z,0.025,0.025,0.83,Self.steel) } }
            for x: Float in [-0.30,0.30] { recreationBall(x,0.57,0.12,0.20) }
        case .lockerBank:
            box(0.4,0,0,1.9,2.3,0.08,Map3DPalette.forecourt)
            for z: Float in [-0.7,0,0.7] {
                box(0,0.08,z,0.65,0.65,1.9,Self.white)
                box(0.335,0.20,z,0.04,0.57,1.65,Self.recreationGold)
                box(0.37,1.0,z+0.17,0.05,0.06,0.18,Self.steel)
                for y: Float in [0.4,0.48,1.65,1.73] { box(0.36,y,z,0.015,0.38,0.02,Self.ink) }
            }
            for z: Float in [-0.8,0.8] { box(0.85,0.08,z,0.12,0.12,0.4,Self.steel) }
            box(0.85,0.48,0,0.65,2.1,0.10,Map3DPalette.counters[1])
        default: break
        }
    }
}
