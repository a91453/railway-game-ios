import Foundation

extension StationKitBuilder {
    mutating func estateResidential(_ p: Map3DEstateKit.Part) {
        switch p {
        case .skybridgeResidences:
            estateBase(15,19)
            for z: Float in [-6,6] { estateBlock(-1,0.16,z,8,5,6) }
            estateBlock(-1,9.16,0,3.5,7.1,1)
            for z: Float in [-6,6] { estatePorch(3.5,0.16,z,2,3,2.6) }
        case .terracedCondominium:
            estateBase(17,17)
            for i in 0..<5 {
                estateBlock(-Float(i),0.16+Float(i)*3,0,14-Float(i)*2,14,1)
                if i<4 { for z: Float in [-5,-2,2,5] { estatePlanter(6.3-Float(i)*2,3.34+Float(i)*3,z) } }
            }
        case .atriumApartments:
            estateBase(17,17)
            for x: Float in [-5.5,5.5] { estateBlock(x,0.16,0,3,14,4) }
            for z: Float in [-5.5,5.5] { estateBlock(0,0.16,z,8,3,4) }
            estatePlanter(0,0.16,0);estatePorch(7.4,0.16,0,1.6,3,2.6)
        case .maisonetteRow:
            estateBase(15,19)
            for i in 0..<4 {
                let z=Float(i)*4.1-6.15,x=Float(i%2)*1.6-0.8
                estateBlock(x,0.16,z,8,3.9,2)
                estateBlock(x-1.4,6.34,z,4.8,3.9,1)
                gable(x-1.4,9.52,z,5.2,4.1,1.1,Self.estateRoof)
                estatePorch(x+4.4,0.16,z,1.4,2.1,2.6)
            }
        case .pilotisResidence:
            estateBase(15,15)
            for x: Float in [-5,0,5] { for z: Float in [-5,0,5] { box(x,0.16,z,0.45,0.45,3,Self.estateGold) } }
            estateBlock(0,3.16,0,11,11,3)
            estateBlock(-3.5,0.16,-3.5,3,3,1)
            for z: Float in [-4,0,4] { estatePlanter(3,0.16,z) }
        case .roofGardenVilla:
            estateBase(15,15);estateBlock(-2,0.16,0,6,11,2);estateBlock(3,0.16,-3,4,5,1)
            for z: Float in [-4,-1,2,4] { estatePlanter(-2,6.34,z) }
            estatePorch(-2,6.34,0,4.5,5,2.2)
            // Roof pergola has four posts, including rear supports.
            for z: Float in [-2.36,2.36] { box(-4.11,6.34,z,0.22,0.22,2.2,Self.estateGold) }
            estatePorch(3,0.16,1.4,4,4,2.6)
        default: break
        }
    }
}
