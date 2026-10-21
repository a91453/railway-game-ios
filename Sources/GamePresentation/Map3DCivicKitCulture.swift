import Foundation

extension StationKitBuilder {
    mutating func civicCulture(_ p: Map3DCivicKit.Part) {
        let red=Self.civicRed,wood=Self.civicWood,white=Self.white,steel=Self.steel
        switch p {
        case .templeGate:
            box(0,0,0,4,10,0.25,Map3DPalette.plaza)
            for x: Float in [-0.9,0.9] { for z: Float in [-3.5,0,3.5] {
                box(x,0.25,z,0.55,0.55,0.30,Map3DPalette.concrete);cylinder(x,0.55,z,0.18,3.4,red)
            } }
            box(0,3.7,0,2.3,8.0,0.3,red)
            civicTempleRoof(0,4,0,length:3,width:9,rise:1.5)
            civicBoard(1.19,3.7,1.75,width:2.3,height:0.3,color:Map3DPalette.playerRoof)
        case .templeHall,.templeSideHall:
            let big=p == .templeHall,l: Float=big ? 10 : 7,w: Float=big ? 12 : 7
            box(0,0,0,l+2,w+2,0.35,Map3DPalette.plaza)
            box(-0.7,0.35,0,l-1.6,w-1,3.4,Map3DPalette.playerRoof)
            for z in stride(from:-w/2+0.7,through:w/2-0.6,by:2.7) {
                box(l/2-0.3,0.35,z,0.5,0.5,0.30,Map3DPalette.concrete)
                cylinder(l/2-0.3,0.65,z,0.17,3.0,red)
            }
            box(0,3.65,0,l,w,0.22,red);civicTempleRoof(0,3.87,0,length:l,width:w,rise:big ? 2.0 : 1.45)
            for z: Float in [-1.1,1.1] { box(l/2-1.48,0.35,z,0.04,1.4,2.6,red) }
            civicBoard(l/2-1.46,2.98,0,width:3.0,height:0.5,color:Map3DPalette.playerRoof)
            box(l/2+0.65,0,0,1.3,3.5,0.18,Map3DPalette.concrete)
        case .incenseBurner:
            for i in 0..<3 { let a=Float(i)*2*Float.pi/3
                cylinder(cosf(a)*0.35,0,sinf(a)*0.35,0.09,0.4,steel)
            }
            cylinder(0,0.30,0,0.52,0.5,steel,sides:16);cylinder(0,0.80,0,0.55,0.07,wood,sides:16)
            cylinder(0,0.87,0,0.44,0.02,Map3DPalette.ballast,sides:16)
            for z: Float in [-0.2,0,0.2] { box(0,0.89,z,0.014,0.014,0.45,red) }
            for z: Float in [-0.62,0.62] { box(0,0.57,z,0.10,0.3,0.07,steel) }
        case .lanternString:
            for z: Float in [-2.7,2.7] { box(0,0,z,0.45,0.45,0.12,Map3DPalette.concrete);cylinder(0,0.12,z,0.05,3.3,steel) }
            beam(Map3DPoint(0,3.4,-2.7),Map3DPoint(0,3.4,2.7),0.035,steel)
            for i in -2...2 { let z=Float(i)*0.95
                cylinder(0,3.05,z,0.015,0.35,steel);cylinder(0,2.57,z,0.23,0.48,red)
                cylinder(0,2.54,z,0.12,0.04,Map3DPalette.playerRoof);cylinder(0,3.05,z,0.12,0.04,Map3DPalette.playerRoof)
                cylinder(0,2.37,z,0.025,0.17,red)
            }
        case .templeWall:
            box(0,0,0,0.40,4,0.25,Map3DPalette.concrete);box(0,0.25,0,0.28,4,1.5,Map3DPalette.playerRoof)
            for z: Float in [-1.85,1.85] { box(0,0.25,z,0.45,0.3,1.75,red) }
            gable(0,2.0,0,0.5,4,0.30,Map3DPalette.templeRoof)
            box(0.15,0.75,0,0.025,1.35,0.55,red)
        case .offeringTable:
            civicLegs(0,0,0,length:0.5,width:1.5,height:0.95,color:red);box(0,0.95,0,0.75,1.8,0.09,wood)
            box(0.28,0.62,0,0.08,1.6,0.28,red)
            for z: Float in [-0.5,0,0.5] { cylinder(0,1.04,z,0.17,0.04,white);cylinder(0,1.08,z,0.09,0.12,Map3DPalette.playerRoof) }
        case .marketStall:
            civicLegs(0,0,0,length:0.8,width:1.8,height:0.85,color:steel);box(0,0.85,0,1,2.05,0.08,wood)
            for x: Float in [-0.45,0.45] { for z: Float in [-1,1] { box(x,0,z,0.06,0.06,2.2,steel) } }
            gable(0,2.2,0,1.1,2.2,0.4,Map3DPalette.canopy)
            for z: Float in [-0.65,0,0.65] { box(0,0.93,z,0.65,0.5,0.08,Map3DPalette.playerRoof);for x: Float in [-0.17,0.12] { cylinder(x,1.01,z,0.10,0.13,Self.civicGreen) } }
        case .produceCart,.snackCart:
            let snack=p == .snackCart
            for z: Float in [-0.57,0.57] { civicTube(Map3DPoint(0,0.22,z-0.05),Map3DPoint(0,0.22,z+0.05),radius:0.22,color:Self.ink) }
            box(0,0.30,0,1.2,1.1,0.55,snack ? white : wood);box(0,0.85,0,1.3,1.2,0.07,steel)
            for z: Float in [-0.46,0.46] { box(-0.55,0,z,0.05,0.05,0.35,steel) }
            if snack {
                box(-0.44,0.92,0,0.12,1.0,0.65,white)
                for z: Float in [-0.45,0.45] { box(0,0.92,z,1.1,0.08,0.65,white) }
                box(0,1.57,0,1.2,1.1,0.08,red);cylinder(0.25,0.92,0,0.23,0.30,steel)
                cylinder(0.25,1.22,0,0.25,0.04,Self.ink)
            } else {
                for x: Float in [-0.30,0.25] { for z: Float in [-0.3,0.3] { box(x,0.92,z,0.44,0.46,0.07,Map3DPalette.playerRoof);cylinder(x,0.99,z,0.17,0.18,Self.civicGreen) } }
                beam(Map3DPoint(-0.55,0.8,0.4),Map3DPoint(-1.0,0.9,0.4),0.045,steel)
            }
        case .marketCanopy:
            for x: Float in [-1.4,1.4] { for z: Float in [-3,0,3] { box(x,0,z,0.12,0.12,2.8,steel) } }
            gable(0,2.8,0,3.0,6.4,0.55,Map3DPalette.canopy)
            for x: Float in [-1.4,1.4] { box(x,2.65,0,0.08,6.4,0.15,steel) }
        case .umbrellaTable:
            cylinder(0,0,0,0.3,0.07,steel);cylinder(0,0.07,0,0.04,2.45,steel)
            cylinder(0,0.75,0,0.7,0.07,wood,sides:24)
            let center=Map3DPoint(0,2.45,0),bottom=Map3DPoint(0,2.39,0)
            for i in 0..<12 { let a=Float(i)*2*Float.pi/12,b=Float(i+1)*2*Float.pi/12
                let p=Map3DPoint(cosf(a)*1.2,2.08,sinf(a)*1.2),q=Map3DPoint(cosf(b)*1.2,2.08,sinf(b)*1.2)
                face([center,p,q],inside:Map3DPoint(0,2.2,0),color:i%2==0 ? white : red)
                face([bottom,q-Map3DPoint(0,0.04,0),p-Map3DPoint(0,0.04,0)],inside:Map3DPoint(0,2.4,0),color:white)
                face([p,p-Map3DPoint(0,0.04,0),q-Map3DPoint(0,0.04,0),q],inside:Map3DPoint(0,2.2,0),color:red)
            }
            for z: Float in [-0.95,0.95] { civicLegs(0,0,z,length:0.3,width:0.3,height:0.45);cylinder(0,0.45,z,0.25,0.06,wood) }
        default: break
        }
    }
}
