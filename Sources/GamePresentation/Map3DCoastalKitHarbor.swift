import Foundation

extension StationKitBuilder {
    mutating func coastalHarbor(_ part: Map3DCoastalKit.Part) {
        let wood=Self.coastalWood,steel=Self.steel,white=Self.white,blue=Self.coastalBlue
        switch part {
        case .rowingSkiff:
            coastalHull(length:3.2,width:1.25,height:0.55,color:Self.coastalGreen)
            // A pair of oars rests across and overlaps both gunwales.
            for x: Float in [-0.7,0.7] {
                civicTube(Map3DPoint(x,0.61,-0.95),Map3DPoint(x,0.61,0.95),radius:0.025,color:wood,sides:8)
                box(x,0.575,0.93,0.15,0.36,0.07,wood)
            }
        case .motorDinghy:
            coastalHull(length:3.8,width:1.7,height:0.7,color:blue)
            box(-0.75,0.14,0,0.55,0.75,0.46,white)
            box(-0.70,0.60,0,0.65,0.85,0.06,white)
            // Transom bracket, motor, shaft and propeller overlap physically.
            box(-1.93,0.52,0,0.22,0.35,0.17,steel)
            box(-2.05,0.60,0,0.38,0.48,0.43,Self.ink)
            box(-2.05,0.10,0,0.10,0.13,0.55,steel)
            civicTube(Map3DPoint(-2.18,0.15,0),Map3DPoint(-1.98,0.15,0),radius:0.07,color:steel,sides:8)
            box(-2.18,0.03,0,0.05,0.10,0.24,steel)
        case .boatTrailer:
            for z: Float in [-0.62,0.62] {
                beam(Map3DPoint(-1.6,0.35,z),Map3DPoint(1.2,0.35,z),0.10,steel)
                beam(Map3DPoint(1.2,0.35,z),Map3DPoint(2.1,0.35,0),0.10,steel)
            }
            beam(Map3DPoint(1.9,0.35,0),Map3DPoint(2.5,0.35,0),0.10,steel)
            box(2.47,0.29,0,0.23,0.18,0.12,white)
            civicTube(Map3DPoint(-0.6,0.28,-0.90),Map3DPoint(-0.6,0.28,0.90),radius:0.06,color:steel,sides:8)
            for z: Float in [-0.83,0.83] {
                civicTube(Map3DPoint(-0.6,0.28,z-0.10),Map3DPoint(-0.6,0.28,z+0.10),radius:0.28,color:Self.ink,sides:12)
                box(-0.6,0.58,z,0.75,0.30,0.07,blue)
            }
            for x: Float in [-1,0.7] {
                box(x,0.35,0,0.12,1.3,0.12,steel)
                for z: Float in [-0.3,0.3] { beam(Map3DPoint(x,0.4,z*1.6),Map3DPoint(x,0.57,z),0.10,wood) }
                box(x,0.55,0,0.20,0.65,0.07,Self.ink)
            }
            box(1.7,0,0,0.13,0.13,0.4,steel);box(1.7,0,0,0.40,0.40,0.06,steel)
        case .mooringBollard:
            box(0,0,0,0.9,0.8,0.12,Map3DPalette.granite)
            cylinder(0,0.12,0,radius:0.18,height:0.55,color:steel,sides:10)
            civicTube(Map3DPoint(0,0.53,-0.42),Map3DPoint(0,0.53,0.42),radius:0.11,color:steel,sides:10)
            for x: Float in [-0.3,0.3] { for z: Float in [-0.25,0.25] { cylinder(x,0.12,z,radius:0.035,height:0.035,color:white,sides:6) } }
        case .lifeRingStand:
            box(0,0,0,0.7,0.65,0.08,Map3DPalette.granite)
            box(0,0.08,0,0.08,0.08,1.6,steel)
            box(0,1.43,0,0.65,0.08,0.08,steel)
            coastalRing(Map3DPoint(0,1.05,0.10),radius:0.36,tube:0.075,color:Map3DPalette.signs[0],upright:true)
            // Hook reaches the ring's top, not a ring floating before the post.
            civicTube(Map3DPoint(0,1.45,0),Map3DPoint(0,1.45,0.16),radius:0.04,color:steel,sides:8)
            box(0,0.20,0.06,0.35,0.15,0.4,white)
        case .netDryingRack:
            for z: Float in [-1.2,1.2] { box(0,0,z,0.9,0.45,0.08,steel);box(0,0.08,z,0.1,0.1,2.1,steel) }
            box(0,2.1,0,0.12,2.65,0.1,steel)
            // Solid low-poly cords replace the source's texture/alpha cards.
            for i in 0..<9 { let z=Float(i)*0.28-1.12
                civicTube(Map3DPoint(0,0.55,z),Map3DPoint(0,2.13,z),radius:0.012,color:Self.coastalGreen,sides:6)
            }
            for i in 0..<7 { let y=Float(i)*0.25+0.58
                civicTube(Map3DPoint(0,y,-1.15),Map3DPoint(0,y,1.15),radius:0.012,color:Self.coastalGreen,sides:6)
            }
        case .fishSortingTable:
            civicLegs(0,0,0,length:1.65,width:0.65,height:0.84,color:steel)
            box(0,0.84,0,1.9,0.9,0.06,white)
            for z: Float in [-0.44,0.44] { box(0,0.9,z,1.9,0.04,0.08,steel) }
            box(-0.93,0.9,0,0.04,0.9,0.08,steel)
            box(0,0.27,0,1.7,0.7,0.05,steel)
            // A drain pipe joins the tabletop and the rear leg.
            civicTube(Map3DPoint(-0.8,0.88,0.30),Map3DPoint(-0.8,0.2,0.30),radius:0.04,color:steel,sides:8)
        case .insulatedFishCrate:
            box(0,0,0,0.85,0.55,0.07,white)
            for sign: Float in [-1,1] {
                box(sign*0.395,0.07,0,0.06,0.55,0.33,white)
                box(0,0.07,sign*0.245,0.75,0.06,0.33,white)
            }
            // Open cavity, a lid hinged vertically to the actual rear rim.
            box(-0.40,0.38,0,0.065,0.55,0.52,white)
            for z: Float in [-0.2,0.2] { box(-0.405,0.36,z,0.09,0.08,0.08,steel) }
            for z: Float in [-0.295,0.295] { box(0,0.23,z,0.23,0.07,0.07,blue) }
        default: break
        }
    }
}
