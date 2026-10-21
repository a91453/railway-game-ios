import Foundation

extension StationKitBuilder {
    mutating func residentialBoundary(_ part: Map3DResidentialKit.Part) {
        let stone=Map3DPalette.concreteWalls[0],tile=Map3DPalette.playerRoof,ink=Self.ink,steel=Self.steel
        switch part {
        case .brickWall:
            box(0,0,0,0.32,4,1.35,stone)
            for z: Float in [-1.9,1.9] { box(0,0,z,0.55,0.55,1.62,Map3DPalette.counters[1]);box(0,1.62,z,0.64,0.64,0.12,tile) }
            box(0,1.35,0,0.42,3.65,0.16,tile)
            for z in stride(from:Float(-1.4),through:1.4,by:0.7) { box(0.18,0.22,z,0.03,0.44,0.13,Map3DPalette.templeRoof) }
        case .tileWall:
            box(0,0,0,0.28,4,1.55,stone)
            box(0.15,0.18,0,0.03,3.8,0.84,tile);box(0.15,1.05,0,0.03,3.8,0.05,ink)
            for z: Float in [-1.9,1.9] { box(0,0,z,0.46,0.46,1.65,stone) }
            box(0,1.55,0,0.40,4.0,0.14,Map3DPalette.roof)
        case .ironGate:
            for z: Float in [-1.65,1.65] { box(0,0,z,0.28,0.28,2.25,stone);box(0,2.25,z,0.34,0.34,0.11,tile) }
            for y: Float in [0.35,1.88] { box(0,y,0,0.09,3.05,0.10,steel) }
            for z in stride(from:Float(-1.35),through:1.35,by:0.34) { box(0,0.34,z,0.075,0.075,1.68,steel) }
            box(0.07,1.03,0,0.045,0.2,0.12,Map3DPalette.platformEdge)
        case .slidingGate:
            for z: Float in [-2.25,2.25] { box(0,0,z,0.36,0.36,2.45,stone) }
            for y: Float in [0.22,2.08] { box(0,y,0,0.09,4.30,0.09,steel) }
            for z in stride(from:Float(-1.9),through:1.9,by:0.24) { box(0,0.22,z,0.045,0.06,1.86,ink) }
            box(0,0,0,0.25,4.6,0.08,Map3DPalette.concrete)
            for z: Float in [-1.65,1.65] { cylinder(0,0.08,z,radius:0.14,height:0.10,color:steel,sides:10) }
        case .porchCanopy:
            box(0.2,0,0,3.8,4.5,0.12,stone)
            for z: Float in [-2.05,2.05] { box(1.7,0.12,z,0.17,0.17,2.85,steel) }
            box(0.2,2.97,0,3.8,4.5,0.19,Map3DPalette.canopy)
            for z: Float in [-2.05,2.05] { beam(Map3DPoint(1.7,2.80,z),Map3DPoint(-1.5,2.80,z),0.12,steel) }
            box(-1.55,0.12,0,0.12,4.2,2.85,stone) // solid backing panel for the wall-side entrance
            residentialDoor(-1.47,0.12,0,width:1.2)
        case .carport:
            for x: Float in [-2.7,2.7] { for z: Float in [-2.2,2.2] { box(x,0,z,0.16,0.16,2.75,steel) } }
            box(0,2.75,0,5.9,4.9,0.20,Map3DPalette.canopy)
            for z: Float in [-2.2,2.2] { beam(Map3DPoint(-2.7,2.58,z),Map3DPoint(2.7,2.58,z),0.12,steel) }
            for x: Float in [-2.7,2.7] { box(x,0,-2.2,0.4,0.4,0.10,stone);box(x,0,2.2,0.4,0.4,0.10,stone) }
        case .balconyModule:
            // x=0 is the supporting wall. The slab and diagonal brackets actually meet it.
            box(0.05,0,0,0.10,3.6,2.65,stone)
            box(0.75,0,0,1.50,3.6,0.18,tile)
            for z: Float in [-1.65,1.65] {
                beam(Map3DPoint(0.09,0.42,z),Map3DPoint(1.43,0.10,z),0.09,steel)
                box(1.43,0.18,z,0.08,0.08,0.92,steel)
            }
            for z in stride(from:Float(-1.3),through:1.3,by:0.43) { box(1.43,0.18,z,0.05,0.05,0.92,steel) }
            box(1.43,1.10,0,0.10,3.5,0.10,steel)
            residentialWindow(0.12,1.13,0,width:1.35,height:1.2)
        case .drainageChannel:
            box(0,0,0,1.1,5.2,0.12,stone)
            box(0,0.12,0,0.85,5.0,0.05,ink)
            for z in stride(from:Float(-2.4),through:2.4,by:0.28) { box(0,0.17,z,0.88,0.06,0.07,steel) }
            for z: Float in [-2.55,2.55] { box(0,0.12,z,1.1,0.12,0.10,tile) }
        default: break
        }
    }

