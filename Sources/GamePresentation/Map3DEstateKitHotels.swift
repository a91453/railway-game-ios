import Foundation

extension StationKitBuilder {
    mutating func estateHotel(_ p: Map3DEstateKit.Part) {
        switch p {
        case .courtyardInn:
            estateBase(15,16)
            estateBlock(-4,0.16,0,4,13,2)
            for z: Float in [-5,5] { estateBlock(0,0.16,z,9,3,2) }
            estatePorch(2.5,0.16,0,4,7,2.8)
            for z: Float in [-2.8,2.8] { estatePlanter(0,0.16,z) }
        case .resortHotel:
            estateBase(17,19)
            // Tall rear room bar + low side wing around a real pool court.
            estateBlock(-3,0.16,0,6,16,4)
            estateBlock(2.3,0.16,-5.2,4.6,5.6,2)
            estateBlock(-3.5,12.34,-3,4,8,1)
            box(3.6,0.16,3.3,5.8,7.0,0.38,Map3DPalette.concrete)
            box(3.6,0.52,3.3,5.3,6.5,0.04,Map3DPalette.water)
            estatePorch(1.2,0.16,-1.6,2.8,1.6,2.6)
            for z: Float in [-5,-2,2,5] { estatePlanter(-0.6,12.34,z) }
        case .hotSpringInn:
            estateBase(16,18)
            for z: Float in [-5.8,5.8] { estateBlock(-1,0.16,z,10,4.2,2);gable(-1,6.34,z,10.5,4.7,1.8,Self.estateRoof) }
            estateBlock(-5,0.16,0,2,8,1)
            for z: Float in [-2.8,2.8] { estatePorch(-1,0.16,z,9,1.1,2.6) }
            box(0,0.16,0,4,3.8,0.35,Map3DPalette.concrete)
            box(0,0.49,0,3.6,3.4,0.03,Map3DPalette.water)
        case .towerHotel:
            estateBase(13,13);estateBlock(0,0.16,0,10,10,1)
            estateBlock(-1,3.34,0,7,7,6)
            estateBlock(-1,21.52,0,5,5,1)
            estateFrustum(-1,24.7,0,3.5,1.0,2,Self.estateGold,sides:4)
            estatePorch(5.2,0.16,0,2,5,2.6)
        case .capsuleHostel:
            estateBase(12,8);estateBlock(-1,0.16,0,7,5,3)
            estateBlock(-3.4,9.34,0,2.2,5,1)
            for i in 0..<9 { box(4.5-Float(i)*0.4,0.16,0,0.4,1.6,Float(i+1)*0.34,Map3DPalette.concrete) }
            estatePorch(3,0.16,0,1.4,2.8,3.2)
        case .motorInn:
            estateBase(14,18)
            for x: Float in [-4,3.7] { for z: Float in [-6,-2,2,6] { box(x,0.16,z,0.35,0.35,3,Self.estateGold) } }
            estateBlock(-1,3.16,0,7,15,1)
            box(3.2,3.16,0,1.6,15,0.18,Self.estateRoof)
            for z: Float in [-6,-3,0,3,6] { box(3.85,3.34,z,0.08,0.08,0.9,Self.steel) }
            beam(Map3DPoint(3.85,4.24,-7.5),Map3DPoint(3.85,4.24,7.5),0.08,Self.steel)
            for i in 0..<10 { box(5.8-Float(i)*0.35,0.16,-6,0.35,2.5,Float(i+1)*0.3,Map3DPalette.concrete) }
            for z: Float in [-5,-1,3] { box(0,0.165,z,7,0.07,0.015,Self.white) }
        default: break
        }
    }
}
