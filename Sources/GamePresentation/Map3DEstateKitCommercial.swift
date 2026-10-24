import Foundation

extension StationKitBuilder {
    mutating func estateCommercial(_ p: Map3DEstateKit.Part) {
        switch p {
        case .foodCourtHall:
            estateBase(17,19)
            for z: Float in [-4,4] { estateBlock(-1,0.16,z,11,7.5,1);gable(-1,3.34,z,11.4,7.9,2.0,Self.estateRoof) }
            estatePorch(5.5,0.16,0,3,15,2.6)
            for z: Float in [-5,-2,2,5] { box(5.95,0.16,z,0.9,1.5,0.85,Map3DPalette.counters[1]) }
        case .coworkingAtrium:
            estateBase(16,16)
            for z: Float in [-4.5,4.5] { estateBlock(-1,0.16,z,10,4,3) }
            estateBlock(-4,0.16,0,4,5,3)
            estateBlock(2,0.16,0,4,5,1)
            estateBarrel(-1,9.34,0,10,5.5,1.4)
            // Central glazing is backed by a solid lobby / rear core.
            pane(4.02,0.4,0,3.8,2.3)
            for z: Float in [-2,2] { box(4,3.16,z,0.25,0.25,6.2,Self.estateGold) }
        case .gardenCenter:
            estateBase(17,18)
            estateBlock(-2,0.16,-3.5,8,7,1);gable(-2,3.34,-3.5,8.5,7.5,2.0,Self.estateRoof)
            box(1.8,0.16,3.8,8,6.5,2.8,Self.white)
            gable(1.8,2.96,3.8,8.4,6.9,2.3,Self.estateRoof)
            for z: Float in [1.3,3,4.7,6.2] { pane(5.82,0.45,z,1.2,2.2) }
            for z: Float in [-5,-2,1,4] { estatePlanter(-6.7,0.16,z) }
        case .outletArcade:
            estateBase(17,21)
            for i in 0..<5 {
                let z=Float(i)*3.8-7.6,x=Float(i%2)*1.4-1
                estateBlock(x,0.16,z,8,3.6,1)
                gable(x,3.34,z,8.4,3.9,1.5,Self.estateRoof)
                estatePorch(x+4.4,0.16,z,1.4,3.6,2.6)
            }
        case .exhibitionHall:
            estateBase(20,21)
            estateBlock(-1,0.16,0,14,17,1)
            for i in 0..<4 {
                let z=Float(i)*4.25-6.375
                // Four capped asymmetric sawtooth prisms, resting on the wall slab.
                let a=[Map3DPoint(-8,3.34,z-2.12),Map3DPoint(-8,3.34,z+2.12),Map3DPoint(-8,6,z+2.12)]
                estatePrism(a,a.map { $0+Map3DPoint(14,0,0) },Self.estateRoof)
            }
            estatePorch(7,0.16,0,3,7,2.6)
        case .weddingBanquetHall:
            estateBase(19,21)
            estateBlock(-2,0.16,0,10,11,2)
            estateBarrel(-2,6.34,0,10.5,11.5,2.7)
            for z: Float in [-7,7] { estateBlock(1,0.16,z,8,3,1);gable(1,3.34,z,8.5,3.5,1.5,Self.estateGold) }
            estatePorch(4.6,0.16,0,3.5,8,4)
            pane(3.02,0.4,0,5.5,3.2)
        default: break
        }
    }
}