    mutating func residentialYard(_ part: Map3DResidentialKit.Part) {
        let stone=Map3DPalette.concreteWalls[0],green=Map3DProp.greens[1],steel=Self.steel,wood=Map3DPalette.counters[1]
        switch part {
        case .waterTank:
            for x: Float in [-0.85,0.85] { for z: Float in [-0.85,0.85] { box(x,0,z,0.12,0.12,1.1,steel) } }
            box(0,1.10,0,2.1,2.1,0.18,steel)
            cylinder(0,1.28,0,radius:0.95,height:1.65,color:Map3DPalette.canopy,sides:12)
            cylinder(0,2.93,0,radius:0.97,height:0.12,color:Map3DPalette.playerRim,sides:12)
            box(0,3.05,0,0.42,0.42,0.12,steel)
            for y: Float in [1.40,2.45] { box(0,y,-1.02,0.10,0.10,0.22,steel) }
        case .roofSolar:
            for z: Float in [-1.3,1.3] {
                box(-1.1,0,z,0.16,0.16,0.42,steel);box(1.1,0,z,0.16,0.16,0.95,steel)
                beam(Map3DPoint(-1.1,0.40,z),Map3DPoint(1.1,0.93,z),0.11,steel)
            }
            for z: Float in [-0.65,0.65] { beam(Map3DPoint(-1.1,0.39,z),Map3DPoint(1.1,0.92,z),0.09,steel) }
            let corners=[Map3DPoint(-1.2,0.46,-1.45),Map3DPoint(1.2,1.02,-1.45),Map3DPoint(1.2,1.02,1.45),Map3DPoint(-1.2,0.46,1.45)]
            face(corners,inside:Map3DPoint(0,0.65,0),color:Map3DPalette.playerRim)
            for z: Float in [-1.45,0,1.45] { beam(Map3DPoint(-1.2,0.47,z),Map3DPoint(1.2,1.03,z),0.045,Map3DPalette.platformEdge) }
        case .planter:
            box(0,0,0,1.1,4.5,0.55,stone);box(0,0.55,0,0.88,4.28,0.08,Map3DPalette.trunk)
            for z in stride(from:Float(-1.7),through:1.7,by:0.85) {
                cylinder(0,0.63,z,radius:0.16,height:0.45,color:green,sides:6)
                for side: Float in [-1,1] { beam(Map3DPoint(0,0.80,z),Map3DPoint(side*0.29,1.04,z+0.10),0.07,green) }
            }
        case .fruitTree:
            box(0,0,0,2.0,2.0,0.12,Map3DPalette.park)
            cylinder(0,0.12,0,radius:0.16,height:2.35,color:Map3DPalette.trunk,sides:8)
            for (x,z,r) in [(-0.6 as Float,0 as Float,0.85 as Float),(0.55,0.3,0.95),(0.05,-0.65,0.8)] {
                cylinder(x,2.0,z,radius:r,height:1.25,color:green,sides:8)
                for dz: Float in [-0.4,0.4] { cylinder(x+0.15,2.2,z+dz,radius:0.12,height:0.12,color:Map3DPalette.templeRidge,sides:6) }
            }
        case .bikeShed:
            box(0,0,0,5.8,5.3,0.10,stone)
            for x: Float in [-2.45,2.45] { for z: Float in [-2.25,2.25] { box(x,0.10,z,0.13,0.13,2.35,steel) } }
            box(0,2.45,0,5.5,5.0,0.17,Map3DPalette.canopy)
            for z: Float in [-2.25,2.25] { beam(Map3DPoint(-2.45,2.28,z),Map3DPoint(2.45,2.28,z),0.12,steel) }
            for z: Float in [-1.5,0,1.5] { box(-1.5,0.10,z,0.12,0.72,0.75,steel) }
        case .clothesline:
            for z: Float in [-2.3,2.3] { box(0,0,z,0.20,0.20,2.5,steel);box(0,0,z,0.45,0.45,0.12,stone) }
            for x: Float in [-0.4,0,0.4] { beam(Map3DPoint(x,2.42,-2.3),Map3DPoint(x,2.42,2.3),0.035,steel) }
            for z: Float in [-1.0,0.5,1.7] { box(0,1.25,z,0.85,0.035,0.95,z<0 ? Self.white : Map3DPalette.canopy) }
        case .utilityPole:
            box(0,0,0,0.65,0.65,0.15,stone)
            cylinder(0,0.15,0,radius:0.17,height:7.2,color:wood,sides:8)
            for y: Float in [5.1,6.6] {
                box(0,y,0,0.15,3.4,0.16,steel)
                for z: Float in [-1.45,0,1.45] { cylinder(0,y+0.16,z,radius:0.12,height:0.22,color:stone,sides:8) }
            }
            box(0.26,2.0,0,0.12,0.65,0.82,stone)
        case .cornerKiosk:
            box(0,0,0,4.8,4.8,0.12,stone)
            box(-0.2,0.12,0,3.8,3.9,2.65,Self.white)
            residentialDoor(1.76,0.12,-1.1,width:0.92)
            for z: Float in [-0.05,1.05] { residentialWindow(1.76,0.95,z,width:0.78,height:1.10) }
            box(0,2.77,0,4.7,4.7,0.20,Map3DPalette.canopy)
            box(1.98,2.2,0,0.07,3.5,0.43,green) // blank sign, no brand
            for z: Float in [-2.05,2.05] { box(2.17,0.12,z,0.13,0.13,2.65,steel) }
        default: break
        }
    }
}
