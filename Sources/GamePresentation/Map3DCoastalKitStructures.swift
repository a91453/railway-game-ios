import Foundation

extension StationKitBuilder {
    mutating func coastalStructure(_ part: Map3DCoastalKit.Part) {
        let wood=Self.coastalWood,blue=Self.coastalBlue,sand=Self.coastalSand,white=Self.white,steel=Self.steel
        switch part {
        case .beaconTower:
            // Short broad octagonal tower with an offset service vestibule;
            // no striped cylinder, cottage, rocky base or animated light beam.
            cylinder(0,0,0,radius:1.35,height:0.22,color:Map3DPalette.granite,sides:8)
            coastalFrustum(0,0.22,0,0.95,0.70,3.4,white,sides:8)
            cylinder(0,3.55,0,radius:1.0,height:0.18,color:blue,sides:8)
            cylinder(0,3.73,0,radius:0.45,height:0.88,color:white,sides:8)
            cylinder(0,3.73,0,radius:0.53,height:0.88,color:Self.glass,sides:8)
            for i in 0..<8 { let a=Float(i)*Float.pi/4
                box(cosf(a)*0.52,3.73,sinf(a)*0.52,0.065,0.065,0.88,steel)
                box(cosf(a)*0.92,3.73,sinf(a)*0.92,0.045,0.045,0.65,steel)
            }
            coastalRing(Map3DPoint(0,4.37,0),radius:0.92,tube:0.035,color:steel,segments:8)
            coastalFrustum(0,4.58,0,0.72,0.16,0.42,blue,sides:8)
            cylinder(0,4.98,0,radius:0.055,height:0.32,color:steel,sides:8)
            box(0.86,0.22,0,0.70,0.85,1.60,white);pane(1.215,0.23,0,0.5,1.3)
            for y: Float in [1.6,2.6] { pane(0.84-(y-1.6)*0.073,y,0,0.25,0.4) }
        case .coastShelter:
            box(0,0,0,4.8,3.8,0.12,sand)
            for x: Float in [-1.9,1.9] { for z: Float in [-1.4,1.4] { box(x,0.12,z,0.16,0.16,2.48,steel) } }
            box(0,2.52,0,4.1,3.1,0.16,steel);gable(0,2.68,0,4.1,3.1,0.55,blue)
            box(-2,0.12,0,0.12,2.9,1.2,white)
            bench(-1.55,0.12,0,back:false)
        case .lifeguardTower:
            for x: Float in [-1,1] { for z: Float in [-1,1] {
                box(x,0,z,0.28,0.28,0.12,Map3DPalette.concrete)
                beam(Map3DPoint(x,0.08,z),Map3DPoint(x*0.82,2,z*0.82),0.15,wood)
            } }
            for z: Float in [-0.9,0.9] {
                beam(Map3DPoint(-0.95,0.2,z),Map3DPoint(0.85,1.95,z),0.10,white)
                beam(Map3DPoint(0.95,0.2,z),Map3DPoint(-0.85,1.95,z),0.10,white)
            }
            box(0,1.96,0,2.2,2.2,0.15,wood)
            for x: Float in [-0.95,0.95] { for z: Float in [-0.95,0.95] { box(x,2.1,z,0.12,0.12,1.85,white) } }
            box(-0.98,2.1,0,0.10,2,0.85,blue)
            for sign: Float in [-1,1] { box(0,2.1,sign*0.98,2,0.10,0.65,blue);box(0,3.05,sign*0.98,2,0.07,0.07,white) }
            gable(0,3.95,0,2.2,2.2,0.55,blue)
            for z: Float in [-0.42,0.42] { beam(Map3DPoint(2.1,0.04,z),Map3DPoint(0.9,2.12,z),0.08,steel) }
            for i in 0..<7 { let t=Float(i)/6;box(2.1-1.2*t,0.08+2.0*t,0,0.22,0.92,0.07,wood) }
        case .boatWorkshop:
            box(0,0,0,7.5,5.5,0.15,Map3DPalette.concrete)
            box(-3.2,0.15,0,0.18,4.8,2.85,white)
            for z: Float in [-2.4,2.4] { box(0,0.15,z,6.4,0.16,2.85,Map3DPalette.shedWalls[0]) }
            box(3.2,2.5,0,0.18,4.8,0.5,white)
            for z: Float in [-2.3,2.3] { box(3.2,0.15,z,0.20,0.2,2.85,steel) }
            gable(0,3.0,0,6.6,4.9,0.8,blue)
            // Closed backed window on the actual rear wall, facing outwards.
            box(-3.30,1.3,0,0.04,1.8,0.8,Self.glass)
            box(-2.5,0.15,-1.6,0.8,1.1,0.9,wood)
            for z: Float in [-1,1] { box(0,0.15,z,4.8,0.2,0.15,steel) }
        case .auctionShelter:
            box(0,0,0,7.8,5.8,0.12,Map3DPalette.concrete)
            for x: Float in [-3.2,0,3.2] { for z: Float in [-2.4,2.4] { box(x,0.12,z,0.18,0.18,2.8,steel) } }
            for z: Float in [-2.4,2.4] { box(0,2.78,z,6.7,0.2,0.22,steel) }
            gable(0,3,0,6.8,5.0,0.6,Map3DPalette.tinRoofs[2])
            box(-3.25,0.12,0,0.12,4.8,1.2,white)
            for z: Float in [-2.6,2.6] { box(0,0.12,z,7,0.12,0.04,steel) }
        case .slipway:
            let p=[Map3DPoint(-3,0,-1.5),Map3DPoint(3,0,-1.5),Map3DPoint(3,0.12,-1.5),Map3DPoint(-3,1.2,-1.5)]
            coastalPrism(p,p.map { $0+Map3DPoint(0,0,3) },Map3DPalette.concrete)
            for z: Float in [-1.1,1.1] { beam(Map3DPoint(-2.95,1.21,z),Map3DPoint(2.95,0.15,z),0.06,steel) }
            for i in 0..<12 { let x=Float(i)*0.45-2.5;box(x,0.66-x*0.18,0,0.08,2,0.02,white) }
        case .seawallStairs:
            stairs(0,0,0,run:3.6,width:2.4,rise:2.0)
            box(2.15,0,0,0.7,2.4,2.0,Map3DPalette.concrete)
            for z: Float in [-1.2,1.2] { box(2.1,2,z,0.7,0.08,0.9,steel) }
        case .floatingPontoon:
            for z: Float in [-0.8,0.8] { box(0,0,z,3.8,0.65,0.38,Self.ink) }
            for x: Float in [-1.5,1.5] { box(x,0.32,0,0.14,2.5,0.12,steel) }
            box(0,0.44,0,4.2,2.6,0.08,wood)
            for x: Float in [-1.8,1.8] { for z: Float in [-1.1,1.1] { cylinder(x,0.52,z,radius:0.06,height:0.2,color:steel,sides:8) } }
        default: break
        }
    }
}
