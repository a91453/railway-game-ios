import Foundation

extension StationKitBuilder {
    mutating func estateLeisure(_ p: Map3DEstateKit.Part) {
        switch p {
        case .themeParkGate:
            estateBase(7,15)
            for z: Float in [-5,5] {
                estateBlock(0,0.16,z,4,3.5,2)
                estateFrustum(0,6.3,z,2.5,0.18,2,Self.estateGold,sides:4)
                pane(2.02,0.4,z,1.6,1.8)
            }
            box(0,4.8,0,2.5,7,1.0,Self.estateGold)
            box(1.28,5.05,0,0.08,4,0.45,Self.ink)
            for z: Float in [-2.6,0,2.6] { box(0,0.16,z,0.8,0.14,0.8,Self.steel) }
        case .carouselPavilion:
            estateBase(8.2,8.2)
            cylinder(0,0.16,0,3.65,0.25,Self.estateGold,sides:16)
            cylinder(0,0.4,0,0.24,4,Self.estateGold)
            estateFrustum(0,3.5,0,3.8,0.15,1.25,Self.estateRoof,sides:8)
            for i in 0..<6 {
                let a=Float(i)*Float.pi/3,x=cosf(a)*3.1,z=sinf(a)*3.1
                cylinder(x,0.4,z,0.10,3.15,Self.estateGold,sides:8)
            }
            for i in 0..<4 {
                let a=Float(i)*Float.pi/2,x=cosf(a)*1.85,z=sinf(a)*1.85
                cylinder(x,0.4,z,0.045,3.15,Self.steel,sides:6)
                box(x,1.1,z,0.85,0.32,0.35,Self.white)
                box(x+0.37,1.32,z,0.23,0.28,0.55,Self.white)
                box(x,1.43,z,0.38,0.36,0.08,Self.estateGold)
                for dx: Float in [-0.28,0.28] { for dz: Float in [-0.1,0.1] { box(x+dx,0.8,z+dz,0.09,0.09,0.35,Self.white) } }
            }
        case .ferrisWheel:
            estateBase(7,12)
            for x: Float in [-2.5,2.5] { for z: Float in [-1.8,1.8] {
                box(x,0.16,z,0.9,0.9,0.35,Map3DPalette.concrete)
                civicTube(Map3DPoint(x,0.4,z),Map3DPoint(x>0 ? 0.60:-0.60,6.2,0),radius:0.16,color:Self.estateGold,sides:8)
            } }
            civicTube(Map3DPoint(-0.85,6.2,0),Map3DPoint(0.85,6.2,0),radius:0.22,color:Self.steel)
            for side: Float in [-0.28,0.28] {
                for i in 0..<24 {
                    let a=Float(i)*Float.pi/12,b=Float(i+1)*Float.pi/12
                    civicTube(Map3DPoint(side,6.2+sinf(a)*4.7,cosf(a)*4.7),Map3DPoint(side,6.2+sinf(b)*4.7,cosf(b)*4.7),radius:0.09,color:Self.estateRoof,sides:6)
                }
                for i in 0..<8 {
                    let a=Float(i)*Float.pi/4
                    civicTube(Map3DPoint(side,6.2,0),Map3DPoint(side,6.2+sinf(a)*4.7,cosf(a)*4.7),radius:0.045,color:Self.steel,sides:6)
                }
            }
            for i in 0..<8 {
                let a=Float(i)*Float.pi/4,y=6.2+sinf(a)*4.7,z=cosf(a)*4.7
                civicTube(Map3DPoint(-0.28,y,z),Map3DPoint(1.05,y,z),radius:0.065,color:Self.steel,sides:6)
                box(1.05,y-0.48,z,0.08,0.08,0.5,Self.steel)
                box(1.05,y-1.12,z,0.9,0.95,0.7,Self.estateGold)
                pane(1.51,y-0.94,z,0.63,0.35)
                box(1.05,y-0.44,z,1.0,1.05,0.10,Self.estateRoof)
            }
        case .waterPlayHall:
            estateBase(14,16);estateBlock(-1,0.16,0,10,13,1)
            estateBarrel(-1,3.3,0,10.4,13.4,3)
            estateBlock(4.6,0.16,-3.3,3,5,1)
            estatePorch(5.2,0.16,2.5,2.6,4,2.6)
            for z: Float in [-5,-2.5,0,2.5,5] { pane(4.02,0.45,z,1.7,2.25) }
        case .planetarium:
            estateBase(13,13)
            cylinder(-1,0.16,0,5,2.8,Self.white,sides:24)
            // Nested closed frusta approximate a hemispherical dome, all rings joined.
            for i in 0..<8 {
                let a=Float(i)*Float.pi/16,b=Float(i+1)*Float.pi/16
                estateFrustum(-1,2.96+sinf(a)*4.5,0,cosf(a)*5,max(0.02,cosf(b)*5),(sinf(b)-sinf(a))*4.5,Self.estateRoof,sides:24)
            }
            estateBlock(4,0.16,0,3,4,1);pane(5.52,0.3,0,2.5,2.4)
        case .fantasyCastle:
            estateBase(13,15);estateBlock(-0.5,0.16,0,7,7,2)
            for x: Float in [-3.5,3.5] { for z: Float in [-5,5] {
                cylinder(x,0.16,z,1.35,7,Self.white,sides:8)
                estateFrustum(x,7.16,z,1.7,0.10,2.8,Self.estateGold,sides:8)
                box(x+1.30,4,z,0.15,0.6,1.1,Self.glass)
            } }
            estateFrustum(-0.5,6.35,0,4.5,0.15,3.4,Self.estateRoof,sides:4)
            pane(3.02,0.3,0,2.8,3.2);estatePorch(4,0.16,0,2.4,4,3.5)
        default: break
        }
    }
}
